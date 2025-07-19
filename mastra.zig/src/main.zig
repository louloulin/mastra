const std = @import("std");
const mastra = @import("mastra.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    // 初始化Mastra框架
    var m = try mastra.Mastra.init(allocator, .{});
    defer m.deinit();

    std.debug.print("🚀 Mastra.zig 初始化成功!\n", .{});
    std.debug.print("📊 框架状态:\n", .{});
    std.debug.print("  - 事件循环: {s}\n", .{if (m.isRunning()) "运行中" else "已停止"});
    std.debug.print("  - 已注册Agent数量: {d}\n", .{m.agents.count()});
    std.debug.print("  - 已注册Workflow数量: {d}\n", .{m.workflows.count()});

    // 演示基本功能
    try demonstrateBasicFeatures(allocator, &m);

    std.debug.print("✅ Mastra.zig 演示完成!\n", .{});
}

fn demonstrateBasicFeatures(allocator: std.mem.Allocator, m: *mastra.Mastra) !void {
    std.debug.print("\n🔧 演示基本功能:\n", .{});

    // 1. 创建存储实例
    var storage = try mastra.Storage.init(allocator, .{ .type = .memory });
    defer storage.deinit();

    // 2. 测试存储功能
    const test_data = std.json.Value{ .string = "Hello, Mastra Storage!" };
    const record_id = try storage.create("test_table", test_data);
    std.debug.print("  ✓ 创建存储记录: {s}\n", .{record_id});

    // 3. 读取存储记录
    if (try storage.read("test_table", record_id)) |record| {
        std.debug.print("  ✓ 读取存储记录成功\n", .{});
        _ = record; // 避免未使用警告
    }

    // 4. 创建内存向量存储（避免SQLite问题）
    var vector_store = try mastra.VectorStore.init(allocator, .{ .type = .memory, .dimension = 3 });
    defer vector_store.deinit();

    // 5. 测试向量存储
    var test_embedding = [_]f32{ 1.0, 0.0, 0.0 };
    const vector_doc = mastra.VectorDocument{
        .id = "test_doc_1",
        .content = "这是一个测试文档",
        .embedding = &test_embedding,
        .metadata = null,
        .score = 0.0,
    };

    try vector_store.upsert(&[_]mastra.VectorDocument{vector_doc});
    std.debug.print("  ✓ 向量文档存储成功\n", .{});

    // 6. 测试向量搜索
    var query_embedding = [_]f32{ 0.8, 0.6, 0.0 };
    const query = mastra.vector.VectorQuery{
        .vector = &query_embedding,
        .limit = 5,
        .threshold = 0.0,
    };

    const search_results = try vector_store.search(query);
    defer allocator.free(search_results);
    std.debug.print("  ✓ 向量搜索完成，找到 {d} 个结果\n", .{search_results.len});

    // 7. 创建内存管理器
    var memory = try mastra.Memory.init(allocator, .{});
    defer memory.deinit();

    // 8. 测试内存功能（简化版本）
    std.debug.print("  ✓ 内存管理器初始化成功\n", .{});

    // 9. 创建遥测系统
    var telemetry = try mastra.Telemetry.init(allocator, .{}, m.getLogger());
    defer telemetry.deinit();

    // 10. 测试遥测功能
    const span_id = try telemetry.startSpan("test_operation", null);
    try telemetry.endSpan(span_id, null, null);
    std.debug.print("  ✓ 遥测跟踪完成\n", .{});

    std.debug.print("🎉 所有基本功能测试通过!\n", .{});
}
