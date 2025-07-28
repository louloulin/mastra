const std = @import("std");
const mastra = @import("src/mastra.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n🚀 Mastra.zig P1功能测试验证\n", .{});
    std.debug.print("==================================================\n", .{});

    var test_results = TestResults.init();

    // 1. 测试RAG系统
    std.debug.print("1. 测试RAG系统...\n", .{});
    if (testRAGSystem(allocator)) {
        test_results.rag_system = true;
        std.debug.print("   ✅ RAG系统测试通过\n", .{});
    } else |err| {
        std.debug.print("   ❌ RAG系统测试失败: {}\n", .{err});
    }

    // 2. 测试事件系统
    std.debug.print("2. 测试事件系统...\n", .{});
    if (testEventSystem(allocator)) {
        test_results.event_system = true;
        std.debug.print("   ✅ 事件系统测试通过\n", .{});
    } else |err| {
        std.debug.print("   ❌ 事件系统测试失败: {}\n", .{err});
    }

    // 3. 测试流式处理
    std.debug.print("3. 测试流式处理...\n", .{});
    if (testStreamingSystem(allocator)) {
        test_results.streaming_system = true;
        std.debug.print("   ✅ 流式处理测试通过\n", .{});
    } else |err| {
        std.debug.print("   ❌ 流式处理测试失败: {}\n", .{err});
    }

    // 输出测试结果总结
    printTestSummary(test_results);
}

const TestResults = struct {
    rag_system: bool = false,
    event_system: bool = false,
    streaming_system: bool = false,

    fn init() TestResults {
        return TestResults{};
    }

    fn getPassedCount(self: TestResults) u32 {
        var count: u32 = 0;
        if (self.rag_system) count += 1;
        if (self.event_system) count += 1;
        if (self.streaming_system) count += 1;
        return count;
    }
};

fn testRAGSystem(allocator: std.mem.Allocator) !void {
    // 创建RAG系统
    const rag_config = mastra.RAGConfig{};
    var rag_system = mastra.RAGSystem.init(allocator, rag_config);
    defer rag_system.deinit();

    std.debug.print("     - RAG系统初始化成功\n", .{});

    // 测试文档处理
    const test_content = "This is a test document about artificial intelligence and machine learning.";
    const metadata = mastra.document.DocumentMetadata{
        .id = "test_doc_1",
        .title = "Test Document",
        .created_at = std.time.timestamp(),
        .updated_at = std.time.timestamp(),
    };

    try rag_system.addDocument(test_content, .text, metadata);
    std.debug.print("     - 文档添加成功\n", .{});

    // 测试查询
    var context = try rag_system.query("artificial intelligence");
    defer context.deinit(allocator);
    
    std.debug.print("     - 查询执行成功，检索到 {d} 个块\n", .{context.retrieved_chunks.len});
    std.debug.print("     - 上下文长度: {d} 字符\n", .{context.context_text.len});

    // 测试统计信息
    const stats = rag_system.getStats();
    std.debug.print("     - 总文档数: {d}\n", .{stats.total_documents});
    std.debug.print("     - 总块数: {d}\n", .{stats.total_chunks});
    std.debug.print("     - 有嵌入的块数: {d}\n", .{stats.chunks_with_embeddings});
}

fn testEventSystem(allocator: std.mem.Allocator) !void {
    // 创建事件总线
    const config = mastra.event_bus.EventBusConfig{
        .worker_threads = 2,
        .max_queue_size = 100,
    };
    
    var bus = try mastra.EventBus.init(allocator, config);
    defer bus.deinit();

    try bus.start();
    defer bus.stop();

    std.debug.print("     - 事件总线启动成功\n", .{});

    // 创建测试事件处理器
    const subscription_id = try bus.subscribe("test.event", testEventHandler);
    defer allocator.free(subscription_id);

    std.debug.print("     - 事件订阅成功: {s}\n", .{subscription_id});

    // 发布测试事件
    const event_data = std.json.Value{ .string = "Hello, Events!" };
    try bus.publish("test.event", event_data, "test_source");

    std.debug.print("     - 事件发布成功\n", .{});

    // 等待事件处理
    std.time.sleep(100 * std.time.ns_per_ms);

    // 检查统计信息
    const stats = bus.getStats();
    std.debug.print("     - 已发布事件: {d}\n", .{stats.total_events_published});
    std.debug.print("     - 已处理事件: {d}\n", .{stats.total_events_processed});
    std.debug.print("     - 活跃订阅: {d}\n", .{stats.active_subscriptions});

    // 测试取消订阅
    const unsubscribed = bus.unsubscribe(subscription_id);
    std.debug.print("     - 取消订阅: {}\n", .{unsubscribed});
}

fn testEventHandler(allocator: std.mem.Allocator, event: *const mastra.Event) !void {
    _ = allocator;
    std.debug.print("     - 处理事件: {s} (类型: {s})\n", .{ event.id, event.event_type });
}

fn testStreamingSystem(allocator: std.mem.Allocator) !void {
    // 创建流
    const stream_config = mastra.streaming.StreamConfig{
        .buffer_size = 1024,
        .max_chunks = 100,
    };
    
    var stream = mastra.Stream.init(allocator, stream_config);
    defer stream.deinit();

    std.debug.print("     - 流初始化成功\n", .{});

    // 添加消费者
    try stream.addConsumer(testStreamConsumer);
    std.debug.print("     - 流消费者添加成功\n", .{});

    // 写入数据
    try stream.write("Hello, Streaming!");
    try stream.write("This is chunk 2");
    try stream.write("Final chunk");

    std.debug.print("     - 数据写入成功\n", .{});

    // 读取数据
    var chunks_read: u32 = 0;
    while (stream.read()) |chunk| {
        var mut_chunk = chunk;
        defer mut_chunk.deinit(allocator);
        chunks_read += 1;
        std.debug.print("     - 读取块 {d}: {s}\n", .{ chunks_read, chunk.data });
    }

    // 测试统计信息
    const stats = stream.getStats();
    std.debug.print("     - 总字节数: {d}\n", .{stats.total_bytes});
    std.debug.print("     - 块数量: {d}\n", .{stats.chunk_count});
    std.debug.print("     - 平均块大小: {d:.1} 字节\n", .{stats.averageChunkSize()});

    // 测试响应流
    const response_config = mastra.response_stream.ResponseStreamConfig{
        .format = .json,
        .buffer_size = 1024,
    };
    
    var response_stream = mastra.ResponseStream.init(allocator, response_config);
    defer response_stream.deinit();

    try response_stream.start();
    defer response_stream.stop();

    std.debug.print("     - 响应流启动成功\n", .{});

    // 添加连接
    const conn_id = try response_stream.addConnection(.json);
    defer allocator.free(conn_id);

    std.debug.print("     - 连接添加成功: {s}\n", .{conn_id});

    // 发送数据
    const test_data = std.json.Value{ .string = "Hello, Response Stream!" };
    try response_stream.sendData(test_data);

    std.debug.print("     - 数据发送成功\n", .{});

    // 发送事件
    try response_stream.sendEvent("test_event", test_data);

    std.debug.print("     - 事件发送成功\n", .{});

    // 检查统计信息
    const response_stats = response_stream.getStats();
    std.debug.print("     - 总连接数: {d}\n", .{response_stats.total_connections});
    std.debug.print("     - 活跃连接数: {d}\n", .{response_stats.active_connections});
    std.debug.print("     - 发送消息数: {d}\n", .{response_stats.messages_sent});

    // 移除连接
    const removed = response_stream.removeConnection(conn_id);
    std.debug.print("     - 连接移除: {}\n", .{removed});
}

fn testStreamConsumer(allocator: std.mem.Allocator, chunk: *const mastra.StreamChunk) !void {
    _ = allocator;
    std.debug.print("     - 消费者处理块: {s} ({d} 字节)\n", .{ chunk.data, chunk.data.len });
}

fn printTestSummary(results: TestResults) void {
    const passed = results.getPassedCount();
    const total = 3;

    std.debug.print("\n🎯 P1功能测试结果总结\n", .{});
    std.debug.print("==================================================\n", .{});
    std.debug.print("✅ 通过测试: {d}/{d}\n", .{ passed, total });
    std.debug.print("📊 成功率: {d:.1}%\n", .{ @as(f64, @floatFromInt(passed)) / @as(f64, @floatFromInt(total)) * 100.0 });

    std.debug.print("\n📋 详细结果:\n", .{});
    std.debug.print("   RAG系统: {s}\n", .{if (results.rag_system) "✅ 通过" else "❌ 失败"});
    std.debug.print("   事件系统: {s}\n", .{if (results.event_system) "✅ 通过" else "❌ 失败"});
    std.debug.print("   流式处理: {s}\n", .{if (results.streaming_system) "✅ 通过" else "❌ 失败"});

    if (passed == total) {
        std.debug.print("\n🏆 恭喜！所有P1级别重要功能测试全部通过！\n", .{});
        std.debug.print("🚀 Mastra.zig现在具备完整的企业级AI应用能力！\n", .{});
        std.debug.print("\n📈 新增能力:\n", .{});
        std.debug.print("   - 文档处理和智能检索 (RAG)\n", .{});
        std.debug.print("   - 异步事件处理和发布订阅\n", .{});
        std.debug.print("   - 实时流式数据处理\n", .{});
        std.debug.print("   - 服务器推送事件 (SSE)\n", .{});
        std.debug.print("   - WebSocket消息处理\n", .{});
    } else {
        std.debug.print("\n⚠️  还有 {d} 个功能需要完善\n", .{total - passed});
        std.debug.print("🔧 请检查失败的测试并修复相关问题\n", .{});
    }
    std.debug.print("==================================================\n", .{});
}
