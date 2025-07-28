const std = @import("std");
const mastra = @import("mastra");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("❌ 检测到内存泄漏！\n", .{});
            std.process.exit(1);
        } else {
            std.debug.print("✅ 无内存泄漏！内存管理完美！\n", .{});
        }
    }
    const allocator = gpa.allocator();

    std.debug.print("🔧 内存泄漏修复测试\n", .{});
    std.debug.print("==================================================\n", .{});

    try testMemoryLeakFix(allocator);

    std.debug.print("\n🎯 内存泄漏修复测试完成！\n", .{});
    std.debug.print("==================================================\n", .{});
}

fn testMemoryLeakFix(allocator: std.mem.Allocator) !void {
    std.debug.print("\n📋 内存泄漏修复测试\n", .{});
    std.debug.print("----------------------------------------\n", .{});

    // 1. 存储系统内存泄漏测试
    std.debug.print("1. 🗄️ 存储系统内存测试...\n", .{});
    {
        for (0..5) |i| {
            const storage_config = mastra.storage.StorageConfig{
                .type = .memory,
            };
            var storage = try mastra.storage.Storage.init(allocator, storage_config);
            defer storage.deinit();

            const test_data = std.json.Value{ .string = "test_value" };
            const record_id = try storage.create("test_table", test_data);

            const retrieved = try storage.read("test_table", record_id);
            if (retrieved != null) {
                std.debug.print("   ✅ 存储测试 {}/5 完成\n", .{i + 1});
            }
        }
    }

    // 2. Agent系统内存测试
    std.debug.print("2. 🤖 Agent系统内存测试...\n", .{});
    {
        for (0..3) |i| {
            const runtime_context = mastra.agent.RuntimeContext.init(allocator);
            const dynamic_arg = mastra.agent.DynamicArgument([]const u8){ .static_value = "测试指令" };
            const resolved = try dynamic_arg.resolve(runtime_context);
            _ = resolved;

            const message_config = mastra.agent.MessageListConfig{};
            var message_list = try mastra.agent.MessageList.init(allocator, message_config, null);
            defer message_list.deinit();

            try message_list.addMessage("user", "测试消息", .normal);
            const message_count = message_list.getMessageCount();
            _ = message_count;

            std.debug.print("   ✅ Agent测试 {}/3 完成\n", .{i + 1});
        }
    }

    // 3. 工作流引擎内存测试
    std.debug.print("3. ⚙️ 工作流引擎内存测试...\n", .{});
    {
        for (0..3) |i| {
            const thread_pool_config = mastra.workflow.ThreadPoolConfig{
                .max_threads = 2,
                .queue_size = 100,
            };

            const logger_config = mastra.utils.LoggerConfig{
                .level = .info,
            };
            var logger = try mastra.utils.Logger.init(allocator, logger_config);
            defer logger.deinit();

            var execution_engine = try mastra.workflow.ExecutionEngine.init(allocator, thread_pool_config, logger);
            defer execution_engine.deinit();

            std.debug.print("   ✅ 工作流测试 {}/3 完成\n", .{i + 1});
        }
    }

    // 4. 事件系统内存测试
    std.debug.print("4. 📡 事件系统内存测试...\n", .{});
    {
        for (0..3) |i| {
            const event_bus_config = mastra.event_bus.EventBusConfig{};
            var event_bus = try mastra.event_bus.EventBus.init(allocator, event_bus_config);
            defer event_bus.deinit();

            const event_data = std.json.Value{ .string = "测试数据" };
            try event_bus.publish("test", event_data, "test_source");

            std.debug.print("   ✅ 事件测试 {}/3 完成\n", .{i + 1});
        }
    }

    std.debug.print("   🎯 所有内存测试完成\n", .{});
}
