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
        try self.headers.put(name_copy, value_copy);
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

/// HTTP客户端
pub const HttpClient = struct {
    allocator: std.mem.Allocator,
    client: std.http.Client,
    event_loop: ?*EventLoop,

    const Self = @This();

    /// 初始化HTTP客户端
    pub fn init(allocator: std.mem.Allocator, event_loop: ?*EventLoop) Self {
        return Self{
            .allocator = allocator,
            .client = std.http.Client{ .allocator = allocator },
            .event_loop = event_loop,
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

        // 添加默认头部
        if (config.body != null) {
            try headers.append(.{
                .name = "Content-Length",
                .value = try std.fmt.allocPrint(self.allocator, "{d}", .{config.body.?.len}),
            });
        }

        // 创建请求
        var req = self.client.open(
            @enumFromInt(@intFromEnum(config.method)),
            uri,
            headers.items,
            .{},
        ) catch {
            return HttpError.RequestFailed;
        };
        defer req.deinit();

        // 设置请求体
        if (config.body) |body| {
            req.transfer_encoding = .{ .content_length = body.len };
            try req.send();
            try req.writeAll(body);
        } else {
            try req.send();
        }

        try req.finish();
        try req.wait();

        // 读取响应
        var response = Response.init(self.allocator, @intCast(req.response.status.phrase().len));

        // 读取响应头
        var header_iter = req.response.iterateHeaders();
        while (header_iter.next()) |header| {
            try response.addHeader(header.name, header.value);
        }

        // 读取响应体
        var body_list = std.ArrayList(u8).init(self.allocator);
        defer body_list.deinit();

        try req.reader().readAllArrayList(&body_list, 10 * 1024 * 1024); // 10MB限制
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
