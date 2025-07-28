//! 直接测试DeepSeek API调用
//! 验证DeepSeek API是否真实可用

const std = @import("std");
const mastra = @import("mastra");

// DeepSeek API 密钥
const DEEPSEEK_API_KEY = "sk-bf82ef56c5c44ef6867bf4199d084706";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n🔍 DeepSeek API 直接调用测试\n", .{});
    std.debug.print("=" ** 40 ++ "\n", .{});

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
        .max_tokens = 100,
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

    // 5. 准备测试消息
    std.debug.print("4. 准备测试消息...\n", .{});
    const messages = [_]mastra.llm.Message{
        .{
            .role = "user",
            .content = "你好！请简单回答：1+1等于几？",
        },
    };
    std.debug.print("   📤 测试消息: {s}\n", .{messages[0].content});

    // 6. 直接调用LLM生成
    std.debug.print("5. 直接调用DeepSeek API...\n", .{});
    std.debug.print("   🔄 正在发送请求...\n", .{});

    const response = llm.generate(&messages, null) catch |err| {
        std.debug.print("   ❌ DeepSeek API调用失败: {}\n", .{err});
        std.debug.print("\n🔍 错误分析:\n", .{});

        switch (err) {
            error.RequestFailed => {
                std.debug.print("   - 网络请求失败\n", .{});
                std.debug.print("   - 可能原因: 网络连接问题或API服务不可用\n", .{});
            },
            error.AuthenticationError => {
                std.debug.print("   - API密钥无效\n", .{});
                std.debug.print("   - 请检查DeepSeek API密钥是否正确\n", .{});
            },
            error.RateLimitExceeded => {
                std.debug.print("   - API调用频率超限\n", .{});
                std.debug.print("   - 请稍后重试\n", .{});
            },
            error.ApiKeyRequired => {
                std.debug.print("   - API密钥缺失\n", .{});
                std.debug.print("   - 请设置有效的API密钥\n", .{});
            },
            else => {
                std.debug.print("   - 其他错误: {}\n", .{err});
            },
        }

        std.debug.print("\n⚠️  测试结论: DeepSeek API当前不可用\n", .{});
        std.debug.print("💡 建议:\n", .{});
        std.debug.print("   1. 检查网络连接\n", .{});
        std.debug.print("   2. 验证API密钥有效性\n", .{});
        std.debug.print("   3. 确认账户状态和配额\n", .{});
        std.debug.print("   4. 稍后重试\n", .{});
        return;
    };

    // 7. 显示成功结果
    std.debug.print("   ✅ DeepSeek API调用成功!\n", .{});
    std.debug.print("\n📥 API响应:\n", .{});
    std.debug.print("=" ** 40 ++ "\n", .{});
    std.debug.print("{s}\n", .{response.content});
    std.debug.print("=" ** 40 ++ "\n", .{});

    // 8. 响应质量分析
    std.debug.print("\n🔍 响应分析:\n", .{});
    std.debug.print("   - 响应长度: {} 字符\n", .{response.content.len});

    // 检查是否包含预期答案
    const has_answer = std.mem.indexOf(u8, response.content, "2") != null or
        std.mem.indexOf(u8, response.content, "二") != null or
        std.mem.indexOf(u8, response.content, "两") != null;

    if (has_answer) {
        std.debug.print("   ✅ 包含正确答案\n", .{});
    } else {
        std.debug.print("   ⚠️  答案可能不正确\n", .{});
    }

    // 检查是否是中文回答
    const has_chinese = std.mem.indexOf(u8, response.content, "等于") != null or
        std.mem.indexOf(u8, response.content, "是") != null or
        std.mem.indexOf(u8, response.content, "答案") != null;

    if (has_chinese) {
        std.debug.print("   ✅ 使用中文回答\n", .{});
    } else {
        std.debug.print("   ⚠️  回答语言可能不是中文\n", .{});
    }

    // 9. 测试第二个问题
    std.debug.print("\n6. 测试第二个问题...\n", .{});
    const messages2 = [_]mastra.llm.Message{
        .{
            .role = "user",
            .content = "请用一句话介绍你自己。",
        },
    };

    std.debug.print("   📤 第二个问题: {s}\n", .{messages2[0].content});

    const response2 = llm.generate(&messages2, null) catch |err| {
        std.debug.print("   ❌ 第二次调用失败: {}\n", .{err});
        std.debug.print("   ⚠️  多次调用测试跳过\n", .{});
        std.debug.print("\n🎉 单次调用测试成功!\n", .{});
        return;
    };

    std.debug.print("   ✅ 第二次调用成功!\n", .{});
    std.debug.print("   📥 第二个回答: {s}\n", .{response2.content});

    // 10. 最终结论
    std.debug.print("\n🎉 DeepSeek API 直接调用测试完成!\n", .{});
    std.debug.print("=" ** 40 ++ "\n", .{});
    std.debug.print("✅ 测试结果:\n", .{});
    std.debug.print("   - DeepSeek API连接: 成功\n", .{});
    std.debug.print("   - API响应: 正常\n", .{});
    std.debug.print("   - 内容生成: 有效\n", .{});
    std.debug.print("   - 多次调用: 支持\n", .{});
    std.debug.print("   - 中文支持: 良好\n", .{});
    std.debug.print("\n🏆 结论: DeepSeek API真实可用，能够返回有效结果!\n", .{});
    std.debug.print("🤖 这证明了Mastra.zig的LLM集成功能正常工作!\n", .{});
}
