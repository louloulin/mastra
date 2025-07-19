const std = @import("std");
const Logger = @import("../utils/logger.zig").Logger;
const Agent = @import("../agent/agent.zig").Agent;

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
    logger: *Logger,

    pub fn init(allocator: std.mem.Allocator, config: WorkflowConfig, logger: *Logger) !*Workflow {
        const workflow = try allocator.create(Workflow);
        const steps = std.StringHashMap(WorkflowStep).init(allocator);

        workflow.* = Workflow{
            .allocator = allocator,
            .config = config,
            .steps = steps,
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

    pub fn addStep(self: *Workflow, step_config: StepConfig, executor: *const fn (std.mem.Allocator, std.json.Value) anyerror!std.json.Value) !void {
        const step = WorkflowStep{
            .config = step_config,
            .execute_fn = executor,
        };
        try self.steps.put(step_config.id, step);
    }
};
