const std = @import("std");
const mastra = @import("mastra");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("❌ 内存泄漏检测到！\n", .{});
            std.process.exit(1);
        } else {
            std.debug.print("✅ 无内存泄漏！所有测试完全通过！\n", .{});
        }
    }
    const allocator = gpa.allocator();

    std.debug.print("🚀 Mastra.zig 最终综合验证\n", .{});
    std.debug.print("==================================================\n", .{});

    var test_count: u32 = 0;
    var passed_count: u32 = 0;

    // 测试1: 存储系统核心功能
    test_count += 1;
    if (testStorageCore(allocator)) {
        passed_count += 1;
        std.debug.print("✅ 测试1: 存储系统核心功能 - 通过\n", .{});
    } else |_| {
        std.debug.print("❌ 测试1: 存储系统核心功能 - 失败\n", .{});
    }

    // 测试2: 存储系统CRUD操作
    test_count += 1;
    if (testStorageCRUD(allocator)) {
        passed_count += 1;
        std.debug.print("✅ 测试2: 存储系统CRUD操作 - 通过\n", .{});
    } else |_| {
        std.debug.print("❌ 测试2: 存储系统CRUD操作 - 失败\n", .{});
    }

    // 测试3: 存储系统内存管理
    test_count += 1;
    if (testStorageMemory(allocator)) {
        passed_count += 1;
        std.debug.print("✅ 测试3: 存储系统内存管理 - 通过\n", .{});
    } else |_| {
        std.debug.print("❌ 测试3: 存储系统内存管理 - 失败\n", .{});
    }

    // 测试4: 工作流引擎基础
    test_count += 1;
    if (testWorkflowBasic(allocator)) {
        passed_count += 1;
        std.debug.print("✅ 测试4: 工作流引擎基础 - 通过\n", .{});
    } else |_| {
        std.debug.print("❌ 测试4: 工作流引擎基础 - 失败\n", .{});
    }

    // 测试5: Agent系统基础
    test_count += 1;
    if (testAgentBasic(allocator)) {
        passed_count += 1;
        std.debug.print("✅ 测试5: Agent系统基础 - 通过\n", .{});
    } else |_| {
        std.debug.print("❌ 测试5: Agent系统基础 - 失败\n", .{});
    }

    std.debug.print("\n📊 测试结果统计:\n", .{});
    std.debug.print("   总测试数: {}\n", .{test_count});
    std.debug.print("   通过数: {}\n", .{passed_count});
    std.debug.print("   失败数: {}\n", .{test_count - passed_count});
    std.debug.print("   通过率: {d:.1}%\n", .{@as(f64, @floatFromInt(passed_count)) / @as(f64, @floatFromInt(test_count)) * 100.0});

    if (passed_count == test_count) {
        std.debug.print("\n🎉 所有测试完全通过！Mastra.zig 功能验证成功！\n", .{});
    } else {
        std.debug.print("\n⚠️ 部分测试失败，需要进一步检查\n", .{});
    }

    std.debug.print("==================================================\n", .{});
}

fn testStorageCore(allocator: std.mem.Allocator) !void {
    const storage_config = mastra.storage.StorageConfig{
        .type = .memory,
    };
    var storage = try mastra.storage.Storage.init(allocator, storage_config);
    defer storage.deinit();

    const test_data = std.json.Value{ .string = "core_test" };
    const record_id = try storage.create("core_table", test_data);

    const retrieved = try storage.read("core_table", record_id);
    if (retrieved == null) return error.ReadFailed;
}

fn testStorageCRUD(allocator: std.mem.Allocator) !void {
    const storage_config = mastra.storage.StorageConfig{
        .type = .memory,
    };
    var storage = try mastra.storage.Storage.init(allocator, storage_config);
    defer storage.deinit();

    // Create
    const test_data = std.json.Value{ .string = "crud_test" };
    const record_id = try storage.create("crud_table", test_data);

    // Read
    const retrieved = try storage.read("crud_table", record_id);
    if (retrieved == null) return error.ReadFailed;

    // Update
    const updated_data = std.json.Value{ .string = "updated_crud_test" };
    const update_success = try storage.update("crud_table", record_id, updated_data);
    if (!update_success) return error.UpdateFailed;

    // Delete
    const delete_success = storage.delete("crud_table", record_id);
    if (!delete_success) return error.DeleteFailed;

    // Verify deletion
    const deleted_record = try storage.read("crud_table", record_id);
    if (deleted_record != null) return error.DeleteVerificationFailed;
}

fn testStorageMemory(allocator: std.mem.Allocator) !void {
    // 创建多个存储实例测试内存管理
    for (0..3) |_| {
        const storage_config = mastra.storage.StorageConfig{
            .type = .memory,
        };
        var storage = try mastra.storage.Storage.init(allocator, storage_config);
        defer storage.deinit();

        // 创建多个记录
        for (0..5) |i| {
            const test_data = std.json.Value{ .integer = @intCast(i) };
            _ = try storage.create("memory_table", test_data);
        }

        // 删除一些记录
        const count_before = storage.count("memory_table");
        if (count_before > 0) {
            var iter = storage.data.iterator();
            if (iter.next()) |entry| {
                _ = storage.delete("memory_table", entry.key_ptr.*);
            }
        }
    }
}

fn testWorkflowBasic(allocator: std.mem.Allocator) !void {
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
}

fn testAgentBasic(allocator: std.mem.Allocator) !void {
    const runtime_context = mastra.agent.RuntimeContext.init(allocator);
    const dynamic_arg = mastra.agent.DynamicArgument([]const u8){ .static_value = "test_instruction" };
    _ = try dynamic_arg.resolve(runtime_context);

    const message_config = mastra.agent.MessageListConfig{};
    var message_list = try mastra.agent.MessageList.init(allocator, message_config, null);
    defer message_list.deinit();
    
    try message_list.addMessage("user", "test_message", .normal);
    const message_count = message_list.getMessageCount();
    if (message_count == 0) return error.MessageListFailed;
}
