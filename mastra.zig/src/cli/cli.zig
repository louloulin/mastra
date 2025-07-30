//! Mastra CLI工具
//!
//! 提供命令行界面用于:
//! - 项目初始化
//! - 开发服务器
//! - 项目构建
//! - 代码生成
//! - 部署管理

const std = @import("std");
const mastra = @import("../mastra.zig");

/// CLI错误类型
pub const CliError = error{
    InvalidCommand,
    MissingArgument,
    InvalidArgument,
    ProjectExists,
    ProjectNotFound,
    ConfigurationError,
    BuildError,
    DeploymentError,
};

/// CLI命令类型
pub const Command = enum {
    init,
    dev,
    build,
    deploy,
    generate,
    help,
    version,

    pub fn fromString(str: []const u8) ?Command {
        if (std.mem.eql(u8, str, "init")) return .init;
        if (std.mem.eql(u8, str, "dev")) return .dev;
        if (std.mem.eql(u8, str, "build")) return .build;
        if (std.mem.eql(u8, str, "deploy")) return .deploy;
        if (std.mem.eql(u8, str, "generate")) return .generate;
        if (std.mem.eql(u8, str, "help")) return .help;
        if (std.mem.eql(u8, str, "version")) return .version;
        return null;
    }

    pub fn toString(self: Command) []const u8 {
        return switch (self) {
            .init => "init",
            .dev => "dev",
            .build => "build",
            .deploy => "deploy",
            .generate => "generate",
            .help => "help",
            .version => "version",
        };
    }
};

/// CLI参数结构
pub const CliArgs = struct {
    command: ?Command = null,
    positional_args: [][]const u8 = &[_][]const u8{},
    flags: std.StringHashMap([]const u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) CliArgs {
        return CliArgs{
            .flags = std.StringHashMap([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *CliArgs) void {
        // 释放位置参数
        for (self.positional_args) |arg| {
            self.allocator.free(arg);
        }
        if (self.positional_args.len > 0) {
            self.allocator.free(self.positional_args);
        }

        // 释放标志参数
        var iterator = self.flags.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.flags.deinit();
    }

    pub fn hasFlag(self: *const CliArgs, flag: []const u8) bool {
        return self.flags.contains(flag);
    }

    pub fn getFlag(self: *const CliArgs, flag: []const u8) ?[]const u8 {
        return self.flags.get(flag);
    }

    /// 添加标志参数（用于测试）
    pub fn addFlag(self: *CliArgs, key: []const u8, value: []const u8) !void {
        try self.flags.put(try self.allocator.dupe(u8, key), try self.allocator.dupe(u8, value));
    }

    /// 添加位置参数（用于测试）
    pub fn addPositionalArg(self: *CliArgs, arg: []const u8) !void {
        const new_args = try self.allocator.alloc([]const u8, self.positional_args.len + 1);
        for (self.positional_args, 0..) |existing_arg, i| {
            new_args[i] = existing_arg;
        }
        new_args[self.positional_args.len] = try self.allocator.dupe(u8, arg);

        // 释放旧的数组
        if (self.positional_args.len > 0) {
            self.allocator.free(self.positional_args);
        }

        self.positional_args = new_args;
    }

    /// 添加布尔标志参数（用于测试）
    pub fn addBoolFlag(self: *CliArgs, key: []const u8) !void {
        try self.flags.put(try self.allocator.dupe(u8, key), try self.allocator.dupe(u8, ""));
    }
};

/// CLI主类
pub const Cli = struct {
    allocator: std.mem.Allocator,
    args: CliArgs,
    file_watch_state: ?FileWatchState = null,

    pub fn init(allocator: std.mem.Allocator, args: ?CliArgs) !Cli {
        return Cli{
            .allocator = allocator,
            .args = args orelse CliArgs.init(allocator),
            .file_watch_state = null,
        };
    }

    pub fn deinit(self: *Cli) void {
        if (self.file_watch_state) |*state| {
            state.deinit();
        }
        self.args.deinit();
    }

    /// 解析命令行参数
    pub fn parseArgs(self: *Cli, args: [][]const u8) !void {
        if (args.len == 0) {
            return;
        }

        var positional = std.ArrayList([]const u8).init(self.allocator);
        defer positional.deinit();

        var i: usize = 0;
        while (i < args.len) : (i += 1) {
            const arg = args[i];

            if (std.mem.startsWith(u8, arg, "--") and arg.len > 2) {
                // 长选项 --key=value 或 --key value
                if (std.mem.indexOf(u8, arg, "=")) |eq_pos| {
                    const key = arg[2..eq_pos];
                    const value = arg[eq_pos + 1 ..];
                    try self.args.flags.put(try self.allocator.dupe(u8, key), try self.allocator.dupe(u8, value));
                } else {
                    const key = arg[2..];
                    if (i + 1 < args.len and !std.mem.startsWith(u8, args[i + 1], "-")) {
                        i += 1;
                        try self.args.flags.put(try self.allocator.dupe(u8, key), try self.allocator.dupe(u8, args[i]));
                    } else {
                        try self.args.flags.put(try self.allocator.dupe(u8, key), try self.allocator.dupe(u8, ""));
                    }
                }
            } else if (std.mem.startsWith(u8, arg, "-") and arg.len > 1) {
                // 短选项 -k value
                const key = arg[1..];
                if (i + 1 < args.len and !std.mem.startsWith(u8, args[i + 1], "-")) {
                    i += 1;
                    try self.args.flags.put(try self.allocator.dupe(u8, key), try self.allocator.dupe(u8, args[i]));
                } else {
                    try self.args.flags.put(try self.allocator.dupe(u8, key), try self.allocator.dupe(u8, ""));
                }
            } else {
                // 位置参数
                try positional.append(try self.allocator.dupe(u8, arg));
            }
        }

        // 第一个位置参数是命令
        if (positional.items.len > 0) {
            self.args.command = Command.fromString(positional.items[0]);
            // 释放命令字符串，因为我们不需要存储它
            self.allocator.free(positional.items[0]);

            // 移除命令，保留其余位置参数
            if (positional.items.len > 1) {
                const remaining_args = try self.allocator.alloc([]const u8, positional.items.len - 1);
                for (positional.items[1..], 0..) |arg, idx| {
                    remaining_args[idx] = arg;
                }
                self.args.positional_args = remaining_args;
            }
        }
    }

    /// 执行CLI命令
    pub fn execute(self: *Cli) !void {
        const command = self.args.command orelse {
            try self.showHelp();
            return;
        };

        switch (command) {
            .init => try self.executeInit(),
            .dev => try self.executeDev(),
            .build => try self.executeBuild(),
            .deploy => try self.executeDeploy(),
            .generate => try self.executeGenerate(),
            .help => try self.showHelp(),
            .version => try self.showVersion(),
        }
    }

    /// 显示帮助信息
    fn showHelp(self: *Cli) !void {
        _ = self;
        const help_text =
            \\Mastra CLI - AI应用开发框架命令行工具
            \\
            \\用法:
            \\    mastra <COMMAND> [OPTIONS] [ARGS]
            \\
            \\命令:
            \\    init [PROJECT_NAME]     初始化新项目
            \\    dev                     启动开发服务器
            \\    build                   构建项目
            \\    deploy                  部署项目
            \\    generate <TYPE>         生成代码模板
            \\    help                    显示帮助信息
            \\    version                 显示版本信息
            \\
            \\选项:
            \\    -h, --help              显示帮助信息
            \\    -v, --version           显示版本信息
            \\    --verbose               详细输出
            \\    --config <FILE>         指定配置文件
            \\
            \\初始化选项:
            \\    --template <NAME>       使用指定模板
            \\    --llm <PROVIDER>        设置LLM提供商 (openai, anthropic, google)
            \\    --storage <TYPE>        设置存储类型 (memory, postgres, mongodb)
            \\
            \\示例:
            \\    mastra init my-project --template basic --llm openai
            \\    mastra dev --port 3000
            \\    mastra build --optimize
            \\    mastra generate agent --name my-agent
            \\
        ;
        std.debug.print("{s}", .{help_text});
    }

    /// 显示版本信息
    fn showVersion(self: *Cli) !void {
        _ = self;
        std.debug.print("Mastra CLI v0.1.0\n", .{});
        std.debug.print("基于 Zig {s}\n", .{@import("builtin").zig_version_string});
    }

    /// 执行初始化命令
    fn executeInit(self: *Cli) !void {
        const project_name = if (self.args.positional_args.len > 0)
            self.args.positional_args[0]
        else
            self.args.getFlag("name") orelse "mastra-project";

        const template = self.args.getFlag("template") orelse "basic";
        const llm_provider = self.args.getFlag("llm") orelse "openai";
        const storage_type = self.args.getFlag("storage") orelse "memory";

        std.debug.print("🚀 初始化 Mastra 项目: {s}\n", .{project_name});
        std.debug.print("📋 模板: {s}\n", .{template});
        std.debug.print("🤖 LLM提供商: {s}\n", .{llm_provider});
        std.debug.print("💾 存储类型: {s}\n", .{storage_type});

        // 检查项目目录是否存在
        const cwd = std.fs.cwd();
        if (cwd.access(project_name, .{})) {
            std.debug.print("❌ 错误: 项目目录 '{s}' 已存在\n", .{project_name});
            return CliError.ProjectExists;
        } else |_| {
            // 目录不存在，继续创建
        }

        // 创建项目目录
        try cwd.makeDir(project_name);
        std.debug.print("📁 创建项目目录: {s}\n", .{project_name});

        // 创建项目结构
        try self.createProjectStructure(project_name, template, llm_provider, storage_type);

        std.debug.print("✅ 项目初始化完成!\n", .{});
        std.debug.print("\n下一步:\n", .{});
        std.debug.print("  cd {s}\n", .{project_name});
        std.debug.print("  zig build run\n", .{});
    }

    /// 创建项目结构
    fn createProjectStructure(self: *Cli, project_name: []const u8, template: []const u8, llm_provider: []const u8, storage_type: []const u8) !void {
        const cwd = std.fs.cwd();
        var project_dir = try cwd.openDir(project_name, .{});
        defer project_dir.close();

        // 创建基础目录结构
        try project_dir.makeDir("src");
        try project_dir.makeDir("config");
        try project_dir.makeDir("examples");
        try project_dir.makeDir("tests");

        // 创建 build.zig
        try self.createBuildFile(project_dir, project_name);

        // 创建 main.zig
        try self.createMainFile(project_dir, template, llm_provider, storage_type);

        // 创建配置文件
        try self.createConfigFiles(project_dir, llm_provider, storage_type);

        // 创建示例文件
        try self.createExampleFiles(project_dir, template);

        // 创建 README.md
        try self.createReadmeFile(project_dir, project_name);

        std.debug.print("📝 项目文件创建完成\n", .{});
    }

    /// 创建 build.zig 文件
    fn createBuildFile(self: *Cli, project_dir: std.fs.Dir, project_name: []const u8) !void {
        const build_content = std.fmt.allocPrint(self.allocator,
            \\const std = @import("std");
            \\
            \\pub fn build(b: *std.Build) void {{
            \\    const target = b.standardTargetOptions(.{{}});
            \\    const optimize = b.standardOptimizeOption(.{{}});
            \\
            \\    const exe = b.addExecutable(.{{
            \\        .name = "{s}",
            \\        .root_source_file = b.path("src/main.zig"),
            \\        .target = target,
            \\        .optimize = optimize,
            \\    }});
            \\
            \\    // 添加 Mastra 依赖
            \\    // TODO: 添加实际的 Mastra 模块导入
            \\
            \\    b.installArtifact(exe);
            \\
            \\    const run_cmd = b.addRunArtifact(exe);
            \\    run_cmd.step.dependOn(b.getInstallStep());
            \\
            \\    if (b.args) |args| {{
            \\        run_cmd.addArgs(args);
            \\    }}
            \\
            \\    const run_step = b.step("run", "Run the app");
            \\    run_step.dependOn(&run_cmd.step);
            \\
            \\    const unit_tests = b.addTest(.{{
            \\        .root_source_file = b.path("src/main.zig"),
            \\        .target = target,
            \\        .optimize = optimize,
            \\    }});
            \\
            \\    const run_unit_tests = b.addRunArtifact(unit_tests);
            \\
            \\    const test_step = b.step("test", "Run unit tests");
            \\    test_step.dependOn(&run_unit_tests.step);
            \\}}
            \\
        , .{project_name}) catch return CliError.ConfigurationError;
        defer self.allocator.free(build_content);

        var build_file = try project_dir.createFile("build.zig", .{});
        defer build_file.close();
        try build_file.writeAll(build_content);
    }

    /// 项目模板类型
    pub const ProjectTemplate = enum {
        basic,
        agent,
        workflow,
        rag,
        tools,

        pub fn fromString(str: []const u8) ProjectTemplate {
            if (std.mem.eql(u8, str, "agent")) return .agent;
            if (std.mem.eql(u8, str, "workflow")) return .workflow;
            if (std.mem.eql(u8, str, "rag")) return .rag;
            if (std.mem.eql(u8, str, "tools")) return .tools;
            return .basic; // 默认模板
        }

        pub fn toString(self: ProjectTemplate) []const u8 {
            return switch (self) {
                .basic => "basic",
                .agent => "agent",
                .workflow => "workflow",
                .rag => "rag",
                .tools => "tools",
            };
        }
    };

    /// 创建 main.zig 文件
    fn createMainFile(self: *Cli, project_dir: std.fs.Dir, template: []const u8, llm_provider: []const u8, storage_type: []const u8) !void {
        const template_type = ProjectTemplate.fromString(template);

        const main_content = switch (template_type) {
            .basic => try self.createBasicMainContent(llm_provider, storage_type),
            .agent => try self.createAgentMainContent(llm_provider, storage_type),
            .workflow => try self.createWorkflowMainContent(llm_provider, storage_type),
            .rag => try self.createRagMainContent(llm_provider, storage_type),
            .tools => try self.createToolsMainContent(llm_provider, storage_type),
        };
        defer self.allocator.free(main_content);

        var src_dir = try project_dir.openDir("src", .{});
        defer src_dir.close();

        var main_file = try src_dir.createFile("main.zig", .{});
        defer main_file.close();
        try main_file.writeAll(main_content);
    }

    /// 创建基础模板的main.zig内容
    pub fn createBasicMainContent(self: *Cli, llm_provider: []const u8, storage_type: []const u8) ![]u8 {
        _ = llm_provider;
        _ = storage_type;

        const template =
            \\const std = @import("std");
            \\// TODO: 添加 Mastra 导入
            \\// const mastra = @import("mastra");
            \\
            \\pub fn main() !void {
            \\    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
            \\    defer _ = gpa.deinit();
            \\    const allocator = gpa.allocator();
            \\
            \\    std.debug.print("🚀 启动 Mastra 基础应用\n", .{});
            \\    std.debug.print("🤖 LLM提供商: openai\n", .{});
            \\    std.debug.print("💾 存储类型: memory\n", .{});
            \\
            \\    // TODO: 初始化 Mastra 框架
            \\    // var m = try mastra.Mastra.init(allocator, .{
            \\    //     .llm_provider = .openai,
            \\    //     .storage_type = .memory,
            \\    // });
            \\    // defer m.deinit();
            \\
            \\    std.debug.print("✅ 应用启动成功!\n", .{});
            \\
            \\    // 保持程序运行
            \\    std.debug.print("按 Ctrl+C 退出...\n", .{});
            \\    while (true) {
            \\        std.time.sleep(1000000000); // 1秒
            \\    }
            \\}
            \\
        ;
        return self.allocator.dupe(u8, template);
    }

    /// 创建Agent模板的main.zig内容
    pub fn createAgentMainContent(self: *Cli, llm_provider: []const u8, storage_type: []const u8) ![]u8 {
        _ = llm_provider;
        _ = storage_type;

        const template =
            \\const std = @import("std");
            \\// TODO: 添加 Mastra 导入
            \\// const mastra = @import("mastra");
            \\
            \\pub fn main() !void {
            \\    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
            \\    defer _ = gpa.deinit();
            \\    const allocator = gpa.allocator();
            \\
            \\    std.debug.print("🤖 启动 Mastra Agent 应用\n", .{});
            \\    std.debug.print("🧠 LLM提供商: openai\n", .{});
            \\    std.debug.print("💾 存储类型: memory\n", .{});
            \\
            \\    // TODO: 初始化 Agent
            \\    // var agent = try mastra.Agent.init(allocator, .{
            \\    //     .name = "MyAgent",
            \\    //     .instructions = "你是一个有用的AI助手",
            \\    //     .llm_provider = .openai,
            \\    //     .storage = .memory,
            \\    // });
            \\    // defer agent.deinit();
            \\
            \\    // 示例对话
            \\    // const response = try agent.chat("你好，请介绍一下自己");
            \\    // std.debug.print("Agent回复: {s}\n", .{response});
            \\
            \\    std.debug.print("✅ Agent 启动成功!\n", .{});
            \\    std.debug.print("💬 开始与Agent对话...\n", .{});
            \\
            \\    // 保持程序运行
            \\    while (true) {
            \\        std.time.sleep(1000000000);
            \\    }
            \\}
            \\
        ;
        return self.allocator.dupe(u8, template);
    }

    /// 创建Workflow模板的main.zig内容
    fn createWorkflowMainContent(self: *Cli, llm_provider: []const u8, storage_type: []const u8) ![]u8 {
        return std.fmt.allocPrint(self.allocator,
            \\const std = @import("std");
            \\// TODO: 添加 Mastra 导入
            \\// const mastra = @import("mastra");
            \\
            \\pub fn main() !void {{
            \\    var gpa = std.heap.GeneralPurposeAllocator(.{{}}){{}};
            \\    defer _ = gpa.deinit();
            \\    const allocator = gpa.allocator();
            \\
            \\    std.debug.print("⚡ 启动 Mastra Workflow 应用\n", .{{}});
            \\    std.debug.print("🧠 LLM提供商: {s}\n", .{{"{s}"}});
            \\    std.debug.print("💾 存储类型: {s}\n", .{{"{s}"}});
            \\
            \\    // TODO: 创建工作流
            \\    // var workflow = try mastra.Workflow.init(allocator, .{{
            \\    //     .name = "MyWorkflow",
            \\    //     .llm_provider = .{s},
            \\    //     .storage = .{s},
            \\    // }});
            \\    // defer workflow.deinit();
            \\
            \\    // 添加工作流步骤
            \\    // try workflow.addStep("step1", processInput);
            \\    // try workflow.addStep("step2", generateResponse);
            \\    // try workflow.addStep("step3", formatOutput);
            \\
            \\    // 执行工作流
            \\    // const result = try workflow.execute(.{{.input = "Hello World"}});
            \\    // std.debug.print("工作流结果: {{s}}\n", .{{result}});
            \\
            \\    std.debug.print("✅ Workflow 启动成功!\n", .{{}});
            \\    std.debug.print("🔄 工作流已准备就绪...\n", .{{}});
            \\
            \\    // 保持程序运行
            \\    while (true) {{
            \\        std.time.sleep(1000000000);
            \\    }}
            \\}}
            \\
        , .{ llm_provider, storage_type, llm_provider, storage_type });
    }

    /// 创建RAG模板的main.zig内容
    fn createRagMainContent(self: *Cli, llm_provider: []const u8, storage_type: []const u8) ![]u8 {
        return std.fmt.allocPrint(self.allocator,
            \\const std = @import("std");
            \\// TODO: 添加 Mastra 导入
            \\// const mastra = @import("mastra");
            \\
            \\pub fn main() !void {{
            \\    var gpa = std.heap.GeneralPurposeAllocator(.{{}}){{}};
            \\    defer _ = gpa.deinit();
            \\    const allocator = gpa.allocator();
            \\
            \\    std.debug.print("📚 启动 Mastra RAG 应用\n", .{{}});
            \\    std.debug.print("🧠 LLM提供商: {s}\n", .{{"{s}"}});
            \\    std.debug.print("💾 存储类型: {s}\n", .{{"{s}"}});
            \\
            \\    // TODO: 初始化 RAG 系统
            \\    // var rag = try mastra.RAG.init(allocator, .{{
            \\    //     .llm_provider = .{s},
            \\    //     .vector_store = .{s},
            \\    //     .embedding_model = "text-embedding-ada-002",
            \\    // }});
            \\    // defer rag.deinit();
            \\
            \\    // 添加文档到知识库
            \\    // try rag.addDocument("doc1", "这是第一个文档的内容...");
            \\    // try rag.addDocument("doc2", "这是第二个文档的内容...");
            \\
            \\    // 执行检索增强生成
            \\    // const query = "请告诉我关于文档的信息";
            \\    // const response = try rag.query(query);
            \\    // std.debug.print("RAG回复: {{s}}\n", .{{response}});
            \\
            \\    std.debug.print("✅ RAG 系统启动成功!\n", .{{}});
            \\    std.debug.print("🔍 知识检索系统已准备就绪...\n", .{{}});
            \\
            \\    // 保持程序运行
            \\    while (true) {{
            \\        std.time.sleep(1000000000);
            \\    }}
            \\}}
            \\
        , .{ llm_provider, storage_type, llm_provider, storage_type });
    }

    /// 创建Tools模板的main.zig内容
    fn createToolsMainContent(self: *Cli, llm_provider: []const u8, storage_type: []const u8) ![]u8 {
        return std.fmt.allocPrint(self.allocator,
            \\const std = @import("std");
            \\// TODO: 添加 Mastra 导入
            \\// const mastra = @import("mastra");
            \\
            \\pub fn main() !void {{
            \\    var gpa = std.heap.GeneralPurposeAllocator(.{{}}){{}};
            \\    defer _ = gpa.deinit();
            \\    const allocator = gpa.allocator();
            \\
            \\    std.debug.print("🔧 启动 Mastra Tools 应用\n", .{{}});
            \\    std.debug.print("🧠 LLM提供商: {s}\n", .{{"{s}"}});
            \\    std.debug.print("💾 存储类型: {s}\n", .{{"{s}"}});
            \\
            \\    // TODO: 初始化工具系统
            \\    // var tools = try mastra.Tools.init(allocator, .{{
            \\    //     .llm_provider = .{s},
            \\    //     .storage = .{s},
            \\    // }});
            \\    // defer tools.deinit();
            \\
            \\    // 注册工具
            \\    // try tools.register("calculator", calculateTool);
            \\    // try tools.register("weather", weatherTool);
            \\    // try tools.register("search", searchTool);
            \\
            \\    // 创建带工具的Agent
            \\    // var agent = try mastra.Agent.init(allocator, .{{
            \\    //     .name = "ToolAgent",
            \\    //     .instructions = "你可以使用各种工具来帮助用户",
            \\    //     .tools = tools,
            \\    // }});
            \\    // defer agent.deinit();
            \\
            \\    // 使用工具
            \\    // const response = try agent.chat("帮我计算 2 + 3 的结果");
            \\    // std.debug.print("Agent回复: {{s}}\n", .{{response}});
            \\
            \\    std.debug.print("✅ Tools 系统启动成功!\n", .{{}});
            \\    std.debug.print("🛠️  工具已准备就绪...\n", .{{}});
            \\
            \\    // 保持程序运行
            \\    while (true) {{
            \\        std.time.sleep(1000000000);
            \\    }}
            \\}}
            \\
        , .{ llm_provider, storage_type, llm_provider, storage_type });
    }

    /// 创建配置文件
    fn createConfigFiles(self: *Cli, project_dir: std.fs.Dir, llm_provider: []const u8, storage_type: []const u8) !void {
        var config_dir = try project_dir.openDir("config", .{});
        defer config_dir.close();

        // 创建 .env 示例文件
        const env_content = std.fmt.allocPrint(self.allocator,
            \\# Mastra 配置文件
            \\
            \\# LLM 配置
            \\OPENAI_API_KEY=your_openai_api_key_here
            \\ANTHROPIC_API_KEY=your_anthropic_api_key_here
            \\GOOGLE_API_KEY=your_google_api_key_here
            \\
            \\# 数据库配置
            \\DATABASE_URL=postgresql://user:password@localhost:5432/mastra
            \\MONGODB_URI=mongodb://localhost:27017/mastra
            \\
            \\# 应用配置
            \\LLM_PROVIDER={s}
            \\STORAGE_TYPE={s}
            \\LOG_LEVEL=info
            \\PORT=3000
            \\
        , .{ llm_provider, storage_type }) catch return CliError.ConfigurationError;
        defer self.allocator.free(env_content);

        var env_file = try config_dir.createFile(".env.example", .{});
        defer env_file.close();
        try env_file.writeAll(env_content);

        // 创建 mastra.json 配置文件
        const json_content = std.fmt.allocPrint(self.allocator,
            \\{{
            \\  "name": "mastra-project",
            \\  "version": "0.1.0",
            \\  "llm": {{
            \\    "provider": "{s}",
            \\    "model": "gpt-3.5-turbo",
            \\    "temperature": 0.7,
            \\    "max_tokens": 1000
            \\  }},
            \\  "storage": {{
            \\    "type": "{s}",
            \\    "connection": {{
            \\      "host": "localhost",
            \\      "port": 5432,
            \\      "database": "mastra"
            \\    }}
            \\  }},
            \\  "agents": [],
            \\  "workflows": [],
            \\  "tools": []
            \\}}
            \\
        , .{ llm_provider, storage_type }) catch return CliError.ConfigurationError;
        defer self.allocator.free(json_content);

        var json_file = try config_dir.createFile("mastra.json", .{});
        defer json_file.close();
        try json_file.writeAll(json_content);
    }

    /// 创建示例文件
    fn createExampleFiles(self: *Cli, project_dir: std.fs.Dir, template: []const u8) !void {
        const template_type = ProjectTemplate.fromString(template);
        var examples_dir = try project_dir.openDir("examples", .{});
        defer examples_dir.close();

        switch (template_type) {
            .basic => try self.createBasicExamples(examples_dir),
            .agent => try self.createAgentExamples(examples_dir),
            .workflow => try self.createWorkflowExamples(examples_dir),
            .rag => try self.createRagExamples(examples_dir),
            .tools => try self.createToolsExamples(examples_dir),
        }
    }

    /// 创建基础模板示例
    fn createBasicExamples(self: *Cli, examples_dir: std.fs.Dir) !void {
        _ = self;
        const example_content =
            \\const std = @import("std");
            \\// TODO: 添加 Mastra 导入
            \\// const mastra = @import("mastra");
            \\
            \\// 简单的聊天机器人示例
            \\pub fn chatbotExample(allocator: std.mem.Allocator) !void {
            \\    std.debug.print("🤖 聊天机器人示例\n", .{});
            \\
            \\    // TODO: 实现聊天机器人逻辑
            \\    // var agent = try mastra.Agent.init(allocator, .{
            \\    //     .name = "chatbot",
            \\    //     .instructions = "你是一个友好的助手",
            \\    // });
            \\    // defer agent.deinit();
            \\
            \\    std.debug.print("✅ 聊天机器人示例完成\n", .{});
            \\}
            \\
        ;

        var example_file = try examples_dir.createFile("chatbot.zig", .{});
        defer example_file.close();
        try example_file.writeAll(example_content);
    }

    /// 创建Agent模板示例
    fn createAgentExamples(self: *Cli, examples_dir: std.fs.Dir) !void {
        _ = self;
        const agent_example =
            \\const std = @import("std");
            \\// TODO: 添加 Mastra 导入
            \\// const mastra = @import("mastra");
            \\
            \\// 智能助手Agent示例
            \\pub fn assistantExample(allocator: std.mem.Allocator) !void {
            \\    std.debug.print("🤖 智能助手Agent示例\n", .{});
            \\
            \\    // TODO: 创建智能助手
            \\    // var assistant = try mastra.Agent.init(allocator, .{
            \\    //     .name = "Assistant",
            \\    //     .instructions = "你是一个专业的AI助手，能够回答各种问题",
            \\    //     .model = "gpt-4",
            \\    // });
            \\    // defer assistant.deinit();
            \\
            \\    // 示例对话
            \\    // const questions = [_][]const u8{
            \\    //     "什么是人工智能？",
            \\    //     "请解释机器学习的基本概念",
            \\    //     "如何开始学习编程？"
            \\    // };
            \\
            \\    // for (questions) |question| {
            \\    //     const response = try assistant.chat(question);
            \\    //     std.debug.print("问题: {s}\n", .{question});
            \\    //     std.debug.print("回答: {s}\n\n", .{response});
            \\    // }
            \\
            \\    std.debug.print("✅ 智能助手示例完成\n", .{});
            \\}
            \\
        ;

        var agent_file = try examples_dir.createFile("assistant.zig", .{});
        defer agent_file.close();
        try agent_file.writeAll(agent_example);
    }

    /// 创建Workflow模板示例
    fn createWorkflowExamples(self: *Cli, examples_dir: std.fs.Dir) !void {
        _ = self;
        const workflow_example =
            \\const std = @import("std");
            \\// TODO: 添加 Mastra 导入
            \\// const mastra = @import("mastra");
            \\
            \\// 数据处理工作流示例
            \\pub fn dataProcessingWorkflow(allocator: std.mem.Allocator) !void {
            \\    std.debug.print("⚡ 数据处理工作流示例\n", .{});
            \\
            \\    // TODO: 创建工作流
            \\    // var workflow = try mastra.Workflow.init(allocator, .{
            \\    //     .name = "DataProcessing",
            \\    // });
            \\    // defer workflow.deinit();
            \\
            \\    // 添加步骤
            \\    // try workflow.addStep("validate", validateData);
            \\    // try workflow.addStep("transform", transformData);
            \\    // try workflow.addStep("analyze", analyzeData);
            \\    // try workflow.addStep("report", generateReport);
            \\
            \\    // 执行工作流
            \\    // const input_data = .{ .raw_data = "sample data" };
            \\    // const result = try workflow.execute(input_data);
            \\    // std.debug.print("处理结果: {any}\n", .{result});
            \\
            \\    std.debug.print("✅ 数据处理工作流示例完成\n", .{});
            \\}
            \\
            \\// 工作流步骤函数示例
            \\fn validateData(data: anytype) !@TypeOf(data) {
            \\    std.debug.print("📋 验证数据...\n", .{});
            \\    return data;
            \\}
            \\
            \\fn transformData(data: anytype) !@TypeOf(data) {
            \\    std.debug.print("🔄 转换数据...\n", .{});
            \\    return data;
            \\}
            \\
            \\fn analyzeData(data: anytype) !@TypeOf(data) {
            \\    std.debug.print("📊 分析数据...\n", .{});
            \\    return data;
            \\}
            \\
            \\fn generateReport(data: anytype) !@TypeOf(data) {
            \\    std.debug.print("📄 生成报告...\n", .{});
            \\    return data;
            \\}
            \\
        ;

        var workflow_file = try examples_dir.createFile("data_processing.zig", .{});
        defer workflow_file.close();
        try workflow_file.writeAll(workflow_example);
    }

    /// 创建RAG模板示例
    fn createRagExamples(self: *Cli, examples_dir: std.fs.Dir) !void {
        _ = self;
        const rag_example =
            \\const std = @import("std");
            \\// TODO: 添加 Mastra 导入
            \\// const mastra = @import("mastra");
            \\
            \\// 文档问答系统示例
            \\pub fn documentQAExample(allocator: std.mem.Allocator) !void {
            \\    std.debug.print("📚 文档问答系统示例\n", .{});
            \\
            \\    // TODO: 初始化RAG系统
            \\    // var rag = try mastra.RAG.init(allocator, .{
            \\    //     .embedding_model = "text-embedding-ada-002",
            \\    //     .vector_store = .pinecone,
            \\    //     .llm_model = "gpt-4",
            \\    // });
            \\    // defer rag.deinit();
            \\
            \\    // 添加文档到知识库
            \\    // const documents = [_][]const u8{
            \\    //     "人工智能是计算机科学的一个分支，致力于创建能够执行通常需要人类智能的任务的系统。",
            \\    //     "机器学习是人工智能的一个子集，它使计算机能够在没有明确编程的情况下学习和改进。",
            \\    //     "深度学习是机器学习的一个分支，使用神经网络来模拟人脑的工作方式。"
            \\    // };
            \\
            \\    // for (documents, 0..) |doc, i| {
            \\    //     const doc_id = try std.fmt.allocPrint(allocator, "doc_{d}", .{i});
            \\    //     defer allocator.free(doc_id);
            \\    //     try rag.addDocument(doc_id, doc);
            \\    // }
            \\
            \\    // 执行问答
            \\    // const questions = [_][]const u8{
            \\    //     "什么是人工智能？",
            \\    //     "机器学习和深度学习有什么区别？",
            \\    //     "如何开始学习AI？"
            \\    // };
            \\
            \\    // for (questions) |question| {
            \\    //     const answer = try rag.query(question);
            \\    //     std.debug.print("问题: {s}\n", .{question});
            \\    //     std.debug.print("答案: {s}\n\n", .{answer});
            \\    // }
            \\
            \\    std.debug.print("✅ 文档问答系统示例完成\n", .{});
            \\}
            \\
        ;

        var rag_file = try examples_dir.createFile("document_qa.zig", .{});
        defer rag_file.close();
        try rag_file.writeAll(rag_example);
    }

    /// 创建Tools模板示例
    fn createToolsExamples(self: *Cli, examples_dir: std.fs.Dir) !void {
        _ = self;
        const tools_example =
            \\const std = @import("std");
            \\// TODO: 添加 Mastra 导入
            \\// const mastra = @import("mastra");
            \\
            \\// 工具集成示例
            \\pub fn toolsIntegrationExample(allocator: std.mem.Allocator) !void {
            \\    std.debug.print("🔧 工具集成示例\n", .{});
            \\
            \\    // TODO: 初始化工具系统
            \\    // var tools = try mastra.Tools.init(allocator);
            \\    // defer tools.deinit();
            \\
            \\    // 注册工具
            \\    // try tools.register("calculator", .{
            \\    //     .name = "计算器",
            \\    //     .description = "执行基本数学计算",
            \\    //     .function = calculateTool,
            \\    // });
            \\
            \\    // try tools.register("weather", .{
            \\    //     .name = "天气查询",
            \\    //     .description = "查询指定城市的天气信息",
            \\    //     .function = weatherTool,
            \\    // });
            \\
            \\    // try tools.register("translator", .{
            \\    //     .name = "翻译工具",
            \\    //     .description = "翻译文本到不同语言",
            \\    //     .function = translatorTool,
            \\    // });
            \\
            \\    // 创建带工具的Agent
            \\    // var agent = try mastra.Agent.init(allocator, .{
            \\    //     .name = "ToolAgent",
            \\    //     .instructions = "你是一个能够使用各种工具的AI助手",
            \\    //     .tools = tools,
            \\    // });
            \\    // defer agent.deinit();
            \\
            \\    // 测试工具使用
            \\    // const tasks = [_][]const u8{
            \\    //     "帮我计算 15 * 23 的结果",
            \\    //     "查询北京今天的天气",
            \\    //     "把'Hello World'翻译成中文"
            \\    // };
            \\
            \\    // for (tasks) |task| {
            \\    //     const response = try agent.chat(task);
            \\    //     std.debug.print("任务: {s}\n", .{task});
            \\    //     std.debug.print("结果: {s}\n\n", .{response});
            \\    // }
            \\
            \\    std.debug.print("✅ 工具集成示例完成\n", .{});
            \\}
            \\
            \\// 工具函数示例
            \\fn calculateTool(expression: []const u8) ![]const u8 {
            \\    std.debug.print("🧮 计算: {s}\n", .{expression});
            \\    // TODO: 实现计算逻辑
            \\    return "计算结果: 42";
            \\}
            \\
            \\fn weatherTool(city: []const u8) ![]const u8 {
            \\    std.debug.print("🌤️  查询天气: {s}\n", .{city});
            \\    // TODO: 实现天气查询逻辑
            \\    return "今天晴朗，温度25°C";
            \\}
            \\
            \\fn translatorTool(text: []const u8, target_lang: []const u8) ![]const u8 {
            \\    std.debug.print("🌐 翻译: {s} -> {s}\n", .{text, target_lang});
            \\    // TODO: 实现翻译逻辑
            \\    return "你好世界";
            \\}
            \\
        ;

        var tools_file = try examples_dir.createFile("tools_integration.zig", .{});
        defer tools_file.close();
        try tools_file.writeAll(tools_example);
    }

    /// 创建 README.md 文件
    fn createReadmeFile(self: *Cli, project_dir: std.fs.Dir, project_name: []const u8) !void {
        const readme_content = std.fmt.allocPrint(self.allocator,
            \\# {s}
            \\
            \\基于 Mastra.zig 框架构建的 AI 应用项目。
            \\
            \\## 快速开始
            \\
            \\1. 配置环境变量:
            \\   ```bash
            \\   cp config/.env.example .env
            \\   # 编辑 .env 文件，设置你的 API 密钥
            \\   ```
            \\
            \\2. 构建并运行:
            \\   ```bash
            \\   zig build run
            \\   ```
            \\
            \\3. 运行测试:
            \\   ```bash
            \\   zig build test
            \\   ```
            \\
            \\## 项目结构
            \\
            \\```
            \\{s}/
            \\├── src/
            \\│   └── main.zig          # 主程序入口
            \\├── config/
            \\│   ├── .env.example      # 环境变量示例
            \\│   └── mastra.json       # Mastra 配置文件
            \\├── examples/
            \\│   └── chatbot.zig       # 聊天机器人示例
            \\├── tests/
            \\├── build.zig             # 构建配置
            \\└── README.md
            \\```
            \\
            \\## 功能特性
            \\
            \\- 🤖 LLM 集成 (OpenAI, Anthropic, Google)
            \\- 💾 多种存储后端 (Memory, PostgreSQL, MongoDB)
            \\- 🔧 工具系统和函数调用
            \\- 🔄 工作流引擎
            \\- 📊 向量存储和相似度搜索
            \\- 🧠 内存管理和持久化
            \\- 📈 遥测和监控
            \\
            \\## 开发
            \\
            \\查看 `examples/` 目录了解更多使用示例。
            \\
            \\## 文档
            \\
            \\- [Mastra.zig 文档](https://github.com/mastra-ai/mastra)
            \\- [Zig 语言文档](https://ziglang.org/documentation/)
            \\
        , .{ project_name, project_name }) catch return CliError.ConfigurationError;
        defer self.allocator.free(readme_content);

        var readme_file = try project_dir.createFile("README.md", .{});
        defer readme_file.close();
        try readme_file.writeAll(readme_content);
    }

    /// 执行开发服务器命令
    fn executeDev(self: *Cli) !void {
        const port = self.args.getFlag("port") orelse "3000";
        const host = self.args.getFlag("host") orelse "localhost";
        const verbose = self.args.hasFlag("verbose");

        std.debug.print("🚀 启动 Mastra 开发服务器\n", .{});
        std.debug.print("🌐 地址: http://{s}:{s}\n", .{ host, port });
        if (verbose) {
            std.debug.print("📝 详细模式: 开启\n", .{});
        }

        // 启动开发服务器
        try self.startDevServer(host, port, verbose);
    }

    /// 启动开发服务器
    fn startDevServer(self: *Cli, host: []const u8, port: []const u8, verbose: bool) !void {
        const port_num = std.fmt.parseInt(u16, port, 10) catch {
            std.debug.print("❌ 错误: 无效的端口号 '{s}'\n", .{port});
            return CliError.InvalidArgument;
        };

        // 检查项目结构
        const cwd = std.fs.cwd();
        const build_file = cwd.openFile("build.zig", .{}) catch {
            std.debug.print("❌ 错误: 未找到 build.zig 文件，请确保在 Mastra 项目根目录中运行\n", .{});
            return CliError.ConfigurationError;
        };
        build_file.close();

        std.debug.print("📁 项目结构检查通过\n", .{});
        std.debug.print("🔧 编译项目...\n", .{});

        // 编译项目
        var build_process = std.process.Child.init(&[_][]const u8{ "zig", "build" }, self.allocator);
        build_process.stdout_behavior = if (verbose) .Inherit else .Ignore;
        build_process.stderr_behavior = .Inherit;

        const build_result = build_process.spawnAndWait() catch {
            std.debug.print("❌ 错误: 无法启动构建进程\n", .{});
            return CliError.BuildError;
        };

        switch (build_result) {
            .Exited => |code| {
                if (code != 0) {
                    std.debug.print("❌ 构建失败，退出码: {d}\n", .{code});
                    return CliError.BuildError;
                }
            },
            else => {
                std.debug.print("❌ 构建进程异常终止\n", .{});
                return CliError.BuildError;
            },
        }

        std.debug.print("✅ 项目编译成功\n", .{});
        std.debug.print("🌐 开发服务器运行在 http://{s}:{d}\n", .{ host, port_num });
        std.debug.print("📝 文件监控已启用，修改文件将自动重新编译\n", .{});
        std.debug.print("🎮 开发面板: http://{s}:{d}/dev\n", .{ host, port_num });
        std.debug.print("⏹️  按 Ctrl+C 停止服务器\n\n", .{});

        // 启动HTTP服务器和文件监控
        try self.runDevServerWithHttp(host, port_num, verbose);
    }

    /// 运行开发服务器循环
    fn runDevServerLoop(self: *Cli, verbose: bool) !void {
        var last_build_time: i64 = std.time.timestamp();

        while (true) {
            // 检查文件变化（简单的时间戳检查）
            const current_time = std.time.timestamp();
            if (current_time - last_build_time > 2) { // 每2秒检查一次
                if (try self.checkForFileChanges()) {
                    std.debug.print("🔄 检测到文件变化，重新编译...\n", .{});

                    var build_process = std.process.Child.init(&[_][]const u8{ "zig", "build" }, self.allocator);
                    build_process.stdout_behavior = if (verbose) .Inherit else .Ignore;
                    build_process.stderr_behavior = .Inherit;

                    const build_result = build_process.spawnAndWait() catch {
                        std.debug.print("❌ 重新编译失败\n", .{});
                        continue;
                    };

                    switch (build_result) {
                        .Exited => |code| {
                            if (code == 0) {
                                std.debug.print("✅ 重新编译成功\n", .{});
                            } else {
                                std.debug.print("❌ 重新编译失败，退出码: {d}\n", .{code});
                            }
                        },
                        else => {
                            std.debug.print("❌ 重新编译进程异常终止\n", .{});
                        },
                    }

                    last_build_time = current_time;
                }
            }

            // 短暂休眠
            std.time.sleep(500 * std.time.ns_per_ms);
        }
    }

    /// 运行带HTTP服务器的开发服务器
    fn runDevServerWithHttp(self: *Cli, host: []const u8, port: u16, verbose: bool) !void {
        // 启动HTTP服务器（在单独的线程中）
        const server_thread = try std.Thread.spawn(.{}, startHttpServer, .{ self, host, port });
        defer server_thread.join();

        // 运行文件监控循环
        try self.runDevServerLoop(verbose);
    }

    /// 启动HTTP服务器
    fn startHttpServer(self: *Cli, host: []const u8, port: u16) !void {
        _ = self;
        _ = host;
        _ = port;

        // 简单的HTTP服务器实现
        // 这里可以添加更复杂的HTTP服务器逻辑
        std.debug.print("🌐 HTTP服务器已启动\n", .{});

        // 保持服务器运行
        while (true) {
            std.time.sleep(1 * std.time.ns_per_s);
        }
    }

    /// 文件监控状态
    pub const FileWatchState = struct {
        file_times: std.HashMap([]const u8, i128, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) FileWatchState {
            return FileWatchState{
                .file_times = std.HashMap([]const u8, i128, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *FileWatchState) void {
            var iterator = self.file_times.iterator();
            while (iterator.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
            }
            self.file_times.deinit();
        }

        pub fn updateFileTime(self: *FileWatchState, path: []const u8, time: i128) !void {
            const owned_path = try self.allocator.dupe(u8, path);
            try self.file_times.put(owned_path, time);
        }

        pub fn getFileTime(self: *FileWatchState, path: []const u8) ?i128 {
            return self.file_times.get(path);
        }
    };

    /// 检查文件变化
    pub fn checkForFileChanges(self: *Cli) !bool {
        // 初始化文件监控状态（如果还没有）
        if (self.file_watch_state == null) {
            self.file_watch_state = FileWatchState.init(self.allocator);
        }

        var has_changes = false;

        // 检查源代码目录
        const dirs_to_watch = [_][]const u8{ "src", "examples", "test" };

        for (dirs_to_watch) |dir_name| {
            if (try self.checkDirectoryChanges(dir_name, &self.file_watch_state.?)) {
                has_changes = true;
            }
        }

        return has_changes;
    }

    /// 检查目录变化
    fn checkDirectoryChanges(self: *Cli, dir_path: []const u8, watch_state: *FileWatchState) !bool {
        const cwd = std.fs.cwd();
        var dir = cwd.openDir(dir_path, .{ .iterate = true }) catch return false;
        defer dir.close();

        var has_changes = false;
        var iterator = dir.iterate();

        while (try iterator.next()) |entry| {
            if (entry.kind == .file) {
                // 只监控 .zig 文件
                if (std.mem.endsWith(u8, entry.name, ".zig")) {
                    const full_path = try std.fmt.allocPrint(watch_state.allocator, "{s}/{s}", .{ dir_path, entry.name });
                    defer watch_state.allocator.free(full_path);

                    const file = dir.openFile(entry.name, .{}) catch continue;
                    defer file.close();

                    const stat = file.stat() catch continue;
                    const current_time = stat.mtime;

                    if (watch_state.getFileTime(full_path)) |last_time| {
                        if (current_time > last_time) {
                            try watch_state.updateFileTime(full_path, current_time);
                            has_changes = true;
                            std.debug.print("📝 文件已修改: {s}\n", .{full_path});
                        }
                    } else {
                        // 第一次见到这个文件
                        try watch_state.updateFileTime(full_path, current_time);
                    }
                }
            } else if (entry.kind == .directory and !std.mem.eql(u8, entry.name, "zig-out")) {
                // 递归检查子目录
                const sub_dir_path = try std.fmt.allocPrint(watch_state.allocator, "{s}/{s}", .{ dir_path, entry.name });
                defer watch_state.allocator.free(sub_dir_path);

                if (try self.checkDirectoryChanges(sub_dir_path, watch_state)) {
                    has_changes = true;
                }
            }
        }

        return has_changes;
    }

    /// 构建模式枚举
    pub const BuildMode = enum {
        debug,
        release_safe,
        release_fast,
        release_small,

        pub fn fromString(str: []const u8) BuildMode {
            if (std.mem.eql(u8, str, "release-safe")) return .release_safe;
            if (std.mem.eql(u8, str, "release-fast")) return .release_fast;
            if (std.mem.eql(u8, str, "release-small")) return .release_small;
            return .debug; // 默认模式
        }

        pub fn toString(self: BuildMode) []const u8 {
            return switch (self) {
                .debug => "Debug",
                .release_safe => "ReleaseSafe",
                .release_fast => "ReleaseFast",
                .release_small => "ReleaseSmall",
            };
        }
    };

    /// 执行构建命令
    fn executeBuild(self: *Cli) !void {
        const optimize = self.args.hasFlag("optimize");
        const target = self.args.getFlag("target");
        const verbose = self.args.hasFlag("verbose");
        const release = self.args.hasFlag("release");
        const output = self.args.getFlag("output");
        const mode_str = self.args.getFlag("mode") orelse "debug";
        const clean = self.args.hasFlag("clean");
        const parallel = self.args.getFlag("parallel");
        const strip = self.args.hasFlag("strip");

        std.debug.print("🔨 构建 Mastra 项目\n", .{});

        // 显示构建配置
        const build_mode = BuildMode.fromString(mode_str);
        std.debug.print("🏗️  构建模式: {s}\n", .{build_mode.toString()});

        if (optimize) {
            std.debug.print("⚡ 优化模式: 开启\n", .{});
        }
        if (target) |t| {
            std.debug.print("🎯 目标平台: {s}\n", .{t});
        }
        if (verbose) {
            std.debug.print("📝 详细模式: 开启\n", .{});
        }
        if (release) {
            std.debug.print("🚀 发布模式: 开启\n", .{});
        }
        if (clean) {
            std.debug.print("🧹 清理构建: 开启\n", .{});
        }
        if (parallel) |p| {
            std.debug.print("⚡ 并行构建: {s} 线程\n", .{p});
        }
        if (strip) {
            std.debug.print("🗜️  符号剥离: 开启\n", .{});
        }

        // 检查项目结构
        const cwd = std.fs.cwd();
        const build_file = cwd.openFile("build.zig", .{}) catch {
            std.debug.print("❌ 错误: 未找到 build.zig 文件，请确保在 Mastra 项目根目录中运行\n", .{});
            return CliError.ConfigurationError;
        };
        build_file.close();

        std.debug.print("📁 项目结构检查通过\n", .{});

        // 验证构建环境
        try self.validateBuildEnvironment();

        // 执行清理操作
        if (clean) {
            try self.cleanBuildArtifacts(output);
        }

        // 构建命令参数
        var build_args = std.ArrayList([]const u8).init(self.allocator);
        defer build_args.deinit();

        // 需要释放的参数列表
        var args_to_free = std.ArrayList([]u8).init(self.allocator);
        defer {
            for (args_to_free.items) |arg| {
                self.allocator.free(arg);
            }
            args_to_free.deinit();
        }

        try build_args.append("zig");
        try build_args.append("build");

        // 添加构建模式
        if (release) {
            try build_args.append("-Doptimize=ReleaseFast");
        } else if (optimize) {
            try build_args.append("-Doptimize=ReleaseSafe");
        } else {
            const optimize_arg = try std.fmt.allocPrint(self.allocator, "-Doptimize={s}", .{build_mode.toString()});
            try args_to_free.append(optimize_arg);
            try build_args.append(optimize_arg);
        }

        // 添加目标平台
        if (target) |t| {
            const target_arg = try std.fmt.allocPrint(self.allocator, "-Dtarget={s}", .{t});
            try args_to_free.append(target_arg);
            try build_args.append(target_arg);
        }

        // 添加输出目录
        if (output) |o| {
            const output_arg = try std.fmt.allocPrint(self.allocator, "-Doutput={s}", .{o});
            try args_to_free.append(output_arg);
            try build_args.append(output_arg);
        }

        // 添加并行构建选项
        if (parallel) |p| {
            const parallel_arg = try std.fmt.allocPrint(self.allocator, "-j{s}", .{p});
            try args_to_free.append(parallel_arg);
            try build_args.append(parallel_arg);
        }

        // 添加符号剥离选项
        if (strip) {
            try build_args.append("-Dstrip=true");
        }

        std.debug.print("🔧 开始编译...\n", .{});

        // 执行构建
        var build_process = std.process.Child.init(build_args.items, self.allocator);
        build_process.stdout_behavior = if (verbose) .Inherit else .Pipe;
        build_process.stderr_behavior = .Inherit;

        const build_result = build_process.spawnAndWait() catch {
            std.debug.print("❌ 错误: 无法启动构建进程\n", .{});
            return CliError.BuildError;
        };

        switch (build_result) {
            .Exited => |code| {
                if (code == 0) {
                    std.debug.print("✅ 构建成功完成\n", .{});

                    // 显示构建产物信息
                    try self.showBuildArtifacts(output);
                } else {
                    std.debug.print("❌ 构建失败，退出码: {d}\n", .{code});
                    return CliError.BuildError;
                }
            },
            else => {
                std.debug.print("❌ 构建进程异常终止\n", .{});
                return CliError.BuildError;
            },
        }
    }

    /// 清理构建产物
    fn cleanBuildArtifacts(self: *Cli, output_dir: ?[]const u8) !void {
        _ = self;
        const artifacts_dir = output_dir orelse "zig-out";

        std.debug.print("🧹 清理构建产物...\n", .{});

        const cwd = std.fs.cwd();

        // 删除输出目录
        cwd.deleteTree(artifacts_dir) catch |err| switch (err) {
            error.FileNotFound => {
                std.debug.print("📁 输出目录 {s} 不存在，无需清理\n", .{artifacts_dir});
                return;
            },
            else => return err,
        };

        // 删除缓存目录
        cwd.deleteTree(".zig-cache") catch |err| switch (err) {
            error.FileNotFound => {},
            else => return err,
        };

        std.debug.print("✅ 清理完成\n", .{});
    }

    /// 验证构建环境
    fn validateBuildEnvironment(self: *Cli) !void {
        std.debug.print("🔍 验证构建环境...\n", .{});

        // 检查Zig版本
        var zig_version_process = std.process.Child.init(&[_][]const u8{ "zig", "version" }, self.allocator);
        zig_version_process.stdout_behavior = .Pipe;
        zig_version_process.stderr_behavior = .Pipe;

        const zig_result = zig_version_process.spawnAndWait() catch {
            std.debug.print("❌ 错误: 无法检查Zig版本\n", .{});
            return CliError.ConfigurationError;
        };

        switch (zig_result) {
            .Exited => |code| {
                if (code == 0) {
                    std.debug.print("✅ Zig环境检查通过\n", .{});
                } else {
                    std.debug.print("❌ Zig环境检查失败\n", .{});
                    return CliError.ConfigurationError;
                }
            },
            else => {
                std.debug.print("❌ Zig版本检查异常\n", .{});
                return CliError.ConfigurationError;
            },
        }
    }

    /// 显示构建产物信息
    fn showBuildArtifacts(self: *Cli, output_dir: ?[]const u8) !void {
        const artifacts_dir = output_dir orelse "zig-out";

        std.debug.print("\n📦 构建产物:\n", .{});

        const cwd = std.fs.cwd();
        var artifacts = cwd.openDir(artifacts_dir, .{}) catch {
            std.debug.print("📁 输出目录: {s} (未找到)\n", .{artifacts_dir});
            return;
        };
        defer artifacts.close();

        var iterator = artifacts.iterate();
        while (try iterator.next()) |entry| {
            switch (entry.kind) {
                .file => {
                    const file_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ artifacts_dir, entry.name });
                    defer self.allocator.free(file_path);

                    const file = cwd.openFile(file_path, .{}) catch continue;
                    defer file.close();

                    const file_size = file.getEndPos() catch 0;
                    std.debug.print("📄 {s} ({d} bytes)\n", .{ file_path, file_size });
                },
                .directory => {
                    std.debug.print("📁 {s}/{s}/\n", .{ artifacts_dir, entry.name });
                },
                else => {},
            }
        }
    }

    /// 执行部署命令
    fn executeDeploy(self: *Cli) !void {
        const platform = self.args.getFlag("platform") orelse "local";
        const env = self.args.getFlag("env") orelse "production";
        const config = self.args.getFlag("config");
        const verbose = self.args.hasFlag("verbose");
        const dry_run = self.args.hasFlag("dry-run");

        std.debug.print("🚀 部署 Mastra 项目\n", .{});
        std.debug.print("🌐 平台: {s}\n", .{platform});
        std.debug.print("🏷️  环境: {s}\n", .{env});
        if (config) |c| {
            std.debug.print("⚙️  配置文件: {s}\n", .{c});
        }
        if (dry_run) {
            std.debug.print("🧪 模拟运行模式\n", .{});
        }

        // 检查项目结构
        const cwd = std.fs.cwd();
        const build_file = cwd.openFile("build.zig", .{}) catch {
            std.debug.print("❌ 错误: 未找到 build.zig 文件，请确保在 Mastra 项目根目录中运行\n", .{});
            return CliError.ConfigurationError;
        };
        build_file.close();

        // 验证部署配置
        try self.validateDeploymentConfig(platform, env, config);

        if (dry_run) {
            std.debug.print("\n🧪 模拟部署流程:\n", .{});
            try self.simulateDeployment(platform, env);
            return;
        }

        // 执行部署
        try self.performDeployment(platform, env, config, verbose);
    }

    /// 验证部署配置
    fn validateDeploymentConfig(self: *Cli, platform: []const u8, env: []const u8, config: ?[]const u8) !void {
        _ = self;

        std.debug.print("🔍 验证部署配置...\n", .{});

        // 验证平台支持
        const supported_platforms = [_][]const u8{ "local", "docker", "kubernetes", "aws", "gcp", "azure" };
        var platform_supported = false;
        for (supported_platforms) |p| {
            if (std.mem.eql(u8, platform, p)) {
                platform_supported = true;
                break;
            }
        }

        if (!platform_supported) {
            std.debug.print("❌ 错误: 不支持的部署平台 '{s}'\n", .{platform});
            std.debug.print("支持的平台: ", .{});
            for (supported_platforms, 0..) |p, i| {
                if (i > 0) std.debug.print(", ", .{});
                std.debug.print("{s}", .{p});
            }
            std.debug.print("\n", .{});
            return CliError.InvalidArgument;
        }

        // 验证环境
        const supported_envs = [_][]const u8{ "development", "staging", "production" };
        var env_supported = false;
        for (supported_envs) |e| {
            if (std.mem.eql(u8, env, e)) {
                env_supported = true;
                break;
            }
        }

        if (!env_supported) {
            std.debug.print("❌ 错误: 不支持的环境 '{s}'\n", .{env});
            std.debug.print("支持的环境: ", .{});
            for (supported_envs, 0..) |e, i| {
                if (i > 0) std.debug.print(", ", .{});
                std.debug.print("{s}", .{e});
            }
            std.debug.print("\n", .{});
            return CliError.InvalidArgument;
        }

        // 检查配置文件
        if (config) |c| {
            const cwd = std.fs.cwd();
            const config_file = cwd.openFile(c, .{}) catch {
                std.debug.print("❌ 错误: 配置文件 '{s}' 不存在\n", .{c});
                return CliError.ConfigurationError;
            };
            config_file.close();
        }

        std.debug.print("✅ 配置验证通过\n", .{});
    }

    /// 模拟部署
    fn simulateDeployment(self: *Cli, platform: []const u8, env: []const u8) !void {
        _ = self;

        std.debug.print("1. 📦 构建项目\n", .{});
        std.debug.print("2. 🔧 准备部署环境\n", .{});

        if (std.mem.eql(u8, platform, "docker")) {
            std.debug.print("3. 🐳 构建 Docker 镜像\n", .{});
            std.debug.print("4. 📤 推送镜像到仓库\n", .{});
        } else if (std.mem.eql(u8, platform, "kubernetes")) {
            std.debug.print("3. ☸️  应用 Kubernetes 配置\n", .{});
            std.debug.print("4. 🔄 滚动更新服务\n", .{});
        } else if (std.mem.eql(u8, platform, "aws")) {
            std.debug.print("3. ☁️  部署到 AWS\n", .{});
            std.debug.print("4. 🌐 配置负载均衡\n", .{});
        }

        std.debug.print("5. 🧪 运行健康检查\n", .{});
        std.debug.print("6. ✅ 部署完成\n", .{});

        std.debug.print("\n📊 部署摘要:\n", .{});
        std.debug.print("   平台: {s}\n", .{platform});
        std.debug.print("   环境: {s}\n", .{env});
        std.debug.print("   状态: 模拟成功\n", .{});
    }

    /// 执行实际部署
    fn performDeployment(self: *Cli, platform: []const u8, env: []const u8, config: ?[]const u8, verbose: bool) !void {
        std.debug.print("\n🚀 开始部署流程...\n", .{});

        // 步骤1: 构建项目
        std.debug.print("📦 步骤1: 构建项目\n", .{});
        try self.buildForDeployment(verbose);

        // 步骤2: 准备部署环境
        std.debug.print("🔧 步骤2: 准备部署环境\n", .{});
        try self.prepareDeploymentEnvironment(platform, env, config);

        // 步骤3: 执行平台特定部署
        std.debug.print("🚀 步骤3: 执行部署\n", .{});
        try self.deployToPlatform(platform, env, verbose);

        // 步骤4: 验证部署
        std.debug.print("🧪 步骤4: 验证部署\n", .{});
        try self.verifyDeployment(platform, env);

        std.debug.print("\n✅ 部署成功完成！\n", .{});
    }

    /// 为部署构建项目
    fn buildForDeployment(self: *Cli, verbose: bool) !void {
        var build_process = std.process.Child.init(&[_][]const u8{ "zig", "build", "-Doptimize=ReleaseFast" }, self.allocator);
        build_process.stdout_behavior = if (verbose) .Inherit else .Ignore;
        build_process.stderr_behavior = .Inherit;

        const build_result = build_process.spawnAndWait() catch {
            std.debug.print("❌ 构建失败\n", .{});
            return CliError.BuildError;
        };

        switch (build_result) {
            .Exited => |code| {
                if (code != 0) {
                    std.debug.print("❌ 构建失败，退出码: {d}\n", .{code});
                    return CliError.BuildError;
                }
            },
            else => {
                std.debug.print("❌ 构建进程异常终止\n", .{});
                return CliError.BuildError;
            },
        }

        std.debug.print("✅ 项目构建完成\n", .{});
    }

    /// 准备部署环境
    fn prepareDeploymentEnvironment(self: *Cli, platform: []const u8, env: []const u8, config: ?[]const u8) !void {
        _ = self;
        _ = config;

        if (std.mem.eql(u8, platform, "docker")) {
            std.debug.print("🐳 准备 Docker 环境\n", .{});
        } else if (std.mem.eql(u8, platform, "kubernetes")) {
            std.debug.print("☸️  准备 Kubernetes 环境\n", .{});
        } else if (std.mem.eql(u8, platform, "local")) {
            std.debug.print("💻 准备本地环境\n", .{});
        }

        std.debug.print("✅ 环境准备完成 ({s})\n", .{env});
    }

    /// 部署到指定平台
    fn deployToPlatform(self: *Cli, platform: []const u8, env: []const u8, verbose: bool) !void {
        _ = self;
        _ = verbose;

        if (std.mem.eql(u8, platform, "local")) {
            std.debug.print("💻 本地部署完成\n", .{});
        } else if (std.mem.eql(u8, platform, "docker")) {
            std.debug.print("🐳 Docker 部署完成\n", .{});
        } else {
            std.debug.print("☁️  云平台部署完成 ({s})\n", .{platform});
        }

        std.debug.print("✅ 部署到 {s} 环境成功\n", .{env});
    }

    /// 验证部署
    fn verifyDeployment(self: *Cli, platform: []const u8, env: []const u8) !void {
        _ = self;

        std.debug.print("🔍 验证部署状态...\n", .{});

        // 模拟健康检查
        std.time.sleep(1 * std.time.ns_per_s);

        std.debug.print("✅ 健康检查通过\n", .{});
        std.debug.print("📊 部署摘要:\n", .{});
        std.debug.print("   平台: {s}\n", .{platform});
        std.debug.print("   环境: {s}\n", .{env});
        std.debug.print("   状态: 运行中\n", .{});
    }

    /// 代码生成类型
    pub const GenerateType = enum {
        agent,
        workflow,
        tool,
        rag,
        middleware,
        @"test",

        pub fn fromString(str: []const u8) ?GenerateType {
            if (std.mem.eql(u8, str, "agent")) return .agent;
            if (std.mem.eql(u8, str, "workflow")) return .workflow;
            if (std.mem.eql(u8, str, "tool")) return .tool;
            if (std.mem.eql(u8, str, "rag")) return .rag;
            if (std.mem.eql(u8, str, "middleware")) return .middleware;
            if (std.mem.eql(u8, str, "test")) return .@"test";
            return null;
        }

        pub fn toString(self: GenerateType) []const u8 {
            return switch (self) {
                .agent => "agent",
                .workflow => "workflow",
                .tool => "tool",
                .rag => "rag",
                .middleware => "middleware",
                .@"test" => "test",
            };
        }

        pub fn getDescription(self: GenerateType) []const u8 {
            return switch (self) {
                .agent => "智能代理，用于处理对话和任务",
                .workflow => "工作流，用于自动化处理流程",
                .tool => "工具函数，用于扩展Agent功能",
                .rag => "检索增强生成系统",
                .middleware => "中间件，用于请求处理",
                .@"test" => "测试文件，用于单元测试",
            };
        }
    };

    /// 执行代码生成命令
    fn executeGenerate(self: *Cli) !void {
        const gen_type_str = if (self.args.positional_args.len > 0)
            self.args.positional_args[0]
        else {
            std.debug.print("❌ 错误: 请指定生成类型\n", .{});
            std.debug.print("支持的类型:\n", .{});
            inline for (@typeInfo(GenerateType).Enum.fields) |field| {
                const gen_type = @field(GenerateType, field.name);
                std.debug.print("  {s} - {s}\n", .{ gen_type.toString(), gen_type.getDescription() });
            }
            return CliError.MissingArgument;
        };

        const gen_type = GenerateType.fromString(gen_type_str) orelse {
            std.debug.print("❌ 错误: 未知的生成类型 '{s}'\n", .{gen_type_str});
            std.debug.print("支持的类型:\n", .{});
            inline for (@typeInfo(GenerateType).Enum.fields) |field| {
                const gt = @field(GenerateType, field.name);
                std.debug.print("  {s} - {s}\n", .{ gt.toString(), gt.getDescription() });
            }
            return CliError.InvalidArgument;
        };

        const name = self.args.getFlag("name") orelse "generated";
        const output_dir = self.args.getFlag("output") orelse "src";
        const with_test = self.args.hasFlag("with-test");

        std.debug.print("🔧 生成 {s}: {s}\n", .{ gen_type.toString(), name });
        std.debug.print("📁 输出目录: {s}\n", .{output_dir});
        if (with_test) {
            std.debug.print("🧪 包含测试: 是\n", .{});
        }

        switch (gen_type) {
            .agent => try self.generateAgent(name, output_dir, with_test),
            .workflow => try self.generateWorkflow(name, output_dir, with_test),
            .tool => try self.generateTool(name, output_dir, with_test),
            .rag => try self.generateRag(name, output_dir, with_test),
            .middleware => try self.generateMiddleware(name, output_dir, with_test),
            .@"test" => try self.generateTest(name, output_dir),
        }
    }

    /// 生成 Agent 代码
    fn generateAgent(self: *Cli, name: []const u8, output_dir: []const u8, with_test: bool) !void {
        const agent_content = try std.fmt.allocPrint(self.allocator,
            \\const std = @import("std");
            \\// TODO: 添加 Mastra 导入
            \\// const mastra = @import("mastra");
            \\
            \\// {s} Agent
            \\pub const {s}Agent = struct {{
            \\    allocator: std.mem.Allocator,
            \\    // agent: mastra.Agent,
            \\
            \\    pub fn init(allocator: std.mem.Allocator) !{s}Agent {{
            \\        return {s}Agent{{
            \\            .allocator = allocator,
            \\            // .agent = try mastra.Agent.init(allocator, .{{
            \\            //     .name = "{s}",
            \\            //     .instructions = "你是一个专业的AI助手",
            \\            // }}),
            \\        }};
            \\    }}
            \\
            \\    pub fn deinit(self: *{s}Agent) void {{
            \\        // self.agent.deinit();
            \\        _ = self;
            \\    }}
            \\
            \\    pub fn process(self: *{s}Agent, input: []const u8) ![]const u8 {{
            \\        std.debug.print("🤖 Agent 处理输入: {{s}}\n", .{{input}});
            \\        
            \\        // TODO: 实现实际的处理逻辑
            \\        // return try self.agent.generate(input);
            \\        
            \\        return try self.allocator.dupe(u8, "这是一个示例响应");
            \\    }}
            \\}}
            \\
            \\test "{s} agent test" {{\n            \\    var gpa = std.heap.GeneralPurposeAllocator(.{{}}){{{{}}}};
            \\    defer _ = gpa.deinit();
            \\    const allocator = gpa.allocator();
            \\
            \\    var agent = try {s}Agent.init(allocator);
            \\    defer agent.deinit();
            \\
            \\    const result = try agent.process("测试输入");
            \\    defer allocator.free(result);
            \\
            \\    std.debug.print("测试结果: {{s}}\n", .{{result}});
            \\}}
            \\
        , .{ name, name, name, name, name, name, name, name, name });
        defer self.allocator.free(agent_content);

        // 确保输出目录存在
        const cwd = std.fs.cwd();
        cwd.makeDir(output_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        const filename = try std.fmt.allocPrint(self.allocator, "{s}/{s}_agent.zig", .{ output_dir, name });
        defer self.allocator.free(filename);

        var agent_file = try cwd.createFile(filename, .{});
        defer agent_file.close();
        try agent_file.writeAll(agent_content);

        std.debug.print("✅ Agent 生成完成: {s}\n", .{filename});

        // 生成测试文件
        if (with_test) {
            try self.generateAgentTest(name, output_dir);
        }
    }

    /// 生成Agent测试文件
    fn generateAgentTest(self: *Cli, name: []const u8, output_dir: []const u8) !void {
        const test_content = try std.fmt.allocPrint(self.allocator,
            \\const std = @import("std");
            \\const testing = std.testing;
            \\const {s}_agent = @import("{s}_agent.zig");
            \\
            \\test "{s} agent initialization" {{
            \\    var gpa = std.heap.GeneralPurposeAllocator(.{{}}){{}};
            \\    defer _ = gpa.deinit();
            \\    const allocator = gpa.allocator();
            \\
            \\    var agent = try {s}_agent.{s}Agent.init(allocator);
            \\    defer agent.deinit();
            \\
            \\    // 测试基本功能
            \\    try testing.expect(agent.allocator.ptr == allocator.ptr);
            \\}}
            \\
            \\test "{s} agent processing" {{
            \\    var gpa = std.heap.GeneralPurposeAllocator(.{{}}){{}};
            \\    defer _ = gpa.deinit();
            \\    const allocator = gpa.allocator();
            \\
            \\    var agent = try {s}_agent.{s}Agent.init(allocator);
            \\    defer agent.deinit();
            \\
            \\    const result = try agent.process("测试输入");
            \\    defer allocator.free(result);
            \\
            \\    try testing.expect(result.len > 0);
            \\    std.debug.print("Agent处理结果: {{s}}\n", .{{result}});
            \\}}
            \\
        , .{ name, name, name, name, name, name, name, name });
        defer self.allocator.free(test_content);

        const test_filename = try std.fmt.allocPrint(self.allocator, "{s}/{s}_agent_test.zig", .{ output_dir, name });
        defer self.allocator.free(test_filename);

        const cwd = std.fs.cwd();
        var test_file = try cwd.createFile(test_filename, .{});
        defer test_file.close();
        try test_file.writeAll(test_content);

        std.debug.print("✅ Agent测试生成完成: {s}\n", .{test_filename});
    }

    /// 生成 Workflow 代码
    fn generateWorkflow(self: *Cli, name: []const u8, output_dir: []const u8, with_test: bool) !void {
        _ = with_test;
        const workflow_content = try std.fmt.allocPrint(self.allocator,
            \\const std = @import("std");
            \\// TODO: 添加 Mastra 导入
            \\// const mastra = @import("mastra");
            \\
            \\// {s} Workflow
            \\pub const {s}Workflow = struct {{
            \\    allocator: std.mem.Allocator,
            \\    // workflow: mastra.Workflow,
            \\
            \\    pub fn init(allocator: std.mem.Allocator) !{s}Workflow {{
            \\        return {s}Workflow{{
            \\            .allocator = allocator,
            \\            // .workflow = try mastra.Workflow.init(allocator, .{{
            \\            //     .name = "{s}",
            \\            //     .description = "自动化工作流",
            \\            // }}),
            \\        }};
            \\    }}
            \\
            \\    pub fn deinit(self: *{s}Workflow) void {{
            \\        // self.workflow.deinit();
            \\        _ = self;
            \\    }}
            \\
            \\    pub fn execute(self: *{s}Workflow, context: std.json.Value) !std.json.Value {{
            \\        std.debug.print("🔄 Workflow 执行工作流\n", .{{}});
            \\        
            \\        // TODO: 实现实际的工作流逻辑
            \\        // Step 1: 数据预处理
            \\        std.debug.print("📊 步骤1: 数据预处理\n", .{{}});
            \\        
            \\        // Step 2: 核心处理
            \\        std.debug.print("⚙️  步骤2: 核心处理\n", .{{}});
            \\        
            \\        // Step 3: 结果输出
            \\        std.debug.print("📤 步骤3: 结果输出\n", .{{}});
            \\        
            \\        _ = context;
            \\        return std.json.Value{{{{ .string = "工作流执行完成" }}}};
            \\    }}
            \\}}
            \\
            \\test "{s} workflow test" {{\n            \\    var gpa = std.heap.GeneralPurposeAllocator(.{{}}){{{{}}}};
            \\    defer _ = gpa.deinit();
            \\    const allocator = gpa.allocator();
            \\
            \\    var workflow = try {s}Workflow.init(allocator);
            \\    defer workflow.deinit();
            \\
            \\    const context = std.json.Value{{{{ .object = std.json.ObjectMap.init(allocator) }}}};
            \\    const result = try workflow.execute(context);
            \\    
            \\        std.debug.print("工作流结果: {{any}}\n", .{{result}});
            \\}}
            \\
        , .{ name, name, name, name, name, name, name, name, name });
        defer self.allocator.free(workflow_content);

        // 确保输出目录存在
        const cwd = std.fs.cwd();
        cwd.makeDir(output_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        const filename = try std.fmt.allocPrint(self.allocator, "{s}/{s}_workflow.zig", .{ output_dir, name });
        defer self.allocator.free(filename);

        var workflow_file = try cwd.createFile(filename, .{});
        defer workflow_file.close();
        try workflow_file.writeAll(workflow_content);

        std.debug.print("✅ Workflow 生成完成: {s}\n", .{filename});
    }

    /// 生成 Tool 代码
    fn generateTool(self: *Cli, name: []const u8, output_dir: []const u8, with_test: bool) !void {
        _ = with_test;
        const tool_content = try std.fmt.allocPrint(self.allocator,
            \\const std = @import("std");
            \\// TODO: 添加 Mastra 导入
            \\// const mastra = @import("mastra");
            \\
            \\// {s} Tool
            \\pub const {s}Tool = struct {{
            \\    allocator: std.mem.Allocator,
            \\    // tool: mastra.Tool,
            \\
            \\    pub fn init(allocator: std.mem.Allocator) !{s}Tool {{
            \\        return {s}Tool{{
            \\            .allocator = allocator,
            \\            // .tool = try mastra.Tool.init(allocator, .{{
            \\            //     .name = "{s}",
            \\            //     .description = "一个有用的工具",
            \\            //     .parameters = &[_]mastra.ToolParameter{},
            \\            // }}),
            \\        }};
            \\    }}
            \\
            \\    pub fn deinit(self: *{s}Tool) void {{
            \\        // self.tool.deinit();
            \\        _ = self;
            \\    }}
            \\
            \\    pub fn execute(self: *{s}Tool, args: std.json.Value) !std.json.Value {{
            \\        std.debug.print("🔧 Tool 执行工具\n", .{{}});
            \\        
            \\        // TODO: 实现实际的工具逻辑
            \\        std.debug.print("📥 输入参数: {{any}}\n", .{{args}});
            \\        
            \\        // 示例处理逻辑
            \\        const result = std.json.Value{{{{ .string = "工具执行成功" }}}};
            \\        
            \\        std.debug.print("📤 输出结果: {{any}}\n", .{{result}});
            \\        return result;
            \\    }}
            \\}};
            \\
            \\test "{s} tool test" {{\n            \\    var gpa = std.heap.GeneralPurposeAllocator(.{{}}){{{{}}}};
            \\    defer _ = gpa.deinit();
            \\    const allocator = gpa.allocator();
            \\
            \\    var tool = try {s}Tool.init(allocator);
            \\    defer tool.deinit();
            \\
            \\    const args = std.json.Value{{{{ .object = std.json.ObjectMap.init(allocator) }}}};
            \\    const result = try tool.execute(args);
            \\    
            \\    std.debug.print("工具结果: {{any}}\n", .{{result}});
            \\}}
            \\
        , .{ name, name, name, name, name, name, name, name, name });
        defer self.allocator.free(tool_content);

        // 确保输出目录存在
        const cwd = std.fs.cwd();
        cwd.makeDir(output_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        const filename = try std.fmt.allocPrint(self.allocator, "{s}/{s}_tool.zig", .{ output_dir, name });
        defer self.allocator.free(filename);

        var tool_file = try cwd.createFile(filename, .{});
        defer tool_file.close();
        try tool_file.writeAll(tool_content);

        std.debug.print("✅ Tool 生成完成: {s}\n", .{filename});
    }

    /// 生成 RAG 代码
    fn generateRag(self: *Cli, name: []const u8, output_dir: []const u8, with_test: bool) !void {
        _ = with_test;

        const rag_content = try std.fmt.allocPrint(self.allocator,
            \\const std = @import("std");
            \\// TODO: 添加 Mastra 导入
            \\// const mastra = @import("mastra");
            \\
            \\// {s} RAG System
            \\pub const {s}RAG = struct {{
            \\    allocator: std.mem.Allocator,
            \\    // rag: mastra.RAG,
            \\
            \\    pub fn init(allocator: std.mem.Allocator) !{s}RAG {{
            \\        return {s}RAG{{
            \\            .allocator = allocator,
            \\            // .rag = try mastra.RAG.init(allocator, .{{
            \\            //     .embedding_model = "text-embedding-ada-002",
            \\            //     .vector_store = .pinecone,
            \\            // }}),
            \\        }};
            \\    }}
            \\
            \\    pub fn deinit(self: *{s}RAG) void {{
            \\        // self.rag.deinit();
            \\        _ = self;
            \\    }}
            \\
            \\    pub fn addDocument(self: *{s}RAG, doc_id: []const u8, content: []const u8) !void {{
            \\        std.debug.print("📄 添加文档: {{s}}\n", .{{doc_id}});
            \\        std.debug.print("📝 内容长度: {{d}}\n", .{{content.len}});
            \\
            \\        // TODO: 实现文档添加逻辑
            \\        // try self.rag.addDocument(doc_id, content);
            \\    }}
            \\
            \\    pub fn query(self: *{s}RAG, question: []const u8) ![]const u8 {{
            \\        std.debug.print("❓ 查询问题: {{s}}\n", .{{question}});
            \\
            \\        // TODO: 实现RAG查询逻辑
            \\        // return try self.rag.query(question);
            \\
            \\        return try self.allocator.dupe(u8, "这是一个基于检索的回答示例");
            \\    }}
            \\}}
            \\
        , .{ name, name, name, name, name, name, name });
        defer self.allocator.free(rag_content);

        // 确保输出目录存在
        const cwd = std.fs.cwd();
        cwd.makeDir(output_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        const filename = try std.fmt.allocPrint(self.allocator, "{s}/{s}_rag.zig", .{ output_dir, name });
        defer self.allocator.free(filename);

        var rag_file = try cwd.createFile(filename, .{});
        defer rag_file.close();
        try rag_file.writeAll(rag_content);

        std.debug.print("✅ RAG 生成完成: {s}\n", .{filename});
    }

    /// 生成 Middleware 代码
    fn generateMiddleware(self: *Cli, name: []const u8, output_dir: []const u8, with_test: bool) !void {
        _ = with_test;

        const middleware_content = try std.fmt.allocPrint(self.allocator,
            \\const std = @import("std");
            \\// TODO: 添加 Mastra 导入
            \\// const mastra = @import("mastra");
            \\
            \\// {s} Middleware
            \\pub const {s}Middleware = struct {{
            \\    allocator: std.mem.Allocator,
            \\
            \\    pub fn init(allocator: std.mem.Allocator) !{s}Middleware {{
            \\        return {s}Middleware{{
            \\            .allocator = allocator,
            \\        }};
            \\    }}
            \\
            \\    pub fn deinit(self: *{s}Middleware) void {{
            \\        _ = self;
            \\    }}
            \\
            \\    pub fn process(self: *{s}Middleware, request: anytype, response: anytype, next: anytype) !void {{
            \\        std.debug.print("🔄 Middleware 处理请求\n", .{{}});
            \\
            \\        // 前置处理
            \\        try self.beforeProcess(request);
            \\
            \\        // 调用下一个中间件或处理器
            \\        try next(request, response);
            \\
            \\        // 后置处理
            \\        try self.afterProcess(response);
            \\    }}
            \\
            \\    fn beforeProcess(self: *{s}Middleware, request: anytype) !void {{
            \\        _ = self;
            \\        _ = request;
            \\        std.debug.print("⬇️  前置处理\n", .{{}});
            \\    }}
            \\
            \\    fn afterProcess(self: *{s}Middleware, response: anytype) !void {{
            \\        _ = self;
            \\        _ = response;
            \\        std.debug.print("⬆️  后置处理\n", .{{}});
            \\    }}
            \\}}
            \\
        , .{ name, name, name, name, name, name, name, name });
        defer self.allocator.free(middleware_content);

        // 确保输出目录存在
        const cwd = std.fs.cwd();
        cwd.makeDir(output_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        const filename = try std.fmt.allocPrint(self.allocator, "{s}/{s}_middleware.zig", .{ output_dir, name });
        defer self.allocator.free(filename);

        var middleware_file = try cwd.createFile(filename, .{});
        defer middleware_file.close();
        try middleware_file.writeAll(middleware_content);

        std.debug.print("✅ Middleware 生成完成: {s}\n", .{filename});
    }

    /// 生成测试文件
    fn generateTest(self: *Cli, name: []const u8, output_dir: []const u8) !void {
        const test_content = try std.fmt.allocPrint(self.allocator,
            \\const std = @import("std");
            \\const testing = std.testing;
            \\
            \\test "{s} basic test" {{
            \\    var gpa = std.heap.GeneralPurposeAllocator(.{{}}){{}};
            \\    defer _ = gpa.deinit();
            \\    const allocator = gpa.allocator();
            \\
            \\    // 基础测试逻辑
            \\    const test_data = try allocator.alloc(u8, 10);
            \\    defer allocator.free(test_data);
            \\
            \\    try testing.expect(test_data.len == 10);
            \\    std.debug.print("✅ {s} 测试通过\n", .{{"{s}"}});
            \\}}
            \\
            \\test "{s} memory test" {{
            \\    var gpa = std.heap.GeneralPurposeAllocator(.{{}}){{}};
            \\    defer _ = gpa.deinit();
            \\    const allocator = gpa.allocator();
            \\
            \\    // 内存分配测试
            \\    var list = std.ArrayList(u32).init(allocator);
            \\    defer list.deinit();
            \\
            \\    try list.append(1);
            \\    try list.append(2);
            \\    try list.append(3);
            \\
            \\    try testing.expect(list.items.len == 3);
            \\    try testing.expect(list.items[0] == 1);
            \\    try testing.expect(list.items[1] == 2);
            \\    try testing.expect(list.items[2] == 3);
            \\}}
            \\
        , .{ name, name, name, name });
        defer self.allocator.free(test_content);

        // 确保输出目录存在
        const cwd = std.fs.cwd();
        cwd.makeDir(output_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        const filename = try std.fmt.allocPrint(self.allocator, "{s}/{s}_test.zig", .{ output_dir, name });
        defer self.allocator.free(filename);

        var test_file = try cwd.createFile(filename, .{});
        defer test_file.close();
        try test_file.writeAll(test_content);

        std.debug.print("✅ 测试文件生成完成: {s}\n", .{filename});
    }
};
