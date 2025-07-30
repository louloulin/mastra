const std = @import("std");
const testing = std.testing;
const cli = @import("cli");

test "CLI generate type enum" {
    // 测试生成类型转换
    const agent = cli.Cli.GenerateType.fromString("agent");
    try testing.expect(agent != null);
    try testing.expect(agent.? == .agent);
    
    const workflow = cli.Cli.GenerateType.fromString("workflow");
    try testing.expect(workflow != null);
    try testing.expect(workflow.? == .workflow);
    
    const tool = cli.Cli.GenerateType.fromString("tool");
    try testing.expect(tool != null);
    try testing.expect(tool.? == .tool);
    
    const rag = cli.Cli.GenerateType.fromString("rag");
    try testing.expect(rag != null);
    try testing.expect(rag.? == .rag);
    
    const middleware = cli.Cli.GenerateType.fromString("middleware");
    try testing.expect(middleware != null);
    try testing.expect(middleware.? == .middleware);
    
    const test_type = cli.Cli.GenerateType.fromString("test");
    try testing.expect(test_type != null);
    try testing.expect(test_type.? == .@"test");
    
    // 测试未知类型
    const unknown = cli.Cli.GenerateType.fromString("unknown");
    try testing.expect(unknown == null);
}

test "CLI generate type toString" {
    try testing.expectEqualStrings("agent", cli.Cli.GenerateType.agent.toString());
    try testing.expectEqualStrings("workflow", cli.Cli.GenerateType.workflow.toString());
    try testing.expectEqualStrings("tool", cli.Cli.GenerateType.tool.toString());
    try testing.expectEqualStrings("rag", cli.Cli.GenerateType.rag.toString());
    try testing.expectEqualStrings("middleware", cli.Cli.GenerateType.middleware.toString());
    try testing.expectEqualStrings("test", cli.Cli.GenerateType.@"test".toString());
}

test "CLI generate type descriptions" {
    const agent_desc = cli.Cli.GenerateType.agent.getDescription();
    try testing.expect(std.mem.indexOf(u8, agent_desc, "智能代理") != null);
    
    const workflow_desc = cli.Cli.GenerateType.workflow.getDescription();
    try testing.expect(std.mem.indexOf(u8, workflow_desc, "工作流") != null);
    
    const tool_desc = cli.Cli.GenerateType.tool.getDescription();
    try testing.expect(std.mem.indexOf(u8, tool_desc, "工具函数") != null);
    
    const rag_desc = cli.Cli.GenerateType.rag.getDescription();
    try testing.expect(std.mem.indexOf(u8, rag_desc, "检索增强") != null);
    
    const middleware_desc = cli.Cli.GenerateType.middleware.getDescription();
    try testing.expect(std.mem.indexOf(u8, middleware_desc, "中间件") != null);
    
    const test_desc = cli.Cli.GenerateType.@"test".getDescription();
    try testing.expect(std.mem.indexOf(u8, test_desc, "测试文件") != null);
}

test "CLI generate command basic options" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var cli_instance = try cli.Cli.init(allocator, null);
    defer cli_instance.deinit();

    // 测试基础生成命令
    var basic_args = [_][]const u8{ "generate", "agent" };
    try cli_instance.parseArgs(&basic_args);
    
    try testing.expect(cli_instance.args.command == .generate);
    try testing.expectEqualStrings("agent", cli_instance.args.positional_args[0]);
}

test "CLI generate command with name" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var cli_instance = try cli.Cli.init(allocator, null);
    defer cli_instance.deinit();

    // 测试带名称的生成命令
    var name_args = [_][]const u8{ "generate", "workflow", "--name", "MyWorkflow" };
    try cli_instance.parseArgs(&name_args);
    
    try testing.expect(cli_instance.args.command == .generate);
    try testing.expectEqualStrings("workflow", cli_instance.args.positional_args[0]);
    try testing.expectEqualStrings("MyWorkflow", cli_instance.args.getFlag("name").?);
}

test "CLI generate command with output directory" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var cli_instance = try cli.Cli.init(allocator, null);
    defer cli_instance.deinit();

    // 测试带输出目录的生成命令
    var output_args = [_][]const u8{ "generate", "tool", "--name", "MyTool", "--output", "lib" };
    try cli_instance.parseArgs(&output_args);
    
    try testing.expect(cli_instance.args.command == .generate);
    try testing.expectEqualStrings("tool", cli_instance.args.positional_args[0]);
    try testing.expectEqualStrings("MyTool", cli_instance.args.getFlag("name").?);
    try testing.expectEqualStrings("lib", cli_instance.args.getFlag("output").?);
}

test "CLI generate command with test option" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var cli_instance = try cli.Cli.init(allocator, null);
    defer cli_instance.deinit();

    // 测试带测试选项的生成命令
    var test_args = [_][]const u8{ "generate", "rag", "--name", "MyRAG", "--with-test" };
    try cli_instance.parseArgs(&test_args);
    
    try testing.expect(cli_instance.args.command == .generate);
    try testing.expectEqualStrings("rag", cli_instance.args.positional_args[0]);
    try testing.expectEqualStrings("MyRAG", cli_instance.args.getFlag("name").?);
    try testing.expect(cli_instance.args.hasFlag("with-test"));
}

test "CLI generate command comprehensive options" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var cli_instance = try cli.Cli.init(allocator, null);
    defer cli_instance.deinit();

    // 测试综合生成选项
    var comprehensive_args = [_][]const u8{ 
        "generate", "middleware", 
        "--name", "AuthMiddleware",
        "--output", "middleware",
        "--with-test"
    };
    try cli_instance.parseArgs(&comprehensive_args);
    
    try testing.expect(cli_instance.args.command == .generate);
    try testing.expectEqualStrings("middleware", cli_instance.args.positional_args[0]);
    try testing.expectEqualStrings("AuthMiddleware", cli_instance.args.getFlag("name").?);
    try testing.expectEqualStrings("middleware", cli_instance.args.getFlag("output").?);
    try testing.expect(cli_instance.args.hasFlag("with-test"));
}

test "CLI generate test type" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var cli_instance = try cli.Cli.init(allocator, null);
    defer cli_instance.deinit();

    // 测试生成测试文件
    var test_args = [_][]const u8{ "generate", "test", "--name", "MyTest", "--output", "test" };
    try cli_instance.parseArgs(&test_args);
    
    try testing.expect(cli_instance.args.command == .generate);
    try testing.expectEqualStrings("test", cli_instance.args.positional_args[0]);
    try testing.expectEqualStrings("MyTest", cli_instance.args.getFlag("name").?);
    try testing.expectEqualStrings("test", cli_instance.args.getFlag("output").?);
}

test "CLI generate error handling" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var cli_instance = try cli.Cli.init(allocator, null);
    defer cli_instance.deinit();

    // 测试无参数的生成命令（这里只测试解析不会崩溃）
    var no_args = [_][]const u8{"generate"};
    try cli_instance.parseArgs(&no_args);
    
    try testing.expect(cli_instance.args.command == .generate);
    try testing.expect(cli_instance.args.positional_args.len == 0);
}

test "CLI generate all types parsing" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const types = [_][]const u8{ "agent", "workflow", "tool", "rag", "middleware", "test" };
    
    for (types) |gen_type| {
        var cli_instance = try cli.Cli.init(allocator, null);
        defer cli_instance.deinit();

        var args = [_][]const u8{ "generate", gen_type, "--name", "TestName" };
        try cli_instance.parseArgs(&args);
        
        try testing.expect(cli_instance.args.command == .generate);
        try testing.expectEqualStrings(gen_type, cli_instance.args.positional_args[0]);
        try testing.expectEqualStrings("TestName", cli_instance.args.getFlag("name").?);
    }
}
