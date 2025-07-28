const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("🧪 最小DeepSeek API测试\n", .{});

    // 使用与Agent相同的中文JSON
    const json_body = "{\"model\":\"deepseek-chat\",\"messages\":[{\"role\":\"system\",\"content\":\"你是一个友好的AI助手，请用中文回答问题。回答要简洁明了，控制在100字以内。\"},{\"role\":\"user\",\"content\":\"你好！请简单介绍一下你自己，并告诉我今天是星期几？\"}],\"temperature\":0.7,\"max_tokens\":200,\"stream\":false}";

    const api_key = "sk-bf82ef56c5c44ef6867bf4199d084706";
    const url = "https://api.deepseek.com/v1/chat/completions";

    // 创建HTTP客户端
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    // 解析URL
    const uri = std.Uri.parse(url) catch |err| {
        std.debug.print("❌ URL解析失败: {}\n", .{err});
        return;
    };

    // 准备头部
    const auth_header = try std.fmt.allocPrint(allocator, "Bearer {s}", .{api_key});
    defer allocator.free(auth_header);

    var header_buffer: [16384]u8 = undefined;
    var req = client.open(.POST, uri, .{
        .server_header_buffer = &header_buffer,
        .extra_headers = &[_]std.http.Header{
            .{ .name = "content-type", .value = "application/json" },
            .{ .name = "authorization", .value = auth_header },
            .{ .name = "user-agent", .value = "curl/8.4.0" },
            .{ .name = "accept", .value = "*/*" },
        },
    }) catch |err| {
        std.debug.print("❌ 请求创建失败: {}\n", .{err});
        return;
    };
    defer req.deinit();

    // 发送请求体
    req.transfer_encoding = .{ .content_length = json_body.len };
    req.send() catch |err| {
        std.debug.print("❌ 请求发送失败: {}\n", .{err});
        return;
    };

    req.writeAll(json_body) catch |err| {
        std.debug.print("❌ 请求体写入失败: {}\n", .{err});
        return;
    };

    req.finish() catch |err| {
        std.debug.print("❌ 请求完成失败: {}\n", .{err});
        return;
    };

    req.wait() catch |err| {
        std.debug.print("❌ 等待响应失败: {}\n", .{err});
        return;
    };

    // 读取响应
    const status_code = @intFromEnum(req.response.status);
    std.debug.print("📊 状态码: {d}\n", .{status_code});

    // 读取响应体
    var body_list = std.ArrayList(u8).init(allocator);
    defer body_list.deinit();

    req.reader().readAllArrayList(&body_list, 10 * 1024 * 1024) catch |err| {
        std.debug.print("❌ 响应体读取失败: {}\n", .{err});
        return;
    };

    std.debug.print("📄 响应体长度: {d} 字节\n", .{body_list.items.len});

    if (status_code == 200) {
        std.debug.print("✅ 成功！响应体: {s}\n", .{body_list.items});
    } else {
        std.debug.print("❌ 失败！响应体: {s}\n", .{body_list.items});
    }
}
