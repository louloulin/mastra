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
            std.debug.print("✅ 无内存泄漏！\n", .{});
        }
    }
    const allocator = gpa.allocator();

    std.debug.print("🚀 存储系统隔离测试\n", .{});
    std.debug.print("==================================================\n", .{});

    // 测试1: 完全隔离的存储系统测试
    std.debug.print("1. 隔离存储系统测试...\n", .{});
    try testStorageOnly(allocator);

    // 测试2: 模拟完整测试环境
    std.debug.print("2. 模拟完整测试环境...\n", .{});
    try testWithOtherModules(allocator);

    std.debug.print("\n🎉 隔离测试完成！\n", .{});
    std.debug.print("==================================================\n", .{});
}

fn testStorageOnly(allocator: std.mem.Allocator) !void {
    std.debug.print("   开始纯存储系统测试...\n", .{});
    
    const storage_config = mastra.storage.StorageConfig{
        .type = .memory,
    };
    var storage = try mastra.storage.Storage.init(allocator, storage_config);
    defer storage.deinit();

    const test_data = std.json.Value{ .string = "test_value" };
    const record_id = try storage.create("test_table", test_data);

    const retrieved = try storage.read("test_table", record_id);
    if (retrieved != null) {
        std.debug.print("   ✅ 存储系统创建和读取成功\n", .{});
    }

    std.debug.print("   ✅ 纯存储系统测试完成\n", .{});
}

fn testWithOtherModules(allocator: std.mem.Allocator) !void {
    std.debug.print("   开始模拟完整环境测试...\n", .{});
    
    // 先初始化其他模块（模拟完整测试环境）
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
    std.debug.print("   ✅ 其他模块初始化成功\n", .{});

    // 然后测试存储系统
    const storage_config = mastra.storage.StorageConfig{
        .type = .memory,
    };
    var storage = try mastra.storage.Storage.init(allocator, storage_config);
    defer storage.deinit();

    const test_data = std.json.Value{ .string = "test_value" };
    const record_id = try storage.create("test_table", test_data);

    const retrieved = try storage.read("test_table", record_id);
    if (retrieved != null) {
        std.debug.print("   ✅ 存储系统在完整环境中工作正常\n", .{});
    }

    std.debug.print("   ✅ 完整环境测试完成，准备清理\n", .{});
    // 注意：defer会按相反顺序清理：storage -> execution_engine -> logger
}
