const std = @import("std");

/// 高级缓存系统配置
pub const AdvancedCacheConfig = struct {
    max_size: usize = 1000,
    ttl_seconds: u64 = 3600, // 1小时默认TTL
    cleanup_interval_seconds: u64 = 300, // 5分钟清理间隔
    enable_lru: bool = true,
    enable_statistics: bool = true,
    enable_compression: bool = false,
};

/// 缓存条目
pub const CacheEntry = struct {
    key: []const u8,
    value: []const u8,
    created_at: i64,
    last_accessed: i64,
    access_count: u64,
    ttl_seconds: u64,
    compressed: bool,

    pub fn isExpired(self: *const CacheEntry, current_time: i64) bool {
        return (current_time - self.created_at) > @as(i64, @intCast(self.ttl_seconds));
    }

    pub fn updateAccess(self: *CacheEntry, current_time: i64) void {
        self.last_accessed = current_time;
        self.access_count += 1;
    }

    pub fn deinit(self: *CacheEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.key);
        allocator.free(self.value);
    }
};

/// 缓存统计信息
pub const CacheStatistics = struct {
    hits: u64 = 0,
    misses: u64 = 0,
    evictions: u64 = 0,
    expired_entries: u64 = 0,
    total_requests: u64 = 0,
    current_size: usize = 0,
    max_size_reached: u64 = 0,

    pub fn getHitRate(self: *const CacheStatistics) f64 {
        if (self.total_requests == 0) return 0.0;
        return @as(f64, @floatFromInt(self.hits)) / @as(f64, @floatFromInt(self.total_requests));
    }

    pub fn getMissRate(self: *const CacheStatistics) f64 {
        if (self.total_requests == 0) return 0.0;
        return @as(f64, @floatFromInt(self.misses)) / @as(f64, @floatFromInt(self.total_requests));
    }
};

/// 高级缓存系统
pub const AdvancedCache = struct {
    allocator: std.mem.Allocator,
    config: AdvancedCacheConfig,
    entries: std.StringHashMap(*CacheEntry),
    lru_list: std.ArrayList(*CacheEntry),
    statistics: CacheStatistics,
    mutex: std.Thread.Mutex,
    cleanup_thread: ?std.Thread,
    should_stop: std.atomic.Value(bool),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: AdvancedCacheConfig) !*Self {
        const cache = try allocator.create(Self);
        cache.* = Self{
            .allocator = allocator,
            .config = config,
            .entries = std.StringHashMap(*CacheEntry).init(allocator),
            .lru_list = std.ArrayList(*CacheEntry).init(allocator),
            .statistics = CacheStatistics{},
            .mutex = std.Thread.Mutex{},
            .cleanup_thread = null,
            .should_stop = std.atomic.Value(bool).init(false),
        };

        // 启动清理线程
        if (config.cleanup_interval_seconds > 0) {
            cache.cleanup_thread = try std.Thread.spawn(.{}, cleanupWorker, .{cache});
        }

        return cache;
    }

    pub fn deinit(self: *Self) void {
        // 停止清理线程
        self.should_stop.store(true, .release);
        if (self.cleanup_thread) |thread| {
            thread.join();
        }

        // 清理所有缓存条目
        self.mutex.lock();

        var iterator = self.entries.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.*.deinit(self.allocator);
            self.allocator.destroy(entry.value_ptr.*);
        }

        self.entries.deinit();
        self.lru_list.deinit();

        self.mutex.unlock();
        self.allocator.destroy(self);
    }

    pub fn put(self: *Self, key: []const u8, value: []const u8, ttl_seconds: ?u64) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const current_time = std.time.timestamp();

        // 检查是否已存在
        if (self.entries.get(key)) |existing_entry| {
            // 更新现有条目
            self.allocator.free(existing_entry.value);
            existing_entry.value = try self.allocator.dupe(u8, value);
            existing_entry.created_at = current_time;
            existing_entry.last_accessed = current_time;
            existing_entry.ttl_seconds = ttl_seconds orelse self.config.ttl_seconds;

            // 更新LRU位置
            if (self.config.enable_lru) {
                try self.updateLRU(existing_entry);
            }
            return;
        }

        // 检查容量限制
        if (self.entries.count() >= self.config.max_size) {
            try self.evictLRU();
            self.statistics.max_size_reached += 1;
        }

        // 创建新条目
        const entry = try self.allocator.create(CacheEntry);
        entry.* = CacheEntry{
            .key = try self.allocator.dupe(u8, key),
            .value = try self.allocator.dupe(u8, value),
            .created_at = current_time,
            .last_accessed = current_time,
            .access_count = 0,
            .ttl_seconds = ttl_seconds orelse self.config.ttl_seconds,
            .compressed = false,
        };

        // 压缩处理（如果启用）
        if (self.config.enable_compression and value.len > 1024) {
            // 简化的压缩标记，实际实现中可以使用真实的压缩算法
            entry.compressed = true;
        }

        try self.entries.put(entry.key, entry);

        if (self.config.enable_lru) {
            try self.lru_list.append(entry);
        }

        self.statistics.current_size = self.entries.count();
    }

    pub fn get(self: *Self, key: []const u8) ?[]const u8 {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.statistics.total_requests += 1;

        const entry = self.entries.get(key) orelse {
            self.statistics.misses += 1;
            return null;
        };

        const current_time = std.time.timestamp();

        // 检查是否过期
        if (entry.isExpired(current_time)) {
            _ = self.removeEntry(key) catch false;
            self.statistics.misses += 1;
            self.statistics.expired_entries += 1;
            return null;
        }

        // 更新访问信息
        entry.updateAccess(current_time);
        self.statistics.hits += 1;

        // 更新LRU位置
        if (self.config.enable_lru) {
            self.updateLRU(entry) catch {};
        }

        return entry.value;
    }

    pub fn remove(self: *Self, key: []const u8) !bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.removeEntry(key);
    }

    fn removeEntry(self: *Self, key: []const u8) !bool {
        const entry = self.entries.get(key) orelse return false;

        // 从LRU列表中移除
        if (self.config.enable_lru) {
            for (self.lru_list.items, 0..) |lru_entry, i| {
                if (lru_entry == entry) {
                    _ = self.lru_list.orderedRemove(i);
                    break;
                }
            }
        }

        // 从哈希表中移除
        _ = self.entries.remove(key);

        // 清理内存
        entry.deinit(self.allocator);
        self.allocator.destroy(entry);

        self.statistics.current_size = self.entries.count();
        return true;
    }

    fn evictLRU(self: *Self) !void {
        if (!self.config.enable_lru or self.lru_list.items.len == 0) {
            return;
        }

        // 移除最少使用的条目
        const lru_entry = self.lru_list.orderedRemove(0);
        _ = self.entries.remove(lru_entry.key);

        lru_entry.deinit(self.allocator);
        self.allocator.destroy(lru_entry);

        self.statistics.evictions += 1;
        self.statistics.current_size = self.entries.count();
    }

    fn updateLRU(self: *Self, entry: *CacheEntry) !void {
        // 找到并移除当前条目
        for (self.lru_list.items, 0..) |lru_entry, i| {
            if (lru_entry == entry) {
                _ = self.lru_list.orderedRemove(i);
                break;
            }
        }

        // 添加到末尾（最近使用）
        try self.lru_list.append(entry);
    }

    pub fn clear(self: *Self) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var iterator = self.entries.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.*.deinit(self.allocator);
            self.allocator.destroy(entry.value_ptr.*);
        }

        self.entries.clearAndFree();
        self.lru_list.clearAndFree();

        self.statistics = CacheStatistics{};
    }

    pub fn getStatistics(self: *Self) CacheStatistics {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.statistics;
    }

    pub fn cleanup(self: *Self) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const current_time = std.time.timestamp();
        var keys_to_remove = std.ArrayList([]const u8).init(self.allocator);
        defer keys_to_remove.deinit();

        // 收集过期的键
        var iterator = self.entries.iterator();
        while (iterator.next()) |entry| {
            if (entry.value_ptr.*.isExpired(current_time)) {
                try keys_to_remove.append(entry.key_ptr.*);
            }
        }

        // 移除过期条目
        for (keys_to_remove.items) |key| {
            _ = try self.removeEntry(key);
            self.statistics.expired_entries += 1;
        }
    }

    fn cleanupWorker(self: *Self) void {
        while (!self.should_stop.load(.acquire)) {
            std.time.sleep(self.config.cleanup_interval_seconds * std.time.ns_per_s);

            if (self.should_stop.load(.acquire)) break;

            self.cleanup() catch |err| {
                std.log.err("Cache cleanup error: {}", .{err});
            };
        }
    }

    pub fn getSize(self: *Self) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.entries.count();
    }

    pub fn contains(self: *Self, key: []const u8) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.entries.contains(key);
    }

    pub fn getKeys(self: *Self) ![][]const u8 {
        self.mutex.lock();
        defer self.mutex.unlock();

        var keys = try std.ArrayList([]const u8).initCapacity(self.allocator, self.entries.count());
        defer keys.deinit();

        var iterator = self.entries.keyIterator();
        while (iterator.next()) |key| {
            try keys.append(key.*);
        }

        return keys.toOwnedSlice();
    }
};

/// 分布式缓存配置
pub const DistributedCacheConfig = struct {
    nodes: [][]const u8,
    replication_factor: u32 = 2,
    consistency_level: ConsistencyLevel = .eventual,
    hash_ring_virtual_nodes: u32 = 150,

    pub const ConsistencyLevel = enum {
        eventual,
        strong,
        weak,
    };
};

/// 分布式缓存系统（架构设计）
pub const DistributedCache = struct {
    allocator: std.mem.Allocator,
    config: DistributedCacheConfig,
    local_cache: *AdvancedCache,
    hash_ring: HashRing,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: DistributedCacheConfig, local_config: AdvancedCacheConfig) !*Self {
        const cache = try allocator.create(Self);
        cache.* = Self{
            .allocator = allocator,
            .config = config,
            .local_cache = try AdvancedCache.init(allocator, local_config),
            .hash_ring = try HashRing.init(allocator, config.nodes, config.hash_ring_virtual_nodes),
        };

        return cache;
    }

    pub fn deinit(self: *Self) void {
        self.local_cache.deinit();
        self.hash_ring.deinit();
        self.allocator.destroy(self);
    }

    pub fn put(self: *Self, key: []const u8, value: []const u8, ttl_seconds: ?u64) !void {
        // 本地缓存
        try self.local_cache.put(key, value, ttl_seconds);

        // 分布式复制（简化实现）
        const target_nodes = try self.hash_ring.getNodes(key, self.config.replication_factor);
        defer self.allocator.free(target_nodes);

        for (target_nodes) |node| {
            // 在实际实现中，这里会通过网络发送到其他节点
            std.log.debug("Replicating to node: {s}", .{node});
        }
    }

    pub fn get(self: *Self, key: []const u8) ?[]const u8 {
        // 首先尝试本地缓存
        if (self.local_cache.get(key)) |value| {
            return value;
        }

        // 如果本地没有，尝试从其他节点获取（简化实现）
        const target_nodes = self.hash_ring.getNodes(key, 1) catch return null;
        defer self.allocator.free(target_nodes);

        for (target_nodes) |node| {
            // 在实际实现中，这里会通过网络从其他节点获取
            std.log.debug("Fetching from node: {s}", .{node});
        }

        return null;
    }
};

/// 一致性哈希环
pub const HashRing = struct {
    allocator: std.mem.Allocator,
    nodes: std.ArrayList([]const u8),
    virtual_nodes: std.ArrayList(VirtualNode),
    virtual_node_count: u32,

    const VirtualNode = struct {
        hash: u64,
        node: []const u8,
    };

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, nodes: [][]const u8, virtual_node_count: u32) !Self {
        var hash_ring = Self{
            .allocator = allocator,
            .nodes = std.ArrayList([]const u8).init(allocator),
            .virtual_nodes = std.ArrayList(VirtualNode).init(allocator),
            .virtual_node_count = virtual_node_count,
        };

        for (nodes) |node| {
            try hash_ring.addNode(node);
        }

        return hash_ring;
    }

    pub fn deinit(self: *Self) void {
        self.nodes.deinit();
        self.virtual_nodes.deinit();
    }

    pub fn addNode(self: *Self, node: []const u8) !void {
        try self.nodes.append(node);

        // 为每个物理节点创建虚拟节点
        var i: u32 = 0;
        while (i < self.virtual_node_count) : (i += 1) {
            const virtual_key = try std.fmt.allocPrint(self.allocator, "{s}:{d}", .{ node, i });
            defer self.allocator.free(virtual_key);

            const hash_value = self.hash(virtual_key);
            try self.virtual_nodes.append(VirtualNode{
                .hash = hash_value,
                .node = node,
            });
        }

        // 排序虚拟节点
        std.mem.sort(VirtualNode, self.virtual_nodes.items, {}, compareVirtualNodes);
    }

    pub fn getNodes(self: *Self, key: []const u8, count: u32) ![][]const u8 {
        if (self.virtual_nodes.items.len == 0) {
            return &[_][]const u8{};
        }

        const key_hash = self.hash(key);
        var result = std.ArrayList([]const u8).init(self.allocator);
        defer result.deinit();

        var added_nodes = std.StringHashMap(void).init(self.allocator);
        defer added_nodes.deinit();

        // 找到第一个大于等于key_hash的虚拟节点
        var start_index: usize = 0;
        for (self.virtual_nodes.items, 0..) |vnode, i| {
            if (vnode.hash >= key_hash) {
                start_index = i;
                break;
            }
        }

        // 从start_index开始，环形查找节点
        var i: usize = 0;
        while (result.items.len < count and i < self.virtual_nodes.items.len) : (i += 1) {
            const index = (start_index + i) % self.virtual_nodes.items.len;
            const vnode = self.virtual_nodes.items[index];

            if (!added_nodes.contains(vnode.node)) {
                try result.append(vnode.node);
                try added_nodes.put(vnode.node, {});
            }
        }

        return result.toOwnedSlice();
    }

    fn hash(self: *Self, key: []const u8) u64 {
        _ = self;
        // 简单的哈希函数，实际实现中应该使用更好的哈希算法
        var hash_value: u64 = 0;
        for (key) |byte| {
            hash_value = hash_value *% 31 +% byte;
        }
        return hash_value;
    }

    fn compareVirtualNodes(context: void, a: VirtualNode, b: VirtualNode) bool {
        _ = context;
        return a.hash < b.hash;
    }
};
