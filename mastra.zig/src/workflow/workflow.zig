const std = @import("std");
const Logger = @import("../utils/logger.zig").Logger;
const Agent = @import("../agent/agent.zig").Agent;

// Import enhanced execution components
pub const StepFlowEntry = @import("execution_engine.zig").StepFlowEntry;
pub const ThreadPoolConfig = @import("parallel_executor.zig").ThreadPoolConfig;

pub const StepStatus = enum {
    pending,
    running,
    completed,
    failed,
    skipped,
};

pub const StepConfig = struct {
    id: []const u8,
    name: []const u8,
    description: ?[]const u8 = null,
    input_schema: ?std.json.Value = null,
    output_schema: ?std.json.Value = null,
    retry_count: u32 = 0,
    timeout_ms: ?u32 = null,
    depends_on: ?[]const []const u8 = null,
    condition: ?[]const u8 = null,
};

pub const StepResult = struct {
    step_id: []const u8,
    status: StepStatus,
    output: ?std.json.Value = null,
    error_message: ?[]const u8 = null,
    execution_time_ms: u64,
    started_at: i64,
    completed_at: i64,

    pub fn deinit(self: *StepResult) void {
        // JSON Value doesn't need explicit deinitialization in newer Zig versions
        _ = self;
    }
};

pub const WorkflowStep = struct {
    config: StepConfig,
    execute_fn: *const fn (std.mem.Allocator, std.json.Value) anyerror!std.json.Value,
    status: StepStatus = .pending,
    result: ?StepResult = null,

    pub fn execute(self: *WorkflowStep, allocator: std.mem.Allocator, input: std.json.Value) !StepResult {
        self.status = .running;

        const started_at = std.time.timestamp();
        var output: ?std.json.Value = null;
        var error_message: ?[]const u8 = null;
        var final_status = StepStatus.completed;

        const result = self.execute_fn(allocator, input) catch |err| {
            final_status = .failed;
            error_message = @errorName(err);
            return StepResult{
                .step_id = self.config.id,
                .status = final_status,
                .output = null,
                .error_message = error_message,
                .execution_time_ms = 0,
                .started_at = started_at,
                .completed_at = std.time.timestamp(),
            };
        };

        output = result;
        const completed_at = std.time.timestamp();
        const execution_time_ms: u64 = @intCast((completed_at - started_at) * 1000);

        self.status = final_status;
        self.result = StepResult{
            .step_id = self.config.id,
            .status = final_status,
            .output = output,
            .error_message = null,
            .execution_time_ms = execution_time_ms,
            .started_at = started_at,
            .completed_at = completed_at,
        };

        return self.result.?;
    }
};

pub const WorkflowConfig = struct {
    id: []const u8,
    name: []const u8,
    description: ?[]const u8 = null,
    version: []const u8 = "1.0.0",
    steps: []const StepConfig,
    triggers: ?std.json.Value = null,
    settings: ?std.json.Value = null,

    // Enhanced execution configuration
    enable_parallel_execution: bool = false,
    thread_pool_config: ThreadPoolConfig = ThreadPoolConfig{},
    max_concurrent_steps: ?usize = null,
    execution_timeout_ms: ?u64 = null,
};

pub const WorkflowRun = struct {
    id: []const u8,
    workflow_id: []const u8,
    status: StepStatus,
    steps: std.StringHashMap(StepResult),
    started_at: i64,
    completed_at: ?i64 = null,
    results: std.StringHashMap(std.json.Value),

    pub fn init(allocator: std.mem.Allocator, workflow_id: []const u8) !*WorkflowRun {
        const run = try allocator.create(WorkflowRun);
        const steps = std.StringHashMap(StepResult).init(allocator);
        const results = std.StringHashMap(std.json.Value).init(allocator);

        const run_id = try std.fmt.allocPrint(allocator, "{s}_{d}", .{ workflow_id, std.time.timestamp() });

        run.* = WorkflowRun{
            .id = run_id,
            .workflow_id = workflow_id,
            .status = .pending,
            .steps = steps,
            .started_at = std.time.timestamp(),
            .results = results,
        };

        return run;
    }

    pub fn deinit(self: *WorkflowRun) void {
        var step_iter = self.steps.iterator();
        while (step_iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.steps.deinit();

        var result_iter = self.results.iterator();
        while (result_iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.results.deinit();
    }

    pub fn getStepResult(self: *WorkflowRun, step_id: []const u8) ?StepResult {
        return self.steps.get(step_id);
    }

    pub fn getResult(self: *WorkflowRun, step_id: []const u8) ?std.json.Value {
        return self.results.get(step_id);
    }

    pub fn setStepResult(self: *WorkflowRun, step_id: []const u8, result: StepResult) !void {
        try self.steps.put(step_id, result);
        if (result.output) |output| {
            try self.results.put(step_id, output);
        }
    }
};

pub const Workflow = struct {
    allocator: std.mem.Allocator,
    config: WorkflowConfig,
    steps: std.StringHashMap(WorkflowStep),
    execution_engine: ?*ExecutionEngine,
    logger: *Logger,

    pub fn init(allocator: std.mem.Allocator, config: WorkflowConfig, logger: *Logger) !*Workflow {
        const workflow = try allocator.create(Workflow);
        const steps = std.StringHashMap(WorkflowStep).init(allocator);

        // Initialize execution engine if parallel execution is enabled
        var execution_engine: ?*ExecutionEngine = null;
        if (config.enable_parallel_execution) {
            execution_engine = try ExecutionEngine.init(allocator, config.thread_pool_config, logger);
        }

        workflow.* = Workflow{
            .allocator = allocator,
            .config = config,
            .steps = steps,
            .execution_engine = execution_engine,
            .logger = logger,
        };

        // Initialize steps
        for (config.steps) |step_config| {
            const step = WorkflowStep{
                .config = step_config,
                .execute_fn = undefined, // Will be set by caller
            };
            try workflow.steps.put(step_config.id, step);
        }

        return workflow;
    }

    pub fn deinit(self: *Workflow) void {
        var iter = self.steps.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.result) |*result| {
                result.deinit();
            }
        }
        self.steps.deinit();

        // Clean up execution engine
        if (self.execution_engine) |engine| {
            engine.deinit();
        }

        self.allocator.destroy(self);
    }

    pub fn setStepExecutor(self: *Workflow, step_id: []const u8, executor: *const fn (std.mem.Allocator, std.json.Value) anyerror!std.json.Value) bool {
        if (self.steps.getPtr(step_id)) |step| {
            step.execute_fn = executor;
            return true;
        }
        return false;
    }

    pub fn execute(self: *Workflow, input: std.json.Value) !*WorkflowRun {
        var run = try WorkflowRun.init(self.allocator, self.config.id);
        errdefer run.deinit();

        run.status = .running;
        self.logger.info("Starting workflow: {s}", .{self.config.name});

        // Execute steps in dependency order
        for (self.config.steps) |step_config| {
            if (self.steps.getPtr(step_config.id)) |step| {
                self.logger.info("Executing step: {s}", .{step_config.name});

                // Check dependencies
                if (step_config.depends_on) |deps| {
                    for (deps) |dep| {
                        const dep_result = run.getStepResult(dep);
                        if (dep_result == null or dep_result.?.status != .completed) {
                            self.logger.warn("Skipping step {s} due to unmet dependency: {s}", .{ step_config.name, dep });
                            const step_result = StepResult{
                                .step_id = step_config.id,
                                .status = .skipped,
                                .output = null,
                                .error_message = null,
                                .execution_time_ms = 0,
                                .started_at = std.time.timestamp(),
                                .completed_at = std.time.timestamp(),
                            };
                            try run.setStepResult(step_config.id, step_result);
                            continue;
                        }
                    }
                }

                // Execute step
                const result = try step.execute(self.allocator, input);
                try run.setStepResult(step_config.id, result);

                if (result.status == .failed) {
                    run.status = .failed;
                    self.logger.err("Step {s} failed: {s}", .{ step_config.name, result.error_message orelse "Unknown error" });
                    break;
                }
            }
        }

        if (run.status != .failed) {
            run.status = .completed;
            run.completed_at = std.time.timestamp();
        }

        self.logger.info("Workflow {s} completed with status: {s}", .{ self.config.name, @tagName(run.status) });
        return run;
    }

    pub fn getStep(self: *Workflow, step_id: []const u8) ?*const WorkflowStep {
        return self.steps.getPtr(step_id);
    }

    pub fn getSteps(self: *Workflow) []const StepConfig {
        return self.config.steps;
    }

    /// Execute workflow with parallel execution if enabled
    pub fn executeParallel(self: *Workflow, input: std.json.Value) !*WorkflowRun {
        if (self.execution_engine == null) {
            // Fall back to sequential execution
            return self.execute(input);
        }

        var run = try WorkflowRun.init(self.allocator, self.config.id);
        errdefer run.deinit();

        run.status = .running;
        self.logger.info("Starting parallel workflow: {s}", .{self.config.name});

        // Collect steps that can be executed in parallel (no dependencies)
        var parallel_steps = std.ArrayList(StepConfig).init(self.allocator);
        defer parallel_steps.deinit();

        var parallel_fns = std.ArrayList(*const fn (std.mem.Allocator, std.json.Value) anyerror!std.json.Value).init(self.allocator);
        defer parallel_fns.deinit();

        for (self.config.steps) |step_config| {
            if (step_config.depends_on == null or step_config.depends_on.?.len == 0) {
                if (self.steps.getPtr(step_config.id)) |step| {
                    try parallel_steps.append(step_config);
                    try parallel_fns.append(step.execute_fn);
                }
            }
        }

        if (parallel_steps.items.len > 0) {
            // Create inputs array
            const inputs = try self.allocator.alloc(std.json.Value, parallel_steps.items.len);
            defer self.allocator.free(inputs);

            for (inputs) |*inp| {
                inp.* = input;
            }

            // Execute in parallel
            const results = self.execution_engine.?.parallel_executor.executeParallel(
                parallel_steps.items,
                parallel_fns.items,
                inputs,
            ) catch |err| {
                run.status = .failed;
                self.logger.err("Parallel execution failed: {}", .{err});
                return run;
            };
            defer self.allocator.free(results);

            // Store results
            for (results) |result| {
                try run.setStepResult(result.step_id, result);
                if (result.status == .failed) {
                    run.status = .failed;
                    break;
                }
            }
        }

        if (run.status != .failed) {
            run.status = .completed;
            run.completed_at = std.time.timestamp();
        }

        self.logger.info("Parallel workflow {s} completed with status: {s}", .{ self.config.name, @tagName(run.status) });
        return run;
    }

    /// Execute a step flow entry using the execution engine
    pub fn executeStepFlow(self: *Workflow, flow: StepFlowEntry, input: std.json.Value) ![]StepResult {
        if (self.execution_engine == null) {
            return error.ExecutionEngineNotAvailable;
        }

        return try self.execution_engine.?.executeStepFlow(flow, input);
    }

    /// Check if parallel execution is enabled
    pub fn isParallelExecutionEnabled(self: *Workflow) bool {
        return self.execution_engine != null;
    }

    pub fn addStep(self: *Workflow, step_config: StepConfig, executor: *const fn (std.mem.Allocator, std.json.Value) anyerror!std.json.Value) !void {
        const step = WorkflowStep{
            .config = step_config,
            .execute_fn = executor,
        };
        try self.steps.put(step_config.id, step);
    }
};

// Export parallel execution components
pub const ThreadPool = @import("parallel_executor.zig").ThreadPool;
pub const ParallelExecutor = @import("parallel_executor.zig").ParallelExecutor;
pub const ExecutionEngine = @import("execution_engine.zig").ExecutionEngine;
