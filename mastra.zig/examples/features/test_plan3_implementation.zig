const std = @import("std");
const mastra = @import("mastra");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("🚀 Plan3 功能实现验证测试\n", .{});
    std.debug.print("==================================================\n", .{});

    // 测试P0级别功能
    try testP0Features(allocator);

    // 测试P1级别功能
    try testP1Features(allocator);

    // 测试P2级别功能
    try testP2Features(allocator);

    std.debug.print("\n🎉 所有功能验证完成！\n", .{});
    std.debug.print("==================================================\n", .{});
}

fn testP0Features(allocator: std.mem.Allocator) !void {
    std.debug.print("\n📋 P0级别核心功能测试\n", .{});
    std.debug.print("----------------------------------------\n", .{});

    // 1. Agent系统增强测试
    std.debug.print("1. 测试Agent系统增强...\n", .{});

    // 测试DynamicArgument
    const static_arg = mastra.agent.DynamicArgument([]const u8){ .static_value = "静态值" };
    const resolved_static = try static_arg.resolve(mastra.agent.RuntimeContext.init(allocator));
    std.debug.print("   ✅ DynamicArgument静态值: {s}\n", .{resolved_static});

    // 测试MessageList
    const message_config = mastra.agent.MessageListConfig{};
    var message_list = try mastra.agent.MessageList.init(allocator, message_config, null);
    defer message_list.deinit();

    try message_list.addMessage("user", "测试消息", .normal);
    std.debug.print("   ✅ MessageList消息管理: {} 条消息\n", .{message_list.messages.items.len});

    // 2. 并行工作流引擎测试
    std.debug.print("2. 测试并行工作流引擎...\n", .{});

    // 创建线程池配置
    const thread_pool_config = mastra.workflow.ThreadPoolConfig{
        .max_threads = 2,
        .queue_size = 100,
    };

    // 创建日志器
    const logger_config = mastra.utils.LoggerConfig{
        .level = .info,
    };
    var logger = try mastra.utils.Logger.init(allocator, logger_config);
    defer logger.deinit();

    // 创建执行引擎
    var execution_engine = try mastra.workflow.ExecutionEngine.init(allocator, thread_pool_config, logger);
    defer execution_engine.deinit();
    std.debug.print("   ✅ ExecutionEngine初始化成功\n", .{});

    // 3. 存储系统测试
    std.debug.print("3. 测试多后端存储系统...\n", .{});

    // 测试基础存储
    var storage = try mastra.storage.Storage.init(allocator);
    defer storage.deinit();
    try storage.save("test_key", "test_value");
    const retrieved_value = try storage.load("test_key");
    if (retrieved_value) |value| {
        defer allocator.free(value);
        std.debug.print("   ✅ 基础存储: {s}\n", .{value});
    }

    std.debug.print("   ✅ P0级别核心功能验证完成\n", .{});
}

fn testP1Features(allocator: std.mem.Allocator) !void {
    std.debug.print("\n📋 P1级别重要功能测试\n", .{});
    std.debug.print("----------------------------------------\n", .{});

    // 1. RAG系统测试
    std.debug.print("1. 测试RAG系统...\n", .{});

    // 创建文档处理器
    var doc_processor = try mastra.rag.DocumentProcessor.init(allocator);
    defer doc_processor.deinit();

    const test_document = mastra.rag.Document{
        .id = "test_doc",
        .content = "这是一个测试文档，用于验证RAG系统的功能。",
        .format = .text,
        .metadata = std.StringHashMap([]const u8).init(allocator),
    };

    const processed_doc = try doc_processor.processDocument(test_document);
    std.debug.print("   ✅ 文档处理: {} 个分块\n", .{processed_doc.chunks.len});

    // 2. 事件系统测试
    std.debug.print("2. 测试事件系统...\n", .{});

    var event_bus = try mastra.events.EventBus.init(allocator);
    defer event_bus.deinit();

    const test_event = mastra.events.Event{
        .id = "test_event",
        .event_type = "test",
        .data = "测试事件数据",
        .timestamp = std.time.timestamp(),
        .priority = .normal,
    };

    try event_bus.publish(test_event);
    std.debug.print("   ✅ 事件发布成功\n", .{});

    // 3. 流式处理测试
    std.debug.print("3. 测试流式处理...\n", .{});

    var response_stream = try mastra.streaming.ResponseStream.init(allocator);
    defer response_stream.deinit();

    try response_stream.write("测试流式数据");
    std.debug.print("   ✅ 流式数据写入成功\n", .{});

    std.debug.print("   ✅ P1级别重要功能验证完成\n", .{});
}

fn testP2Features(allocator: std.mem.Allocator) !void {
    std.debug.print("\n📋 P2级别增强功能测试\n", .{});
    std.debug.print("----------------------------------------\n", .{});

    // 1. 图RAG系统测试
    std.debug.print("1. 测试图RAG系统...\n", .{});

    var knowledge_graph = try mastra.rag.KnowledgeGraph.init(allocator);
    defer knowledge_graph.deinit();

    const entity1 = mastra.rag.Entity{
        .id = "entity1",
        .name = "实体1",
        .entity_type = "person",
        .properties = std.StringHashMap([]const u8).init(allocator),
    };

    try knowledge_graph.addEntity(entity1);
    std.debug.print("   ✅ 知识图谱实体添加成功\n", .{});

    // 2. 评估系统测试
    std.debug.print("2. 测试评估系统...\n", .{});

    var evaluation_session = try mastra.evaluation.EvaluationSession.init(allocator, "test_session");
    defer evaluation_session.deinit();

    const test_case = mastra.evaluation.TestCase{
        .id = "test_case_1",
        .input = "测试输入",
        .expected_output = "期望输出",
        .metadata = std.StringHashMap([]const u8).init(allocator),
    };

    try evaluation_session.addTestCase(test_case);
    std.debug.print("   ✅ 评估测试用例添加成功\n", .{});

    // 3. 集成生态测试
    std.debug.print("3. 测试集成生态...\n", .{});

    var integration_manager = try mastra.integration.IntegrationManager.init(allocator);
    defer integration_manager.deinit();

    const auth_config = mastra.integration.AuthConfig{
        .auth_type = .api_key,
        .credentials = "test_api_key",
    };

    try integration_manager.registerAuth("test_service", auth_config);
    std.debug.print("   ✅ 认证配置注册成功\n", .{});

    std.debug.print("   ✅ P2级别增强功能验证完成\n", .{});
}
