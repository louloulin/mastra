const std = @import("std");

/// Options for agent text generation
pub const AgentGenerateOptions = struct {
    /// Maximum number of tokens to generate
    max_tokens: ?u32 = null,
    
    /// Temperature for randomness (0.0 to 2.0)
    temperature: ?f32 = null,
    
    /// Top-p sampling parameter
    top_p: ?f32 = null,
    
    /// Top-k sampling parameter
    top_k: ?u32 = null,
    
    /// Frequency penalty (-2.0 to 2.0)
    frequency_penalty: ?f32 = null,
    
    /// Presence penalty (-2.0 to 2.0)
    presence_penalty: ?f32 = null,
    
    /// Stop sequences
    stop: ?[]const []const u8 = null,
    
    /// Whether to include usage statistics in response
    include_usage: bool = true,
    
    /// Custom metadata to include in request
    metadata: ?std.json.Value = null,
    
    /// Timeout for the request in milliseconds
    timeout_ms: ?u64 = null,
    
    /// Whether to enable tool calling
    enable_tools: bool = true,
    
    /// Maximum number of tool calls per generation
    max_tool_calls: ?u32 = null,

    const Self = @This();

    /// Create default generation options
    pub fn default() Self {
        return Self{};
    }

    /// Create options optimized for creative tasks
    pub fn creative() Self {
        return Self{
            .temperature = 0.8,
            .top_p = 0.9,
            .frequency_penalty = 0.1,
            .presence_penalty = 0.1,
        };
    }

    /// Create options optimized for factual/analytical tasks
    pub fn factual() Self {
        return Self{
            .temperature = 0.2,
            .top_p = 0.8,
            .frequency_penalty = 0.0,
            .presence_penalty = 0.0,
        };
    }

    /// Create options optimized for code generation
    pub fn code() Self {
        return Self{
            .temperature = 0.1,
            .top_p = 0.95,
            .frequency_penalty = 0.0,
            .presence_penalty = 0.0,
            .enable_tools = true,
        };
    }

    /// Merge with another options struct, with other taking precedence
    pub fn merge(self: Self, other: Self) Self {
        return Self{
            .max_tokens = other.max_tokens orelse self.max_tokens,
            .temperature = other.temperature orelse self.temperature,
            .top_p = other.top_p orelse self.top_p,
            .top_k = other.top_k orelse self.top_k,
            .frequency_penalty = other.frequency_penalty orelse self.frequency_penalty,
            .presence_penalty = other.presence_penalty orelse self.presence_penalty,
            .stop = other.stop orelse self.stop,
            .include_usage = other.include_usage,
            .metadata = other.metadata orelse self.metadata,
            .timeout_ms = other.timeout_ms orelse self.timeout_ms,
            .enable_tools = other.enable_tools,
            .max_tool_calls = other.max_tool_calls orelse self.max_tool_calls,
        };
    }

    /// Convert to JSON for API requests
    pub fn toJson(self: Self, allocator: std.mem.Allocator) !std.json.Value {
        var obj = std.json.ObjectMap.init(allocator);

        if (self.max_tokens) |val| {
            try obj.put("max_tokens", std.json.Value{ .integer = @intCast(val) });
        }
        if (self.temperature) |val| {
            try obj.put("temperature", std.json.Value{ .float = val });
        }
        if (self.top_p) |val| {
            try obj.put("top_p", std.json.Value{ .float = val });
        }
        if (self.top_k) |val| {
            try obj.put("top_k", std.json.Value{ .integer = @intCast(val) });
        }
        if (self.frequency_penalty) |val| {
            try obj.put("frequency_penalty", std.json.Value{ .float = val });
        }
        if (self.presence_penalty) |val| {
            try obj.put("presence_penalty", std.json.Value{ .float = val });
        }
        if (self.stop) |stops| {
            var stop_array = std.json.Array.init(allocator);
            for (stops) |stop_seq| {
                try stop_array.append(std.json.Value{ .string = stop_seq });
            }
            try obj.put("stop", std.json.Value{ .array = stop_array });
        }

        return std.json.Value{ .object = obj };
    }
};

/// Options for agent streaming generation
pub const AgentStreamOptions = struct {
    /// Base generation options
    base: AgentGenerateOptions = AgentGenerateOptions.default(),
    
    /// Whether to stream partial results
    stream: bool = true,
    
    /// Chunk size for streaming (in tokens)
    chunk_size: ?u32 = null,
    
    /// Buffer size for streaming
    buffer_size: usize = 4096,
    
    /// Whether to include delta information in stream
    include_deltas: bool = true,
    
    /// Whether to include finish reason in final chunk
    include_finish_reason: bool = true,
    
    /// Callback for handling stream chunks
    on_chunk: ?*const fn ([]const u8) void = null,
    
    /// Callback for handling stream completion
    on_complete: ?*const fn () void = null,
    
    /// Callback for handling stream errors
    on_error: ?*const fn (anyerror) void = null,

    const Self = @This();

    /// Create default streaming options
    pub fn default() Self {
        return Self{};
    }

    /// Create streaming options with custom base options
    pub fn withBase(base_options: AgentGenerateOptions) Self {
        return Self{
            .base = base_options,
        };
    }

    /// Create streaming options optimized for real-time chat
    pub fn realtime() Self {
        return Self{
            .base = AgentGenerateOptions{
                .temperature = 0.7,
                .max_tokens = 1000,
            },
            .chunk_size = 10,
            .buffer_size = 1024,
            .include_deltas = true,
        };
    }

    /// Create streaming options optimized for long-form content
    pub fn longForm() Self {
        return Self{
            .base = AgentGenerateOptions{
                .temperature = 0.6,
                .max_tokens = 4000,
            },
            .chunk_size = 50,
            .buffer_size = 8192,
            .include_deltas = false,
        };
    }

    /// Convert to JSON for API requests
    pub fn toJson(self: Self, allocator: std.mem.Allocator) !std.json.Value {
        var base_json = try self.base.toJson(allocator);
        
        if (base_json == .object) {
            try base_json.object.put("stream", std.json.Value{ .bool = self.stream });
            
            if (self.chunk_size) |size| {
                try base_json.object.put("chunk_size", std.json.Value{ .integer = @intCast(size) });
            }
        }

        return base_json;
    }
};

/// Response from agent generation
pub const AgentGenerateResponse = struct {
    content: []const u8,
    usage: ?GenerationUsage = null,
    finish_reason: ?[]const u8 = null,
    metadata: ?std.json.Value = null,
    tool_calls: ?[]ToolCall = null,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.content);
        if (self.tool_calls) |calls| {
            for (calls) |*call| {
                call.deinit();
            }
            self.allocator.free(calls);
        }
    }
};

/// Usage statistics for generation
pub const GenerationUsage = struct {
    prompt_tokens: u32,
    completion_tokens: u32,
    total_tokens: u32,
    
    pub fn init(prompt: u32, completion: u32) GenerationUsage {
        return GenerationUsage{
            .prompt_tokens = prompt,
            .completion_tokens = completion,
            .total_tokens = prompt + completion,
        };
    }
};

/// Tool call information
pub const ToolCall = struct {
    id: []const u8,
    name: []const u8,
    arguments: std.json.Value,
    result: ?std.json.Value = null,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, id: []const u8, name: []const u8, arguments: std.json.Value) !Self {
        return Self{
            .id = try allocator.dupe(u8, id),
            .name = try allocator.dupe(u8, name),
            .arguments = arguments,
            .result = null,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.id);
        self.allocator.free(self.name);
    }
};

/// Stream chunk for streaming responses
pub const StreamChunk = struct {
    content: []const u8,
    delta: ?[]const u8 = null,
    finish_reason: ?[]const u8 = null,
    usage: ?GenerationUsage = null,
    is_final: bool = false,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.content);
        if (self.delta) |delta| {
            self.allocator.free(delta);
        }
    }
};

// Tests
test "AgentGenerateOptions creation and merging" {
    const options1 = AgentGenerateOptions.creative();
    const options2 = AgentGenerateOptions{ .max_tokens = 1000 };
    
    const merged = options1.merge(options2);
    
    try std.testing.expectEqual(@as(?u32, 1000), merged.max_tokens);
    try std.testing.expectEqual(@as(?f32, 0.8), merged.temperature);
}

test "AgentStreamOptions creation" {
    const stream_opts = AgentStreamOptions.realtime();
    
    try std.testing.expectEqual(true, stream_opts.stream);
    try std.testing.expectEqual(@as(?u32, 10), stream_opts.chunk_size);
    try std.testing.expectEqual(@as(?f32, 0.7), stream_opts.base.temperature);
}

test "GenerationUsage calculation" {
    const usage = GenerationUsage.init(100, 50);
    
    try std.testing.expectEqual(@as(u32, 100), usage.prompt_tokens);
    try std.testing.expectEqual(@as(u32, 50), usage.completion_tokens);
    try std.testing.expectEqual(@as(u32, 150), usage.total_tokens);
}
