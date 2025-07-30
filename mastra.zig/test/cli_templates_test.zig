const std = @import("std");
const testing = std.testing;
const cli = @import("cli");

test "CLI project template types" {
    // 测试模板类型转换
    const basic = cli.Cli.ProjectTemplate.fromString("basic");
    try testing.expect(basic == .basic);

    const agent = cli.Cli.ProjectTemplate.fromString("agent");
    try testing.expect(agent == .agent);

    const workflow = cli.Cli.ProjectTemplate.fromString("workflow");
    try testing.expect(workflow == .workflow);

    const rag = cli.Cli.ProjectTemplate.fromString("rag");
    try testing.expect(rag == .rag);

    const tools = cli.Cli.ProjectTemplate.fromString("tools");
    try testing.expect(tools == .tools);

    // 测试未知模板默认为basic
    const unknown = cli.Cli.ProjectTemplate.fromString("unknown");
    try testing.expect(unknown == .basic);
}

test "CLI project template toString" {
    try testing.expectEqualStrings("basic", cli.Cli.ProjectTemplate.basic.toString());
    try testing.expectEqualStrings("agent", cli.Cli.ProjectTemplate.agent.toString());
    try testing.expectEqualStrings("workflow", cli.Cli.ProjectTemplate.workflow.toString());
    try testing.expectEqualStrings("rag", cli.Cli.ProjectTemplate.rag.toString());
    try testing.expectEqualStrings("tools", cli.Cli.ProjectTemplate.tools.toString());
}

test "CLI init command with different templates" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 测试基础模板
    var cli_instance = try cli.Cli.init(allocator, null);
    defer cli_instance.deinit();

    var basic_args = [_][]const u8{ "init", "test-basic", "--template", "basic" };
    try cli_instance.parseArgs(&basic_args);

    try testing.expect(cli_instance.args.command == .init);
    try testing.expectEqualStrings("test-basic", cli_instance.args.positional_args[0]);
    try testing.expectEqualStrings("basic", cli_instance.args.getFlag("template").?);

    // 测试Agent模板
    var cli_instance2 = try cli.Cli.init(allocator, null);
    defer cli_instance2.deinit();

    var agent_args = [_][]const u8{ "init", "test-agent", "--template", "agent", "--llm", "openai" };
    try cli_instance2.parseArgs(&agent_args);

    try testing.expect(cli_instance2.args.command == .init);
    try testing.expectEqualStrings("test-agent", cli_instance2.args.positional_args[0]);
    try testing.expectEqualStrings("agent", cli_instance2.args.getFlag("template").?);
    try testing.expectEqualStrings("openai", cli_instance2.args.getFlag("llm").?);
}

test "CLI init command with workflow template" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var cli_instance = try cli.Cli.init(allocator, null);
    defer cli_instance.deinit();

    var workflow_args = [_][]const u8{ "init", "test-workflow", "--template", "workflow", "--llm", "anthropic", "--storage", "postgres" };
    try cli_instance.parseArgs(&workflow_args);

    try testing.expect(cli_instance.args.command == .init);
    try testing.expectEqualStrings("test-workflow", cli_instance.args.positional_args[0]);
    try testing.expectEqualStrings("workflow", cli_instance.args.getFlag("template").?);
    try testing.expectEqualStrings("anthropic", cli_instance.args.getFlag("llm").?);
    try testing.expectEqualStrings("postgres", cli_instance.args.getFlag("storage").?);
}

test "CLI init command with RAG template" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var cli_instance = try cli.Cli.init(allocator, null);
    defer cli_instance.deinit();

    var rag_args = [_][]const u8{ "init", "test-rag", "--template", "rag", "--llm", "google", "--storage", "pinecone" };
    try cli_instance.parseArgs(&rag_args);

    try testing.expect(cli_instance.args.command == .init);
    try testing.expectEqualStrings("test-rag", cli_instance.args.positional_args[0]);
    try testing.expectEqualStrings("rag", cli_instance.args.getFlag("template").?);
    try testing.expectEqualStrings("google", cli_instance.args.getFlag("llm").?);
    try testing.expectEqualStrings("pinecone", cli_instance.args.getFlag("storage").?);
}

test "CLI init command with tools template" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var cli_instance = try cli.Cli.init(allocator, null);
    defer cli_instance.deinit();

    var tools_args = [_][]const u8{ "init", "test-tools", "--template", "tools", "--llm", "deepseek", "--storage", "mongodb" };
    try cli_instance.parseArgs(&tools_args);

    try testing.expect(cli_instance.args.command == .init);
    try testing.expectEqualStrings("test-tools", cli_instance.args.positional_args[0]);
    try testing.expectEqualStrings("tools", cli_instance.args.getFlag("template").?);
    try testing.expectEqualStrings("deepseek", cli_instance.args.getFlag("llm").?);
    try testing.expectEqualStrings("mongodb", cli_instance.args.getFlag("storage").?);
}

test "CLI template content generation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var cli_instance = try cli.Cli.init(allocator, null);
    defer cli_instance.deinit();

    // 测试基础模板内容生成
    const basic_content = try cli_instance.createBasicMainContent("openai", "memory");
    defer allocator.free(basic_content);

    try testing.expect(std.mem.indexOf(u8, basic_content, "基础应用") != null);
    try testing.expect(std.mem.indexOf(u8, basic_content, "const std = @import") != null);

    // 测试Agent模板内容生成
    const agent_content = try cli_instance.createAgentMainContent("anthropic", "postgres");
    defer allocator.free(agent_content);

    try testing.expect(std.mem.indexOf(u8, agent_content, "Agent 应用") != null);
    try testing.expect(std.mem.indexOf(u8, agent_content, "const std = @import") != null);
}

test "CLI help shows template options" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var cli_instance = try cli.Cli.init(allocator, null);
    defer cli_instance.deinit();

    var help_args = [_][]const u8{"help"};
    try cli_instance.parseArgs(&help_args);

    try testing.expect(cli_instance.args.command == .help);

    // 这里只测试不会崩溃，实际的帮助输出会打印到stdout
    // 在实际使用中，用户会看到模板选项的说明
}
