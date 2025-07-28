const std = @import("std");
const mastra = @import("mastra");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("❌ 内存泄漏检测到！\n", .{});
        } else {
            std.debug.print("✅ 无内存泄漏！\n", .{});
        }
    }
    const allocator = gpa.allocator();

    std.debug.print("🚀 调试内存问题\n", .{});

    // 测试1: 只初始化和清理
    std.debug.print("1. 测试初始化和清理...\n", .{});
    {
        const storage_config = mastra.storage.StorageConfig{
            .type = .memory,
        };
        const storage = try mastra.storage.Storage.init(allocator, storage_config);
        std.debug.print("   ✅ 初始化成功\n", .{});

        // 不调用deinit，看看是否有问题
        // storage.deinit();
        _ = storage; // 避免未使用警告
    }
    std.debug.print("   ✅ 测试1完成（未清理）\n", .{});

    // 测试2: 初始化和清理
    std.debug.print("2. 测试初始化和清理...\n", .{});
    {
        const storage_config = mastra.storage.StorageConfig{
            .type = .memory,
        };
        var storage = try mastra.storage.Storage.init(allocator, storage_config);
        std.debug.print("   ✅ 初始化成功\n", .{});

        // 尝试清理
        storage.deinit();
        std.debug.print("   ✅ 清理成功\n", .{});
    }
    std.debug.print("   ✅ 测试2完成\n", .{});

    // 测试3: 创建数据然后清理
    std.debug.print("3. 测试创建数据然后清理...\n", .{});
    {
        const storage_config = mastra.storage.StorageConfig{
            .type = .memory,
        };
        var storage = try mastra.storage.Storage.init(allocator, storage_config);
        std.debug.print("   ✅ 初始化成功\n", .{});

        const test_data = std.json.Value{ .string = "test_value" };
        const record_id = try storage.create("test_table", test_data);
        defer allocator.free(record_id);
        std.debug.print("   ✅ 创建数据成功: {s}\n", .{record_id});

        // 尝试清理
        storage.deinit();
        std.debug.print("   ✅ 清理成功\n", .{});
    }
    std.debug.print("   ✅ 测试3完成\n", .{});

    std.debug.print("🎉 调试完成！\n", .{});
}
