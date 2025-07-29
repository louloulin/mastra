const std = @import("std");
const http = @import("../core/http.zig");
const HttpClient = http.HttpClient;
const Header = http.Header;

/// Ollama 错误类型
pub const OllamaError = error{
    RequestFailed,
    ResponseParseError,
    OutOfMemory,
    InvalidResponse,
    NetworkError,
    UnexpectedWriteFailure,
    InvalidContentLength,
    UnsupportedTransferEncoding,
    NotWriteable,
    MessageTooLong,
    MessageNotCompleted,
    HttpRequestFailed,
    ConnectionFailed,
    Timeout,
    InvalidUrl,
    TlsInitializationFailed,
    CertificateVerificationFailed,
    UnsupportedUriScheme,
    UriMissingHost,
    UnknownHostName,
    TemporaryNameServerFailure,
    NameServerFailure,
    AddressFamilyNotSupported,
    UnexpectedConnectFailure,
    TlsFailure,
    TlsAlert,
    ConnectionTimedOut,
    ConnectionRefused,
    NetworkUnreachable,
    HostUnreachable,
    SocketNotConnected,
    SystemResources,
    OperationAborted,
    BrokenPipe,
    ConnectionResetByPeer,
    BlockingOperationWouldBlock,
    FileDescriptorNotASocket,
    NetworkSubsystemFailed,
    ProtocolFailure,
    ProtocolNotSupported,
    FileNotFound,
    AccessDenied,
    PipeBusy,
    NameTooLong,
    InvalidUtf8,
    BadPathName,
    SymLinkLoop,
    ProcessFdQuotaExceeded,
    SystemFdQuotaExceeded,
    NoDevice,
    PathAlreadyExists,
    DeviceBusy,
    FileTooBig,
    NoSpaceLeft,
    NotDir,
    IsDir,
    WouldBlock,
    InputOutput,
    InvalidArgument,
    NotOpenForReading,
    NotOpenForWriting,
    Unseekable,
    EndOfStream,
    StreamTooLong,
    LockViolation,
    FileBusy,
    Unexpected,
    ResponseError,
    TimeoutError,
};

/// Ollama API 消息结构
pub const OllamaMessage = struct {
    role: []const u8,
    content: []const u8,
    images: ?[][]const u8 = null, // 支持多模态
    
    const Self = @This();
    
    pub fn init(role: []const u8, content: []const u8) Self {
        return Self{
            .role = role,
            .content = content,
        };
    }
    
    pub fn initWithImages(role: []const u8, content: []const u8, images: [][]const u8) Self {
        return Self{
            .role = role,
            .content = content,
            .images = images,
        };
    }
};

/// Ollama API 请求结构
pub const OllamaRequest = struct {
    model: []const u8,
    prompt: ?[]const u8 = null,
    messages: ?[]OllamaMessage = null,
    format: ?[]const u8 = null, // "json" for JSON response
    options: ?OllamaOptions = null,
    system: ?[]const u8 = null,
    template: ?[]const u8 = null,
    context: ?[]i32 = null,
    stream: bool = false,
    raw: bool = false,
    keep_alive: ?[]const u8 = null,
    
    const Self = @This();
    
    pub fn init(model: []const u8) Self {
        return Self{
            .model = model,
        };
    }
    
    pub fn setPrompt(self: *Self, prompt: []const u8) void {
        self.prompt = prompt;
    }
    
    pub fn setMessages(self: *Self, messages: []OllamaMessage) void {
        self.messages = messages;
    }
    
    pub fn setFormat(self: *Self, format: []const u8) void {
        self.format = format;
    }
    
    pub fn setSystem(self: *Self, system: []const u8) void {
        self.system = system;
    }
    
    pub fn setOptions(self: *Self, options: OllamaOptions) void {
        self.options = options;
    }
    
    pub fn enableStream(self: *Self) void {
        self.stream = true;
    }
    
    pub fn enableRaw(self: *Self) void {
        self.raw = true;
    }
    
    pub fn setKeepAlive(self: *Self, duration: []const u8) void {
        self.keep_alive = duration;
    }
};

/// Ollama 选项结构
pub const OllamaOptions = struct {
    temperature: ?f32 = null,
    top_k: ?u32 = null,
    top_p: ?f32 = null,
    repeat_last_n: ?u32 = null,
    repeat_penalty: ?f32 = null,
    presence_penalty: ?f32 = null,
    frequency_penalty: ?f32 = null,
    mirostat: ?u32 = null,
    mirostat_eta: ?f32 = null,
    mirostat_tau: ?f32 = null,
    num_ctx: ?u32 = null,
    num_gqa: ?u32 = null,
    num_gpu: ?u32 = null,
    num_thread: ?u32 = null,
    num_predict: ?u32 = null,
    tfs_z: ?f32 = null,
    typical_p: ?f32 = null,
    seed: ?i32 = null,
    stop: ?[][]const u8 = null,
    
    const Self = @This();
    
    pub fn init() Self {
        return Self{};
    }
    
    pub fn setTemperature(self: *Self, temperature: f32) void {
        self.temperature = temperature;
    }
    
    pub fn setTopK(self: *Self, top_k: u32) void {
        self.top_k = top_k;
    }
    
    pub fn setTopP(self: *Self, top_p: f32) void {
        self.top_p = top_p;
    }
    
    pub fn setNumPredict(self: *Self, num_predict: u32) void {
        self.num_predict = num_predict;
    }
    
    pub fn setStop(self: *Self, stop: [][]const u8) void {
        self.stop = stop;
    }
};

/// Ollama API 响应结构
pub const OllamaResponse = struct {
    allocator: std.mem.Allocator,
    model: []const u8,
    created_at: []const u8,
    response: []const u8,
    done: bool,
    context: ?[]i32 = null,
    total_duration: ?u64 = null,
    load_duration: ?u64 = null,
    prompt_eval_count: ?u32 = null,
    prompt_eval_duration: ?u64 = null,
    eval_count: ?u32 = null,
    eval_duration: ?u64 = null,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, model: []const u8, created_at: []const u8, response: []const u8, done: bool) !Self {
        const model_copy = try allocator.dupe(u8, model);
        const created_at_copy = try allocator.dupe(u8, created_at);
        const response_copy = try allocator.dupe(u8, response);
        
        return Self{
            .allocator = allocator,
            .model = model_copy,
            .created_at = created_at_copy,
            .response = response_copy,
            .done = done,
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.model);
        self.allocator.free(self.created_at);
        self.allocator.free(self.response);
        
        if (self.context) |ctx| {
            self.allocator.free(ctx);
        }
    }
    
    pub fn setContext(self: *Self, context: []i32) !void {
        self.context = try self.allocator.dupe(i32, context);
    }
    
    pub fn setTimings(self: *Self, total_duration: u64, load_duration: u64, prompt_eval_count: u32, prompt_eval_duration: u64, eval_count: u32, eval_duration: u64) void {
        self.total_duration = total_duration;
        self.load_duration = load_duration;
        self.prompt_eval_count = prompt_eval_count;
        self.prompt_eval_duration = prompt_eval_duration;
        self.eval_count = eval_count;
        self.eval_duration = eval_duration;
    }
    
    pub fn getTokensPerSecond(self: *const Self) ?f32 {
        if (self.eval_count != null and self.eval_duration != null) {
            const tokens = @as(f32, @floatFromInt(self.eval_count.?));
            const duration_seconds = @as(f32, @floatFromInt(self.eval_duration.?)) / 1_000_000_000.0;
            return tokens / duration_seconds;
        }
        return null;
    }
};

/// Ollama 聊天响应结构
pub const OllamaChatResponse = struct {
    allocator: std.mem.Allocator,
    model: []const u8,
    created_at: []const u8,
    message: OllamaMessage,
    done: bool,
    total_duration: ?u64 = null,
    load_duration: ?u64 = null,
    prompt_eval_count: ?u32 = null,
    prompt_eval_duration: ?u64 = null,
    eval_count: ?u32 = null,
    eval_duration: ?u64 = null,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, model: []const u8, created_at: []const u8, message: OllamaMessage, done: bool) !Self {
        const model_copy = try allocator.dupe(u8, model);
        const created_at_copy = try allocator.dupe(u8, created_at);
        
        return Self{
            .allocator = allocator,
            .model = model_copy,
            .created_at = created_at_copy,
            .message = message,
            .done = done,
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.model);
        self.allocator.free(self.created_at);
    }
};

/// Ollama 模型信息
pub const OllamaModel = struct {
    name: []const u8,
    modified_at: []const u8,
    size: u64,
    digest: []const u8,
    details: ?OllamaModelDetails = null,
    
    const Self = @This();
    
    pub const OllamaModelDetails = struct {
        format: []const u8,
        family: []const u8,
        families: ?[][]const u8 = null,
        parameter_size: []const u8,
        quantization_level: []const u8,
    };
};

/// Ollama 客户端
pub const OllamaClient = struct {
    allocator: std.mem.Allocator,
    http_client: *HttpClient,
    base_url: []const u8,
    
    const Self = @This();
    const DEFAULT_BASE_URL = "http://localhost:11434";
    
    pub fn init(allocator: std.mem.Allocator, http_client: *HttpClient, base_url: ?[]const u8) Self {
        return Self{
            .allocator = allocator,
            .http_client = http_client,
            .base_url = base_url orelse DEFAULT_BASE_URL,
        };
    }
    
    /// 生成文本
    pub fn generate(self: *Self, request: OllamaRequest) !OllamaResponse {
        // 构建请求URL
        const url = try std.fmt.allocPrint(self.allocator, "{s}/api/generate", .{self.base_url});
        defer self.allocator.free(url);
        
        // 构建请求体
        const request_body = try self.buildGenerateRequestBody(request);
        defer self.allocator.free(request_body);
        
        // 构建请求头
        const headers = [_]http.Header{
            http.Header{ .name = "Content-Type", .value = "application/json" },
        };
        
        // 发送HTTP请求
        var response = try self.http_client.post(url, &headers, request_body);
        defer response.deinit();
        
        // 解析响应
        return try self.parseGenerateResponse(response.body);
    }
    
    /// 聊天
    pub fn chat(self: *Self, request: OllamaRequest) OllamaError!OllamaChatResponse {
        // 构建请求URL
        const url = try std.fmt.allocPrint(self.allocator, "{s}/api/chat", .{self.base_url});
        defer self.allocator.free(url);
        
        // 构建请求体
        const request_body = try self.buildChatRequestBody(request);
        defer self.allocator.free(request_body);
        
        // 构建请求头
        const headers = [_]http.Header{
            .{ .name = "Content-Type", .value = "application/json" },
        };
        
        // 发送HTTP请求
        var response = try self.http_client.post(url, &headers, request_body);
        defer response.deinit();
        
        // 解析响应
        return try self.parseChatResponse(response.body);
    }
    
    /// 获取模型列表
    pub fn listModels(self: *Self) ![]OllamaModel {
        // 构建请求URL
        const url = try std.fmt.allocPrint(self.allocator, "{s}/api/tags", .{self.base_url});
        defer self.allocator.free(url);
        
        // 发送HTTP请求
        var response = try self.http_client.get(url, &[_]http.Header{});
        defer response.deinit();
        
        // 解析响应
        return try self.parseModelsResponse(response.body);
    }
    
    /// 显示模型信息
    pub fn showModel(self: *Self, model_name: []const u8) !OllamaModel {
        // 构建请求URL
        const url = try std.fmt.allocPrint(self.allocator, "{s}/api/show", .{self.base_url});
        defer self.allocator.free(url);
        
        // 构建请求体
        const request_body = try self.buildShowModelRequestBody(model_name);
        defer self.allocator.free(request_body);
        
        // 构建请求头
        const headers = [_]http.Header{
            .{ .name = "Content-Type", .value = "application/json" },
        };
        
        // 发送HTTP请求
        var response = try self.http_client.post(url, &headers, request_body);
        defer response.deinit();
        
        // 解析响应
        return try self.parseShowModelResponse(response.body);
    }
    
    /// 拉取模型
    pub fn pullModel(self: *Self, model_name: []const u8) !void {
        // 构建请求URL
        const url = try std.fmt.allocPrint(self.allocator, "{s}/api/pull", .{self.base_url});
        defer self.allocator.free(url);
        
        // 构建请求体
        const request_body = try self.buildPullModelRequestBody(model_name);
        defer self.allocator.free(request_body);
        
        // 构建请求头
        const headers = [_]http.Header{
            .{ .name = "Content-Type", .value = "application/json" },
        };
        
        // 发送HTTP请求
        var response = try self.http_client.post(url, &headers, request_body);
        defer response.deinit();
        
        // 这里可以解析拉取进度，简化处理
        std.log.info("Model pull initiated for: {s}", .{model_name});
    }
    
    /// 删除模型
    pub fn deleteModel(self: *Self, model_name: []const u8) !void {
        // 构建请求URL
        const url = try std.fmt.allocPrint(self.allocator, "{s}/api/delete", .{self.base_url});
        defer self.allocator.free(url);
        
        // 构建请求体
        const request_body = try self.buildDeleteModelRequestBody(model_name);
        defer self.allocator.free(request_body);
        
        // 构建请求头
        const headers = [_]http.Header{
            .{ .name = "Content-Type", .value = "application/json" },
        };
        
        // 发送HTTP请求
        var response = try self.http_client.request(.{
            .method = .DELETE,
            .url = url,
            .headers = &headers,
            .body = request_body,
        });
        defer response.deinit();
        
        std.log.info("Model deleted: {s}", .{model_name});
    }
    
    /// 生成嵌入
    pub fn embeddings(self: *Self, model: []const u8, prompt: []const u8) ![]f32 {
        // 构建请求URL
        const url = try std.fmt.allocPrint(self.allocator, "{s}/api/embeddings", .{self.base_url});
        defer self.allocator.free(url);
        
        // 构建请求体
        const request_body = try self.buildEmbeddingsRequestBody(model, prompt);
        defer self.allocator.free(request_body);
        
        // 构建请求头
        const headers = [_]http.Header{
            .{ .name = "Content-Type", .value = "application/json" },
        };
        
        // 发送HTTP请求
        var response = try self.http_client.post(url, &headers, request_body);
        defer response.deinit();
        
        // 解析响应
        return try self.parseEmbeddingsResponse(response.body);
    }
    
    /// 构建生成请求体
    fn buildGenerateRequestBody(self: *Self, request: OllamaRequest) ![]u8 {
        var json_obj = std.json.ObjectMap.init(self.allocator);
        defer json_obj.deinit();
        
        // 基本参数
        try json_obj.put("model", std.json.Value{ .string = request.model });
        
        if (request.prompt) |prompt| {
            try json_obj.put("prompt", std.json.Value{ .string = prompt });
        }
        
        if (request.format) |format| {
            try json_obj.put("format", std.json.Value{ .string = format });
        }
        
        if (request.system) |system| {
            try json_obj.put("system", std.json.Value{ .string = system });
        }
        
        if (request.template) |template| {
            try json_obj.put("template", std.json.Value{ .string = template });
        }
        
        if (request.stream) {
            try json_obj.put("stream", std.json.Value{ .bool = true });
        }
        
        if (request.raw) {
            try json_obj.put("raw", std.json.Value{ .bool = true });
        }
        
        if (request.keep_alive) |keep_alive| {
            try json_obj.put("keep_alive", std.json.Value{ .string = keep_alive });
        }
        
        // 选项
        if (request.options) |options| {
            var options_obj = std.json.ObjectMap.init(self.allocator);
            defer options_obj.deinit();
            
            if (options.temperature) |temp| {
                try options_obj.put("temperature", std.json.Value{ .float = temp });
            }
            
            if (options.top_k) |top_k| {
                try options_obj.put("top_k", std.json.Value{ .integer = @intCast(top_k) });
            }
            
            if (options.top_p) |top_p| {
                try options_obj.put("top_p", std.json.Value{ .float = top_p });
            }
            
            if (options.num_predict) |num_predict| {
                try options_obj.put("num_predict", std.json.Value{ .integer = @intCast(num_predict) });
            }
            
            try json_obj.put("options", std.json.Value{ .object = options_obj });
        }
        
        const json_value = std.json.Value{ .object = json_obj };
        return try std.json.stringifyAlloc(self.allocator, json_value, .{});
    }
    
    /// 构建聊天请求体
    fn buildChatRequestBody(self: *Self, request: OllamaRequest) ![]u8 {
        var json_obj = std.json.ObjectMap.init(self.allocator);
        defer json_obj.deinit();
        
        // 基本参数
        try json_obj.put("model", std.json.Value{ .string = request.model });
        
        // 消息
        if (request.messages) |messages| {
            var messages_array = std.json.Array.init(self.allocator);
            defer messages_array.deinit();
            
            for (messages) |msg| {
                var msg_obj = std.json.ObjectMap.init(self.allocator);
                defer msg_obj.deinit();
                
                try msg_obj.put("role", std.json.Value{ .string = msg.role });
                try msg_obj.put("content", std.json.Value{ .string = msg.content });
                
                if (msg.images) |images| {
                    var images_array = std.json.Array.init(self.allocator);
                    defer images_array.deinit();
                    
                    for (images) |image| {
                        try images_array.append(std.json.Value{ .string = image });
                    }
                    
                    try msg_obj.put("images", std.json.Value{ .array = images_array });
                }
                
                try messages_array.append(std.json.Value{ .object = msg_obj });
            }
            
            try json_obj.put("messages", std.json.Value{ .array = messages_array });
        }
        
        if (request.stream) {
            try json_obj.put("stream", std.json.Value{ .bool = true });
        }
        
        // 选项
        if (request.options) |options| {
            var options_obj = std.json.ObjectMap.init(self.allocator);
            defer options_obj.deinit();
            
            if (options.temperature) |temp| {
                try options_obj.put("temperature", std.json.Value{ .float = temp });
            }
            
            if (options.top_k) |top_k| {
                try options_obj.put("top_k", std.json.Value{ .integer = @intCast(top_k) });
            }
            
            if (options.top_p) |top_p| {
                try options_obj.put("top_p", std.json.Value{ .float = top_p });
            }
            
            try json_obj.put("options", std.json.Value{ .object = options_obj });
        }
        
        const json_value = std.json.Value{ .object = json_obj };
        return try std.json.stringifyAlloc(self.allocator, json_value, .{});
    }
    
    /// 构建显示模型请求体
    fn buildShowModelRequestBody(self: *Self, model_name: []const u8) ![]u8 {
        var json_obj = std.json.ObjectMap.init(self.allocator);
        defer json_obj.deinit();
        
        try json_obj.put("name", std.json.Value{ .string = model_name });
        
        const json_value = std.json.Value{ .object = json_obj };
        return try std.json.stringifyAlloc(self.allocator, json_value, .{});
    }
    
    /// 构建拉取模型请求体
    fn buildPullModelRequestBody(self: *Self, model_name: []const u8) ![]u8 {
        var json_obj = std.json.ObjectMap.init(self.allocator);
        defer json_obj.deinit();
        
        try json_obj.put("name", std.json.Value{ .string = model_name });
        
        const json_value = std.json.Value{ .object = json_obj };
        return try std.json.stringifyAlloc(self.allocator, json_value, .{});
    }
    
    /// 构建删除模型请求体
    fn buildDeleteModelRequestBody(self: *Self, model_name: []const u8) ![]u8 {
        var json_obj = std.json.ObjectMap.init(self.allocator);
        defer json_obj.deinit();
        
        try json_obj.put("name", std.json.Value{ .string = model_name });
        
        const json_value = std.json.Value{ .object = json_obj };
        return try std.json.stringifyAlloc(self.allocator, json_value, .{});
    }
    
    /// 构建嵌入请求体
    fn buildEmbeddingsRequestBody(self: *Self, model: []const u8, prompt: []const u8) ![]u8 {
        var json_obj = std.json.ObjectMap.init(self.allocator);
        defer json_obj.deinit();
        
        try json_obj.put("model", std.json.Value{ .string = model });
        try json_obj.put("prompt", std.json.Value{ .string = prompt });
        
        const json_value = std.json.Value{ .object = json_obj };
        return try std.json.stringifyAlloc(self.allocator, json_value, .{});
    }
    
    /// 解析生成响应
    fn parseGenerateResponse(self: *Self, response_body: []const u8) OllamaError!OllamaResponse {
        // 简化的JSON解析
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, response_body, .{}) catch {
            return OllamaError.ResponseParseError;
        };
        defer parsed.deinit();
        
        const root = parsed.value;
        
        // 提取基本信息
        const model = if (root.object.get("model")) |val| val.string else "unknown";
        const created_at = if (root.object.get("created_at")) |val| val.string else "";
        const response = if (root.object.get("response")) |val| val.string else "";
        const done = if (root.object.get("done")) |val| val.bool else false;
        
        var result = try OllamaResponse.init(self.allocator, model, created_at, response, done);
        
        // 提取性能统计
        if (root.object.get("total_duration")) |val| {
            result.total_duration = @as(u64, @intCast(val.integer));
        }
        
        if (root.object.get("load_duration")) |val| {
            result.load_duration = @as(u64, @intCast(val.integer));
        }
        
        if (root.object.get("prompt_eval_count")) |val| {
            result.prompt_eval_count = @as(u32, @intCast(val.integer));
        }
        
        if (root.object.get("prompt_eval_duration")) |val| {
            result.prompt_eval_duration = @as(u64, @intCast(val.integer));
        }
        
        if (root.object.get("eval_count")) |val| {
            result.eval_count = @as(u32, @intCast(val.integer));
        }
        
        if (root.object.get("eval_duration")) |val| {
            result.eval_duration = @as(u64, @intCast(val.integer));
        }
        
        return result;
    }
    
    /// 解析聊天响应
    fn parseChatResponse(self: *Self, response_body: []const u8) OllamaError!OllamaChatResponse {
        // 简化的JSON解析
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, response_body, .{}) catch {
            return OllamaError.ResponseParseError;
        };
        defer parsed.deinit();
        
        const root = parsed.value;
        
        // 提取基本信息
        const model = if (root.object.get("model")) |val| val.string else "unknown";
        const created_at = if (root.object.get("created_at")) |val| val.string else "";
        const done = if (root.object.get("done")) |val| val.bool else false;
        
        // 提取消息
        var message = OllamaMessage.init("assistant", "");
        if (root.object.get("message")) |msg_val| {
            if (msg_val.object.get("role")) |role_val| {
                message.role = role_val.string;
            }
            if (msg_val.object.get("content")) |content_val| {
                message.content = content_val.string;
            }
        }
        
        var result = try OllamaChatResponse.init(self.allocator, model, created_at, message, done);
        
        // 提取性能统计
        if (root.object.get("total_duration")) |val| {
            result.total_duration = @as(u64, @intCast(val.integer));
        }
        
        if (root.object.get("eval_count")) |val| {
            result.eval_count = @as(u32, @intCast(val.integer));
        }
        
        if (root.object.get("eval_duration")) |val| {
            result.eval_duration = @as(u64, @intCast(val.integer));
        }
        
        return result;
    }
    
    /// 解析模型列表响应
    fn parseModelsResponse(self: *Self, response_body: []const u8) ![]OllamaModel {
        // 简化的JSON解析
        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, response_body, .{});
        defer parsed.deinit();
        
        const root = parsed.value;
        
        var models = std.ArrayList(OllamaModel).init(self.allocator);
        
        if (root.object.get("models")) |models_val| {
            for (models_val.array.items) |model_val| {
                const name = if (model_val.object.get("name")) |val| val.string else "unknown";
                const modified_at = if (model_val.object.get("modified_at")) |val| val.string else "";
                const size = if (model_val.object.get("size")) |val| @as(u64, @intCast(val.integer)) else 0;
                const digest = if (model_val.object.get("digest")) |val| val.string else "";
                
                const model = OllamaModel{
                    .name = name,
                    .modified_at = modified_at,
                    .size = size,
                    .digest = digest,
                };
                
                try models.append(model);
            }
        }
        
        return try models.toOwnedSlice();
    }
    
    /// 解析显示模型响应
    fn parseShowModelResponse(self: *Self, response_body: []const u8) !OllamaModel {
        // 简化的JSON解析
        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, response_body, .{});
        defer parsed.deinit();
        
        const root = parsed.value;
        
        const name = if (root.object.get("name")) |val| val.string else "unknown";
        const modified_at = if (root.object.get("modified_at")) |val| val.string else "";
        const size = if (root.object.get("size")) |val| @as(u64, @intCast(val.integer)) else 0;
        const digest = if (root.object.get("digest")) |val| val.string else "";
        
        return OllamaModel{
            .name = name,
            .modified_at = modified_at,
            .size = size,
            .digest = digest,
        };
    }
    
    /// 解析嵌入响应
    fn parseEmbeddingsResponse(self: *Self, response_body: []const u8) ![]f32 {
        // 简化的JSON解析
        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, response_body, .{});
        defer parsed.deinit();
        
        const root = parsed.value;
        
        var embedding_list = std.ArrayList(f32).init(self.allocator);
        
        if (root.object.get("embedding")) |embedding_val| {
            for (embedding_val.array.items) |val| {
                try embedding_list.append(@as(f32, @floatCast(val.float)));
            }
        }
        
        return try embedding_list.toOwnedSlice();
    }
};