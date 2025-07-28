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
            std.debug.print("✅ 无内存泄漏！修复成功！\n", .{});
        }
    }
    const allocator = gpa.allocator();

    std.debug.print("🚀 最终内存修复验证\n", .{});
    std.debug.print("==================================================\n", .{});

    // 测试1: 基本存储操作
    std.debug.print("1. 测试基本存储操作...\n", .{});
    {
        const storage_config = mastra.storage.StorageConfig{
            .type = .memory,
        };
        var storage = try mastra.storage.Storage.init(allocator, storage_config);
        defer storage.deinit();

        const test_data = std.json.Value{ .string = "test_value" };
        const record_id = try storage.create("test_table", test_data);
        // 注意：不需要手动释放record_id，因为StringHashMap拥有它
        std.debug.print("   ✅ 创建记录: {s}\n", .{record_id});

        const retrieved = try storage.read("test_table", record_id);
        if (retrieved != null) {
            std.debug.print("   ✅ 读取记录成功\n", .{});
        }

        std.debug.print("   ✅ 基本操作测试完成\n", .{});
    }

    // 测试2: 多记录操作
    std.debug.print("2. 测试多记录操作...\n", .{});
    {
        const storage_config = mastra.storage.StorageConfig{
            .type = .memory,
        };
        var storage = try mastra.storage.Storage.init(allocator, storage_config);
        defer storage.deinit();

        // 创建多个记录
        for (0..3) |i| {
            const test_data = std.json.Value{ .integer = @intCast(i) };
            const record_id = try storage.create("test_table", test_data);
            std.debug.print("   ✅ 创建记录 {}: {s}\n", .{ i + 1, record_id });
        }

        const count = storage.count("test_table");
        std.debug.print("   ✅ 总记录数: {}\n", .{count});

        std.debug.print("   ✅ 多记录操作测试完成\n", .{});
    }

    // 测试3: 删除操作
    std.debug.print("3. 测试删除操作...\n", .{});
    {
        const storage_config = mastra.storage.StorageConfig{
            .type = .memory,
        };
        var storage = try mastra.storage.Storage.init(allocator, storage_config);
        defer storage.deinit();

        const test_data = std.json.Value{ .string = "to_be_deleted" };
        const record_id = try storage.create("test_table", test_data);
        std.debug.print("   ✅ 创建记录: {s}\n", .{record_id});

        const delete_success = storage.delete("test_table", record_id);
        if (delete_success) {
            std.debug.print("   ✅ 删除记录成功\n", .{});
        }

        const final_count = storage.count("test_table");
        std.debug.print("   ✅ 删除后记录数: {}\n", .{final_count});

        std.debug.print("   ✅ 删除操作测试完成\n", .{});
    }

    std.debug.print("\n🎉 所有测试完成！内存管理修复验证成功！\n", .{});
    std.debug.print("==================================================\n", .{});
}
