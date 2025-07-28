const std = @import("std");
const mastra = @import("mastra");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("🧪 缓存系统独立测试\n", .{});

    // 测试1: 只初始化和清理
    std.debug.print("1. 只初始化和清理测试...\n", .{});
    {
        var cache = try mastra.LRUCache.init(allocator, .{ .max_size = 3 });
        std.debug.print("   ✅ 缓存初始化成功\n", .{});

        std.debug.print("   🔄 开始清理缓存...\n", .{});
        cache.deinit();
        std.debug.print("   ✅ 缓存清理成功\n", .{});
    }

    // 测试2: 多个键值对
    std.debug.print("2. 多键值对测试...\n", .{});
    {
        var cache = try mastra.LRUCache.init(allocator, .{ .max_size = 3 });
        std.debug.print("   ✅ 缓存初始化成功\n", .{});

        try cache.put("key1", "value1");
        try cache.put("key2", "value2");
        try cache.put("key3", "value3");
        std.debug.print("   ✅ 插入3个键值对成功\n", .{});

        std.debug.print("   🔄 开始清理缓存...\n", .{});
        cache.deinit();
        std.debug.print("   ✅ 缓存清理成功\n", .{});
    }

    // 测试3: LRU淘汰
    std.debug.print("3. LRU淘汰测试...\n", .{});
    {
        var cache = try mastra.LRUCache.init(allocator, .{ .max_size = 2 });
        std.debug.print("   ✅ 缓存初始化成功\n", .{});

        try cache.put("key1", "value1");
        try cache.put("key2", "value2");
        std.debug.print("   ✅ 插入2个键值对成功\n", .{});

        // 这应该触发LRU淘汰
        try cache.put("key3", "value3");
        std.debug.print("   ✅ 插入第3个键值对成功（应该淘汰key1）\n", .{});

        // 检查key1是否被淘汰
        if (cache.get("key1")) |_| {
            std.debug.print("   ⚠️  key1仍然存在（可能有问题）\n", .{});
        } else {
            std.debug.print("   ✅ key1已被正确淘汰\n", .{});
        }

        std.debug.print("   🔄 开始清理缓存...\n", .{});
        cache.deinit();
        std.debug.print("   ✅ 缓存清理成功\n", .{});
    }

    std.debug.print("\n🎉 缓存系统独立测试完成！\n", .{});
}
