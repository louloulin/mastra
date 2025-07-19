//! OpenAI API 集成
//!
//! 支持：
//! - Chat Completions API
//! - 流式响应
//! - 函数调用
//! - 错误处理和重试

const std = @import("std");
const HttpClient = @import("../core/http.zig").HttpClient;
const Header = @import("../core/http.zig").Header;
const Response = @import("../core/http.zig").Response;
const Message = @import("../agent/agent.zig").Message;
const AgentResponse = @import("../agent/agent.zig").AgentResponse;

/// OpenAI API 错误
pub const OpenAIError = error{
    ApiKeyMissing,
    HttpClientMissing,
    RequestFailed,
    ResponseParseError,
    ApiError,
    RateLimitExceeded,
    InvalidRequest,
    AuthenticationError,
    NoChoicesInResponse,
    OutOfMemory,
};

/// OpenAI 消息结构
pub const OpenAIMessage = struct {
    role: []const u8,
    content: []const u8,
    name: ?[]const u8 = null,
    function_call: ?FunctionCall = null,
    tool_calls: ?[]ToolCall = null,

    pub const FunctionCall = struct {
        name: []const u8,
        arguments: []const u8,
    };

    pub const ToolCall = struct {
        id: []const u8,
        type: []const u8,
        function: FunctionCall,
    };
};

/// OpenAI 函数定义
pub const OpenAIFunction = struct {
    name: []const u8,
    description: ?[]const u8 = null,
    parameters: std.json.Value,
};

/// OpenAI 工具定义
pub const OpenAITool = struct {
    type: []const u8 = "function",
    function: OpenAIFunction,
};

/// OpenAI 请求结构
pub const OpenAIRequest = struct {
    model: []const u8,
    messages: []OpenAIMessage,
    temperature: ?f32 = null,
    max_tokens: ?u32 = null,
    top_p: ?f32 = null,
    frequency_penalty: ?f32 = null,
    presence_penalty: ?f32 = null,
    functions: ?[]OpenAIFunction = null,
    function_call: ?std.json.Value = null,
    tools: ?[]OpenAITool = null,
    tool_choice: ?std.json.Value = null,
    stream: bool = false,
    stop: ?[][]const u8 = null,
    user: ?[]const u8 = null,
};

/// OpenAI 响应结构
pub const OpenAIResponse = struct {
    id: []const u8,
    object: []const u8,
    created: u64,
    model: []const u8,
    choices: []Choice,
    usage: ?Usage = null,
    system_fingerprint: ?[]const u8 = null,

    pub const Choice = struct {
        index: u32,
        message: OpenAIMessage,
        finish_reason: ?[]const u8 = null,
        logprobs: ?std.json.Value = null,
    };

    pub const Usage = struct {
        prompt_tokens: u32,
        completion_tokens: u32,
        total_tokens: u32,
    };
};

/// OpenAI 错误响应
pub const OpenAIErrorResponse = struct {
    @"error": ErrorDetail,

    pub const ErrorDetail = struct {
        message: []const u8,
        type: []const u8,
        param: ?[]const u8 = null,
        code: ?[]const u8 = null,
    };
};

/// OpenAI 客户端
pub const OpenAIClient = struct {
    allocator: std.mem.Allocator,
    api_key: []const u8,
    base_url: []const u8,
    http_client: *HttpClient,
    organization: ?[]const u8 = null,
    project: ?[]const u8 = null,

    const Self = @This();

    /// 初始化 OpenAI 客户端
    pub fn init(
        allocator: std.mem.Allocator,
        api_key: []const u8,
        http_client: *HttpClient,
        base_url: ?[]const u8,
    ) Self {
        return Self{
            .allocator = allocator,
            .api_key = api_key,
            .base_url = base_url orelse "https://api.openai.com/v1",
            .http_client = http_client,
        };
    }

    /// 设置组织 ID
    pub fn setOrganization(self: *Self, organization: []const u8) void {
        self.organization = organization;
    }

    /// 设置项目 ID
    pub fn setProject(self: *Self, project: []const u8) void {
        self.project = project;
    }

    /// 发送聊天完成请求
    pub fn chatCompletion(self: *Self, request: OpenAIRequest) OpenAIError!OpenAIResponse {
        // 序列化请求
        const request_json = try std.json.stringifyAlloc(self.allocator, request, .{});
        defer self.allocator.free(request_json);

        // 准备请求头
        var headers = std.ArrayList(Header).init(self.allocator);
        defer headers.deinit();

        try headers.append(.{ .name = "Authorization", .value = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{self.api_key}) });
        defer self.allocator.free(headers.items[headers.items.len - 1].value);

        try headers.append(.{ .name = "Content-Type", .value = "application/json" });

        if (self.organization) |org| {
            try headers.append(.{ .name = "OpenAI-Organization", .value = org });
        }

        if (self.project) |proj| {
            try headers.append(.{ .name = "OpenAI-Project", .value = proj });
        }

        // 构建 URL
        const url = try std.fmt.allocPrint(self.allocator, "{s}/chat/completions", .{self.base_url});
        defer self.allocator.free(url);

        // 发送请求
        var response = self.http_client.post(url, headers.items, request_json) catch |err| {
            std.log.err("OpenAI API request failed: {}", .{err});
            return OpenAIError.RequestFailed;
        };
        defer response.deinit();

        // 检查响应状态
        if (!response.isSuccess()) {
            return self.handleErrorResponse(&response);
        }

        // 解析响应
        const parsed = std.json.parseFromSlice(OpenAIResponse, self.allocator, response.body, .{}) catch |err| {
            std.log.err("Failed to parse OpenAI response: {}", .{err});
            return OpenAIError.ResponseParseError;
        };
        defer parsed.deinit();

        // 验证响应
        if (parsed.value.choices.len == 0) {
            return OpenAIError.NoChoicesInResponse;
        }

        // 复制响应数据（因为 parsed 会被释放）
        return try self.copyResponse(parsed.value);
    }

    /// 处理错误响应
    fn handleErrorResponse(self: *Self, response: *Response) OpenAIError {
        // 尝试解析错误响应
        const error_response = std.json.parseFromSlice(OpenAIErrorResponse, self.allocator, response.body, .{}) catch {
            std.log.err("OpenAI API error {d}: {s}", .{ response.status_code, response.body });
            return OpenAIError.ApiError;
        };
        defer error_response.deinit();

        const error_detail = error_response.value.@"error";
        std.log.err("OpenAI API error: {s} (type: {s})", .{ error_detail.message, error_detail.type });

        return switch (response.status_code) {
            401 => OpenAIError.AuthenticationError,
            400 => OpenAIError.InvalidRequest,
            429 => OpenAIError.RateLimitExceeded,
            else => OpenAIError.ApiError,
        };
    }

    /// 复制响应数据
    fn copyResponse(self: *Self, response: OpenAIResponse) !OpenAIResponse {
        var copied_choices = try self.allocator.alloc(OpenAIResponse.Choice, response.choices.len);

        for (response.choices, 0..) |choice, i| {
            copied_choices[i] = OpenAIResponse.Choice{
                .index = choice.index,
                .message = OpenAIMessage{
                    .role = try self.allocator.dupe(u8, choice.message.role),
                    .content = try self.allocator.dupe(u8, choice.message.content),
                    .name = if (choice.message.name) |name| try self.allocator.dupe(u8, name) else null,
                    // TODO: 复制 function_call 和 tool_calls
                },
                .finish_reason = if (choice.finish_reason) |reason| try self.allocator.dupe(u8, reason) else null,
            };
        }

        return OpenAIResponse{
            .id = try self.allocator.dupe(u8, response.id),
            .object = try self.allocator.dupe(u8, response.object),
            .created = response.created,
            .model = try self.allocator.dupe(u8, response.model),
            .choices = copied_choices,
            .usage = response.usage, // Usage 是简单的数值类型，可以直接复制
            .system_fingerprint = if (response.system_fingerprint) |fp| try self.allocator.dupe(u8, fp) else null,
        };
    }

    /// 释放响应数据
    pub fn freeResponse(self: *Self, response: *OpenAIResponse) void {
        self.allocator.free(response.id);
        self.allocator.free(response.object);
        self.allocator.free(response.model);

        for (response.choices) |choice| {
            self.allocator.free(choice.message.role);
            self.allocator.free(choice.message.content);
            if (choice.message.name) |name| {
                self.allocator.free(name);
            }
            if (choice.finish_reason) |reason| {
                self.allocator.free(reason);
            }
        }
        self.allocator.free(response.choices);

        if (response.system_fingerprint) |fp| {
            self.allocator.free(fp);
        }
    }

    /// 将 Mastra 消息转换为 OpenAI 消息
    pub fn convertMessages(self: *Self, messages: []const Message) ![]OpenAIMessage {
        var openai_messages = try self.allocator.alloc(OpenAIMessage, messages.len);

        for (messages, 0..) |message, i| {
            openai_messages[i] = OpenAIMessage{
                .role = try self.allocator.dupe(u8, message.role),
                .content = try self.allocator.dupe(u8, message.content),
            };
        }

        return openai_messages;
    }

    /// 释放转换后的消息
    pub fn freeMessages(self: *Self, messages: []OpenAIMessage) void {
        for (messages) |message| {
            self.allocator.free(message.role);
            self.allocator.free(message.content);
            if (message.name) |name| {
                self.allocator.free(name);
            }
        }
        self.allocator.free(messages);
    }

    /// 流式完成请求
    pub fn streamCompletion(
        self: *Self,
        allocator: std.mem.Allocator,
        request: OpenAIRequest,
        callback: *const fn (chunk: []const u8) void,
    ) OpenAIError!void {
        // api_key是非可选类型，不需要检查null

        // http_client是非可选类型，不需要检查null

        // 序列化请求
        const json_body = try std.json.stringifyAlloc(allocator, request, .{});
        defer allocator.free(json_body);

        // 准备头部
        const auth_header = try std.fmt.allocPrint(allocator, "Bearer {s}", .{self.api_key});
        defer allocator.free(auth_header);

        const headers = [_]Header{
            .{ .name = "Authorization", .value = auth_header },
            .{ .name = "Content-Type", .value = "application/json" },
            .{ .name = "Accept", .value = "text/event-stream" },
        };

        // 构建完整的URL
        const url = try std.fmt.allocPrint(allocator, "{s}/chat/completions", .{self.base_url});
        defer allocator.free(url);

        // 发送流式请求
        var response = self.http_client.request(.{
            .method = .POST,
            .url = url,
            .headers = &headers,
            .body = json_body,
        }) catch |err| {
            return switch (err) {
                else => OpenAIError.RequestFailed,
            };
        };
        defer response.deinit();

        if (!response.isSuccess()) {
            return OpenAIError.ApiError;
        }

        // 解析Server-Sent Events流
        try self.parseSSEStream(response.body, callback);
    }

    /// 解析Server-Sent Events流
    fn parseSSEStream(self: *Self, stream_data: []const u8, callback: *const fn (chunk: []const u8) void) !void {
        var lines = std.mem.splitSequence(u8, stream_data, "\n");

        while (lines.next()) |line| {
            if (std.mem.startsWith(u8, line, "data: ")) {
                const data = line[6..]; // 跳过"data: "

                if (std.mem.eql(u8, data, "[DONE]")) {
                    break;
                }

                // 解析JSON数据并提取内容
                var parsed = std.json.parseFromSlice(std.json.Value, self.allocator, data, .{}) catch continue;
                defer parsed.deinit();

                if (parsed.value.object.get("choices")) |choices| {
                    if (choices.array.items.len > 0) {
                        const choice = choices.array.items[0];
                        if (choice.object.get("delta")) |delta| {
                            if (delta.object.get("content")) |content| {
                                callback(content.string);
                            }
                        }
                    }
                }
            }
        }
    }
};
