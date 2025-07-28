const std = @import("std");
const mastra = @import("mastra.zig/src/mastra.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("🚀 简单并行工作流测试\n", .{});
    std.debug.print("==================================================\n", .{});

    // 1. 测试基本组件创建
    std.debug.print("1. 测试基本组件...\n", .{});

    // 创建线程池配置
    const thread_pool_config = mastra.workflow.ThreadPoolConfig{
        .max_threads = 2,
        .queue_size = 10,
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
    std.debug.print("   ✅ ExecutionEngine创建成功\n", .{});

    // 2. 测试简单的步骤流
    std.debug.print("2. 测试步骤流类型...\n", .{});

    // 创建一个基本的步骤流条目
    const step_flow = mastra.workflow.StepFlowEntry{
        .flow_type = .step,
    };

    std.debug.print("   ✅ StepFlowEntry创建成功，类型: {}\n", .{step_flow.flow_type});

    // 3. 测试不同的流类型
    std.debug.print("3. 测试不同流类型...\n", .{});

    const parallel_flow = mastra.workflow.StepFlowEntry{
        .flow_type = .parallel,
    };

    const conditional_flow = mastra.workflow.StepFlowEntry{
        .flow_type = .conditional,
    };

    const loop_flow = mastra.workflow.StepFlowEntry{
        .flow_type = .loop,
    };

    std.debug.print("   ✅ 并行流类型: {}\n", .{parallel_flow.flow_type});
    std.debug.print("   ✅ 条件流类型: {}\n", .{conditional_flow.flow_type});
    std.debug.print("   ✅ 循环流类型: {}\n", .{loop_flow.flow_type});

    // 4. 测试工作流配置
    std.debug.print("4. 测试工作流配置...\n", .{});

    const workflow_config = mastra.workflow.WorkflowConfig{
        .id = "test_workflow",
        .name = "测试工作流",
        .description = "这是一个测试工作流",
        .version = "1.0.0",
        .steps = &[_]mastra.workflow.StepConfig{},
        .execution_timeout_ms = 30000,
    };

    std.debug.print("   ✅ 工作流配置: {s} v{s}\n", .{ workflow_config.name, workflow_config.version });

    // 5. 测试步骤配置
    std.debug.print("5. 测试步骤配置...\n", .{});

    const step_config = mastra.workflow.StepConfig{
        .id = "test_step",
        .name = "测试步骤",
        .description = "这是一个测试步骤",
        .timeout_ms = 5000,
    };

    std.debug.print("   ✅ 步骤配置: {s}\n", .{step_config.name});

    std.debug.print("\n✅ 所有基本测试通过！\n", .{});
    std.debug.print("==================================================\n", .{});
}
