const std = @import("std");
const HttpClient = @import("../core/http.zig").HttpClient;
const Header = @import("../core/http.zig").Header;

/// Cohere 错误类型
pub const CohereError = error{
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

/// Cohere API 消息结构
pub const CohereMessage = struct {
    role: []const u8,
    message: []const u8,
    
    const Self = @This();
    
    pub fn init(role: []const u8, message: []const u8) Self {
        return Self{
            .role = role,
            .message = message,
        };
    }
};

/// Cohere API 请求结构
pub const CohereRequest = struct {
    message: []const u8,
    model: []const u8 = "command-r-plus",
    chat_history: ?[]CohereMessage = null,
    temperature: ?f32 = null,
    max_tokens: ?u32 = null,
    k: ?u32 = null, // top-k
    p: ?f32 = null, // top-p
    frequency_penalty: ?f32 = null,
    presence_penalty: ?f32 = null,
    stop_sequences: ?[][]const u8 = null,
    stream: bool = false,
    
    const Self = @This();
    
    pub fn init(message: []const u8, model: []const u8) Self {
        return Self{
            .message = message,
            .model = model,
        };
    }
    
    pub fn setTemperature(self: *Self, temperature: f32) void {
        self.temperature = temperature;
    }
    
    pub fn setMaxTokens(self: *Self, max_tokens: u32) void {
        self.max_tokens = max_tokens;
    }
    
    pub fn setTopK(self: *Self, k: u32) void {
        self.k = k;
    }
    
    pub fn setTopP(self: *Self, p: f32) void {
        self.p = p;
    }
    
    pub fn setChatHistory(self: *Self, history: []CohereMessage) void {
        self.chat_history = history;
    }
    
    pub fn setStopSequences(self: *Self, sequences: [][]const u8) void {
        self.stop_sequences = sequences;
    }
    
    pub fn enableStream(self: *Self) void {
        self.stream = true;
    }
    
    pub fn setMessages(self: *CohereRequest, messages: []CohereMessage) void {
        self.chat_history = messages;
    }

    pub fn setFrequencyPenalty(self: *CohereRequest, penalty: f32) void {
        self.frequency_penalty = penalty;
    }

    pub fn setPresencePenalty(self: *CohereRequest, penalty: f32) void {
        self.presence_penalty = penalty;
    }
};

/// Cohere API 响应中的使用统计
pub const CohereUsage = struct {
    input_tokens: u32,
    output_tokens: u32,
    
    const Self = @This();
    
    pub fn getTotalTokens(self: *const Self) u32 {
        return self.input_tokens + self.output_tokens;
    }
};

/// Cohere API 响应结构
pub const CohereResponse = struct {
    allocator: std.mem.Allocator,
    text: []const u8,
    generation_id: ?[]const u8 = null,
    finish_reason: ?[]const u8 = null,
    meta: ?CohereUsage = null,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, text: []const u8) !Self {
        const text_copy = try allocator.dupe(u8, text);
        return Self{
            .allocator = allocator,
            .text = text_copy,
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.text);
        
        if (self.generation_id) |id| {
            self.allocator.free(id);
        }
        
        if (self.finish_reason) |reason| {
            self.allocator.free(reason);
        }
    }
    
    pub fn setGenerationId(self: *Self, id: []const u8) !void {
        self.generation_id = try self.allocator.dupe(u8, id);
    }
    
    pub fn setFinishReason(self: *Self, reason: []const u8) !void {
        self.finish_reason = try self.allocator.dupe(u8, reason);
    }
    
    pub fn setUsage(self: *Self, usage: CohereUsage) void {
        self.meta = usage;
    }
};

/// Cohere 客户端
pub const CohereClient = struct {
    allocator: std.mem.Allocator,
    api_key: []const u8,
    http_client: *HttpClient,
    base_url: []const u8,
    
    const Self = @This();
    const DEFAULT_BASE_URL = "https://api.cohere.ai";
    
    pub fn init(allocator: std.mem.Allocator, api_key: []const u8, http_client: *HttpClient, base_url: ?[]const u8) Self {
        return Self{
            .allocator = allocator,
            .api_key = api_key,
            .http_client = http_client,
            .base_url = base_url orelse DEFAULT_BASE_URL,
        };
    }
    
    /// 发送聊天请求
    pub fn chat(self: *Self, request: CohereRequest) CohereError!CohereResponse {
        // 构建请求URL
        const url = try std.fmt.allocPrint(self.allocator, "{s}/v1/chat", .{self.base_url});
        defer self.allocator.free(url);
        
        // 构建请求体
        const request_body = try self.buildRequestBody(request);
        defer self.allocator.free(request_body);
        
        // 构建请求头
        var headers = std.ArrayList(Header).init(self.allocator);
        defer headers.deinit();
        
        try headers.append(Header{ .name = "Content-Type", .value = "application/json" });
        
        const auth_header = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{self.api_key});
        defer self.allocator.free(auth_header);
        try headers.append(Header{ .name = "Authorization", .value = auth_header });
        
        // 发送HTTP请求
        var response = try self.http_client.post(url, headers.items, request_body);
        defer response.deinit();
        
        // 解析响应
        return try self.parseResponse(response.body);
    }
    
    /// 生成文本（非聊天模式）
    pub fn generate(self: *Self, prompt: []const u8, model: []const u8, options: ?CohereRequest) !CohereResponse {
        // 构建请求URL
        const url = try std.fmt.allocPrint(self.allocator, "{s}/v1/generate", .{self.base_url});
        defer self.allocator.free(url);
        
        // 构建生成请求
        var generate_request = CohereRequest.init(prompt, model);
        if (options) |opts| {
            generate_request.temperature = opts.temperature;
            generate_request.max_tokens = opts.max_tokens;
            generate_request.k = opts.k;
            generate_request.p = opts.p;
            generate_request.frequency_penalty = opts.frequency_penalty;
            generate_request.presence_penalty = opts.presence_penalty;
            generate_request.stop_sequences = opts.stop_sequences;
        }
        
        // 构建请求体
        const request_body = try self.buildGenerateRequestBody(generate_request);
        defer self.allocator.free(request_body);
        
        // 构建请求头
        var headers = std.ArrayList(Header).init(self.allocator);
        defer headers.deinit();
        
        try headers.append(Header{ .name = "Content-Type", .value = "application/json" });
        
        const auth_header = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{self.api_key});
        defer self.allocator.free(auth_header);
        try headers.append(Header{ .name = "Authorization", .value = auth_header });
        
        // 发送HTTP请求
        var response = try self.http_client.post(url, headers.items, request_body);
        defer response.deinit();
        
        // 解析响应
        return try self.parseGenerateResponse(response.body);
    }
    
    /// 嵌入文本
    pub fn embed(self: *Self, texts: [][]const u8, model: []const u8) ![][]f32 {
        // 构建请求URL
        const url = try std.fmt.allocPrint(self.allocator, "{s}/v1/embed", .{self.base_url});
        defer self.allocator.free(url);
        
        // 构建嵌入请求体
        const request_body = try self.buildEmbedRequestBody(texts, model);
        defer self.allocator.free(request_body);
        
        // 构建请求头
        var headers = std.ArrayList(Header).init(self.allocator);
        defer headers.deinit();
        
        try headers.append(Header{ .name = "Content-Type", .value = "application/json" });
        
        const auth_header = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{self.api_key});
        defer self.allocator.free(auth_header);
        try headers.append(Header{ .name = "Authorization", .value = auth_header });
        
        // 发送HTTP请求
        var response = try self.http_client.post(url, headers.items, request_body);
        defer response.deinit();
        
        // 解析嵌入响应
        return try self.parseEmbedResponse(response.body);
    }
    
    /// 重新排序文档
    pub fn rerank(self: *Self, query: []const u8, documents: [][]const u8, model: []const u8, top_n: ?u32) ![]u32 {
        // 构建请求URL
        const url = try std.fmt.allocPrint(self.allocator, "{s}/v1/rerank", .{self.base_url});
        defer self.allocator.free(url);
        
        // 构建重排序请求体
        const request_body = try self.buildRerankRequestBody(query, documents, model, top_n);
        defer self.allocator.free(request_body);
        
        // 构建请求头
        var headers = std.ArrayList(Header).init(self.allocator);
        defer headers.deinit();
        
        try headers.append(Header{ .name = "Content-Type", .value = "application/json" });
        
        const auth_header = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{self.api_key});
        defer self.allocator.free(auth_header);
        try headers.append(Header{ .name = "Authorization", .value = auth_header });
        
        // 发送HTTP请求
        var response = try self.http_client.post(url, headers.items, request_body);
        defer response.deinit();
        
        // 解析重排序响应
        return try self.parseRerankResponse(response.body);
    }
    
    /// 构建聊天请求体
    fn buildRequestBody(self: *Self, request: CohereRequest) ![]u8 {
        var json_obj = std.json.ObjectMap.init(self.allocator);
        defer json_obj.deinit();
        
        // 基本参数
        try json_obj.put("message", std.json.Value{ .string = request.message });
        try json_obj.put("model", std.json.Value{ .string = request.model });
        
        // 可选参数
        if (request.temperature) |temp| {
            try json_obj.put("temperature", std.json.Value{ .float = temp });
        }
        
        if (request.max_tokens) |tokens| {
            try json_obj.put("max_tokens", std.json.Value{ .integer = @intCast(tokens) });
        }
        
        if (request.k) |k| {
            try json_obj.put("k", std.json.Value{ .integer = @intCast(k) });
        }
        
        if (request.p) |p| {
            try json_obj.put("p", std.json.Value{ .float = p });
        }
        
        if (request.frequency_penalty) |penalty| {
            try json_obj.put("frequency_penalty", std.json.Value{ .float = penalty });
        }
        
        if (request.presence_penalty) |penalty| {
            try json_obj.put("presence_penalty", std.json.Value{ .float = penalty });
        }
        
        if (request.stream) {
            try json_obj.put("stream", std.json.Value{ .bool = true });
        }
        
        // 聊天历史
        if (request.chat_history) |history| {
            var history_array = std.json.Array.init(self.allocator);
            defer history_array.deinit();
            
            for (history) |msg| {
                var msg_obj = std.json.ObjectMap.init(self.allocator);
                defer msg_obj.deinit();
                
                try msg_obj.put("role", std.json.Value{ .string = msg.role });
                try msg_obj.put("message", std.json.Value{ .string = msg.message });
                
                try history_array.append(std.json.Value{ .object = msg_obj });
            }
            
            try json_obj.put("chat_history", std.json.Value{ .array = history_array });
        }
        
        // 停止序列
        if (request.stop_sequences) |sequences| {
            var stop_array = std.json.Array.init(self.allocator);
            defer stop_array.deinit();
            
            for (sequences) |seq| {
                try stop_array.append(std.json.Value{ .string = seq });
            }
            
            try json_obj.put("stop_sequences", std.json.Value{ .array = stop_array });
        }
        
        const json_value = std.json.Value{ .object = json_obj };
        return try std.json.stringifyAlloc(self.allocator, json_value, .{});
    }
    
    /// 构建生成请求体
    fn buildGenerateRequestBody(self: *Self, request: CohereRequest) ![]u8 {
        var json_obj = std.json.ObjectMap.init(self.allocator);
        defer json_obj.deinit();
        
        // 基本参数
        try json_obj.put("prompt", std.json.Value{ .string = request.message });
        try json_obj.put("model", std.json.Value{ .string = request.model });
        
        // 可选参数
        if (request.temperature) |temp| {
            try json_obj.put("temperature", std.json.Value{ .float = temp });
        }
        
        if (request.max_tokens) |tokens| {
            try json_obj.put("max_tokens", std.json.Value{ .integer = @intCast(tokens) });
        }
        
        if (request.k) |k| {
            try json_obj.put("k", std.json.Value{ .integer = @intCast(k) });
        }
        
        if (request.p) |p| {
            try json_obj.put("p", std.json.Value{ .float = p });
        }
        
        const json_value = std.json.Value{ .object = json_obj };
        return try std.json.stringifyAlloc(self.allocator, json_value, .{});
    }
    
    /// 构建嵌入请求体
    fn buildEmbedRequestBody(self: *Self, texts: [][]const u8, model: []const u8) ![]u8 {
        var json_obj = std.json.ObjectMap.init(self.allocator);
        defer json_obj.deinit();
        
        // 文本数组
        var texts_array = std.json.Array.init(self.allocator);
        defer texts_array.deinit();
        
        for (texts) |text| {
            try texts_array.append(std.json.Value{ .string = text });
        }
        
        try json_obj.put("texts", std.json.Value{ .array = texts_array });
        try json_obj.put("model", std.json.Value{ .string = model });
        
        const json_value = std.json.Value{ .object = json_obj };
        return try std.json.stringifyAlloc(self.allocator, json_value, .{});
    }
    
    /// 构建重排序请求体
    fn buildRerankRequestBody(self: *Self, query: []const u8, documents: [][]const u8, model: []const u8, top_n: ?u32) ![]u8 {
        var json_obj = std.json.ObjectMap.init(self.allocator);
        defer json_obj.deinit();
        
        try json_obj.put("query", std.json.Value{ .string = query });
        try json_obj.put("model", std.json.Value{ .string = model });
        
        // 文档数组
        var docs_array = std.json.Array.init(self.allocator);
        defer docs_array.deinit();
        
        for (documents) |doc| {
            try docs_array.append(std.json.Value{ .string = doc });
        }
        
        try json_obj.put("documents", std.json.Value{ .array = docs_array });
        
        if (top_n) |n| {
            try json_obj.put("top_n", std.json.Value{ .integer = @intCast(n) });
        }
        
        const json_value = std.json.Value{ .object = json_obj };
        return try std.json.stringifyAlloc(self.allocator, json_value, .{});
    }
    
    /// 解析聊天响应
    fn parseResponse(self: *Self, response_body: []const u8) CohereError!CohereResponse {
        // 简化的JSON解析，实际实现需要更完整的错误处理
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, response_body, .{}) catch {
            return CohereError.ResponseParseError;
        };
        defer parsed.deinit();
        
        const root = parsed.value;
        
        // 提取文本内容
        var text: []const u8 = "";
        if (root.object.get("text")) |text_value| {
            text = text_value.string;
        }
        
        var result = try CohereResponse.init(self.allocator, text);
        
        // 提取生成ID
        if (root.object.get("generation_id")) |id_value| {
            try result.setGenerationId(id_value.string);
        }
        
        // 提取完成原因
        if (root.object.get("finish_reason")) |reason_value| {
            try result.setFinishReason(reason_value.string);
        }
        
        // 提取使用统计
        if (root.object.get("meta")) |meta_value| {
            if (meta_value.object.get("tokens")) |tokens_value| {
                const input_tokens = if (tokens_value.object.get("input_tokens")) |val| @as(u32, @intCast(val.integer)) else 0;
                const output_tokens = if (tokens_value.object.get("output_tokens")) |val| @as(u32, @intCast(val.integer)) else 0;
                
                result.setUsage(CohereUsage{
                    .input_tokens = input_tokens,
                    .output_tokens = output_tokens,
                });
            }
        }
        
        return result;
    }
    
    /// 解析生成响应
    fn parseGenerateResponse(self: *Self, response_body: []const u8) !CohereResponse {
        // 简化的JSON解析
        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, response_body, .{});
        defer parsed.deinit();
        
        const root = parsed.value;
        
        // 提取生成的文本
        var text: []const u8 = "";
        if (root.object.get("generations")) |generations| {
            if (generations.array.items.len > 0) {
                const first_gen = generations.array.items[0];
                if (first_gen.object.get("text")) |text_value| {
                    text = text_value.string;
                }
            }
        }
        
        return try CohereResponse.init(self.allocator, text);
    }
    
    /// 解析嵌入响应
    fn parseEmbedResponse(self: *Self, response_body: []const u8) ![][]f32 {
        // 简化的JSON解析
        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, response_body, .{});
        defer parsed.deinit();
        
        const root = parsed.value;
        
        var embeddings = std.ArrayList([]f32).init(self.allocator);
        
        if (root.object.get("embeddings")) |embeddings_value| {
            for (embeddings_value.array.items) |embedding| {
                var embedding_vec = std.ArrayList(f32).init(self.allocator);
                
                for (embedding.array.items) |val| {
                    try embedding_vec.append(@as(f32, @floatCast(val.float)));
                }
                
                try embeddings.append(try embedding_vec.toOwnedSlice());
            }
        }
        
        return try embeddings.toOwnedSlice();
    }
    
    /// 解析重排序响应
    fn parseRerankResponse(self: *Self, response_body: []const u8) ![]u32 {
        // 简化的JSON解析
        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, response_body, .{});
        defer parsed.deinit();
        
        const root = parsed.value;
        
        var indices = std.ArrayList(u32).init(self.allocator);
        
        if (root.object.get("results")) |results| {
            for (results.array.items) |result| {
                if (result.object.get("index")) |index_value| {
                    try indices.append(@as(u32, @intCast(index_value.integer)));
                }
            }
        }
        
        return try indices.toOwnedSlice();
    }
};