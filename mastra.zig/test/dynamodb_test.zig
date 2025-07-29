const std = @import("std");
const testing = std.testing;
const mastra = @import("mastra");

test "DynamoDB storage basic operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // 配置DynamoDB存储
    const storage_config = mastra.StorageConfig{
        .type = .dynamodb,
        .table_prefix = "test_",
    };
    
    const dynamodb_config = mastra.DynamoDBConfig{
        .region = "us-east-1",
        .access_key_id = "test_access_key",
        .secret_access_key = "test_secret_key",
        .table_name = "test_table",
    };
    
    // 初始化DynamoDB存储
    const dynamodb_storage = try mastra.DynamoDBStorage.init(allocator, storage_config, dynamodb_config);
    defer dynamodb_storage.deinit();
    
    // 测试数据
    const test_data = std.json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };
    
    // 测试创建记录
    const record_id = try dynamodb_storage.create("users", test_data);
    defer allocator.free(record_id);
    try testing.expect(record_id.len > 0);
    
    // 测试读取记录
    const read_result = try dynamodb_storage.read("users", record_id);
    try testing.expect(read_result != null);
    
    // 测试更新记录
    const update_result = try dynamodb_storage.update("users", record_id, test_data);
    try testing.expect(update_result == true);
    
    // 测试计数
    const count = try dynamodb_storage.count("users");
    try testing.expect(count >= 0);
    
    // 测试删除记录
    const delete_result = try dynamodb_storage.delete("users", record_id);
    try testing.expect(delete_result == true);
}

test "DynamoDB connection and basic operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const dynamodb_config = mastra.DynamoDBConfig{
        .region = "us-west-2",
        .access_key_id = "test_access_key",
        .secret_access_key = "test_secret_key",
        .table_name = "test_table",
    };
    
    // 测试DynamoDB连接
    const connection = try mastra.dynamodb.DynamoDBConnection.init(allocator, dynamodb_config);
    defer connection.deinit();
    
    // 测试创建表
    try connection.createTable();
    
    // 测试项目操作
    var item = mastra.dynamodb.DynamoDBItem.init(allocator);
    defer item.deinit();
    
    try item.putString("id", "test_id");
    try item.putString("name", "test_name");
    try item.putNumber("age", 25.0);
    try item.putBoolean("active", true);
    
    // 测试放置项目
    try connection.putItem(item);
    
    // 测试获取项目
    var key = mastra.dynamodb.DynamoDBItem.init(allocator);
    defer key.deinit();
    try key.putString("id", "test_id");
    
    if (try connection.getItem(key)) |retrieved_item| {
        defer {
            var mutable_item = retrieved_item;
            mutable_item.deinit();
        }
        
        try testing.expect(retrieved_item.getString("id") != null);
    }
}

test "DynamoDB item operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // 测试DynamoDB项目
    var item = mastra.dynamodb.DynamoDBItem.init(allocator);
    defer item.deinit();
    
    // 测试字符串属性
    try item.putString("name", "John Doe");
    const name = item.getString("name");
    try testing.expect(name != null);
    try testing.expectEqualStrings("John Doe", name.?);
    
    // 测试数字属性
    try item.putNumber("age", 30.5);
    const age = item.getNumber("age");
    try testing.expect(age != null);
    try testing.expectEqual(@as(f64, 30.5), age.?);
    
    // 测试布尔属性
    try item.putBoolean("active", true);
    // 注意：这里没有getBoolean方法，但可以通过attributes直接访问
    const active_value = item.attributes.get("active");
    try testing.expect(active_value != null);
    switch (active_value.?) {
        .boolean => |b| try testing.expect(b == true),
        else => try testing.expect(false),
    }
}

test "DynamoDB query and scan operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const dynamodb_config = mastra.DynamoDBConfig{
        .region = "eu-west-1",
        .access_key_id = "test_access_key",
        .secret_access_key = "test_secret_key",
        .table_name = "test_table",
    };
    
    const connection = try mastra.dynamodb.DynamoDBConnection.init(allocator, dynamodb_config);
    defer connection.deinit();
    
    // 测试查询
    var query_result = try connection.query("id = :id", "#status = :status");
    defer query_result.deinit();
    
    try testing.expect(query_result.count >= 0);
    
    // 测试扫描
    var scan_result = try connection.scan("attribute_exists(#name)");
    defer scan_result.deinit();
    
    try testing.expect(scan_result.scanned_count >= 0);
}

test "DynamoDB batch operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const dynamodb_config = mastra.DynamoDBConfig{
        .region = "ap-southeast-1",
        .access_key_id = "test_access_key",
        .secret_access_key = "test_secret_key",
        .table_name = "test_table",
    };
    
    const connection = try mastra.dynamodb.DynamoDBConnection.init(allocator, dynamodb_config);
    defer connection.deinit();
    
    // 测试批量写入
    var batch_writer = mastra.dynamodb.DynamoDBBatchWriter.init(allocator, connection);
    defer batch_writer.deinit();
    
    // 添加多个项目
    for (0..5) |i| {
        var item = mastra.dynamodb.DynamoDBItem.init(allocator);
        const id = try std.fmt.allocPrint(allocator, "item_{d}", .{i});
        defer allocator.free(id);
        
        try item.putString("id", id);
        try item.putString("name", "Test Item");
        try item.putNumber("index", @as(f64, @floatFromInt(i)));
        
        try batch_writer.addItem(item);
    }
    
    // 刷新剩余项目
    try batch_writer.flush();
}

test "DynamoDB configuration options" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // 测试不同的配置选项
    const config1 = mastra.DynamoDBConfig{
        .region = "us-east-1",
        .access_key_id = "key1",
        .secret_access_key = "secret1",
        .table_name = "table1",
        .billing_mode = .provisioned,
        .read_capacity = 10,
        .write_capacity = 10,
    };
    
    const config2 = mastra.DynamoDBConfig{
        .region = "us-west-2",
        .access_key_id = "key2",
        .secret_access_key = "secret2",
        .table_name = "table2",
        .billing_mode = .pay_per_request,
        .endpoint = "http://localhost:8000", // 本地DynamoDB
    };
    
    // 测试两种配置都能正常创建连接
    const conn1 = try mastra.dynamodb.DynamoDBConnection.init(allocator, config1);
    defer conn1.deinit();
    
    const conn2 = try mastra.dynamodb.DynamoDBConnection.init(allocator, config2);
    defer conn2.deinit();
    
    try testing.expectEqualStrings("us-east-1", conn1.config.region);
    try testing.expectEqualStrings("us-west-2", conn2.config.region);
}