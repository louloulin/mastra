const std = @import("std");
const testing = std.testing;
const cli = @import("cli");
const Cli = cli.Cli;
const CliArgs = cli.CliArgs;

test "CLI dev command validation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 测试 dev 命令参数解析
    var cli_instance = try Cli.init(allocator, null);
    defer cli_instance.deinit();

    try cli_instance.args.addFlag("port", "8080");
    try cli_instance.args.addFlag("host", "0.0.0.0");
    try cli_instance.args.addBoolFlag("verbose");

    // 验证参数解析
    const port = cli_instance.args.getFlag("port");
    const host = cli_instance.args.getFlag("host");
    const verbose = cli_instance.args.hasFlag("verbose");

    try testing.expect(port != null);
    try testing.expectEqualStrings("8080", port.?);
    try testing.expect(host != null);
    try testing.expectEqualStrings("0.0.0.0", host.?);
    try testing.expect(verbose);
}

test "CLI build command validation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 测试 build 命令参数解析
    var cli_instance = try Cli.init(allocator, null);
    defer cli_instance.deinit();

    try cli_instance.args.addBoolFlag("optimize");
    try cli_instance.args.addBoolFlag("release");
    try cli_instance.args.addFlag("target", "x86_64-linux");
    try cli_instance.args.addFlag("output", "./dist");

    // 验证参数解析
    const optimize = cli_instance.args.hasFlag("optimize");
    const release = cli_instance.args.hasFlag("release");
    const target = cli_instance.args.getFlag("target");
    const output = cli_instance.args.getFlag("output");

    try testing.expect(optimize);
    try testing.expect(release);
    try testing.expect(target != null);
    try testing.expectEqualStrings("x86_64-linux", target.?);
    try testing.expect(output != null);
    try testing.expectEqualStrings("./dist", output.?);
}

test "CLI deploy command validation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 测试 deploy 命令参数解析
    var cli_instance = try Cli.init(allocator, null);
    defer cli_instance.deinit();

    try cli_instance.args.addFlag("platform", "docker");
    try cli_instance.args.addFlag("env", "staging");
    try cli_instance.args.addFlag("config", "deploy.json");
    try cli_instance.args.addBoolFlag("dry-run");
    try cli_instance.args.addBoolFlag("verbose");

    // 验证参数解析
    const platform = cli_instance.args.getFlag("platform");
    const env = cli_instance.args.getFlag("env");
    const config = cli_instance.args.getFlag("config");
    const dry_run = cli_instance.args.hasFlag("dry-run");
    const verbose = cli_instance.args.hasFlag("verbose");

    try testing.expect(platform != null);
    try testing.expectEqualStrings("docker", platform.?);
    try testing.expect(env != null);
    try testing.expectEqualStrings("staging", env.?);
    try testing.expect(config != null);
    try testing.expectEqualStrings("deploy.json", config.?);
    try testing.expect(dry_run);
    try testing.expect(verbose);
}

test "CLI generate command with different types" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 测试 generate agent 命令
    {
        var cli_instance = try Cli.init(allocator, null);
        defer cli_instance.deinit();

        try cli_instance.args.addPositionalArg("agent");
        try cli_instance.args.addFlag("name", "test_agent");

        try testing.expect(cli_instance.args.positional_args.len == 1);
        try testing.expectEqualStrings("agent", cli_instance.args.positional_args[0]);
        
        const name = cli_instance.args.getFlag("name");
        try testing.expect(name != null);
        try testing.expectEqualStrings("test_agent", name.?);
    }

    // 测试 generate workflow 命令
    {
        var cli_instance = try Cli.init(allocator, null);
        defer cli_instance.deinit();

        try cli_instance.args.addPositionalArg("workflow");
        try cli_instance.args.addFlag("name", "test_workflow");

        try testing.expect(cli_instance.args.positional_args.len == 1);
        try testing.expectEqualStrings("workflow", cli_instance.args.positional_args[0]);
        
        const name = cli_instance.args.getFlag("name");
        try testing.expect(name != null);
        try testing.expectEqualStrings("test_workflow", name.?);
    }

    // 测试 generate tool 命令
    {
        var cli_instance = try Cli.init(allocator, null);
        defer cli_instance.deinit();

        try cli_instance.args.addPositionalArg("tool");
        try cli_instance.args.addFlag("name", "test_tool");

        try testing.expect(cli_instance.args.positional_args.len == 1);
        try testing.expectEqualStrings("tool", cli_instance.args.positional_args[0]);
        
        const name = cli_instance.args.getFlag("name");
        try testing.expect(name != null);
        try testing.expectEqualStrings("test_tool", name.?);
    }
}

test "CLI error handling" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 测试无效端口号
    {
        var cli_instance = try Cli.init(allocator, null);
        defer cli_instance.deinit();

        try cli_instance.args.addFlag("port", "invalid_port");

        const port = cli_instance.args.getFlag("port");
        try testing.expect(port != null);
        
        // 尝试解析无效端口号应该失败
        const port_num = std.fmt.parseInt(u16, port.?, 10);
        try testing.expectError(error.InvalidCharacter, port_num);
    }

    // 测试空的生成类型
    {
        var cli_instance = try Cli.init(allocator, null);
        defer cli_instance.deinit();

        // 没有位置参数应该导致错误
        try testing.expect(cli_instance.args.positional_args.len == 0);
    }
}