const std = @import("std");
const mastra = @import("src/mastra.zig");

/// 专门测试HTTP响应的内存管理
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("🔍 HTTP内存管理测试\n", .{});
    std.debug.print("=" ** 25 ++ "\n", .{});

    // 测试1：创建HTTP客户端
    std.debug.print("\n📋 测试1：HTTP客户端创建\n", .{});
    var http_client = try allocator.create(mastra.http.HttpClient);
    defer allocator.destroy(http_client);
    http_client.* = mastra.http.HttpClient.init(allocator, null);
    defer http_client.deinit();
    std.debug.print("✅ HTTP客户端创建成功\n", .{});

    // 测试2：创建简单的HTTP响应
    std.debug.print("\n📋 测试2：HTTP响应创建和释放\n", .{});
    {
        var response = mastra.http.Response.init(allocator, 200);
        try response.addHeader("Content-Type", "application/json");
        try response.addHeader("Content-Length", "100");
        try response.setBody("test body");
        
        std.debug.print("✅ HTTP响应创建成功\n", .{});
        std.debug.print("   - 状态码: {d}\n", .{response.status_code});
        std.debug.print("   - 头部数量: {d}\n", .{response.headers.count()});
        std.debug.print("   - 响应体长度: {d}\n", .{response.body.len});
        
        response.deinit();
        std.debug.print("✅ HTTP响应释放成功\n", .{});
    }

    // 测试3：多个HTTP响应的创建和释放
    std.debug.print("\n📋 测试3：多个HTTP响应测试\n", .{});
    for (0..3) |i| {
        var response = mastra.http.Response.init(allocator, 200);
        try response.addHeader("Test-Header", "test-value");
        try response.addHeader("Request-ID", "12345");
        try response.setBody("response body");
        
        std.debug.print("   ✅ 响应 {d} 创建成功\n", .{i + 1});
        
        response.deinit();
        std.debug.print("   ✅ 响应 {d} 释放成功\n", .{i + 1});
    }

    // 测试4：模拟DeepSeek的使用模式
    std.debug.print("\n📋 测试4：模拟DeepSeek使用模式\n", .{});
    {
        // 模拟HTTP请求的创建
        var response = mastra.http.Response.init(allocator, 200);
        defer response.deinit(); // 使用defer，就像DeepSeek中一样
        
        // 添加典型的API响应头部
        try response.addHeader("Content-Type", "application/json");
        try response.addHeader("Content-Length", "500");
        try response.addHeader("Server", "nginx");
        try response.addHeader("Date", "Mon, 01 Jan 2024 00:00:00 GMT");
        
        // 设置响应体
        const json_body = 
            \\{"id":"test","object":"chat.completion","created":1234567890,"model":"deepseek-chat","choices":[{"index":0,"message":{"role":"assistant","content":"你好！"},"finish_reason":"stop"}],"usage":{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15}}
        ;
        try response.setBody(json_body);
        
        std.debug.print("✅ 模拟DeepSeek响应创建成功\n", .{});
        std.debug.print("   - 头部数量: {d}\n", .{response.headers.count()});
        std.debug.print("   - 响应体长度: {d}\n", .{response.body.len});
        
        // 模拟JSON解析过程
        var json_arena = std.heap.ArenaAllocator.init(allocator);
        defer json_arena.deinit();
        
        // 简单的JSON解析测试（不使用实际的DeepSeek结构）
        const parsed = std.json.parseFromSlice(std.json.Value, json_arena.allocator(), response.body, .{}) catch |err| {
            std.debug.print("   ❌ JSON解析失败: {}\n", .{err});
            return;
        };
        
        std.debug.print("✅ JSON解析成功\n", .{});
        std.debug.print("   - JSON类型: {}\n", .{parsed.value});
        
        // defer response.deinit() 会在这里自动调用
    }

    std.debug.print("\n🎉 HTTP内存管理测试完成\n", .{});
    std.debug.print("✅ 所有测试通过\n", .{});
    std.debug.print("✅ 如果没有内存泄漏报告，说明HTTP响应内存管理正常\n", .{});
}
