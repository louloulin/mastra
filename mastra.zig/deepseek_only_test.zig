const std = @import("std");
const mastra = @import("src/mastra.zig");

/// 专门测试DeepSeek的HTTP调用，不涉及其他任何HTTP操作
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("🔍 DeepSeek专用HTTP测试\n", .{});
    std.debug.print("=" ** 25 ++ "\n", .{});

    // 只创建必要的组件
    std.debug.print("\n📋 创建HTTP客户端\n", .{});
    var http_client = try allocator.create(mastra.http.HttpClient);
    defer allocator.destroy(http_client);
    http_client.* = mastra.http.HttpClient.init(allocator, null);
    defer http_client.deinit();
    std.debug.print("✅ HTTP客户端创建成功\n", .{});

    // 创建DeepSeek客户端
    std.debug.print("\n📋 创建DeepSeek客户端\n", .{});
    var deepseek_client = mastra.llm.DeepSeekClient.init(
        allocator,
        "sk-bf82ef56c5c44ef6867bf4199d084706",
        http_client,
        null,
    );
    std.debug.print("✅ DeepSeek客户端创建成功\n", .{});

    // 创建单个请求
    std.debug.print("\n📋 创建DeepSeek请求\n", .{});
    const messages = [_]mastra.llm.DeepSeekMessage{
        .{
            .role = "user",
            .content = "你好",
        },
    };

    const request = mastra.llm.DeepSeekRequest{
        .model = "deepseek-chat",
        .messages = &messages,
        .temperature = 0.7,
        .max_tokens = 50,
        .stream = false,
    };
    std.debug.print("✅ DeepSeek请求创建成功\n", .{});

    // 进行单次API调用
    std.debug.print("\n📋 进行DeepSeek API调用\n", .{});
    std.debug.print("🔄 调用chatCompletion...\n", .{});

    var response = deepseek_client.chatCompletion(request) catch |err| {
        std.debug.print("❌ DeepSeek API调用失败: {}\n", .{err});
        return;
    };
    defer response.deinitCopy(allocator);

    std.debug.print("✅ DeepSeek API调用成功\n", .{});
    std.debug.print("📄 响应ID: {s}\n", .{response.id});
    std.debug.print("📄 模型: {s}\n", .{response.model});

    if (response.choices.len > 0) {
        const content = response.choices[0].message.content;
        std.debug.print("📄 响应内容长度: {d}\n", .{content.len});
        std.debug.print("📄 响应内容: {s}\n", .{content});
    }

    std.debug.print("\n🎉 DeepSeek专用测试完成\n", .{});
    std.debug.print("✅ 如果没有内存泄漏，说明DeepSeek的HTTP调用是正确的\n", .{});
}
