const std = @import("std");
const Logger = @import("../utils/logger.zig").Logger;
const ParallelExecutor = @import("parallel_executor.zig").ParallelExecutor;
const ThreadPoolConfig = @import("parallel_executor.zig").ThreadPoolConfig;

// Import from workflow module
const StepConfig = @import("workflow.zig").StepConfig;
const StepResult = @import("workflow.zig").StepResult;
const StepStatus = @import("workflow.zig").StepStatus;

/// Types of step flow entries
pub const StepFlowType = enum {
    step, // Single step execution
    parallel, // Parallel execution of multiple steps
    conditional, // Conditional execution based on conditions
    loop, // Loop execution with condition
    foreach, // Foreach execution over array
    sleep, // Sleep for specified duration
    waitForEvent, // Wait for external event
};

/// Condition function for conditional execution
pub const ConditionFunc = struct {
    func: *const fn (std.json.Value) anyerror!bool,

    const Self = @This();

    pub fn evaluate(self: Self, context: std.json.Value) !bool {
        return try self.func(context);
    }
};

/// Loop configuration
pub const LoopConfig = struct {
    max_iterations: ?usize = null,
    condition: ConditionFunc,
    break_on_error: bool = true,
};

/// Foreach configuration
pub const ForeachConfig = struct {
    array_path: []const u8, // JSON path to array in context
    item_key: []const u8, // Key to store current item in context
    index_key: ?[]const u8 = null, // Optional key to store current index
    max_parallel: ?usize = null, // Max parallel executions (null = sequential)
};

/// Sleep configuration
pub const SleepConfig = struct {
    duration_ms: u64,
};

/// Wait for event configuration
pub const WaitEventConfig = struct {
    event_name: []const u8,
    timeout_ms: ?u64 = null,
    condition: ?ConditionFunc = null,
};

/// Step flow entry representing different execution patterns
pub const StepFlowEntry = struct {
    flow_type: StepFlowType,

    // Single step execution
    step_config: ?StepConfig = null,
    execute_fn: ?*const fn (std.mem.Allocator, std.json.Value) anyerror!std.json.Value = null,

    // Parallel execution
    steps: ?[]const StepConfig = null,
    execute_fns: ?[]const *const fn (std.mem.Allocator, std.json.Value) anyerror!std.json.Value = null,

    // Conditional execution
    conditions: ?[]const ConditionFunc = null,

    // Loop execution
    loop_config: ?LoopConfig = null,

    // Foreach execution
    foreach_config: ?ForeachConfig = null,

    // Sleep execution
    sleep_config: ?SleepConfig = null,

    // Wait for event
    wait_event_config: ?WaitEventConfig = null,

    const Self = @This();

    /// Create a single step flow entry
    pub fn step(step_config: StepConfig, execute_fn: *const fn (std.mem.Allocator, std.json.Value) anyerror!std.json.Value) Self {
        return Self{
            .flow_type = .step,
            .step_config = step_config,
            .execute_fn = execute_fn,
        };
    }

    /// Create a parallel execution flow entry
    pub fn parallel(
        step_configs: []const StepConfig,
        execute_functions: []const *const fn (std.mem.Allocator, std.json.Value) anyerror!std.json.Value,
    ) Self {
        return Self{
            .flow_type = .parallel,
            .steps = step_configs,
            .execute_fns = execute_functions,
        };
    }

    /// Create a conditional execution flow entry
    pub fn conditional(
        step_configs: []const StepConfig,
        execute_functions: []const *const fn (std.mem.Allocator, std.json.Value) anyerror!std.json.Value,
        condition_funcs: []const ConditionFunc,
    ) Self {
        return Self{
            .flow_type = .conditional,
            .steps = step_configs,
            .execute_fns = execute_functions,
            .conditions = condition_funcs,
        };
    }

    /// Create a loop execution flow entry
    pub fn loop(
        step_config: StepConfig,
        execute_fn: *const fn (std.mem.Allocator, std.json.Value) anyerror!std.json.Value,
        config: LoopConfig,
    ) Self {
        return Self{
            .flow_type = .loop,
            .step_config = step_config,
            .execute_fn = execute_fn,
            .loop_config = config,
        };
    }

    /// Create a foreach execution flow entry
    pub fn foreach(
        step_config: StepConfig,
        execute_fn: *const fn (std.mem.Allocator, std.json.Value) anyerror!std.json.Value,
        config: ForeachConfig,
    ) Self {
        return Self{
            .flow_type = .foreach,
            .step_config = step_config,
            .execute_fn = execute_fn,
            .foreach_config = config,
        };
    }

    /// Create a sleep flow entry
    pub fn sleep(duration_ms: u64) Self {
        return Self{
            .flow_type = .sleep,
            .sleep_config = SleepConfig{ .duration_ms = duration_ms },
        };
    }

    /// Create a wait for event flow entry
    pub fn waitForEvent(event_name: []const u8, timeout_ms: ?u64, condition: ?ConditionFunc) Self {
        return Self{
            .flow_type = .waitForEvent,
            .wait_event_config = WaitEventConfig{
                .event_name = event_name,
                .timeout_ms = timeout_ms,
                .condition = condition,
            },
        };
    }
};

/// Execution context for workflow steps
pub const ExecutionContext = struct {
    variables: std.StringHashMap(std.json.Value),
    step_results: std.StringHashMap(StepResult),
    events: std.StringHashMap(std.json.Value),
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .variables = std.StringHashMap(std.json.Value).init(allocator),
            .step_results = std.StringHashMap(StepResult).init(allocator),
            .events = std.StringHashMap(std.json.Value).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.variables.deinit();
        self.step_results.deinit();
        self.events.deinit();
    }

    pub fn setVariable(self: *Self, key: []const u8, value: std.json.Value) !void {
        try self.variables.put(key, value);
    }

    pub fn getVariable(self: *Self, key: []const u8) ?std.json.Value {
        return self.variables.get(key);
    }

    pub fn setStepResult(self: *Self, step_id: []const u8, result: StepResult) !void {
        try self.step_results.put(step_id, result);
    }

    pub fn getStepResult(self: *Self, step_id: []const u8) ?StepResult {
        return self.step_results.get(step_id);
    }

    pub fn setEvent(self: *Self, event_name: []const u8, data: std.json.Value) !void {
        try self.events.put(event_name, data);
    }

    pub fn getEvent(self: *Self, event_name: []const u8) ?std.json.Value {
        return self.events.get(event_name);
    }
};

/// Enhanced execution engine with parallel and advanced flow control
pub const ExecutionEngine = struct {
    allocator: std.mem.Allocator,
    parallel_executor: *ParallelExecutor,
    context: ExecutionContext,
    logger: *Logger,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, thread_pool_config: ThreadPoolConfig, logger: *Logger) !*Self {
        const engine = try allocator.create(Self);

        engine.* = Self{
            .allocator = allocator,
            .parallel_executor = try ParallelExecutor.init(allocator, thread_pool_config, logger),
            .context = ExecutionContext.init(allocator),
            .logger = logger,
        };

        return engine;
    }

    pub fn deinit(self: *Self) void {
        self.parallel_executor.deinit();
        self.context.deinit();
        self.allocator.destroy(self);
    }

    /// Execute a step flow entry
    pub fn executeStepFlow(self: *Self, flow: StepFlowEntry, input: std.json.Value) ![]StepResult {
        return switch (flow.flow_type) {
            .step => try self.executeStep(flow, input),
            .parallel => try self.executeParallel(flow, input),
            .conditional => try self.executeConditional(flow, input),
            .loop => try self.executeLoop(flow, input),
            .foreach => try self.executeForeach(flow, input),
            .sleep => try self.executeSleep(flow, input),
            .waitForEvent => try self.executeWaitForEvent(flow, input),
        };
    }

    /// Execute a single step
    pub fn executeStep(self: *Self, flow: StepFlowEntry, input: std.json.Value) ![]StepResult {
        if (flow.step_config == null or flow.execute_fn == null) {
            return error.InvalidStepFlow;
        }

        const step_config = flow.step_config.?;
        const execute_fn = flow.execute_fn.?;

        self.logger.info("Executing step: {s}", .{step_config.name});

        const started_at = std.time.timestamp();
        const output = execute_fn(self.allocator, input) catch |err| {
            const result = StepResult{
                .step_id = step_config.id,
                .status = .failed,
                .output = null,
                .error_message = @errorName(err),
                .execution_time_ms = @intCast(std.time.timestamp() - started_at),
                .started_at = started_at,
                .completed_at = std.time.timestamp(),
            };

            var results = try self.allocator.alloc(StepResult, 1);
            results[0] = result;
            return results;
        };

        const result = StepResult{
            .step_id = step_config.id,
            .status = .completed,
            .output = output,
            .error_message = null,
            .execution_time_ms = @intCast(std.time.timestamp() - started_at),
            .started_at = started_at,
            .completed_at = std.time.timestamp(),
        };

        try self.context.setStepResult(step_config.id, result);

        var results = try self.allocator.alloc(StepResult, 1);
        results[0] = result;
        return results;
    }

    /// Execute steps in parallel
    fn executeParallel(self: *Self, flow: StepFlowEntry, input: std.json.Value) ![]StepResult {
        if (flow.steps == null or flow.execute_fns == null) {
            return error.InvalidStepFlow;
        }

        const steps = flow.steps.?;
        const execute_fns = flow.execute_fns.?;

        self.logger.info("Executing {} steps in parallel", .{steps.len});

        // Create inputs array (same input for all steps for now)
        const inputs = try self.allocator.alloc(std.json.Value, steps.len);
        defer self.allocator.free(inputs);

        for (inputs) |*inp| {
            inp.* = input;
        }

        const results = try self.parallel_executor.executeParallel(steps, execute_fns, inputs);

        // Store results in context
        for (results) |result| {
            try self.context.setStepResult(result.step_id, result);
        }

        return results;
    }

    /// Execute conditional steps
    fn executeConditional(self: *Self, flow: StepFlowEntry, input: std.json.Value) ![]StepResult {
        if (flow.steps == null or flow.execute_fns == null or flow.conditions == null) {
            return error.InvalidStepFlow;
        }

        const steps = flow.steps.?;
        const execute_fns = flow.execute_fns.?;
        const conditions = flow.conditions.?;

        for (conditions, 0..) |condition, i| {
            if (i >= steps.len or i >= execute_fns.len) break;

            if (try condition.evaluate(input)) {
                const step_flow = StepFlowEntry.step(steps[i], execute_fns[i]);
                return try self.executeStep(step_flow, input);
            }
        }

        // No condition matched, return empty results
        return try self.allocator.alloc(StepResult, 0);
    }

    /// Execute loop
    fn executeLoop(self: *Self, flow: StepFlowEntry, input: std.json.Value) ![]StepResult {
        if (flow.step_config == null or flow.execute_fn == null or flow.loop_config == null) {
            return error.InvalidStepFlow;
        }

        const loop_config = flow.loop_config.?;
        var results = std.ArrayList(StepResult).init(self.allocator);
        defer results.deinit();

        var iteration: usize = 0;
        var current_input = input;

        while (true) {
            // Check max iterations
            if (loop_config.max_iterations) |max| {
                if (iteration >= max) break;
            }

            // Check condition
            if (!try loop_config.condition.evaluate(current_input)) break;

            // Execute step
            const step_flow = StepFlowEntry.step(flow.step_config.?, flow.execute_fn.?);
            const step_results = try self.executeStep(step_flow, current_input);
            defer self.allocator.free(step_results);

            for (step_results) |result| {
                try results.append(result);

                // Use output as input for next iteration if available
                if (result.output) |output| {
                    current_input = output;
                }

                // Break on error if configured
                if (loop_config.break_on_error and result.status == .failed) {
                    return try self.allocator.dupe(StepResult, results.items);
                }
            }

            iteration += 1;
        }

        return try self.allocator.dupe(StepResult, results.items);
    }

    /// Execute foreach (simplified implementation)
    fn executeForeach(self: *Self, flow: StepFlowEntry, input: std.json.Value) ![]StepResult {
        // TODO: Implement proper foreach with JSON path parsing
        _ = self;
        _ = flow;
        _ = input;
        return error.NotImplemented;
    }

    /// Execute sleep
    fn executeSleep(self: *Self, flow: StepFlowEntry, input: std.json.Value) ![]StepResult {
        if (flow.sleep_config == null) {
            return error.InvalidStepFlow;
        }

        const sleep_config = flow.sleep_config.?;
        self.logger.info("Sleeping for {}ms", .{sleep_config.duration_ms});

        std.time.sleep(sleep_config.duration_ms * std.time.ns_per_ms);

        // Return empty result indicating sleep completed
        var results = try self.allocator.alloc(StepResult, 1);
        results[0] = StepResult{
            .step_id = "sleep",
            .status = .completed,
            .output = input, // Pass through input
            .error_message = null,
            .execution_time_ms = sleep_config.duration_ms,
            .started_at = std.time.timestamp(),
            .completed_at = std.time.timestamp(),
        };

        return results;
    }

    /// Execute wait for event (simplified implementation)
    fn executeWaitForEvent(self: *Self, flow: StepFlowEntry, input: std.json.Value) ![]StepResult {
        // TODO: Implement proper event waiting with timeout
        _ = self;
        _ = flow;
        _ = input;
        return error.NotImplemented;
    }
};

// Tests
test "ExecutionEngine initialization" {
    const allocator = std.testing.allocator;
    const logger = try Logger.init(allocator, .{ .level = .info });
    defer logger.deinit();

    const config = ThreadPoolConfig{ .max_threads = 2 };
    var engine = try ExecutionEngine.init(allocator, config, logger);
    defer engine.deinit();

    // Test context operations
    try engine.context.setVariable("test", std.json.Value{ .string = "value" });
    const value = engine.context.getVariable("test");
    try std.testing.expect(value != null);
}
