const std = @import("std");
const mastra = @import("mastra");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("🚀 简单功能验证测试\n", .{});
    std.debug.print("==================================================\n", .{});

    try testBasicFeatures(allocator);

    std.debug.print("\n🎉 简单功能验证完成！\n", .{});
    std.debug.print("==================================================\n", .{});
}

fn testBasicFeatures(allocator: std.mem.Allocator) !void {
    std.debug.print("\n📋 基础功能测试\n", .{});
    std.debug.print("----------------------------------------\n", .{});

    // 1. 测试工作流引擎
    std.debug.print("1. 测试工作流引擎...\n", .{});

    const thread_pool_config = mastra.workflow.ThreadPoolConfig{
        .max_threads = 2,
        .queue_size = 100,
    };

    const logger_config = mastra.utils.LoggerConfig{
        .level = .info,
    };
    var logger = try mastra.utils.Logger.init(allocator, logger_config);
    defer logger.deinit();

    var execution_engine = try mastra.workflow.ExecutionEngine.init(allocator, thread_pool_config, logger);
    defer execution_engine.deinit();
    std.debug.print("   ✅ 工作流引擎初始化成功\n", .{});

    // 2. 测试存储系统
    std.debug.print("2. 测试存储系统...\n", .{});

    const storage_config = mastra.storage.StorageConfig{
        .type = .memory,
    };
    var storage = try mastra.storage.Storage.init(allocator, storage_config);
    defer storage.deinit();

    const test_data = std.json.Value{ .string = "test_value" };
    const record_id = try storage.create("test_table", test_data);
    // 不需要手动释放record_id，存储系统会管理它

    const retrieved_record = try storage.read("test_table", record_id);
    if (retrieved_record) |_| {
        std.debug.print("   ✅ 存储系统: 创建和读取成功 - ID: {s}\n", .{record_id});
    }

    // 3. 测试Agent配置
    std.debug.print("3. 测试Agent配置...\n", .{});

    const runtime_context = mastra.agent.RuntimeContext.init(allocator);
    const dynamic_arg = mastra.agent.DynamicArgument([]const u8){ .static_value = "测试指令" };
    const resolved = try dynamic_arg.resolve(runtime_context);
    std.debug.print("   ✅ DynamicArgument解析: {s}\n", .{resolved});

    // 4. 测试消息列表
    std.debug.print("4. 测试消息列表...\n", .{});

    const message_config = mastra.agent.MessageListConfig{};
    var message_list = try mastra.agent.MessageList.init(allocator, message_config, null);
    defer message_list.deinit();

    try message_list.addMessage("user", "测试消息", .normal);
    const message_count = message_list.getMessageCount();
    std.debug.print("   ✅ 消息列表: {} 条消息\n", .{message_count});

    // 5. 测试工具系统
    std.debug.print("5. 测试工具系统...\n", .{});

    var tool_registry = mastra.tool_builder.ToolRegistry.init(allocator);
    defer tool_registry.deinit();
    std.debug.print("   ✅ 工具注册表初始化成功\n", .{});

    // 6. 测试事件系统
    std.debug.print("6. 测试事件系统...\n", .{});

    const event_bus_config = mastra.event_bus.EventBusConfig{};
    var event_bus = try mastra.event_bus.EventBus.init(allocator, event_bus_config);
    defer event_bus.deinit();

    const event_data = std.json.Value{ .string = "测试数据" };
    var test_event = try mastra.events.Event.init(allocator, "test", event_data, "test_source");
    defer test_event.deinit(allocator);

    try event_bus.publish("test", event_data, "test_source");
    std.debug.print("   ✅ 事件发布成功\n", .{});

    // 7. 测试流式处理
    std.debug.print("7. 测试流式处理...\n", .{});

    const stream_config = mastra.response_stream.ResponseStreamConfig{};
    var response_stream = mastra.response_stream.ResponseStream.init(allocator, stream_config);
    defer response_stream.deinit();

    try response_stream.start();
    const stream_data = std.json.Value{ .string = "测试流数据" };
    try response_stream.sendData(stream_data);
    std.debug.print("   ✅ 流式数据写入成功\n", .{});

    // 8. 测试文档类型
    std.debug.print("8. 测试文档类型...\n", .{});

    const doc_types = [_]mastra.document.DocumentType{ .text, .markdown, .html, .json, .csv };
    for (doc_types) |doc_type| {
        std.debug.print("   ✅ 支持文档类型: {}\n", .{doc_type});
    }

    // 9. 测试嵌入配置
    std.debug.print("9. 测试嵌入配置...\n", .{});

    const embedding_config = mastra.embeddings.EmbeddingConfig{};
    _ = mastra.EmbeddingProvider.init(allocator, embedding_config);
    std.debug.print("   ✅ 嵌入提供者初始化成功，维度: {}\n", .{embedding_config.dimensions});

    // 10. 测试向量存储
    std.debug.print("10. 测试向量存储...\n", .{});

    var vector_store = mastra.RAGVectorStore.init(allocator);
    defer vector_store.deinit();
    std.debug.print("   ✅ 向量存储初始化成功\n", .{});

    std.debug.print("   ✅ 所有基础功能验证完成\n", .{});
}
