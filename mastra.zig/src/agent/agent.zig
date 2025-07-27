const std = @import("std");
const Logger = @import("../utils/logger.zig").Logger;
const Memory = @import("../memory/memory.zig").Memory;
const Tool = @import("../tools/tool.zig").Tool;
const LLM = @import("../llm/llm.zig").LLM;
const Storage = @import("../storage/storage.zig").Storage;

// Import new components
const DynamicArgument = @import("dynamic_argument.zig").DynamicArgument;
const DynamicString = @import("dynamic_argument.zig").DynamicString;
const RuntimeContext = @import("dynamic_argument.zig").RuntimeContext;
const MessageList = @import("message_list.zig").MessageList;
const MessageListConfig = @import("message_list.zig").MessageListConfig;
const MessageImportance = @import("message_list.zig").MessageImportance;
const SaveQueueManager = @import("save_queue_manager.zig").SaveQueueManager;
const SaveQueueConfig = @import("save_queue_manager.zig").SaveQueueConfig;
const AgentGenerateOptions = @import("agent_options.zig").AgentGenerateOptions;
const AgentStreamOptions = @import("agent_options.zig").AgentStreamOptions;
const AgentGenerateResponse = @import("agent_options.zig").AgentGenerateResponse;

/// Enhanced agent configuration with dynamic arguments and advanced features
pub const AgentConfig = struct {
    name: []const u8,
    model: *LLM,
    memory: ?*Memory = null,
    tools: ?std.ArrayList(*Tool) = null,

    // Dynamic instructions support
    instructions: DynamicString = DynamicString.static("You are a helpful AI assistant."),

    // Message management
    message_list_config: MessageListConfig = MessageListConfig{},

    // Save queue configuration
    save_queue_config: SaveQueueConfig = SaveQueueConfig{},

    // Generation options
    default_generate_options: AgentGenerateOptions = AgentGenerateOptions.default(),
    default_stream_options: AgentStreamOptions = AgentStreamOptions.default(),

    // Storage for persistence
    storage: ?*Storage = null,

    // Thread ID for message persistence
    thread_id: ?[]const u8 = null,

    logger: ?*Logger = null,
};

/// Simple message structure for backward compatibility
pub const Message = struct {
    role: []const u8,
    content: []const u8,
    metadata: ?std.json.Value = null,

    pub fn deinit(_: *Message) void {
        // No owned memory to free in basic implementation
    }
};

/// Legacy response structure - use AgentGenerateResponse for new code
pub const AgentResponse = struct {
    content: []const u8,
    usage: ?std.json.Value = null,
    metadata: ?std.json.Value = null,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *AgentResponse) void {
        self.allocator.free(self.content);
    }
};

/// Enhanced Agent with dynamic arguments and advanced message management
pub const Agent = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    model: *LLM,
    memory: ?*Memory,
    tools: std.ArrayList(*Tool),

    // Dynamic instructions
    instructions: DynamicString,

    // Advanced message management
    message_list: *MessageList,

    // Async save queue
    save_queue: ?*SaveQueueManager,

    // Generation options
    default_generate_options: AgentGenerateOptions,
    default_stream_options: AgentStreamOptions,

    // Runtime context for dynamic resolution
    runtime_context: RuntimeContext,

    logger: *Logger,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: AgentConfig) !*Agent {
        const agent = try allocator.create(Agent);

        var tools = std.ArrayList(*Tool).init(allocator);
        if (config.tools) |tool_list| {
            try tools.appendSlice(tool_list.items);
        }

        const logger = config.logger orelse try Logger.init(allocator, .{ .level = .info });

        // Initialize message list
        const message_list = try MessageList.init(allocator, config.message_list_config, config.storage);

        // Initialize save queue if storage is available
        var save_queue: ?*SaveQueueManager = null;
        if (config.storage) |storage| {
            save_queue = try SaveQueueManager.init(allocator, config.save_queue_config, storage);
        }

        // Initialize runtime context
        const runtime_context = RuntimeContext.init(allocator);

        agent.* = Agent{
            .allocator = allocator,
            .name = config.name,
            .model = config.model,
            .memory = config.memory,
            .tools = tools,
            .instructions = config.instructions,
            .message_list = message_list,
            .save_queue = save_queue,
            .default_generate_options = config.default_generate_options,
            .default_stream_options = config.default_stream_options,
            .runtime_context = runtime_context,
            .logger = logger,
        };

        agent.logger.info("Enhanced Agent {s} initialized with {} tools", .{ config.name, tools.items.len });
        return agent;
    }

    pub fn deinit(self: *Agent) void {
        self.tools.deinit();
        if (self.memory) |memory| {
            memory.deinit();
        }

        // Clean up message list
        self.message_list.deinit();

        // Clean up save queue
        if (self.save_queue) |queue| {
            queue.deinit();
        }

        // Clean up runtime context
        self.runtime_context.deinit();

        self.logger.deinit();
        self.allocator.destroy(self);
    }

    /// Legacy generate method for backward compatibility
    pub fn generate(self: *Agent, messages: []const Message) !AgentResponse {
        // Convert to new format and use enhanced generate
        const options = self.default_generate_options;
        var response = try self.generateWithOptions(messages, options);
        defer response.deinit();

        // Convert back to legacy format
        const content_copy = try self.allocator.dupe(u8, response.content);
        return AgentResponse{
            .content = content_copy,
            .usage = null, // Legacy format doesn't include detailed usage
            .metadata = response.metadata,
            .allocator = self.allocator,
        };
    }

    /// Enhanced generate method with options
    pub fn generateWithOptions(self: *Agent, messages: []const Message, options: AgentGenerateOptions) !AgentGenerateResponse {
        self.logger.info("Agent {s} generating response for {d} messages with options", .{ self.name, messages.len });

        // Add messages to message list
        for (messages) |msg| {
            try self.message_list.addMessage(msg.role, msg.content, .normal);
        }

        // Resolve dynamic instructions
        const instructions = try self.instructions.resolve(self.runtime_context);

        // Get context from message list with token limit from options
        const max_tokens = options.max_tokens orelse 4000;
        const context_messages = try self.message_list.getContext(max_tokens);
        defer self.allocator.free(context_messages);

        var formatted_messages = std.ArrayList(Message).init(self.allocator);
        defer formatted_messages.deinit();

        // Add system message with resolved instructions
        try formatted_messages.append(.{
            .role = "system",
            .content = instructions,
            .metadata = null,
        });

        // Add context messages
        for (context_messages) |ctx_msg| {
            try formatted_messages.append(.{
                .role = ctx_msg.role,
                .content = ctx_msg.content,
                .metadata = ctx_msg.metadata,
            });
        }

        // Generate response using LLM with options
        // TODO: Pass options to LLM generate method
        var llm_response = try self.model.generate(formatted_messages.items, null);
        defer llm_response.deinit();

        // Add response to message list
        try self.message_list.addMessage("assistant", llm_response.content, .normal);

        // Update memory if available
        if (self.memory) |memory| {
            for (messages) |msg| {
                try memory.addMessage(.{ .role = msg.role, .content = msg.content });
            }
            try memory.addMessage(.{ .role = "assistant", .content = llm_response.content });
        }

        // Create enhanced response
        const content_copy = try self.allocator.dupe(u8, llm_response.content);

        return AgentGenerateResponse{
            .content = content_copy,
            .usage = null, // TODO: Extract usage from LLM response
            .finish_reason = null,
            .metadata = null, // LLM response doesn't have metadata field
            .tool_calls = null, // TODO: Handle tool calls
            .allocator = self.allocator,
        };
    }

    /// Stream generation with options
    pub fn streamWithOptions(self: *Agent, messages: []const Message, options: AgentStreamOptions) !void {
        // TODO: Implement streaming generation
        _ = self;
        _ = messages;
        _ = options;
        return error.NotImplemented;
    }

    /// Update runtime context variable
    pub fn setContextVariable(self: *Agent, key: []const u8, value: std.json.Value) !void {
        try self.runtime_context.setVariable(key, value);
    }

    /// Get runtime context variable
    pub fn getContextVariable(self: *Agent, key: []const u8) ?std.json.Value {
        return self.runtime_context.getVariable(key);
    }

    /// Update runtime context metadata
    pub fn setContextMetadata(self: *Agent, key: []const u8, value: std.json.Value) !void {
        try self.runtime_context.setMetadata(key, value);
    }

    /// Get message list statistics
    pub fn getMessageStats(self: *Agent) struct { count: usize, tokens: usize } {
        return .{
            .count = self.message_list.getMessageCount(),
            .tokens = self.message_list.getTotalTokens(),
        };
    }

    /// Flush pending save operations
    pub fn flushSaves(self: *Agent) !void {
        if (self.save_queue) |queue| {
            try queue.flush();
        }
    }

    /// Legacy stream method for backward compatibility
    pub fn stream(self: *Agent, messages: []const Message) !void {
        const options = self.default_stream_options;
        try self.streamWithOptions(messages, options);
    }

    pub fn getMemory(self: *Agent) ?*Memory {
        return self.memory;
    }

    pub fn getTools(self: *Agent) []const *Tool {
        return self.tools.items;
    }

    pub fn addTool(self: *Agent, tool: *Tool) !void {
        try self.tools.append(tool);
        self.logger.info("Added tool {s} to agent {s}", .{ tool.name, self.name });
    }

    pub fn removeTool(self: *Agent, tool_name: []const u8) bool {
        for (self.tools.items, 0..) |tool, i| {
            if (std.mem.eql(u8, tool.name, tool_name)) {
                _ = self.tools.swapRemove(i);
                self.logger.info("Removed tool {s} from agent {s}", .{ tool_name, self.name });
                return true;
            }
        }
        return false;
    }
};
