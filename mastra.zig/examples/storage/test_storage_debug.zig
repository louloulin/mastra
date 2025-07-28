const std = @import("std");
const mastra = @import("mastra");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("❌ 内存泄漏！\n", .{});
        } else {
            std.debug.print("✅ 无内存泄漏！\n", .{});
        }
    }
    const allocator = gpa.allocator();

    std.debug.print("🚀 存储系统调试测试\n", .{});

    // 测试1: 只初始化和清理，不创建数据
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

    // 测试2: 创建数据但不读取
    std.debug.print("2. 测试创建数据...\n", .{});
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
        
        storage.deinit();
        std.debug.print("   ✅ 清理成功\n", .{});
    }

    std.debug.print("🎉 调试测试完成！\n", .{});
}
