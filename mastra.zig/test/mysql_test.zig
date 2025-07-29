const std = @import("std");
const testing = std.testing;
const mastra = @import("mastra");

test "MySQL storage basic operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // 配置MySQL存储
    const storage_config = mastra.StorageConfig{
        .type = .mysql,
        .table_prefix = "test_",
    };
    
    const mysql_config = mastra.MySQLConfig{
        .host = "localhost",
        .port = 3306,
        .database = "test_db",
        .username = "test_user",
        .password = "test_pass",
    };
    
    // 初始化MySQL存储
    const mysql_storage = try mastra.MySQLStorage.init(allocator, storage_config, mysql_config);
    defer mysql_storage.deinit();
    
    // 测试数据
    const test_data = std.json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };
    
    // 测试创建记录
    const record_id = try mysql_storage.create("users", test_data);
    defer allocator.free(record_id);
    try testing.expect(record_id.len > 0);
    
    // 测试读取记录
    const read_result = try mysql_storage.read("users", record_id);
    try testing.expect(read_result != null);
    
    // 测试更新记录
    const update_result = try mysql_storage.update("users", record_id, test_data);
    try testing.expect(update_result == true);
    
    // 测试计数
    const count = try mysql_storage.count("users");
    try testing.expect(count >= 0);
    
    // 测试删除记录
    const delete_result = try mysql_storage.delete("users", record_id);
    try testing.expect(delete_result == true);
}

test "MySQL connection and basic commands" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const mysql_config = mastra.MySQLConfig{
        .host = "localhost",
        .port = 3306,
        .database = "test_db",
        .username = "test_user",
        .password = "test_pass",
    };
    
    // 测试MySQL连接
    const connection = try mastra.mysql.MySQLConnection.init(allocator, mysql_config);
    defer connection.deinit();
    
    // 测试ping
    const ping_result = try connection.ping();
    try testing.expect(ping_result == true);
    
    // 测试SQL执行
    var result = try connection.execute("SELECT 1 as test", &[_]std.json.Value{});
    defer result.deinit();
    
    try testing.expect(result.getRows().len >= 0);
}

test "MySQL connection pool" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const mysql_config = mastra.MySQLConfig{
        .host = "localhost",
        .port = 3306,
        .database = "test_db",
        .username = "test_user",
        .password = "test_pass",
        .max_connections = 5,
    };
    
    // 测试连接池
    const pool = try mastra.mysql.MySQLConnectionPool.init(allocator, mysql_config);
    defer pool.deinit();
    
    // 获取连接
    const conn1 = try pool.getConnection();
    const conn2 = try pool.getConnection();
    
    // 归还连接
    try pool.returnConnection(conn1);
    try pool.returnConnection(conn2);
}

test "MySQL transaction support" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const mysql_config = mastra.MySQLConfig{
        .host = "localhost",
        .port = 3306,
        .database = "test_db",
        .username = "test_user",
        .password = "test_pass",
    };
    
    const connection = try mastra.mysql.MySQLConnection.init(allocator, mysql_config);
    defer connection.deinit();
    
    // 测试事务
    var transaction = try mastra.mysql.MySQLTransaction.init(connection);
    
    // 执行事务中的操作
    var result = try transaction.execute("INSERT INTO test (name) VALUES (?)", &[_]std.json.Value{
        std.json.Value{ .string = "test_name" },
    });
    defer result.deinit();
    
    // 提交事务
    try transaction.commit();
}

test "MySQL SSL and charset configuration" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const mysql_config = mastra.MySQLConfig{
        .host = "localhost",
        .port = 3306,
        .database = "test_db",
        .username = "test_user",
        .password = "test_pass",
        .charset = "utf8mb4",
        .ssl_mode = .required,
        .timeout = 60000,
    };
    
    // 测试带SSL配置的连接
    const connection = try mastra.mysql.MySQLConnection.init(allocator, mysql_config);
    defer connection.deinit();
    
    const ping_result = try connection.ping();
    try testing.expect(ping_result == true);
}