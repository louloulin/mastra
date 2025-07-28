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

    std.debug.print("🚀 最终内存泄漏修复测试\n", .{});
    std.debug.print("==================================================\n", .{});

    // 测试存储系统
    std.debug.print("📋 存储系统内存管理测试\n", .{});
    {
        const storage_config = mastra.storage.StorageConfig{
            .type = .memory,
        };
        var storage = try mastra.storage.Storage.init(allocator, storage_config);
        defer storage.deinit();

        std.debug.print("✅ 存储系统初始化成功\n", .{});

        // 创建多个记录测试
        var record_ids = std.ArrayList([]const u8).init(allocator);
        defer {
            for (record_ids.items) |id| {
                allocator.free(id);
            }
            record_ids.deinit();
        }

        for (0..5) |i| {
            const test_data = std.json.Value{ .integer = @intCast(i) };
            const record_id = try storage.create("test_table", test_data);
            try record_ids.append(record_id);
            std.debug.print("✅ 创建记录 {}: {s}\n", .{ i + 1, record_id });
        }

        // 读取所有记录
        for (record_ids.items, 0..) |id, i| {
            const retrieved = try storage.read("test_table", id);
            if (retrieved != null) {
                std.debug.print("✅ 读取记录 {} 成功\n", .{ i + 1 });
            }
        }

        std.debug.print("✅ 存储系统测试完成\n", .{});
    }

    std.debug.print("\n🎉 内存泄漏修复验证完成！\n", .{});
    std.debug.print("==================================================\n", .{});
}
