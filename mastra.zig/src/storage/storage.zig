const std = @import("std");

pub const StorageType = enum {
    memory,
    postgres,
    postgresql,
    sqlite,
    mongodb,
    redis,
    mysql,
    dynamodb,
    pinecone,
    custom,
};

pub const StorageConfig = struct {
    type: StorageType,
    connection_string: ?[]const u8 = null,
    database: ?[]const u8 = null,
    table_prefix: []const u8 = "mastra_",
};

pub const StorageRecord = struct {
    id: []const u8,
    data: std.json.Value,
    created_at: i64,
    updated_at: i64,

    pub fn deinit(_: *StorageRecord) void {
        // No owned memory to free in basic implementation
    }
};

pub const StorageQuery = struct {
    filters: ?std.json.Value = null,
    limit: ?usize = null,
    offset: ?usize = null,
    order_by: ?[]const u8 = null,
    order_direction: []const u8 = "ASC",
};

pub const Storage = struct {
    allocator: std.mem.Allocator,
    config: StorageConfig,
    data: std.StringHashMap(std.json.Value),
    allocated_keys: std.ArrayList([]const u8),
    next_id: u64,

    pub fn init(allocator: std.mem.Allocator, config: StorageConfig) !*Storage {
        const storage = try allocator.create(Storage);
        const data = std.StringHashMap(std.json.Value).init(allocator);
        const allocated_keys = std.ArrayList([]const u8).init(allocator);

        storage.* = Storage{
            .allocator = allocator,
            .config = config,
            .data = data,
            .allocated_keys = allocated_keys,
            .next_id = 1,
        };

        return storage;
    }

    pub fn deinit(self: *Storage) void {
        // 释放所有分配的key
        for (self.allocated_keys.items) |key| {
            self.allocator.free(key);
        }
        self.allocated_keys.deinit();

        // 清理HashMap结构
        self.data.deinit();

        // 释放Storage结构本身
        self.allocator.destroy(self);
    }

    pub fn create(self: *Storage, table: []const u8, data: std.json.Value) ![]const u8 {
        // 使用简单的计数器生成ID，避免动态内存分配
        const id = try std.fmt.allocPrint(self.allocator, "{s}_{d}", .{ table, self.next_id });
        self.next_id += 1;

        // 跟踪分配的key
        try self.allocated_keys.append(id);

        // 直接存储数据，不使用复杂的JSON对象结构
        // 这避免了复杂的内存管理问题
        try self.data.put(id, data);

        return id;
    }

    pub fn read(self: *Storage, _: []const u8, id: []const u8) !?StorageRecord {
        if (self.data.get(id)) |value| {
            // 简化版本：直接返回存储的数据
            return StorageRecord{
                .id = id,
                .data = value,
                .created_at = std.time.timestamp(),
                .updated_at = std.time.timestamp(),
            };
        }
        return null;
    }

    pub fn update(self: *Storage, _: []const u8, id: []const u8, data: std.json.Value) !bool {
        if (self.data.getPtr(id)) |existing| {
            // 直接更新数据，简化版本
            existing.* = data;
            return true;
        }
        return false;
    }

    pub fn delete(self: *Storage, _: []const u8, id: []const u8) bool {
        // 不在这里释放key的内存，让deinit统一处理
        return self.data.remove(id);
    }

    pub fn query(self: *Storage, table_name: []const u8, query_config: StorageQuery) ![]StorageRecord {
        var results = std.ArrayList(StorageRecord).init(self.allocator);
        defer results.deinit();

        var iter = self.data.iterator();
        while (iter.next()) |entry| {
            if (std.mem.startsWith(u8, entry.key_ptr.*, table_name)) {
                // 简化版本：直接使用存储的数据
                try results.append(StorageRecord{
                    .id = entry.key_ptr.*,
                    .data = entry.value_ptr.*,
                    .created_at = std.time.timestamp(),
                    .updated_at = std.time.timestamp(),
                });
            }
        }

        // Apply limit and offset
        const start = query_config.offset orelse 0;
        const end = if (query_config.limit) |limit|
            @min(start + limit, results.items.len)
        else
            results.items.len;

        if (start >= results.items.len) {
            return &[_]StorageRecord{};
        }

        // Return copy of results
        var final_results = try std.ArrayList(StorageRecord).initCapacity(self.allocator, end - start);
        for (results.items[start..end]) |result| {
            final_results.appendAssumeCapacity(result);
        }

        return final_results.toOwnedSlice();
    }

    pub fn count(self: *Storage, table_name: []const u8) usize {
        var total: usize = 0;
        var iter = self.data.iterator();
        while (iter.next()) |entry| {
            if (std.mem.startsWith(u8, entry.key_ptr.*, table_name)) {
                total += 1;
            }
        }
        return total;
    }
};
