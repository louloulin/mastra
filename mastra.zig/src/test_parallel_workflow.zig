const std = @import("std");
const testing = std.testing;

// Import workflow components
const ExecutionEngine = @import("workflow/execution_engine.zig").ExecutionEngine;
const StepFlowEntry = @import("workflow/execution_engine.zig").StepFlowEntry;
const StepFlowType = @import("workflow/execution_engine.zig").StepFlowType;
const ConditionFunc = @import("workflow/execution_engine.zig").ConditionFunc;
const LoopConfig = @import("workflow/execution_engine.zig").LoopConfig;
const ParallelExecutor = @import("workflow/parallel_executor.zig").ParallelExecutor;
const ThreadPoolConfig = @import("workflow/parallel_executor.zig").ThreadPoolConfig;
const StepConfig = @import("workflow/workflow.zig").StepConfig;
const StepResult = @import("workflow/workflow.zig").StepResult;
const StepStatus = @import("workflow/workflow.zig").StepStatus;
const Workflow = @import("workflow/workflow.zig").Workflow;
const WorkflowConfig = @import("workflow/workflow.zig").WorkflowConfig;
const Logger = @import("utils/logger.zig").Logger;

// Test step execution functions
fn doubleValue(allocator: std.mem.Allocator, input: std.json.Value) anyerror!std.json.Value {
    _ = allocator;

    if (input == .integer) {
        const doubled = input.integer * 2;
        return std.json.Value{ .integer = doubled };
    }

    return std.json.Value{ .integer = 0 };
}

fn addOne(allocator: std.mem.Allocator, input: std.json.Value) anyerror!std.json.Value {
    _ = allocator;

    if (input == .integer) {
        const incremented = input.integer + 1;
        return std.json.Value{ .integer = incremented };
    }

    return std.json.Value{ .integer = 1 };
}

fn multiplyByThree(allocator: std.mem.Allocator, input: std.json.Value) anyerror!std.json.Value {
    _ = allocator;

    if (input == .integer) {
        const tripled = input.integer * 3;
        return std.json.Value{ .integer = tripled };
    }

    return std.json.Value{ .integer = 0 };
}

fn failingStep(allocator: std.mem.Allocator, input: std.json.Value) anyerror!std.json.Value {
    _ = allocator;
    _ = input;
    return error.TestFailure;
}

test "StepFlowEntry creation" {
    const step_config = StepConfig{
        .id = "test_step",
        .name = "Test Step",
        .description = "A test step",
    };

    // Test single step flow entry
    const step_flow = StepFlowEntry.step(step_config, doubleValue);
    try testing.expectEqual(StepFlowType.step, step_flow.flow_type);
    try testing.expect(step_flow.step_config != null);
    try testing.expect(step_flow.execute_fn != null);

    // Test parallel flow entry
    const step_configs = [_]StepConfig{step_config};
    const execute_fns = [_]*const fn (std.mem.Allocator, std.json.Value) anyerror!std.json.Value{doubleValue};
    const parallel_flow = StepFlowEntry.parallel(&step_configs, &execute_fns);
    try testing.expectEqual(StepFlowType.parallel, parallel_flow.flow_type);
    try testing.expect(parallel_flow.steps != null);
    try testing.expect(parallel_flow.execute_fns != null);

    // Test sleep flow entry
    const sleep_flow = StepFlowEntry.sleep(100);
    try testing.expectEqual(StepFlowType.sleep, sleep_flow.flow_type);
    try testing.expect(sleep_flow.sleep_config != null);
    try testing.expectEqual(@as(u64, 100), sleep_flow.sleep_config.?.duration_ms);
}

test "ConditionFunc evaluation" {
    const condition_func = ConditionFunc{
        .func = struct {
            fn evaluate(input: std.json.Value) anyerror!bool {
                if (input == .integer) {
                    return input.integer > 5;
                }
                return false;
            }
        }.evaluate,
    };

    const input1 = std.json.Value{ .integer = 10 };
    const input2 = std.json.Value{ .integer = 3 };

    try testing.expect(try condition_func.evaluate(input1));
    try testing.expect(!try condition_func.evaluate(input2));
}

test "ExecutionEngine initialization and cleanup" {
    const allocator = testing.allocator;
    const logger = try Logger.init(allocator, .{ .level = .info });
    defer logger.deinit();

    const config = ThreadPoolConfig{ .max_threads = 2 };
    var engine = try ExecutionEngine.init(allocator, config, logger);
    defer engine.deinit();

    // Test context operations
    try engine.context.setVariable("test_var", std.json.Value{ .string = "test_value" });
    const value = engine.context.getVariable("test_var");
    try testing.expect(value != null);
    try testing.expectEqualStrings("test_value", value.?.string);
}

test "ExecutionEngine single step execution" {
    const allocator = testing.allocator;
    const logger = try Logger.init(allocator, .{ .level = .info });
    defer logger.deinit();

    const config = ThreadPoolConfig{ .max_threads = 2 };
    var engine = try ExecutionEngine.init(allocator, config, logger);
    defer engine.deinit();

    const step_config = StepConfig{
        .id = "double_step",
        .name = "Double Step",
        .description = "Doubles the input value",
    };

    const step_flow = StepFlowEntry.step(step_config, doubleValue);
    const input = std.json.Value{ .integer = 5 };

    const results = try engine.executeStepFlow(step_flow, input);
    defer allocator.free(results);

    try testing.expectEqual(@as(usize, 1), results.len);
    try testing.expectEqual(StepStatus.completed, results[0].status);
    try testing.expect(results[0].output != null);
    try testing.expectEqual(@as(i64, 10), results[0].output.?.integer);
}

test "ExecutionEngine parallel execution" {
    const allocator = testing.allocator;
    const logger = try Logger.init(allocator, .{ .level = .info });
    defer logger.deinit();

    const config = ThreadPoolConfig{ .max_threads = 3 };
    var engine = try ExecutionEngine.init(allocator, config, logger);
    defer engine.deinit();

    const step_configs = [_]StepConfig{
        StepConfig{
            .id = "step1",
            .name = "Double Step",
            .description = "Doubles the input",
        },
        StepConfig{
            .id = "step2",
            .name = "Add One Step",
            .description = "Adds one to input",
        },
        StepConfig{
            .id = "step3",
            .name = "Triple Step",
            .description = "Triples the input",
        },
    };

    const execute_fns = [_]*const fn (std.mem.Allocator, std.json.Value) anyerror!std.json.Value{
        doubleValue,
        addOne,
        multiplyByThree,
    };

    const parallel_flow = StepFlowEntry.parallel(&step_configs, &execute_fns);
    const input = std.json.Value{ .integer = 4 };

    const results = try engine.executeStepFlow(parallel_flow, input);
    defer allocator.free(results);

    try testing.expectEqual(@as(usize, 3), results.len);

    // Check that all steps completed successfully
    for (results) |result| {
        try testing.expectEqual(StepStatus.completed, result.status);
        try testing.expect(result.output != null);
    }

    // Check specific results (order may vary due to parallel execution)
    var found_8 = false; // 4 * 2 = 8
    var found_5 = false; // 4 + 1 = 5
    var found_12 = false; // 4 * 3 = 12

    for (results) |result| {
        const value = result.output.?.integer;
        if (value == 8) found_8 = true;
        if (value == 5) found_5 = true;
        if (value == 12) found_12 = true;
    }

    try testing.expect(found_8);
    try testing.expect(found_5);
    try testing.expect(found_12);
}

test "ExecutionEngine conditional execution" {
    const allocator = testing.allocator;
    const logger = try Logger.init(allocator, .{ .level = .info });
    defer logger.deinit();

    const config = ThreadPoolConfig{ .max_threads = 2 };
    var engine = try ExecutionEngine.init(allocator, config, logger);
    defer engine.deinit();

    const step_configs = [_]StepConfig{
        StepConfig{
            .id = "step1",
            .name = "Double Step",
            .description = "Doubles the input",
        },
        StepConfig{
            .id = "step2",
            .name = "Add One Step",
            .description = "Adds one to input",
        },
    };

    const execute_fns = [_]*const fn (std.mem.Allocator, std.json.Value) anyerror!std.json.Value{
        doubleValue,
        addOne,
    };

    const conditions = [_]ConditionFunc{
        ConditionFunc{
            .func = struct {
                fn evaluate(input: std.json.Value) anyerror!bool {
                    return input.integer > 5; // Should be false for input 3
                }
            }.evaluate,
        },
        ConditionFunc{
            .func = struct {
                fn evaluate(input: std.json.Value) anyerror!bool {
                    return input.integer <= 5; // Should be true for input 3
                }
            }.evaluate,
        },
    };

    const conditional_flow = StepFlowEntry.conditional(&step_configs, &execute_fns, &conditions);
    const input = std.json.Value{ .integer = 3 };

    const results = try engine.executeStepFlow(conditional_flow, input);
    defer allocator.free(results);

    try testing.expectEqual(@as(usize, 1), results.len);
    try testing.expectEqual(StepStatus.completed, results[0].status);
    try testing.expectEqualStrings("step2", results[0].step_id); // Second condition should match
    try testing.expectEqual(@as(i64, 4), results[0].output.?.integer); // 3 + 1 = 4
}

test "ExecutionEngine loop execution" {
    const allocator = testing.allocator;
    const logger = try Logger.init(allocator, .{ .level = .info });
    defer logger.deinit();

    const config = ThreadPoolConfig{ .max_threads = 2 };
    var engine = try ExecutionEngine.init(allocator, config, logger);
    defer engine.deinit();

    const step_config = StepConfig{
        .id = "increment_step",
        .name = "Increment Step",
        .description = "Adds one to input",
    };

    const loop_condition = ConditionFunc{
        .func = struct {
            fn evaluate(input: std.json.Value) anyerror!bool {
                return input.integer < 10; // Loop while value is less than 10
            }
        }.evaluate,
    };

    const loop_config = LoopConfig{
        .max_iterations = 20, // Safety limit
        .condition = loop_condition,
        .break_on_error = true,
    };

    const loop_flow = StepFlowEntry.loop(step_config, addOne, loop_config);
    const input = std.json.Value{ .integer = 5 };

    const results = try engine.executeStepFlow(loop_flow, input);
    defer allocator.free(results);

    // Should execute 5 times: 5->6->7->8->9->10, then stop because 10 is not < 10
    try testing.expectEqual(@as(usize, 5), results.len);

    // Check that all iterations completed successfully
    for (results) |result| {
        try testing.expectEqual(StepStatus.completed, result.status);
    }

    // Last result should be 10
    try testing.expectEqual(@as(i64, 10), results[results.len - 1].output.?.integer);
}

test "ExecutionEngine sleep execution" {
    const allocator = testing.allocator;
    const logger = try Logger.init(allocator, .{ .level = .info });
    defer logger.deinit();

    const config = ThreadPoolConfig{ .max_threads = 2 };
    var engine = try ExecutionEngine.init(allocator, config, logger);
    defer engine.deinit();

    const sleep_flow = StepFlowEntry.sleep(10); // 10ms sleep
    const input = std.json.Value{ .integer = 42 };

    const start_time = std.time.timestamp();
    const results = try engine.executeStepFlow(sleep_flow, input);
    const end_time = std.time.timestamp();
    defer allocator.free(results);

    try testing.expectEqual(@as(usize, 1), results.len);
    try testing.expectEqual(StepStatus.completed, results[0].status);
    try testing.expectEqual(@as(i64, 42), results[0].output.?.integer); // Input passed through

    // Should have taken at least 10ms (allowing for some timing variance)
    const elapsed_ms = @as(u64, @intCast(end_time - start_time)) * 1000;
    try testing.expect(elapsed_ms >= 5); // Allow some variance in timing
}

test "ExecutionEngine error handling" {
    const allocator = testing.allocator;
    const logger = try Logger.init(allocator, .{ .level = .info });
    defer logger.deinit();

    const config = ThreadPoolConfig{ .max_threads = 2 };
    var engine = try ExecutionEngine.init(allocator, config, logger);
    defer engine.deinit();

    const step_config = StepConfig{
        .id = "failing_step",
        .name = "Failing Step",
        .description = "A step that always fails",
    };

    const step_flow = StepFlowEntry.step(step_config, failingStep);
    const input = std.json.Value{ .integer = 5 };

    const results = try engine.executeStepFlow(step_flow, input);
    defer allocator.free(results);

    try testing.expectEqual(@as(usize, 1), results.len);
    try testing.expectEqual(StepStatus.failed, results[0].status);
    try testing.expect(results[0].error_message != null);
    try testing.expectEqualStrings("TestFailure", results[0].error_message.?);
}
