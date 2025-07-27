const std = @import("std");
const Storage = @import("../storage/storage.zig").Storage;

/// Message importance levels for smart trimming
pub const MessageImportance = enum {
    system,      // System messages (never trim)
    critical,    // Critical messages (trim last)
    important,   // Important messages
    normal,      // Normal messages
    low,         // Low importance messages (trim first)
};

/// Enhanced message structure for MessageList
pub const ListMessage = struct {
    id: []const u8,
    role: []const u8,
    content: []const u8,
    timestamp: i64,
    importance: MessageImportance,
    token_count: ?usize,
    metadata: ?std.json.Value,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        role: []const u8,
        content: []const u8,
        importance: MessageImportance,
    ) !Self {
        const id = try std.fmt.allocPrint(allocator, "msg_{d}_{d}", .{ std.time.timestamp(), std.crypto.random.int(u32) });
        
        return Self{
            .id = id,
            .role = try allocator.dupe(u8, role),
            .content = try allocator.dupe(u8, content),
            .timestamp = std.time.timestamp(),
            .importance = importance,
            .token_count = estimateTokenCount(content),
            .metadata = null,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.id);
        self.allocator.free(self.role);
        self.allocator.free(self.content);
    }

    /// Estimate token count for the message (simple approximation)
    fn estimateTokenCount(content: []const u8) usize {
        // Simple approximation: ~4 characters per token
        return (content.len + 3) / 4;
    }
};

/// Configuration for MessageList behavior
pub const MessageListConfig = struct {
    max_context_length: usize = 4000,  // Maximum tokens in context
    max_messages: usize = 100,         // Maximum number of messages to keep
    preserve_system_messages: bool = true,
    preserve_recent_messages: usize = 5,  // Always keep N most recent messages
    enable_persistence: bool = false,
    thread_id: ?[]const u8 = null,
};

/// Smart message list with context management
pub const MessageList = struct {
    allocator: std.mem.Allocator,
    config: MessageListConfig,
    messages: std.ArrayList(ListMessage),
    storage: ?*Storage,
    thread_id: ?[]const u8,
    total_tokens: usize,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: MessageListConfig, storage: ?*Storage) !*Self {
        const list = try allocator.create(Self);
        
        list.* = Self{
            .allocator = allocator,
            .config = config,
            .messages = std.ArrayList(ListMessage).init(allocator),
            .storage = storage,
            .thread_id = if (config.thread_id) |tid| try allocator.dupe(u8, tid) else null,
            .total_tokens = 0,
        };

        // Load existing messages if persistence is enabled
        if (config.enable_persistence and storage != null and config.thread_id != null) {
            try list.loadMessages();
        }

        return list;
    }

    pub fn deinit(self: *Self) void {
        for (self.messages.items) |*msg| {
            msg.deinit();
        }
        self.messages.deinit();
        
        if (self.thread_id) |tid| {
            self.allocator.free(tid);
        }
        
        self.allocator.destroy(self);
    }

    /// Add a message to the list
    pub fn addMessage(self: *Self, role: []const u8, content: []const u8, importance: MessageImportance) !void {
        var message = try ListMessage.init(self.allocator, role, content, importance);
        
        try self.messages.append(message);
        if (message.token_count) |tokens| {
            self.total_tokens += tokens;
        }

        // Persist message if enabled
        if (self.config.enable_persistence and self.storage != null and self.thread_id != null) {
            try self.saveMessage(&message);
        }

        // Trim context if necessary
        try self.trimContext();
    }

    /// Get messages for context, respecting token limits
    pub fn getContext(self: *Self, max_tokens: ?usize) ![]ListMessage {
        const token_limit = max_tokens orelse self.config.max_context_length;
        return try self.smartTrim(token_limit);
    }

    /// Get all messages
    pub fn getAllMessages(self: *Self) []ListMessage {
        return self.messages.items;
    }

    /// Get message count
    pub fn getMessageCount(self: *Self) usize {
        return self.messages.items.len;
    }

    /// Get total token count
    pub fn getTotalTokens(self: *Self) usize {
        return self.total_tokens;
    }

    /// Smart context trimming algorithm
    fn smartTrim(self: *Self, max_tokens: usize) ![]ListMessage {
        if (self.total_tokens <= max_tokens) {
            return self.messages.items;
        }

        var result = std.ArrayList(ListMessage).init(self.allocator);
        defer result.deinit();

        var current_tokens: usize = 0;
        const messages = self.messages.items;

        // Always include system messages first
        if (self.config.preserve_system_messages) {
            for (messages) |msg| {
                if (msg.importance == .system) {
                    try result.append(msg);
                    if (msg.token_count) |tokens| {
                        current_tokens += tokens;
                    }
                }
            }
        }

        // Include recent messages (working backwards)
        const recent_start = if (messages.len > self.config.preserve_recent_messages) 
            messages.len - self.config.preserve_recent_messages else 0;
        
        var i = messages.len;
        while (i > recent_start and current_tokens < max_tokens) {
            i -= 1;
            const msg = messages[i];
            
            // Skip if already included (system messages)
            if (msg.importance == .system and self.config.preserve_system_messages) {
                continue;
            }

            const msg_tokens = msg.token_count orelse 0;
            if (current_tokens + msg_tokens <= max_tokens) {
                try result.insert(result.items.len, msg);
                current_tokens += msg_tokens;
            }
        }

        // Fill remaining space with important messages (by importance)
        if (current_tokens < max_tokens) {
            const importance_order = [_]MessageImportance{ .critical, .important, .normal, .low };
            
            for (importance_order) |importance| {
                for (messages) |msg| {
                    if (msg.importance != importance) continue;
                    
                    // Skip if already included
                    var already_included = false;
                    for (result.items) |included| {
                        if (std.mem.eql(u8, msg.id, included.id)) {
                            already_included = true;
                            break;
                        }
                    }
                    if (already_included) continue;

                    const msg_tokens = msg.token_count orelse 0;
                    if (current_tokens + msg_tokens <= max_tokens) {
                        // Insert in chronological order
                        var insert_pos: usize = 0;
                        for (result.items, 0..) |included, idx| {
                            if (msg.timestamp < included.timestamp) {
                                insert_pos = idx;
                                break;
                            }
                            insert_pos = idx + 1;
                        }
                        
                        try result.insert(insert_pos, msg);
                        current_tokens += msg_tokens;
                    }
                }
            }
        }

        // Return owned slice
        return try self.allocator.dupe(ListMessage, result.items);
    }

    /// Trim context to stay within limits
    fn trimContext(self: *Self) !void {
        // Remove old messages if we exceed max_messages
        while (self.messages.items.len > self.config.max_messages) {
            var removed = self.messages.orderedRemove(0);
            if (removed.token_count) |tokens| {
                self.total_tokens -= tokens;
            }
            removed.deinit();
        }

        // Trim by token count if necessary
        while (self.total_tokens > self.config.max_context_length and self.messages.items.len > self.config.preserve_recent_messages) {
            // Find least important, oldest message to remove
            var remove_idx: ?usize = null;
            var lowest_importance = MessageImportance.system;
            var oldest_timestamp: i64 = std.math.maxInt(i64);

            for (self.messages.items, 0..) |msg, idx| {
                // Don't remove system messages or recent messages
                if (msg.importance == .system and self.config.preserve_system_messages) continue;
                if (idx >= self.messages.items.len - self.config.preserve_recent_messages) continue;

                const is_less_important = @intFromEnum(msg.importance) > @intFromEnum(lowest_importance);
                const is_same_importance_but_older = msg.importance == lowest_importance and msg.timestamp < oldest_timestamp;

                if (is_less_important or is_same_importance_but_older) {
                    remove_idx = idx;
                    lowest_importance = msg.importance;
                    oldest_timestamp = msg.timestamp;
                }
            }

            if (remove_idx) |idx| {
                var removed = self.messages.orderedRemove(idx);
                if (removed.token_count) |tokens| {
                    self.total_tokens -= tokens;
                }
                removed.deinit();
            } else {
                break; // Can't remove any more messages
            }
        }
    }

    /// Save message to storage
    fn saveMessage(self: *Self, message: *const ListMessage) !void {
        if (self.storage == null or self.thread_id == null) return;

        var msg_data = std.json.ObjectMap.init(self.allocator);
        defer msg_data.deinit();

        try msg_data.put("id", std.json.Value{ .string = message.id });
        try msg_data.put("role", std.json.Value{ .string = message.role });
        try msg_data.put("content", std.json.Value{ .string = message.content });
        try msg_data.put("timestamp", std.json.Value{ .integer = @intCast(message.timestamp) });
        try msg_data.put("importance", std.json.Value{ .string = @tagName(message.importance) });
        
        if (message.token_count) |tokens| {
            try msg_data.put("token_count", std.json.Value{ .integer = @intCast(tokens) });
        }

        const table_name = try std.fmt.allocPrint(self.allocator, "messages_{s}", .{self.thread_id.?});
        defer self.allocator.free(table_name);

        _ = try self.storage.?.create(table_name, std.json.Value{ .object = msg_data });
    }

    /// Load messages from storage
    fn loadMessages(self: *Self) !void {
        if (self.storage == null or self.thread_id == null) return;

        const table_name = try std.fmt.allocPrint(self.allocator, "messages_{s}", .{self.thread_id.?});
        defer self.allocator.free(table_name);

        // In a real implementation, this would query the storage
        // For now, we'll skip the actual loading
    }
};

// Tests
test "MessageList basic operations" {
    const allocator = std.testing.allocator;
    const config = MessageListConfig{};
    
    var list = try MessageList.init(allocator, config, null);
    defer list.deinit();

    try list.addMessage("user", "Hello", .normal);
    try list.addMessage("assistant", "Hi there!", .normal);

    try std.testing.expectEqual(@as(usize, 2), list.getMessageCount());
    try std.testing.expect(list.getTotalTokens() > 0);
}

test "MessageList smart trimming" {
    const allocator = std.testing.allocator;
    const config = MessageListConfig{ .max_context_length = 10 }; // Very small limit
    
    var list = try MessageList.init(allocator, config, null);
    defer list.deinit();

    try list.addMessage("system", "You are helpful", .system);
    try list.addMessage("user", "Long message that should be trimmed", .normal);
    try list.addMessage("assistant", "Short", .normal);

    const context = try list.getContext(null);
    defer allocator.free(context);

    // Should preserve system message and recent messages
    try std.testing.expect(context.len >= 1);
}
