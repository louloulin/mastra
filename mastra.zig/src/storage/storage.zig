const std = @import("std");

pub const StorageType = enum {
    memory,
    postgres,
    sqlite,
    mongodb,
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

    pub fn init(allocator: std.mem.Allocator, config: StorageConfig) !*Storage {
        const storage = try allocator.create(Storage);
        const data = std.StringHashMap(std.json.Value).init(allocator);

        storage.* = Storage{
            .allocator = allocator,
            .config = config,
            .data = data,
        };

        return storage;
    }

    pub fn deinit(self: *Storage) void {
        // 正确清理HashMap中的所有内存
        var iter = self.data.iterator();
        while (iter.next()) |entry| {
            // 释放key字符串（由allocPrint分配）
            self.allocator.free(entry.key_ptr.*);

            // 释放JSON对象中的内存
            if (entry.value_ptr.* == .object) {
                // 注意：不要释放object中的字符串，因为id字符串和key是同一个
                // 只需要清理object本身
                entry.value_ptr.object.deinit();
            }
        }

        self.data.deinit();
        self.allocator.destroy(self);
    }

    pub fn create(self: *Storage, table: []const u8, data: std.json.Value) ![]const u8 {
        const id = try std.fmt.allocPrint(self.allocator, "{s}_{d}", .{ table, std.time.timestamp() });

        var record = std.json.ObjectMap.init(self.allocator);
        try record.put("id", std.json.Value{ .string = id });
        try record.put("data", data);
        try record.put("created_at", std.json.Value{ .integer = @intCast(std.time.timestamp()) });
        try record.put("updated_at", std.json.Value{ .integer = @intCast(std.time.timestamp()) });

        try self.data.put(id, std.json.Value{ .object = record });

        return id;
    }

    pub fn read(self: *Storage, _: []const u8, id: []const u8) !?StorageRecord {
        if (self.data.get(id)) |value| {
            if (value == .object) {
                const obj = value.object;

                const record_id = obj.get("id") orelse return null;
                const record_data = obj.get("data") orelse return null;
                const created_at = obj.get("created_at") orelse return null;
                const updated_at = obj.get("updated_at") orelse return null;

                return StorageRecord{
                    .id = record_id.string,
                    .data = record_data,
                    .created_at = created_at.integer,
                    .updated_at = updated_at.integer,
                };
            }
        }
        return null;
    }

    pub fn update(self: *Storage, _: []const u8, id: []const u8, data: std.json.Value) !bool {
        if (self.data.getPtr(id)) |existing| {
            if (existing.* == .object) {
                var obj = &existing.*.object;

                try obj.put("data", data);
                try obj.put("updated_at", std.json.Value{ .integer = @intCast(std.time.timestamp()) });

                return true;
            }
        }
        return false;
    }

    pub fn delete(self: *Storage, _: []const u8, id: []const u8) bool {
        return self.data.remove(id);
    }

    pub fn query(self: *Storage, table_name: []const u8, query_config: StorageQuery) ![]StorageRecord {
        var results = std.ArrayList(StorageRecord).init(self.allocator);
        defer results.deinit();

        var iter = self.data.iterator();
        while (iter.next()) |entry| {
            if (std.mem.startsWith(u8, entry.key_ptr.*, table_name)) {
                if (entry.value_ptr.* == .object) {
                    const obj = entry.value_ptr.*.object;

                    const record_id = obj.get("id") orelse continue;
                    const record_data = obj.get("data") orelse continue;
                    const created_at = obj.get("created_at") orelse continue;
                    const updated_at = obj.get("updated_at") orelse continue;

                    try results.append(StorageRecord{
                        .id = record_id.string,
                        .data = record_data.*,
                        .created_at = created_at.integer,
                        .updated_at = updated_at.integer,
                    });
                }
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
