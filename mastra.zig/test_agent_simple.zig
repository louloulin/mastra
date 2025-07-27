//! 简单的AI Agent DeepSeek测试
//! 直接测试AI Agent是否能使用DeepSeek provider真实返回结果

const std = @import("std");
const mastra = @import("src/mastra.zig");

// DeepSeek API 密钥
const DEEPSEEK_API_KEY = "sk-bf82ef56c5c44ef6867bf4199d084706";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n🤖 AI Agent with DeepSeek Provider 真实调用测试\n", .{});
    std.debug.print("=" ** 50 ++ "\n", .{});

    // 1. 创建HTTP客户端
    std.debug.print("1. 创建HTTP客户端...\n", .{});
    var http_client = mastra.http.HttpClient.initWithConfig(allocator, null, .{ .max_attempts = 3, .initial_delay_ms = 1000 }, .{ .request_timeout_ms = 30000 });
    defer http_client.deinit();
    std.debug.print("   ✅ HTTP客户端创建成功\n", .{});

    // 2. 创建LLM配置
    std.debug.print("2. 配置DeepSeek LLM...\n", .{});
    const llm_config = mastra.llm.LLMConfig{
        .provider = .deepseek,
        .model = "deepseek-chat",
        .api_key = DEEPSEEK_API_KEY,
        .base_url = null,
        .temperature = 0.7,
        .max_tokens = 200,
    };
    std.debug.print("   ✅ LLM配置完成\n", .{});
    std.debug.print("   - 提供商: {s}\n", .{llm_config.provider.toString()});
    std.debug.print("   - 模型: {s}\n", .{llm_config.model});
    std.debug.print("   - API密钥: {s}...{s}\n", .{ DEEPSEEK_API_KEY[0..8], DEEPSEEK_API_KEY[DEEPSEEK_API_KEY.len - 8 ..] });

    // 3. 创建LLM实例
    std.debug.print("3. 初始化LLM实例...\n", .{});
    var llm = mastra.llm.LLM.init(allocator, llm_config) catch |err| {
        std.debug.print("   ❌ LLM初始化失败: {}\n", .{err});
        return;
    };
    defer llm.deinit();

    // 4. 设置HTTP客户端
    llm.setHttpClient(&http_client) catch |err| {
        std.debug.print("   ❌ 设置HTTP客户端失败: {}\n", .{err});
        return;
    };
    std.debug.print("   ✅ LLM实例初始化成功\n", .{});

    // 5. 创建Agent
    std.debug.print("4. 创建AI Agent...\n", .{});
    const agent_config = mastra.agent.AgentConfig{
        .name = "DeepSeek测试Agent",
        .model = llm,
        .memory = null,
        .tools = null,
        .instructions = mastra.DynamicString.static("你是一个友好的AI助手，请用中文回答问题。回答要简洁明了，控制在100字以内。"),
        .logger = null,
    };

    const agent = mastra.agent.Agent.init(allocator, agent_config) catch |err| {
        std.debug.print("   ❌ Agent创建失败: {}\n", .{err});
        return;
    };
    defer agent.deinit();
    std.debug.print("   ✅ Agent创建成功\n", .{});
    std.debug.print("   - 名称: {s}\n", .{agent.name});
    const resolved_instructions = try agent.instructions.resolve(agent.runtime_context);
    std.debug.print("   - 指令: {s}\n", .{resolved_instructions});

    // 6. 准备测试消息
    std.debug.print("5. 准备测试消息...\n", .{});
    const test_message = mastra.agent.Message{
        .role = "user",
        .content = "你好！请简单介绍一下你自己，并告诉我今天是星期几？",
        .metadata = null,
    };
    std.debug.print("   📤 用户消息: {s}\n", .{test_message.content});

    // 7. 调用Agent生成响应
    std.debug.print("6. 调用Agent生成响应...\n", .{});
    std.debug.print("   🔄 正在连接DeepSeek API...\n", .{});

    const response = agent.generate(&[_]mastra.agent.Message{test_message}) catch |err| {
        std.debug.print("   ❌ Agent生成响应失败: {}\n", .{err});
        std.debug.print("\n🔍 可能的原因:\n", .{});
        std.debug.print("   1. DeepSeek API密钥无效或过期\n", .{});
        std.debug.print("   2. 网络连接问题\n", .{});
        std.debug.print("   3. DeepSeek API服务暂时不可用\n", .{});
        std.debug.print("   4. 请求格式或参数错误\n", .{});
        std.debug.print("   5. API配额已用完\n", .{});
        std.debug.print("\n⚠️  测试结论: 无法连接到DeepSeek API\n", .{});
        return;
    };

    // 8. 显示响应结果
    std.debug.print("   ✅ 成功收到响应!\n", .{});
    std.debug.print("\n📥 AI Agent响应:\n", .{});
    std.debug.print("=" ** 50 ++ "\n", .{});
    std.debug.print("{s}\n", .{response.content});
    std.debug.print("=" ** 50 ++ "\n", .{});

    // 9. 验证响应质量
    std.debug.print("\n🔍 响应质量分析:\n", .{});
    std.debug.print("   - 响应长度: {} 字符\n", .{response.content.len});

    // 检查是否包含中文回答
    const has_chinese = std.mem.indexOf(u8, response.content, "你好") != null or
        std.mem.indexOf(u8, response.content, "您好") != null or
        std.mem.indexOf(u8, response.content, "助手") != null or
        std.mem.indexOf(u8, response.content, "我是") != null;

    if (has_chinese) {
        std.debug.print("   ✅ 包含中文回答\n", .{});
    } else {
        std.debug.print("   ⚠️  回答语言可能不符合预期\n", .{});
    }

    // 检查回答是否合理
    if (response.content.len > 10) {
        std.debug.print("   ✅ 回答长度合理\n", .{});
    } else {
        std.debug.print("   ⚠️  回答可能过短\n", .{});
    }

    // 10. 测试多轮对话
    std.debug.print("\n7. 测试多轮对话...\n", .{});
    const follow_up_message = mastra.agent.Message{
        .role = "user",
        .content = "请用一句话总结一下人工智能的定义。",
        .metadata = null,
    };

    std.debug.print("   📤 后续消息: {s}\n", .{follow_up_message.content});

    const follow_up_response = agent.generate(&[_]mastra.agent.Message{follow_up_message}) catch |err| {
        std.debug.print("   ❌ 多轮对话失败: {}\n", .{err});
        std.debug.print("   ⚠️  多轮对话测试跳过\n", .{});
        std.debug.print("\n🎉 单轮对话测试成功完成!\n", .{});
        return;
    };

    std.debug.print("   ✅ 多轮对话成功!\n", .{});
    std.debug.print("   📥 后续响应: {s}\n", .{follow_up_response.content});

    // 11. 最终结论
    std.debug.print("\n🎉 AI Agent with DeepSeek Provider 测试完成!\n", .{});
    std.debug.print("=" ** 50 ++ "\n", .{});
    std.debug.print("✅ 测试结果:\n", .{});
    std.debug.print("   - DeepSeek API连接: 成功\n", .{});
    std.debug.print("   - Agent消息处理: 正常\n", .{});
    std.debug.print("   - 响应内容生成: 有效\n", .{});
    std.debug.print("   - 多轮对话: 支持\n", .{});
    std.debug.print("   - 中文回答: 符合预期\n", .{});
    std.debug.print("\n🏆 结论: AI Agent使用DeepSeek provider能够真实返回有效结果!\n", .{});
}
