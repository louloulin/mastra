const std = @import("std");

// 最小的存储测试，不依赖复杂的mastra模块
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

    std.debug.print("🚀 最小存储测试\n", .{});

    // 简单的HashMap测试
    var data = std.HashMap([]const u8, std.json.Value, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator);
    defer {
        // 清理HashMap
        var iter = data.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }
        data.deinit();
    }

    // 创建一个记录
    const id = try std.fmt.allocPrint(allocator, "test_{d}", .{std.time.timestamp()});
    const value = std.json.Value{ .string = "test_value" };
    
    try data.put(id, value);
    std.debug.print("✅ 创建记录: {s}\n", .{id});

    // 读取记录
    if (data.get(id)) |retrieved| {
        std.debug.print("✅ 读取记录成功: {}\n", .{retrieved});
    }

    std.debug.print("🎉 测试完成！\n", .{});
}
