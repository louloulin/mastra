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

    std.debug.print("🚀 高级缓存系统测试\n", .{});
    std.debug.print("==================================================\n", .{});

    // 测试基本缓存功能
    try testBasicCacheOperations(allocator);

    // 测试LRU淘汰策略
    try testLRUEviction(allocator);

    // 测试TTL过期机制
    try testTTLExpiration(allocator);

    // 测试缓存统计
    try testCacheStatistics(allocator);

    // 测试分布式缓存架构
    try testDistributedCacheArchitecture(allocator);

    std.debug.print("\n🎉 高级缓存系统测试完成！\n", .{});
    std.debug.print("==================================================\n", .{});
}

fn testBasicCacheOperations(allocator: std.mem.Allocator) !void {
    std.debug.print("\n1. 📝 基本缓存操作测试\n", .{});
    std.debug.print("----------------------------------------\n", .{});

    const config = mastra.utils.AdvancedCacheConfig{
        .max_size = 100,
        .ttl_seconds = 3600,
        .cleanup_interval_seconds = 0, // 禁用自动清理以便测试
        .enable_lru = true,
        .enable_statistics = true,
    };

    var cache = try mastra.utils.AdvancedCache.init(allocator, config);
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

    std.debug.print("   ✅ 缓存大小: {}\n", .{cache.getSize()});
    std.debug.print("   🎯 基本缓存操作测试完成\n", .{});
}

fn testLRUEviction(allocator: std.mem.Allocator) !void {
    std.debug.print("\n2. 🔄 LRU淘汰策略测试\n", .{});
    std.debug.print("----------------------------------------\n", .{});

    const config = mastra.utils.AdvancedCacheConfig{
        .max_size = 3, // 小容量以测试淘汰
        .ttl_seconds = 3600,
        .cleanup_interval_seconds = 0,
        .enable_lru = true,
        .enable_statistics = true,
    };

    var cache = try mastra.utils.AdvancedCache.init(allocator, config);
    defer cache.deinit();

    // 填满缓存
    try cache.put("key1", "value1", null);
    try cache.put("key2", "value2", null);
    try cache.put("key3", "value3", null);
    std.debug.print("   ✅ 填满缓存 (3/3)\n", .{});

    // 访问key1使其成为最近使用
    _ = cache.get("key1");
    std.debug.print("   ✅ 访问key1，更新LRU状态\n", .{});

    // 添加新条目，应该淘汰key2（最少使用）
    try cache.put("key4", "value4", null);
    std.debug.print("   ✅ 添加key4，触发LRU淘汰\n", .{});

    // 验证淘汰结果
    if (cache.get("key1")) |_| {
        std.debug.print("   ✅ key1仍然存在（最近访问）\n", .{});
    } else {
        std.debug.print("   ❌ key1不应该被淘汰\n", .{});
    }

    if (cache.get("key2")) |_| {
        std.debug.print("   ❌ key2应该被淘汰\n", .{});
    } else {
        std.debug.print("   ✅ key2正确被淘汰（LRU）\n", .{});
    }

    if (cache.get("key4")) |_| {
        std.debug.print("   ✅ key4成功添加\n", .{});
    } else {
        std.debug.print("   ❌ key4应该存在\n", .{});
    }

    const stats = cache.getStatistics();
    std.debug.print("   ✅ 淘汰次数: {}\n", .{stats.evictions});
    std.debug.print("   🎯 LRU淘汰策略测试完成\n", .{});
}

fn testTTLExpiration(allocator: std.mem.Allocator) !void {
    std.debug.print("\n3. ⏰ TTL过期机制测试\n", .{});
    std.debug.print("----------------------------------------\n", .{});

    const config = mastra.utils.AdvancedCacheConfig{
        .max_size = 100,
        .ttl_seconds = 1, // 1秒TTL用于测试
        .cleanup_interval_seconds = 0,
        .enable_lru = true,
        .enable_statistics = true,
    };

    var cache = try mastra.utils.AdvancedCache.init(allocator, config);
    defer cache.deinit();

    // 添加短TTL条目
    try cache.put("short_ttl", "expires_soon", 1);
    try cache.put("long_ttl", "expires_later", 10);
    std.debug.print("   ✅ 添加不同TTL的条目\n", .{});

    // 立即获取应该成功
    if (cache.get("short_ttl")) |value| {
        std.debug.print("   ✅ 立即获取short_ttl: {s}\n", .{value});
    }

    // 等待过期
    std.debug.print("   ⏳ 等待1.5秒让short_ttl过期...\n", .{});
    std.time.sleep(1500 * std.time.ns_per_ms);

    // 尝试获取过期条目
    if (cache.get("short_ttl")) |_| {
        std.debug.print("   ❌ short_ttl应该已过期\n", .{});
    } else {
        std.debug.print("   ✅ short_ttl正确过期\n", .{});
    }

    // 长TTL条目应该仍然存在
    if (cache.get("long_ttl")) |value| {
        std.debug.print("   ✅ long_ttl仍然有效: {s}\n", .{value});
    } else {
        std.debug.print("   ❌ long_ttl不应该过期\n", .{});
    }

    // 测试手动清理
    try cache.cleanup();
    const stats = cache.getStatistics();
    std.debug.print("   ✅ 过期条目数: {}\n", .{stats.expired_entries});
    std.debug.print("   🎯 TTL过期机制测试完成\n", .{});
}

fn testCacheStatistics(allocator: std.mem.Allocator) !void {
    std.debug.print("\n4. 📊 缓存统计测试\n", .{});
    std.debug.print("----------------------------------------\n", .{});

    const config = mastra.utils.AdvancedCacheConfig{
        .max_size = 10,
        .ttl_seconds = 3600,
        .cleanup_interval_seconds = 0,
        .enable_lru = true,
        .enable_statistics = true,
    };

    var cache = try mastra.utils.AdvancedCache.init(allocator, config);
    defer cache.deinit();

    // 执行各种操作以生成统计数据
    try cache.put("stat1", "value1", null);
    try cache.put("stat2", "value2", null);
    try cache.put("stat3", "value3", null);

    // 命中测试
    _ = cache.get("stat1"); // 命中
    _ = cache.get("stat2"); // 命中
    _ = cache.get("nonexistent1"); // 未命中
    _ = cache.get("nonexistent2"); // 未命中
    _ = cache.get("stat1"); // 再次命中

    const stats = cache.getStatistics();
    std.debug.print("   📈 缓存统计信息:\n", .{});
    std.debug.print("      总请求数: {}\n", .{stats.total_requests});
    std.debug.print("      命中数: {}\n", .{stats.hits});
    std.debug.print("      未命中数: {}\n", .{stats.misses});
    std.debug.print("      命中率: {d:.2}%\n", .{stats.getHitRate() * 100});
    std.debug.print("      未命中率: {d:.2}%\n", .{stats.getMissRate() * 100});
    std.debug.print("      当前大小: {}\n", .{stats.current_size});
    std.debug.print("      淘汰次数: {}\n", .{stats.evictions});
    std.debug.print("      过期条目: {}\n", .{stats.expired_entries});

    // 验证统计数据的正确性
    if (stats.hits >= 3 and stats.misses >= 2) {
        std.debug.print("   ✅ 统计数据正确\n", .{});
    } else {
        std.debug.print("   ❌ 统计数据异常\n", .{});
    }

    std.debug.print("   🎯 缓存统计测试完成\n", .{});
}

fn testDistributedCacheArchitecture(allocator: std.mem.Allocator) !void {
    std.debug.print("\n5. 🌐 分布式缓存架构测试\n", .{});
    std.debug.print("----------------------------------------\n", .{});

    // 测试一致性哈希环
    const nodes = [_][]const u8{ "node1:8080", "node2:8080", "node3:8080" };
    var hash_ring = try mastra.utils.HashRing.init(allocator, &nodes, 150);
    defer hash_ring.deinit();

    std.debug.print("   ✅ 创建一致性哈希环，3个节点，150个虚拟节点\n", .{});

    // 测试键分布
    const test_keys = [_][]const u8{ "user:1001", "user:1002", "user:1003", "session:abc123", "cache:data1" };

    for (test_keys) |key| {
        const target_nodes = try hash_ring.getNodes(key, 2);
        defer allocator.free(target_nodes);

        std.debug.print("   ✅ 键 '{s}' 映射到节点: ", .{key});
        for (target_nodes, 0..) |node, i| {
            if (i > 0) std.debug.print(", ", .{});
            std.debug.print("{s}", .{node});
        }
        std.debug.print("\n", .{});
    }

    // 测试分布式缓存配置
    const dist_config = mastra.utils.DistributedCacheConfig{
        .nodes = &nodes,
        .replication_factor = 2,
        .consistency_level = .eventual,
        .hash_ring_virtual_nodes = 150,
    };

    const local_config = mastra.utils.AdvancedCacheConfig{
        .max_size = 1000,
        .ttl_seconds = 3600,
        .cleanup_interval_seconds = 0,
        .enable_lru = true,
        .enable_statistics = true,
    };

    var dist_cache = try mastra.utils.DistributedCache.init(allocator, dist_config, local_config);
    defer dist_cache.deinit();

    std.debug.print("   ✅ 创建分布式缓存实例\n", .{});

    // 测试分布式操作（模拟）
    try dist_cache.put("distributed_key1", "distributed_value1", null);
    try dist_cache.put("distributed_key2", "distributed_value2", null);

    std.debug.print("   ✅ 分布式缓存put操作完成\n", .{});

    if (dist_cache.get("distributed_key1")) |value| {
        std.debug.print("   ✅ 分布式缓存get操作: {s}\n", .{value});
    } else {
        std.debug.print("   ⚠️ 分布式缓存get操作（本地未命中，需要网络获取）\n", .{});
    }

    std.debug.print("   ✅ 分布式缓存架构验证完成\n", .{});
    std.debug.print("   📋 架构特性:\n", .{});
    std.debug.print("      - 一致性哈希环负载均衡\n", .{});
    std.debug.print("      - 多节点数据复制\n", .{});
    std.debug.print("      - 本地缓存 + 分布式缓存\n", .{});
    std.debug.print("      - 虚拟节点提高分布均匀性\n", .{});

    std.debug.print("   🎯 分布式缓存架构测试完成\n", .{});
}
