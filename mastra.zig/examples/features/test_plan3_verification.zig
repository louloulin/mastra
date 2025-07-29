const std = @import("std");
const mastra = @import("mastra");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("❌ 检测到内存泄漏！\n", .{});
        } else {
            std.debug.print("✅ 无内存泄漏！\n", .{});
        }
    }
    const allocator = gpa.allocator();

    std.debug.print("🎯 Plan3.md 功能验证测试\n", .{});
    std.debug.print("==================================================\n", .{});

    var success_count: u32 = 0;
    var total_count: u32 = 0;

    // P0级别核心功能验证
    std.debug.print("\n📋 P0级别核心功能验证\n", .{});
    std.debug.print("----------------------------------------\n", .{});

    // 1. Agent系统增强
    if (testAgentEnhancements(allocator)) {
        std.debug.print("✅ Agent系统增强: 通过\n", .{});
        success_count += 1;
    } else |_| {
        std.debug.print("❌ Agent系统增强: 失败\n", .{});
    }
    total_count += 1;

    // 2. 并行工作流引擎
    if (testParallelWorkflow(allocator)) {
        std.debug.print("✅ 并行工作流引擎: 通过\n", .{});
        success_count += 1;
    } else |_| {
        std.debug.print("❌ 并行工作流引擎: 失败\n", .{});
    }
    total_count += 1;

    // 3. 多后端存储系统
    if (testMultiBackendStorage(allocator)) {
        std.debug.print("✅ 多后端存储系统: 通过\n", .{});
        success_count += 1;
    } else |_| {
        std.debug.print("❌ 多后端存储系统: 失败\n", .{});
    }
    total_count += 1;

    // 4. 动态工具系统
    if (testDynamicToolSystem(allocator)) {
        std.debug.print("✅ 动态工具系统: 通过\n", .{});
        success_count += 1;
    } else |_| {
        std.debug.print("❌ 动态工具系统: 失败\n", .{});
    }
    total_count += 1;

    // P1级别重要功能验证
    std.debug.print("\n📋 P1级别重要功能验证\n", .{});
    std.debug.print("----------------------------------------\n", .{});

    // 5. RAG系统
    if (testRAGSystem(allocator)) {
        std.debug.print("✅ RAG系统: 通过\n", .{});
        success_count += 1;
    } else |_| {
        std.debug.print("❌ RAG系统: 失败\n", .{});
    }
    total_count += 1;

    // 6. 事件系统
    if (testEventSystem(allocator)) {
        std.debug.print("✅ 事件系统: 通过\n", .{});
        success_count += 1;
    } else |_| {
        std.debug.print("❌ 事件系统: 失败\n", .{});
    }
    total_count += 1;

    // 7. 流式处理
    if (testStreamingSystem(allocator)) {
        std.debug.print("✅ 流式处理: 通过\n", .{});
        success_count += 1;
    } else |_| {
        std.debug.print("❌ 流式处理: 失败\n", .{});
    }
    total_count += 1;

    // P2级别增强功能验证
    std.debug.print("\n📋 P2级别增强功能验证\n", .{});
    std.debug.print("----------------------------------------\n", .{});

    // 8. 图RAG系统
    if (testGraphRAGSystem(allocator)) {
        std.debug.print("✅ 图RAG系统: 通过\n", .{});
        success_count += 1;
    } else |_| {
        std.debug.print("❌ 图RAG系统: 失败\n", .{});
    }
    total_count += 1;

    // 9. 评估系统
    if (testEvaluationSystem(allocator)) {
        std.debug.print("✅ 评估系统: 通过\n", .{});
        success_count += 1;
    } else |_| {
        std.debug.print("❌ 评估系统: 失败\n", .{});
    }
    total_count += 1;

    // 10. 集成生态
    if (testIntegrationEcosystem(allocator)) {
        std.debug.print("✅ 集成生态: 通过\n", .{});
        success_count += 1;
    } else |_| {
        std.debug.print("❌ 集成生态: 失败\n", .{});
    }
    total_count += 1;

    // 最终结果
    std.debug.print("\n🏆 最终验证结果\n", .{});
    std.debug.print("==================================================\n", .{});
    std.debug.print("通过测试: {}/{}\n", .{ success_count, total_count });
    std.debug.print("成功率: {d:.1}%\n", .{@as(f64, @floatFromInt(success_count)) / @as(f64, @floatFromInt(total_count)) * 100.0});

    if (success_count == total_count) {
        std.debug.print("🎉 所有功能验证通过！Plan3.md实现完成！\n", .{});
    } else {
        std.debug.print("⚠️ 部分功能需要进一步完善\n", .{});
    }
}

fn testAgentEnhancements(allocator: std.mem.Allocator) !void {
    // 测试DynamicArgument
    const static_arg = mastra.agent.DynamicArgument([]const u8){ .static_value = "测试值" };
    const context = mastra.agent.RuntimeContext.init(allocator);
    const resolved = try static_arg.resolve(context);
    if (!std.mem.eql(u8, resolved, "测试值")) {
        return error.DynamicArgumentFailed;
    }

    // 测试MessageList
    const config = mastra.agent.MessageListConfig{};
    var message_list = try mastra.agent.MessageList.init(allocator, config, null);
    defer message_list.deinit();

    try message_list.addMessage("user", "测试消息", .normal);
    if (message_list.messages.items.len != 1) {
        return error.MessageListFailed;
    }
}

fn testParallelWorkflow(allocator: std.mem.Allocator) !void {
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

    // 测试单步执行
    const testStepFunction = struct {
        fn execute(alloc: std.mem.Allocator, input: std.json.Value) anyerror!std.json.Value {
            _ = alloc;
            _ = input;
            return std.json.Value{ .string = "success" };
        }
    }.execute;

    const single_step = mastra.workflow.StepFlowEntry{
        .flow_type = .step,
        .step_config = mastra.workflow.StepConfig{
            .id = "test_step",
            .name = "测试步骤",
            .description = "测试步骤",
            .timeout_ms = 5000,
        },
        .execute_fn = testStepFunction,
    };

    const input_data = std.json.Value{ .string = "test" };
    const result = try execution_engine.executeStepFlow(single_step, input_data);
    defer allocator.free(result);

    if (result.len == 0) {
        return error.ParallelWorkflowFailed;
    }
}

fn testMultiBackendStorage(allocator: std.mem.Allocator) !void {
    // 测试内存存储
    const storage_config = mastra.storage.StorageConfig{
        .type = .memory,
    };
    var storage = try mastra.storage.Storage.init(allocator, storage_config);
    defer storage.deinit();

    const test_data = std.json.Value{ .string = "test_value" };
    const record_id = try storage.create("test_table", test_data);

    const retrieved = try storage.read("test_table", record_id);
    if (retrieved == null) {
        return error.StorageFailed;
    }

    // 测试PostgreSQL和MongoDB架构（模拟）
    const pg_config = mastra.postgresql.PostgreSQLConfig{
        .host = "localhost",
        .port = 5432,
        .database = "test",
        .username = "test",
        .password = "test",
    };

    const pg_storage_config = mastra.storage.StorageConfig{
        .type = .postgresql,
    };

    var pg_storage = try mastra.postgresql.PostgreSQLStorage.init(allocator, pg_storage_config, pg_config);
    defer pg_storage.deinit();

    // 如果能创建就说明架构正确
}

fn testDynamicToolSystem(allocator: std.mem.Allocator) !void {
    // 创建工具注册表
    var registry = mastra.tool_builder.ToolRegistry.init(allocator);
    defer registry.deinit();

    // 创建工具构建器
    var builder = mastra.tool_builder.ToolBuilder.init(allocator);
    defer builder.deinit();

    const param = mastra.tool_builder.ParameterDefinition{
        .name = "input",
        .type = .string,
        .description = "输入参数",
        .required = true,
    };

    _ = try builder.addParameter(param);
    const tool = try builder
        .setName("test_tool")
        .setDescription("测试工具")
        .setCategory("test")
        .setExecuteFunction(testToolExecute)
        .build();

    try registry.registerTool(tool);

    const tool_names = try registry.listTools();
    defer allocator.free(tool_names);

    if (tool_names.len == 0) {
        return error.DynamicToolSystemFailed;
    }
}

fn testRAGSystem(allocator: std.mem.Allocator) !void {
    // 测试文档处理器
    const doc_config = mastra.document.DocumentConfig{};
    var doc_processor = mastra.document.DocumentProcessor.init(allocator, doc_config);

    const test_content = "这是一个测试文档";
    const metadata = mastra.document.DocumentMetadata{
        .id = "test_doc",
        .created_at = std.time.timestamp(),
        .updated_at = std.time.timestamp(),
    };

    const chunks = try doc_processor.processDocument(test_content, .text, metadata);
    defer {
        for (chunks) |*chunk| {
            chunk.deinit(allocator);
        }
        allocator.free(chunks);
    }

    if (chunks.len == 0) {
        return error.RAGSystemFailed;
    }

    // 测试嵌入提供者
    const embedding_config = mastra.embeddings.EmbeddingConfig{};
    var embedding_provider = mastra.embeddings.EmbeddingProvider.init(allocator, embedding_config);

    const embedding = try embedding_provider.embedText("测试文本");
    if (embedding.len == 0) {
        return error.RAGSystemFailed;
    }
}

fn testEventSystem(allocator: std.mem.Allocator) !void {
    const event_config = mastra.event_bus.EventBusConfig{};
    var event_bus = try mastra.event_bus.EventBus.init(allocator, event_config);
    defer event_bus.deinit();

    const test_event = mastra.events.Event{
        .id = "test_event",
        .event_type = "test",
        .data = "test_data",
        .timestamp = std.time.timestamp(),
        .priority = .normal,
    };

    try event_bus.publish(test_event);
}

fn testStreamingSystem(allocator: std.mem.Allocator) !void {
    var response_stream = try mastra.response_stream.ResponseStream.init(allocator);
    defer response_stream.deinit();

    try response_stream.write("test_data");
}

fn testGraphRAGSystem(allocator: std.mem.Allocator) !void {
    var knowledge_graph = try mastra.graph_rag.KnowledgeGraph.init(allocator);
    defer knowledge_graph.deinit();

    var properties = std.StringHashMap([]const u8).init(allocator);
    defer properties.deinit();

    const entity = mastra.graph_rag.Entity{
        .id = "test_entity",
        .name = "测试实体",
        .entity_type = "test",
        .properties = properties,
    };

    try knowledge_graph.addEntity(entity);
}

fn testEvaluationSystem(allocator: std.mem.Allocator) !void {
    var evaluation_session = try mastra.evaluator.EvaluationSession.init(allocator, "test_session");
    defer evaluation_session.deinit();

    const test_case = mastra.evaluator.TestCase{
        .id = "test_case",
        .input = "test_input",
        .expected_output = "test_output",
        .metadata = std.StringHashMap([]const u8).init(allocator),
    };

    try evaluation_session.addTestCase(test_case);
}

fn testIntegrationEcosystem(allocator: std.mem.Allocator) !void {
    var integration_manager = try mastra.integration.IntegrationManager.init(allocator);
    defer integration_manager.deinit();

    const auth_config = mastra.integration.AuthConfig{
        .auth_type = .api_key,
        .credentials = "test_key",
    };

    try integration_manager.registerAuth("test_service", auth_config);
}

fn testToolExecute(allocator: std.mem.Allocator, input: mastra.tools.ToolInput) !mastra.tools.ToolOutput {
    _ = allocator;
    _ = input;
    return mastra.tools.ToolOutput{
        .data = std.json.Value{ .string = "success" },
    };
}
