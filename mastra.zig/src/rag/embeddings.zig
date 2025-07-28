const std = @import("std");
const document = @import("document.zig");

/// Embedding model configuration
pub const EmbeddingConfig = struct {
    model_name: []const u8 = "text-embedding-ada-002",
    api_endpoint: []const u8 = "https://api.openai.com/v1/embeddings",
    api_key: ?[]const u8 = null,
    dimensions: usize = 1536,
    batch_size: usize = 100,
    max_tokens: usize = 8191,
    timeout_ms: u32 = 30000,
};

/// Embedding provider interface
pub const EmbeddingProvider = struct {
    allocator: std.mem.Allocator,
    config: EmbeddingConfig,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: EmbeddingConfig) Self {
        return Self{
            .allocator = allocator,
            .config = config,
        };
    }

    pub fn embedText(self: *Self, text: []const u8) ![]f32 {
        // For now, return a mock embedding
        // In a real implementation, this would call the embedding API
        const embedding = try self.allocator.alloc(f32, self.config.dimensions);

        // Generate a simple hash-based embedding for testing
        var hash: u64 = 0;
        for (text) |char| {
            hash = hash *% 31 +% char;
        }

        var rng = std.Random.DefaultPrng.init(hash);
        const random = rng.random();

        for (embedding) |*value| {
            value.* = random.floatNorm(f32);
        }

        // Normalize the embedding
        var norm: f32 = 0;
        for (embedding) |value| {
            norm += value * value;
        }
        norm = @sqrt(norm);

        if (norm > 0) {
            for (embedding) |*value| {
                value.* /= norm;
            }
        }

        std.log.debug("Generated embedding for text: {s} (length: {d})", .{ text[0..@min(50, text.len)], embedding.len });

        return embedding;
    }

    pub fn embedBatch(self: *Self, texts: [][]const u8) ![][]f32 {
        var embeddings = try self.allocator.alloc([]f32, texts.len);

        for (texts, 0..) |text, i| {
            embeddings[i] = try self.embedText(text);
        }

        return embeddings;
    }

    pub fn embedDocumentChunks(self: *Self, chunks: []document.DocumentChunk) !void {
        for (chunks) |*chunk| {
            if (chunk.embedding == null) {
                chunk.embedding = try self.embedText(chunk.content);
            }
        }
    }
};

/// Vector similarity calculation
pub const VectorSimilarity = struct {
    pub fn cosineSimilarity(a: []const f32, b: []const f32) f32 {
        if (a.len != b.len) return 0.0;

        var dot_product: f32 = 0;
        var norm_a: f32 = 0;
        var norm_b: f32 = 0;

        for (a, b) |val_a, val_b| {
            dot_product += val_a * val_b;
            norm_a += val_a * val_a;
            norm_b += val_b * val_b;
        }

        const norm_product = @sqrt(norm_a) * @sqrt(norm_b);
        if (norm_product == 0) return 0.0;

        return dot_product / norm_product;
    }

    pub fn euclideanDistance(a: []const f32, b: []const f32) f32 {
        if (a.len != b.len) return std.math.inf(f32);

        var sum: f32 = 0;
        for (a, b) |val_a, val_b| {
            const diff = val_a - val_b;
            sum += diff * diff;
        }

        return @sqrt(sum);
    }

    pub fn dotProduct(a: []const f32, b: []const f32) f32 {
        if (a.len != b.len) return 0.0;

        var result: f32 = 0;
        for (a, b) |val_a, val_b| {
            result += val_a * val_b;
        }

        return result;
    }
};

/// Search result
pub const SearchResult = struct {
    chunk: document.DocumentChunk,
    score: f32,
    rank: usize,

    pub fn deinit(self: *SearchResult, allocator: std.mem.Allocator) void {
        self.chunk.deinit(allocator);
    }
};

/// Vector search configuration
pub const SearchConfig = struct {
    similarity_metric: SimilarityMetric = .cosine,
    top_k: usize = 10,
    min_score: f32 = 0.0,
    max_results: usize = 100,
    rerank: bool = false,

    pub const SimilarityMetric = enum {
        cosine,
        euclidean,
        dot_product,
    };
};

/// Vector store for embeddings
pub const VectorStore = struct {
    allocator: std.mem.Allocator,
    chunks: std.ArrayList(document.DocumentChunk),
    index_built: bool,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .chunks = std.ArrayList(document.DocumentChunk).init(allocator),
            .index_built = false,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.chunks.items) |*chunk| {
            chunk.deinit(self.allocator);
        }
        self.chunks.deinit();
    }

    pub fn addChunk(self: *Self, chunk: document.DocumentChunk) !void {
        try self.chunks.append(chunk);
        self.index_built = false;
    }

    pub fn addChunks(self: *Self, chunks: []document.DocumentChunk) !void {
        for (chunks) |chunk| {
            try self.addChunk(chunk);
        }
    }

    pub fn buildIndex(self: *Self) !void {
        // For now, we'll use a simple linear search
        // In a real implementation, you might build an HNSW or IVF index
        self.index_built = true;
        std.log.info("Vector index built with {d} chunks", .{self.chunks.items.len});
    }

    pub fn search(self: *Self, query_embedding: []const f32, config: SearchConfig) ![]SearchResult {
        if (!self.index_built) {
            try self.buildIndex();
        }

        var results = std.ArrayList(SearchResult).init(self.allocator);
        defer results.deinit();

        // Calculate similarity scores for all chunks
        for (self.chunks.items, 0..) |chunk, i| {
            if (chunk.embedding) |embedding| {
                const score = switch (config.similarity_metric) {
                    .cosine => VectorSimilarity.cosineSimilarity(query_embedding, embedding),
                    .euclidean => 1.0 / (1.0 + VectorSimilarity.euclideanDistance(query_embedding, embedding)),
                    .dot_product => VectorSimilarity.dotProduct(query_embedding, embedding),
                };

                if (score >= config.min_score) {
                    try results.append(SearchResult{
                        .chunk = chunk,
                        .score = score,
                        .rank = i,
                    });
                }
            }
        }

        // Sort by score (descending)
        std.sort.pdq(SearchResult, results.items, {}, compareSearchResults);

        // Limit results
        const max_results = @min(config.top_k, results.items.len);
        const final_results = try self.allocator.alloc(SearchResult, max_results);

        for (final_results, 0..) |*result, i| {
            result.* = results.items[i];
            result.rank = i;
        }

        return final_results;
    }

    fn compareSearchResults(_: void, a: SearchResult, b: SearchResult) bool {
        return a.score > b.score;
    }

    pub fn searchByText(self: *Self, embedding_provider: *EmbeddingProvider, query: []const u8, config: SearchConfig) ![]SearchResult {
        const query_embedding = try embedding_provider.embedText(query);
        defer embedding_provider.allocator.free(query_embedding);

        return try self.search(query_embedding, config);
    }

    pub fn getChunkById(self: *Self, chunk_id: []const u8) ?*document.DocumentChunk {
        for (self.chunks.items) |*chunk| {
            if (std.mem.eql(u8, chunk.id, chunk_id)) {
                return chunk;
            }
        }
        return null;
    }

    pub fn removeChunk(self: *Self, chunk_id: []const u8) bool {
        for (self.chunks.items, 0..) |chunk, i| {
            if (std.mem.eql(u8, chunk.id, chunk_id)) {
                var removed_chunk = self.chunks.swapRemove(i);
                removed_chunk.deinit(self.allocator);
                self.index_built = false;
                return true;
            }
        }
        return false;
    }

    pub fn updateChunk(self: *Self, chunk_id: []const u8, new_chunk: document.DocumentChunk) !bool {
        for (self.chunks.items, 0..) |*chunk, i| {
            if (std.mem.eql(u8, chunk.id, chunk_id)) {
                chunk.deinit(self.allocator);
                self.chunks.items[i] = new_chunk;
                self.index_built = false;
                return true;
            }
        }
        return false;
    }

    pub fn getStats(self: *Self) VectorStoreStats {
        var total_chunks: usize = 0;
        var chunks_with_embeddings: usize = 0;
        var total_content_length: usize = 0;

        for (self.chunks.items) |chunk| {
            total_chunks += 1;
            total_content_length += chunk.content.len;
            if (chunk.embedding != null) {
                chunks_with_embeddings += 1;
            }
        }

        return VectorStoreStats{
            .total_chunks = total_chunks,
            .chunks_with_embeddings = chunks_with_embeddings,
            .total_content_length = total_content_length,
            .index_built = self.index_built,
        };
    }
};

/// Vector store statistics
pub const VectorStoreStats = struct {
    total_chunks: usize,
    chunks_with_embeddings: usize,
    total_content_length: usize,
    index_built: bool,
};
