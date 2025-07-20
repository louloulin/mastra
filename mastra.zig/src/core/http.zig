//! HTTP客户端模块 - 基于std.http.Client的HTTP客户端
//!
//! 支持：
//! - HTTP请求
//! - TLS 1.3支持
//! - 请求重试
//! - JSON处理

const std = @import("std");
const EventLoop = @import("event_loop.zig").EventLoop;

/// HTTP错误类型
pub const HttpError = error{
    InvalidUrl,
    RequestFailed,
    ResponseError,
    ConnectionFailed,
    TimeoutError,
    OutOfMemory,
    ConnectionResetByPeer,
    UnexpectedWriteFailure,
    InvalidContentLength,
    UnsupportedTransferEncoding,
    NotWriteable,
    MessageTooLong,
    MessageNotCompleted,
};

/// HTTP方法
pub const Method = enum {
    GET,
    POST,
    PUT,
    DELETE,
    PATCH,
    HEAD,
    OPTIONS,

    pub fn toString(self: Method) []const u8 {
        return switch (self) {
            .GET => "GET",
            .POST => "POST",
            .PUT => "PUT",
            .DELETE => "DELETE",
            .PATCH => "PATCH",
            .HEAD => "HEAD",
            .OPTIONS => "OPTIONS",
        };
    }
};

/// HTTP头部
pub const Header = struct {
    name: []const u8,
    value: []const u8,
};

/// HTTP请求配置
pub const RequestConfig = struct {
    method: Method = .GET,
    url: []const u8,
    headers: []const Header = &[_]Header{},
    body: ?[]const u8 = null,
    timeout_ms: u32 = 30000,
    retry_count: u32 = 0,
    retry_delay_ms: u32 = 1000,
};

/// HTTP响应
pub const Response = struct {
    status_code: u16,
    headers: std.StringHashMap([]const u8),
    body: []const u8,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, status_code: u16) Self {
        return Self{
            .status_code = status_code,
            .headers = std.StringHashMap([]const u8).init(allocator),
            .body = "",
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        var iterator = self.headers.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.headers.deinit();
        if (self.body.len > 0) {
            self.allocator.free(self.body);
        }
    }

    pub fn addHeader(self: *Self, name: []const u8, value: []const u8) !void {
        const name_copy = try self.allocator.dupe(u8, name);
        const value_copy = try self.allocator.dupe(u8, value);

        // 使用getOrPut来正确处理重复键的情况
        const result = try self.headers.getOrPut(name_copy);
        if (result.found_existing) {
            // 如果键已存在，释放旧的键值对内存
            self.allocator.free(result.key_ptr.*);
            self.allocator.free(result.value_ptr.*);
            // 释放新分配的name_copy，因为我们要重用旧的键
            self.allocator.free(name_copy);
            // 重新分配键
            result.key_ptr.* = try self.allocator.dupe(u8, name);
        }
        result.value_ptr.* = value_copy;
    }

    pub fn setBody(self: *Self, body: []const u8) !void {
        if (self.body.len > 0) {
            self.allocator.free(self.body);
        }
        self.body = try self.allocator.dupe(u8, body);
    }

    pub fn getHeader(self: *const Self, name: []const u8) ?[]const u8 {
        return self.headers.get(name);
    }

    pub fn isSuccess(self: *const Self) bool {
        return self.status_code >= 200 and self.status_code < 300;
    }
};

/// 重试配置
pub const RetryConfig = struct {
    max_attempts: u32 = 3,
    initial_delay_ms: u64 = 100,
    max_delay_ms: u64 = 5000,
    backoff_multiplier: f32 = 2.0,
};

/// 超时配置
pub const TimeoutConfig = struct {
    connect_timeout_ms: u64 = 5000,
    request_timeout_ms: u64 = 30000,
    read_timeout_ms: u64 = 30000,
};

/// HTTP客户端
pub const HttpClient = struct {
    allocator: std.mem.Allocator,
    client: std.http.Client,
    event_loop: ?*EventLoop,
    retry_config: RetryConfig,
    timeout_config: TimeoutConfig,

    const Self = @This();

    /// 初始化HTTP客户端
    pub fn init(allocator: std.mem.Allocator, event_loop: ?*EventLoop) Self {
        return Self{
            .allocator = allocator,
            .client = std.http.Client{ .allocator = allocator },
            .event_loop = event_loop,
            .retry_config = RetryConfig{},
            .timeout_config = TimeoutConfig{},
        };
    }

    /// 初始化HTTP客户端（带配置）
    pub fn initWithConfig(allocator: std.mem.Allocator, event_loop: ?*EventLoop, retry_config: RetryConfig, timeout_config: TimeoutConfig) Self {
        return Self{
            .allocator = allocator,
            .client = std.http.Client{ .allocator = allocator },
            .event_loop = event_loop,
            .retry_config = retry_config,
            .timeout_config = timeout_config,
        };
    }

    /// 清理HTTP客户端
    pub fn deinit(self: *Self) void {
        self.client.deinit();
    }

    /// 发送HTTP请求
    pub fn request(self: *Self, config: RequestConfig) HttpError!Response {
        // 解析URL
        const uri = std.Uri.parse(config.url) catch {
            return HttpError.InvalidUrl;
        };

        // 准备头部
        var headers = std.ArrayList(std.http.Header).init(self.allocator);
        defer headers.deinit();

        for (config.headers) |header| {
            try headers.append(.{
                .name = header.name,
                .value = header.value,
            });
        }

        // 不手动设置Content-Length，让transfer_encoding自动处理

        // 创建请求
        const http_method = switch (config.method) {
            .GET => std.http.Method.GET,
            .POST => std.http.Method.POST,
            .PUT => std.http.Method.PUT,
            .DELETE => std.http.Method.DELETE,
            .PATCH => std.http.Method.PATCH,
            .HEAD => std.http.Method.HEAD,
            .OPTIONS => std.http.Method.OPTIONS,
        };

        // 分配足够大的头部缓冲区
        var header_buffer: [16384]u8 = undefined; // 16KB缓冲区

        var req = self.client.open(
            http_method,
            uri,
            .{
                .server_header_buffer = &header_buffer,
                .extra_headers = headers.items,
            },
        ) catch |err| {
            std.debug.print("HTTP client.open() failed: {}\n", .{err});
            return HttpError.RequestFailed;
        };
        defer req.deinit();

        // 设置请求体
        if (config.body) |body| {
            req.transfer_encoding = .{ .content_length = body.len };
            req.send() catch |err| {
                std.debug.print("HTTP req.send() with body failed: {}\n", .{err});
                return HttpError.RequestFailed;
            };
            req.writeAll(body) catch |err| {
                std.debug.print("HTTP req.writeAll() failed: {}\n", .{err});
                return HttpError.RequestFailed;
            };
        } else {
            req.send() catch |err| {
                std.debug.print("HTTP req.send() without body failed: {}\n", .{err});
                return HttpError.RequestFailed;
            };
        }

        req.finish() catch |err| {
            std.debug.print("HTTP req.finish() failed: {}\n", .{err});
            return HttpError.RequestFailed;
        };
        req.wait() catch |err| {
            std.debug.print("HTTP req.wait() failed: {}\n", .{err});
            return HttpError.RequestFailed;
        };

        // 读取响应
        const status_code = @intFromEnum(req.response.status);
        var response = Response.init(self.allocator, status_code);

        // 读取响应头
        var header_iter = req.response.iterateHeaders();
        while (header_iter.next()) |header| {
            try response.addHeader(header.name, header.value);
        }

        // 读取响应体
        var body_list = std.ArrayList(u8).init(self.allocator);
        defer body_list.deinit();

        req.reader().readAllArrayList(&body_list, 10 * 1024 * 1024) catch {
            return HttpError.ResponseError;
        }; // 10MB限制
        try response.setBody(body_list.items);

        return response;
    }

    /// 发送GET请求
    pub fn get(self: *Self, url: []const u8, headers: []const Header) HttpError!Response {
        return self.request(.{
            .method = .GET,
            .url = url,
            .headers = headers,
        });
    }

    /// 发送POST请求
    pub fn post(self: *Self, url: []const u8, headers: []const Header, body: []const u8) HttpError!Response {
        return self.request(.{
            .method = .POST,
            .url = url,
            .headers = headers,
            .body = body,
        });
    }

    /// 发送PUT请求
    pub fn put(self: *Self, url: []const u8, headers: []const Header, body: []const u8) HttpError!Response {
        return self.request(.{
            .method = .PUT,
            .url = url,
            .headers = headers,
            .body = body,
        });
    }

    /// 发送DELETE请求
    pub fn delete(self: *Self, url: []const u8, headers: []const Header) HttpError!Response {
        return self.request(.{
            .method = .DELETE,
            .url = url,
            .headers = headers,
        });
    }

    /// 带重试机制的HTTP请求
    pub fn requestWithRetry(self: *Self, config: RequestConfig) HttpError!Response {
        var attempts: u32 = 0;
        var delay_ms = self.retry_config.initial_delay_ms;

        while (attempts < self.retry_config.max_attempts) {
            const result = self.request(config);

            if (result) |*response| {
                // 检查是否需要重试（5xx错误或网络错误）
                if (response.status_code >= 500 and response.status_code < 600) {
                    response.deinit();
                    attempts += 1;
                    if (attempts < self.retry_config.max_attempts) {
                        std.time.sleep(delay_ms * 1_000_000); // 转换为纳秒
                        delay_ms = @min(@as(u64, @intFromFloat(@as(f32, @floatFromInt(delay_ms)) * self.retry_config.backoff_multiplier)), self.retry_config.max_delay_ms);
                        continue;
                    }
                }
                return response.*;
            } else |err| switch (err) {
                HttpError.TimeoutError, HttpError.ConnectionFailed, HttpError.RequestFailed => {
                    attempts += 1;
                    if (attempts < self.retry_config.max_attempts) {
                        std.time.sleep(delay_ms * 1_000_000); // 转换为纳秒
                        delay_ms = @min(@as(u64, @intFromFloat(@as(f32, @floatFromInt(delay_ms)) * self.retry_config.backoff_multiplier)), self.retry_config.max_delay_ms);
                        continue;
                    }
                    return err;
                },
                else => return err,
            }
        }

        return HttpError.RequestFailed;
    }
};

// 测试
test "HttpClient basic functionality" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client = HttpClient.init(allocator, null);
    defer client.deinit();

    // 测试基本功能（需要网络连接）
    // 这里只测试客户端初始化
    try std.testing.expect(client.allocator.ptr == allocator.ptr);
}

test "Response functionality" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var response = Response.init(allocator, 200);
    defer response.deinit();

    // 测试头部操作
    try response.addHeader("Content-Type", "application/json");
    try response.addHeader("Content-Length", "100");

    try std.testing.expect(response.getHeader("Content-Type") != null);
    try std.testing.expectEqualStrings("application/json", response.getHeader("Content-Type").?);

    // 测试响应体
    try response.setBody("test body");
    try std.testing.expectEqualStrings("test body", response.body);

    // 测试状态码
    try std.testing.expect(response.isSuccess());
}

test "Method enum" {
    try std.testing.expectEqualStrings("GET", Method.GET.toString());
    try std.testing.expectEqualStrings("POST", Method.POST.toString());
    try std.testing.expectEqualStrings("PUT", Method.PUT.toString());
    try std.testing.expectEqualStrings("DELETE", Method.DELETE.toString());
}
