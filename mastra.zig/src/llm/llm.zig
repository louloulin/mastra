const std = @import("std");
const AgentResponse = @import("../agent/agent.zig").AgentResponse;
pub const Message = @import("../agent/agent.zig").Message;
const HttpClient = @import("../core/http.zig").HttpClient;
const Header = @import("../core/http.zig").Header;
pub const OpenAIClient = @import("openai.zig").OpenAIClient;
pub const OpenAIRequest = @import("openai.zig").OpenAIRequest;
pub const OpenAIResponse = @import("openai.zig").OpenAIResponse;
pub const OpenAIMessage = @import("openai.zig").OpenAIMessage;

pub const DeepSeekClient = @import("deepseek.zig").DeepSeekClient;
pub const DeepSeekRequest = @import("deepseek.zig").DeepSeekRequest;
pub const DeepSeekResponse = @import("deepseek.zig").DeepSeekResponse;
pub const DeepSeekMessage = @import("deepseek.zig").DeepSeekMessage;

/// LLM 提供商类型
pub const LLMProvider = enum {
    openai,
    anthropic,
    groq,
    ollama,
    deepseek,
    custom,

    pub fn fromString(str: []const u8) ?LLMProvider {
        if (std.mem.eql(u8, str, "openai")) return .openai;
        if (std.mem.eql(u8, str, "anthropic")) return .anthropic;
        if (std.mem.eql(u8, str, "groq")) return .groq;
        if (std.mem.eql(u8, str, "ollama")) return .ollama;
        if (std.mem.eql(u8, str, "deepseek")) return .deepseek;
        if (std.mem.eql(u8, str, "custom")) return .custom;
        return null;
    }

    pub fn toString(self: LLMProvider) []const u8 {
        return switch (self) {
            .openai => "openai",
            .anthropic => "anthropic",
            .groq => "groq",
            .ollama => "ollama",
            .deepseek => "deepseek",
            .custom => "custom",
        };
    }
};

/// LLM 配置
pub const LLMConfig = struct {
    provider: LLMProvider,
    model: []const u8,
    api_key: ?[]const u8 = null,
    base_url: ?[]const u8 = null,
    temperature: f32 = 0.7,
    max_tokens: ?u32 = null,
    top_p: ?f32 = null,
    frequency_penalty: ?f32 = null,
    presence_penalty: ?f32 = null,
    stop_sequences: ?[][]const u8 = null,
    user_id: ?[]const u8 = null,

    /// 验证配置
    pub fn validate(self: *const LLMConfig) !void {
        if (self.model.len == 0) {
            return error.InvalidModel;
        }

        // 检查需要 API 密钥的提供商
        switch (self.provider) {
            .openai, .anthropic, .groq, .deepseek => {
                if (self.api_key == null) {
                    return error.ApiKeyRequired;
                }
            },
            .ollama => {
                // Ollama 通常不需要 API 密钥
            },
            .custom => {
                // 自定义提供商的验证由用户负责
            },
        }

        // 验证参数范围
        if (self.temperature < 0.0 or self.temperature > 2.0) {
            return error.InvalidTemperature;
        }

        if (self.top_p) |top_p| {
            if (top_p < 0.0 or top_p > 1.0) {
                return error.InvalidTopP;
            }
        }

        if (self.frequency_penalty) |penalty| {
            if (penalty < -2.0 or penalty > 2.0) {
                return error.InvalidFrequencyPenalty;
            }
        }

        if (self.presence_penalty) |penalty| {
            if (penalty < -2.0 or penalty > 2.0) {
                return error.InvalidPresencePenalty;
            }
        }
    }

    /// 获取默认基础 URL
    pub fn getDefaultBaseUrl(self: *const LLMConfig) []const u8 {
        return switch (self.provider) {
            .openai => "https://api.openai.com/v1",
            .anthropic => "https://api.anthropic.com",
            .groq => "https://api.groq.com/openai/v1",
            .deepseek => "https://api.deepseek.com/v1",
            .ollama => "http://localhost:11434/v1",
            .custom => self.base_url orelse "",
        };
    }
};

/// LLM 错误类型
pub const LLMError = error{
    InvalidModel,
    ApiKeyRequired,
    InvalidTemperature,
    InvalidTopP,
    InvalidFrequencyPenalty,
    InvalidPresencePenalty,
    HttpClientNotSet,
    RequestFailed,
    ResponseParseError,
    ApiError,
    UnsupportedProvider,
    ConfigurationError,
    OutOfMemory,
    NoChoicesInResponse,
    HttpClientMissing,
    AuthenticationError,
    ApiKeyMissing,
    RateLimitExceeded,
    InvalidRequest,
};

/// LLM 使用统计
pub const LLMUsage = struct {
    prompt_tokens: u32,
    completion_tokens: u32,
    total_tokens: u32,

    pub fn init(prompt: u32, completion: u32) LLMUsage {
        return LLMUsage{
            .prompt_tokens = prompt,
            .completion_tokens = completion,
            .total_tokens = prompt + completion,
        };
    }
};

/// LLM 生成选项
pub const GenerateOptions = struct {
    temperature: ?f32 = null,
    max_tokens: ?u32 = null,
    top_p: ?f32 = null,
    frequency_penalty: ?f32 = null,
    presence_penalty: ?f32 = null,
    stop_sequences: ?[][]const u8 = null,
    stream: bool = false,
    user_id: ?[]const u8 = null,
};

/// LLM 生成结果
pub const GenerateResult = struct {
    content: []const u8,
    finish_reason: ?[]const u8,
    usage: ?LLMUsage,
    model: []const u8,
    created_at: i64,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, content: []const u8, model: []const u8) !GenerateResult {
        return GenerateResult{
            .content = try allocator.dupe(u8, content),
            .finish_reason = null,
            .usage = null,
            .model = try allocator.dupe(u8, model),
            .created_at = std.time.timestamp(),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *GenerateResult) void {
        self.allocator.free(self.content);
        self.allocator.free(self.model);
        if (self.finish_reason) |reason| {
            self.allocator.free(reason);
        }
    }
};

/// 统一的 LLM 接口
pub const LLM = struct {
    allocator: std.mem.Allocator,
    config: LLMConfig,
    http_client: ?*HttpClient,
    openai_client: ?OpenAIClient,
    deepseek_client: ?DeepSeekClient,

    const Self = @This();

    /// 初始化 LLM
    pub fn init(allocator: std.mem.Allocator, config: LLMConfig) !*LLM {
        // 验证配置
        try config.validate();

        const llm = try allocator.create(LLM);
        llm.* = LLM{
            .allocator = allocator,
            .config = config,
            .http_client = null,
            .openai_client = null,
            .deepseek_client = null,
        };
        return llm;
    }

    /// 清理 LLM
    pub fn deinit(self: *LLM) void {
        self.allocator.destroy(self);
    }

    /// 设置 HTTP 客户端
    pub fn setHttpClient(self: *LLM, client: *HttpClient) !void {
        self.http_client = client;

        // 根据提供商初始化相应的客户端
        switch (self.config.provider) {
            .openai, .groq => {
                if (self.config.api_key) |api_key| {
                    self.openai_client = OpenAIClient.init(
                        self.allocator,
                        api_key,
                        client,
                        self.config.base_url,
                    );
                }
            },
            .deepseek => {
                if (self.config.api_key) |api_key| {
                    self.deepseek_client = DeepSeekClient.init(
                        self.allocator,
                        api_key,
                        client,
                        self.config.base_url,
                    );
                }
            },
            else => {
                // 其他提供商暂时不需要特殊客户端
            },
        }
    }

    /// 生成文本
    pub fn generate(self: *LLM, messages: []const Message, options: ?GenerateOptions) LLMError!GenerateResult {
        if (self.http_client == null) {
            return LLMError.HttpClientNotSet;
        }

        return switch (self.config.provider) {
            .openai, .groq => self.generateOpenAI(messages, options),
            .anthropic => self.generateAnthropic(messages, options),
            .deepseek => self.generateDeepSeek(messages, options),
            .ollama => self.generateOllama(messages, options),
            .custom => self.generateCustom(messages, options),
        };
    }

    /// 流式生成文本
    pub fn generateStream(
        self: *LLM,
        messages: []const Message,
        options: ?GenerateOptions,
        callback: *const fn (chunk: []const u8) void,
    ) LLMError!void {
        if (self.http_client == null) {
            return LLMError.HttpClientNotSet;
        }

        return switch (self.config.provider) {
            .openai, .groq => self.generateStreamOpenAI(messages, options, callback),
            .anthropic => self.generateStreamAnthropic(messages, options, callback),
            .deepseek => self.generateStreamDeepSeek(messages, options, callback),
            .ollama => self.generateStreamOllama(messages, options, callback),
            .custom => self.generateStreamCustom(messages, options, callback),
        };
    }

    /// OpenAI/Groq API 生成实现
    fn generateOpenAI(self: *LLM, messages: []const Message, options: ?GenerateOptions) LLMError!GenerateResult {
        if (self.openai_client == null) {
            return LLMError.ConfigurationError;
        }

        const client = &self.openai_client.?;

        // 转换消息格式
        const openai_messages = try client.convertMessages(messages);
        defer client.freeMessages(openai_messages);

        // 构建请求
        const request = OpenAIRequest{
            .model = self.config.model,
            .messages = openai_messages,
            .temperature = if (options) |opts| opts.temperature else null orelse self.config.temperature,
            .max_tokens = if (options) |opts| opts.max_tokens else null orelse self.config.max_tokens,
            .top_p = if (options) |opts| opts.top_p else null orelse self.config.top_p,
            .frequency_penalty = if (options) |opts| opts.frequency_penalty else null orelse self.config.frequency_penalty,
            .presence_penalty = if (options) |opts| opts.presence_penalty else null orelse self.config.presence_penalty,
            .stop = if (options) |opts| opts.stop_sequences else null orelse self.config.stop_sequences,
            .user = if (options) |opts| opts.user_id else null orelse self.config.user_id,
            .stream = if (options) |opts| opts.stream else false,
        };

        // 发送请求
        var response = try client.chatCompletion(request);
        defer client.freeResponse(&response);

        // 转换为统一格式
        const choice = response.choices[0];
        var result = try GenerateResult.init(self.allocator, choice.message.content, response.model);

        if (choice.finish_reason) |reason| {
            result.finish_reason = try self.allocator.dupe(u8, reason);
        }

        if (response.usage) |usage| {
            result.usage = LLMUsage.init(usage.prompt_tokens, usage.completion_tokens);
        }

        result.created_at = @intCast(response.created);

        return result;
    }

    /// DeepSeek API 生成实现
    fn generateDeepSeek(self: *LLM, messages: []const Message, options: ?GenerateOptions) LLMError!GenerateResult {
        if (self.deepseek_client == null) {
            return LLMError.ConfigurationError;
        }

        const client = &self.deepseek_client.?;

        // 转换消息格式
        var deepseek_messages = std.ArrayList(DeepSeekMessage).init(self.allocator);
        defer deepseek_messages.deinit();

        for (messages) |msg| {
            try deepseek_messages.append(.{
                .role = msg.role,
                .content = msg.content,
            });
        }

        // 构建请求
        const request = DeepSeekRequest{
            .model = self.config.model,
            .messages = deepseek_messages.items,
            .temperature = if (options) |opts| opts.temperature else self.config.temperature,
            .max_tokens = if (options) |opts| opts.max_tokens else self.config.max_tokens,
            .stream = false,
        };

        // 发送请求
        const response = client.chatCompletion(request) catch |err| {
            return switch (err) {
                else => LLMError.RequestFailed,
            };
        };

        // 检查响应
        if (response.choices.len == 0) {
            return LLMError.NoChoicesInResponse;
        }

        const choice = response.choices[0];
        var result = try GenerateResult.init(self.allocator, choice.message.content, response.model);

        if (choice.finish_reason) |reason| {
            result.finish_reason = try self.allocator.dupe(u8, reason);
        }

        result.usage = LLMUsage.init(response.usage.prompt_tokens, response.usage.completion_tokens);
        result.created_at = @intCast(response.created);

        return result;
    }

    /// Anthropic Claude API 生成实现
    fn generateAnthropic(self: *LLM, messages: []const Message, options: ?GenerateOptions) LLMError!GenerateResult {
        _ = messages;
        _ = options;

        // TODO: 实现 Anthropic API 调用
        return GenerateResult.init(
            self.allocator,
            "Anthropic API not implemented yet",
            self.config.model,
        );
    }

    /// Ollama API 生成实现
    fn generateOllama(self: *LLM, messages: []const Message, options: ?GenerateOptions) LLMError!GenerateResult {
        _ = messages;
        _ = options;

        // TODO: 实现 Ollama API 调用
        return GenerateResult.init(
            self.allocator,
            "Ollama API not implemented yet",
            self.config.model,
        );
    }

    /// 自定义提供商生成实现
    fn generateCustom(self: *LLM, messages: []const Message, options: ?GenerateOptions) LLMError!GenerateResult {
        _ = messages;
        _ = options;

        // TODO: 实现自定义提供商支持
        return GenerateResult.init(
            self.allocator,
            "Custom provider not implemented yet",
            self.config.model,
        );
    }

    /// OpenAI/Groq 流式生成实现
    fn generateStreamOpenAI(
        self: *LLM,
        messages: []const Message,
        options: ?GenerateOptions,
        callback: *const fn (chunk: []const u8) void,
    ) LLMError!void {
        if (self.openai_client) |client| {
            // 构建OpenAI请求
            var openai_messages = std.ArrayList(OpenAIMessage).init(self.allocator);
            defer openai_messages.deinit();

            for (messages) |msg| {
                try openai_messages.append(.{
                    .role = msg.role,
                    .content = msg.content,
                });
            }

            const request = OpenAIRequest{
                .model = self.config.model,
                .messages = openai_messages.items,
                .temperature = if (options) |opts| opts.temperature else self.config.temperature,
                .max_tokens = if (options) |opts| opts.max_tokens else self.config.max_tokens,
                .stream = true, // 启用流式响应
            };

            try client.streamCompletion(self.allocator, request, callback);
        } else {
            return LLMError.HttpClientMissing;
        }
    }

    /// DeepSeek 流式生成实现
    fn generateStreamDeepSeek(
        self: *LLM,
        messages: []const Message,
        options: ?GenerateOptions,
        callback: *const fn (chunk: []const u8) void,
    ) LLMError!void {
        if (self.deepseek_client) |*client| {
            // 构建DeepSeek请求
            var deepseek_messages = std.ArrayList(DeepSeekMessage).init(self.allocator);
            defer deepseek_messages.deinit();

            for (messages) |msg| {
                try deepseek_messages.append(.{
                    .role = msg.role,
                    .content = msg.content,
                });
            }

            const request = DeepSeekRequest{
                .model = self.config.model,
                .messages = deepseek_messages.items,
                .temperature = if (options) |opts| opts.temperature else self.config.temperature,
                .max_tokens = if (options) |opts| opts.max_tokens else self.config.max_tokens,
                .stream = true, // 启用流式响应
            };

            try client.streamCompletion(self.allocator, request, callback);
        } else {
            return LLMError.HttpClientMissing;
        }
    }

    /// Anthropic 流式生成实现
    fn generateStreamAnthropic(
        self: *LLM,
        messages: []const Message,
        options: ?GenerateOptions,
        callback: *const fn (chunk: []const u8) void,
    ) LLMError!void {
        _ = self;
        _ = messages;
        _ = options;

        callback("Anthropic streaming not implemented yet");
    }

    /// Ollama 流式生成实现
    fn generateStreamOllama(
        self: *LLM,
        messages: []const Message,
        options: ?GenerateOptions,
        callback: *const fn (chunk: []const u8) void,
    ) LLMError!void {
        _ = self;
        _ = messages;
        _ = options;

        callback("Ollama streaming not implemented yet");
    }

    /// 自定义提供商流式生成实现
    fn generateStreamCustom(
        self: *LLM,
        messages: []const Message,
        options: ?GenerateOptions,
        callback: *const fn (chunk: []const u8) void,
    ) LLMError!void {
        _ = self;
        _ = messages;
        _ = options;

        callback("Custom provider streaming not implemented yet");
    }

    /// 获取提供商
    pub fn getProvider(self: *const LLM) LLMProvider {
        return self.config.provider;
    }

    /// 获取模型名称
    pub fn getModel(self: *const LLM) []const u8 {
        return self.config.model;
    }

    /// 获取配置
    pub fn getConfig(self: *const LLM) LLMConfig {
        return self.config;
    }

    /// 检查是否支持流式生成
    pub fn supportsStreaming(self: *const LLM) bool {
        return switch (self.config.provider) {
            .openai, .anthropic, .groq => true,
            .ollama => true,
            .custom => false, // 取决于具体实现
        };
    }

    /// 检查是否支持函数调用
    pub fn supportsFunctionCalling(self: *const LLM) bool {
        return switch (self.config.provider) {
            .openai, .groq => true,
            .anthropic => false, // Anthropic 使用不同的工具调用格式
            .ollama => false, // 取决于模型
            .custom => false, // 取决于具体实现
        };
    }

    /// 估算 token 数量（简单实现）
    pub fn estimateTokens(self: *const LLM, text: []const u8) u32 {
        _ = self;
        // 简单的 token 估算：大约 4 个字符 = 1 个 token
        return @intCast((text.len + 3) / 4);
    }
};
