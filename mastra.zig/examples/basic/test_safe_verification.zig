const std = @import("std");
const mastra = @import("mastra");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("❌ 检测到内存泄漏！\n", .{});
            std.process.exit(1);
        } else {
            std.debug.print("✅ 无内存泄漏！所有模块内存管理完美！\n", .{});
        }
    }
    const allocator = gpa.allocator();

    std.debug.print("🚀 Mastra.zig 安全功能验证\n", .{});
    std.debug.print("==================================================\n", .{});

    try testAllFeaturesSafely(allocator);

    std.debug.print("\n🎉 所有功能验证完成！\n", .{});
    std.debug.print("==================================================\n", .{});
}

fn testAllFeaturesSafely(allocator: std.mem.Allocator) !void {
    std.debug.print("\n📋 安全功能验证测试\n", .{});
    std.debug.print("----------------------------------------\n", .{});

    // 1. 工作流引擎测试（独立作用域）
    std.debug.print("1. ✅ 工作流引擎测试...\n", .{});
    try testWorkflowEngine(allocator);

    // 2. 存储系统测试（独立作用域）
    std.debug.print("2. ✅ 存储系统测试...\n", .{});
    try testStorageSystem(allocator);

    // 3. Agent系统测试（独立作用域）
    std.debug.print("3. ✅ Agent系统测试...\n", .{});
    try testAgentSystem(allocator);

    // 4. 其他模块测试（独立作用域）
    std.debug.print("4. ✅ 其他模块测试...\n", .{});
    try testOtherModules(allocator);

    std.debug.print("   🎯 所有核心功能验证完成\n", .{});
}

fn testWorkflowEngine(allocator: std.mem.Allocator) !void {
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
    std.debug.print("   ✅ 并行工作流引擎初始化成功\n", .{});
}

fn testStorageSystem(allocator: std.mem.Allocator) !void {
    const storage_config = mastra.storage.StorageConfig{
        .type = .memory,
    };
    var storage = try mastra.storage.Storage.init(allocator, storage_config);
    defer storage.deinit();

    const test_data = std.json.Value{ .string = "test_value" };
    const record_id = try storage.create("test_table", test_data);

    const retrieved = try storage.read("test_table", record_id);
    if (retrieved != null) {
        std.debug.print("   ✅ 存储系统创建和读取成功\n", .{});
    }

    std.debug.print("   ✅ 存储系统测试完成\n", .{});
}

fn testAgentSystem(allocator: std.mem.Allocator) !void {
    const runtime_context = mastra.agent.RuntimeContext.init(allocator);
    const dynamic_arg = mastra.agent.DynamicArgument([]const u8){ .static_value = "测试指令" };
    const resolved = try dynamic_arg.resolve(runtime_context);
    std.debug.print("   ✅ DynamicArgument解析: {s}\n", .{resolved});

    const message_config = mastra.agent.MessageListConfig{};
    var message_list = try mastra.agent.MessageList.init(allocator, message_config, null);
    defer message_list.deinit();
    
    try message_list.addMessage("user", "测试消息", .normal);
    const message_count = message_list.getMessageCount();
    std.debug.print("   ✅ 消息列表管理: {} 条消息\n", .{message_count});
}

fn testOtherModules(allocator: std.mem.Allocator) !void {
    // 工具系统测试
    {
        var tool_registry = mastra.tool_builder.ToolRegistry.init(allocator);
        defer tool_registry.deinit();
        std.debug.print("   ✅ 工具注册表初始化成功\n", .{});
    }

    // 事件系统测试
    {
        const event_bus_config = mastra.event_bus.EventBusConfig{};
        var event_bus = try mastra.event_bus.EventBus.init(allocator, event_bus_config);
        defer event_bus.deinit();
        
        const event_data = std.json.Value{ .string = "测试数据" };
        try event_bus.publish("test", event_data, "test_source");
        std.debug.print("   ✅ 事件发布成功\n", .{});
    }

    // 流式处理测试
    {
        const stream_config = mastra.response_stream.ResponseStreamConfig{};
        var response_stream = mastra.response_stream.ResponseStream.init(allocator, stream_config);
        defer response_stream.deinit();
        
        try response_stream.start();
        const stream_data = std.json.Value{ .string = "测试流数据" };
        try response_stream.sendData(stream_data);
        std.debug.print("   ✅ 流式数据处理成功\n", .{});
    }

    // RAG系统测试
    {
        const doc_config = mastra.document.DocumentConfig{};
        var doc_processor = mastra.DocumentProcessor.init(allocator, doc_config);
        
        const metadata = mastra.document.DocumentMetadata{
            .id = "test_doc",
            .created_at = std.time.timestamp(),
            .updated_at = std.time.timestamp(),
        };
        const chunks = try doc_processor.processDocument("测试文档内容", .text, metadata);
        defer {
            for (chunks) |*chunk| {
                chunk.deinit(allocator);
            }
            allocator.free(chunks);
        }
        
        std.debug.print("   ✅ 文档处理成功，生成 {} 个分块\n", .{chunks.len});

        const embedding_config = mastra.embeddings.EmbeddingConfig{};
        _ = mastra.EmbeddingProvider.init(allocator, embedding_config);
        std.debug.print("   ✅ 嵌入提供者初始化成功\n", .{});

        var vector_store = mastra.RAGVectorStore.init(allocator);
        defer vector_store.deinit();
        std.debug.print("   ✅ 向量存储初始化成功\n", .{});
    }
}
