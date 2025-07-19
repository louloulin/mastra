const std = @import("std");
const VectorStore = @import("../storage/vector.zig").VectorStore;
const VectorDocument = @import("../storage/vector.zig").VectorDocument;
const VectorQuery = @import("../storage/vector.zig").VectorQuery;

/// 内存错误类型
pub const MemoryError = error{
    MemoryFull,
    InvalidMessage,
    StorageError,
    RetrievalError,
    SerializationError,
};

/// 内存类型
pub const MemoryType = enum {
    conversational,
    semantic,
    working,
    episodic,
};

pub const MemoryMessage = struct {
    id: []const u8,
    role: []const u8,
    content: []const u8,
    timestamp: i64,
    memory_type: MemoryType,
    importance: f32,
    embedding: ?[]f32,
    metadata: ?std.json.Value = null,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        id: []const u8,
        role: []const u8,
        content: []const u8,
        memory_type: MemoryType,
    ) !Self {
        return Self{
            .id = try allocator.dupe(u8, id),
            .role = try allocator.dupe(u8, role),
            .content = try allocator.dupe(u8, content),
            .timestamp = std.time.timestamp(),
            .memory_type = memory_type,
            .importance = 0.5,
            .embedding = null,
            .metadata = null,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.id);
        self.allocator.free(self.role);
        self.allocator.free(self.content);
        if (self.embedding) |embedding| {
            self.allocator.free(embedding);
        }
        // JSON Value doesn't need explicit deinitialization in newer Zig versions
        _ = self.metadata;
    }

    pub fn clone(self: *const Self, allocator: std.mem.Allocator) !Self {
        var cloned = try Self.init(allocator, self.id, self.role, self.content, self.memory_type);
        cloned.timestamp = self.timestamp;
        cloned.importance = self.importance;

        if (self.embedding) |embedding| {
            cloned.embedding = try allocator.dupe(f32, embedding);
        }

        if (self.metadata) |metadata| {
            // 简单的元数据复制，实际应用中可能需要深度复制
            cloned.metadata = metadata;
        }

        return cloned;
    }
};

pub const MemorySearchResult = struct {
    message: MemoryMessage,
    score: f32,

    pub fn deinit(self: *MemorySearchResult) void {
        self.message.deinit();
    }
};

pub const MemoryConfig = struct {
    max_conversational_messages: usize = 100,
    max_semantic_entries: usize = 1000,
    max_working_memory_size: usize = 50,
    retention_days: ?u32 = null,
    enable_vector_search: bool = false,
    enable_semantic_recall: bool = true,
    enable_working_memory: bool = false,
    decay_threshold: f32 = 0.1,
    importance_threshold: f32 = 0.3,
    vector_store_config: ?@import("../storage/vector.zig").VectorStoreConfig = null,
};

pub const Memory = struct {
    allocator: std.mem.Allocator,
    config: MemoryConfig,
    conversational_memory: std.ArrayList(MemoryMessage),
    semantic_memory: std.StringHashMap(MemoryMessage),
    working_memory: std.ArrayList(MemoryMessage),
    vector_store: ?*VectorStore,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: MemoryConfig) !*Memory {
        const memory = try allocator.create(Memory);

        // 初始化向量存储（如果启用）
        var vector_store: ?*VectorStore = null;
        if (config.enable_vector_search and config.vector_store_config != null) {
            vector_store = try VectorStore.init(allocator, config.vector_store_config.?);
        }

        memory.* = Memory{
            .allocator = allocator,
            .config = config,
            .conversational_memory = std.ArrayList(MemoryMessage).init(allocator),
            .semantic_memory = std.StringHashMap(MemoryMessage).init(allocator),
            .working_memory = std.ArrayList(MemoryMessage).init(allocator),
            .vector_store = vector_store,
        };

        return memory;
    }

    pub fn deinit(self: *Memory) void {
        // 清理对话记忆
        for (self.conversational_memory.items) |*msg| {
            msg.deinit();
        }
        self.conversational_memory.deinit();

        // 清理语义记忆
        var semantic_iter = self.semantic_memory.iterator();
        while (semantic_iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.semantic_memory.deinit();

        // 清理工作记忆
        for (self.working_memory.items) |*msg| {
            msg.deinit();
        }
        self.working_memory.deinit();

        // 清理向量存储
        if (self.vector_store) |store| {
            store.deinit();
        }

        self.allocator.destroy(self);
    }

    /// 添加对话消息（兼容性方法）
    pub fn addMessage(self: *Memory, message: struct { role: []const u8, content: []const u8 }) !void {
        const id = try std.fmt.allocPrint(self.allocator, "msg_{d}", .{std.time.timestamp()});
        defer self.allocator.free(id);

        const memory_msg = try MemoryMessage.init(
            self.allocator,
            id,
            message.role,
            message.content,
            .conversational,
        );

        try self.addConversationalMessage(memory_msg);
    }

    /// 添加对话消息
    pub fn addConversationalMessage(self: *Memory, message: MemoryMessage) !void {
        if (message.memory_type != .conversational) {
            return MemoryError.InvalidMessage;
        }

        // 检查是否超过最大消息数
        if (self.conversational_memory.items.len >= self.config.max_conversational_messages) {
            var oldest = self.conversational_memory.orderedRemove(0);
            oldest.deinit();
        }

        try self.conversational_memory.append(message);
    }

    /// 获取对话历史（兼容性方法）
    pub fn getMessages(self: *Memory, limit: ?usize) []const MemoryMessage {
        return self.getConversationalHistory(limit);
    }

    /// 获取对话历史
    pub fn getConversationalHistory(self: *Memory, limit: ?usize) []const MemoryMessage {
        const max = limit orelse self.conversational_memory.items.len;
        const start = if (max >= self.conversational_memory.items.len) 0 else self.conversational_memory.items.len - max;
        return self.conversational_memory.items[start..];
    }

    /// 文本搜索
    pub fn search(self: *Memory, query: []const u8, limit: ?usize) ![]MemorySearchResult {
        var results = std.ArrayList(MemorySearchResult).init(self.allocator);
        defer results.deinit();

        const max_results = limit orelse 10;

        // 在对话记忆中搜索
        for (self.conversational_memory.items) |msg| {
            if (std.mem.indexOf(u8, msg.content, query) != null) {
                try results.append(MemorySearchResult{
                    .message = msg,
                    .score = 1.0, // 对话记忆高分
                });
                if (results.items.len >= max_results) break;
            }
        }

        // 在语义记忆中搜索
        if (results.items.len < max_results) {
            var semantic_iter = self.semantic_memory.iterator();
            while (semantic_iter.next()) |entry| {
                if (std.mem.indexOf(u8, entry.value_ptr.content, query) != null) {
                    try results.append(MemorySearchResult{
                        .message = entry.value_ptr.*,
                        .score = 0.8, // 语义记忆稍低分
                    });
                    if (results.items.len >= max_results) break;
                }
            }
        }

        return try results.toOwnedSlice();
    }

    /// 清空所有记忆
    pub fn clear(self: *Memory) void {
        // 清空对话记忆
        for (self.conversational_memory.items) |*msg| {
            msg.deinit();
        }
        self.conversational_memory.clearAndFree();

        // 清空语义记忆
        var semantic_iter = self.semantic_memory.iterator();
        while (semantic_iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.semantic_memory.clearAndFree();

        // 清空工作记忆
        for (self.working_memory.items) |*msg| {
            msg.deinit();
        }
        self.working_memory.clearAndFree();
    }

    /// 获取消息总数
    pub fn getMessageCount(self: *Memory) usize {
        return self.conversational_memory.items.len +
            self.semantic_memory.count() +
            self.working_memory.items.len;
    }

    /// 获取对话消息数量
    pub fn getConversationalMessageCount(self: *Memory) usize {
        return self.conversational_memory.items.len;
    }

    /// 获取语义记忆数量
    pub fn getSemanticMemoryCount(self: *Memory) usize {
        return self.semantic_memory.count();
    }

    /// 获取工作记忆数量
    pub fn getWorkingMemoryCount(self: *Memory) usize {
        return self.working_memory.items.len;
    }
};
