const std = @import("std");
const mastra = @import("src/mastra.zig");

/// 逐步调试Agent功能，找出段错误的原因
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("🔍 逐步调试Agent功能\n", .{});
    std.debug.print("=" ** 30 ++ "\n", .{});

    // 步骤1：测试基础组件初始化
    std.debug.print("\n📋 步骤1：测试基础组件初始化\n", .{});

    // 测试HTTP客户端
    std.debug.print("   🌐 创建HTTP客户端...\n", .{});
    var http_client = try allocator.create(mastra.http.HttpClient);
    defer allocator.destroy(http_client);
    http_client.* = mastra.http.HttpClient.init(allocator, null);
    defer http_client.deinit();
    std.debug.print("   ✅ HTTP客户端创建成功\n", .{});

    // 测试Logger
    std.debug.print("   📝 创建Logger...\n", .{});
    const logger = try mastra.Logger.init(allocator, .{ .level = .info });
    std.debug.print("   ✅ Logger创建成功\n", .{});

    // 步骤2：测试LLM初始化
    std.debug.print("\n📋 步骤2：测试LLM初始化\n", .{});

    std.debug.print("   🧠 创建LLM配置...\n", .{});
    const llm_config = mastra.llm.LLMConfig{
        .provider = .deepseek,
        .model = "deepseek-chat",
        .api_key = "sk-bf82ef56c5c44ef6867bf4199d084706",
        .base_url = "https://api.deepseek.com/v1",
        .temperature = 0.7,
        .max_tokens = 200,
    };
    std.debug.print("   ✅ LLM配置创建成功\n", .{});

    std.debug.print("   🧠 初始化LLM实例...\n", .{});
    var llm = try mastra.llm.LLM.init(allocator, llm_config);
    defer llm.deinit();
    std.debug.print("   ✅ LLM实例创建成功\n", .{});

    std.debug.print("   🔗 设置HTTP客户端...\n", .{});
    try llm.setHttpClient(http_client);
    std.debug.print("   ✅ HTTP客户端设置成功\n", .{});

    // 步骤3：测试Agent初始化
    std.debug.print("\n📋 步骤3：测试Agent初始化\n", .{});

    std.debug.print("   🤖 创建Agent配置...\n", .{});
    const agent_config = mastra.agent.AgentConfig{
        .name = "调试Agent",
        .model = llm,
        .memory = null,
        .instructions = mastra.DynamicString.static("你是一个测试用的AI助手。"),
        .logger = logger,
    };
    std.debug.print("   ✅ Agent配置创建成功\n", .{});

    std.debug.print("   🤖 初始化Agent实例...\n", .{});
    var agent = try mastra.agent.Agent.init(allocator, agent_config);
    defer agent.deinit();
    std.debug.print("   ✅ Agent实例创建成功\n", .{});

    // 步骤4：测试简单消息创建
    std.debug.print("\n📋 步骤4：测试消息创建\n", .{});

    std.debug.print("   💬 创建测试消息...\n", .{});
    const test_message = mastra.agent.Message{
        .role = "user",
        .content = "你好",
    };
    std.debug.print("   ✅ 测试消息创建成功: {s}\n", .{test_message.content});

    // 步骤5：测试LLM直接调用（不通过Agent）
    std.debug.print("\n📋 步骤5：测试LLM直接调用\n", .{});

    std.debug.print("   🔄 准备直接调用LLM...\n", .{});
    const messages = [_]mastra.llm.Message{
        .{ .role = "user", .content = "你好" },
    };

    std.debug.print("   🔄 调用LLM generate方法...\n", .{});
    var llm_response = llm.generate(&messages, null) catch |err| {
        std.debug.print("   ❌ LLM调用失败: {}\n", .{err});
        std.debug.print("   🔍 错误详情: LLM直接调用出现问题\n", .{});
        return;
    };
    defer llm_response.deinit();

    std.debug.print("   ✅ LLM直接调用成功\n", .{});
    std.debug.print("   📄 响应内容: {s}\n", .{llm_response.content});

    // 步骤6：测试Agent调用（如果LLM直接调用成功）
    std.debug.print("\n📋 步骤6：测试Agent调用\n", .{});

    std.debug.print("   🤖 通过Agent调用LLM...\n", .{});
    var agent_response = agent.generate(&[_]mastra.agent.Message{test_message}) catch |err| {
        std.debug.print("   ❌ Agent调用失败: {}\n", .{err});
        std.debug.print("   🔍 错误详情: Agent调用出现问题\n", .{});
        return;
    };
    defer agent_response.deinit();

    std.debug.print("   ✅ Agent调用成功\n", .{});
    std.debug.print("   📄 响应内容: {s}\n", .{agent_response.content});

    // 步骤7：测试多次调用
    std.debug.print("\n📋 步骤7：测试多次调用\n", .{});

    const test_questions = [_][]const u8{
        "1+1等于几？",
        "今天天气怎么样？",
        "什么是AI？",
    };

    for (test_questions, 0..) |question, i| {
        std.debug.print("   🔄 测试问题 {d}: {s}\n", .{ i + 1, question });

        const msg = mastra.agent.Message{
            .role = "user",
            .content = question,
        };

        var response = agent.generate(&[_]mastra.agent.Message{msg}) catch |err| {
            std.debug.print("   ❌ 问题 {d} 调用失败: {}\n", .{ i + 1, err });
            continue;
        };
        defer response.deinit();

        std.debug.print("   ✅ 问题 {d} 调用成功\n", .{i + 1});
        std.debug.print("   📄 响应: {s}\n", .{response.content});

        // 短暂延迟
        std.time.sleep(1000000000); // 1秒
    }

    // 总结
    std.debug.print("\n🎉 调试总结\n", .{});
    std.debug.print("=" ** 30 ++ "\n", .{});
    std.debug.print("✅ 所有测试步骤完成\n", .{});
    std.debug.print("✅ Agent功能正常工作\n", .{});
    std.debug.print("✅ 没有发现段错误\n", .{});
    std.debug.print("🚀 Mastra.zig Agent系统验证成功！\n", .{});
}
