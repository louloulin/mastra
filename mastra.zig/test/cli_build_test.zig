const std = @import("std");
const testing = std.testing;
const cli = @import("cli");

test "CLI build mode enum" {
    // 测试构建模式转换
    const debug = cli.Cli.BuildMode.fromString("debug");
    try testing.expect(debug == .debug);
    
    const release_safe = cli.Cli.BuildMode.fromString("release-safe");
    try testing.expect(release_safe == .release_safe);
    
    const release_fast = cli.Cli.BuildMode.fromString("release-fast");
    try testing.expect(release_fast == .release_fast);
    
    const release_small = cli.Cli.BuildMode.fromString("release-small");
    try testing.expect(release_small == .release_small);
    
    // 测试未知模式默认为debug
    const unknown = cli.Cli.BuildMode.fromString("unknown");
    try testing.expect(unknown == .debug);
}

test "CLI build mode toString" {
    try testing.expectEqualStrings("Debug", cli.Cli.BuildMode.debug.toString());
    try testing.expectEqualStrings("ReleaseSafe", cli.Cli.BuildMode.release_safe.toString());
    try testing.expectEqualStrings("ReleaseFast", cli.Cli.BuildMode.release_fast.toString());
    try testing.expectEqualStrings("ReleaseSmall", cli.Cli.BuildMode.release_small.toString());
}

test "CLI build command basic options" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var cli_instance = try cli.Cli.init(allocator, null);
    defer cli_instance.deinit();

    // 测试基础构建命令
    var basic_args = [_][]const u8{ "build" };
    try cli_instance.parseArgs(&basic_args);
    
    try testing.expect(cli_instance.args.command == .build);
    try testing.expect(!cli_instance.args.hasFlag("optimize"));
    try testing.expect(!cli_instance.args.hasFlag("verbose"));
    try testing.expect(!cli_instance.args.hasFlag("release"));
}

test "CLI build command with optimization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var cli_instance = try cli.Cli.init(allocator, null);
    defer cli_instance.deinit();

    // 测试优化构建
    var optimize_args = [_][]const u8{ "build", "--optimize", "--verbose" };
    try cli_instance.parseArgs(&optimize_args);
    
    try testing.expect(cli_instance.args.command == .build);
    try testing.expect(cli_instance.args.hasFlag("optimize"));
    try testing.expect(cli_instance.args.hasFlag("verbose"));
}

test "CLI build command with target platform" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var cli_instance = try cli.Cli.init(allocator, null);
    defer cli_instance.deinit();

    // 测试目标平台构建
    var target_args = [_][]const u8{ "build", "--target", "x86_64-linux-gnu" };
    try cli_instance.parseArgs(&target_args);
    
    try testing.expect(cli_instance.args.command == .build);
    try testing.expectEqualStrings("x86_64-linux-gnu", cli_instance.args.getFlag("target").?);
}

test "CLI build command with release mode" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var cli_instance = try cli.Cli.init(allocator, null);
    defer cli_instance.deinit();

    // 测试发布模式构建
    var release_args = [_][]const u8{ "build", "--release", "--strip" };
    try cli_instance.parseArgs(&release_args);
    
    try testing.expect(cli_instance.args.command == .build);
    try testing.expect(cli_instance.args.hasFlag("release"));
    try testing.expect(cli_instance.args.hasFlag("strip"));
}

test "CLI build command with custom output" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var cli_instance = try cli.Cli.init(allocator, null);
    defer cli_instance.deinit();

    // 测试自定义输出目录
    var output_args = [_][]const u8{ "build", "--output", "dist" };
    try cli_instance.parseArgs(&output_args);
    
    try testing.expect(cli_instance.args.command == .build);
    try testing.expectEqualStrings("dist", cli_instance.args.getFlag("output").?);
}

test "CLI build command with parallel build" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var cli_instance = try cli.Cli.init(allocator, null);
    defer cli_instance.deinit();

    // 测试并行构建
    var parallel_args = [_][]const u8{ "build", "--parallel", "4" };
    try cli_instance.parseArgs(&parallel_args);
    
    try testing.expect(cli_instance.args.command == .build);
    try testing.expectEqualStrings("4", cli_instance.args.getFlag("parallel").?);
}

test "CLI build command with clean option" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var cli_instance = try cli.Cli.init(allocator, null);
    defer cli_instance.deinit();

    // 测试清理构建
    var clean_args = [_][]const u8{ "build", "--clean" };
    try cli_instance.parseArgs(&clean_args);
    
    try testing.expect(cli_instance.args.command == .build);
    try testing.expect(cli_instance.args.hasFlag("clean"));
}

test "CLI build command with build mode" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var cli_instance = try cli.Cli.init(allocator, null);
    defer cli_instance.deinit();

    // 测试构建模式
    var mode_args = [_][]const u8{ "build", "--mode", "release-fast" };
    try cli_instance.parseArgs(&mode_args);
    
    try testing.expect(cli_instance.args.command == .build);
    try testing.expectEqualStrings("release-fast", cli_instance.args.getFlag("mode").?);
}

test "CLI build command comprehensive options" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var cli_instance = try cli.Cli.init(allocator, null);
    defer cli_instance.deinit();

    // 测试综合构建选项
    var comprehensive_args = [_][]const u8{ 
        "build", 
        "--mode", "release-safe",
        "--target", "aarch64-macos",
        "--output", "build",
        "--parallel", "8",
        "--verbose",
        "--strip",
        "--clean"
    };
    try cli_instance.parseArgs(&comprehensive_args);
    
    try testing.expect(cli_instance.args.command == .build);
    try testing.expectEqualStrings("release-safe", cli_instance.args.getFlag("mode").?);
    try testing.expectEqualStrings("aarch64-macos", cli_instance.args.getFlag("target").?);
    try testing.expectEqualStrings("build", cli_instance.args.getFlag("output").?);
    try testing.expectEqualStrings("8", cli_instance.args.getFlag("parallel").?);
    try testing.expect(cli_instance.args.hasFlag("verbose"));
    try testing.expect(cli_instance.args.hasFlag("strip"));
    try testing.expect(cli_instance.args.hasFlag("clean"));
}

test "CLI build error handling" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var cli_instance = try cli.Cli.init(allocator, null);
    defer cli_instance.deinit();

    // 测试构建命令解析（这里只测试不会崩溃）
    var build_args = [_][]const u8{ "build", "--invalid-option" };
    try cli_instance.parseArgs(&build_args);
    
    // 验证命令被正确解析
    try testing.expect(cli_instance.args.command == .build);
    // 无效选项会被忽略或作为标志处理
}
