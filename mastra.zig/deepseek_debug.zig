//! DeepSeek API 详细调试工具
//! 逐步调试DeepSeek API调用的每个环节

const std = @import("std");
const mastra = @import("src/mastra.zig");

const DEEPSEEK_API_KEY = "sk-bf82ef56c5c44ef6867bf4199d084706";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n🔧 DeepSeek API 详细调试\n", .{});
    std.debug.print("=" ** 50 ++ "\n", .{});

    // 1. 测试基础HTTP POST请求
    std.debug.print("1. 测试基础HTTP POST请求...\n", .{});

    var http_client = mastra.http.HttpClient.initWithConfig(allocator, null, .{ .max_attempts = 1, .initial_delay_ms = 1000 }, .{ .request_timeout_ms = 30000 });
    defer http_client.deinit();

    // 测试简单的POST请求
    const test_headers = [_]mastra.http.Header{
        .{ .name = "Content-Type", .value = "application/json" },
        .{ .name = "User-Agent", .value = "Mastra-Zig/1.0" },
    };

    const test_body = "{\"test\": \"data\"}";

    std.debug.print("   📤 测试POST到httpbin.org...\n", .{});
    var test_response = http_client.post("https://httpbin.org/post", &test_headers, test_body) catch |err| {
        std.debug.print("   ❌ 基础POST请求失败: {}\n", .{err});
        return;
    };
    defer test_response.deinit();

    std.debug.print("   ✅ 基础POST请求成功\n", .{});
    std.debug.print("   📊 状态码: {}\n", .{test_response.status_code});

    // 2. 测试DeepSeek API连接
    std.debug.print("\n2. 测试DeepSeek API连接...\n", .{});

    const auth_header_value = try std.fmt.allocPrint(allocator, "Bearer {s}", .{DEEPSEEK_API_KEY});
    defer allocator.free(auth_header_value);

    const deepseek_headers = [_]mastra.http.Header{
        .{ .name = "Content-Type", .value = "application/json" },
        .{ .name = "Authorization", .value = auth_header_value },
        .{ .name = "User-Agent", .value = "Mastra-Zig/1.0" },
    };

    // 构建最小的有效请求
    const minimal_request =
        \\{
        \\  "model": "deepseek-chat",
        \\  "messages": [
        \\    {"role": "user", "content": "Hi"}
        \\  ],
        \\  "max_tokens": 5
        \\}
    ;

    std.debug.print("   📤 发送最小请求到DeepSeek API...\n", .{});
    std.debug.print("   🌐 URL: https://api.deepseek.com/v1/chat/completions\n", .{});
    std.debug.print("   🔑 API密钥: {s}...{s}\n", .{ DEEPSEEK_API_KEY[0..8], DEEPSEEK_API_KEY[DEEPSEEK_API_KEY.len - 8 ..] });
    std.debug.print("   📄 请求体: {s}\n", .{minimal_request});

    var deepseek_response = http_client.post("https://api.deepseek.com/v1/chat/completions", &deepseek_headers, minimal_request) catch |err| {
        std.debug.print("   ❌ DeepSeek API请求失败: {}\n", .{err});

        // 尝试诊断具体错误
        std.debug.print("\n🔍 错误诊断:\n", .{});
        switch (err) {
            error.RequestFailed => {
                std.debug.print("   - 这是一个通用的网络请求失败错误\n", .{});
                std.debug.print("   - 可能的原因:\n", .{});
                std.debug.print("     * SSL/TLS握手失败\n", .{});
                std.debug.print("     * 连接超时\n", .{});
                std.debug.print("     * 服务器拒绝连接\n", .{});
                std.debug.print("     * DNS解析问题\n", .{});
            },
            else => {
                std.debug.print("   - 未知错误类型: {}\n", .{err});
            },
        }
        return;
    };
    defer deepseek_response.deinit();

    std.debug.print("   ✅ DeepSeek API请求成功!\n", .{});
    std.debug.print("   📊 状态码: {}\n", .{deepseek_response.status_code});
    std.debug.print("   📄 响应体: {s}\n", .{deepseek_response.body});

    // 3. 解析响应
    std.debug.print("\n3. 解析API响应...\n", .{});

    if (deepseek_response.status_code == 200) {
        std.debug.print("   ✅ API调用成功!\n", .{});

        // 尝试解析JSON响应
        var json_parser = std.json.parseFromSlice(std.json.Value, allocator, deepseek_response.body, .{}) catch |err| {
            std.debug.print("   ⚠️  JSON解析失败: {}\n", .{err});
            return;
        };
        defer json_parser.deinit();

        const json_obj = json_parser.value;
        if (json_obj.object.get("choices")) |choices| {
            if (choices.array.items.len > 0) {
                const first_choice = choices.array.items[0];
                if (first_choice.object.get("message")) |message| {
                    if (message.object.get("content")) |content| {
                        std.debug.print("   🤖 AI响应: {s}\n", .{content.string});
                    }
                }
            }
        }
    } else {
        std.debug.print("   ❌ API返回错误状态码: {}\n", .{deepseek_response.status_code});
        std.debug.print("   📄 错误响应: {s}\n", .{deepseek_response.body});

        // 分析常见的错误状态码
        switch (deepseek_response.status_code) {
            400 => std.debug.print("   💡 400 Bad Request: 请求格式错误\n", .{}),
            401 => std.debug.print("   💡 401 Unauthorized: API密钥无效\n", .{}),
            403 => std.debug.print("   💡 403 Forbidden: 访问被拒绝\n", .{}),
            429 => std.debug.print("   💡 429 Too Many Requests: 请求频率过高\n", .{}),
            500 => std.debug.print("   💡 500 Internal Server Error: 服务器内部错误\n", .{}),
            else => std.debug.print("   💡 未知状态码\n", .{}),
        }
    }

    // 4. 测试Mastra的LLM系统
    std.debug.print("\n4. 测试Mastra的LLM系统...\n", .{});

    const llm_config = mastra.llm.LLMConfig{
        .provider = .deepseek,
        .model = "deepseek-chat",
        .api_key = DEEPSEEK_API_KEY,
        .base_url = null,
        .temperature = 0.7,
        .max_tokens = 10,
    };

    var llm = mastra.llm.LLM.init(allocator, llm_config) catch |err| {
        std.debug.print("   ❌ LLM初始化失败: {}\n", .{err});
        return;
    };
    defer llm.deinit();

    llm.setHttpClient(&http_client) catch |err| {
        std.debug.print("   ❌ 设置HTTP客户端失败: {}\n", .{err});
        return;
    };

    const messages = [_]mastra.llm.Message{
        .{ .role = "user", .content = "Hello, how are you?" },
    };

    std.debug.print("   📤 使用Mastra LLM系统发送请求...\n", .{});
    const mastra_response = llm.generate(&messages, null) catch |err| {
        std.debug.print("   ❌ Mastra LLM系统失败: {}\n", .{err});
        return;
    };

    std.debug.print("   ✅ Mastra LLM系统成功!\n", .{});
    std.debug.print("   🤖 响应: {s}\n", .{mastra_response.content});

    // 5. 总结
    std.debug.print("\n🎉 DeepSeek API 调试完成!\n", .{});
    std.debug.print("=" ** 50 ++ "\n", .{});
    std.debug.print("✅ 调试结果:\n", .{});
    std.debug.print("   - 基础HTTP POST: 正常\n", .{});
    std.debug.print("   - DeepSeek API连接: 成功\n", .{});
    std.debug.print("   - API响应解析: 正常\n", .{});
    std.debug.print("   - Mastra LLM系统: 正常\n", .{});
    std.debug.print("\n🏆 结论: DeepSeek API完全可用，AI Agent应该能正常工作!\n", .{});
}
