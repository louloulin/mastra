const std = @import("std");
const mastra = @import("mastra");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("🚀 内存修复验证测试\n", .{});
    std.debug.print("==================================================\n", .{});

    try testStorageMemoryFix(allocator);

    std.debug.print("\n🎉 内存修复验证完成！\n", .{});
    std.debug.print("==================================================\n", .{});
}

fn testStorageMemoryFix(allocator: std.mem.Allocator) !void {
    std.debug.print("\n📋 存储系统内存修复测试\n", .{});
    std.debug.print("----------------------------------------\n", .{});

    // 测试存储系统的内存管理
    std.debug.print("1. 测试存储系统内存管理...\n", .{});
    
    const storage_config = mastra.storage.StorageConfig{
        .type = .memory,
    };
    var storage = try mastra.storage.Storage.init(allocator, storage_config);
    defer storage.deinit();

    // 创建多个记录来测试内存管理
    const test_data1 = std.json.Value{ .string = "test_value_1" };
    const record_id1 = try storage.create("test_table", test_data1);
    defer allocator.free(record_id1);
    
    const test_data2 = std.json.Value{ .string = "test_value_2" };
    const record_id2 = try storage.create("test_table", test_data2);
    defer allocator.free(record_id2);
    
    std.debug.print("   ✅ 创建了2个记录: {s}, {s}\n", .{ record_id1, record_id2 });

    // 读取记录
    const retrieved_record1 = try storage.read("test_table", record_id1);
    const retrieved_record2 = try storage.read("test_table", record_id2);
    
    if (retrieved_record1 != null and retrieved_record2 != null) {
        std.debug.print("   ✅ 成功读取了2个记录\n", .{});
    }

    std.debug.print("   ✅ 存储系统内存管理测试完成\n", .{});
}
