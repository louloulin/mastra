const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 暂时移除外部依赖，先实现基础功能

    const lib = b.addStaticLibrary(.{
        .name = "mastra",
        .root_source_file = b.path("src/mastra.zig"),
        .target = target,
        .optimize = optimize,
    });

    // 暂时移除外部模块导入
    // lib.root_module.addImport("xev", libxev.module("xev"));
    // lib.root_module.addImport("zqlite", zqlite.module("zqlite"));
    // lib.root_module.addImport("zul", zul.module("zul"));

    // 链接系统库
    lib.linkLibC();
    // 暂时移除SQLite依赖
    // lib.linkSystemLibrary("sqlite3");

    b.installArtifact(lib);

    const exe = b.addExecutable(.{
        .name = "mastra",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // 暂时移除外部模块导入
    // exe.root_module.addImport("xev", libxev.module("xev"));
    // exe.root_module.addImport("zqlite", zqlite.module("zqlite"));
    // exe.root_module.addImport("zul", zul.module("zul"));
    exe.linkLibC();
    // 暂时移除SQLite依赖
    // exe.linkSystemLibrary("sqlite3");

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/mastra.zig"),
        .target = target,
        .optimize = optimize,
    });

    // 暂时移除外部模块导入
    // unit_tests.root_module.addImport("xev", libxev.module("xev"));
    // unit_tests.root_module.addImport("zqlite", zqlite.module("zqlite"));
    // unit_tests.root_module.addImport("zul", zul.module("zul"));
    unit_tests.linkLibC();
    // 暂时移除SQLite依赖
    // unit_tests.linkSystemLibrary("sqlite3");

    const run_unit_tests = b.addRunArtifact(unit_tests);

    // 添加简单测试
    const simple_tests = b.addTest(.{
        .root_source_file = b.path("test/simple_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    simple_tests.linkLibC();

    const run_simple_tests = b.addRunArtifact(simple_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    const simple_test_step = b.step("test-simple", "Run simple tests");
    simple_test_step.dependOn(&run_simple_tests.step);

    // 添加集成测试
    const integration_tests = b.addTest(.{
        .root_source_file = b.path("test/integration_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    // 创建mastra模块
    const mastra_module = b.createModule(.{
        .root_source_file = b.path("src/mastra.zig"),
    });
    integration_tests.root_module.addImport("mastra", mastra_module);
    integration_tests.linkLibC();

    const run_integration_tests = b.addRunArtifact(integration_tests);

    const integration_test_step = b.step("test-integration", "Run integration tests");
    integration_test_step.dependOn(&run_integration_tests.step);

    const all_tests_step = b.step("test-all", "Run all tests");
    all_tests_step.dependOn(&run_unit_tests.step);
    all_tests_step.dependOn(&run_simple_tests.step);
    all_tests_step.dependOn(&run_integration_tests.step);
}
