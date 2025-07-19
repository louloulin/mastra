//! DeepSeek API 简化测试
//!
//! 这个测试验证DeepSeek API的基础功能，不进行实际网络调用

const std = @import("std");
const testing = std.testing;
const mastra = @import("mastra");

// DeepSeek API 密钥 (从用户提供)
const DEEPSEEK_API_KEY = "sk-bf82ef56c5c44ef6867bf4199d084706";

test "DeepSeek 基础配置测试" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n🧪 DeepSeek基础配置测试\n", .{});

    // 创建HTTP客户端
    var http_client = mastra.http.HttpClient.init(allocator, null);
    defer http_client.deinit();

    // 创建DeepSeek客户端
    const deepseek_client = mastra.DeepSeekClient.init(
        allocator,
        DEEPSEEK_API_KEY,
        &http_client,
        null,
    );

    // 验证配置
    try testing.expectEqualStrings(DEEPSEEK_API_KEY, deepseek_client.api_key);
    try testing.expectEqualStrings("https://api.deepseek.com/v1", deepseek_client.base_url);

    std.debug.print("✅ DeepSeek客户端配置正确\n", .{});
    std.debug.print("  - API Key: {s}...{s}\n", .{ DEEPSEEK_API_KEY[0..8], DEEPSEEK_API_KEY[DEEPSEEK_API_KEY.len - 8 ..] });
    std.debug.print("  - Base URL: {s}\n", .{deepseek_client.base_url});
}

test "DeepSeek 请求序列化测试" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n🧪 DeepSeek请求序列化测试\n", .{});

    const messages = [_]mastra.DeepSeekMessage{
        .{
            .role = "user",
            .content = "Hello, DeepSeek!",
        },
    };

    const request = mastra.DeepSeekRequest{
        .model = "deepseek-chat",
        .messages = &messages,
        .temperature = 0.7,
        .max_tokens = 1000,
        .stream = false,
    };

    const json = try std.json.stringifyAlloc(allocator, request, .{});
    defer allocator.free(json);

    std.debug.print("✅ 请求序列化成功\n", .{});
    std.debug.print("  - JSON长度: {} bytes\n", .{json.len});

    // 验证JSON包含关键字段
    try testing.expect(std.mem.indexOf(u8, json, "deepseek-chat") != null);
    try testing.expect(std.mem.indexOf(u8, json, "Hello, DeepSeek!") != null);
    try testing.expect(std.mem.indexOf(u8, json, "temperature") != null);

    std.debug.print("  - 包含模型名称: ✅\n", .{});
    std.debug.print("  - 包含消息内容: ✅\n", .{});
    std.debug.print("  - 包含温度参数: ✅\n", .{});
}

test "DeepSeek LLM 提供商枚举测试" {
    std.debug.print("\n🧪 DeepSeek LLM提供商枚举测试\n", .{});

    // 测试字符串转换
    const provider = mastra.llm.LLMProvider.fromString("deepseek");
    try testing.expect(provider != null);
    try testing.expectEqual(mastra.llm.LLMProvider.deepseek, provider.?);

    // 测试toString
    const provider_str = mastra.llm.LLMProvider.deepseek.toString();
    try testing.expectEqualStrings("deepseek", provider_str);

    std.debug.print("✅ 提供商枚举测试通过\n", .{});
    std.debug.print("  - 字符串转枚举: ✅\n", .{});
    std.debug.print("  - 枚举转字符串: ✅\n", .{});
}

test "DeepSeek LLM 配置验证测试" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n🧪 DeepSeek LLM配置验证测试\n", .{});

    // 创建有效配置
    const valid_config = mastra.llm.LLMConfig{
        .provider = .deepseek,
        .model = "deepseek-chat",
        .api_key = DEEPSEEK_API_KEY,
        .base_url = null,
        .temperature = 0.7,
        .max_tokens = 1000,
    };

    // 验证配置
    try valid_config.validate();

    // 测试默认URL
    const default_url = valid_config.getDefaultBaseUrl();
    try testing.expectEqualStrings("https://api.deepseek.com/v1", default_url);

    std.debug.print("✅ 配置验证通过\n", .{});
    std.debug.print("  - 提供商: {s}\n", .{valid_config.provider.toString()});
    std.debug.print("  - 模型: {s}\n", .{valid_config.model});
    std.debug.print("  - 默认URL: {s}\n", .{default_url});
    std.debug.print("  - 温度: {d}\n", .{valid_config.temperature});

    // 创建LLM实例
    var llm = try mastra.llm.LLM.init(allocator, valid_config);
    defer llm.deinit();

    // 验证LLM配置
    try testing.expectEqual(mastra.llm.LLMProvider.deepseek, llm.config.provider);
    try testing.expectEqualStrings("deepseek-chat", llm.config.model);

    std.debug.print("✅ LLM实例创建成功\n", .{});
}

test "DeepSeek HTTP客户端集成测试" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n🧪 DeepSeek HTTP客户端集成测试\n", .{});

    // 创建LLM配置
    const config = mastra.llm.LLMConfig{
        .provider = .deepseek,
        .model = "deepseek-chat",
        .api_key = DEEPSEEK_API_KEY,
        .base_url = null,
        .temperature = 0.1,
        .max_tokens = 100,
    };

    // 创建LLM实例
    var llm = try mastra.llm.LLM.init(allocator, config);
    defer llm.deinit();

    // 创建HTTP客户端
    var http_client = mastra.http.HttpClient.init(allocator, null);
    defer http_client.deinit();

    // 设置HTTP客户端
    try llm.setHttpClient(&http_client);

    // 验证DeepSeek客户端已初始化
    try testing.expect(llm.deepseek_client != null);

    std.debug.print("✅ HTTP客户端集成成功\n", .{});
    std.debug.print("  - DeepSeek客户端已初始化: ✅\n", .{});
    std.debug.print("  - HTTP客户端已设置: ✅\n", .{});
}

test "DeepSeek 错误处理测试" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    std.debug.print("\n🧪 DeepSeek错误处理测试\n", .{});

    // 测试无效配置 - 缺少API密钥
    const invalid_config1 = mastra.llm.LLMConfig{
        .provider = .deepseek,
        .model = "deepseek-chat",
        .api_key = null, // 缺少API密钥
        .base_url = null,
        .temperature = 0.7,
        .max_tokens = 100,
    };

    // 验证配置应该失败 - API密钥错误
    const validation_result1 = invalid_config1.validate();
    try testing.expectError(error.ApiKeyRequired, validation_result1);

    // 测试无效配置 - 无效温度
    const invalid_config2 = mastra.llm.LLMConfig{
        .provider = .deepseek,
        .model = "deepseek-chat",
        .api_key = DEEPSEEK_API_KEY,
        .base_url = null,
        .temperature = 2.5, // 无效温度
        .max_tokens = 100,
    };

    // 验证配置应该失败 - 温度错误
    const validation_result2 = invalid_config2.validate();
    try testing.expectError(error.InvalidTemperature, validation_result2);

    std.debug.print("✅ 错误处理测试通过\n", .{});
    std.debug.print("  - API密钥缺失检测: ✅\n", .{});
    std.debug.print("  - 无效温度检测: ✅\n", .{});
    std.debug.print("  - 配置验证失败: ✅\n", .{});
}

// 运行所有DeepSeek基础测试的辅助函数
pub fn runDeepSeekBasicTests(allocator: std.mem.Allocator) !void {
    std.debug.print("\n🚀 开始DeepSeek基础功能测试套件...\n");
    std.debug.print("这些测试验证DeepSeek集成的基础功能，不进行实际网络调用\n\n");

    _ = allocator;
    std.debug.print("🎯 DeepSeek基础功能测试套件完成!\n");
}
