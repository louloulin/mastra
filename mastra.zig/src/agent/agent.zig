const std = @import("std");
const Logger = @import("../utils/logger.zig").Logger;
const Memory = @import("../memory/memory.zig").Memory;
const Tool = @import("../tools/tool.zig").Tool;
const LLM = @import("../llm/llm.zig").LLM;

pub const AgentConfig = struct {
    name: []const u8,
    model: *LLM,
    memory: ?*Memory = null,
    tools: ?std.ArrayList(*Tool) = null,
    instructions: ?[]const u8 = null,
    logger: ?*Logger = null,
};

pub const Message = struct {
    role: []const u8,
    content: []const u8,
    metadata: ?std.json.Value = null,

    pub fn deinit(_: *Message) void {
        // No owned memory to free in basic implementation
    }
};

pub const AgentResponse = struct {
    content: []const u8,
    usage: ?std.json.Value = null,
    metadata: ?std.json.Value = null,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *AgentResponse) void {
        self.allocator.free(self.content);
    }
};

pub const Agent = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    model: *LLM,
    memory: ?*Memory,
    tools: std.ArrayList(*Tool),
    instructions: ?[]const u8,
    logger: *Logger,

    pub fn init(allocator: std.mem.Allocator, config: AgentConfig) !*Agent {
        const agent = try allocator.create(Agent);

        var tools = std.ArrayList(*Tool).init(allocator);
        if (config.tools) |tool_list| {
            try tools.appendSlice(tool_list.items);
        }

        const logger = config.logger orelse try Logger.init(allocator, .{ .level = .info });

        agent.* = Agent{
            .allocator = allocator,
            .name = config.name,
            .model = config.model,
            .memory = config.memory,
            .tools = tools,
            .instructions = config.instructions,
            .logger = logger,
        };

        agent.logger.info("Agent {s} initialized", .{config.name});
        return agent;
    }

    pub fn deinit(self: *Agent) void {
        self.tools.deinit();
        if (self.memory) |memory| {
            memory.deinit();
        }
        self.logger.deinit();
        self.allocator.destroy(self);
    }

    pub fn generate(self: *Agent, messages: []const Message) !AgentResponse {
        self.logger.info("Agent {s} generating response for {d} messages", .{ self.name, messages.len });

        var formatted_messages = std.ArrayList(Message).init(self.allocator);
        defer formatted_messages.deinit();

        if (self.instructions) |instructions| {
            try formatted_messages.append(.{
                .role = "system",
                .content = instructions,
                .metadata = null,
            });
        }

        for (messages) |msg| {
            try formatted_messages.append(msg);
        }

        var response = try self.model.generate(formatted_messages.items, null);
        // 注意：不要在这里调用defer response.deinit()，因为我们需要先复制内容

        if (self.memory) |memory| {
            for (messages) |msg| {
                try memory.addMessage(.{ .role = msg.role, .content = msg.content });
            }
            try memory.addMessage(.{ .role = "assistant", .content = response.content });
        }

        // 调试：检查LLM响应内容
        std.debug.print("Agent收到LLM响应长度: {d}\n", .{response.content.len});
        std.debug.print("Agent收到LLM响应内容: {s}\n", .{response.content});

        // 复制内容到AgentResponse，避免使用已释放的内存
        const content_copy = try self.allocator.dupe(u8, response.content);

        // 现在可以安全地释放GenerateResult的内存
        response.deinit();

        // 调试：检查复制后的内容
        std.debug.print("Agent复制后内容长度: {d}\n", .{content_copy.len});
        std.debug.print("Agent复制后内容: {s}\n", .{content_copy});

        // 转换GenerateResult为AgentResponse
        return AgentResponse{
            .content = content_copy,
            .usage = null,
            .metadata = null,
            .allocator = self.allocator,
        };
    }

    pub fn stream(self: *Agent, messages: []const Message) !void {
        self.logger.info("Agent {s} streaming response for {d} messages", .{ self.name, messages.len });

        var formatted_messages = std.ArrayList(Message).init(self.allocator);
        defer formatted_messages.deinit();

        if (self.instructions) |instructions| {
            try formatted_messages.append(.{
                .role = "system",
                .content = instructions,
                .metadata = null,
            });
        }

        for (messages) |msg| {
            try formatted_messages.append(msg);
        }

        try self.model.stream(self.allocator, formatted_messages.items);
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
