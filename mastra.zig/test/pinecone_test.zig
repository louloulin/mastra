const std = @import("std");
const testing = std.testing;
const mastra = @import("mastra");

test "Pinecone基本配置" {
    const config = mastra.PineconeConfig{
        .api_key = "test-api-key",
        .environment = "us-east1-gcp",
        .index_name = "test-index",
        .dimension = 1536,
        .metric = .cosine,
    };
    
    try testing.expect(std.mem.eql(u8, config.api_key, "test-api-key"));
    try testing.expect(std.mem.eql(u8, config.environment, "us-east1-gcp"));
    try testing.expect(std.mem.eql(u8, config.index_name, "test-index"));
    try testing.expect(config.dimension == 1536);
    try testing.expect(config.metric == .cosine);
}

test "Pinecone向量创建和销毁" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const values = [_]f32{ 0.1, 0.2, 0.3, 0.4, 0.5 };
    var vector = try mastra.PineconeVector.init(allocator, "test-vector-1", &values);
    defer vector.deinit(allocator);
    
    try testing.expect(std.mem.eql(u8, vector.id, "test-vector-1"));
    try testing.expect(vector.values.len == 5);
    try testing.expect(vector.values[0] == 0.1);
    try testing.expect(vector.values[4] == 0.5);
}

test "Pinecone向量稀疏值设置" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const values = [_]f32{ 0.1, 0.2, 0.3 };
    var vector = try mastra.PineconeVector.init(allocator, "sparse-vector", &values);
    defer vector.deinit(allocator);
    
    const sparse_indices = [_]u32{ 0, 5, 10 };
    const sparse_values = [_]f32{ 0.8, 0.9, 1.0 };
    
    try vector.setSparseValues(allocator, &sparse_indices, &sparse_values);
    
    try testing.expect(vector.sparse_values != null);
    if (vector.sparse_values) |sparse| {
        try testing.expect(sparse.indices.len == 3);
        try testing.expect(sparse.values.len == 3);
        try testing.expect(sparse.indices[0] == 0);
        try testing.expect(sparse.values[2] == 1.0);
    }
}

test "Pinecone连接创建和销毁" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const config = mastra.PineconeConfig{
        .api_key = "test-key",
        .environment = "test-env",
        .index_name = "test-index",
        .dimension = 768,
    };
    
    var connection = try mastra.pinecone.PineconeConnection.init(allocator, config);
    defer connection.deinit();
    
    try testing.expect(connection.is_connected);
    try testing.expect(connection.config.dimension == 768);
}

test "Pinecone索引操作" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const config = mastra.PineconeConfig{
        .api_key = "test-key",
        .environment = "test-env",
        .index_name = "test-index",
        .dimension = 512,
    };
    
    var connection = try mastra.pinecone.PineconeConnection.init(allocator, config);
    defer connection.deinit();
    
    // 测试创建索引
    try connection.createIndex();
    
    // 测试删除索引
    try connection.deleteIndex();
}

test "Pinecone向量插入" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const config = mastra.PineconeConfig{
        .api_key = "test-key",
        .environment = "test-env",
        .index_name = "test-index",
        .dimension = 3,
    };
    
    var connection = try mastra.pinecone.PineconeConnection.init(allocator, config);
    defer connection.deinit();
    
    // 创建测试向量
    const values1 = [_]f32{ 0.1, 0.2, 0.3 };
    const values2 = [_]f32{ 0.4, 0.5, 0.6 };
    
    var vector1 = try mastra.PineconeVector.init(allocator, "vec1", &values1);
    defer vector1.deinit(allocator);
    
    var vector2 = try mastra.PineconeVector.init(allocator, "vec2", &values2);
    defer vector2.deinit(allocator);
    
    const vectors = [_]mastra.PineconeVector{ vector1, vector2 };
    
    // 测试向量插入
    try connection.upsert(&vectors, "test-namespace");
}

test "Pinecone向量查询" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const config = mastra.PineconeConfig{
        .api_key = "test-key",
        .environment = "test-env",
        .index_name = "test-index",
        .dimension = 4,
    };
    
    var connection = try mastra.pinecone.PineconeConnection.init(allocator, config);
    defer connection.deinit();
    
    const query_vector = [_]f32{ 0.1, 0.2, 0.3, 0.4 };
    
    var response = try connection.query(&query_vector, 5, "test-namespace", null, true, true);
    defer response.deinit();
    
    // 验证查询结果
    try testing.expect(response.matches.items.len <= 5);
    
    if (response.matches.items.len > 0) {
        const first_match = response.matches.items[0];
        try testing.expect(first_match.score >= 0.0 and first_match.score <= 1.0);
        try testing.expect(first_match.values != null);
        try testing.expect(first_match.metadata != null);
    }
}

test "Pinecone向量获取" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const config = mastra.PineconeConfig{
        .api_key = "test-key",
        .environment = "test-env",
        .index_name = "test-index",
        .dimension = 256,
    };
    
    var connection = try mastra.pinecone.PineconeConnection.init(allocator, config);
    defer connection.deinit();
    
    const ids = [_][]const u8{ "vec1", "vec2", "vec3" };
    
    var response = try connection.fetch(&ids, "test-namespace");
    defer response.deinit();
    
    // 验证获取结果
    try testing.expect(response.matches.items.len == ids.len);
    
    for (response.matches.items, 0..) |match, i| {
        try testing.expect(std.mem.eql(u8, match.id, ids[i]));
        try testing.expect(match.values != null);
        try testing.expect(match.values.?.len == config.dimension);
    }
}

test "Pinecone向量删除" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const config = mastra.PineconeConfig{
        .api_key = "test-key",
        .environment = "test-env",
        .index_name = "test-index",
        .dimension = 128,
    };
    
    var connection = try mastra.pinecone.PineconeConnection.init(allocator, config);
    defer connection.deinit();
    
    const ids = [_][]const u8{ "vec1", "vec2" };
    
    // 测试删除特定向量
    try connection.delete(&ids, "test-namespace", false);
    
    // 测试删除所有向量
    try connection.delete(&[_][]const u8{}, "test-namespace", true);
}

test "Pinecone索引统计" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const config = mastra.PineconeConfig{
        .api_key = "test-key",
        .environment = "test-env",
        .index_name = "test-index",
        .dimension = 1024,
    };
    
    var connection = try mastra.pinecone.PineconeConnection.init(allocator, config);
    defer connection.deinit();
    
    var stats = try connection.describeIndexStats();
    defer stats.deinit();
    
    try testing.expect(stats.dimension == config.dimension);
    try testing.expect(stats.index_fullness >= 0.0 and stats.index_fullness <= 1.0);
    try testing.expect(stats.total_vector_count >= 0);
}

test "PineconeStorage基本操作" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const storage_config = mastra.StorageConfig{
        .storage_type = .pinecone,
        .table_prefix = "test_",
    };
    
    const pinecone_config = mastra.PineconeConfig{
        .api_key = "test-key",
        .environment = "test-env",
        .index_name = "test-index",
        .dimension = 512,
    };
    
    var storage = try mastra.PineconeStorage.init(allocator, storage_config, pinecone_config);
    defer storage.deinit();
    
    // 创建测试数据
    var test_data = std.json.ObjectMap.init(allocator);
    defer test_data.deinit();
    
    const vector_array = std.json.Array.init(allocator);
    defer vector_array.deinit();
    
    // 这里简化测试，实际使用时需要正确构建JSON数据
    const data = std.json.Value{ .object = test_data };
    
    // 测试创建
    const id = try storage.create("vectors", data);
    defer allocator.free(id);
    
    try testing.expect(id.len > 0);
    
    // 测试读取
    const result = try storage.read("vectors", id);
    try testing.expect(result != null);
    
    // 测试更新
    const updated = try storage.update("vectors", id, data);
    try testing.expect(updated);
    
    // 测试删除
    const deleted = try storage.delete("vectors", id);
    try testing.expect(deleted);
    
    // 测试计数
    const count = try storage.count("vectors");
    try testing.expect(count >= 0);
}

test "PineconeStorage相似性搜索" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const storage_config = mastra.StorageConfig{
        .storage_type = .pinecone,
        .table_prefix = "search_",
    };
    
    const pinecone_config = mastra.PineconeConfig{
        .api_key = "test-key",
        .environment = "test-env",
        .index_name = "search-index",
        .dimension = 256,
    };
    
    var storage = try mastra.PineconeStorage.init(allocator, storage_config, pinecone_config);
    defer storage.deinit();
    
    const query_vector = [_]f32{ 0.1, 0.2, 0.3, 0.4, 0.5 };
    
    var response = try storage.similaritySearch("embeddings", &query_vector, 10, null);
    defer response.deinit();
    
    try testing.expect(response.matches.items.len <= 10);
}

test "PineconeStorage批量插入" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const storage_config = mastra.StorageConfig{
        .storage_type = .pinecone,
        .table_prefix = "batch_",
    };
    
    const pinecone_config = mastra.PineconeConfig{
        .api_key = "test-key",
        .environment = "test-env",
        .index_name = "batch-index",
        .dimension = 128,
    };
    
    var storage = try mastra.PineconeStorage.init(allocator, storage_config, pinecone_config);
    defer storage.deinit();
    
    // 创建批量向量
    var vectors = std.ArrayList(mastra.PineconeVector).init(allocator);
    defer {
        for (vectors.items) |*vector| {
            vector.deinit(allocator);
        }
        vectors.deinit();
    }
    
    for (0..5) |i| {
        const values = try allocator.alloc(f32, pinecone_config.dimension);
        defer allocator.free(values);
        
        // 填充测试向量值
        for (values, 0..) |*val, j| {
            val.* = @as(f32, @floatFromInt(i * 100 + j)) / 1000.0;
        }
        
        const id = try std.fmt.allocPrint(allocator, "batch_vec_{d}", .{i});
        defer allocator.free(id);
        
        const vector = try mastra.PineconeVector.init(allocator, id, values);
        try vectors.append(vector);
    }
    
    // 测试批量插入
    try storage.batchUpsert("batch_vectors", vectors.items);
}