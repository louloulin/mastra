const std = @import("std");
const tool = @import("tool.zig");
const tool_builder = @import("tool_builder.zig");

/// MCP (Model Context Protocol) implementation
/// Provides standardized communication between AI models and external tools
/// MCP message types
pub const MCPMessageType = enum {
    request,
    response,
    notification,
    @"error",
};

/// MCP request structure
pub const MCPRequest = struct {
    id: []const u8,
    method: []const u8,
    params: ?std.json.Value = null,

    pub fn fromJson(allocator: std.mem.Allocator, json_str: []const u8) !MCPRequest {
        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_str, .{});
        defer parsed.deinit();

        const root = parsed.value;
        if (root != .object) {
            return error.InvalidMCPRequest;
        }

        const obj = root.object;
        const id = obj.get("id") orelse return error.MissingRequestId;
        const method = obj.get("method") orelse return error.MissingMethod;
        const params = obj.get("params");

        return MCPRequest{
            .id = id.string,
            .method = method.string,
            .params = if (params) |p| p else null,
        };
    }

    pub fn toJson(self: *const MCPRequest, allocator: std.mem.Allocator) ![]const u8 {
        var obj = std.json.ObjectMap.init(allocator);
        defer obj.deinit();

        try obj.put("id", std.json.Value{ .string = self.id });
        try obj.put("method", std.json.Value{ .string = self.method });

        if (self.params) |params| {
            try obj.put("params", params);
        }

        const json_value = std.json.Value{ .object = obj };
        return try std.json.stringifyAlloc(allocator, json_value, .{});
    }
};

/// MCP response structure
pub const MCPResponse = struct {
    id: []const u8,
    result: ?std.json.Value = null,
    @"error": ?MCPError = null,

    pub const MCPError = struct {
        code: i32,
        message: []const u8,
        data: ?std.json.Value = null,
    };

    pub fn success(allocator: std.mem.Allocator, id: []const u8, result: std.json.Value) MCPResponse {
        _ = allocator;
        return MCPResponse{
            .id = id,
            .result = result,
            .@"error" = null,
        };
    }

    pub fn failure(allocator: std.mem.Allocator, id: []const u8, code: i32, message: []const u8) MCPResponse {
        _ = allocator;
        return MCPResponse{
            .id = id,
            .result = null,
            .@"error" = MCPError{
                .code = code,
                .message = message,
                .data = null,
            },
        };
    }

    pub fn toJson(self: *const MCPResponse, allocator: std.mem.Allocator) ![]const u8 {
        var obj = std.json.ObjectMap.init(allocator);
        defer obj.deinit();

        try obj.put("id", std.json.Value{ .string = self.id });

        if (self.result) |result| {
            try obj.put("result", result);
        }

        if (self.@"error") |err| {
            var error_obj = std.json.ObjectMap.init(allocator);
            defer error_obj.deinit();

            try error_obj.put("code", std.json.Value{ .integer = err.code });
            try error_obj.put("message", std.json.Value{ .string = err.message });

            if (err.data) |data| {
                try error_obj.put("data", data);
            }

            try obj.put("error", std.json.Value{ .object = error_obj });
        }

        const json_value = std.json.Value{ .object = obj };
        return try std.json.stringifyAlloc(allocator, json_value, .{});
    }
};

/// MCP tool descriptor
pub const MCPToolDescriptor = struct {
    name: []const u8,
    description: []const u8,
    input_schema: std.json.Value,

    pub fn fromDynamicTool(allocator: std.mem.Allocator, definition: tool_builder.DynamicToolDefinition) !MCPToolDescriptor {
        // Convert parameters to JSON schema
        var schema = std.json.ObjectMap.init(allocator);

        try schema.put("type", std.json.Value{ .string = "object" });

        var properties = std.json.ObjectMap.init(allocator);

        var required = std.ArrayList(std.json.Value).init(allocator);

        for (definition.parameters) |param| {
            var param_schema = std.json.ObjectMap.init(allocator);
            defer param_schema.deinit();

            const type_str = switch (param.type) {
                .string => "string",
                .integer => "integer",
                .number => "number",
                .boolean => "boolean",
                .array => "array",
                .object => "object",
                .@"enum" => "string",
            };

            try param_schema.put("type", std.json.Value{ .string = type_str });
            try param_schema.put("description", std.json.Value{ .string = param.description });

            if (param.enum_values) |enum_vals| {
                var enum_array = std.ArrayList(std.json.Value).init(allocator);

                for (enum_vals) |enum_val| {
                    try enum_array.append(std.json.Value{ .string = enum_val });
                }

                try param_schema.put("enum", std.json.Value{ .array = enum_array });
            }

            try properties.put(param.name, std.json.Value{ .object = param_schema });

            if (param.required) {
                try required.append(std.json.Value{ .string = param.name });
            }
        }

        try schema.put("properties", std.json.Value{ .object = properties });
        try schema.put("required", std.json.Value{ .array = required });

        return MCPToolDescriptor{
            .name = definition.name,
            .description = definition.description,
            .input_schema = std.json.Value{ .object = schema },
        };
    }
};

/// MCP server implementation
pub const MCPServer = struct {
    allocator: std.mem.Allocator,
    registry: *tool_builder.ToolRegistry,
    capabilities: MCPCapabilities,

    const Self = @This();

    pub const MCPCapabilities = struct {
        tools: bool = true,
        resources: bool = false,
        prompts: bool = false,
        logging: bool = true,
    };

    pub fn init(allocator: std.mem.Allocator, registry: *tool_builder.ToolRegistry) Self {
        return Self{
            .allocator = allocator,
            .registry = registry,
            .capabilities = MCPCapabilities{},
        };
    }

    pub fn handleRequest(self: *Self, request_json: []const u8) ![]const u8 {
        const request = try MCPRequest.fromJson(self.allocator, request_json);

        if (std.mem.eql(u8, request.method, "initialize")) {
            return try self.handleInitialize(request);
        } else if (std.mem.eql(u8, request.method, "tools/list")) {
            return try self.handleToolsList(request);
        } else if (std.mem.eql(u8, request.method, "tools/call")) {
            return try self.handleToolsCall(request);
        } else {
            const response = MCPResponse.failure(self.allocator, request.id, -32601, "Method not found");
            return try response.toJson(self.allocator);
        }
    }

    fn handleInitialize(self: *Self, request: MCPRequest) ![]const u8 {
        var result = std.json.ObjectMap.init(self.allocator);
        defer result.deinit();

        try result.put("protocolVersion", std.json.Value{ .string = "2024-11-05" });

        var capabilities = std.json.ObjectMap.init(self.allocator);
        defer capabilities.deinit();

        var tools_cap = std.json.ObjectMap.init(self.allocator);
        defer tools_cap.deinit();
        try tools_cap.put("listChanged", std.json.Value{ .bool = true });
        try capabilities.put("tools", std.json.Value{ .object = tools_cap });

        var logging_cap = std.json.ObjectMap.init(self.allocator);
        defer logging_cap.deinit();
        try capabilities.put("logging", std.json.Value{ .object = logging_cap });

        try result.put("capabilities", std.json.Value{ .object = capabilities });

        var server_info = std.json.ObjectMap.init(self.allocator);
        defer server_info.deinit();
        try server_info.put("name", std.json.Value{ .string = "Mastra.zig MCP Server" });
        try server_info.put("version", std.json.Value{ .string = "1.0.0" });
        try result.put("serverInfo", std.json.Value{ .object = server_info });

        const response = MCPResponse.success(self.allocator, request.id, std.json.Value{ .object = result });
        return try response.toJson(self.allocator);
    }

    fn handleToolsList(self: *Self, request: MCPRequest) ![]const u8 {
        const tool_names = try self.registry.listTools();
        defer self.allocator.free(tool_names);

        var tools_array = std.ArrayList(std.json.Value).init(self.allocator);

        for (tool_names) |tool_name| {
            if (self.registry.getTool(tool_name)) |definition| {
                const descriptor = try MCPToolDescriptor.fromDynamicTool(self.allocator, definition);

                var tool_obj = std.json.ObjectMap.init(self.allocator);
                defer tool_obj.deinit();

                try tool_obj.put("name", std.json.Value{ .string = descriptor.name });
                try tool_obj.put("description", std.json.Value{ .string = descriptor.description });
                try tool_obj.put("inputSchema", descriptor.input_schema);

                try tools_array.append(std.json.Value{ .object = tool_obj });
            }
        }

        var result = std.json.ObjectMap.init(self.allocator);
        defer result.deinit();
        try result.put("tools", std.json.Value{ .array = tools_array });

        const response = MCPResponse.success(self.allocator, request.id, std.json.Value{ .object = result });
        return try response.toJson(self.allocator);
    }

    fn handleToolsCall(self: *Self, request: MCPRequest) ![]const u8 {
        const params = request.params orelse {
            const response = MCPResponse.failure(self.allocator, request.id, -32602, "Invalid params");
            return try response.toJson(self.allocator);
        };

        if (params != .object) {
            const response = MCPResponse.failure(self.allocator, request.id, -32602, "Invalid params");
            return try response.toJson(self.allocator);
        }

        const params_obj = params.object;
        const tool_name = params_obj.get("name") orelse {
            const response = MCPResponse.failure(self.allocator, request.id, -32602, "Missing tool name");
            return try response.toJson(self.allocator);
        };

        const arguments = params_obj.get("arguments") orelse {
            const response = MCPResponse.failure(self.allocator, request.id, -32602, "Missing arguments");
            return try response.toJson(self.allocator);
        };

        // Create tool input
        const tool_input = tool.ToolInput{
            .data = arguments,
        };

        // Execute tool
        const tool_output = self.registry.executeTool(tool_name.string, tool_input) catch |err| {
            const error_msg = switch (err) {
                error.ToolNotFound => "Tool not found",
                error.MissingRequiredParameter => "Missing required parameter",
                error.InvalidParameterType => "Invalid parameter type",
                else => "Tool execution failed",
            };
            const response = MCPResponse.failure(self.allocator, request.id, -32603, error_msg);
            return try response.toJson(self.allocator);
        };

        var result = std.json.ObjectMap.init(self.allocator);
        defer result.deinit();

        try result.put("content", tool_output.data);
        try result.put("isError", std.json.Value{ .bool = false });

        const response = MCPResponse.success(self.allocator, request.id, std.json.Value{ .object = result });
        return try response.toJson(self.allocator);
    }
};
