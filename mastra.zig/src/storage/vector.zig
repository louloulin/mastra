const std = @import("std");

pub const VectorStoreType = enum {
    memory,
    pinecone,
    qdrant,
    weaviate,
    chroma,
    custom,
};

pub const VectorStoreConfig = struct {
    type: VectorStoreType,
    api_key: ?[]const u8 = null,
    base_url: ?[]const u8 = null,
    index_name: ?[]const u8 = null,
    dimension: usize = 1536, // Default OpenAI embedding dimension
    metric: []const u8 = "cosine",
};

pub const VectorDocument = struct {
    id: []const u8,
    content: []const u8,
    embedding: []f32,
    metadata: ?std.json.Value = null,
    score: f32 = 0.0,

    pub fn deinit(_: *VectorDocument) void {
        // No owned memory to free in basic implementation
    }
};

pub const VectorQuery = struct {
    vector: []const f32,
    limit: usize = 10,
    threshold: f32 = 0.0,
    filters: ?std.json.Value = null,
};

pub const VectorStore = struct {
    allocator: std.mem.Allocator,
    config: VectorStoreConfig,
    documents: std.StringHashMap(VectorDocument),
    
    pub fn init(allocator: std.mem.Allocator, config: VectorStoreConfig) !*VectorStore {
        const store = try allocator.create(VectorStore);
        const documents = std.StringHashMap(VectorDocument).init(allocator);
        
        store.* = VectorStore{
            .allocator = allocator,
            .config = config,
            .documents = documents,
        };
        
        return store;
    }

    pub fn deinit(self: *VectorStore) void {
        var iter = self.documents.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.embedding);
        }
        self.documents.deinit();
        self.allocator.destroy(self);
    }

    pub fn upsert(self: *VectorStore, documents: []const VectorDocument) !void {
        for (documents) |doc| {
            const embedding_copy = try self.allocator.alloc(f32, doc.embedding.len);
            @memcpy(embedding_copy, doc.embedding);
            
            const document_copy = VectorDocument{
                .id = doc.id,
                .content = doc.content,
                .embedding = embedding_copy,
                .metadata = doc.metadata,
                .score = doc.score,
            };
            
            // Remove existing document if it exists
            if (self.documents.getPtr(doc.id)) |existing| {
                self.allocator.free(existing.embedding);
            }
            
            try self.documents.put(doc.id, document_copy);
        }
    }

    pub fn delete(self: *VectorStore, ids: []const []const u8) !void {
        for (ids) |id| {
            if (self.documents.fetchRemove(id)) |kv| {
                self.allocator.free(kv.value.embedding);
            }
        }
    }

    pub fn search(self: *VectorStore, query: VectorQuery) ![]VectorDocument {
        var results = std.ArrayList(VectorDocument).init(self.allocator);
        defer results.deinit();

        var iter = self.documents.iterator();
        while (iter.next()) |entry| {
            const doc = entry.value_ptr;
            const similarity = try self.calculateSimilarity(query.vector, doc.embedding);
            
            if (similarity >= query.threshold) {
                const doc_copy = VectorDocument{
                    .id = doc.id,
                    .content = doc.content,
                    .embedding = try self.allocator.dupe(f32, doc.embedding),
                    .metadata = doc.metadata,
                    .score = similarity,
                };
                
                try results.append(doc_copy);
            }
        }

        // Sort by similarity score (descending)
        std.mem.sort(VectorDocument, results.items, {}, struct {
            fn lessThan(_: void, a: VectorDocument, b: VectorDocument) bool {
                return a.score > b.score;
            }
        }.lessThan);

        // Return top results
        const limit = @min(query.limit, results.items.len);
        var final_results = try std.ArrayList(VectorDocument).initCapacity(self.allocator, limit);
        
        for (results.items[0..limit]) |doc| {
            final_results.appendAssumeCapacity(doc);
        }

        return final_results.toOwnedSlice();
    }

    pub fn get(self: *VectorStore, id: []const u8) ?VectorDocument {
        if (self.documents.get(id)) |doc| {
            return VectorDocument{
                .id = doc.id,
                .content = doc.content,
                .embedding = self.allocator.dupe(f32, doc.embedding) catch return null,
                .metadata = doc.metadata,
                .score = doc.score,
            };
        }
        return null;
    }

    pub fn getAll(self: *VectorStore, limit: ?usize) ![]VectorDocument {
        var results = std.ArrayList(VectorDocument).init(self.allocator);
        defer results.deinit();

        var iter = self.documents.iterator();
        while (iter.next()) |entry| {
            const doc = entry.value_ptr;
            const doc_copy = VectorDocument{
                .id = doc.id,
                .content = doc.content,
                .embedding = try self.allocator.dupe(f32, doc.embedding),
                .metadata = doc.metadata,
                .score = doc.score,
            };
            
            try results.append(doc_copy);
        }

        const actual_limit = limit orelse results.items.len;
        const final_limit = @min(actual_limit, results.items.len);
        
        var final_results = try std.ArrayList(VectorDocument).initCapacity(self.allocator, final_limit);
        for (results.items[0..final_limit]) |doc| {
            final_results.appendAssumeCapacity(doc);
        }

        return final_results.toOwnedSlice();
    }

    pub fn count(self: *VectorStore) usize {
        return self.documents.count();
    }

    pub fn clear(self: *VectorStore) void {
        var iter = self.documents.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.embedding);
        }
        self.documents.clearRetainingCapacity();
    }

    fn calculateSimilarity(self: *VectorStore, vec1: []const f32, vec2: []const f32) !f32 {
        if (vec1.len != vec2.len) {
            return 0.0;
        }

        if (std.mem.eql(u8, self.config.metric, "cosine")) {
            return try self.cosineSimilarity(vec1, vec2);
        } else if (std.mem.eql(u8, self.config.metric, "euclidean")) {
            return try self.euclideanSimilarity(vec1, vec2);
        } else if (std.mem.eql(u8, self.config.metric, "dot_product")) {
            return try self.dotProductSimilarity(vec1, vec2);
        }

        return 0.0;
    }

    fn cosineSimilarity(_: *VectorStore, vec1: []const f32, vec2: []const f32) !f32 {
        var dot_product: f32 = 0.0;
        var norm1: f32 = 0.0;
        var norm2: f32 = 0.0;

        for (vec1, vec2) |v1, v2| {
            dot_product += v1 * v2;
            norm1 += v1 * v1;
            norm2 += v2 * v2;
        }

        const denominator = @sqrt(norm1) * @sqrt(norm2);
        if (denominator == 0.0) {
            return 0.0;
        }

        return dot_product / denominator;
    }

    fn euclideanSimilarity(_: *VectorStore, vec1: []const f32, vec2: []const f32) !f32 {
        var distance: f32 = 0.0;
        
        for (vec1, vec2) |v1, v2| {
            const diff = v1 - v2;
            distance += diff * diff;
        }

        const similarity = 1.0 / (1.0 + @sqrt(distance));
        return similarity;
    }

    fn dotProductSimilarity(_: *VectorStore, vec1: []const f32, vec2: []const f32) !f32 {
        var dot_product: f32 = 0.0;
        
        for (vec1, vec2) |v1, v2| {
            dot_product += v1 * v2;
        }

        return dot_product;
    }
};