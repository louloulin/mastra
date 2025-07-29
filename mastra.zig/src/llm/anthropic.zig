//! Anthropic Claude API 集成
//!
//! 支持：
//! - Messages API
//! - 流式响应
//! - 工具调用
//! - 错误处理和重试

const std = @import("std");
const HttpClient = @import("../core/http.zig").HttpClient;
const Header = @import("../core/http.zig").Header;
const Response = @import("../core/http.zig").Response;
const Message = @import("../agent/agent.zig").Message;

/// Anthropic API 错误
pub const AnthropicError = error{
    ApiKeyMissing,
    HttpClientMissing,
    RequestFailed,
    ResponseParseError,
    ApiError,
    RateLimitExceeded,
    InvalidRequest,
    AuthenticationError,
    NoContentInResponse,
    OutOfMemory,
};

/// Anthropic 消息结构
pub const AnthropicMessage = struct {
    role: []const u8,
    content: []const u8,
};

/// Anthropic 工具定义
pub const AnthropicTool = struct {
    name: []const u8,
    description: []const u8,
    input_schema: std.json.Value,
};

/// Anthropic 请求结构
pub const AnthropicRequest = struct {
    model: []const u8,
    max_tokens: u32,
    messages: []AnthropicMessage,
    system: ?[]const u8 = null,
    temperature: ?f32 = null,
    top_p: ?f32 = null,
    top_k: ?u32 = null,
    tools: ?[]AnthropicTool = null,
    tool_choice: ?std.json.Value = null,
    stream: bool = false,
    stop_sequences: ?[][]const u8 = null,
    metadata: ?std.json.Value = null,
};

/// Anthropic 响应结构
pub const AnthropicResponse = struct {
    id: []const u8,
    type: []const u8,
    role: []const u8,
    content: []Content,
    model: []const u8,
    stop_reason: ?[]const u8 = null,
    stop_sequence: ?[]const u8 = null,
    usage: Usage,

    pub const Content = struct {
        type: []const u8,
        text: ?[]const u8 = null,
        tool_use: ?ToolUse = null,
    };

    pub const ToolUse = struct {
        id: []const u8,
        name: []const u8,
        input: std.json.Value,
    };

    pub const Usage = struct {
        input_tokens: u32,
        output_tokens: u32,
    };
};

/// Anthropic 错误响应
pub const AnthropicErrorResponse = struct {
    type: []const u8,
    @"error": ErrorDetail,

    pub const ErrorDetail = struct {
        type: []const u8,
        message: []const u8,
    };
};

/// Anthropic 客户端
pub const AnthropicClient = struct {
    allocator: std.mem.Allocator,
    api_key: []const u8,
    base_url: []const u8,
    http_client: *HttpClient,
    anthropic_version: []const u8,

    const Self = @This();

    /// 初始化 Anthropic 客户端
    pub fn init(
        allocator: std.mem.Allocator,
        api_key: []const u8,
        http_client: *HttpClient,
        base_url: ?[]const u8,
    ) Self {
        return Self{
            .allocator = allocator,
            .api_key = api_key,
            .base_url = base_url orelse "https://api.anthropic.com",
            .http_client = http_client,
            .anthropic_version = "2023-06-01",
        };
    }

    /// 设置 Anthropic API 版本
    pub fn setVersion(self: *Self, version: []const u8) void {
        self.anthropic_version = version;
    }

    /// 转换消息格式
    pub fn convertMessages(self: *Self, input_messages: []const Message) ![]AnthropicMessage {
        var anthropic_messages = try self.allocator.alloc(AnthropicMessage, input_messages.len);
        
        for (input_messages, 0..) |msg, i| {
            anthropic_messages[i] = AnthropicMessage{
                .role = try self.allocator.dupe(u8, msg.role),
                .content = try self.allocator.dupe(u8, msg.content),
            };
        }
        
        return anthropic_messages;
    }

    /// 释放消息内存
    pub fn freeMessages(self: *Self, anthropic_messages: []AnthropicMessage) void {
        for (anthropic_messages) |msg| {
            self.allocator.free(msg.role);
            self.allocator.free(msg.content);
        }
        self.allocator.free(anthropic_messages);
    }

    /// 发送消息请求
    pub fn messages(self: *Self, request: AnthropicRequest) AnthropicError!AnthropicResponse {
        // 序列化请求
        const request_json = try std.json.stringifyAlloc(self.allocator, request, .{});
        defer self.allocator.free(request_json);

        // 准备请求头
        var headers = std.ArrayList(Header).init(self.allocator);
        defer headers.deinit();

        try headers.append(.{ .name = "x-api-key", .value = self.api_key });
        try headers.append(.{ .name = "Content-Type", .value = "application/json" });
        try headers.append(.{ .name = "anthropic-version", .value = self.anthropic_version });

        // 构建 URL
        const url = try std.fmt.allocPrint(self.allocator, "{s}/v1/messages", .{self.base_url});
        defer self.allocator.free(url);

        // 发送请求
        var response = self.http_client.post(url, headers.items, request_json) catch |err| {
            std.log.err("Anthropic API request failed: {}", .{err});
            return AnthropicError.RequestFailed;
        };
        defer response.deinit();

        // 检查响应状态
        if (!response.isSuccess()) {
            return self.handleErrorResponse(&response);
        }

        // 解析响应
        const parsed = std.json.parseFromSlice(AnthropicResponse, self.allocator, response.body, .{}) catch |err| {
            std.log.err("Failed to parse Anthropic response: {}", .{err});
            return AnthropicError.ResponseParseError;
        };
        defer parsed.deinit();

        // 验证响应
        if (parsed.value.content.len == 0) {
            return AnthropicError.NoContentInResponse;
        }

        // 深拷贝响应数据
        return try self.copyResponse(parsed.value);
    }

    /// 流式消息请求
    pub fn streamMessages(
        self: *Self,
        allocator: std.mem.Allocator,
        request: AnthropicRequest,
        callback: *const fn (chunk: []const u8) void,
    ) AnthropicError!void {
        // 修改请求以启用流式响应
        var stream_request = request;
        stream_request.stream = true;

        // 序列化请求
        const request_json = try std.json.stringifyAlloc(allocator, stream_request, .{});
        defer allocator.free(request_json);

        // 准备请求头
        var headers = std.ArrayList(Header).init(allocator);
        defer headers.deinit();

        try headers.append(.{ .name = "x-api-key", .value = self.api_key });
        try headers.append(.{ .name = "Content-Type", .value = "application/json" });
        try headers.append(.{ .name = "anthropic-version", .value = self.anthropic_version });
        try headers.append(.{ .name = "Accept", .value = "text/event-stream" });

        // 构建 URL
        const url = try std.fmt.allocPrint(allocator, "{s}/v1/messages", .{self.base_url});
        defer allocator.free(url);

        // 发送流式请求
        try self.http_client.postStream(url, headers.items, request_json, callback);
    }

    /// 处理错误响应
    fn handleErrorResponse(self: *Self, response: *const Response) AnthropicError {
        _ = self;
        
        return switch (response.status_code) {
            401 => AnthropicError.AuthenticationError,
            429 => AnthropicError.RateLimitExceeded,
            400 => AnthropicError.InvalidRequest,
            else => AnthropicError.ApiError,
        };
    }

    /// 深拷贝响应数据
    fn copyResponse(self: *Self, response: AnthropicResponse) !AnthropicResponse {
        var copied_response = AnthropicResponse{
            .id = try self.allocator.dupe(u8, response.id),
            .type = try self.allocator.dupe(u8, response.type),
            .role = try self.allocator.dupe(u8, response.role),
            .content = try self.allocator.alloc(AnthropicResponse.Content, response.content.len),
            .model = try self.allocator.dupe(u8, response.model),
            .stop_reason = if (response.stop_reason) |reason| try self.allocator.dupe(u8, reason) else null,
            .stop_sequence = if (response.stop_sequence) |seq| try self.allocator.dupe(u8, seq) else null,
            .usage = response.usage,
        };

        // 拷贝内容数组
        for (response.content, 0..) |content, i| {
            copied_response.content[i] = AnthropicResponse.Content{
                .type = try self.allocator.dupe(u8, content.type),
                .text = if (content.text) |text| try self.allocator.dupe(u8, text) else null,
                .tool_use = content.tool_use, // TODO: 深拷贝工具使用数据
            };
        }

        return copied_response;
    }

    /// 释放响应内存
    pub fn freeResponse(self: *Self, response: *AnthropicResponse) void {
        self.allocator.free(response.id);
        self.allocator.free(response.type);
        self.allocator.free(response.role);
        self.allocator.free(response.model);
        
        if (response.stop_reason) |reason| {
            self.allocator.free(reason);
        }
        
        if (response.stop_sequence) |seq| {
            self.allocator.free(seq);
        }

        for (response.content) |content| {
            self.allocator.free(content.type);
            if (content.text) |text| {
                self.allocator.free(text);
            }
        }
        
        self.allocator.free(response.content);
    }

    /// 释放深拷贝的响应内存
    pub fn deinitCopy(self: *Self, response: *AnthropicResponse) void {
        self.freeResponse(response);
    }
};