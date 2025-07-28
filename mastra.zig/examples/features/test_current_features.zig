const std = @import("std");
const mastra = @import("mastra");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("🚀 当前功能验证测试\n", .{});
    std.debug.print("==================================================\n", .{});

    // 测试已实现的核心功能
    try testCoreFeatures(allocator);

    std.debug.print("\n🎉 当前功能验证完成！\n", .{});
    std.debug.print("==================================================\n", .{});
}

fn testCoreFeatures(allocator: std.mem.Allocator) !void {
    std.debug.print("\n📋 核心功能测试\n", .{});
    std.debug.print("----------------------------------------\n", .{});

    // 1. 并行工作流引擎测试
    std.debug.print("1. 测试并行工作流引擎...\n", .{});

    // 创建线程池配置
    const thread_pool_config = mastra.workflow.ThreadPoolConfig{
        .max_threads = 2,
        .queue_size = 100,
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
    std.debug.print("   ✅ ExecutionEngine初始化成功\n", .{});

    // 测试单步执行
    const testStepFunction = struct {
        fn execute(alloc: std.mem.Allocator, input: std.json.Value) anyerror!std.json.Value {
            _ = alloc;
            _ = input;
            return std.json.Value{ .string = "测试完成" };
        }
    }.execute;

    const single_step = mastra.workflow.StepFlowEntry{
        .flow_type = .step,
        .step_config = mastra.workflow.StepConfig{
            .id = "test_step",
            .name = "测试步骤",
            .description = "这是一个测试步骤",
            .timeout_ms = 5000,
        },
        .execute_fn = testStepFunction,
    };

    const input_data = std.json.Value{ .string = "测试输入" };
    const single_result = try execution_engine.executeStepFlow(single_step, input_data);
    defer allocator.free(single_result);
    std.debug.print("   ✅ 单步执行成功，结果数: {}\n", .{single_result.len});

    // 2. 工作流配置测试
    std.debug.print("2. 测试工作流配置...\n", .{});

    const workflow_config = mastra.workflow.WorkflowConfig{
        .id = "test_workflow",
        .name = "测试工作流",
        .description = "这是一个测试工作流",
        .version = "1.0.0",
        .steps = &[_]mastra.workflow.StepConfig{},
        .execution_timeout_ms = 30000,
    };

    std.debug.print("   ✅ 工作流配置: {s} v{s}\n", .{ workflow_config.name, workflow_config.version });

    // 3. 步骤配置测试
    std.debug.print("3. 测试步骤配置...\n", .{});

    const step_config = mastra.workflow.StepConfig{
        .id = "test_step",
        .name = "测试步骤",
        .description = "这是一个测试步骤",
        .timeout_ms = 5000,
    };

    std.debug.print("   ✅ 步骤配置: {s}\n", .{step_config.name});

    // 4. 流类型测试
    std.debug.print("4. 测试流类型...\n", .{});

    const ExecutionEngine = @import("src/workflow/execution_engine.zig");
    const flow_types = [_]ExecutionEngine.StepFlowType{ .step, .parallel, .conditional, .loop, .foreach, .sleep, .waitForEvent };

    for (flow_types) |flow_type| {
        std.debug.print("   ✅ 支持流类型: {}\n", .{flow_type});
    }

    // 5. 日志系统测试
    std.debug.print("5. 测试日志系统...\n", .{});

    logger.info("测试信息日志", .{});
    logger.debug("测试调试日志", .{});
    std.debug.print("   ✅ 日志系统正常工作\n", .{});

    // 6. 存储系统基础测试
    std.debug.print("6. 测试存储系统...\n", .{});

    const storage_config = mastra.storage.StorageConfig{
        .type = .memory,
    };
    var storage = try mastra.storage.Storage.init(allocator, storage_config);
    defer storage.deinit();
    std.debug.print("   ✅ 存储系统初始化成功\n", .{});

    std.debug.print("   ✅ 核心功能验证完成\n", .{});
}
