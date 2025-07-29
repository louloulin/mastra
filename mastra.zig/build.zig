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

    // 添加安全模式测试
    const safe_mode_exe = b.addExecutable(.{
        .name = "mastra_safe",
        .root_source_file = b.path("src/main_safe.zig"),
        .target = target,
        .optimize = optimize,
    });
    safe_mode_exe.linkLibC();
    b.installArtifact(safe_mode_exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // 添加安全模式测试运行步骤
    const run_safe_mode_cmd = b.addRunArtifact(safe_mode_exe);
    run_safe_mode_cmd.step.dependOn(b.getInstallStep());

    const run_safe_mode_step = b.step("run-safe", "Run Mastra in safe mode");
    run_safe_mode_step.dependOn(&run_safe_mode_cmd.step);

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

    // 添加 examples 目录支持
    addExampleTargets(b, target, optimize, mastra_module);
}

fn addExampleTargets(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, mastra_module: *std.Build.Module) void {
    // Basic examples
    const final_verification_exe = b.addExecutable(.{
        .name = "final_verification",
        .root_source_file = b.path("examples/basic/final_verification.zig"),
        .target = target,
        .optimize = optimize,
    });
    final_verification_exe.root_module.addImport("mastra", mastra_module);
    final_verification_exe.linkLibC();
    b.installArtifact(final_verification_exe);

    const comprehensive_test_exe = b.addExecutable(.{
        .name = "comprehensive_test",
        .root_source_file = b.path("examples/basic/comprehensive_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    comprehensive_test_exe.root_module.addImport("mastra", mastra_module);
    comprehensive_test_exe.linkLibC();
    b.installArtifact(comprehensive_test_exe);

    // Memory examples
    const memory_leak_fix_exe = b.addExecutable(.{
        .name = "memory_leak_fix",
        .root_source_file = b.path("examples/memory/test_memory_leak_fix.zig"),
        .target = target,
        .optimize = optimize,
    });
    memory_leak_fix_exe.root_module.addImport("mastra", mastra_module);
    memory_leak_fix_exe.linkLibC();
    b.installArtifact(memory_leak_fix_exe);

    // Agent examples
    const agent_complete_exe = b.addExecutable(.{
        .name = "agent_complete",
        .root_source_file = b.path("examples/agent/complete_agent_example.zig"),
        .target = target,
        .optimize = optimize,
    });
    agent_complete_exe.root_module.addImport("mastra", mastra_module);
    agent_complete_exe.linkLibC();
    b.installArtifact(agent_complete_exe);

    // Storage examples
    const storage_comprehensive_exe = b.addExecutable(.{
        .name = "storage_comprehensive",
        .root_source_file = b.path("examples/storage/test_storage_comprehensive.zig"),
        .target = target,
        .optimize = optimize,
    });
    storage_comprehensive_exe.root_module.addImport("mastra", mastra_module);
    storage_comprehensive_exe.linkLibC();
    b.installArtifact(storage_comprehensive_exe);

    // RAG examples
    const rag_system_exe = b.addExecutable(.{
        .name = "rag_system",
        .root_source_file = b.path("examples/rag/test_rag_system.zig"),
        .target = target,
        .optimize = optimize,
    });
    rag_system_exe.root_module.addImport("mastra", mastra_module);
    rag_system_exe.linkLibC();
    b.installArtifact(rag_system_exe);

    const simple_rag_exe = b.addExecutable(.{
        .name = "simple_rag",
        .root_source_file = b.path("examples/rag/simple_rag_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    simple_rag_exe.root_module.addImport("mastra", mastra_module);
    simple_rag_exe.linkLibC();
    b.installArtifact(simple_rag_exe);

    // Workflow examples
    const parallel_workflow_exe = b.addExecutable(.{
        .name = "parallel_workflow",
        .root_source_file = b.path("examples/workflow/test_parallel_workflow.zig"),
        .target = target,
        .optimize = optimize,
    });
    parallel_workflow_exe.root_module.addImport("mastra", mastra_module);
    parallel_workflow_exe.linkLibC();
    b.installArtifact(parallel_workflow_exe);

    // 添加运行步骤
    const run_final_verification_cmd = b.addRunArtifact(final_verification_exe);
    run_final_verification_cmd.step.dependOn(b.getInstallStep());
    const run_final_verification_step = b.step("run-final-verification", "Run final verification example");
    run_final_verification_step.dependOn(&run_final_verification_cmd.step);

    const run_memory_leak_fix_cmd = b.addRunArtifact(memory_leak_fix_exe);
    run_memory_leak_fix_cmd.step.dependOn(b.getInstallStep());
    const run_memory_leak_fix_step = b.step("run-memory-leak-fix", "Run memory leak fix example");
    run_memory_leak_fix_step.dependOn(&run_memory_leak_fix_cmd.step);

    const run_agent_complete_cmd = b.addRunArtifact(agent_complete_exe);
    run_agent_complete_cmd.step.dependOn(b.getInstallStep());
    const run_agent_complete_step = b.step("run-agent-complete", "Run complete agent example");
    run_agent_complete_step.dependOn(&run_agent_complete_cmd.step);

    const run_storage_comprehensive_cmd = b.addRunArtifact(storage_comprehensive_exe);
    run_storage_comprehensive_cmd.step.dependOn(b.getInstallStep());
    const run_storage_comprehensive_step = b.step("run-storage-comprehensive", "Run comprehensive storage example");
    run_storage_comprehensive_step.dependOn(&run_storage_comprehensive_cmd.step);

    const run_rag_system_cmd = b.addRunArtifact(rag_system_exe);
    run_rag_system_cmd.step.dependOn(b.getInstallStep());
    const run_rag_system_step = b.step("run-rag-system", "Run RAG system example");
    run_rag_system_step.dependOn(&run_rag_system_cmd.step);

    const run_simple_rag_cmd = b.addRunArtifact(simple_rag_exe);
    run_simple_rag_cmd.step.dependOn(b.getInstallStep());
    const run_simple_rag_step = b.step("run-simple-rag", "Run simple RAG test");
    run_simple_rag_step.dependOn(&run_simple_rag_cmd.step);

    const run_parallel_workflow_cmd = b.addRunArtifact(parallel_workflow_exe);
    run_parallel_workflow_cmd.step.dependOn(b.getInstallStep());
    const run_parallel_workflow_step = b.step("run-parallel-workflow", "Run parallel workflow example");
    run_parallel_workflow_step.dependOn(&run_parallel_workflow_cmd.step);
}
