const std = @import("std");
const mastra = @import("mastra");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("🔍 HTTP客户端详细调试\n", .{});
    std.debug.print("====================\n", .{});

    // 测试1: 基础HTTP客户端初始化
    std.debug.print("1. 初始化HTTP客户端...\n", .{});
    var http_client = mastra.http.HttpClient.init(allocator, null);
    defer http_client.deinit();
    std.debug.print("   ✅ HTTP客户端初始化成功\n", .{});

    // 测试2: 简单GET请求到httpbin
    std.debug.print("\n2. 测试简单GET请求...\n", .{});
    const get_config = mastra.http.RequestConfig{
        .method = .GET,
        .url = "https://httpbin.org/get",
        .timeout_ms = 10000,
    };

    std.debug.print("   📤 发送GET请求到: {s}\n", .{get_config.url});
    var get_response = http_client.request(get_config) catch |err| {
        std.debug.print("   ❌ GET请求失败: {}\n", .{err});
        return;
    };
    defer get_response.deinit();
    std.debug.print("   ✅ GET请求成功，状态码: {d}\n", .{get_response.status_code});

    // 测试3: POST请求到httpbin
    std.debug.print("\n3. 测试POST请求...\n", .{});
    const test_json = "{\"test\": \"data\"}";

    var post_headers = std.ArrayList(mastra.http.Header).init(allocator);
    defer post_headers.deinit();
    try post_headers.append(.{ .name = "Content-Type", .value = "application/json" });

    const post_config = mastra.http.RequestConfig{
        .method = .POST,
        .url = "https://httpbin.org/post",
        .headers = post_headers.items,
        .body = test_json,
        .timeout_ms = 10000,
    };

    std.debug.print("   📤 发送POST请求到: {s}\n", .{post_config.url});
    std.debug.print("   📄 请求体: {s}\n", .{test_json});
    var post_response = http_client.request(post_config) catch |err| {
        std.debug.print("   ❌ POST请求失败: {}\n", .{err});
        return;
    };
    defer post_response.deinit();
    std.debug.print("   ✅ POST请求成功，状态码: {d}\n", .{post_response.status_code});

    // 测试4: DeepSeek API请求
    std.debug.print("\n4. 测试DeepSeek API请求...\n", .{});
    const api_key = "sk-bf82ef56c5c44ef6867bf4199d084706";
    const deepseek_url = "https://api.deepseek.com/v1/chat/completions";

    const deepseek_json = "{\"model\":\"deepseek-chat\",\"messages\":[{\"role\":\"user\",\"content\":\"Hello\"}],\"temperature\":0.7,\"max_tokens\":10,\"stream\":false}";

    var deepseek_headers = std.ArrayList(mastra.http.Header).init(allocator);
    defer deepseek_headers.deinit();

    const auth_header = try std.fmt.allocPrint(allocator, "Bearer {s}", .{api_key});
    defer allocator.free(auth_header);

    try deepseek_headers.append(.{ .name = "Content-Type", .value = "application/json" });
    try deepseek_headers.append(.{ .name = "Authorization", .value = auth_header });
    try deepseek_headers.append(.{ .name = "User-Agent", .value = "curl/8.4.0" });
    try deepseek_headers.append(.{ .name = "Accept", .value = "*/*" });

    const deepseek_config = mastra.http.RequestConfig{
        .method = .POST,
        .url = deepseek_url,
        .headers = deepseek_headers.items,
        .body = deepseek_json,
        .timeout_ms = 30000,
    };

    std.debug.print("   📤 发送请求到: {s}\n", .{deepseek_url});
    std.debug.print("   🔑 API密钥: {s}...{s}\n", .{ api_key[0..8], api_key[api_key.len - 8 ..] });
    std.debug.print("   📄 请求体: {s}\n", .{deepseek_json});
    std.debug.print("   📋 请求头数量: {d}\n", .{deepseek_headers.items.len});

    var deepseek_response = http_client.request(deepseek_config) catch |err| {
        std.debug.print("   ❌ DeepSeek API请求失败: {}\n", .{err});
        std.debug.print("   💡 这可能是网络问题、API密钥问题或服务器问题\n", .{});
        return;
    };
    defer deepseek_response.deinit();

    std.debug.print("   ✅ DeepSeek API请求成功！\n", .{});
    std.debug.print("   📊 状态码: {d}\n", .{deepseek_response.status_code});
    std.debug.print("   📄 响应体长度: {d} 字节\n", .{deepseek_response.body.len});

    if (deepseek_response.body.len > 0 and deepseek_response.body.len < 1000) {
        std.debug.print("   📄 响应体: {s}\n", .{deepseek_response.body});
    }

    std.debug.print("\n🎉 HTTP调试完成！\n", .{});
}
