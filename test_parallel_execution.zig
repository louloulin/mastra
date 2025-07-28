const std = @import("std");
const mastra = @import("mastra.zig/src/mastra.zig");

// 测试步骤函数
fn testStep1(alloc: std.mem.Allocator, input: std.json.Value) anyerror!std.json.Value {
    _ = alloc;
    _ = input;
    std.debug.print("   执行步骤1...\n", .{});
    std.time.sleep(100 * std.time.ns_per_ms); // 100ms
    return std.json.Value{ .string = "步骤1完成" };
}

fn testStep2(alloc: std.mem.Allocator, input: std.json.Value) anyerror!std.json.Value {
    _ = alloc;
    _ = input;
    std.debug.print("   执行步骤2...\n", .{});
    std.time.sleep(150 * std.time.ns_per_ms); // 150ms
    return std.json.Value{ .string = "步骤2完成" };
}

fn testStep3(alloc: std.mem.Allocator, input: std.json.Value) anyerror!std.json.Value {
    _ = alloc;
    _ = input;
    std.debug.print("   执行步骤3...\n", .{});
    std.time.sleep(200 * std.time.ns_per_ms); // 200ms
    return std.json.Value{ .string = "步骤3完成" };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("🚀 并行执行测试\n", .{});
    std.debug.print("==================================================\n", .{});

    // 创建线程池配置
    const thread_pool_config = mastra.workflow.ThreadPoolConfig{
        .max_threads = 4,
        .queue_size = 20,
    };

    // 创建日志器
    const logger_config = mastra.utils.LoggerConfig{
        .level = .info,
    };
    var logger = try mastra.utils.Logger.init(allocator, logger_config);
    defer logger.deinit();

    // 创建执行引擎
    var execution_engine = try mastra.workflow.ExecutionEngine.init(allocator, thread_pool_config, logger);
    defer execution_engine.deinit();

    std.debug.print("1. 测试单步执行...\n", .{});

    // 创建单个步骤
    const single_step = mastra.workflow.StepFlowEntry{
        .flow_type = .step,
        .step_config = mastra.workflow.StepConfig{
            .id = "single_step",
            .name = "单个步骤",
            .description = "测试单个步骤执行",
            .timeout_ms = 5000,
        },
        .execute_fn = testStep1,
    };

    const input_data = std.json.Value{ .string = "测试输入" };

    const start_time = std.time.milliTimestamp();
    const single_result = try execution_engine.executeStepFlow(single_step, input_data);
    const single_duration = std.time.milliTimestamp() - start_time;
    defer allocator.free(single_result);

    std.debug.print("   ✅ 单步执行完成，耗时: {}ms\n", .{single_duration});

    std.debug.print("2. 测试并行执行...\n", .{});

    // 创建并行步骤
    const parallel_steps = [_]mastra.workflow.StepConfig{
        mastra.workflow.StepConfig{
            .id = "parallel_step_1",
            .name = "并行步骤1",
            .description = "第一个并行步骤",
            .timeout_ms = 5000,
        },
        mastra.workflow.StepConfig{
            .id = "parallel_step_2",
            .name = "并行步骤2",
            .description = "第二个并行步骤",
            .timeout_ms = 5000,
        },
        mastra.workflow.StepConfig{
            .id = "parallel_step_3",
            .name = "并行步骤3",
            .description = "第三个并行步骤",
            .timeout_ms = 5000,
        },
    };

    const parallel_fns = [_]*const fn (std.mem.Allocator, std.json.Value) anyerror!std.json.Value{
        testStep1,
        testStep2,
        testStep3,
    };

    const parallel_entry = mastra.workflow.StepFlowEntry{
        .flow_type = .parallel,
        .steps = &parallel_steps,
        .execute_fns = &parallel_fns,
    };

    const parallel_start_time = std.time.milliTimestamp();
    const parallel_result = try execution_engine.executeStepFlow(parallel_entry, input_data);
    const parallel_duration = std.time.milliTimestamp() - parallel_start_time;
    defer allocator.free(parallel_result);

    std.debug.print("   ✅ 并行执行完成，执行了 {} 个步骤，总耗时: {}ms\n", .{ parallel_result.len, parallel_duration });

    // 验证并行执行确实更快
    if (parallel_duration < single_duration * 3) {
        std.debug.print("   ✅ 并行执行效率验证通过！\n", .{});
    } else {
        std.debug.print("   ⚠️  并行执行可能没有达到预期效果\n", .{});
    }

    std.debug.print("\n✅ 并行执行测试完成！\n", .{});
    std.debug.print("==================================================\n", .{});
}
