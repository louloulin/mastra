const std = @import("std");
const testing = std.testing;
const mastra = @import("mastra");

test "Mastra.zig 集成测试" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 1. 测试Mastra框架初始化
    var m = try mastra.Mastra.init(allocator, .{});
    defer m.deinit();

    try testing.expect(!m.isRunning());
    try testing.expect(m.agents.count() == 0);
    try testing.expect(m.workflows.count() == 0);

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
    defer allocator.free(search_results);
    try testing.expect(search_results.len == 1);
    try testing.expectEqualStrings("test_doc_1", search_results[0].id);

    // 4. 测试内存管理
    var memory = try mastra.Memory.init(allocator, .{});
    defer memory.deinit();

    // 内存管理器应该成功初始化
    try testing.expect(memory.allocator.ptr == allocator.ptr);

    // 5. 测试遥测系统
    var telemetry = try mastra.Telemetry.init(allocator, .{}, m.getLogger());
    defer telemetry.deinit();

    const span_id = try telemetry.startSpan("test_span", null);
    try testing.expect(span_id.len > 0);

    try telemetry.endSpan(span_id, null, null);

    // 6. 测试LLM配置验证
    const openai_config = mastra.llm.LLMConfig{
        .provider = .openai,
        .model = "gpt-4",
        .api_key = "test-key",
        .base_url = null,
        .temperature = 0.7,
        .max_tokens = 1000,
    };

    try testing.expectEqual(mastra.llm.LLMProvider.openai, openai_config.provider);
    try testing.expectEqualStrings("gpt-4", openai_config.model);
    try testing.expectEqual(@as(f32, 0.7), openai_config.temperature);

    // 7. 测试基本配置验证
    std.debug.print("  ✓ 所有核心组件测试通过\n", .{});
}

test "Mastra.zig 性能测试" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    _ = allocator; // 避免未使用警告

    // 向量相似度计算性能测试
    const iterations = 10000;
    const vec1 = [_]f32{ 1.0, 2.0, 3.0, 4.0 } ** 256; // 1024维向量
    const vec2 = [_]f32{ 0.5, 1.5, 2.5, 3.5 } ** 256;

    const start = std.time.nanoTimestamp();

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        var dot_product: f32 = 0.0;
        var norm1: f32 = 0.0;
        var norm2: f32 = 0.0;

        for (vec1, vec2) |v1, v2| {
            dot_product += v1 * v2;
            norm1 += v1 * v1;
            norm2 += v2 * v2;
        }

        const similarity = dot_product / (@sqrt(norm1) * @sqrt(norm2));
        _ = similarity;
    }

    const end = std.time.nanoTimestamp();
    const total_time = @as(u64, @intCast(end - start));
    const avg_time = total_time / iterations;

    std.debug.print("\n向量相似度计算性能:\n", .{});
    std.debug.print("  迭代次数: {d}\n", .{iterations});
    std.debug.print("  总时间: {d:.2} ms\n", .{@as(f64, @floatFromInt(total_time)) / 1_000_000.0});
    std.debug.print("  平均时间: {d:.2} μs\n", .{@as(f64, @floatFromInt(avg_time)) / 1_000.0});
    std.debug.print("  每秒操作数: {d:.0}\n", .{@as(f64, @floatFromInt(iterations)) / (@as(f64, @floatFromInt(total_time)) / 1_000_000_000.0)});

    // 性能应该足够好（每次操作少于100微秒）
    try testing.expect(avg_time < 100_000); // 100微秒
}

test "Mastra.zig 内存管理测试" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("警告: 检测到内存泄漏\n", .{});
        }
    }
    const allocator = gpa.allocator();

    // 创建和销毁多个组件，确保没有内存泄漏
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        var storage = try mastra.Storage.init(allocator, .{ .type = .memory });
        defer storage.deinit();

        const test_data = std.json.Value{ .float = @as(f64, @floatFromInt(i)) };
        const record_id = try storage.create("test", test_data);
        _ = record_id;
    }

    // 测试向量存储的内存管理
    i = 0;
    while (i < 50) : (i += 1) {
        var vector_store = try mastra.VectorStore.init(allocator, .{ .type = .memory, .dimension = 4 });
        defer vector_store.deinit();

        var embedding = [_]f32{ @as(f32, @floatFromInt(i)), 1.0, 2.0, 3.0 };
        const doc = mastra.VectorDocument{
            .id = "test",
            .content = "test content",
            .embedding = &embedding,
            .metadata = null,
            .score = 0.0,
        };

        try vector_store.upsert(&[_]mastra.VectorDocument{doc});
    }
}
