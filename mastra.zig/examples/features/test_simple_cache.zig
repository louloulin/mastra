const std = @import("std");
const mastra = @import("mastra");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("❌ 检测到内存泄漏！\n", .{});
        } else {
            std.debug.print("✅ 无内存泄漏！\n", .{});
        }
    }
    const allocator = gpa.allocator();

    std.debug.print("🚀 简化缓存系统测试\n", .{});
    std.debug.print("==================================================\n", .{});

    // 测试基本缓存功能
    try testBasicCacheOperations(allocator);

    std.debug.print("\n🎉 简化缓存系统测试完成！\n", .{});
    std.debug.print("==================================================\n", .{});
}

fn testBasicCacheOperations(allocator: std.mem.Allocator) !void {
    std.debug.print("\n1. 📝 基本缓存操作测试\n", .{});
    std.debug.print("----------------------------------------\n", .{});

    const config = mastra.advanced_cache.AdvancedCacheConfig{
        .max_size = 100,
        .ttl_seconds = 3600,
        .cleanup_interval_seconds = 0, // 禁用自动清理以便测试
        .enable_lru = true,
        .enable_statistics = true,
    };

    var cache = try mastra.advanced_cache.AdvancedCache.init(allocator, config);
    defer cache.deinit();

    // 测试基本的put/get操作
    try cache.put("key1", "value1", null);
    try cache.put("key2", "value2", null);
    try cache.put("key3", "value3", null);

    std.debug.print("   ✅ 添加3个缓存条目\n", .{});

    // 测试获取
    if (cache.get("key1")) |value| {
        std.debug.print("   ✅ 获取key1: {s}\n", .{value});
    }

    if (cache.get("key2")) |value| {
        std.debug.print("   ✅ 获取key2: {s}\n", .{value});
    }

    // 测试不存在的键
    if (cache.get("nonexistent")) |_| {
        std.debug.print("   ❌ 不应该找到不存在的键\n", .{});
    } else {
        std.debug.print("   ✅ 正确处理不存在的键\n", .{});
    }

    // 测试更新
    try cache.put("key1", "updated_value1", null);
    if (cache.get("key1")) |value| {
        std.debug.print("   ✅ 更新key1: {s}\n", .{value});
    }

    // 测试删除
    const removed = try cache.remove("key2");
    std.debug.print("   ✅ 删除key2: {}\n", .{removed});

    if (cache.get("key2")) |_| {
        std.debug.print("   ❌ 删除后不应该找到key2\n", .{});
    } else {
        std.debug.print("   ✅ 删除后正确处理key2\n", .{});
    }

    // 测试统计信息
    const stats = cache.getStatistics();
    std.debug.print("   📊 缓存统计:\n", .{});
    std.debug.print("      总请求数: {}\n", .{stats.total_requests});
    std.debug.print("      命中数: {}\n", .{stats.hits});
    std.debug.print("      未命中数: {}\n", .{stats.misses});
    std.debug.print("      命中率: {d:.2}%\n", .{stats.getHitRate() * 100});
    std.debug.print("      当前大小: {}\n", .{cache.getSize()});

    std.debug.print("   🎯 基本缓存操作测试完成\n", .{});
}
