//! 缓存系统 - LRU缓存实现
//!
//! 支持：
//! - LRU (Least Recently Used) 缓存策略
//! - 线程安全操作
//! - 自动过期
//! - 内存限制

const std = @import("std");

/// 缓存错误类型
pub const CacheError = error{
    KeyNotFound,
    CacheFull,
    OutOfMemory,
};

/// 缓存项
pub const CacheItem = struct {
    key: []const u8,
    value: []const u8,
    timestamp: i64,
    access_count: u32,
    prev: ?*CacheItem,
    next: ?*CacheItem,

    pub fn init(allocator: std.mem.Allocator, key: []const u8, value: []const u8) !*CacheItem {
        const item = try allocator.create(CacheItem);
        item.* = CacheItem{
            .key = try allocator.dupe(u8, key),
            .value = try allocator.dupe(u8, value),
            .timestamp = std.time.timestamp(),
            .access_count = 1,
            .prev = null,
            .next = null,
        };
        return item;
    }

    pub fn deinit(self: *CacheItem, allocator: std.mem.Allocator) void {
        allocator.free(self.key);
        allocator.free(self.value);
        allocator.destroy(self);
    }

    pub fn isExpired(self: *const CacheItem, ttl_seconds: i64) bool {
        const now = std.time.timestamp();
        return (now - self.timestamp) > ttl_seconds;
    }
};

/// LRU缓存配置
pub const CacheConfig = struct {
    max_size: usize = 1000,
    ttl_seconds: i64 = 3600, // 1小时
    cleanup_interval_seconds: i64 = 300, // 5分钟
};

/// LRU缓存实现
pub const LRUCache = struct {
    allocator: std.mem.Allocator,
    config: CacheConfig,
    items: std.StringHashMap(*CacheItem),
    head: ?*CacheItem,
    tail: ?*CacheItem,
    size: usize,
    mutex: std.Thread.RwLock,
    last_cleanup: i64,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: CacheConfig) !*Self {
        const cache = try allocator.create(Self);
        cache.* = Self{
            .allocator = allocator,
            .config = config,
            .items = std.StringHashMap(*CacheItem).init(allocator),
            .head = null,
            .tail = null,
            .size = 0,
            .mutex = std.Thread.RwLock{},
            .last_cleanup = std.time.timestamp(),
        };
        return cache;
    }

    pub fn deinit(self: *Self) void {
        // 不使用mutex，因为在deinit时不应该有并发访问

        // 简化清理：只清理CacheItem，让HashMap自己管理key
        var iter = self.items.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.*.deinit(self.allocator);
        }
        self.items.deinit();
        self.allocator.destroy(self);
    }

    /// 获取缓存项
    pub fn get(self: *Self, key: []const u8) ?[]const u8 {
        self.mutex.lockShared();
        defer self.mutex.unlockShared();

        if (self.items.get(key)) |item| {
            // 检查是否过期
            if (item.isExpired(self.config.ttl_seconds)) {
                return null;
            }

            // 更新访问信息
            item.access_count += 1;
            item.timestamp = std.time.timestamp();

            // 移动到头部（最近使用）
            self.moveToHead(item);

            return item.value;
        }
        return null;
    }

    /// 设置缓存项
    pub fn put(self: *Self, key: []const u8, value: []const u8) CacheError!void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // 检查是否需要清理过期项
        try self.cleanupIfNeeded();

        if (self.items.get(key)) |existing_item| {
            // 更新现有项
            self.allocator.free(existing_item.value);
            existing_item.value = self.allocator.dupe(u8, value) catch return CacheError.OutOfMemory;
            existing_item.timestamp = std.time.timestamp();
            existing_item.access_count += 1;
            self.moveToHead(existing_item);
        } else {
            // 添加新项
            if (self.size >= self.config.max_size) {
                try self.evictLRU();
            }

            const new_item = CacheItem.init(self.allocator, key, value) catch return CacheError.OutOfMemory;
            // 使用CacheItem的key作为HashMap的key（避免重复分配）
            self.items.put(new_item.key, new_item) catch return CacheError.OutOfMemory;
            self.addToHead(new_item);
            self.size += 1;
        }
    }

    /// 删除缓存项
    pub fn remove(self: *Self, key: []const u8) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.items.fetchRemove(key)) |kv| {
            const item = kv.value;
            self.removeFromList(item);
            item.deinit(self.allocator);
            self.size -= 1;
            return true;
        }
        return false;
    }

    /// 清空缓存
    pub fn clear(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var iter = self.items.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.*.deinit(self.allocator);
        }
        self.items.clearAndFree();
        self.head = null;
        self.tail = null;
        self.size = 0;
    }

    /// 获取缓存统计信息
    pub fn getStats(self: *Self) CacheStats {
        self.mutex.lockShared();
        defer self.mutex.unlockShared();

        return CacheStats{
            .size = self.size,
            .max_size = self.config.max_size,
            .hit_rate = 0.0, // 需要额外跟踪命中率
        };
    }

    // 私有方法
    fn moveToHead(self: *Self, item: *CacheItem) void {
        if (self.head == item) return;

        self.removeFromList(item);
        self.addToHead(item);
    }

    fn addToHead(self: *Self, item: *CacheItem) void {
        item.prev = null;
        item.next = self.head;

        if (self.head) |head| {
            head.prev = item;
        }
        self.head = item;

        if (self.tail == null) {
            self.tail = item;
        }
    }

    fn removeFromList(self: *Self, item: *CacheItem) void {
        if (item.prev) |prev| {
            prev.next = item.next;
        } else {
            self.head = item.next;
        }

        if (item.next) |next| {
            next.prev = item.prev;
        } else {
            self.tail = item.prev;
        }
    }

    fn evictLRU(self: *Self) CacheError!void {
        if (self.tail) |tail_item| {
            _ = self.items.remove(tail_item.key);
            self.removeFromList(tail_item);
            tail_item.deinit(self.allocator);
            self.size -= 1;
        }
    }

    fn cleanupIfNeeded(self: *Self) CacheError!void {
        const now = std.time.timestamp();
        if (now - self.last_cleanup < self.config.cleanup_interval_seconds) {
            return;
        }

        // 清理过期项
        var to_remove = std.ArrayList([]const u8).init(self.allocator);
        defer to_remove.deinit();

        var iter = self.items.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.*.isExpired(self.config.ttl_seconds)) {
                try to_remove.append(entry.key_ptr.*);
            }
        }

        for (to_remove.items) |key| {
            _ = self.remove(key);
        }

        self.last_cleanup = now;
    }
};

/// 缓存统计信息
pub const CacheStats = struct {
    size: usize,
    max_size: usize,
    hit_rate: f32,
};

// 测试
test "LRU Cache basic operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var cache = try LRUCache.init(allocator, .{ .max_size = 3 });
    defer cache.deinit();

    // 测试设置和获取
    try cache.put("key1", "value1");
    try cache.put("key2", "value2");
    try cache.put("key3", "value3");

    try std.testing.expectEqualStrings("value1", cache.get("key1").?);
    try std.testing.expectEqualStrings("value2", cache.get("key2").?);
    try std.testing.expectEqualStrings("value3", cache.get("key3").?);

    // 测试LRU淘汰
    try cache.put("key4", "value4");
    try std.testing.expect(cache.get("key1") == null); // key1应该被淘汰

    // 测试删除
    try std.testing.expect(cache.remove("key2"));
    try std.testing.expect(cache.get("key2") == null);
}
