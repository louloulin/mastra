const std = @import("std");
const rag = @import("rag.zig");
const document = @import("document.zig");
const embeddings = @import("embeddings.zig");

/// Knowledge graph entity
pub const Entity = struct {
    id: []const u8,
    name: []const u8,
    type: []const u8,
    properties: std.json.Value,
    embedding: ?[]f32 = null,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, name: []const u8, entity_type: []const u8) !Self {
        const id = try std.fmt.allocPrint(allocator, "{s}_{s}_{d}", .{ entity_type, name, std.time.timestamp() });

        return Self{
            .id = id,
            .name = try allocator.dupe(u8, name),
            .type = try allocator.dupe(u8, entity_type),
            .properties = std.json.Value{ .object = std.json.ObjectMap.init(allocator) },
            .embedding = null,
        };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.name);
        allocator.free(self.type);
        if (self.embedding) |embedding| {
            allocator.free(embedding);
        }
    }
};

/// Knowledge graph relationship
pub const Relationship = struct {
    id: []const u8,
    source_entity_id: []const u8,
    target_entity_id: []const u8,
    relation_type: []const u8,
    properties: std.json.Value,
    weight: f32 = 1.0,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, source_id: []const u8, target_id: []const u8, relation_type: []const u8) !Self {
        const id = try std.fmt.allocPrint(allocator, "rel_{d}_{d}", .{ std.time.timestamp(), std.crypto.random.int(u32) });

        return Self{
            .id = id,
            .source_entity_id = try allocator.dupe(u8, source_id),
            .target_entity_id = try allocator.dupe(u8, target_id),
            .relation_type = try allocator.dupe(u8, relation_type),
            .properties = std.json.Value{ .object = std.json.ObjectMap.init(allocator) },
            .weight = 1.0,
        };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.source_entity_id);
        allocator.free(self.target_entity_id);
        allocator.free(self.relation_type);
    }
};

/// Knowledge graph
pub const KnowledgeGraph = struct {
    allocator: std.mem.Allocator,
    entities: std.StringHashMap(Entity),
    relationships: std.ArrayList(Relationship),
    entity_index: std.StringHashMap(std.ArrayList([]const u8)), // type -> entity_ids

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .entities = std.StringHashMap(Entity).init(allocator),
            .relationships = std.ArrayList(Relationship).init(allocator),
            .entity_index = std.StringHashMap(std.ArrayList([]const u8)).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        var entity_iter = self.entities.iterator();
        while (entity_iter.next()) |entry| {
            var entity = entry.value_ptr;
            entity.deinit(self.allocator);
        }
        self.entities.deinit();

        for (self.relationships.items) |*rel| {
            rel.deinit(self.allocator);
        }
        self.relationships.deinit();

        var index_iter = self.entity_index.iterator();
        while (index_iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.entity_index.deinit();
    }

    pub fn addEntity(self: *Self, entity: Entity) !void {
        // Add to entity index
        const result = try self.entity_index.getOrPut(entity.type);
        if (!result.found_existing) {
            result.value_ptr.* = std.ArrayList([]const u8).init(self.allocator);
        }
        try result.value_ptr.append(entity.id);

        // Add entity
        try self.entities.put(entity.id, entity);
    }

    pub fn addRelationship(self: *Self, relationship: Relationship) !void {
        try self.relationships.append(relationship);
    }

    pub fn getEntity(self: *Self, entity_id: []const u8) ?*Entity {
        return self.entities.getPtr(entity_id);
    }

    pub fn getEntitiesByType(self: *Self, entity_type: []const u8) ![][]const u8 {
        if (self.entity_index.get(entity_type)) |entity_ids| {
            return try self.allocator.dupe([]const u8, entity_ids.items);
        }
        return &[_][]const u8{};
    }

    pub fn getRelationships(self: *Self, entity_id: []const u8) ![]Relationship {
        var results = std.ArrayList(Relationship).init(self.allocator);
        defer results.deinit();

        for (self.relationships.items) |rel| {
            if (std.mem.eql(u8, rel.source_entity_id, entity_id) or
                std.mem.eql(u8, rel.target_entity_id, entity_id))
            {
                try results.append(rel);
            }
        }

        return try results.toOwnedSlice();
    }
};

/// Entity extraction configuration
pub const EntityExtractionConfig = struct {
    entity_types: [][]const u8 = &[_][]const u8{ "PERSON", "ORGANIZATION", "LOCATION", "CONCEPT" },
    min_entity_length: usize = 2,
    max_entity_length: usize = 50,
    confidence_threshold: f32 = 0.7,
};

/// Simple entity extractor (in production, would use NLP models)
pub const EntityExtractor = struct {
    allocator: std.mem.Allocator,
    config: EntityExtractionConfig,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: EntityExtractionConfig) Self {
        return Self{
            .allocator = allocator,
            .config = config,
        };
    }

    pub fn extractEntities(self: *Self, text: []const u8) ![]Entity {
        var entities = std.ArrayList(Entity).init(self.allocator);
        defer entities.deinit();

        // Simple pattern-based extraction (in production, would use NER models)
        var words = std.mem.tokenize(u8, text, " \t\n\r.,!?;:");
        while (words.next()) |word| {
            if (word.len >= self.config.min_entity_length and
                word.len <= self.config.max_entity_length)
            {

                // Simple heuristics for entity detection
                const entity_type = self.classifyEntity(word);
                if (entity_type) |etype| {
                    const entity = try Entity.init(self.allocator, word, etype);
                    try entities.append(entity);
                }
            }
        }

        return try entities.toOwnedSlice();
    }

    fn classifyEntity(self: *Self, word: []const u8) ?[]const u8 {
        _ = self;

        // Simple classification rules (in production, would use ML models)
        if (word.len > 0 and std.ascii.isUpper(word[0])) {
            // Capitalized words might be entities
            if (std.mem.indexOf(u8, word, "Corp") != null or
                std.mem.indexOf(u8, word, "Inc") != null or
                std.mem.indexOf(u8, word, "Ltd") != null)
            {
                return "ORGANIZATION";
            }

            if (std.mem.indexOf(u8, word, "City") != null or
                std.mem.indexOf(u8, word, "Street") != null)
            {
                return "LOCATION";
            }

            return "PERSON"; // Default for capitalized words
        }

        return null;
    }
};

/// Graph RAG system
pub const GraphRAG = struct {
    allocator: std.mem.Allocator,
    base_rag: rag.RAGSystem,
    knowledge_graph: KnowledgeGraph,
    entity_extractor: EntityExtractor,
    embedding_provider: *embeddings.EmbeddingProvider,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, base_rag: rag.RAGSystem, embedding_provider: *embeddings.EmbeddingProvider) Self {
        const extraction_config = EntityExtractionConfig{};

        return Self{
            .allocator = allocator,
            .base_rag = base_rag,
            .knowledge_graph = KnowledgeGraph.init(allocator),
            .entity_extractor = EntityExtractor.init(allocator, extraction_config),
            .embedding_provider = embedding_provider,
        };
    }

    pub fn deinit(self: *Self) void {
        self.knowledge_graph.deinit();
        self.base_rag.deinit();
    }

    pub fn addDocument(self: *Self, content: []const u8, doc_type: document.DocumentType, metadata: document.DocumentMetadata) !void {
        // Add to base RAG system
        try self.base_rag.addDocument(content, doc_type, metadata);

        // Extract entities and build knowledge graph
        const entities = try self.entity_extractor.extractEntities(content);
        defer {
            for (entities) |*entity| {
                entity.deinit(self.allocator);
            }
            self.allocator.free(entities);
        }

        // Add entities to knowledge graph
        for (entities) |entity| {
            // Generate embedding for entity
            var entity_copy = try Entity.init(self.allocator, entity.name, entity.type);
            entity_copy.embedding = try self.embedding_provider.embedText(entity.name);

            try self.knowledge_graph.addEntity(entity_copy);
        }

        // Extract relationships (simplified)
        try self.extractRelationships(entities);

        std.log.info("Added document to GraphRAG: {s} with {d} entities", .{ metadata.id, entities.len });
    }

    pub fn query(self: *Self, query_text: []const u8) !GraphRAGContext {
        // Get base RAG context
        const base_context = try self.base_rag.query(query_text);

        // Extract entities from query
        const query_entities = try self.entity_extractor.extractEntities(query_text);
        defer {
            for (query_entities) |*entity| {
                entity.deinit(self.allocator);
            }
            self.allocator.free(query_entities);
        }

        // Find related entities in knowledge graph
        var related_entities = std.ArrayList(Entity).init(self.allocator);
        defer related_entities.deinit();

        for (query_entities) |query_entity| {
            const similar_entities = try self.findSimilarEntities(query_entity.name);
            defer self.allocator.free(similar_entities);

            for (similar_entities) |entity_id| {
                if (self.knowledge_graph.getEntity(entity_id)) |entity| {
                    try related_entities.append(entity.*);
                }
            }
        }

        // Build enhanced context
        const enhanced_context = try self.buildEnhancedContext(base_context, related_entities.items);

        return GraphRAGContext{
            .base_context = base_context,
            .related_entities = try related_entities.toOwnedSlice(),
            .enhanced_context = enhanced_context,
        };
    }

    fn extractRelationships(self: *Self, entities: []Entity) !void {
        // Simple co-occurrence based relationship extraction
        for (entities, 0..) |source_entity, i| {
            for (entities[i + 1 ..]) |target_entity| {
                const relationship = try Relationship.init(self.allocator, source_entity.id, target_entity.id, "CO_OCCURS");
                try self.knowledge_graph.addRelationship(relationship);
            }
        }
    }

    fn findSimilarEntities(self: *Self, entity_name: []const u8) ![][]const u8 {
        var similar = std.ArrayList([]const u8).init(self.allocator);
        defer similar.deinit();

        // Simple string similarity (in production, would use embedding similarity)
        var entity_iter = self.knowledge_graph.entities.iterator();
        while (entity_iter.next()) |entry| {
            const entity = entry.value_ptr;
            if (std.mem.indexOf(u8, entity.name, entity_name) != null or
                std.mem.indexOf(u8, entity_name, entity.name) != null)
            {
                try similar.append(entity.id);
            }
        }

        return try similar.toOwnedSlice();
    }

    fn buildEnhancedContext(self: *Self, base_context: rag.RAGContext, related_entities: []Entity) ![]const u8 {
        var enhanced = std.ArrayList(u8).init(self.allocator);
        defer enhanced.deinit();

        // Add base context
        try enhanced.appendSlice(base_context.context_text);

        // Add entity information
        if (related_entities.len > 0) {
            try enhanced.appendSlice("\n\n--- Related Entities ---\n");

            for (related_entities) |entity| {
                try enhanced.writer().print("Entity: {s} (Type: {s})\n", .{ entity.name, entity.type });
            }
        }

        return try enhanced.toOwnedSlice();
    }

    pub fn getGraphStats(self: *Self) GraphStats {
        return GraphStats{
            .entity_count = self.knowledge_graph.entities.count(),
            .relationship_count = self.knowledge_graph.relationships.items.len,
            .entity_types = self.knowledge_graph.entity_index.count(),
        };
    }
};

/// Graph RAG query context
pub const GraphRAGContext = struct {
    base_context: rag.RAGContext,
    related_entities: []Entity,
    enhanced_context: []const u8,

    pub fn deinit(self: *GraphRAGContext, allocator: std.mem.Allocator) void {
        self.base_context.deinit(allocator);
        for (self.related_entities) |*entity| {
            entity.deinit(allocator);
        }
        allocator.free(self.related_entities);
        allocator.free(self.enhanced_context);
    }
};

/// Graph statistics
pub const GraphStats = struct {
    entity_count: u32,
    relationship_count: usize,
    entity_types: u32,
};
