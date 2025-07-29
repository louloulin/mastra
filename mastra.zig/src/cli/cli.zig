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
        self.allocator.free(self.positional_args);

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
};

/// CLI主类
pub const Cli = struct {
    allocator: std.mem.Allocator,
    args: CliArgs,

    pub fn init(allocator: std.mem.Allocator) Cli {
        return Cli{
            .allocator = allocator,
            .args = CliArgs.init(allocator),
        };
    }

    pub fn deinit(self: *Cli) void {
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
                    const value = arg[eq_pos + 1..];
                    try self.args.flags.put(
                        try self.allocator.dupe(u8, key),
                        try self.allocator.dupe(u8, value)
                    );
                } else {
                    const key = arg[2..];
                    if (i + 1 < args.len and !std.mem.startsWith(u8, args[i + 1], "-")) {
                        i += 1;
                        try self.args.flags.put(
                            try self.allocator.dupe(u8, key),
                            try self.allocator.dupe(u8, args[i])
                        );
                    } else {
                        try self.args.flags.put(
                            try self.allocator.dupe(u8, key),
                            try self.allocator.dupe(u8, "")
                        );
                    }
                }
            } else if (std.mem.startsWith(u8, arg, "-") and arg.len > 1) {
                // 短选项 -k value
                const key = arg[1..];
                if (i + 1 < args.len and !std.mem.startsWith(u8, args[i + 1], "-")) {
                    i += 1;
                    try self.args.flags.put(
                        try self.allocator.dupe(u8, key),
                        try self.allocator.dupe(u8, args[i])
                    );
                } else {
                    try self.args.flags.put(
                        try self.allocator.dupe(u8, key),
                        try self.allocator.dupe(u8, "")
                    );
                }
            } else {
                // 位置参数
                try positional.append(try self.allocator.dupe(u8, arg));
            }
        }

        // 第一个位置参数是命令
        if (positional.items.len > 0) {
            self.args.command = Command.fromString(positional.items[0]);
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
        std.debug.print("Mastra CLI v0.1.0\n");
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

        std.debug.print("✅ 项目初始化完成!\n");
        std.debug.print("\n下一步:\n");
        std.debug.print("  cd {s}\n", .{project_name});
        std.debug.print("  zig build run\n");
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

        std.debug.print("📝 项目文件创建完成\n");
    }

    /// 创建 build.zig 文件
    fn createBuildFile(self: *Cli, project_dir: std.fs.Dir, project_name: []const u8) !void {
        _ = self;
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

    /// 创建 main.zig 文件
    fn createMainFile(self: *Cli, project_dir: std.fs.Dir, template: []const u8, llm_provider: []const u8, storage_type: []const u8) !void {
        _ = template;
        const main_content = std.fmt.allocPrint(self.allocator,
            \const std = @import("std");
            \// TODO: 添加 Mastra 导入
            \// const mastra = @import("mastra");
            \
            \pub fn main() !void {{
            \    var gpa = std.heap.GeneralPurposeAllocator(.{{}}){{}};
            \    defer _ = gpa.deinit();
            \    const allocator = gpa.allocator();
            \
            \    std.debug.print("🚀 启动 Mastra 应用\n", .{{}});
            \    std.debug.print("🤖 LLM提供商: {s}\n", .{{"{s}"}});
            \    std.debug.print("💾 存储类型: {s}\n", .{{"{s}"}});
            \
            \    // TODO: 初始化 Mastra 框架
            \    // var m = try mastra.Mastra.init(allocator, .{{
            \    //     .llm_provider = .{s},
            \    //     .storage_type = .{s},
            \    // }});
            \    // defer m.deinit();
            \
            \    std.debug.print("✅ 应用启动成功!\n", .{{}});
            \
            \    // 保持程序运行
            \    std.debug.print("按 Ctrl+C 退出...\n", .{{}});
            \    while (true) {{
            \        std.time.sleep(1000000000); // 1秒
            \    }}
            \}}
            \
        , .{ llm_provider, storage_type, llm_provider, storage_type }) catch return CliError.ConfigurationError;
        defer self.allocator.free(main_content);

        var src_dir = try project_dir.openDir("src", .{});
        defer src_dir.close();

        var main_file = try src_dir.createFile("main.zig", .{});
        defer main_file.close();
        try main_file.writeAll(main_content);
    }

    /// 创建配置文件
    fn createConfigFiles(self: *Cli, project_dir: std.fs.Dir, llm_provider: []const u8, storage_type: []const u8) !void {
        var config_dir = try project_dir.openDir("config", .{});
        defer config_dir.close();

        // 创建 .env 示例文件
        const env_content = std.fmt.allocPrint(self.allocator,
            \# Mastra 配置文件
            \
            \# LLM 配置
            \OPENAI_API_KEY=your_openai_api_key_here
            \ANTHROPIC_API_KEY=your_anthropic_api_key_here
            \GOOGLE_API_KEY=your_google_api_key_here
            \
            \# 数据库配置
            \DATABASE_URL=postgresql://user:password@localhost:5432/mastra
            \MONGODB_URI=mongodb://localhost:27017/mastra
            \
            \# 应用配置
            \LLM_PROVIDER={s}
            \STORAGE_TYPE={s}
            \LOG_LEVEL=info
            \PORT=3000
            \
        , .{ llm_provider, storage_type }) catch return CliError.ConfigurationError;
        defer self.allocator.free(env_content);

        var env_file = try config_dir.createFile(".env.example", .{});
        defer env_file.close();
        try env_file.writeAll(env_content);

        // 创建 mastra.json 配置文件
        const json_content = std.fmt.allocPrint(self.allocator,
            \{{
            \  "name": "mastra-project",
            \  "version": "0.1.0",
            \  "llm": {{
            \    "provider": "{s}",
            \    "model": "gpt-3.5-turbo",
            \    "temperature": 0.7,
            \    "max_tokens": 1000
            \  }},
            \  "storage": {{
            \    "type": "{s}",
            \    "connection": {{
            \      "host": "localhost",
            \      "port": 5432,
            \      "database": "mastra"
            \    }}
            \  }},
            \  "agents": [],
            \  "workflows": [],
            \  "tools": []
            \}}
            \
        , .{ llm_provider, storage_type }) catch return CliError.ConfigurationError;
        defer self.allocator.free(json_content);

        var json_file = try config_dir.createFile("mastra.json", .{});
        defer json_file.close();
        try json_file.writeAll(json_content);
    }

    /// 创建示例文件
    fn createExampleFiles(self: *Cli, project_dir: std.fs.Dir, template: []const u8) !void {
        _ = template;
        var examples_dir = try project_dir.openDir("examples", .{});
        defer examples_dir.close();

        const example_content =
            \const std = @import("std");
            \// TODO: 添加 Mastra 导入
            \// const mastra = @import("mastra");
            \
            \// 简单的聊天机器人示例
            \pub fn chatbotExample(allocator: std.mem.Allocator) !void {
            \    std.debug.print("🤖 聊天机器人示例\n", .{});
            \
            \    // TODO: 实现聊天机器人逻辑
            \    // var agent = try mastra.Agent.init(allocator, .{
            \    //     .name = "chatbot",
            \    //     .instructions = "你是一个友好的助手",
            \    // });
            \    // defer agent.deinit();
            \
            \    std.debug.print("✅ 聊天机器人示例完成\n", .{});
            \}
            \
        ;

        var example_file = try examples_dir.createFile("chatbot.zig", .{});
        defer example_file.close();
        try example_file.writeAll(example_content);
    }

    /// 创建 README.md 文件
    fn createReadmeFile(self: *Cli, project_dir: std.fs.Dir, project_name: []const u8) !void {
        const readme_content = std.fmt.allocPrint(self.allocator,
            \# {s}
            \
            \基于 Mastra.zig 框架构建的 AI 应用项目。
            \
            \## 快速开始
            \
            \1. 配置环境变量:
            \   ```bash
            \   cp config/.env.example .env
            \   # 编辑 .env 文件，设置你的 API 密钥
            \   ```
            \
            \2. 构建并运行:
            \   ```bash
            \   zig build run
            \   ```
            \
            \3. 运行测试:
            \   ```bash
            \   zig build test
            \   ```
            \
            \## 项目结构
            \
            \```
            \{s}/
            \├── src/
            \│   └── main.zig          # 主程序入口
            \├── config/
            \│   ├── .env.example      # 环境变量示例
            \│   └── mastra.json       # Mastra 配置文件
            \├── examples/
            \│   └── chatbot.zig       # 聊天机器人示例
            \├── tests/
            \├── build.zig             # 构建配置
            \└── README.md
            \```
            \
            \## 功能特性
            \
            \- 🤖 LLM 集成 (OpenAI, Anthropic, Google)
            \- 💾 多种存储后端 (Memory, PostgreSQL, MongoDB)
            \- 🔧 工具系统和函数调用
            \- 🔄 工作流引擎
            \- 📊 向量存储和相似度搜索
            \- 🧠 内存管理和持久化
            \- 📈 遥测和监控
            \
            \## 开发
            \
            \查看 `examples/` 目录了解更多使用示例。
            \
            \## 文档
            \
            \- [Mastra.zig 文档](https://github.com/mastra-ai/mastra)
            \- [Zig 语言文档](https://ziglang.org/documentation/)
            \
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

        // TODO: 实现开发服务器
        std.debug.print("⚠️  开发服务器功能正在开发中...\n", .{});
        return CliError.BuildError;
    }

    /// 执行构建命令
    fn executeBuild(self: *Cli) !void {
        const optimize = self.args.hasFlag("optimize");
        const target = self.args.getFlag("target");
        const verbose = self.args.hasFlag("verbose");

        std.debug.print("🔨 构建 Mastra 项目\n", .{});
        if (optimize) {
            std.debug.print("⚡ 优化模式: 开启\n", .{});
        }
        if (target) |t| {
            std.debug.print("🎯 目标平台: {s}\n", .{t});
        }
        if (verbose) {
            std.debug.print("📝 详细模式: 开启\n", .{});
        }

        // TODO: 实现构建逻辑
        std.debug.print("⚠️  构建功能正在开发中...\n", .{});
        return CliError.BuildError;
    }

    /// 执行部署命令
    fn executeDeploy(self: *Cli) !void {
        const platform = self.args.getFlag("platform") orelse "local";
        const env = self.args.getFlag("env") orelse "production";

        std.debug.print("🚀 部署 Mastra 项目\n", .{});
        std.debug.print("🌐 平台: {s}\n", .{platform});
        std.debug.print("🏷️  环境: {s}\n", .{env});

        // TODO: 实现部署逻辑
        std.debug.print("⚠️  部署功能正在开发中...\n", .{});
        return CliError.DeploymentError;
    }

    /// 执行代码生成命令
    fn executeGenerate(self: *Cli) !void {
        const gen_type = if (self.args.positional_args.len > 0)
            self.args.positional_args[0]
        else {
            std.debug.print("❌ 错误: 请指定生成类型 (agent, workflow, tool)\n", .{});
            return CliError.MissingArgument;
        };

        const name = self.args.getFlag("name") orelse "generated";

        std.debug.print("🔧 生成 {s}: {s}\n", .{ gen_type, name });

        if (std.mem.eql(u8, gen_type, "agent")) {
            try self.generateAgent(name);
        } else if (std.mem.eql(u8, gen_type, "workflow")) {
            try self.generateWorkflow(name);
        } else if (std.mem.eql(u8, gen_type, "tool")) {
            try self.generateTool(name);
        } else {
            std.debug.print("❌ 错误: 未知的生成类型 '{s}'\n", .{gen_type});
            std.debug.print("支持的类型: agent, workflow, tool\n", .{});
            return CliError.InvalidArgument;
        }
    }

    /// 生成 Agent 代码
    fn generateAgent(self: *Cli, name: []const u8) !void {
        const agent_content = std.fmt.allocPrint(self.allocator,
            \const std = @import("std");
            \// TODO: 添加 Mastra 导入
            \// const mastra = @import("mastra");
            \
            \// {s} Agent
            \pub const {s}Agent = struct {{
            \    allocator: std.mem.Allocator,
            \    // agent: mastra.Agent,
            \
            \    pub fn init(allocator: std.mem.Allocator) !{s}Agent {{
            \        return {s}Agent{{
            \            .allocator = allocator,
            \            // .agent = try mastra.Agent.init(allocator, .{{
            \            //     .name = "{s}",
            \            //     .instructions = "你是一个专业的AI助手",
            \            // }}),
            \        }};
            \    }}
            \
            \    pub fn deinit(self: *{s}Agent) void {{
            \        // self.agent.deinit();
            \        _ = self;
            \    }}
            \
            \    pub fn process(self: *{s}Agent, input: []const u8) ![]const u8 {{
            \        std.debug.print("🤖 {s} 处理输入: {{s}}\n", .{{input}});
            \        
            \        // TODO: 实现实际的处理逻辑
            \        // return try self.agent.generate(input);
            \        
            \        return try self.allocator.dupe(u8, "这是一个示例响应");
            \    }}
            \}};
            \
            \test "{s} agent test" {{
            \    var gpa = std.heap.GeneralPurposeAllocator(.{{}}){{}};
            \    defer _ = gpa.deinit();
            \    const allocator = gpa.allocator();
            \
            \    var agent = try {s}Agent.init(allocator);
            \    defer agent.deinit();
            \
            \    const result = try agent.process("测试输入");
            \    defer allocator.free(result);
            \
            \    std.debug.print("测试结果: {{s}}\n", .{{result}});
            \}}
            \
        , .{ name, name, name, name, name, name, name, name, name, name }) catch return CliError.ConfigurationError;
        defer self.allocator.free(agent_content);

        const filename = std.fmt.allocPrint(self.allocator, "src/{s}_agent.zig", .{name}) catch return CliError.ConfigurationError;
        defer self.allocator.free(filename);

        const cwd = std.fs.cwd();
        var agent_file = try cwd.createFile(filename, .{});
        defer agent_file.close();
        try agent_file.writeAll(agent_content);

        std.debug.print("✅ Agent 生成完成: {s}\n", .{filename});
    }

    /// 生成 Workflow 代码
    fn generateWorkflow(self: *Cli, name: []const u8) !void {
        const workflow_content = std.fmt.allocPrint(self.allocator,
            \const std = @import("std");
            \// TODO: 添加 Mastra 导入
            \// const mastra = @import("mastra");
            \
            \// {s} Workflow
            \pub const {s}Workflow = struct {{
            \    allocator: std.mem.Allocator,
            \    // workflow: mastra.Workflow,
            \
            \    pub fn init(allocator: std.mem.Allocator) !{s}Workflow {{
            \        return {s}Workflow{{
            \            .allocator = allocator,
            \            // .workflow = try mastra.Workflow.init(allocator, .{{
            \            //     .name = "{s}",
            \            //     .description = "自动化工作流",
            \            // }}),
            \        }};
            \    }}
            \
            \    pub fn deinit(self: *{s}Workflow) void {{
            \        // self.workflow.deinit();
            \        _ = self;
            \    }}
            \
            \    pub fn execute(self: *{s}Workflow, context: std.json.Value) !std.json.Value {{
            \        std.debug.print("🔄 {s} 执行工作流\n", .{{}});
            \        
            \        // TODO: 实现实际的工作流逻辑
            \        // Step 1: 数据预处理
            \        std.debug.print("📊 步骤1: 数据预处理\n", .{{}});
            \        
            \        // Step 2: 核心处理
            \        std.debug.print("⚙️  步骤2: 核心处理\n", .{{}});
            \        
            \        // Step 3: 结果输出
            \        std.debug.print("📤 步骤3: 结果输出\n", .{{}});
            \        
            \        _ = context;
            \        return std.json.Value{{ .string = "工作流执行完成" }};
            \    }}
            \}};
            \
            \test "{s} workflow test" {{
            \    var gpa = std.heap.GeneralPurposeAllocator(.{{}}){{}};
            \    defer _ = gpa.deinit();
            \    const allocator = gpa.allocator();
            \
            \    var workflow = try {s}Workflow.init(allocator);
            \    defer workflow.deinit();
            \
            \    const context = std.json.Value{{ .object = std.json.ObjectMap.init(allocator) }};
            \    const result = try workflow.execute(context);
            \    
            \    std.debug.print("工作流结果: {{}}\n", .{{result}});
            \}}
            \
        , .{ name, name, name, name, name, name, name, name, name, name }) catch return CliError.ConfigurationError;
        defer self.allocator.free(workflow_content);

        const filename = std.fmt.allocPrint(self.allocator, "src/{s}_workflow.zig", .{name}) catch return CliError.ConfigurationError;
        defer self.allocator.free(filename);

        const cwd = std.fs.cwd();
        var workflow_file = try cwd.createFile(filename, .{});
        defer workflow_file.close();
        try workflow_file.writeAll(workflow_content);

        std.debug.print("✅ Workflow 生成完成: {s}\n", .{filename});
    }

    /// 生成 Tool 代码
    fn generateTool(self: *Cli, name: []const u8) !void {
        const tool_content = std.fmt.allocPrint(self.allocator,
            \const std = @import("std");
            \// TODO: 添加 Mastra 导入
            \// const mastra = @import("mastra");
            \
            \// {s} Tool
            \pub const {s}Tool = struct {{
            \    allocator: std.mem.Allocator,
            \    // tool: mastra.Tool,
            \
            \    pub fn init(allocator: std.mem.Allocator) !{s}Tool {{
            \        return {s}Tool{{
            \            .allocator = allocator,
            \            // .tool = try mastra.Tool.init(allocator, .{{
            \            //     .name = "{s}",
            \            //     .description = "一个有用的工具",
            \            //     .parameters = &[_]mastra.ToolParameter{{}},
            \            // }}),
            \        }};
            \    }}
            \
            \    pub fn deinit(self: *{s}Tool) void {{
            \        // self.tool.deinit();
            \        _ = self;
            \    }}
            \
            \    pub fn execute(self: *{s}Tool, args: std.json.Value) !std.json.Value {{
            \        std.debug.print("🔧 {s} 执行工具\n", .{{}});
            \        
            \        // TODO: 实现实际的工具逻辑
            \        std.debug.print("📥 输入参数: {{}}\n", .{{args}});
            \        
            \        // 示例处理逻辑
            \        const result = std.json.Value{{ .string = "工具执行成功" }};
            \        
            \        std.debug.print("📤 输出结果: {{}}\n", .{{result}});
            \        return result;
            \    }}
            \}};
            \
            \test "{s} tool test" {{
            \    var gpa = std.heap.GeneralPurposeAllocator(.{{}}){{}};
            \    defer _ = gpa.deinit();
            \    const allocator = gpa.allocator();
            \
            \    var tool = try {s}Tool.init(allocator);
            \    defer tool.deinit();
            \
            \    const args = std.json.Value{{ .object = std.json.ObjectMap.init(allocator) }};
            \    const result = try tool.execute(args);
            \    
            \    std.debug.print("工具结果: {{}}\n", .{{result}});
            \}}
            \
        , .{ name, name, name, name, name, name, name, name, name, name }) catch return CliError.ConfigurationError;
        defer self.allocator.free(tool_content);

        const filename = std.fmt.allocPrint(self.allocator, "src/{s}_tool.zig", .{name}) catch return CliError.ConfigurationError;
        defer self.allocator.free(filename);

        const cwd = std.fs.cwd();
        var tool_file = try cwd.createFile(filename, .{});
        defer tool_file.close();
        try tool_file.writeAll(tool_content);

        std.debug.print("✅ Tool 生成完成: {s}\n", .{filename});
    }
};