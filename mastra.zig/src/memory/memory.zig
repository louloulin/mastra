const std = @import("std");

pub const MemoryMessage = struct {
    role: []const u8,
    content: []const u8,
    timestamp: i64,
    metadata: ?std.json.Value = null,

    pub fn deinit(_: *MemoryMessage) void {
        // No owned memory to free in basic implementation
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
    max_messages: usize = 1000,
    retention_days: ?u32 = null,
    enable_vector_search: bool = false,
};

pub const Memory = struct {
    allocator: std.mem.Allocator,
    config: MemoryConfig,
    messages: std.ArrayList(MemoryMessage),
    
    pub fn init(allocator: std.mem.Allocator, config: MemoryConfig) !*Memory {
        const memory = try allocator.create(Memory);
        const messages = std.ArrayList(MemoryMessage).init(allocator);
        
        memory.* = Memory{
            .allocator = allocator,
            .config = config,
            .messages = messages,
        };
        
        return memory;
    }

    pub fn deinit(self: *Memory) void {
        for (self.messages.items) |*msg| {
            msg.deinit();
        }
        self.messages.deinit();
        self.allocator.destroy(self);
    }

    pub fn addMessage(self: *Memory, message: struct { role: []const u8, content: []const u8 }) !void {
        const timestamp = std.time.timestamp();
        
        const memory_msg = MemoryMessage{
            .role = message.role,
            .content = message.content,
            .timestamp = timestamp,
            .metadata = null,
        };
        
        try self.messages.append(memory_msg);
        
        // Enforce max_messages limit
        if (self.messages.items.len > self.config.max_messages) {
            _ = self.messages.orderedRemove(0);
        }
    }

    pub fn getMessages(self: *Memory, limit: ?usize) []const MemoryMessage {
        const max = limit orelse self.messages.items.len;
        const start = if (max >= self.messages.items.len) 0 else self.messages.items.len - max;
        return self.messages.items[start..];
    }

    pub fn search(self: *Memory, query: []const u8, _: ?usize) ![]MemorySearchResult {
        var results = std.ArrayList(MemorySearchResult).init(self.allocator);
        defer results.deinit();

        // Simple keyword search implementation
        for (self.messages.items) |msg| {
            if (std.mem.indexOf(u8, std.ascii.lowerString(self.allocator, msg.content), std.ascii.lowerString(self.allocator, query)) != null) {
                try results.append(MemorySearchResult{
                    .message = msg,
                    .score = 1.0, // Simple exact match score
                });
            }
        }

        // Return copy of results
        var final_results = try std.ArrayList(MemorySearchResult).initCapacity(self.allocator, results.items.len);
        for (results.items) |result| {
            final_results.appendAssumeCapacity(result);
        }

        return final_results.toOwnedSlice();
    }

    pub fn clear(self: *Memory) void {
        for (self.messages.items) |*msg| {
            msg.deinit();
        }
        self.messages.clearAndFree();
    }

    pub fn getMessageCount(self: *Memory) usize {
        return self.messages.items.len;
    }
};