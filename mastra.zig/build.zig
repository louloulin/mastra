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
    // 暂时禁用SQLite支持，等待修复编译问题
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

    // 添加真实API测试
    const real_api_tests = b.addTest(.{
        .root_source_file = b.path("test/real_api_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    real_api_tests.root_module.addImport("mastra", mastra_module);
    real_api_tests.linkLibC();

    // 添加DeepSeek API测试
    const deepseek_tests = b.addTest(.{
        .root_source_file = b.path("test/deepseek_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    deepseek_tests.root_module.addImport("mastra", mastra_module);
    deepseek_tests.linkLibC();

    // 添加DeepSeek简化测试
    const deepseek_simple_tests = b.addTest(.{
        .root_source_file = b.path("test/deepseek_simple_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    deepseek_simple_tests.root_module.addImport("mastra", mastra_module);
    deepseek_simple_tests.linkLibC();

    const run_integration_tests = b.addRunArtifact(integration_tests);
    const run_real_api_tests = b.addRunArtifact(real_api_tests);
    const run_deepseek_tests = b.addRunArtifact(deepseek_tests);
    const run_deepseek_simple_tests = b.addRunArtifact(deepseek_simple_tests);

    const integration_test_step = b.step("test-integration", "Run integration tests");
    integration_test_step.dependOn(&run_integration_tests.step);

    const real_api_tests_step = b.step("test-real-api", "Run real API tests (requires API keys)");
    real_api_tests_step.dependOn(&run_real_api_tests.step);

    const deepseek_tests_step = b.step("test-deepseek", "Run DeepSeek API tests (requires network)");
    deepseek_tests_step.dependOn(&run_deepseek_tests.step);

    const deepseek_simple_tests_step = b.step("test-deepseek-simple", "Run DeepSeek basic tests (no network)");
    deepseek_simple_tests_step.dependOn(&run_deepseek_simple_tests.step);

    const all_tests_step = b.step("test-all", "Run all tests");
    all_tests_step.dependOn(&run_unit_tests.step);
    all_tests_step.dependOn(&run_simple_tests.step);
    all_tests_step.dependOn(&run_integration_tests.step);
}
