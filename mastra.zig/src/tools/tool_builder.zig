const std = @import("std");
const tool = @import("tool.zig");

/// Dynamic tool parameter definition
pub const ParameterDefinition = struct {
    name: []const u8,
    type: ParameterType,
    description: []const u8,
    required: bool = true,
    default_value: ?std.json.Value = null,
    enum_values: ?[][]const u8 = null,
    min_value: ?f64 = null,
    max_value: ?f64 = null,
    pattern: ?[]const u8 = null,

    pub const ParameterType = enum {
        string,
        integer,
        number,
        boolean,
        array,
        object,
        @"enum",
    };

    pub fn validate(self: *const ParameterDefinition, value: std.json.Value) bool {
        switch (self.type) {
            .string => return value == .string,
            .integer => return value == .integer,
            .number => return value == .float or value == .integer,
            .boolean => return value == .bool,
            .array => return value == .array,
            .object => return value == .object,
            .@"enum" => {
                if (value != .string) return false;
                if (self.enum_values) |enum_vals| {
                    for (enum_vals) |enum_val| {
                        if (std.mem.eql(u8, value.string, enum_val)) {
                            return true;
                        }
                    }
                    return false;
                }
                return true;
            },
        }
    }
};

/// Tool execution function signature
pub const ToolExecuteFn = *const fn (allocator: std.mem.Allocator, input: tool.ToolInput) anyerror!tool.ToolOutput;

/// Dynamic tool definition
pub const DynamicToolDefinition = struct {
    name: []const u8,
    description: []const u8,
    parameters: []ParameterDefinition,
    execute_fn: ToolExecuteFn,
    category: []const u8 = "general",
    version: []const u8 = "1.0.0",
    author: ?[]const u8 = null,
    tags: [][]const u8 = &[_][]const u8{},
    examples: []ToolExample = &[_]ToolExample{},

    pub const ToolExample = struct {
        description: []const u8,
        input: std.json.Value,
        expected_output: std.json.Value,
    };

    pub fn validateInput(self: *const DynamicToolDefinition, input: tool.ToolInput) !void {
        for (self.parameters) |param| {
            const value = input.data.object.get(param.name);

            if (param.required and value == null) {
                return error.MissingRequiredParameter;
            }

            if (value) |val| {
                if (!param.validate(val)) {
                    return error.InvalidParameterType;
                }
            }
        }
    }
};

/// Tool registry for managing dynamic tools
pub const ToolRegistry = struct {
    allocator: std.mem.Allocator,
    tools: std.StringHashMap(DynamicToolDefinition),
    categories: std.StringHashMap(std.ArrayList([]const u8)),
    mutex: std.Thread.Mutex,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .tools = std.StringHashMap(DynamicToolDefinition).init(allocator),
            .categories = std.StringHashMap(std.ArrayList([]const u8)).init(allocator),
            .mutex = std.Thread.Mutex{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var category_iter = self.categories.iterator();
        while (category_iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.categories.deinit();
        self.tools.deinit();
    }

    pub fn registerTool(self: *Self, definition: DynamicToolDefinition) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Validate tool definition
        try self.validateToolDefinition(definition);

        // Register the tool
        try self.tools.put(definition.name, definition);

        // Add to category
        const category_result = try self.categories.getOrPut(definition.category);
        if (!category_result.found_existing) {
            category_result.value_ptr.* = std.ArrayList([]const u8).init(self.allocator);
        }
        try category_result.value_ptr.append(definition.name);

        std.log.info("Tool registered: {s} (category: {s})", .{ definition.name, definition.category });
    }

    pub fn unregisterTool(self: *Self, name: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.tools.get(name)) |definition| {
            // Remove from category
            if (self.categories.getPtr(definition.category)) |category_tools| {
                for (category_tools.items, 0..) |tool_name, i| {
                    if (std.mem.eql(u8, tool_name, name)) {
                        _ = category_tools.swapRemove(i);
                        break;
                    }
                }
            }

            // Remove the tool
            _ = self.tools.remove(name);
            std.log.info("Tool unregistered: {s}", .{name});
        } else {
            return error.ToolNotFound;
        }
    }

    pub fn getTool(self: *Self, name: []const u8) ?DynamicToolDefinition {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.tools.get(name);
    }

    pub fn listTools(self: *Self) ![][]const u8 {
        self.mutex.lock();
        defer self.mutex.unlock();

        var tool_names = std.ArrayList([]const u8).init(self.allocator);
        defer tool_names.deinit();

        var iter = self.tools.iterator();
        while (iter.next()) |entry| {
            try tool_names.append(entry.key_ptr.*);
        }

        return try tool_names.toOwnedSlice();
    }

    pub fn listToolsByCategory(self: *Self, category: []const u8) ![][]const u8 {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.categories.get(category)) |category_tools| {
            return try self.allocator.dupe([]const u8, category_tools.items);
        }

        return &[_][]const u8{};
    }

    pub fn searchTools(self: *Self, query: []const u8) ![][]const u8 {
        self.mutex.lock();
        defer self.mutex.unlock();

        var results = std.ArrayList([]const u8).init(self.allocator);
        defer results.deinit();

        var iter = self.tools.iterator();
        while (iter.next()) |entry| {
            const definition = entry.value_ptr.*;

            // Search in name, description, and tags
            if (std.mem.indexOf(u8, definition.name, query) != null or
                std.mem.indexOf(u8, definition.description, query) != null)
            {
                try results.append(definition.name);
                continue;
            }

            for (definition.tags) |tag| {
                if (std.mem.indexOf(u8, tag, query) != null) {
                    try results.append(definition.name);
                    break;
                }
            }
        }

        return try results.toOwnedSlice();
    }

    fn validateToolDefinition(self: *Self, definition: DynamicToolDefinition) !void {
        _ = self;

        // Validate tool name
        if (definition.name.len == 0) {
            return error.InvalidToolName;
        }

        // Validate description
        if (definition.description.len == 0) {
            return error.InvalidToolDescription;
        }

        // Validate parameters
        for (definition.parameters) |param| {
            if (param.name.len == 0) {
                return error.InvalidParameterName;
            }
            if (param.description.len == 0) {
                return error.InvalidParameterDescription;
            }
        }
    }

    pub fn executeTool(self: *Self, name: []const u8, input: tool.ToolInput) !tool.ToolOutput {
        const definition = self.getTool(name) orelse return error.ToolNotFound;

        // Validate input
        try definition.validateInput(input);

        // Execute the tool
        return try definition.execute_fn(self.allocator, input);
    }
};

/// Tool builder for creating dynamic tools
pub const ToolBuilder = struct {
    allocator: std.mem.Allocator,
    name: ?[]const u8 = null,
    description: ?[]const u8 = null,
    parameters: std.ArrayList(ParameterDefinition),
    execute_fn: ?ToolExecuteFn = null,
    category: []const u8 = "general",
    version: []const u8 = "1.0.0",
    author: ?[]const u8 = null,
    tags: std.ArrayList([]const u8),
    examples: std.ArrayList(DynamicToolDefinition.ToolExample),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .parameters = std.ArrayList(ParameterDefinition).init(allocator),
            .tags = std.ArrayList([]const u8).init(allocator),
            .examples = std.ArrayList(DynamicToolDefinition.ToolExample).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.parameters.deinit();
        self.tags.deinit();
        self.examples.deinit();
    }

    pub fn setName(self: *Self, name: []const u8) *Self {
        self.name = name;
        return self;
    }

    pub fn setDescription(self: *Self, description: []const u8) *Self {
        self.description = description;
        return self;
    }

    pub fn setCategory(self: *Self, category: []const u8) *Self {
        self.category = category;
        return self;
    }

    pub fn setVersion(self: *Self, version: []const u8) *Self {
        self.version = version;
        return self;
    }

    pub fn setAuthor(self: *Self, author: []const u8) *Self {
        self.author = author;
        return self;
    }

    pub fn setExecuteFunction(self: *Self, execute_fn: ToolExecuteFn) *Self {
        self.execute_fn = execute_fn;
        return self;
    }

    pub fn addParameter(self: *Self, param: ParameterDefinition) !*Self {
        try self.parameters.append(param);
        return self;
    }

    pub fn addTag(self: *Self, tag: []const u8) !*Self {
        try self.tags.append(tag);
        return self;
    }

    pub fn addExample(self: *Self, example: DynamicToolDefinition.ToolExample) !*Self {
        try self.examples.append(example);
        return self;
    }

    pub fn build(self: *Self) !DynamicToolDefinition {
        if (self.name == null) {
            return error.MissingToolName;
        }
        if (self.description == null) {
            return error.MissingToolDescription;
        }
        if (self.execute_fn == null) {
            return error.MissingExecuteFunction;
        }

        return DynamicToolDefinition{
            .name = self.name.?,
            .description = self.description.?,
            .parameters = try self.parameters.toOwnedSlice(),
            .execute_fn = self.execute_fn.?,
            .category = self.category,
            .version = self.version,
            .author = self.author,
            .tags = try self.tags.toOwnedSlice(),
            .examples = try self.examples.toOwnedSlice(),
        };
    }
};
