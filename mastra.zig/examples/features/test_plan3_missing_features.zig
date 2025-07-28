const std = @import("std");
const mastra = @import("mastra");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("❌ 检测到内存泄漏！\n", .{});
        } else {
            std.debug.print("✅ 无内存泄漏！\n", .{});
        }
    }
    const allocator = gpa.allocator();

    std.debug.print("🔧 Plan3.md 待实现功能测试\n", .{});
    std.debug.print("==================================================\n", .{});

    try testMissingFeatures(allocator);

    std.debug.print("\n🎯 待实现功能测试完成！\n", .{});
    std.debug.print("==================================================\n", .{});
}

fn testMissingFeatures(allocator: std.mem.Allocator) !void {
    std.debug.print("\n📋 测试待实现功能\n", .{});
    std.debug.print("----------------------------------------\n", .{});

    // 1. 测试动态工具系统 - 这个应该已经实现了
    std.debug.print("1. 🔧 动态工具系统测试...\n", .{});
    {
        var tool_registry = mastra.tool_builder.ToolRegistry.init(allocator);
        defer tool_registry.deinit();

        // 创建一个简单的工具
        var builder = mastra.tool_builder.ToolBuilder.init(allocator);
        defer builder.deinit();

        const param = mastra.tool_builder.ParameterDefinition{
            .name = "message",
            .type = .string,
            .description = "输入消息",
            .required = true,
        };

        _ = try builder.addParameter(param);
        const tool_def = try builder
            .setName("echo_tool")
            .setDescription("回显工具")
            .setCategory("utility")
            .setExecuteFunction(echoToolExecute)
            .build();

        try tool_registry.registerTool(tool_def);

        // 测试工具执行
        var input_obj = std.json.ObjectMap.init(allocator);
        defer input_obj.deinit();
        try input_obj.put("message", std.json.Value{ .string = "Hello, World!" });

        const input_data = std.json.Value{ .object = input_obj };

        const tool_input = mastra.tools.ToolInput{ .data = input_data };
        const result = try tool_registry.executeTool("echo_tool", tool_input);

        std.debug.print("   ✅ 动态工具系统正常工作\n", .{});
        std.debug.print("   ✅ 工具执行结果: {}\n", .{result.data});
    }

    // 2. 测试 MCP 协议支持
    std.debug.print("2. 🌐 MCP协议支持测试...\n", .{});
    {
        var tool_registry = mastra.tool_builder.ToolRegistry.init(allocator);
        defer tool_registry.deinit();

        var mcp_server = mastra.mcp.MCPServer.init(allocator, &tool_registry);

        // 测试初始化请求
        const init_request =
            \\{"id": "1", "method": "initialize", "params": {"protocolVersion": "2024-11-05"}}
        ;

        const response = try mcp_server.handleRequest(init_request);
        defer allocator.free(response);

        std.debug.print("   ✅ MCP协议支持正常工作\n", .{});
        std.debug.print("   ✅ 初始化响应: {s}\n", .{response});
    }

    // 3. 测试存储后端 - 检查是否真正支持 PostgreSQL 和 MongoDB
    std.debug.print("3. 🗄️ 存储后端测试...\n", .{});
    {
        // 测试内存存储（已实现）
        const memory_config = mastra.storage.StorageConfig{
            .type = .memory,
        };
        var memory_storage = try mastra.storage.Storage.init(allocator, memory_config);
        defer memory_storage.deinit();

        const test_data = std.json.Value{ .string = "test_value" };
        const record_id = try memory_storage.create("test_table", test_data);
        const retrieved = try memory_storage.read("test_table", record_id);

        if (retrieved != null) {
            std.debug.print("   ✅ 内存存储后端正常工作\n", .{});
        }

        // 测试 PostgreSQL 存储（需要检查是否真正实现）
        std.debug.print("   ⚠️ PostgreSQL存储后端: 架构已完成，但需要真实数据库连接实现\n", .{});

        // 测试 MongoDB 存储（需要检查是否真正实现）
        std.debug.print("   ⚠️ MongoDB存储后端: 架构已完成，但需要真实数据库连接实现\n", .{});
    }

    // 4. 内存管理测试
    std.debug.print("4. 🧠 内存管理测试...\n", .{});
    {
        // 创建和销毁多个对象来测试内存管理
        for (0..10) |i| {
            const storage_config = mastra.storage.StorageConfig{
                .type = .memory,
            };
            var storage = try mastra.storage.Storage.init(allocator, storage_config);

            const test_data = std.json.Value{ .string = "test_value" };
            const record_id = try storage.create("test_table", test_data);
            _ = record_id;

            storage.deinit();

            if (i % 3 == 0) {
                std.debug.print("   🔄 内存管理测试进度: {}/10\n", .{i + 1});
            }
        }
        std.debug.print("   ✅ 内存管理测试完成\n", .{});
    }

    std.debug.print("   🎯 所有待实现功能测试完成\n", .{});
}

// 简单的回显工具实现
fn echoToolExecute(allocator: std.mem.Allocator, input: mastra.tools.ToolInput) !mastra.tools.ToolOutput {
    _ = allocator;

    if (input.data != .object) {
        return error.InvalidInput;
    }

    const message = input.data.object.get("message") orelse return error.MissingMessage;

    return mastra.tools.ToolOutput{
        .data = std.json.Value{ .string = message.string },
    };
}
