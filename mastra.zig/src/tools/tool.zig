const std = @import("std");

pub const ToolInput = struct {
    name: []const u8,
    description: []const u8,
    required: bool = true,
    type: []const u8 = "string",
};

pub const ToolOutput = struct {
    content: []const u8,
    metadata: ?std.json.Value = null,

    pub fn deinit(_: *ToolOutput) void {
        // No owned memory to free in basic implementation
    }
};

pub const ToolSchema = struct {
    name: []const u8,
    description: []const u8,
    inputs: []const ToolInput,
    output: []const u8,
};

pub const ToolExecuteFunc = *const fn (std.mem.Allocator, std.json.Value) anyerror!ToolOutput;

pub const Tool = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    description: []const u8,
    schema: ToolSchema,
    execute: ToolExecuteFunc,

    pub fn init(allocator: std.mem.Allocator, schema: ToolSchema, execute: ToolExecuteFunc) !*Tool {
        const tool = try allocator.create(Tool);
        tool.* = Tool{
            .allocator = allocator,
            .name = schema.name,
            .description = schema.description,
            .schema = schema,
            .execute = execute,
        };
        return tool;
    }

    pub fn deinit(self: *Tool) void {
        self.allocator.destroy(self);
    }

    pub fn executeTool(self: *Tool, parameters: std.json.Value) !ToolOutput {
        return try self.execute(self.allocator, parameters);
    }

    pub fn getSchema(self: *Tool) ToolSchema {
        return self.schema;
    }
};

// Utility functions for common tool creation
pub fn createTool(
    allocator: std.mem.Allocator,
    name: []const u8,
    description: []const u8,
    inputs: []const ToolInput,
    output: []const u8,
    execute: ToolExecuteFunc,
) !*Tool {
    const schema = ToolSchema{
        .name = name,
        .description = description,
        .inputs = inputs,
        .output = output,
    };

    return try Tool.init(allocator, schema, execute);
}