const std = @import("std");
const testing = std.testing;
const cli = @import("cli");

test "CLI dev server initialization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var cli_instance = try cli.Cli.init(allocator, null);
    defer cli_instance.deinit();

    // 测试参数解析
    var args = [_][]const u8{ "dev", "--port", "3001", "--host", "127.0.0.1", "--verbose" };
    try cli_instance.parseArgs(&args);

    // 验证参数解析结果
    try testing.expect(cli_instance.args.command == .dev);
    try testing.expectEqualStrings("3001", cli_instance.args.getFlag("port").?);
    try testing.expectEqualStrings("127.0.0.1", cli_instance.args.getFlag("host").?);
    try testing.expect(cli_instance.args.hasFlag("verbose"));
}

test "CLI file watch state management" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 测试文件监控状态
    var watch_state = cli.Cli.FileWatchState.init(allocator);
    defer watch_state.deinit();

    // 测试文件时间更新
    try watch_state.updateFileTime("test.zig", 1234567890);
    const time = watch_state.getFileTime("test.zig");
    try testing.expect(time != null);
    try testing.expect(time.? == 1234567890);

    // 测试不存在的文件
    const no_time = watch_state.getFileTime("nonexistent.zig");
    try testing.expect(no_time == null);
}

test "CLI dev command argument validation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var cli_instance = try cli.Cli.init(allocator, null);
    defer cli_instance.deinit();

    // 测试有效端口号
    var valid_args = [_][]const u8{ "dev", "--port", "8080" };
    try cli_instance.parseArgs(&valid_args);
    try testing.expectEqualStrings("8080", cli_instance.args.getFlag("port").?);

    // 测试默认值
    var cli_instance2 = try cli.Cli.init(allocator, null);
    defer cli_instance2.deinit();

    var minimal_args = [_][]const u8{"dev"};
    try cli_instance2.parseArgs(&minimal_args);
    try testing.expect(cli_instance2.args.command == .dev);
}

test "CLI dev server configuration" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var cli_instance = try cli.Cli.init(allocator, null);
    defer cli_instance.deinit();

    // 测试完整配置
    var full_args = [_][]const u8{ "dev", "--port", "4000", "--host", "0.0.0.0", "--verbose" };
    try cli_instance.parseArgs(&full_args);

    // 验证所有配置项
    try testing.expect(cli_instance.args.command == .dev);
    try testing.expectEqualStrings("4000", cli_instance.args.getFlag("port").?);
    try testing.expectEqualStrings("0.0.0.0", cli_instance.args.getFlag("host").?);
    try testing.expect(cli_instance.args.hasFlag("verbose"));
}

test "CLI file monitoring directory traversal" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var cli_instance = try cli.Cli.init(allocator, null);
    defer cli_instance.deinit();

    // 创建临时测试目录结构
    const test_dir = "test_watch_dir";
    const cwd = std.fs.cwd();

    // 清理可能存在的测试目录
    cwd.deleteTree(test_dir) catch {};

    // 创建测试目录
    try cwd.makeDir(test_dir);
    defer cwd.deleteTree(test_dir) catch {};

    var test_dir_handle = try cwd.openDir(test_dir, .{});
    defer test_dir_handle.close();

    // 创建测试文件
    const test_file = try test_dir_handle.createFile("test.zig", .{});
    defer test_file.close();
    try test_file.writeAll("// Test file content\n");

    // 测试文件变化检测（这里只测试不会崩溃）
    // 实际的文件监控需要在真实的项目结构中测试
    const has_changes = cli_instance.checkForFileChanges() catch false;
    _ = has_changes; // 忽略结果，只测试不崩溃
}

test "CLI dev server error handling" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var cli_instance = try cli.Cli.init(allocator, null);
    defer cli_instance.deinit();

    // 测试无效端口号处理
    var invalid_port_args = [_][]const u8{ "dev", "--port", "invalid" };
    try cli_instance.parseArgs(&invalid_port_args);

    // 验证参数被正确解析（即使端口号无效）
    try testing.expect(cli_instance.args.command == .dev);
    try testing.expectEqualStrings("invalid", cli_instance.args.getFlag("port").?);
}
