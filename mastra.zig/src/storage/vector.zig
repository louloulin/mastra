const std = @import("std");
// 暂时禁用SQLite导入，等待修复编译问题
// const SQLiteConnection = @import("sqlite.zig").SQLiteConnection;
// const SQLiteValue = @import("sqlite.zig").SQLiteValue;
// const SQLiteError = @import("sqlite.zig").SQLiteError;

pub const VectorStoreType = enum {
    memory,
    sqlite,
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
    // SQLite 特定配置
    database_path: ?[]const u8 = null,
    similarity_threshold: f32 = 0.7,
    max_results: usize = 10,
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
    // 暂时禁用SQLite支持
    // sqlite_db: ?SQLiteConnection,

    pub fn init(allocator: std.mem.Allocator, config: VectorStoreConfig) !*VectorStore {
        const store = try allocator.create(VectorStore);
        const documents = std.StringHashMap(VectorDocument).init(allocator);

        // 暂时禁用SQLite功能
        // var sqlite_db: ?SQLiteConnection = null;
        // if (config.type == .sqlite) {
        //     const db_path = config.database_path orelse "vectors.db";
        //     sqlite_db = try SQLiteConnection.open(allocator, db_path);
        //     try initializeSQLiteSchema(&sqlite_db.?);
        // }

        store.* = VectorStore{
            .allocator = allocator,
            .config = config,
            .documents = documents,
            // 暂时禁用SQLite
            // .sqlite_db = sqlite_db,
        };

        return store;
    }

    pub fn deinit(self: *VectorStore) void {
        // 简化内存清理，避免复杂的双重释放问题
        var iter = self.documents.iterator();
        while (iter.next()) |entry| {
            // 只释放embedding数组（这是我们确定分配的）
            const doc = entry.value_ptr.*;
            self.allocator.free(doc.embedding);

            // 释放key字符串（由upsert中的dupe分配）
            self.allocator.free(entry.key_ptr.*);
        }
        self.documents.deinit();

        // 暂时禁用SQLite功能
        // if (self.sqlite_db) |*db| {
        //     db.close();
        // }

        self.allocator.destroy(self);
    }

    pub fn upsert(self: *VectorStore, documents: []const VectorDocument) !void {
        for (documents) |doc| {
            const embedding_copy = try self.allocator.alloc(f32, doc.embedding.len);
            @memcpy(embedding_copy, doc.embedding);

            // 复制id字符串以确保内存安全
            const id_copy = try self.allocator.dupe(u8, doc.id);

            const document_copy = VectorDocument{
                .id = id_copy,
                .content = doc.content,
                .embedding = embedding_copy,
                .metadata = doc.metadata,
                .score = doc.score,
            };

            // Remove existing document if it exists
            if (self.documents.fetchRemove(doc.id)) |kv| {
                // 释放旧的key、embedding和id
                self.allocator.free(kv.key);
                self.allocator.free(kv.value.embedding);
                // kv.value.id和kv.key是同一个字符串，不需要重复释放
            }

            try self.documents.put(id_copy, document_copy);
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

// 暂时禁用SQLite功能
// /// 初始化 SQLite 向量存储模式
// fn initializeSQLiteSchema(db: *SQLiteConnection) !void {
//     const create_table_sql =
//         \\CREATE TABLE IF NOT EXISTS vector_embeddings (
//         \\    id TEXT PRIMARY KEY,
//         \\    content TEXT NOT NULL,
//         \\    vector BLOB NOT NULL,
//         \\    dimension INTEGER NOT NULL,
//         \\    metadata TEXT,
//         \\    score REAL DEFAULT 0.0,
//         \\    created_at INTEGER NOT NULL
//         \\);
//         \\
//         \\CREATE INDEX IF NOT EXISTS idx_vector_embeddings_created_at
//         \\ON vector_embeddings(created_at);
//         \\
//         \\CREATE INDEX IF NOT EXISTS idx_vector_embeddings_dimension
//         \\ON vector_embeddings(dimension);
//     ;
//
//     var result = try db.execute(create_table_sql, null);
//     result.deinit();
// }
