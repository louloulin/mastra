const std = @import("std");
const testing = std.testing;
const cli = @import("cli");

test "CLI integration - full command parsing" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 测试所有主要命令的解析
    const commands = [_]struct {
        args: []const []const u8,
        expected_command: cli.Command,
    }{
        .{ .args = &[_][]const u8{"init"}, .expected_command = .init },
        .{ .args = &[_][]const u8{"dev"}, .expected_command = .dev },
        .{ .args = &[_][]const u8{"build"}, .expected_command = .build },
        .{ .args = &[_][]const u8{"deploy"}, .expected_command = .deploy },
        .{ .args = &[_][]const u8{"generate"}, .expected_command = .generate },
        .{ .args = &[_][]const u8{"help"}, .expected_command = .help },
        .{ .args = &[_][]const u8{"version"}, .expected_command = .version },
    };

    for (commands) |cmd| {
        var cli_instance = try cli.Cli.init(allocator, null);
        defer cli_instance.deinit();

        var args = std.ArrayList([]const u8).init(allocator);
        defer args.deinit();
        
        for (cmd.args) |arg| {
            try args.append(arg);
        }

        try cli_instance.parseArgs(args.items);
        try testing.expect(cli_instance.args.command == cmd.expected_command);
    }
}

test "CLI integration - command with complex flags" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var cli_instance = try cli.Cli.init(allocator, null);
    defer cli_instance.deinit();

    // 测试复杂的命令行参数组合
    var complex_args = [_][]const u8{
        "init", "my-project",
        "--template", "agent",
        "--llm", "openai",
        "--storage", "postgres",
        "--verbose"
    };
    
    try cli_instance.parseArgs(&complex_args);
    
    try testing.expect(cli_instance.args.command == .init);
    try testing.expectEqualStrings("my-project", cli_instance.args.positional_args[0]);
    try testing.expectEqualStrings("agent", cli_instance.args.getFlag("template").?);
    try testing.expectEqualStrings("openai", cli_instance.args.getFlag("llm").?);
    try testing.expectEqualStrings("postgres", cli_instance.args.getFlag("storage").?);
    try testing.expect(cli_instance.args.hasFlag("verbose"));
}

test "CLI integration - build command with all options" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var cli_instance = try cli.Cli.init(allocator, null);
    defer cli_instance.deinit();

    var build_args = [_][]const u8{
        "build",
        "--mode", "release-fast",
        "--target", "x86_64-linux-gnu",
        "--output", "dist",
        "--parallel", "8",
        "--verbose",
        "--strip",
        "--clean"
    };
    
    try cli_instance.parseArgs(&build_args);
    
    try testing.expect(cli_instance.args.command == .build);
    try testing.expectEqualStrings("release-fast", cli_instance.args.getFlag("mode").?);
    try testing.expectEqualStrings("x86_64-linux-gnu", cli_instance.args.getFlag("target").?);
    try testing.expectEqualStrings("dist", cli_instance.args.getFlag("output").?);
    try testing.expectEqualStrings("8", cli_instance.args.getFlag("parallel").?);
    try testing.expect(cli_instance.args.hasFlag("verbose"));
    try testing.expect(cli_instance.args.hasFlag("strip"));
    try testing.expect(cli_instance.args.hasFlag("clean"));
}

test "CLI integration - dev server command" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var cli_instance = try cli.Cli.init(allocator, null);
    defer cli_instance.deinit();

    var dev_args = [_][]const u8{
        "dev",
        "--port", "3000",
        "--host", "0.0.0.0",
        "--verbose"
    };
    
    try cli_instance.parseArgs(&dev_args);
    
    try testing.expect(cli_instance.args.command == .dev);
    try testing.expectEqualStrings("3000", cli_instance.args.getFlag("port").?);
    try testing.expectEqualStrings("0.0.0.0", cli_instance.args.getFlag("host").?);
    try testing.expect(cli_instance.args.hasFlag("verbose"));
}

test "CLI integration - generate command with all types" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const generate_types = [_][]const u8{ "agent", "workflow", "tool", "rag", "middleware", "test" };
    
    for (generate_types) |gen_type| {
        var cli_instance = try cli.Cli.init(allocator, null);
        defer cli_instance.deinit();

        var generate_args = [_][]const u8{
            "generate", gen_type,
            "--name", "TestComponent",
            "--output", "generated",
            "--with-test"
        };
        
        try cli_instance.parseArgs(&generate_args);
        
        try testing.expect(cli_instance.args.command == .generate);
        try testing.expectEqualStrings(gen_type, cli_instance.args.positional_args[0]);
        try testing.expectEqualStrings("TestComponent", cli_instance.args.getFlag("name").?);
        try testing.expectEqualStrings("generated", cli_instance.args.getFlag("output").?);
        try testing.expect(cli_instance.args.hasFlag("with-test"));
    }
}

test "CLI integration - error handling" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 测试空命令
    {
        var cli_instance = try cli.Cli.init(allocator, null);
        defer cli_instance.deinit();

        var empty_args = [_][]const u8{};
        try cli_instance.parseArgs(&empty_args);
        
        // 应该有默认行为或错误处理
        // 这里只测试不会崩溃
    }

    // 测试未知命令
    {
        var cli_instance = try cli.Cli.init(allocator, null);
        defer cli_instance.deinit();

        var unknown_args = [_][]const u8{"unknown-command"};
        try cli_instance.parseArgs(&unknown_args);
        
        // 应该有错误处理
        // 这里只测试不会崩溃
    }
}

test "CLI integration - memory management" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 测试多次创建和销毁CLI实例
    for (0..10) |i| {
        var cli_instance = try cli.Cli.init(allocator, null);
        defer cli_instance.deinit();

        var test_args = [_][]const u8{
            "generate", "agent",
            "--name", "TestAgent",
            "--output", "test"
        };
        
        try cli_instance.parseArgs(&test_args);
        
        try testing.expect(cli_instance.args.command == .generate);
        try testing.expectEqualStrings("agent", cli_instance.args.positional_args[0]);
        
        _ = i; // 使用循环变量避免警告
    }
}

test "CLI integration - flag parsing edge cases" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 测试重复标志
    {
        var cli_instance = try cli.Cli.init(allocator, null);
        defer cli_instance.deinit();

        var duplicate_args = [_][]const u8{
            "build",
            "--verbose",
            "--verbose",
            "--output", "first",
            "--output", "second"
        };
        
        try cli_instance.parseArgs(&duplicate_args);
        
        try testing.expect(cli_instance.args.command == .build);
        try testing.expect(cli_instance.args.hasFlag("verbose"));
        // 最后一个值应该被保留
        try testing.expectEqualStrings("second", cli_instance.args.getFlag("output").?);
    }

    // 测试空值标志
    {
        var cli_instance = try cli.Cli.init(allocator, null);
        defer cli_instance.deinit();

        var empty_value_args = [_][]const u8{
            "init", "project",
            "--template", "",
            "--llm"
        };
        
        try cli_instance.parseArgs(&empty_value_args);
        
        try testing.expect(cli_instance.args.command == .init);
        try testing.expectEqualStrings("project", cli_instance.args.positional_args[0]);
        // 空字符串值应该被正确处理
        if (cli_instance.args.getFlag("template")) |template| {
            try testing.expectEqualStrings("", template);
        }
    }
}

test "CLI integration - command chaining validation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 测试命令的逻辑组合
    var cli_instance = try cli.Cli.init(allocator, null);
    defer cli_instance.deinit();

    // 测试init命令的完整工作流
    var init_workflow_args = [_][]const u8{
        "init", "test-project",
        "--template", "workflow",
        "--llm", "anthropic",
        "--storage", "memory",
        "--verbose"
    };
    
    try cli_instance.parseArgs(&init_workflow_args);
    
    try testing.expect(cli_instance.args.command == .init);
    try testing.expectEqualStrings("test-project", cli_instance.args.positional_args[0]);
    try testing.expectEqualStrings("workflow", cli_instance.args.getFlag("template").?);
    try testing.expectEqualStrings("anthropic", cli_instance.args.getFlag("llm").?);
    try testing.expectEqualStrings("memory", cli_instance.args.getFlag("storage").?);
    try testing.expect(cli_instance.args.hasFlag("verbose"));
}
