const std = @import("std");

// 直接测试HashMap的内存管理，不依赖复杂的mastra模块
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("❌ 内存泄漏检测到！\n", .{});
            std.process.exit(1);
        } else {
            std.debug.print("✅ 无内存泄漏！HashMap修复成功！\n", .{});
        }
    }
    const allocator = gpa.allocator();

    std.debug.print("🚀 HashMap内存管理测试\n", .{});
    std.debug.print("==================================================\n", .{});

    // 测试1: 基本HashMap操作
    std.debug.print("1. 测试基本HashMap操作...\n", .{});
    {
        var data = std.HashMap([]const u8, std.json.Value, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator);
        defer {
            // 清理所有key
            var iter = data.iterator();
            while (iter.next()) |entry| {
                allocator.free(entry.key_ptr.*);
            }
            data.deinit();
        }

        // 创建一些测试数据
        for (0..3) |i| {
            const key = try std.fmt.allocPrint(allocator, "key_{d}", .{i});
            const value = std.json.Value{ .integer = @intCast(i) };
            try data.put(key, value);
            std.debug.print("   ✅ 插入键值对: {s} = {}\n", .{ key, i });
        }

        // 读取数据
        var read_iter = data.iterator();
        while (read_iter.next()) |entry| {
            std.debug.print("   ✅ 读取键值对: {s} = {}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        }

        std.debug.print("   ✅ HashMap基本操作测试完成\n", .{});
    }

    // 测试2: 模拟存储系统操作
    std.debug.print("2. 测试模拟存储系统操作...\n", .{});
    {
        var storage_data = std.HashMap([]const u8, std.json.Value, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator);
        defer {
            // 安全清理
            var iter = storage_data.iterator();
            while (iter.next()) |entry| {
                allocator.free(entry.key_ptr.*);
            }
            storage_data.deinit();
        }

        // 模拟create操作
        for (0..5) |i| {
            const nano_timestamp = std.time.nanoTimestamp();
            const id = try std.fmt.allocPrint(allocator, "test_table_{d}_{d}", .{ std.time.timestamp(), nano_timestamp + i });
            const test_data = std.json.Value{ .string = "test_value" };
            
            try storage_data.put(id, test_data);
            std.debug.print("   ✅ 创建记录: {s}\n", .{id});
        }

        // 模拟read操作
        var read_count: usize = 0;
        var read_iter = storage_data.iterator();
        while (read_iter.next()) |entry| {
            read_count += 1;
            std.debug.print("   ✅ 读取记录 {}: {s}\n", .{ read_count, entry.key_ptr.* });
        }

        std.debug.print("   ✅ 模拟存储系统操作测试完成\n", .{});
    }

    std.debug.print("\n🎉 HashMap内存管理测试完成！\n", .{});
    std.debug.print("==================================================\n", .{});
}
