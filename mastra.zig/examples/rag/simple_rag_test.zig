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

    std.debug.print("🚀 简化RAG系统测试\n", .{});
    std.debug.print("==================================================\n", .{});

    try testSimpleRAG(allocator);

    std.debug.print("\n🎉 简化RAG系统测试完成！\n", .{});
    std.debug.print("==================================================\n", .{});
}

fn testSimpleRAG(allocator: std.mem.Allocator) !void {
    std.debug.print("\n📋 简化RAG功能测试\n", .{});
    std.debug.print("----------------------------------------\n", .{});

    // 1. 测试文档处理器
    std.debug.print("1. 测试文档处理器...\n", .{});

    const doc_config = mastra.document.DocumentConfig{
        .chunk_size = 500,
        .chunk_overlap = 0, // 不使用重叠避免复杂性
        .min_chunk_size = 10,
    };
    var doc_processor = mastra.document.DocumentProcessor.init(allocator, doc_config);

    const test_content = "这是一个简单的测试文档。";

    const metadata = mastra.document.DocumentMetadata{
        .id = "simple_doc",
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

    std.debug.print("   ✅ 文档处理成功，生成 {} 个分块\n", .{chunks.len});
    if (chunks.len > 0) {
        std.debug.print("   📄 分块内容: {s}\n", .{chunks[0].content});
    }

    // 2. 测试嵌入提供者
    std.debug.print("2. 测试嵌入提供者...\n", .{});

    const embedding_config = mastra.embeddings.EmbeddingConfig{
        .dimensions = 64, // 使用更小的维度
    };
    var embedding_provider = mastra.embeddings.EmbeddingProvider.init(allocator, embedding_config);

    const test_text = "测试";
    const embedding = try embedding_provider.embedText(test_text);
    defer allocator.free(embedding);

    std.debug.print("   ✅ 嵌入生成成功，维度: {}\n", .{embedding.len});

    std.debug.print("   ✅ 简化RAG系统基础功能验证完成\n", .{});
}
