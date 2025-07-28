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

    std.debug.print("🚀 最小存储测试\n", .{});

    // 测试1: 只初始化和清理
    std.debug.print("1. 测试空存储系统...\n", .{});
    {
        const storage_config = mastra.storage.StorageConfig{
            .type = .memory,
        };
        var storage = try mastra.storage.Storage.init(allocator, storage_config);
        std.debug.print("   ✅ 初始化成功\n", .{});
        
        storage.deinit();
        std.debug.print("   ✅ 清理成功\n", .{});
    }

    // 测试2: 创建一个记录然后清理
    std.debug.print("2. 测试创建记录...\n", .{});
    {
        const storage_config = mastra.storage.StorageConfig{
            .type = .memory,
        };
        var storage = try mastra.storage.Storage.init(allocator, storage_config);
        std.debug.print("   ✅ 初始化成功\n", .{});
        
        const test_data = std.json.Value{ .string = "test_value" };
        const record_id = try storage.create("test_table", test_data);
        defer allocator.free(record_id);
        std.debug.print("   ✅ 创建记录: {s}\n", .{record_id});
        
        storage.deinit();
        std.debug.print("   ✅ 清理成功\n", .{});
    }

    std.debug.print("🎉 测试完成！\n", .{});
}
