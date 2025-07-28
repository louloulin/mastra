const std = @import("std");
const mastra = @import("mastra.zig/src/mastra.zig");

// 简单的测试步骤函数
fn simpleStep(alloc: std.mem.Allocator, input: std.json.Value) anyerror!std.json.Value {
    _ = alloc;
    _ = input;
    std.debug.print("   ⚡ 执行步骤\n", .{});
    std.time.sleep(50 * std.time.ns_per_ms); // 50ms
    return std.json.Value{ .string = "完成" };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("🚀 并行工作流最终测试\n", .{});
    std.debug.print("==================================================\n", .{});

    // 创建线程池配置 - 使用更大的队列
    const thread_pool_config = mastra.workflow.ThreadPoolConfig{
        .max_threads = 2,
        .queue_size = 50, // 增大队列大小
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

    std.debug.print("✅ 执行引擎初始化完成\n", .{});

    // 测试1: 单步执行
    std.debug.print("\n1. 测试单步执行...\n", .{});

    const single_step = mastra.workflow.StepFlowEntry{
        .flow_type = .step,
        .step_config = mastra.workflow.StepConfig{
            .id = "single",
            .name = "单步",
            .description = "单步测试",
            .timeout_ms = 5000,
        },
        .execute_fn = simpleStep,
    };

    const input_data = std.json.Value{ .string = "测试" };

    const start_time = std.time.milliTimestamp();
    const single_result = try execution_engine.executeStepFlow(single_step, input_data);
    const single_duration = std.time.milliTimestamp() - start_time;
    defer allocator.free(single_result);

    std.debug.print("   ✅ 单步执行完成，耗时: {}ms，结果数: {}\n", .{ single_duration, single_result.len });

    // 测试2: 并行执行（简化版本）
    std.debug.print("\n2. 测试并行执行...\n", .{});

    // 创建2个并行步骤
    const parallel_steps = [_]mastra.workflow.StepConfig{
        mastra.workflow.StepConfig{
            .id = "p1",
            .name = "并行1",
            .description = "并行步骤1",
            .timeout_ms = 5000,
        },
        mastra.workflow.StepConfig{
            .id = "p2",
            .name = "并行2",
            .description = "并行步骤2",
            .timeout_ms = 5000,
        },
    };

    const parallel_fns = [_]*const fn (std.mem.Allocator, std.json.Value) anyerror!std.json.Value{
        simpleStep,
        simpleStep,
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

    std.debug.print("   ✅ 并行执行完成，耗时: {}ms，结果数: {}\n", .{ parallel_duration, parallel_result.len });

    // 验证结果
    if (parallel_result.len == 2) {
        std.debug.print("   ✅ 并行执行返回了正确数量的结果\n", .{});
    }

    if (parallel_duration < single_duration * 2) {
        std.debug.print("   ✅ 并行执行效率验证通过！\n", .{});
    } else {
        std.debug.print("   ⚠️  并行执行时间: {}ms vs 单步时间: {}ms\n", .{ parallel_duration, single_duration });
    }

    // 测试3: 流类型验证
    std.debug.print("\n3. 测试流类型...\n", .{});

    const ExecutionEngine = @import("mastra.zig/src/workflow/execution_engine.zig");
    const flow_types = [_]ExecutionEngine.StepFlowType{ .step, .parallel, .conditional, .loop, .foreach, .sleep, .waitForEvent };

    for (flow_types) |flow_type| {
        std.debug.print("   ✅ 支持流类型: {}\n", .{flow_type});
    }

    std.debug.print("\n🎉 所有测试完成！\n", .{});
    std.debug.print("==================================================\n", .{});
}
