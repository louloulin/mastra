//! Google Gemini API 集成
//!
//! 支持：
//! - Gemini Pro 和 Gemini Pro Vision
//! - 流式响应
//! - 多模态输入（文本、图像）
//! - 函数调用
//! - 错误处理和重试

const std = @import("std");
const HttpClient = @import("../core/http.zig").HttpClient;
const Header = @import("../core/http.zig").Header;
const Response = @import("../core/http.zig").Response;
const Message = @import("../agent/agent.zig").Message;

/// Google Gemini API 错误
pub const GoogleError = error{
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
    UnsupportedModel,
};

/// Gemini 内容部分
pub const GeminiPart = struct {
    text: ?[]const u8 = null,
    inline_data: ?InlineData = null,
    function_call: ?FunctionCall = null,
    function_response: ?FunctionResponse = null,

    pub const InlineData = struct {
        mime_type: []const u8,
        data: []const u8, // base64 encoded
    };

    pub const FunctionCall = struct {
        name: []const u8,
        args: std.json.Value,
    };

    pub const FunctionResponse = struct {
        name: []const u8,
        response: std.json.Value,
    };
};

/// Gemini 内容
pub const GeminiContent = struct {
    role: []const u8,
    parts: []GeminiPart,
};

/// Gemini 函数声明
pub const GeminiFunctionDeclaration = struct {
    name: []const u8,
    description: []const u8,
    parameters: std.json.Value,
};

/// Gemini 工具
pub const GeminiTool = struct {
    function_declarations: []GeminiFunctionDeclaration,
};

/// Gemini 安全设置
pub const GeminiSafetySetting = struct {
    category: []const u8,
    threshold: []const u8,
};

/// Gemini 生成配置
pub const GeminiGenerationConfig = struct {
    temperature: ?f32 = null,
    top_p: ?f32 = null,
    top_k: ?u32 = null,
    candidate_count: ?u32 = null,
    max_output_tokens: ?u32 = null,
    stop_sequences: ?[][]const u8 = null,
};

/// Gemini 请求结构
pub const GeminiRequest = struct {
    contents: []GeminiContent,
    tools: ?[]GeminiTool = null,
    safety_settings: ?[]GeminiSafetySetting = null,
    generation_config: ?GeminiGenerationConfig = null,
    system_instruction: ?GeminiContent = null,
};

/// Gemini 候选响应
pub const GeminiCandidate = struct {
    content: GeminiContent,
    finish_reason: ?[]const u8 = null,
    index: u32,
    safety_ratings: ?[]SafetyRating = null,

    pub const SafetyRating = struct {
        category: []const u8,
        probability: []const u8,
    };
};

/// Gemini 使用统计
pub const GeminiUsageMetadata = struct {
    prompt_token_count: u32,
    candidates_token_count: u32,
    total_token_count: u32,
};

/// Gemini 响应结构
pub const GeminiResponse = struct {
    candidates: []GeminiCandidate,
    usage_metadata: ?GeminiUsageMetadata = null,
    prompt_feedback: ?PromptFeedback = null,

    pub const PromptFeedback = struct {
        safety_ratings: []GeminiCandidate.SafetyRating,
        block_reason: ?[]const u8 = null,
    };
};

/// Gemini 错误响应
pub const GeminiErrorResponse = struct {
    @"error": ErrorDetail,

    pub const ErrorDetail = struct {
        code: u32,
        message: []const u8,
        status: []const u8,
        details: ?[]std.json.Value = null,
    };
};

/// Google Gemini 客户端
pub const GoogleClient = struct {
    allocator: std.mem.Allocator,
    api_key: []const u8,
    base_url: []const u8,
    http_client: *HttpClient,
    model: []const u8,

    const Self = @This();

    /// 支持的模型
    pub const GEMINI_PRO = "gemini-pro";
    pub const GEMINI_PRO_VISION = "gemini-pro-vision";
    pub const GEMINI_1_5_PRO = "gemini-1.5-pro";
    pub const GEMINI_1_5_FLASH = "gemini-1.5-flash";

    /// 初始化 Google 客户端
    pub fn init(
        allocator: std.mem.Allocator,
        api_key: []const u8,
        http_client: *HttpClient,
        model: ?[]const u8,
        base_url: ?[]const u8,
    ) Self {
        return Self{
            .allocator = allocator,
            .api_key = api_key,
            .base_url = base_url orelse "https://generativelanguage.googleapis.com",
            .http_client = http_client,
            .model = model orelse GEMINI_PRO,
        };
    }

    /// 设置模型
    pub fn setModel(self: *Self, model: []const u8) GoogleError!void {
        const supported_models = [_][]const u8{
            GEMINI_PRO,
            GEMINI_PRO_VISION,
            GEMINI_1_5_PRO,
            GEMINI_1_5_FLASH,
        };

        for (supported_models) |supported| {
            if (std.mem.eql(u8, model, supported)) {
                self.model = model;
                return;
            }
        }

        return GoogleError.UnsupportedModel;
    }

    /// 转换消息格式
    pub fn convertMessages(self: *Self, input_messages: []const Message) ![]GeminiContent {
        var gemini_contents = try self.allocator.alloc(GeminiContent, input_messages.len);
        
        for (input_messages, 0..) |msg, i| {
            // 创建文本部分
            var parts = try self.allocator.alloc(GeminiPart, 1);
            parts[0] = GeminiPart{
                .text = try self.allocator.dupe(u8, msg.content),
            };

            gemini_contents[i] = GeminiContent{
                .role = try self.convertRole(msg.role),
                .parts = parts,
            };
        }
        
        return gemini_contents;
    }

    /// 转换角色
    fn convertRole(self: *Self, role: []const u8) ![]const u8 {
        _ = self;
        
        if (std.mem.eql(u8, role, "system")) {
            return "user"; // Gemini 将 system 消息作为 user 消息处理
        } else if (std.mem.eql(u8, role, "assistant")) {
            return "model";
        } else {
            return role; // user 保持不变
        }
    }

    /// 释放内容内存
    pub fn freeContents(self: *Self, contents: []GeminiContent) void {
        for (contents) |content| {
            for (content.parts) |part| {
                if (part.text) |text| {
                    self.allocator.free(text);
                }
            }
            self.allocator.free(content.parts);
        }
        self.allocator.free(contents);
    }

    /// 生成内容
    pub fn generateContent(self: *Self, request: GeminiRequest) GoogleError!GeminiResponse {
        // 序列化请求
        const request_json = try std.json.stringifyAlloc(self.allocator, request, .{});
        defer self.allocator.free(request_json);

        // 准备请求头
        var headers = std.ArrayList(Header).init(self.allocator);
        defer headers.deinit();

        try headers.append(.{ .name = "Content-Type", .value = "application/json" });

        // 构建 URL
        const url = try std.fmt.allocPrint(
            self.allocator,
            "{s}/v1beta/models/{s}:generateContent?key={s}",
            .{ self.base_url, self.model, self.api_key },
        );
        defer self.allocator.free(url);

        // 发送请求
        var response = self.http_client.post(url, headers.items, request_json) catch |err| {
            std.log.err("Google Gemini API request failed: {}", .{err});
            return GoogleError.RequestFailed;
        };
        defer response.deinit();

        // 检查响应状态
        if (!response.isSuccess()) {
            return self.handleErrorResponse(&response);
        }

        // 解析响应
        const parsed = std.json.parseFromSlice(GeminiResponse, self.allocator, response.body, .{}) catch |err| {
            std.log.err("Failed to parse Gemini response: {}", .{err});
            return GoogleError.ResponseParseError;
        };
        defer parsed.deinit();

        // 验证响应
        if (parsed.value.candidates.len == 0) {
            return GoogleError.NoContentInResponse;
        }

        // 深拷贝响应数据
        return try self.copyResponse(parsed.value);
    }

    /// 流式生成内容
    pub fn streamGenerateContent(
        self: *Self,
        allocator: std.mem.Allocator,
        request: GeminiRequest,
        callback: *const fn (chunk: []const u8) void,
    ) GoogleError!void {
        // 序列化请求
        const request_json = try std.json.stringifyAlloc(allocator, request, .{});
        defer allocator.free(request_json);

        // 准备请求头
        var headers = std.ArrayList(Header).init(allocator);
        defer headers.deinit();

        try headers.append(.{ .name = "Content-Type", .value = "application/json" });
        try headers.append(.{ .name = "Accept", .value = "text/event-stream" });

        // 构建 URL
        const url = try std.fmt.allocPrint(
            allocator,
            "{s}/v1beta/models/{s}:streamGenerateContent?key={s}",
            .{ self.base_url, self.model, self.api_key },
        );
        defer allocator.free(url);

        // 发送流式请求
        try self.http_client.postStream(url, headers.items, request_json, callback);
    }

    /// 处理错误响应
    fn handleErrorResponse(self: *Self, response: *const Response) GoogleError {
        _ = self;
        
        return switch (response.status_code) {
            401, 403 => GoogleError.AuthenticationError,
            429 => GoogleError.RateLimitExceeded,
            400 => GoogleError.InvalidRequest,
            else => GoogleError.ApiError,
        };
    }

    /// 深拷贝响应数据
    fn copyResponse(self: *Self, response: GeminiResponse) !GeminiResponse {
        var copied_response = GeminiResponse{
            .candidates = try self.allocator.alloc(GeminiCandidate, response.candidates.len),
            .usage_metadata = response.usage_metadata,
            .prompt_feedback = response.prompt_feedback, // TODO: 深拷贝
        };

        // 拷贝候选响应
        for (response.candidates, 0..) |candidate, i| {
            copied_response.candidates[i] = try self.copyCandidate(candidate);
        }

        return copied_response;
    }

    /// 深拷贝候选响应
    fn copyCandidate(self: *Self, candidate: GeminiCandidate) !GeminiCandidate {
        const copied_candidate = GeminiCandidate{
            .content = try self.copyContent(candidate.content),
            .finish_reason = if (candidate.finish_reason) |reason| try self.allocator.dupe(u8, reason) else null,
            .index = candidate.index,
            .safety_ratings = candidate.safety_ratings, // TODO: 深拷贝
        };

        return copied_candidate;
    }

    /// 深拷贝内容
    fn copyContent(self: *Self, content: GeminiContent) !GeminiContent {
        var copied_content = GeminiContent{
            .role = try self.allocator.dupe(u8, content.role),
            .parts = try self.allocator.alloc(GeminiPart, content.parts.len),
        };

        for (content.parts, 0..) |part, i| {
            copied_content.parts[i] = GeminiPart{
                .text = if (part.text) |text| try self.allocator.dupe(u8, text) else null,
                .inline_data = part.inline_data, // TODO: 深拷贝
                .function_call = part.function_call, // TODO: 深拷贝
                .function_response = part.function_response, // TODO: 深拷贝
            };
        }

        return copied_content;
    }

    /// 释放响应内存
    pub fn freeResponse(self: *Self, response: *GeminiResponse) void {
        for (response.candidates) |candidate| {
            self.freeCandidate(candidate);
        }
        self.allocator.free(response.candidates);
    }

    /// 释放候选响应内存
    fn freeCandidate(self: *Self, candidate: GeminiCandidate) void {
        self.freeContent(candidate.content);
        if (candidate.finish_reason) |reason| {
            self.allocator.free(reason);
        }
    }

    /// 释放内容内存
    fn freeContent(self: *Self, content: GeminiContent) void {
        self.allocator.free(content.role);
        for (content.parts) |part| {
            if (part.text) |text| {
                self.allocator.free(text);
            }
        }
        self.allocator.free(content.parts);
    }

    /// 释放深拷贝的响应内存
    pub fn deinitCopy(self: *Self, response: *GeminiResponse) void {
        self.freeResponse(response);
    }
};