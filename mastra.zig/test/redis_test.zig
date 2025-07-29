const std = @import("std");
const testing = std.testing;
const mastra = @import("mastra");

test "Redis storage basic operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 配置Redis存储
    const storage_config = mastra.StorageConfig{
        .type = .redis,
        .database = "test_db",
        .table_prefix = "test_",
    };

    const redis_config = mastra.RedisConfig{
        .host = "localhost",
        .port = 6379,
        .database = 0,
        .key_prefix = "mastra_test:",
    };

    // 初始化Redis存储
    var redis_storage = try mastra.RedisStorage.init(allocator, storage_config, redis_config);
    defer redis_storage.deinit();

    // 测试数据
    const test_data = std.json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };
    defer {
        var obj = test_data.object;
        obj.deinit();
    }

    var obj = test_data.object;
    try obj.put("name", std.json.Value{ .string = "test_user" });
    try obj.put("age", std.json.Value{ .integer = 25 });

    // 测试创建记录
    const record_id = try redis_storage.create("users", test_data);
    try testing.expect(record_id.len > 0);
    std.debug.print("✓ Redis创建记录成功，ID: {s}\n", .{record_id});

    // 测试读取记录
    const record = try redis_storage.read("users", record_id);
    try testing.expect(record != null);
    if (record) |r| {
        try testing.expectEqualStrings(record_id, r.id);
        std.debug.print("✓ Redis读取记录成功\n", .{});
    }

    // 测试更新记录
    var updated_obj = std.json.ObjectMap.init(allocator);
    defer updated_obj.deinit();
    try updated_obj.put("name", std.json.Value{ .string = "updated_user" });
    try updated_obj.put("age", std.json.Value{ .integer = 30 });
    
    const updated_data = std.json.Value{ .object = updated_obj };
    const update_result = try redis_storage.update("users", record_id, updated_data);
    try testing.expect(update_result);
    std.debug.print("✓ Redis更新记录成功\n", .{});

    // 测试删除记录
    const delete_result = try redis_storage.delete("users", record_id);
    try testing.expect(delete_result);
    std.debug.print("✓ Redis删除记录成功\n", .{});

    // 验证记录已删除
    const deleted_record = try redis_storage.read("users", record_id);
    try testing.expect(deleted_record == null);
    std.debug.print("✓ Redis记录删除验证成功\n", .{});
}

test "Redis connection and basic commands" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const redis_config = mastra.RedisConfig{
        .host = "localhost",
        .port = 6379,
        .database = 0,
    };

    // 测试Redis连接
    var connection = try mastra.redis.RedisConnection.init(allocator, redis_config);
    defer connection.deinit();

    try connection.connect();
    std.debug.print("✓ Redis连接成功\n", .{});

    // 测试PING命令
    var ping_result = try connection.ping();
    defer ping_result.deinit();
    
    const pong = ping_result.asString();
    try testing.expect(pong != null);
    try testing.expectEqualStrings("PONG", pong.?);
    std.debug.print("✓ Redis PING命令成功\n", .{});

    // 测试SET/GET命令
    var set_result = try connection.set("test_key", "test_value");
    defer set_result.deinit();
    try testing.expect(set_result.isOk());
    std.debug.print("✓ Redis SET命令成功\n", .{});

    var get_result = try connection.get("test_key");
    defer get_result.deinit();
    const value = get_result.asString();
    try testing.expect(value != null);
    try testing.expectEqualStrings("test_value", value.?);
    std.debug.print("✓ Redis GET命令成功\n", .{});

    // 测试DEL命令
    var del_result = try connection.del("test_key");
    defer del_result.deinit();
    const deleted_count = del_result.asInteger();
    try testing.expect(deleted_count != null);
    try testing.expect(deleted_count.? == 1);
    std.debug.print("✓ Redis DEL命令成功\n", .{});

    // 测试EXISTS命令
    var exists_result = try connection.exists("test_key");
    defer exists_result.deinit();
    const exists_count = exists_result.asInteger();
    try testing.expect(exists_count != null);
    try testing.expect(exists_count.? == 0);
    std.debug.print("✓ Redis EXISTS命令成功\n", .{});
}

test "Redis connection pool" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const redis_config = mastra.RedisConfig{
        .host = "localhost",
        .port = 6379,
        .database = 0,
        .max_connections = 5,
    };

    // 测试连接池
    var pool = try mastra.redis.RedisConnectionPool.init(allocator, redis_config);
    defer pool.deinit();

    std.debug.print("✓ Redis连接池初始化成功\n", .{});

    // 获取连接
    var conn1 = try pool.getConnection();
    var conn2 = try pool.getConnection();
    
    // 测试连接
    var ping1 = try conn1.ping();
    defer ping1.deinit();
    try testing.expect(ping1.asString() != null);
    
    var ping2 = try conn2.ping();
    defer ping2.deinit();
    try testing.expect(ping2.asString() != null);
    
    std.debug.print("✓ Redis连接池连接测试成功\n", .{});

    // 释放连接
    pool.releaseConnection(conn1);
    pool.releaseConnection(conn2);
    
    std.debug.print("✓ Redis连接池释放连接成功\n", .{});
}

test "Redis hash operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const redis_config = mastra.RedisConfig{
        .host = "localhost",
        .port = 6379,
        .database = 0,
    };

    var connection = try mastra.redis.RedisConnection.init(allocator, redis_config);
    defer connection.deinit();

    try connection.connect();

    // 测试HSET命令
    var hset_result = try connection.hset("test_hash", "test_field", "test_hash_value");
    defer hset_result.deinit();
    const set_count = hset_result.asInteger();
    try testing.expect(set_count != null);
    try testing.expect(set_count.? == 1);
    std.debug.print("✓ Redis HSET命令成功\n", .{});

    // 测试HGET命令
    var hget_result = try connection.hget("test_hash", "test_field");
    defer hget_result.deinit();
    const hash_value = hget_result.asString();
    try testing.expect(hash_value != null);
    try testing.expectEqualStrings("test_hash_value", hash_value.?);
    std.debug.print("✓ Redis HGET命令成功\n", .{});
}

test "Redis storage TTL operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const storage_config = mastra.StorageConfig{
        .type = .redis,
        .database = "test_db",
        .table_prefix = "test_",
    };

    const redis_config = mastra.RedisConfig{
        .host = "localhost",
        .port = 6379,
        .database = 0,
        .key_prefix = "mastra_ttl_test:",
    };

    var redis_storage = try mastra.RedisStorage.init(allocator, storage_config, redis_config);
    defer redis_storage.deinit();

    // 创建测试记录
    const test_data = std.json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };
    defer {
        var obj = test_data.object;
        obj.deinit();
    }

    var obj = test_data.object;
    try obj.put("temp_data", std.json.Value{ .string = "expires_soon" });

    const record_id = try redis_storage.create("temp_records", test_data);
    std.debug.print("✓ Redis TTL测试记录创建成功\n", .{});

    // 设置过期时间
    const expire_result = try redis_storage.setExpire("temp_records", record_id, 60);
    try testing.expect(expire_result);
    std.debug.print("✓ Redis设置过期时间成功\n", .{});

    // 获取TTL
    const ttl = try redis_storage.getTTL("temp_records", record_id);
    try testing.expect(ttl >= -1); // -1表示没有过期时间，>=0表示剩余秒数
    std.debug.print("✓ Redis获取TTL成功: {d}\n", .{ttl});
}