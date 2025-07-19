const std = @import("std");
const testing = std.testing;
const mastra = @import("mastra");

test "Mastra initialization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    
    const allocator = gpa.allocator();
    
    var m = try mastra.Mastra.init(allocator, .{});
    defer m.deinit();
    
    try testing.expect(m.agents.count() == 0);
    try testing.expect(m.workflows.count() == 0);
}

test "Agent creation and registration" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    
    const allocator = gpa.allocator();
    
    var m = try mastra.Mastra.init(allocator, .{});
    defer m.deinit();
    
    const llm_config = mastra.llm.LLMConfig{
        .provider = .openai,
        .model = "gpt-3.5-turbo",
    };
    
    var llm = try mastra.llm.LLM.init(allocator, llm_config);
    defer llm.deinit();
    
    const agent_config = mastra.agent.AgentConfig{
        .name = "test_agent",
        .model = llm,
    };
    
    var agent = try mastra.agent.Agent.init(allocator, agent_config);
    defer agent.deinit();
    
    try m.registerAgent("test_agent", agent);
    try testing.expect(m.getAgent("test_agent") != null);
}

test "Workflow creation and execution" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    
    const allocator = gpa.allocator();
    
    var m = try mastra.Mastra.init(allocator, .{});
    defer m.deinit();
    
    const step_config = mastra.workflow.StepConfig{
        .id = "test_step",
        .name = "Test Step",
    };
    
    const workflow_config = mastra.workflow.WorkflowConfig{
        .id = "test_workflow",
        .name = "Test Workflow",
        .steps = &[_]mastra.workflow.StepConfig{step_config},
    };
    
    var workflow = try mastra.workflow.Workflow.init(allocator, workflow_config, m.getLogger());
    defer workflow.deinit();
    
    _ = workflow.setStepExecutor("test_step", testStepExecutor);
    
    const result = try workflow.execute(std.json.Value{ .object = std.json.ObjectMap.init(allocator) });
    defer result.deinit();
    
    try testing.expect(result.status == .completed);
    try testing.expect(result.getStepResult("test_step") != null);
}

test "Tool creation and execution" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    
    const allocator = gpa.allocator();
    
    const tool_schema = mastra.tools.ToolSchema{
        .name = "test_tool",
        .description = "A test tool",
        .inputs = &[_]mastra.tools.ToolInput{
            .{ .name = "input", .description = "Test input", .required = true },
        },
        .output = "Test output",
    };
    
    const tool = try mastra.tools.Tool.init(allocator, tool_schema, testToolExecutor);
    defer tool.deinit();
    
    var params = std.json.ObjectMap.init(allocator);
    try params.put("input", std.json.Value{ .string = "test" });
    
    const result = try tool.executeTool(std.json.Value{ .object = params });
    defer result.deinit();
    
    try testing.expect(std.mem.eql(u8, result.content, "test_processed"));
}

test "Memory operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    
    const allocator = gpa.allocator();
    
    const memory_config = mastra.memory.MemoryConfig{
        .max_messages = 10,
    };
    
    var memory = try mastra.memory.Memory.init(allocator, memory_config);
    defer memory.deinit();
    
    try memory.addMessage(.{ .role = "user", .content = "Hello" });
    try memory.addMessage(.{ .role = "assistant", .content = "Hi there" });
    
    const messages = memory.getMessages(null);
    try testing.expect(messages.len == 2);
    try testing.expect(std.mem.eql(u8, messages[0].role, "user"));
    try testing.expect(std.mem.eql(u8, messages[1].role, "assistant"));
}

test "Vector store operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    
    const allocator = gpa.allocator();
    
    const vector_config = mastra.vector.VectorStoreConfig{
        .type = .memory,
        .dimension = 3,
    };
    
    var vector_store = try mastra.vector.VectorStore.init(allocator, vector_config);
    defer vector_store.deinit();
    
    const embedding1 = [_]f32{ 1.0, 2.0, 3.0 };
    const embedding2 = [_]f32{ 4.0, 5.0, 6.0 };
    
    const doc1 = mastra.vector.VectorDocument{
        .id = "doc1",
        .content = "Test document 1",
        .embedding = &embedding1,
    };
    
    const doc2 = mastra.vector.VectorDocument{
        .id = "doc2",
        .content = "Test document 2",
        .embedding = &embedding2,
    };
    
    try vector_store.upsert(&[_]mastra.vector.VectorDocument{ doc1, doc2 });
    
    const query = mastra.vector.VectorQuery{
        .vector = &embedding1,
        .limit = 5,
    };
    
    const results = try vector_store.search(query);
    defer {
        for (results) |doc| {
            allocator.free(doc.embedding);
        }
        allocator.free(results);
    }
    
    try testing.expect(results.len > 0);
}

fn testStepExecutor(allocator: std.mem.Allocator, _input: std.json.Value) !std.json.Value {
    _ = _input;
    return std.json.Value{ .string = "test_result" };
}

fn testToolExecutor(allocator: std.mem.Allocator, params: std.json.Value) !mastra.tools.ToolOutput {
    const input = params.object.get("input") orelse return error.MissingInput;
    const input_str = input.string;
    
    const result = try std.fmt.allocPrint(allocator, "{s}_processed", .{input_str});
    return mastra.tools.ToolOutput{ .content = result };
}