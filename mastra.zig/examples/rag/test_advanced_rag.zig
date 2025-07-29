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

    std.debug.print("🧠 高级RAG系统测试\n", .{});
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
    var doc_processor = try mastra.document.DocumentProcessor.init(allocator);
    defer doc_processor.deinit();

    // 测试不同格式的文档处理
    const documents = [_]struct {
        format: mastra.rag.DocumentType,
        content: []const u8,
        name: []const u8,
    }{
        .{ .format = .text, .content = "这是一个纯文本文档，包含了一些重要的信息。", .name = "文本文档" },
        .{ .format = .markdown, .content = "# 标题\n\n这是一个**Markdown**文档。\n\n- 列表项1\n- 列表项2", .name = "Markdown文档" },
        .{ .format = .html, .content = "<html><body><h1>HTML文档</h1><p>这是一个HTML文档。</p></body></html>", .name = "HTML文档" },
        .{ .format = .json, .content = "{\"title\": \"JSON文档\", \"content\": \"这是一个JSON格式的文档\"}", .name = "JSON文档" },
        .{ .format = .csv, .content = "姓名,年龄,城市\n张三,25,北京\n李四,30,上海", .name = "CSV文档" },
    };

    for (documents) |doc_info| {
        var metadata = std.StringHashMap([]const u8).init(allocator);
        defer metadata.deinit();
        try metadata.put("source", doc_info.name);

        const document = mastra.rag.Document{
            .id = doc_info.name,
            .content = doc_info.content,
            .format = doc_info.format,
            .metadata = metadata,
        };

        const processed = try doc_processor.processDocument(document);
        std.debug.print("   ✅ 处理{s}: {} 个分块\n", .{ doc_info.name, processed.chunks.len });

        // 显示第一个分块的内容（如果存在）
        if (processed.chunks.len > 0) {
            const first_chunk = processed.chunks[0];
            const preview = if (first_chunk.content.len > 50)
                first_chunk.content[0..50]
            else
                first_chunk.content;
            std.debug.print("      预览: {s}...\n", .{preview});
        }
    }

    std.debug.print("   🎯 文档处理系统测试完成\n", .{});
}

fn testEmbeddingSystem(allocator: std.mem.Allocator) !void {
    std.debug.print("\n2. 🔢 向量嵌入系统测试\n", .{});
    std.debug.print("----------------------------------------\n", .{});

    // 创建嵌入提供者
    var embedding_provider = try mastra.rag.EmbeddingProvider.init(allocator);
    defer embedding_provider.deinit();

    // 测试文本向量化
    const test_texts = [_][]const u8{
        "人工智能是计算机科学的一个分支",
        "机器学习是人工智能的核心技术",
        "深度学习使用神经网络进行学习",
        "自然语言处理处理人类语言",
        "计算机视觉让机器理解图像",
    };

    std.debug.print("   📊 向量化测试文本:\n", .{});
    for (test_texts, 0..) |text, i| {
        const embedding = try embedding_provider.embed(text);
        std.debug.print("   ✅ 文本{}: {} 维向量\n", .{ i + 1, embedding.len });

        // 显示向量的前几个维度
        if (embedding.len >= 5) {
            std.debug.print("      前5维: [{d:.3}, {d:.3}, {d:.3}, {d:.3}, {d:.3}]\n", .{ embedding[0], embedding[1], embedding[2], embedding[3], embedding[4] });
        }
    }

    // 测试相似度计算
    const embedding1 = try embedding_provider.embed("人工智能技术");
    const embedding2 = try embedding_provider.embed("AI技术发展");
    const embedding3 = try embedding_provider.embed("天气预报系统");

    const similarity1_2 = try embedding_provider.cosineSimilarity(embedding1, embedding2);
    const similarity1_3 = try embedding_provider.cosineSimilarity(embedding1, embedding3);

    std.debug.print("   ✅ 相似度计算:\n", .{});
    std.debug.print("      '人工智能技术' vs 'AI技术发展': {d:.3}\n", .{similarity1_2});
    std.debug.print("      '人工智能技术' vs '天气预报系统': {d:.3}\n", .{similarity1_3});

    std.debug.print("   🎯 向量嵌入系统测试完成\n", .{});
}

fn testGraphRAG(allocator: std.mem.Allocator) !void {
    std.debug.print("\n3. 🕸️ 知识图谱RAG测试\n", .{});
    std.debug.print("----------------------------------------\n", .{});

    // 创建知识图谱
    var knowledge_graph = try mastra.rag.KnowledgeGraph.init(allocator);
    defer knowledge_graph.deinit();

    // 添加实体
    const entities = [_]struct {
        id: []const u8,
        name: []const u8,
        entity_type: []const u8,
    }{
        .{ .id = "ai", .name = "人工智能", .entity_type = "concept" },
        .{ .id = "ml", .name = "机器学习", .entity_type = "concept" },
        .{ .id = "dl", .name = "深度学习", .entity_type = "concept" },
        .{ .id = "nlp", .name = "自然语言处理", .entity_type = "concept" },
        .{ .id = "cv", .name = "计算机视觉", .entity_type = "concept" },
    };

    for (entities) |entity_info| {
        var properties = std.StringHashMap([]const u8).init(allocator);
        defer properties.deinit();
        try properties.put("domain", "computer_science");

        const entity = mastra.rag.Entity{
            .id = entity_info.id,
            .name = entity_info.name,
            .entity_type = entity_info.entity_type,
            .properties = properties,
        };

        try knowledge_graph.addEntity(entity);
        std.debug.print("   ✅ 添加实体: {s} ({s})\n", .{ entity_info.name, entity_info.entity_type });
    }

    // 添加关系
    const relations = [_]struct {
        from: []const u8,
        to: []const u8,
        relation_type: []const u8,
    }{
        .{ .from = "ml", .to = "ai", .relation_type = "is_part_of" },
        .{ .from = "dl", .to = "ml", .relation_type = "is_part_of" },
        .{ .from = "nlp", .to = "ai", .relation_type = "is_part_of" },
        .{ .from = "cv", .to = "ai", .relation_type = "is_part_of" },
    };

    for (relations) |rel| {
        var properties = std.StringHashMap([]const u8).init(allocator);
        defer properties.deinit();
        try properties.put("strength", "high");

        const relation = mastra.rag.Relation{
            .from_entity = rel.from,
            .to_entity = rel.to,
            .relation_type = rel.relation_type,
            .weight = 0.8,
            .properties = properties,
        };

        try knowledge_graph.addRelation(relation);
        std.debug.print("   ✅ 添加关系: {s} -> {s} ({s})\n", .{ rel.from, rel.to, rel.relation_type });
    }

    // 测试图谱查询
    const neighbors = try knowledge_graph.getNeighbors("ai");
    defer allocator.free(neighbors);
    std.debug.print("   ✅ 'ai'的邻居节点数量: {}\n", .{neighbors.len});

    // 创建图RAG系统
    var graph_rag = try mastra.rag.GraphRAG.init(allocator, knowledge_graph);
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
    var rag_system = try mastra.rag.RAGSystem.init(allocator);
    defer rag_system.deinit();

    // 添加文档到知识库
    const knowledge_docs = [_][]const u8{
        "人工智能（AI）是计算机科学的一个分支，致力于创建能够执行通常需要人类智能的任务的系统。",
        "机器学习是人工智能的一个子集，它使计算机能够在没有明确编程的情况下学习和改进。",
        "深度学习是机器学习的一个子集，使用多层神经网络来模拟人脑的工作方式。",
        "自然语言处理（NLP）是人工智能的一个分支，专注于计算机与人类语言之间的交互。",
        "计算机视觉是人工智能的一个领域，致力于让计算机能够理解和解释视觉信息。",
    };

    std.debug.print("   📚 构建知识库:\n", .{});
    for (knowledge_docs, 0..) |doc_content, i| {
        const doc_id = try std.fmt.allocPrint(allocator, "doc_{}", .{i});
        defer allocator.free(doc_id);

        var metadata = std.StringHashMap([]const u8).init(allocator);
        defer metadata.deinit();
        try metadata.put("topic", "AI");

        const document = mastra.rag.Document{
            .id = doc_id,
            .content = doc_content,
            .format = .text,
            .metadata = metadata,
        };

        try rag_system.addDocument(document);
        std.debug.print("   ✅ 添加文档{}: {} 字符\n", .{ i + 1, doc_content.len });
    }

    // 测试检索增强生成
    const queries = [_][]const u8{
        "什么是人工智能？",
        "机器学习和深度学习的关系是什么？",
        "自然语言处理的应用有哪些？",
    };

    std.debug.print("   🔍 检索增强生成测试:\n", .{});
    for (queries, 0..) |query, i| {
        const rag_result = try rag_system.query(query, .{
            .top_k = 3,
            .similarity_threshold = 0.5,
        });
        defer rag_result.deinit();

        std.debug.print("   ✅ 查询{}: {s}\n", .{ i + 1, query });
        std.debug.print("      检索到 {} 个相关文档\n", .{rag_result.retrieved_docs.len});

        if (rag_result.retrieved_docs.len > 0) {
            const best_match = rag_result.retrieved_docs[0];
            std.debug.print("      最佳匹配相似度: {d:.3}\n", .{best_match.similarity});
        }

        if (rag_result.generated_response.len > 0) {
            const preview = if (rag_result.generated_response.len > 100)
                rag_result.generated_response[0..100]
            else
                rag_result.generated_response;
            std.debug.print("      生成回答预览: {s}...\n", .{preview});
        }
    }

    // 测试RAG系统统计
    const stats = try rag_system.getStatistics();
    std.debug.print("   📊 RAG系统统计:\n", .{});
    std.debug.print("      文档总数: {}\n", .{stats.total_documents});
    std.debug.print("      分块总数: {}\n", .{stats.total_chunks});
    std.debug.print("      向量维度: {}\n", .{stats.embedding_dimension});
    std.debug.print("      查询总数: {}\n", .{stats.total_queries});

    std.debug.print("   🎯 完整RAG工作流测试完成\n", .{});
}
