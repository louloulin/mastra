const std = @import("std");
const document = @import("document.zig");
const embeddings = @import("embeddings.zig");

/// RAG system configuration
pub const RAGConfig = struct {
    document_config: document.DocumentConfig = .{},
    embedding_config: embeddings.EmbeddingConfig = .{},
    search_config: embeddings.SearchConfig = .{},
    enable_reranking: bool = false,
    enable_query_expansion: bool = false,
    context_window_size: usize = 4000,
    max_chunks_per_query: usize = 5,
};

/// RAG query context
pub const RAGContext = struct {
    query: []const u8,
    retrieved_chunks: []embeddings.SearchResult,
    context_text: []const u8,
    metadata: std.json.Value,

    pub fn deinit(self: *RAGContext, allocator: std.mem.Allocator) void {
        allocator.free(self.query);
        for (self.retrieved_chunks) |*result| {
            result.deinit(allocator);
        }
        allocator.free(self.retrieved_chunks);
        allocator.free(self.context_text);
    }
};

/// RAG system main interface
pub const RAGSystem = struct {
    allocator: std.mem.Allocator,
    config: RAGConfig,
    document_processor: document.DocumentProcessor,
    embedding_provider: embeddings.EmbeddingProvider,
    vector_store: embeddings.VectorStore,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: RAGConfig) Self {
        return Self{
            .allocator = allocator,
            .config = config,
            .document_processor = document.DocumentProcessor.init(allocator, config.document_config),
            .embedding_provider = embeddings.EmbeddingProvider.init(allocator, config.embedding_config),
            .vector_store = embeddings.VectorStore.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.vector_store.deinit();
    }

    /// Add a document to the RAG system
    pub fn addDocument(self: *Self, content: []const u8, doc_type: document.DocumentType, metadata: document.DocumentMetadata) !void {
        // Process document into chunks
        const chunks = try self.document_processor.processDocument(content, doc_type, metadata);

        // Generate embeddings for chunks
        try self.embedding_provider.embedDocumentChunks(chunks);

        // Add chunks to vector store (vector store takes ownership)
        try self.vector_store.addChunks(chunks);

        // Free the chunks array but not the individual chunks (vector store owns them now)
        self.allocator.free(chunks);

        std.log.info("Added document {s} with {d} chunks", .{ metadata.id, chunks.len });
    }

    /// Add multiple documents in batch
    pub fn addDocuments(self: *Self, documents: []DocumentInput) !void {
        for (documents) |doc| {
            try self.addDocument(doc.content, doc.doc_type, doc.metadata);
        }
    }

    /// Query the RAG system
    pub fn query(self: *Self, query_text: []const u8) !RAGContext {
        // Expand query if enabled
        const expanded_query = if (self.config.enable_query_expansion)
            try self.expandQuery(query_text)
        else
            try self.allocator.dupe(u8, query_text);
        defer if (self.config.enable_query_expansion) self.allocator.free(expanded_query);

        // Search for relevant chunks
        const search_results = try self.vector_store.searchByText(&self.embedding_provider, expanded_query, self.config.search_config);
        defer self.allocator.free(search_results);

        // Rerank results if enabled
        const final_results = if (self.config.enable_reranking)
            try self.rerankResults(query_text, search_results)
        else
            search_results;
        defer if (self.config.enable_reranking) self.allocator.free(final_results);

        // Limit results
        const max_chunks = @min(self.config.max_chunks_per_query, final_results.len);
        const selected_results = final_results[0..max_chunks];

        // Build context text
        const context_text = try self.buildContextText(selected_results);

        // Create metadata
        var metadata_obj = std.json.ObjectMap.init(self.allocator);
        try metadata_obj.put("query", std.json.Value{ .string = query_text });
        try metadata_obj.put("num_chunks", std.json.Value{ .integer = @intCast(selected_results.len) });
        try metadata_obj.put("context_length", std.json.Value{ .integer = @intCast(context_text.len) });

        return RAGContext{
            .query = try self.allocator.dupe(u8, query_text),
            .retrieved_chunks = try self.allocator.dupe(embeddings.SearchResult, selected_results),
            .context_text = context_text,
            .metadata = std.json.Value{ .object = metadata_obj },
        };
    }

    /// Remove a document from the RAG system
    pub fn removeDocument(self: *Self, document_id: []const u8) !usize {
        var removed_count: usize = 0;

        // Find and remove all chunks belonging to this document
        var i: usize = 0;
        while (i < self.vector_store.chunks.items.len) {
            const chunk = &self.vector_store.chunks.items[i];
            if (std.mem.eql(u8, chunk.document_id, document_id)) {
                _ = self.vector_store.removeChunk(chunk.id);
                removed_count += 1;
                // Don't increment i since we removed an item
            } else {
                i += 1;
            }
        }

        std.log.info("Removed {d} chunks for document {s}", .{ removed_count, document_id });
        return removed_count;
    }

    /// Update a document in the RAG system
    pub fn updateDocument(self: *Self, document_id: []const u8, content: []const u8, doc_type: document.DocumentType, metadata: document.DocumentMetadata) !void {
        // Remove existing document
        _ = try self.removeDocument(document_id);

        // Add updated document
        try self.addDocument(content, doc_type, metadata);
    }

    /// Get system statistics
    pub fn getStats(self: *Self) RAGStats {
        const vector_stats = self.vector_store.getStats();

        return RAGStats{
            .total_documents = self.countUniqueDocuments(),
            .total_chunks = vector_stats.total_chunks,
            .chunks_with_embeddings = vector_stats.chunks_with_embeddings,
            .total_content_length = vector_stats.total_content_length,
            .index_built = vector_stats.index_built,
        };
    }

    fn countUniqueDocuments(self: *Self) usize {
        var document_ids = std.StringHashMap(void).init(self.allocator);
        defer document_ids.deinit();

        for (self.vector_store.chunks.items) |chunk| {
            document_ids.put(chunk.document_id, {}) catch {};
        }

        return document_ids.count();
    }

    fn expandQuery(self: *Self, query_text: []const u8) ![]const u8 {
        // Simple query expansion - add synonyms or related terms
        // In a real implementation, this might use a language model or thesaurus
        var expanded = std.ArrayList(u8).init(self.allocator);
        defer expanded.deinit();

        try expanded.appendSlice(query_text);

        // Add some common expansions based on keywords
        if (std.mem.indexOf(u8, query_text, "AI") != null) {
            try expanded.appendSlice(" artificial intelligence machine learning");
        }
        if (std.mem.indexOf(u8, query_text, "code") != null) {
            try expanded.appendSlice(" programming software development");
        }
        if (std.mem.indexOf(u8, query_text, "data") != null) {
            try expanded.appendSlice(" information dataset");
        }

        return try expanded.toOwnedSlice();
    }

    fn rerankResults(self: *Self, query_text: []const u8, results: []embeddings.SearchResult) ![]embeddings.SearchResult {
        // Simple reranking based on exact keyword matches
        // In a real implementation, this might use a cross-encoder model

        const reranked = try self.allocator.dupe(embeddings.SearchResult, results);

        // Boost scores for exact keyword matches
        const query_lower = try self.allocator.alloc(u8, query_text.len);
        defer self.allocator.free(query_lower);

        for (query_text, 0..) |char, i| {
            query_lower[i] = std.ascii.toLower(char);
        }

        for (reranked) |*result| {
            const content_lower = try self.allocator.alloc(u8, result.chunk.content.len);
            defer self.allocator.free(content_lower);

            for (result.chunk.content, 0..) |char, i| {
                content_lower[i] = std.ascii.toLower(char);
            }

            if (std.mem.indexOf(u8, content_lower, query_lower) != null) {
                result.score *= 1.2; // Boost score by 20%
            }
        }

        // Re-sort by updated scores
        std.sort.pdq(embeddings.SearchResult, reranked, {}, compareSearchResults);

        return reranked;
    }

    fn compareSearchResults(_: void, a: embeddings.SearchResult, b: embeddings.SearchResult) bool {
        return a.score > b.score;
    }

    fn buildContextText(self: *Self, results: []const embeddings.SearchResult) ![]const u8 {
        var context = std.ArrayList(u8).init(self.allocator);
        defer context.deinit();

        var total_length: usize = 0;

        for (results, 0..) |result, i| {
            // Check if adding this chunk would exceed context window
            if (total_length + result.chunk.content.len > self.config.context_window_size) {
                break;
            }

            if (i > 0) {
                try context.appendSlice("\n\n---\n\n");
            }

            // Add chunk metadata
            try context.writer().print("Document: {s} (Chunk {d}, Score: {d:.3})\n", .{
                result.chunk.document_id,
                result.chunk.chunk_index,
                result.score,
            });

            try context.appendSlice(result.chunk.content);
            total_length += result.chunk.content.len;
        }

        return try context.toOwnedSlice();
    }
};

/// Document input for batch processing
pub const DocumentInput = struct {
    content: []const u8,
    doc_type: document.DocumentType,
    metadata: document.DocumentMetadata,
};

/// RAG system statistics
pub const RAGStats = struct {
    total_documents: usize,
    total_chunks: usize,
    chunks_with_embeddings: usize,
    total_content_length: usize,
    index_built: bool,
};
