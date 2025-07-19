const std = @import("std");
const mastra = @import("mastra");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    
    const allocator = gpa.allocator();
    
    // Initialize Mastra
    var m = try mastra.Mastra.init(allocator, .{});
    defer m.deinit();
    
    std.debug.print("Mastra initialized successfully\n", .{});
    
    // Create an LLM
    const llm_config = mastra.llm.LLMConfig{
        .provider = .openai,
        .model = "gpt-3.5-turbo",
    };
    
    var llm = try mastra.llm.LLM.init(allocator, llm_config);
    defer llm.deinit();
    
    // Create a simple tool
    const tool_schema = mastra.tools.ToolSchema{
        .name = "calculator",
        .description = "A simple calculator tool",
        .inputs = &[_]mastra.tools.ToolInput{
            .{ .name = "operation", .description = "The operation to perform", .required = true },
            .{ .name = "a", .description = "First number", .required = true },
            .{ .name = "b", .description = "Second number", .required = true },
        },
        .output = "The result of the calculation",
    };
    
    const calculator = try mastra.tools.Tool.init(allocator, tool_schema, calculatorExecute);
    defer calculator.deinit();
    
    // Create an agent
    const agent_config = mastra.agent.AgentConfig{
        .name = "math_assistant",
        .model = llm,
        .instructions = "You are a helpful math assistant. Use the calculator tool when needed.",
    };
    
    var agent = try mastra.agent.Agent.init(allocator, agent_config);
    defer agent.deinit();
    
    try agent.addTool(calculator);
    
    // Register agent with Mastra
    try m.registerAgent("math_assistant", agent);
    
    // Create a workflow
    const step1 = mastra.workflow.StepConfig{
        .id = "step1",
        .name = "Calculate sum",
        .description = "Calculate 15 + 27",
    };
    
    const step2 = mastra.workflow.StepConfig{
        .id = "step2",
        .name = "Calculate product",
        .description = "Calculate 8 * 12",
    };
    
    const workflow_config = mastra.workflow.WorkflowConfig{
        .id = "math_workflow",
        .name = "Math Operations Workflow",
        .steps = &[_]mastra.workflow.StepConfig{ step1, step2 },
    };
    
    var workflow = try mastra.workflow.Workflow.init(allocator, workflow_config, m.getLogger());
    defer workflow.deinit();
    
    _ = workflow.setStepExecutor("step1", step1Executor);
    _ = workflow.setStepExecutor("step2", step2Executor);
    
    try m.registerWorkflow("math_workflow", workflow);
    
    // Execute workflow
    const workflow_result = try workflow.execute(std.json.Value{ .object = std.json.ObjectMap.init(allocator) });
    defer workflow_result.deinit();
    
    std.debug.print("Workflow completed with status: {s}\n", .{@tagName(workflow_result.status)});
    
    // Test agent
    const messages = [_]mastra.agent.Message{
        .{ .role = "user", .content = "What is 25 * 4?" },
    };
    
    const response = try agent.generate(&messages);
    defer response.deinit();
    
    std.debug.print("Agent response: {s}\n", .{response.content});
}

fn calculatorExecute(allocator: std.mem.Allocator, params: std.json.Value) !mastra.tools.ToolOutput {
    const operation = params.object.get("operation") orelse return error.MissingOperation;
    const a = params.object.get("a") orelse return error.MissingA;
    const b = params.object.get("b") orelse return error.MissingB;
    
    const op_str = operation.string;
    const num_a = std.fmt.parseFloat(f64, a.string) catch return error.InvalidNumber;
    const num_b = std.fmt.parseFloat(f64, b.string) catch return error.InvalidNumber;
    
    const result = switch (op_str) {
        "add" => num_a + num_b,
        "subtract" => num_a - num_b,
        "multiply" => num_a * num_b,
        "divide" => if (num_b != 0) num_a / num_b else return error.DivisionByZero,
        else => return error.InvalidOperation,
    };
    
    const result_str = try std.fmt.allocPrint(allocator, "{d}", .{result});
    return mastra.tools.ToolOutput{ .content = result_str };
}

fn step1Executor(allocator: std.mem.Allocator, _input: std.json.Value) !std.json.Value {
    _ = _input;
    const result = std.json.Value{ .integer = 42 }; // 15 + 27
    return result;
}

fn step2Executor(allocator: std.mem.Allocator, _input: std.json.Value) !std.json.Value {
    _ = _input;
    const result = std.json.Value{ .integer = 96 }; // 8 * 12
    return result;
}