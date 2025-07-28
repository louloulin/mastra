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
            std.debug.print("✅ 无内存泄漏！双重释放问题修复成功！\n", .{});
        }
    }
    const allocator = gpa.allocator();

    std.debug.print("🚀 双重释放问题修复验证\n", .{});
    std.debug.print("==================================================\n", .{});

    // 测试1: 基本操作（不删除）
    std.debug.print("1. 测试基本操作（不删除）...\n", .{});
    try testBasicOperations(allocator);

    // 测试2: 包含删除操作
    std.debug.print("2. 测试包含删除操作...\n", .{});
    try testWithDelete(allocator);

    // 测试3: 混合操作
    std.debug.print("3. 测试混合操作...\n", .{});
    try testMixedOperations(allocator);

    std.debug.print("\n🎉 双重释放问题修复验证完成！\n", .{});
    std.debug.print("==================================================\n", .{});
}

fn testBasicOperations(allocator: std.mem.Allocator) !void {
    const storage_config = mastra.storage.StorageConfig{
        .type = .memory,
    };
    var storage = try mastra.storage.Storage.init(allocator, storage_config);
    defer storage.deinit();

    const test_data = std.json.Value{ .string = "basic_test" };
    const record_id = try storage.create("test_table", test_data);
    std.debug.print("   ✅ 创建记录: {s}\n", .{record_id});

    const retrieved = try storage.read("test_table", record_id);
    if (retrieved != null) {
        std.debug.print("   ✅ 读取记录成功\n", .{});
    }

    std.debug.print("   ✅ 基本操作测试完成\n", .{});
}

fn testWithDelete(allocator: std.mem.Allocator) !void {
    const storage_config = mastra.storage.StorageConfig{
        .type = .memory,
    };
    var storage = try mastra.storage.Storage.init(allocator, storage_config);
    defer storage.deinit();

    // 创建记录
    const test_data = std.json.Value{ .string = "to_be_deleted" };
    const record_id = try storage.create("delete_table", test_data);
    std.debug.print("   ✅ 创建记录: {s}\n", .{record_id});

    // 删除记录
    const delete_success = storage.delete("delete_table", record_id);
    if (delete_success) {
        std.debug.print("   ✅ 删除记录成功\n", .{});
    }

    // 验证删除
    const retrieved = try storage.read("delete_table", record_id);
    if (retrieved == null) {
        std.debug.print("   ✅ 验证删除成功\n", .{});
    }

    std.debug.print("   ✅ 删除操作测试完成\n", .{});
}

fn testMixedOperations(allocator: std.mem.Allocator) !void {
    const storage_config = mastra.storage.StorageConfig{
        .type = .memory,
    };
    var storage = try mastra.storage.Storage.init(allocator, storage_config);
    defer storage.deinit();

    // 创建多个记录
    var record_ids = std.ArrayList([]const u8).init(allocator);
    defer record_ids.deinit();

    for (0..5) |i| {
        const test_data = std.json.Value{ .integer = @intCast(i) };
        const record_id = try storage.create("mixed_table", test_data);
        try record_ids.append(record_id);
        std.debug.print("   ✅ 创建记录 {}: {s}\n", .{ i + 1, record_id });
    }

    // 删除一些记录
    for (0..2) |i| {
        const delete_success = storage.delete("mixed_table", record_ids.items[i]);
        if (delete_success) {
            std.debug.print("   ✅ 删除记录 {} 成功\n", .{ i + 1 });
        }
    }

    // 检查剩余记录数
    const remaining_count = storage.count("mixed_table");
    std.debug.print("   ✅ 剩余记录数: {}\n", .{remaining_count});

    std.debug.print("   ✅ 混合操作测试完成\n", .{});
}
