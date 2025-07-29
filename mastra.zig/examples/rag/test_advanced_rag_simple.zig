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

    std.debug.print("🧠 高级RAG系统测试（简化版）\n", .{});
    std.debug.print("==================================================\n", .{});

    // 测试文档处理系统
    try testDocumentProcessing(allocator);

    // 测试向量嵌入系统
    try testEmbeddingSystem(allocator);

    // 测试知识图谱RAG
    try testGraphRAG(allocator);

    // 测试完整RAG工作流
    try testCompleteRAGWorkflow(allocator);

    std.debug.print("\n🎉 高级RAG系统测试完成！\n", .{});
    std.debug.print("==================================================\n", .{});
}

fn testDocumentProcessing(allocator: std.mem.Allocator) !void {
    std.debug.print("\n1. 📄 文档处理系统测试\n", .{});
    std.debug.print("----------------------------------------\n", .{});

    // 创建文档处理器
    const doc_config = mastra.document.DocumentConfig{};
    var doc_processor = mastra.document.DocumentProcessor.init(allocator, doc_config);

    // 测试基本文档处理
    var metadata = std.StringHashMap([]const u8).init(allocator);
    defer metadata.deinit();
    try metadata.put("source", "测试文档");

    const document = mastra.document.Document{
        .id = "test_doc",
        .content = "这是一个测试文档，包含了一些重要的信息。人工智能是计算机科学的一个分支。",
        .format = .text,
        .metadata = metadata,
    };

    const processed = try doc_processor.processDocument(document);
    std.debug.print("   ✅ 处理文档: {} 个分块\n", .{processed.chunks.len});

    if (processed.chunks.len > 0) {
        const first_chunk = processed.chunks[0];
        std.debug.print("   ✅ 第一个分块: {s}\n", .{first_chunk.content});
    }

    std.debug.print("   🎯 文档处理系统测试完成\n", .{});
}

fn testEmbeddingSystem(allocator: std.mem.Allocator) !void {
    std.debug.print("\n2. 🔢 向量嵌入系统测试\n", .{});
    std.debug.print("----------------------------------------\n", .{});

    // 创建嵌入提供者
    const embedding_config = mastra.embeddings.EmbeddingConfig{};
    var embedding_provider = mastra.embeddings.EmbeddingProvider.init(allocator, embedding_config);

    // 测试文本向量化
    const test_text = "人工智能是计算机科学的一个分支";
    const embedding = try embedding_provider.embed(test_text);
    std.debug.print("   ✅ 文本向量化: {} 维向量\n", .{embedding.len});

    // 显示向量的前几个维度
    if (embedding.len >= 5) {
        std.debug.print("   ✅ 前5维: [{d:.3}, {d:.3}, {d:.3}, {d:.3}, {d:.3}]\n", .{ embedding[0], embedding[1], embedding[2], embedding[3], embedding[4] });
    }

    // 测试相似度计算
    const embedding1 = try embedding_provider.embed("人工智能技术");
    const embedding2 = try embedding_provider.embed("AI技术发展");

    const similarity = try embedding_provider.cosineSimilarity(embedding1, embedding2);
    std.debug.print("   ✅ 相似度计算: {d:.3}\n", .{similarity});

    std.debug.print("   🎯 向量嵌入系统测试完成\n", .{});
}

fn testGraphRAG(allocator: std.mem.Allocator) !void {
    std.debug.print("\n3. 🕸️ 知识图谱RAG测试\n", .{});
    std.debug.print("----------------------------------------\n", .{});

    // 创建知识图谱
    var knowledge_graph = try mastra.graph_rag.KnowledgeGraph.init(allocator);
    defer knowledge_graph.deinit();

    // 添加实体
    var properties = std.StringHashMap([]const u8).init(allocator);
    defer properties.deinit();
    try properties.put("domain", "computer_science");

    const entity = mastra.graph_rag.Entity{
        .id = "ai",
        .name = "人工智能",
        .entity_type = "concept",
        .properties = properties,
    };

    try knowledge_graph.addEntity(entity);
    std.debug.print("   ✅ 添加实体: {s} ({s})\n", .{ entity.name, entity.entity_type });

    // 测试图谱查询
    const neighbors = try knowledge_graph.getNeighbors("ai");
    defer allocator.free(neighbors);
    std.debug.print("   ✅ 'ai'的邻居节点数量: {}\n", .{neighbors.len});

    // 创建图RAG系统
    var graph_rag = try mastra.graph_rag.GraphRAG.init(allocator, knowledge_graph);
    defer graph_rag.deinit();

    // 测试图增强检索
    const query = "什么是机器学习？";
    const enhanced_context = try graph_rag.enhanceQuery(query);
    defer allocator.free(enhanced_context);
    std.debug.print("   ✅ 图增强查询: {s}\n", .{enhanced_context});

    std.debug.print("   🎯 知识图谱RAG测试完成\n", .{});
}

fn testCompleteRAGWorkflow(allocator: std.mem.Allocator) !void {
    std.debug.print("\n4. 🔄 完整RAG工作流测试\n", .{});
    std.debug.print("----------------------------------------\n", .{});

    // 创建RAG系统
    const rag_config = mastra.rag.RAGConfig{};
    var rag_system = mastra.rag.RAGSystem.init(allocator, rag_config);
    defer rag_system.deinit();

    // 添加文档到知识库
    const knowledge_docs = [_][]const u8{
        "人工智能（AI）是计算机科学的一个分支，致力于创建能够执行通常需要人类智能的任务的系统。",
        "机器学习是人工智能的一个子集，它使计算机能够在没有明确编程的情况下学习和改进。",
        "深度学习是机器学习的一个子集，使用多层神经网络来模拟人脑的工作方式。",
    };

    std.debug.print("   📚 构建知识库:\n", .{});
    for (knowledge_docs, 0..) |doc_content, i| {
        var metadata = std.StringHashMap([]const u8).init(allocator);
        defer metadata.deinit();
        try metadata.put("topic", "AI");

        const doc_id = try std.fmt.allocPrint(allocator, "doc_{}", .{i});
        defer allocator.free(doc_id);

        const document = mastra.document.Document{
            .id = doc_id,
            .content = doc_content,
            .format = .text,
            .metadata = metadata,
        };

        try rag_system.addDocument(document);
        std.debug.print("   ✅ 添加文档{}: {} 字符\n", .{ i + 1, doc_content.len });
    }

    // 测试检索增强生成
    const query = "什么是人工智能？";
    const search_config = mastra.embeddings.SearchConfig{
        .top_k = 3,
        .similarity_threshold = 0.5,
    };

    const rag_result = try rag_system.query(query, search_config);
    defer rag_result.deinit(allocator);

    std.debug.print("   ✅ 查询: {s}\n", .{query});
    std.debug.print("   ✅ 检索到 {} 个相关文档\n", .{rag_result.retrieved_chunks.len});

    if (rag_result.retrieved_chunks.len > 0) {
        const best_match = rag_result.retrieved_chunks[0];
        std.debug.print("   ✅ 最佳匹配相似度: {d:.3}\n", .{best_match.similarity});
    }

    std.debug.print("   🎯 完整RAG工作流测试完成\n", .{});
}
