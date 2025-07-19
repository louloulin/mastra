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

    // 添加Agent测试程序
    const agent_test_exe = b.addExecutable(.{
        .name = "test_agent_simple",
        .root_source_file = b.path("test_agent_simple.zig"),
        .target = target,
        .optimize = optimize,
    });
    agent_test_exe.linkLibC();
    b.installArtifact(agent_test_exe);

    // 添加DeepSeek直接测试程序
    const deepseek_direct_test_exe = b.addExecutable(.{
        .name = "test_deepseek_direct",
        .root_source_file = b.path("test_deepseek_direct.zig"),
        .target = target,
        .optimize = optimize,
    });
    deepseek_direct_test_exe.linkLibC();
    b.installArtifact(deepseek_direct_test_exe);

    // 添加网络诊断工具
    const network_diagnostic_exe = b.addExecutable(.{
        .name = "network_diagnostic",
        .root_source_file = b.path("network_diagnostic.zig"),
        .target = target,
        .optimize = optimize,
    });
    network_diagnostic_exe.linkLibC();
    b.installArtifact(network_diagnostic_exe);

    // 添加DeepSeek调试工具
    const deepseek_debug_exe = b.addExecutable(.{
        .name = "deepseek_debug",
        .root_source_file = b.path("deepseek_debug.zig"),
        .target = target,
        .optimize = optimize,
    });
    deepseek_debug_exe.linkLibC();
    b.installArtifact(deepseek_debug_exe);

    // 添加安全模式测试
    const safe_mode_exe = b.addExecutable(.{
        .name = "mastra_safe",
        .root_source_file = b.path("src/main_safe.zig"),
        .target = target,
        .optimize = optimize,
    });
    safe_mode_exe.linkLibC();
    b.installArtifact(safe_mode_exe);

    // 添加缓存测试
    const cache_test_exe = b.addExecutable(.{
        .name = "cache_test",
        .root_source_file = b.path("cache_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    cache_test_exe.linkLibC();
    b.installArtifact(cache_test_exe);

    // 添加HTTP调试工具
    const http_debug_exe = b.addExecutable(.{
        .name = "http_debug",
        .root_source_file = b.path("http_debug.zig"),
        .target = target,
        .optimize = optimize,
    });
    http_debug_exe.linkLibC();
    b.installArtifact(http_debug_exe);

    // 添加最小测试
    const minimal_test_exe = b.addExecutable(.{
        .name = "minimal_test",
        .root_source_file = b.path("minimal_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    minimal_test_exe.linkLibC();
    b.installArtifact(minimal_test_exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // 添加Agent测试运行步骤
    const run_agent_test_cmd = b.addRunArtifact(agent_test_exe);
    run_agent_test_cmd.step.dependOn(b.getInstallStep());

    const run_agent_test_step = b.step("run-agent-test", "Run AI Agent DeepSeek test");
    run_agent_test_step.dependOn(&run_agent_test_cmd.step);

    // 添加DeepSeek直接测试运行步骤
    const run_deepseek_direct_test_cmd = b.addRunArtifact(deepseek_direct_test_exe);
    run_deepseek_direct_test_cmd.step.dependOn(b.getInstallStep());

    const run_deepseek_direct_test_step = b.step("run-deepseek-direct", "Run DeepSeek API direct test");
    run_deepseek_direct_test_step.dependOn(&run_deepseek_direct_test_cmd.step);

    // 添加网络诊断工具运行步骤
    const run_network_diagnostic_cmd = b.addRunArtifact(network_diagnostic_exe);
    run_network_diagnostic_cmd.step.dependOn(b.getInstallStep());

    const run_network_diagnostic_step = b.step("run-network-diagnostic", "Run network diagnostic tool");
    run_network_diagnostic_step.dependOn(&run_network_diagnostic_cmd.step);

    // 添加DeepSeek调试工具运行步骤
    const run_deepseek_debug_cmd = b.addRunArtifact(deepseek_debug_exe);
    run_deepseek_debug_cmd.step.dependOn(b.getInstallStep());

    const run_deepseek_debug_step = b.step("run-deepseek-debug", "Run DeepSeek API debug tool");
    run_deepseek_debug_step.dependOn(&run_deepseek_debug_cmd.step);

    // 添加安全模式测试运行步骤
    const run_safe_mode_cmd = b.addRunArtifact(safe_mode_exe);
    run_safe_mode_cmd.step.dependOn(b.getInstallStep());

    const run_safe_mode_step = b.step("run-safe", "Run Mastra in safe mode");
    run_safe_mode_step.dependOn(&run_safe_mode_cmd.step);

    // 添加缓存测试运行步骤
    const run_cache_test_cmd = b.addRunArtifact(cache_test_exe);
    run_cache_test_cmd.step.dependOn(b.getInstallStep());

    const run_cache_test_step = b.step("run-cache-test", "Run cache system test");
    run_cache_test_step.dependOn(&run_cache_test_cmd.step);

    // 添加HTTP调试工具运行步骤
    const run_http_debug_cmd = b.addRunArtifact(http_debug_exe);
    run_http_debug_cmd.step.dependOn(b.getInstallStep());

    const run_http_debug_step = b.step("run-http-debug", "Run HTTP client debug tool");
    run_http_debug_step.dependOn(&run_http_debug_cmd.step);

    // 添加最小测试运行步骤
    const run_minimal_test_cmd = b.addRunArtifact(minimal_test_exe);
    run_minimal_test_cmd.step.dependOn(b.getInstallStep());

    const run_minimal_test_step = b.step("run-minimal-test", "Run minimal DeepSeek API test");
    run_minimal_test_step.dependOn(&run_minimal_test_cmd.step);

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

    // 添加Agent DeepSeek测试
    const agent_deepseek_tests = b.addTest(.{
        .root_source_file = b.path("test/agent_deepseek_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    agent_deepseek_tests.root_module.addImport("mastra", mastra_module);
    agent_deepseek_tests.linkLibC();

    const run_integration_tests = b.addRunArtifact(integration_tests);
    const run_real_api_tests = b.addRunArtifact(real_api_tests);
    const run_deepseek_tests = b.addRunArtifact(deepseek_tests);
    const run_deepseek_simple_tests = b.addRunArtifact(deepseek_simple_tests);
    const run_agent_deepseek_tests = b.addRunArtifact(agent_deepseek_tests);

    const integration_test_step = b.step("test-integration", "Run integration tests");
    integration_test_step.dependOn(&run_integration_tests.step);

    const real_api_tests_step = b.step("test-real-api", "Run real API tests (requires API keys)");
    real_api_tests_step.dependOn(&run_real_api_tests.step);

    const deepseek_tests_step = b.step("test-deepseek", "Run DeepSeek API tests (requires network)");
    deepseek_tests_step.dependOn(&run_deepseek_tests.step);

    const deepseek_simple_tests_step = b.step("test-deepseek-simple", "Run DeepSeek basic tests (no network)");
    deepseek_simple_tests_step.dependOn(&run_deepseek_simple_tests.step);

    const agent_deepseek_tests_step = b.step("test-agent-deepseek", "Run AI Agent with DeepSeek tests (requires API key)");
    agent_deepseek_tests_step.dependOn(&run_agent_deepseek_tests.step);

    const all_tests_step = b.step("test-all", "Run all tests");
    all_tests_step.dependOn(&run_unit_tests.step);
    all_tests_step.dependOn(&run_simple_tests.step);
    all_tests_step.dependOn(&run_integration_tests.step);
}
