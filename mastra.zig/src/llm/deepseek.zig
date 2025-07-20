//! DeepSeek API 客户端
//!
//! DeepSeek是一个高性能的AI模型提供商，提供与OpenAI兼容的API接口
//! 支持：
//! - Chat Completions API
//! - 流式响应
//! - 多种模型 (deepseek-chat, deepseek-coder等)

const std = @import("std");
const http = @import("../core/http.zig");

/// DeepSeek API 错误
pub const DeepSeekError = error{
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

/// DeepSeek 消息结构
pub const DeepSeekMessage = struct {
    role: []const u8, // "system", "user", "assistant"
    content: []const u8,
};

/// DeepSeek 请求结构
pub const DeepSeekRequest = struct {
    model: []const u8, // "deepseek-chat", "deepseek-coder"
    messages: []const DeepSeekMessage,
    temperature: f32 = 0.7,
    max_tokens: u32 = 100,
    stream: bool = false,
};

/// DeepSeek 响应中的选择
pub const DeepSeekChoice = struct {
    index: u32,
    message: DeepSeekMessage,
    finish_reason: ?[]const u8,
    logprobs: ?std.json.Value = null,
};

/// DeepSeek 使用统计
pub const DeepSeekUsage = struct {
    prompt_tokens: u32,
    completion_tokens: u32,
    total_tokens: u32,
    prompt_tokens_details: ?std.json.Value = null,
    prompt_cache_hit_tokens: ?u32 = null,
    prompt_cache_miss_tokens: ?u32 = null,
};

/// DeepSeek API 响应
pub const DeepSeekResponse = struct {
    id: []const u8,
    object: []const u8,
    created: u64,
    model: []const u8,
    choices: []DeepSeekChoice,
    usage: DeepSeekUsage,
    system_fingerprint: ?[]const u8 = null,

    /// 释放深拷贝的DeepSeekResponse内存
    pub fn deinitCopy(self: *DeepSeekResponse, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.object);
        allocator.free(self.model);

        for (self.choices) |*choice| {
            allocator.free(choice.message.role);
            allocator.free(choice.message.content);
            if (choice.finish_reason) |fr| {
                allocator.free(fr);
            }
        }
        allocator.free(self.choices);

        if (self.system_fingerprint) |sf| {
            allocator.free(sf);
        }
    }
};

/// DeepSeek API 客户端
pub const DeepSeekClient = struct {
    allocator: std.mem.Allocator,
    api_key: []const u8,
    base_url: []const u8,
    http_client: *http.HttpClient,

    const Self = @This();

    /// 初始化DeepSeek客户端
    pub fn init(
        allocator: std.mem.Allocator,
        api_key: []const u8,
        http_client: *http.HttpClient,
        base_url: ?[]const u8,
    ) Self {
        return Self{
            .allocator = allocator,
            .api_key = api_key,
            .base_url = base_url orelse "https://api.deepseek.com/v1",
            .http_client = http_client,
        };
    }

    /// 聊天完成请求
    pub fn chatCompletion(self: *Self, request: DeepSeekRequest) DeepSeekError!DeepSeekResponse {
        // 手动构建JSON以确保格式正确
        var json_builder = std.ArrayList(u8).init(self.allocator);
        defer json_builder.deinit();

        try json_builder.appendSlice("{");
        try json_builder.appendSlice("\"model\":\"");
        try json_builder.appendSlice(request.model);
        try json_builder.appendSlice("\",\"messages\":[");

        for (request.messages, 0..) |msg, i| {
            if (i > 0) try json_builder.appendSlice(",");
            try json_builder.appendSlice("{\"role\":\"");
            try json_builder.appendSlice(msg.role);
            try json_builder.appendSlice("\",\"content\":\"");
            try json_builder.appendSlice(msg.content);
            try json_builder.appendSlice("\"}");
        }

        try json_builder.appendSlice("],");
        try json_builder.appendSlice("\"temperature\":");
        try std.fmt.format(json_builder.writer(), "{d:.1}", .{request.temperature});
        try json_builder.appendSlice(",\"max_tokens\":");
        try std.fmt.format(json_builder.writer(), "{d}", .{request.max_tokens});
        try json_builder.appendSlice(",\"stream\":");
        try json_builder.appendSlice(if (request.stream) "true" else "false");
        try json_builder.appendSlice("}");

        const request_json = try self.allocator.dupe(u8, json_builder.items);
        defer self.allocator.free(request_json);

        // 调试输出
        std.debug.print("DeepSeek API 请求JSON: {s}\n", .{request_json});

        // 准备头部
        const auth_header = std.fmt.allocPrint(self.allocator, "Bearer {s}", .{self.api_key}) catch {
            return DeepSeekError.OutOfMemory;
        };
        defer self.allocator.free(auth_header);

        var headers = std.ArrayList(http.Header).init(self.allocator);
        defer headers.deinit();

        headers.append(.{ .name = "authorization", .value = auth_header }) catch {
            return DeepSeekError.OutOfMemory;
        };
        headers.append(.{ .name = "content-type", .value = "application/json" }) catch {
            return DeepSeekError.OutOfMemory;
        };
        headers.append(.{ .name = "user-agent", .value = "curl/8.4.0" }) catch {
            return DeepSeekError.OutOfMemory;
        };
        headers.append(.{ .name = "accept", .value = "*/*" }) catch {
            return DeepSeekError.OutOfMemory;
        };

        // 构建URL
        const url = std.fmt.allocPrint(self.allocator, "{s}/chat/completions", .{self.base_url}) catch {
            return DeepSeekError.OutOfMemory;
        };
        defer self.allocator.free(url);

        // 发送请求
        var response = self.http_client.post(url, headers.items, request_json) catch |err| {
            std.debug.print("DeepSeek API HTTP POST failed: {}\n", .{err});
            std.debug.print("URL: {s}\n", .{url});
            std.debug.print("Request body: {s}\n", .{request_json});
            return switch (err) {
                else => DeepSeekError.RequestFailed,
            };
        };
        // 注意：暂时不调用response.deinit()，避免双重释放问题
        // TODO: 需要仔细检查HTTP响应的生命周期管理
        defer response.deinit();

        // 检查HTTP状态码
        if (!response.isSuccess()) {
            std.debug.print("DeepSeek: HTTP状态码错误: {d}\n", .{response.status_code});
            return switch (response.status_code) {
                401 => DeepSeekError.AuthenticationError,
                429 => DeepSeekError.RateLimitExceeded,
                400 => DeepSeekError.InvalidRequest,
                else => DeepSeekError.ApiError,
            };
        }

        // 调试：打印响应信息
        std.debug.print("DeepSeek API 响应状态: {d}\n", .{response.status_code});
        std.debug.print("DeepSeek API 响应体长度: {d}\n", .{response.body.len});
        if (response.body.len > 0) {
            const preview_len = @min(200, response.body.len);
            std.debug.print("DeepSeek API 响应体前{d}字符: {s}\n", .{ preview_len, response.body[0..preview_len] });
        }

        // 使用临时Arena分配器解析JSON，避免内存泄漏
        var json_arena = std.heap.ArenaAllocator.init(self.allocator);
        defer json_arena.deinit(); // 这会释放所有JSON解析器分配的内存

        const parsed = std.json.parseFromSlice(DeepSeekResponse, json_arena.allocator(), response.body, .{}) catch |err| {
            std.debug.print("DeepSeek API响应解析失败: {}\n响应内容: {s}\n", .{ err, response.body });
            return DeepSeekError.ResponseParseError;
        };
        // 注意：parsed.deinit()会被json_arena.deinit()自动处理

        // 调试：检查解析后的内容
        if (parsed.value.choices.len > 0) {
            const content = parsed.value.choices[0].message.content;
            std.debug.print("解析后的内容长度: {d}\n", .{content.len});
            std.debug.print("解析后的内容前10字节: ", .{});
            const debug_len = @min(10, content.len);
            for (content[0..debug_len]) |byte| {
                std.debug.print("{d} ", .{byte});
            }
            std.debug.print("\n解析后的内容: {s}\n", .{content});
        }

        // 立即创建一个深拷贝，避免内存被破坏
        var result = parsed.value;

        // 复制所有字符串字段
        result.id = try self.allocator.dupe(u8, parsed.value.id);
        result.object = try self.allocator.dupe(u8, parsed.value.object);
        result.model = try self.allocator.dupe(u8, parsed.value.model);
        result.system_fingerprint = if (parsed.value.system_fingerprint) |sf| try self.allocator.dupe(u8, sf) else null;

        // 复制choices数组
        result.choices = try self.allocator.alloc(DeepSeekChoice, parsed.value.choices.len);
        for (parsed.value.choices, 0..) |choice, i| {
            result.choices[i] = DeepSeekChoice{
                .index = choice.index,
                .message = DeepSeekMessage{
                    .role = try self.allocator.dupe(u8, choice.message.role),
                    .content = try self.allocator.dupe(u8, choice.message.content),
                },
                .logprobs = choice.logprobs,
                .finish_reason = if (choice.finish_reason) |fr| try self.allocator.dupe(u8, fr) else null,
            };
        }

        return result;
    }

    /// 流式聊天完成请求
    pub fn streamCompletion(
        self: *Self,
        allocator: std.mem.Allocator,
        request: DeepSeekRequest,
        callback: *const fn (chunk: []const u8) void,
    ) DeepSeekError!void {
        // 序列化请求（启用流式）
        var stream_request = request;
        stream_request.stream = true;

        const request_json = std.json.stringifyAlloc(allocator, stream_request, .{}) catch {
            return DeepSeekError.OutOfMemory;
        };
        defer allocator.free(request_json);

        // 准备头部
        const auth_header = std.fmt.allocPrint(allocator, "Bearer {s}", .{self.api_key}) catch {
            return DeepSeekError.OutOfMemory;
        };
        defer allocator.free(auth_header);

        const headers = [_]http.Header{
            .{ .name = "Authorization", .value = auth_header },
            .{ .name = "Content-Type", .value = "application/json" },
            .{ .name = "Accept", .value = "text/event-stream" },
        };

        // 构建完整的URL
        const url = std.fmt.allocPrint(allocator, "{s}/chat/completions", .{self.base_url}) catch {
            return DeepSeekError.OutOfMemory;
        };
        defer allocator.free(url);

        // 发送流式请求
        var response = self.http_client.request(.{
            .method = .POST,
            .url = url,
            .headers = &headers,
            .body = request_json,
        }) catch |err| {
            return switch (err) {
                else => DeepSeekError.RequestFailed,
            };
        };
        defer response.deinit();

        if (!response.isSuccess()) {
            return DeepSeekError.ApiError;
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

    /// 释放响应资源
    pub fn freeResponse(self: *Self, response: *DeepSeekResponse) void {
        _ = self;
        _ = response;
        // DeepSeek响应由JSON解析器管理，不需要手动释放
    }
};

// 测试
test "DeepSeek Client initialization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var http_client = http.HttpClient.init(allocator, null);
    defer http_client.deinit();

    const client = DeepSeekClient.init(
        allocator,
        "test-api-key",
        &http_client,
        null,
    );

    try std.testing.expectEqualStrings("test-api-key", client.api_key);
    try std.testing.expectEqualStrings("https://api.deepseek.com/v1", client.base_url);
}

test "DeepSeek Request serialization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const messages = [_]DeepSeekMessage{
        .{
            .role = "user",
            .content = "Hello, DeepSeek!",
        },
    };

    const request = DeepSeekRequest{
        .model = "deepseek-chat",
        .messages = &messages,
        .temperature = 0.7,
        .max_tokens = 1000,
    };

    const json = try std.json.stringifyAlloc(allocator, request, .{});
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "deepseek-chat") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "Hello, DeepSeek!") != null);
}
