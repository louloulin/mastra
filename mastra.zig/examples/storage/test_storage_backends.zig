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

    std.debug.print("🗄️ 存储后端综合测试\n", .{});
    std.debug.print("==================================================\n", .{});

    // 测试内存存储后端
    try testMemoryStorage(allocator);

    // 测试PostgreSQL存储后端（模拟）
    try testPostgreSQLStorage(allocator);

    // 测试MongoDB存储后端（模拟）
    try testMongoDBStorage(allocator);

    std.debug.print("\n🎉 所有存储后端测试完成！\n", .{});
    std.debug.print("==================================================\n", .{});
}

fn testMemoryStorage(allocator: std.mem.Allocator) !void {
    std.debug.print("\n1. 📝 内存存储后端测试\n", .{});
    std.debug.print("----------------------------------------\n", .{});

    const storage_config = mastra.storage.StorageConfig{
        .type = .memory,
        .table_prefix = "test_",
    };

    var storage = try mastra.storage.Storage.init(allocator, storage_config);
    defer storage.deinit();

    // 测试基本CRUD操作
    const test_data = std.json.Value{ .string = "测试数据" };
    const record_id = try storage.create("users", test_data);
    std.debug.print("   ✅ 创建记录: {s}\n", .{record_id});

    const retrieved = try storage.read("users", record_id);
    if (retrieved) |record| {
        std.debug.print("   ✅ 读取记录: {s}\n", .{record.data.string});
    }

    const updated_data = std.json.Value{ .string = "更新后的数据" };
    const update_success = try storage.update("users", record_id, updated_data);
    std.debug.print("   ✅ 更新记录: {}\n", .{update_success});

    const delete_success = storage.delete("users", record_id);
    std.debug.print("   ✅ 删除记录: {}\n", .{delete_success});

    std.debug.print("   🎯 内存存储后端测试完成\n", .{});
}

fn testPostgreSQLStorage(allocator: std.mem.Allocator) !void {
    std.debug.print("\n2. 🐘 PostgreSQL存储后端测试\n", .{});
    std.debug.print("----------------------------------------\n", .{});

    // 创建PostgreSQL配置
    const pg_config = mastra.postgresql.PostgreSQLConfig{
        .host = "localhost",
        .port = 5432,
        .database = "mastra_test",
        .username = "test_user",
        .password = "test_password",
        .max_connections = 5,
    };

    const storage_config = mastra.storage.StorageConfig{
        .type = .postgresql,
        .table_prefix = "pg_test_",
    };

    // 注意：这里是模拟测试，不需要真实的PostgreSQL连接
    std.debug.print("   📋 PostgreSQL配置:\n", .{});
    std.debug.print("      - 主机: {s}:{d}\n", .{ pg_config.host, pg_config.port });
    std.debug.print("      - 数据库: {s}\n", .{pg_config.database});
    std.debug.print("      - 用户: {s}\n", .{pg_config.username});
    std.debug.print("      - 最大连接数: {d}\n", .{pg_config.max_connections});

    // 创建PostgreSQL存储实例（模拟）
    var pg_storage = try mastra.postgresql.PostgreSQLStorage.init(allocator, storage_config, pg_config);
    defer pg_storage.deinit();

    std.debug.print("   ✅ PostgreSQL存储后端初始化成功\n", .{});

    // 测试基本操作（模拟）
    const test_data = std.json.Value{ .string = "PostgreSQL测试数据" };
    const record_id = try pg_storage.create("pg_users", test_data);
    std.debug.print("   ✅ 创建记录: {s}\n", .{record_id});

    const retrieved = try pg_storage.read("pg_users", record_id);
    if (retrieved) |record| {
        std.debug.print("   ✅ 读取记录成功\n", .{});
        _ = record;
    }

    // 测试事务功能
    var transaction = try pg_storage.beginTransaction();
    defer transaction.deinit();

    const tx_record_id = try transaction.create("pg_transactions", test_data);
    std.debug.print("   ✅ 事务中创建记录: {s}\n", .{tx_record_id});

    try transaction.commit();
    std.debug.print("   ✅ 事务提交成功\n", .{});

    std.debug.print("   🎯 PostgreSQL存储后端测试完成\n", .{});
}

fn testMongoDBStorage(allocator: std.mem.Allocator) !void {
    std.debug.print("\n3. 🍃 MongoDB存储后端测试\n", .{});
    std.debug.print("----------------------------------------\n", .{});

    // 创建MongoDB配置
    const mongo_config = mastra.mongodb.MongoDBConfig{
        .connection_string = "mongodb://localhost:27017",
        .database = "mastra_test",
        .collection_prefix = "mongo_test_",
        .max_pool_size = 10,
    };

    const storage_config = mastra.storage.StorageConfig{
        .type = .mongodb,
        .table_prefix = "mongo_test_",
    };

    std.debug.print("   📋 MongoDB配置:\n", .{});
    std.debug.print("      - 连接字符串: {s}\n", .{mongo_config.connection_string});
    std.debug.print("      - 数据库: {s}\n", .{mongo_config.database});
    std.debug.print("      - 集合前缀: {s}\n", .{mongo_config.collection_prefix});
    std.debug.print("      - 最大连接池大小: {d}\n", .{mongo_config.max_pool_size});

    // 创建MongoDB存储实例（模拟）
    var mongo_storage = try mastra.mongodb.MongoDBStorage.init(allocator, storage_config, mongo_config);
    defer mongo_storage.deinit();

    std.debug.print("   ✅ MongoDB存储后端初始化成功\n", .{});

    // 测试基本操作（模拟）
    const test_data = std.json.Value{ .string = "MongoDB测试数据" };
    const record_id = try mongo_storage.create("mongo_users", test_data);
    std.debug.print("   ✅ 创建记录: {s}\n", .{record_id});

    const retrieved = try mongo_storage.read("mongo_users", record_id);
    if (retrieved) |record| {
        std.debug.print("   ✅ 读取记录成功\n", .{});
        _ = record;
    }

    // 测试查询功能
    const query_config = mastra.storage.StorageQuery{
        .filters = null,
        .order_by = "created_at",
        .order_direction = "DESC",
        .limit = 10,
        .offset = 0,
    };

    const query_results = try mongo_storage.query("mongo_users", query_config);
    defer allocator.free(query_results);
    std.debug.print("   ✅ 查询结果: {} 条记录\n", .{query_results.len});

    // 测试索引创建
    var index_keys = mastra.mongodb.BSONDocument.init(allocator);
    defer index_keys.deinit();
    try index_keys.put("email", std.json.Value{ .integer = 1 });

    const index_options = mastra.mongodb.IndexOptions{
        .unique = true,
        .background = true,
    };

    try mongo_storage.createIndex("mongo_users", index_keys, index_options);
    std.debug.print("   ✅ 创建索引成功\n", .{});

    // 测试集合统计
    const stats = try mongo_storage.getCollectionStats("mongo_users");
    std.debug.print("   ✅ 集合统计: {} 个文档, {} 字节存储\n", .{ stats.document_count, stats.storage_size });

    std.debug.print("   🎯 MongoDB存储后端测试完成\n", .{});
}
