const std = @import("std");
const mastra = @import("src/mastra.zig");

/// 单次调用测试，验证基本功能并分析内存问题
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("🔍 单次调用测试\n", .{});
    std.debug.print("=" ** 20 ++ "\n", .{});

    // 创建HTTP客户端
    std.debug.print("🌐 创建HTTP客户端...\n", .{});
    var http_client = try allocator.create(mastra.http.HttpClient);
    defer allocator.destroy(http_client);
    http_client.* = mastra.http.HttpClient.init(allocator, null);
    defer http_client.deinit();
    std.debug.print("✅ HTTP客户端创建成功\n", .{});

    // 创建LLM
    std.debug.print("🧠 创建LLM...\n", .{});
    var llm = try mastra.llm.LLM.init(allocator, .{
        .provider = .deepseek,
        .model = "deepseek-chat",
        .api_key = "sk-bf82ef56c5c44ef6867bf4199d084706",
        .base_url = "https://api.deepseek.com/v1",
        .temperature = 0.7,
        .max_tokens = 100, // 减少token数量
    });
    defer llm.deinit();
    
    try llm.setHttpClient(http_client);
    std.debug.print("✅ LLM创建成功\n", .{});

    // 创建Logger
    std.debug.print("📝 创建Logger...\n", .{});
    const logger = try mastra.Logger.init(allocator, .{ .level = .info });
    std.debug.print("✅ Logger创建成功\n", .{});

    // 创建Agent
    std.debug.print("🤖 创建Agent...\n", .{});
    var agent = try mastra.agent.Agent.init(allocator, .{
        .name = "单次测试Agent",
        .model = llm,
        .memory = null,
        .instructions = "请用中文简短回答。",
        .logger = logger,
    });
    defer agent.deinit();
    std.debug.print("✅ Agent创建成功\n", .{});

    // 进行单次调用
    std.debug.print("\n💬 进行单次AI调用...\n", .{});
    const test_message = mastra.agent.Message{
        .role = "user",
        .content = "你好",
    };

    std.debug.print("📤 用户: {s}\n", .{test_message.content});
    
    var response = agent.generate(&[_]mastra.agent.Message{test_message}) catch |err| {
        std.debug.print("❌ 调用失败: {}\n", .{err});
        return;
    };
    defer response.deinit();
    
    std.debug.print("✅ 调用成功\n", .{});
    std.debug.print("📄 响应长度: {d} 字节\n", .{response.content.len});
    
    // 检查响应内容的前几个字节
    if (response.content.len > 0) {
        std.debug.print("📄 响应前10字节: ", .{});
        const max_len = @min(10, response.content.len);
        for (response.content[0..max_len]) |byte| {
            std.debug.print("{d} ", .{byte});
        }
        std.debug.print("\n", .{});
        
        // 尝试打印响应内容（可能有乱码）
        std.debug.print("📄 响应内容: {s}\n", .{response.content});
    }

    std.debug.print("\n🎉 单次调用测试完成\n", .{});
    std.debug.print("✅ 基本功能正常\n", .{});
    std.debug.print("⚠️  字符编码需要修复\n", .{});
}
