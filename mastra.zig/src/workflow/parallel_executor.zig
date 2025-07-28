const std = @import("std");
const Logger = @import("../utils/logger.zig").Logger;

/// Step execution task for parallel processing
pub const StepTask = struct {
    step_id: []const u8,
    execute_fn: *const fn (std.mem.Allocator, std.json.Value) anyerror!std.json.Value,
    input: std.json.Value,
    result_ptr: *StepResult,
    allocator: std.mem.Allocator,
    started_at: i64,

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        step_id: []const u8,
        execute_fn: *const fn (std.mem.Allocator, std.json.Value) anyerror!std.json.Value,
        input: std.json.Value,
        result_ptr: *StepResult,
    ) Self {
        return Self{
            .step_id = step_id,
            .execute_fn = execute_fn,
            .input = input,
            .result_ptr = result_ptr,
            .allocator = allocator,
            .started_at = std.time.timestamp(),
        };
    }

    pub fn execute(self: *Self) void {
        const output = self.execute_fn(self.allocator, self.input) catch |err| {
            self.result_ptr.* = StepResult{
                .step_id = self.step_id,
                .status = .failed,
                .output = null,
                .error_message = @errorName(err),
                .execution_time_ms = @intCast(std.time.timestamp() - self.started_at),
                .started_at = self.started_at,
                .completed_at = std.time.timestamp(),
            };
            return;
        };

        self.result_ptr.* = StepResult{
            .step_id = self.step_id,
            .status = .completed,
            .output = output,
            .error_message = null,
            .execution_time_ms = @intCast(std.time.timestamp() - self.started_at),
            .started_at = self.started_at,
            .completed_at = std.time.timestamp(),
        };
    }
};

/// Thread pool configuration
pub const ThreadPoolConfig = struct {
    max_threads: usize = 4,
    queue_size: usize = 100,
    thread_stack_size: usize = 1024 * 1024, // 1MB
};

/// Simple thread pool for parallel step execution
pub const ThreadPool = struct {
    allocator: std.mem.Allocator,
    config: ThreadPoolConfig,
    threads: []std.Thread,
    task_queue: std.fifo.LinearFifo(*StepTask, .Dynamic),
    mutex: std.Thread.Mutex,
    condition: std.Thread.Condition,
    running: std.atomic.Value(bool),
    active_tasks: std.atomic.Value(usize),
    logger: *Logger,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: ThreadPoolConfig, logger: *Logger) !*Self {
        const pool = try allocator.create(Self);

        var task_queue = std.fifo.LinearFifo(*StepTask, .Dynamic).init(allocator);
        try task_queue.ensureTotalCapacity(config.queue_size);

        pool.* = Self{
            .allocator = allocator,
            .config = config,
            .threads = try allocator.alloc(std.Thread, config.max_threads),
            .task_queue = task_queue,
            .mutex = std.Thread.Mutex{},
            .condition = std.Thread.Condition{},
            .running = std.atomic.Value(bool).init(true),
            .active_tasks = std.atomic.Value(usize).init(0),
            .logger = logger,
        };

        // Start worker threads
        for (pool.threads, 0..) |*thread, i| {
            thread.* = try std.Thread.spawn(.{ .stack_size = config.thread_stack_size }, workerThread, .{ pool, i });
        }

        logger.info("ThreadPool initialized with {} threads", .{config.max_threads});
        return pool;
    }

    pub fn deinit(self: *Self) void {
        // Signal shutdown
        self.running.store(false, .release);
        self.condition.broadcast();

        // Wait for all threads to finish
        for (self.threads) |*thread| {
            thread.join();
        }

        // Clean up remaining tasks
        self.mutex.lock();
        defer self.mutex.unlock();

        while (self.task_queue.readItem()) |task| {
            self.allocator.destroy(task);
        }

        self.task_queue.deinit();
        self.allocator.free(self.threads);
        self.allocator.destroy(self);
    }

    /// Submit a task for execution
    pub fn submitTask(self: *Self, task: *StepTask) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.task_queue.writableLength() == 0) {
            return error.QueueFull;
        }

        try self.task_queue.writeItem(task);
        self.logger.info("Task submitted to queue, queue size: {}", .{self.task_queue.readableLength()});
        self.condition.signal();
    }

    /// Submit multiple tasks as a batch
    pub fn submitBatch(self: *Self, tasks: []*StepTask) !void {
        for (tasks) |task| {
            try self.submitTask(task);
        }
    }

    /// Wait for all active tasks to complete
    pub fn waitAll(self: *Self) void {
        while (true) {
            self.mutex.lock();
            defer self.mutex.unlock();

            const queue_empty = self.task_queue.readableLength() == 0;
            const no_active_tasks = self.active_tasks.load(.acquire) == 0;

            if (queue_empty and no_active_tasks) {
                // Double-check after a small delay to avoid race conditions
                self.mutex.unlock();
                std.time.sleep(5 * std.time.ns_per_ms); // 5ms
                self.mutex.lock();

                const still_queue_empty = self.task_queue.readableLength() == 0;
                const still_no_active_tasks = self.active_tasks.load(.acquire) == 0;

                if (still_queue_empty and still_no_active_tasks) {
                    break;
                }
            }

            // Wait for notification from worker threads
            self.condition.wait(&self.mutex);
        }
    }

    /// Get current queue size
    pub fn getQueueSize(self: *Self) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.task_queue.readableLength();
    }

    /// Get number of active tasks
    pub fn getActiveTasks(self: *Self) usize {
        return self.active_tasks.load(.acquire);
    }

    /// Worker thread function
    fn workerThread(self: *Self, worker_id: usize) void {
        self.logger.info("Worker thread {} started", .{worker_id});

        while (self.running.load(.acquire)) {
            var task: ?*StepTask = null;

            // Get task from queue
            {
                self.mutex.lock();
                defer self.mutex.unlock();

                while (self.task_queue.readableLength() == 0 and self.running.load(.acquire)) {
                    self.condition.wait(&self.mutex);
                }

                if (!self.running.load(.acquire)) break;

                task = self.task_queue.readItem();
            }

            if (task) |t| {
                // Increment active tasks count
                _ = self.active_tasks.fetchAdd(1, .acq_rel);

                self.logger.info("Worker {} executing step: {s}", .{ worker_id, t.step_id });

                // Execute the task
                t.execute();

                // Clean up task memory
                self.allocator.destroy(t);

                // Decrement active tasks count AFTER cleanup
                _ = self.active_tasks.fetchSub(1, .acq_rel);

                // Notify waiting threads that a task completed
                {
                    self.mutex.lock();
                    defer self.mutex.unlock();
                    self.condition.broadcast();
                }
            }
        }

        self.logger.info("Worker thread {} stopped", .{worker_id});
    }
};

/// Import step result from workflow module
const StepResult = @import("workflow.zig").StepResult;
const StepStatus = @import("workflow.zig").StepStatus;

/// Parallel execution engine for workflows
pub const ParallelExecutor = struct {
    allocator: std.mem.Allocator,
    thread_pool: *ThreadPool,
    logger: *Logger,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: ThreadPoolConfig, logger: *Logger) !*Self {
        const executor = try allocator.create(Self);

        executor.* = Self{
            .allocator = allocator,
            .thread_pool = try ThreadPool.init(allocator, config, logger),
            .logger = logger,
        };

        return executor;
    }

    pub fn deinit(self: *Self) void {
        self.thread_pool.deinit();
        self.allocator.destroy(self);
    }

    /// Execute multiple steps in parallel
    pub fn executeParallel(
        self: *Self,
        step_configs: []const StepConfig,
        execute_fns: []const *const fn (std.mem.Allocator, std.json.Value) anyerror!std.json.Value,
        inputs: []const std.json.Value,
    ) ![]StepResult {
        if (step_configs.len != execute_fns.len or step_configs.len != inputs.len) {
            return error.MismatchedArrayLengths;
        }

        self.logger.info("Executing {} steps in parallel", .{step_configs.len});

        // Allocate results array
        const results = try self.allocator.alloc(StepResult, step_configs.len);
        var tasks = try self.allocator.alloc(*StepTask, step_configs.len);
        defer self.allocator.free(tasks);

        // Create tasks
        for (step_configs, execute_fns, inputs, results, 0..) |config, execute_fn, input, *result, i| {
            const task = try self.allocator.create(StepTask);
            task.* = StepTask.init(self.allocator, config.id, execute_fn, input, result);
            tasks[i] = task;
        }

        // Submit all tasks
        self.logger.info("Submitting {} tasks to thread pool", .{tasks.len});
        try self.thread_pool.submitBatch(tasks);
        self.logger.info("All tasks submitted, waiting for completion", .{});

        // Wait for completion
        self.thread_pool.waitAll();

        // Additional safety: ensure all results are populated
        for (results, 0..) |result, i| {
            if (result.status == .pending) {
                self.logger.info("Warning: Task {} still pending after waitAll()", .{i});
            }
        }

        self.logger.info("All tasks completed", .{});

        self.logger.info("Parallel execution completed", .{});

        // Note: results array ownership is transferred to caller
        // Caller is responsible for freeing the results array
        return results;
    }

    /// Execute steps with dependencies (topological sort + parallel execution)
    pub fn executeWithDependencies(
        self: *Self,
        step_configs: []const StepConfig,
        execute_fns: []const *const fn (std.mem.Allocator, std.json.Value) anyerror!std.json.Value,
        inputs: []const std.json.Value,
    ) ![]StepResult {
        // TODO: Implement topological sorting and dependency-aware parallel execution
        // For now, fall back to simple parallel execution
        return self.executeParallel(step_configs, execute_fns, inputs);
    }

    /// Get execution statistics
    pub fn getStats(self: *Self) struct { queue_size: usize, active_tasks: usize } {
        return .{
            .queue_size = self.thread_pool.getQueueSize(),
            .active_tasks = self.thread_pool.getActiveTasks(),
        };
    }
};

// Import step config from workflow module
const StepConfig = @import("workflow.zig").StepConfig;

// Tests will be in separate test files to avoid import path issues
