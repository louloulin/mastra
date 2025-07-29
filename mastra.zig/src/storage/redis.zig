const std = @import("std");
const storage = @import("storage.zig");

/// Redis connection configuration
pub const RedisConfig = struct {
    host: []const u8 = "localhost",
    port: u16 = 6379,
    database: u8 = 0,
    username: ?[]const u8 = null,
    password: ?[]const u8 = null,
    connection_string: ?[]const u8 = null,
    ssl: bool = false,
    max_connections: u32 = 10,
    connection_timeout_ms: u32 = 5000,
    command_timeout_ms: u32 = 30000,
    key_prefix: []const u8 = "mastra:",
    
    pub fn getConnectionString(self: *const RedisConfig, allocator: std.mem.Allocator) ![]const u8 {
        if (self.connection_string) |conn_str| {
            return try allocator.dupe(u8, conn_str);
        }
        
        const auth_part = if (self.password) |pwd| 
            if (self.username) |user|
                try std.fmt.allocPrint(allocator, "{s}:{s}@", .{user, pwd})
            else
                try std.fmt.allocPrint(allocator, ":{s}@", .{pwd})
        else
            try allocator.dupe(u8, "");
        defer allocator.free(auth_part);
        
        const protocol = if (self.ssl) "rediss" else "redis";
        return try std.fmt.allocPrint(allocator, "{s}://{s}{s}:{d}/{d}", .{
            protocol, auth_part, self.host, self.port, self.database
        });
    }
};

/// Redis command result
pub const RedisResult = struct {
    allocator: std.mem.Allocator,
    data: RedisValue,
    
    const Self = @This();
    
    pub fn deinit(self: *Self) void {
        self.data.deinit(self.allocator);
    }
    
    pub fn asString(self: *const Self) ?[]const u8 {
        return switch (self.data) {
            .string => |s| s,
            .bulk_string => |s| s,
            else => null,
        };
    }
    
    pub fn asInteger(self: *const Self) ?i64 {
        return switch (self.data) {
            .integer => |i| i,
            else => null,
        };
    }
    
    pub fn isOk(self: *const Self) bool {
        return switch (self.data) {
            .string => |s| std.mem.eql(u8, s, "OK"),
            .bulk_string => |s| std.mem.eql(u8, s, "OK"),
            else => false,
        };
    }
};

/// Redis value types
pub const RedisValue = union(enum) {
    string: []const u8,
    bulk_string: []const u8,
    integer: i64,
    array: []RedisValue,
    null_value,
    error_value: []const u8,
    
    pub fn deinit(self: *RedisValue, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .string => |s| allocator.free(s),
            .bulk_string => |s| allocator.free(s),
            .array => |arr| {
                for (arr) |*item| {
                    item.deinit(allocator);
                }
                allocator.free(arr);
            },
            .error_value => |s| allocator.free(s),
            else => {},
        }
    }
};

/// Redis connection wrapper
pub const RedisConnection = struct {
    allocator: std.mem.Allocator,
    config: RedisConfig,
    is_connected: bool,
    connection_string: []const u8,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, config: RedisConfig) !*Self {
        const connection = try allocator.create(Self);
        const connection_string = try config.getConnectionString(allocator);
        
        connection.* = Self{
            .allocator = allocator,
            .config = config,
            .is_connected = false,
            .connection_string = connection_string,
        };
        
        return connection;
    }
    
    pub fn deinit(self: *Self) void {
        if (self.is_connected) {
            self.close();
        }
        self.allocator.free(self.connection_string);
        self.allocator.destroy(self);
    }
    
    pub fn connect(self: *Self) !void {
        // 在真实实现中，这里会建立到Redis的TCP连接
        // 目前使用模拟实现
        std.log.info("Redis: Connecting to {s}", .{self.connection_string});
        self.is_connected = true;
    }
    
    pub fn close(self: *Self) void {
        if (self.is_connected) {
            std.log.info("Redis: Closing connection", .{});
            self.is_connected = false;
        }
    }
    
    pub fn ping(self: *Self) !RedisResult {
        if (!self.is_connected) {
            return error.NotConnected;
        }
        
        // 模拟PING命令
        const pong = try self.allocator.dupe(u8, "PONG");
        return RedisResult{
            .allocator = self.allocator,
            .data = RedisValue{ .string = pong },
        };
    }
    
    pub fn set(self: *Self, key: []const u8, value: []const u8) !RedisResult {
        if (!self.is_connected) {
            return error.NotConnected;
        }
        
        // 模拟SET命令
        std.log.debug("Redis SET: {s} = {s}", .{key, value});
        const ok = try self.allocator.dupe(u8, "OK");
        return RedisResult{
            .allocator = self.allocator,
            .data = RedisValue{ .string = ok },
        };
    }
    
    pub fn get(self: *Self, key: []const u8) !RedisResult {
        if (!self.is_connected) {
            return error.NotConnected;
        }
        
        // 模拟GET命令
        std.log.debug("Redis GET: {s}", .{key});
        
        // 模拟返回值（在真实实现中会从Redis获取）
        if (std.mem.eql(u8, key, "test_key")) {
            const value = try self.allocator.dupe(u8, "test_value");
            return RedisResult{
                .allocator = self.allocator,
                .data = RedisValue{ .bulk_string = value },
            };
        }
        
        return RedisResult{
            .allocator = self.allocator,
            .data = RedisValue.null_value,
        };
    }
    
    pub fn del(self: *Self, key: []const u8) !RedisResult {
        if (!self.is_connected) {
            return error.NotConnected;
        }
        
        // 模拟DEL命令
        std.log.debug("Redis DEL: {s}", .{key});
        return RedisResult{
            .allocator = self.allocator,
            .data = RedisValue{ .integer = 1 },
        };
    }
    
    pub fn exists(self: *Self, key: []const u8) !RedisResult {
        if (!self.is_connected) {
            return error.NotConnected;
        }
        
        // 模拟EXISTS命令
        std.log.debug("Redis EXISTS: {s}", .{key});
        const exists_count = if (std.mem.eql(u8, key, "test_key")) @as(i64, 1) else @as(i64, 0);
        return RedisResult{
            .allocator = self.allocator,
            .data = RedisValue{ .integer = exists_count },
        };
    }
    
    pub fn hset(self: *Self, key: []const u8, field: []const u8, value: []const u8) !RedisResult {
        if (!self.is_connected) {
            return error.NotConnected;
        }
        
        // 模拟HSET命令
        std.log.debug("Redis HSET: {s} {s} = {s}", .{key, field, value});
        return RedisResult{
            .allocator = self.allocator,
            .data = RedisValue{ .integer = 1 },
        };
    }
    
    pub fn hget(self: *Self, key: []const u8, field: []const u8) !RedisResult {
        if (!self.is_connected) {
            return error.NotConnected;
        }
        
        // 模拟HGET命令
        std.log.debug("Redis HGET: {s} {s}", .{key, field});
        
        // 模拟返回值
        if (std.mem.eql(u8, key, "test_hash") and std.mem.eql(u8, field, "test_field")) {
            const value = try self.allocator.dupe(u8, "test_hash_value");
            return RedisResult{
                .allocator = self.allocator,
                .data = RedisValue{ .bulk_string = value },
            };
        }
        
        return RedisResult{
            .allocator = self.allocator,
            .data = RedisValue.null_value,
        };
    }
};

/// Redis connection pool
pub const RedisConnectionPool = struct {
    allocator: std.mem.Allocator,
    config: RedisConfig,
    connections: std.ArrayList(*RedisConnection),
    available_connections: std.ArrayList(*RedisConnection),
    mutex: std.Thread.Mutex,
    is_closed: bool,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, config: RedisConfig) !*Self {
        const pool = try allocator.create(Self);
        const connections = std.ArrayList(*RedisConnection).init(allocator);
        const available_connections = std.ArrayList(*RedisConnection).init(allocator);
        
        pool.* = Self{
            .allocator = allocator,
            .config = config,
            .connections = connections,
            .available_connections = available_connections,
            .mutex = std.Thread.Mutex{},
            .is_closed = false,
        };
        
        // 初始化连接池
        try pool.initializeConnections();
        return pool;
    }
    
    pub fn deinit(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        self.is_closed = true;
        
        // 关闭所有连接
        for (self.connections.items) |conn| {
            conn.deinit();
        }
        
        self.connections.deinit();
        self.available_connections.deinit();
        self.allocator.destroy(self);
    }
    
    fn initializeConnections(self: *Self) !void {
        for (0..self.config.max_connections) |_| {
            const conn = try RedisConnection.init(self.allocator, self.config);
            try conn.connect();
            try self.connections.append(conn);
            try self.available_connections.append(conn);
        }
    }
    
    pub fn getConnection(self: *Self) !*RedisConnection {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        if (self.is_closed) {
            return error.PoolClosed;
        }
        
        if (self.available_connections.items.len == 0) {
            return error.NoAvailableConnections;
        }
        
        return self.available_connections.pop();
    }
    
    pub fn releaseConnection(self: *Self, conn: *RedisConnection) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        if (!self.is_closed) {
            self.available_connections.append(conn) catch {};
        }
    }
};

/// Redis storage implementation
pub const RedisStorage = struct {
    allocator: std.mem.Allocator,
    config: storage.StorageConfig,
    redis_config: RedisConfig,
    pool: *RedisConnectionPool,
    key_prefix: []const u8,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, config: storage.StorageConfig, redis_config: RedisConfig) !*Self {
        const redis_storage = try allocator.create(Self);
        const pool = try RedisConnectionPool.init(allocator, redis_config);
        
        redis_storage.* = Self{
            .allocator = allocator,
            .config = config,
            .redis_config = redis_config,
            .pool = pool,
            .key_prefix = redis_config.key_prefix,
        };
        
        // 初始化存储结构
        try redis_storage.initializeSchema();
        return redis_storage;
    }
    
    pub fn deinit(self: *Self) void {
        self.pool.deinit();
        self.allocator.destroy(self);
    }
    
    fn initializeSchema(self: *Self) !void {
        // Redis不需要预定义schema，但可以设置一些初始配置
        std.log.info("Redis Storage: Initializing with key prefix '{s}'", .{self.key_prefix});
    }
    
    fn getRecordKey(self: *Self, table: []const u8, id: []const u8) ![]const u8 {
        return try std.fmt.allocPrint(self.allocator, "{s}{s}:{s}", .{ self.key_prefix, table, id });
    }
    
    fn getTableKey(self: *Self, table: []const u8) ![]const u8 {
        return try std.fmt.allocPrint(self.allocator, "{s}{s}:*", .{ self.key_prefix, table });
    }
    
    pub fn create(self: *Self, table: []const u8, data: std.json.Value) ![]const u8 {
        const conn = try self.pool.getConnection();
        defer self.pool.releaseConnection(conn);
        
        // 生成唯一ID
        const timestamp = std.time.timestamp();
        const id = try std.fmt.allocPrint(self.allocator, "redis_{d}", .{timestamp});
        
        // 构建记录key
        const record_key = try self.getRecordKey(table, id);
        defer self.allocator.free(record_key);
        
        // 序列化数据
        var json_string = std.ArrayList(u8).init(self.allocator);
        defer json_string.deinit();
        try std.json.stringify(data, .{}, json_string.writer());
        
        // 创建完整记录
        const record_data = try std.fmt.allocPrint(self.allocator, 
            "{{\"id\":\"{s}\",\"data\":{s},\"created_at\":{d},\"updated_at\":{d}}}",
            .{ id, json_string.items, timestamp, timestamp }
        );
        defer self.allocator.free(record_data);
        
        // 存储到Redis
        var result = try conn.set(record_key, record_data);
        defer result.deinit();
        
        if (!result.isOk()) {
            return error.RedisSetFailed;
        }
        
        return id;
    }
    
    pub fn read(self: *Self, table: []const u8, id: []const u8) !?storage.StorageRecord {
        const conn = try self.pool.getConnection();
        defer self.pool.releaseConnection(conn);
        
        const record_key = try self.getRecordKey(table, id);
        defer self.allocator.free(record_key);
        
        var result = try conn.get(record_key);
        defer result.deinit();
        
        const data_str = result.asString() orelse return null;
        
        // 解析JSON数据
        var parsed = std.json.parseFromSlice(std.json.Value, self.allocator, data_str, .{}) catch return null;
        defer parsed.deinit();
        
        const obj = parsed.value.object;
        const record_id = obj.get("id") orelse return null;
        const record_data = obj.get("data") orelse return null;
        const created_at = obj.get("created_at") orelse return null;
        const updated_at = obj.get("updated_at") orelse return null;
        
        return storage.StorageRecord{
            .id = record_id.string,
            .data = record_data.*,
            .created_at = created_at.integer,
            .updated_at = updated_at.integer,
        };
    }
    
    pub fn update(self: *Self, table: []const u8, id: []const u8, data: std.json.Value) !bool {
        const conn = try self.pool.getConnection();
        defer self.pool.releaseConnection(conn);
        
        const record_key = try self.getRecordKey(table, id);
        defer self.allocator.free(record_key);
        
        // 检查记录是否存在
        var exists_result = try conn.exists(record_key);
        defer exists_result.deinit();
        
        if (exists_result.asInteger() orelse 0 == 0) {
            return false;
        }
        
        // 序列化新数据
        var json_string = std.ArrayList(u8).init(self.allocator);
        defer json_string.deinit();
        try std.json.stringify(data, .{}, json_string.writer());
        
        // 更新记录
        const timestamp = std.time.timestamp();
        const record_data = try std.fmt.allocPrint(self.allocator,
            "{{\"id\":\"{s}\",\"data\":{s},\"created_at\":{d},\"updated_at\":{d}}}",
            .{ id, json_string.items, timestamp, timestamp }
        );
        defer self.allocator.free(record_data);
        
        var result = try conn.set(record_key, record_data);
        defer result.deinit();
        
        return result.isOk();
    }
    
    pub fn delete(self: *Self, table: []const u8, id: []const u8) !bool {
        const conn = try self.pool.getConnection();
        defer self.pool.releaseConnection(conn);
        
        const record_key = try self.getRecordKey(table, id);
        defer self.allocator.free(record_key);
        
        var result = try conn.del(record_key);
        defer result.deinit();
        
        return (result.asInteger() orelse 0) > 0;
    }
    
    pub fn query(self: *Self, table_name: []const u8, query_config: storage.StorageQuery) ![]storage.StorageRecord {
        // Redis的查询功能有限，这里提供基本实现
        // 在真实实现中，可能需要使用Redis的SCAN命令或维护索引
        _ = self;
        _ = table_name;
        _ = query_config;
        
        // 返回空结果，实际实现需要根据具体需求来完善
        return &[_]storage.StorageRecord{};
    }
    
    pub fn count(self: *Self, table_name: []const u8) !usize {
        // Redis的计数功能，这里提供基本实现
        _ = self;
        _ = table_name;
        
        // 在真实实现中，可以使用SCAN命令计算匹配的key数量
        return 0;
    }
    
    // Redis特有的操作
    pub fn setExpire(self: *Self, table: []const u8, id: []const u8, seconds: u32) !bool {
        const conn = try self.pool.getConnection();
        defer self.pool.releaseConnection(conn);
        
        const record_key = try self.getRecordKey(table, id);
        defer self.allocator.free(record_key);
        
        // 在真实实现中，这里会调用Redis的EXPIRE命令
        std.log.debug("Redis EXPIRE: {s} {d}", .{ record_key, seconds });
        return true;
    }
    
    pub fn getTTL(self: *Self, table: []const u8, id: []const u8) !i64 {
        const conn = try self.pool.getConnection();
        defer self.pool.releaseConnection(conn);
        
        const record_key = try self.getRecordKey(table, id);
        defer self.allocator.free(record_key);
        
        // 在真实实现中，这里会调用Redis的TTL命令
        std.log.debug("Redis TTL: {s}", .{record_key});
        return -1; // -1表示没有过期时间
    }
};

/// Redis事务支持
pub const RedisTransaction = struct {
    storage: *RedisStorage,
    connection: *RedisConnection,
    is_active: bool,
    
    const Self = @This();
    
    pub fn commit(self: *Self) !void {
        if (!self.is_active) {
            return error.TransactionNotActive;
        }
        
        // 在真实实现中，这里会执行EXEC命令
        std.log.debug("Redis Transaction: EXEC", .{});
        self.storage.pool.releaseConnection(self.connection);
        self.is_active = false;
    }
    
    pub fn rollback(self: *Self) !void {
        if (!self.is_active) {
            return error.TransactionNotActive;
        }
        
        // 在真实实现中，这里会执行DISCARD命令
        std.log.debug("Redis Transaction: DISCARD", .{});
        self.storage.pool.releaseConnection(self.connection);
        self.is_active = false;
    }
    
    pub fn deinit(self: *Self) void {
        if (self.is_active) {
            self.rollback() catch {};
        }
        self.storage.allocator.destroy(self);
    }
};