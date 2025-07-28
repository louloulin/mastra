const std = @import("std");
const mastra = @import("mastra");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("🚀 RAG系统功能测试\n", .{});
    std.debug.print("==================================================\n", .{});

    try testRAGSystem(allocator);

    std.debug.print("\n🎉 RAG系统测试完成！\n", .{});
    std.debug.print("==================================================\n", .{});
}

fn testRAGSystem(allocator: std.mem.Allocator) !void {
    std.debug.print("\n📋 RAG系统功能测试\n", .{});
    std.debug.print("----------------------------------------\n", .{});

    // 1. 测试文档处理器
    std.debug.print("1. 测试文档处理器...\n", .{});

    const doc_config = mastra.document.DocumentConfig{
        .chunk_size = 200, // 使用合理的分块大小
        .chunk_overlap = 50,
        .min_chunk_size = 50, // 设置最小分块大小
    };
    var doc_processor = mastra.DocumentProcessor.init(allocator, doc_config);

    const test_content = "这是一个测试文档。它包含多个段落。第二个段落包含更多信息。";

    const metadata = mastra.document.DocumentMetadata{
        .id = "test_doc",
        .created_at = std.time.timestamp(),
        .updated_at = std.time.timestamp(),
    };

    std.debug.print("   🔄 开始处理文档...\n", .{});
    const chunks = try doc_processor.processDocument(test_content, .text, metadata);
    defer {
        for (chunks) |*chunk| {
            chunk.deinit(allocator);
        }
        allocator.free(chunks);
    }

    std.debug.print("   ✅ 文档处理成功，生成 {} 个分块\n", .{chunks.len});

    for (chunks, 0..) |chunk, i| {
        std.debug.print("   📄 分块 {}: {} 字符\n", .{ i + 1, chunk.content.len });
    }

    // 2. 测试嵌入提供者
    std.debug.print("2. 测试嵌入提供者...\n", .{});

    const embedding_config = mastra.embeddings.EmbeddingConfig{
        .dimensions = 128, // 使用较小的维度避免内存问题
    };
    var embedding_provider = mastra.EmbeddingProvider.init(allocator, embedding_config);

    const test_text = "这是一个测试文本";
    std.debug.print("   🔄 生成嵌入向量...\n", .{});
    const embedding = try embedding_provider.embedText(test_text);
    defer allocator.free(embedding);

    std.debug.print("   ✅ 嵌入生成成功，维度: {}\n", .{embedding.len});

    // 3. 测试向量存储
    std.debug.print("3. 测试向量存储...\n", .{});

    var vector_store = mastra.embeddings.VectorStore.init(allocator);
    defer vector_store.deinit();

    std.debug.print("   🔄 添加分块到向量存储...\n", .{});
    // 为每个分块生成嵌入
    for (chunks) |*chunk| {
        if (chunk.embedding == null) {
            chunk.embedding = try embedding_provider.embedText(chunk.content);
        }
    }

    try vector_store.addChunks(chunks);
    std.debug.print("   ✅ 向量存储成功，存储了 {} 个向量\n", .{chunks.len});

    // 4. 测试相似性搜索
    std.debug.print("4. 测试相似性搜索...\n", .{});

    const query = "测试文档";
    std.debug.print("   🔄 生成查询嵌入...\n", .{});
    const query_embedding = try embedding_provider.embedText(query);
    defer allocator.free(query_embedding);

    const search_config = mastra.embeddings.SearchConfig{
        .top_k = 2,
        .min_score = 0.0,
    };

    std.debug.print("   🔄 执行相似性搜索...\n", .{});
    const search_results = try vector_store.search(query_embedding, search_config);
    defer allocator.free(search_results);

    std.debug.print("   ✅ 搜索完成，找到 {} 个相关结果\n", .{search_results.len});

    for (search_results, 0..) |result, i| {
        const preview = if (result.chunk.content.len > 30) result.chunk.content[0..30] else result.chunk.content;
        std.debug.print("   🔍 结果 {}: 相似度 {d:.3}, 内容: {s}...\n", .{ i + 1, result.score, preview });
    }

    // 注意：不要调用 result.deinit()，因为 chunk 是从 vector_store 借用的

    std.debug.print("   ✅ RAG系统基础功能验证完成\n", .{});
}
