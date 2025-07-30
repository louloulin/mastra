const std = @import("std");
const testing = std.testing;
const mastra = @import("mastra");

test "简化集成测试 - 基础功能" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 1. 测试Mastra框架初始化
    var m = try mastra.Mastra.init(allocator, .{});
    defer m.deinit();

    try testing.expect(!m.isRunning());
    try testing.expect(m.agents.count() == 0);
    try testing.expect(m.workflows.count() == 0);

    std.debug.print("✓ Mastra框架初始化测试通过\n", .{});
}

test "简化集成测试 - 存储功能" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 2. 测试存储功能
    var storage = try mastra.Storage.init(allocator, .{ .type = .memory });
    defer storage.deinit();

    const test_data = std.json.Value{ .string = "测试数据" };
    const record_id = try storage.create("test_table", test_data);
    try testing.expect(record_id.len > 0);

    if (try storage.read("test_table", record_id)) |record| {
        try testing.expect(record.data == .string);
        try testing.expectEqualStrings("测试数据", record.data.string);
    } else {
        try testing.expect(false); // 应该能读取到记录
    }

    std.debug.print("✓ 存储功能测试通过\n", .{});
}

test "简化集成测试 - 向量存储" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 3. 测试向量存储功能
    var vector_store = try mastra.VectorStore.init(allocator, .{ .type = .memory, .dimension = 3 });
    defer vector_store.deinit();

    var test_embedding = [_]f32{ 1.0, 0.0, 0.0 };
    const vector_doc = mastra.VectorDocument{
        .id = "test_doc_1",
        .content = "测试文档",
        .embedding = &test_embedding,
        .metadata = null,
        .score = 0.0,
    };

    try vector_store.upsert(&[_]mastra.VectorDocument{vector_doc});

    var query_embedding = [_]f32{ 0.8, 0.6, 0.0 };
    const query = mastra.vector.VectorQuery{
        .vector = &query_embedding,
        .limit = 5,
        .threshold = 0.0,
    };

    const search_results = try vector_store.search(query);
    defer vector_store.freeSearchResults(search_results);
    try testing.expect(search_results.len == 1);
    try testing.expectEqualStrings("test_doc_1", search_results[0].id);

    std.debug.print("✓ 向量存储功能测试通过\n", .{});
}
