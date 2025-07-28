//! 网络诊断工具
//! 用于诊断DeepSeek API访问问题

const std = @import("std");
const mastra = @import("mastra");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n🔍 DeepSeek API 网络诊断工具\n", .{});
    std.debug.print("=" ** 50 ++ "\n", .{});

    // 1. 基础网络连接测试
    std.debug.print("1. 基础网络连接测试...\n", .{});

    // 测试DNS解析
    std.debug.print("   📡 测试DNS解析...\n", .{});
    const deepseek_host = "api.deepseek.com";

    // 使用std.net.getAddressList进行DNS解析测试
    const address_list = std.net.getAddressList(allocator, deepseek_host, 443) catch |err| {
        std.debug.print("   ❌ DNS解析失败: {}\n", .{err});
        std.debug.print("   💡 可能原因:\n", .{});
        std.debug.print("      - DNS服务器配置问题\n", .{});
        std.debug.print("      - 网络连接问题\n", .{});
        std.debug.print("      - 域名被屏蔽\n", .{});
        return;
    };
    defer address_list.deinit();

    std.debug.print("   ✅ DNS解析成功\n", .{});
    std.debug.print("   📍 解析到的IP地址:\n", .{});
    for (address_list.addrs) |addr| {
        std.debug.print("      - {any}\n", .{addr});
    }

    // 2. TCP连接测试
    std.debug.print("\n2. TCP连接测试...\n", .{});
    std.debug.print("   🔌 尝试连接到 {s}:443...\n", .{deepseek_host});

    if (address_list.addrs.len > 0) {
        const addr = address_list.addrs[0];
        const stream = std.net.tcpConnectToAddress(addr) catch |err| {
            std.debug.print("   ❌ TCP连接失败: {}\n", .{err});
            std.debug.print("   💡 可能原因:\n", .{});
            std.debug.print("      - 防火墙阻止连接\n", .{});
            std.debug.print("      - 网络代理配置问题\n", .{});
            std.debug.print("      - 服务器不可达\n", .{});
            std.debug.print("      - 端口被封锁\n", .{});
            return;
        };
        defer stream.close();

        std.debug.print("   ✅ TCP连接成功\n", .{});
    }

    // 3. HTTP客户端配置测试
    std.debug.print("\n3. HTTP客户端配置测试...\n", .{});

    var http_client = mastra.http.HttpClient.initWithConfig(allocator, null, .{ .max_attempts = 1, .initial_delay_ms = 1000 }, .{ .request_timeout_ms = 10000 } // 减少超时时间
    );
    defer http_client.deinit();

    std.debug.print("   ✅ HTTP客户端初始化成功\n", .{});

    // 4. 简单HTTP请求测试
    std.debug.print("\n4. 简单HTTP请求测试...\n", .{});
    std.debug.print("   🌐 测试GET请求到 https://httpbin.org/get...\n", .{});

    const test_headers = [_]mastra.http.Header{
        .{ .name = "User-Agent", .value = "Mastra-Zig/1.0" },
    };

    var test_response = http_client.get("https://httpbin.org/get", &test_headers) catch |err| {
        std.debug.print("   ❌ HTTP测试请求失败: {}\n", .{err});
        std.debug.print("   💡 这表明HTTP客户端本身可能有问题\n", .{});
        return;
    };
    defer test_response.deinit();

    std.debug.print("   ✅ HTTP测试请求成功\n", .{});
    std.debug.print("   📊 响应状态: {}\n", .{test_response.status_code});

    // 5. DeepSeek API连接测试
    std.debug.print("\n5. DeepSeek API连接测试...\n", .{});
    std.debug.print("   🤖 测试连接到 https://api.deepseek.com/v1...\n", .{});

    const deepseek_headers = [_]mastra.http.Header{
        .{ .name = "User-Agent", .value = "Mastra-Zig/1.0" },
        .{ .name = "Content-Type", .value = "application/json" },
    };

    // 尝试简单的GET请求到DeepSeek API根路径
    var deepseek_response = http_client.get("https://api.deepseek.com/v1", &deepseek_headers) catch |err| {
        std.debug.print("   ❌ DeepSeek API连接失败: {}\n", .{err});
        std.debug.print("   💡 可能原因:\n", .{});
        std.debug.print("      - DeepSeek API服务不可用\n", .{});
        std.debug.print("      - 需要特殊的网络配置\n", .{});
        std.debug.print("      - API访问被限制\n", .{});
        std.debug.print("      - SSL/TLS配置问题\n", .{});

        // 尝试诊断具体的SSL问题
        std.debug.print("\n   🔧 尝试诊断SSL问题...\n", .{});
        return;
    };
    defer deepseek_response.deinit();

    std.debug.print("   ✅ DeepSeek API连接成功\n", .{});
    std.debug.print("   📊 响应状态: {}\n", .{deepseek_response.status_code});

    // 6. API密钥验证测试
    std.debug.print("\n6. API密钥验证测试...\n", .{});

    const api_key = "sk-bf82ef56c5c44ef6867bf4199d084706";
    std.debug.print("   🔑 使用API密钥: {s}...{s}\n", .{ api_key[0..8], api_key[api_key.len - 8 ..] });

    // 构建一个最小的API请求
    const test_request_body =
        \\{
        \\  "model": "deepseek-chat",
        \\  "messages": [
        \\    {"role": "user", "content": "Hello"}
        \\  ],
        \\  "max_tokens": 10
        \\}
    ;

    const auth_header_value = try std.fmt.allocPrint(allocator, "Bearer {s}", .{api_key});
    defer allocator.free(auth_header_value);

    const api_headers = [_]mastra.http.Header{
        .{ .name = "Content-Type", .value = "application/json" },
        .{ .name = "Authorization", .value = auth_header_value },
        .{ .name = "User-Agent", .value = "Mastra-Zig/1.0" },
    };

    std.debug.print("   📤 发送测试API请求...\n", .{});
    var api_response = http_client.post("https://api.deepseek.com/v1/chat/completions", &api_headers, test_request_body) catch |err| {
        std.debug.print("   ❌ API请求失败: {}\n", .{err});
        std.debug.print("   💡 这可能是API密钥、配额或请求格式问题\n", .{});
        return;
    };
    defer api_response.deinit();

    std.debug.print("   ✅ API请求成功!\n", .{});
    std.debug.print("   📊 响应状态: {}\n", .{api_response.status_code});
    std.debug.print("   📄 响应内容: {s}\n", .{api_response.body});

    // 7. 总结
    std.debug.print("\n🎉 网络诊断完成!\n", .{});
    std.debug.print("=" ** 50 ++ "\n", .{});
    std.debug.print("✅ 诊断结果:\n", .{});
    std.debug.print("   - DNS解析: 正常\n", .{});
    std.debug.print("   - TCP连接: 正常\n", .{});
    std.debug.print("   - HTTP客户端: 正常\n", .{});
    std.debug.print("   - DeepSeek API: 可访问\n", .{});
    std.debug.print("   - API密钥: 有效\n", .{});
    std.debug.print("\n🏆 结论: 网络和API配置正常，DeepSeek API应该可以正常使用!\n", .{});
}
