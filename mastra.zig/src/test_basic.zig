//! 基础功能测试
//! 
//! 测试核心模块的基本功能

const std = @import("std");
const mastra = @import("mastra.zig");

test "Mastra basic initialization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // 测试基本配置
    const config = mastra.Config{
        .enable_event_loop = true,
        .log_level = .info,
    };
    
    var m = try mastra.Mastra.init(allocator, config);
    defer m.deinit();
    
    // 验证基本功能
    try std.testing.expect(m.isRunning() == false);
    try std.testing.expect(m.getEventLoop() != null);
    try std.testing.expect(m.getHttpClient() != null);
}

test "LLM configuration" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // 创建LLM配置
    const llm_config = mastra.llm.LLMConfig{
        .provider = .openai,
        .model = "gpt-4",
        .api_key = "test-key",
        .temperature = 0.7,
    };
    
    var llm = try mastra.llm.LLM.init(allocator, llm_config);
    defer llm.deinit();
    
    // 验证配置
    try std.testing.expect(llm.getProvider() == .openai);
    try std.testing.expectEqualStrings("gpt-4", llm.getModel());
}

test "Agent creation and basic functionality" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // 创建LLM
    const llm_config = mastra.llm.LLMConfig{
        .provider = .openai,
        .model = "gpt-4",
        .api_key = "test-key",
    };
    
    var llm = try mastra.llm.LLM.init(allocator, llm_config);
    defer llm.deinit();
    
    // 创建Agent
    const agent_config = mastra.agent.AgentConfig{
        .name = "test-agent",
        .model = llm,
        .instructions = "You are a helpful assistant",
    };
    
    var agent = try mastra.agent.Agent.init(allocator, agent_config);
    defer agent.deinit();
    
    // 验证Agent属性
    try std.testing.expectEqualStrings("test-agent", agent.name);
    try std.testing.expect(agent.instructions != null);
    try std.testing.expectEqualStrings("You are a helpful assistant", agent.instructions.?);
}

test "HTTP Client basic functionality" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // 创建HTTP客户端
    var client = mastra.http.HttpClient.init(allocator, null);
    defer client.deinit();
    
    // 测试基本功能（不发送真实请求）
    try std.testing.expect(client.allocator.ptr == allocator.ptr);
}

test "Event Loop task scheduling" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var loop = try mastra.EventLoop.init(allocator);
    defer loop.deinit();
    
    // 测试基本功能
    try std.testing.expect(!loop.isRunning());
    
    // 创建简单任务
    var executed = false;
    const TestContext = struct {
        executed: *bool,
        
        fn callback(ctx: ?*anyopaque) !void {
            if (ctx) |c| {
                const test_ctx: *@This() = @ptrCast(@alignCast(c));
                test_ctx.executed.* = true;
            }
        }
    };
    
    var test_ctx = TestContext{ .executed = &executed };
    var task = mastra.EventLoop.Task.init(TestContext.callback, &test_ctx);
    
    // 提交任务
    try loop.submitTask(&task);
    
    // 验证任务已提交
    try std.testing.expect(loop.task_queue.items.len == 1);
}

test "Message and Response structures" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // 测试Message结构
    const message = mastra.Message{
        .role = "user",
        .content = "Hello, world!",
        .metadata = null,
    };
    
    try std.testing.expectEqualStrings("user", message.role);
    try std.testing.expectEqualStrings("Hello, world!", message.content);
    
    // 测试AgentResponse结构
    const response_content = try allocator.dupe(u8, "Hello! How can I help you?");
    defer allocator.free(response_content);
    
    const response = mastra.AgentResponse{
        .content = response_content,
        .usage = null,
        .metadata = null,
    };
    
    try std.testing.expectEqualStrings("Hello! How can I help you?", response.content);
}

test "Tool system basic functionality" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // 创建工具schema
    const tool_schema = mastra.tools.ToolSchema{
        .name = "test_tool",
        .description = "A test tool",
        .parameters = null,
    };
    
    // 简单的工具执行函数
    const TestTool = struct {
        fn execute(input: mastra.tools.ToolInput) mastra.tools.ToolOutput {
            _ = input;
            return mastra.tools.ToolOutput{
                .success = true,
                .result = "Tool executed successfully",
                .error_message = null,
            };
        }
    };
    
    var tool = try mastra.tools.Tool.init(allocator, tool_schema, TestTool.execute);
    defer tool.deinit();
    
    // 测试工具执行
    const input = mastra.tools.ToolInput{
        .parameters = null,
        .context = null,
    };
    
    const output = tool.execute(input);
    try std.testing.expect(output.success);
    try std.testing.expectEqualStrings("Tool executed successfully", output.result);
}

test "Workflow basic structure" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // 创建工作流配置
    const workflow_config = mastra.workflow.WorkflowConfig{
        .id = "test-workflow",
        .name = "Test Workflow",
        .description = "A test workflow",
        .steps = std.ArrayList(mastra.workflow.StepConfig).init(allocator),
    };
    
    var workflow = try mastra.workflow.Workflow.init(allocator, workflow_config);
    defer workflow.deinit();
    
    // 验证工作流属性
    try std.testing.expectEqualStrings("test-workflow", workflow.id);
    try std.testing.expectEqualStrings("Test Workflow", workflow.name);
}

test "Memory system basic functionality" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // 创建内存配置
    const memory_config = mastra.memory.MemoryConfig{
        .max_messages = 100,
        .enable_semantic_search = false,
    };
    
    var memory = try mastra.memory.Memory.init(allocator, memory_config);
    defer memory.deinit();
    
    // 测试添加消息
    const message = mastra.Message{
        .role = "user",
        .content = "Test message",
        .metadata = null,
    };
    
    try memory.addMessage(message);
    
    // 验证消息已添加
    const messages = try memory.getMessages();
    try std.testing.expect(messages.len == 1);
    try std.testing.expectEqualStrings("Test message", messages[0].content);
}
