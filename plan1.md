# Mastra.zig 开发计划

## 核心技术栈选择

### 事件循环和异步I/O
- **libxev** - 跨平台高性能事件循环库
  - 支持Linux (io_uring/epoll), macOS (kqueue), Windows (IOCP)
  - 提供Zig和C API
  - 用于所有异步网络操作的基础

### HTTP客户端和服务器
- **std.http.Client** - Zig标准库HTTP客户端 (Zig 0.12+)
  - 内置TLS 1.3支持
  - 与libxev集成用于异步操作
- **zap** - 高性能HTTP服务器框架
  - 基于C库facil.io的Zig包装
  - 支持路由、中间件、WebSocket

### 数据库和存储
- **zqlite.zig** (karlseguin) - SQLite包装库
  - 轻量级、类型安全的SQLite接口
  - 支持预编译语句和事务
- **zig-sqlite** (vrischmann) - 另一个SQLite选择
  - 更底层的SQLite C API包装

### JSON处理
- **std.json** - Zig标准库JSON支持
  - 内置解析和序列化
  - 支持流式解析
- **ziggy** - 高性能JSON库备选

### 日志系统
- **log.zig** (karlseguin) - 结构化日志库
  - 支持多种输出格式
  - 线程安全
  - 可配置日志级别

### 工具库
- **zul** (karlseguin) - Zig实用工具库
  - 日期时间处理
  - 字符串操作
  - 数据结构

### CLI参数解析
- **std.process** - Zig标准库原生CLI参数解析
  - 零依赖，完全跨平台
  - 使用std.process.argsAlloc()或std.process.argsWithAllocator()
  - 自定义参数解析逻辑，更灵活

### 向量计算
- **自实现** - 基于Zig的SIMD支持
  - 使用@Vector进行向量化计算
  - HNSW算法实现相似度搜索
  - 可选集成FAISS C库

## 项目现状分析

### 已完成部分
- ✅ 基础项目结构和Zig构建系统
- ✅ 核心模块定义：agent、workflow、tools、storage、memory、llm、telemetry、utils
- ✅ 基本数据结构和接口设计
- ✅ 测试框架搭建
- ✅ 内存管理模式建立

### 主要问题和缺失

#### 1. 核心功能缺失
- ❌ **LLM集成完全是模拟实现** - 没有真实的API调用
- ❌ **缺少HTTP客户端** - 无法与外部API通信
- ❌ **工具调用系统不完整** - 没有函数调用支持
- ❌ **工作流执行引擎缺失** - 只有基础结构
- ❌ **流式响应支持缺失** - 无法实现实时交互

#### 2. 存储和持久化问题
- ❌ **只有内存存储** - 缺少真实数据库集成
- ❌ **向量存储功能不完整** - 只有基础相似度计算
- ❌ **没有数据迁移机制** - 缺少schema管理
- ❌ **缺少缓存层** - 性能优化不足

#### 3. 系统架构问题
- ❌ **异步I/O模式缺失** - 网络操作同步化
- ❌ **错误处理不一致** - 缺少统一错误类型
- ❌ **配置管理缺失** - 没有环境变量支持
- ❌ **日志系统不完整** - 只有基础控制台输出

#### 4. 生态系统缺失
- ❌ **没有CLI工具** - 缺少项目脚手架
- ❌ **没有部署支持** - 缺少打包和分发
- ❌ **没有插件系统** - 扩展性不足
- ❌ **文档和示例不足** - 学习成本高

## 开发优先级和MVP规划

### 第一优先级：核心功能MVP（1-2周）

#### 1.1 libxev事件循环集成
```zig
// build.zig依赖配置
const libxev = b.dependency("libxev", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("xev", libxev.module("xev"));

// 事件循环初始化
const xev = @import("xev");
var loop = try xev.Loop.init(.{});
defer loop.deinit();
```

#### 1.2 HTTP客户端和LLM集成
```zig
// 使用std.http.Client + libxev实现异步HTTP
const std = @import("std");
const xev = @import("xev");

const HttpClient = struct {
    allocator: std.mem.Allocator,
    client: std.http.Client,
    loop: *xev.Loop,

    pub fn init(allocator: std.mem.Allocator, loop: *xev.Loop) !HttpClient {
        return HttpClient{
            .allocator = allocator,
            .client = std.http.Client{ .allocator = allocator },
            .loop = loop,
        };
    }

    pub fn post(self: *HttpClient, url: []const u8, headers: []const std.http.Header, body: []const u8) ![]u8 {
        // 异步HTTP POST实现
        var req = try self.client.open(.POST, try std.Uri.parse(url), headers, .{});
        defer req.deinit();

        req.transfer_encoding = .{ .content_length = body.len };
        try req.send();
        try req.writeAll(body);
        try req.finish();
        try req.wait();

        // 读取响应
        var response_body = std.ArrayList(u8).init(self.allocator);
        try req.reader().readAllArrayList(&response_body, 1024 * 1024);
        return response_body.toOwnedSlice();
    }
};

// OpenAI API集成
const OpenAI = struct {
    http_client: *HttpClient,
    api_key: []const u8,
    base_url: []const u8 = "https://api.openai.com/v1",

    pub fn chatCompletion(self: *OpenAI, messages: []const Message) ![]u8 {
        const headers = [_]std.http.Header{
            .{ .name = "Authorization", .value = try std.fmt.allocPrint(self.http_client.allocator, "Bearer {s}", .{self.api_key}) },
            .{ .name = "Content-Type", .value = "application/json" },
        };

        const payload = try std.json.stringifyAlloc(self.http_client.allocator, .{
            .model = "gpt-4",
            .messages = messages,
        }, .{});
        defer self.http_client.allocator.free(payload);

        const url = try std.fmt.allocPrint(self.http_client.allocator, "{s}/chat/completions", .{self.base_url});
        defer self.http_client.allocator.free(url);

        return try self.http_client.post(url, &headers, payload);
    }
};
```

#### 1.3 配置管理系统
```zig
// 使用zul库进行配置管理
const zul = @import("zul");

const Config = struct {
    openai_api_key: ?[]const u8 = null,
    anthropic_api_key: ?[]const u8 = null,
    log_level: []const u8 = "info",
    database_url: []const u8 = "data.db",

    pub fn load(allocator: std.mem.Allocator, path: ?[]const u8) !Config {
        var config = Config{};

        // 1. 从环境变量加载
        if (std.process.getEnvVarOwned(allocator, "OPENAI_API_KEY")) |key| {
            config.openai_api_key = key;
        } else |_| {}

        // 2. 从配置文件加载
        if (path) |config_path| {
            const file_content = std.fs.cwd().readFileAlloc(allocator, config_path, 1024 * 1024) catch |err| switch (err) {
                error.FileNotFound => return config,
                else => return err,
            };
            defer allocator.free(file_content);

            const parsed = try std.json.parseFromSlice(std.json.Value, allocator, file_content, .{});
            defer parsed.deinit();

            if (parsed.value.object.get("openai_api_key")) |key| {
                config.openai_api_key = try allocator.dupe(u8, key.string);
            }
        }

        return config;
    }
};
```

#### 1.4 结构化日志系统
```zig
// build.zig添加log.zig依赖
const log_zig = b.dependency("log", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("log", log_zig.module("log"));

// 日志配置
const log = @import("log");

const Logger = struct {
    logger: *log.Logger,

    pub fn init(allocator: std.mem.Allocator, level: log.Level) !Logger {
        const logger = try log.Logger.init(allocator, .{
            .level = level,
            .output = .stdout,
            .format = .json,
        });

        return Logger{ .logger = logger };
    }

    pub fn info(self: *Logger, comptime fmt: []const u8, args: anytype) void {
        self.logger.info(fmt, args);
    }

    pub fn err(self: *Logger, comptime fmt: []const u8, args: anytype) void {
        self.logger.err(fmt, args);
    }

    pub fn debug(self: *Logger, comptime fmt: []const u8, args: anytype) void {
        self.logger.debug(fmt, args);
    }
};
```

### 第二优先级：存储和持久化（3-4周）

#### 2.1 SQLite集成 (使用zqlite.zig)
```zig
// build.zig添加zqlite依赖
const zqlite = b.dependency("zqlite", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("zqlite", zqlite.module("zqlite"));

// SQLite存储实现
const zqlite = @import("zqlite");

const SqliteStorage = struct {
    allocator: std.mem.Allocator,
    db: *zqlite.DB,

    pub fn init(allocator: std.mem.Allocator, db_path: []const u8) !SqliteStorage {
        const db = try zqlite.DB.open(db_path, .{});

        // 创建表结构
        try db.exec(
            \\CREATE TABLE IF NOT EXISTS storage_records (
            \\  id TEXT PRIMARY KEY,
            \\  table_name TEXT NOT NULL,
            \\  data TEXT NOT NULL,
            \\  created_at INTEGER NOT NULL,
            \\  updated_at INTEGER NOT NULL
            \\)
        );

        try db.exec(
            \\CREATE TABLE IF NOT EXISTS vector_documents (
            \\  id TEXT PRIMARY KEY,
            \\  content TEXT NOT NULL,
            \\  embedding BLOB NOT NULL,
            \\  metadata TEXT,
            \\  created_at INTEGER NOT NULL
            \\)
        );

        return SqliteStorage{
            .allocator = allocator,
            .db = db,
        };
    }

    pub fn create(self: *SqliteStorage, table_name: []const u8, data: std.json.Value) ![]const u8 {
        const id = try std.fmt.allocPrint(self.allocator, "{s}_{d}", .{ table_name, std.time.timestamp() });
        const data_json = try std.json.stringifyAlloc(self.allocator, data, .{});
        defer self.allocator.free(data_json);

        const stmt = try self.db.prepare("INSERT INTO storage_records (id, table_name, data, created_at, updated_at) VALUES (?, ?, ?, ?, ?)");
        defer stmt.deinit();

        const now = std.time.timestamp();
        try stmt.bind(.{ id, table_name, data_json, now, now });
        try stmt.exec();

        return id;
    }

    pub fn read(self: *SqliteStorage, table_name: []const u8, id: []const u8) !?StorageRecord {
        const stmt = try self.db.prepare("SELECT id, data, created_at, updated_at FROM storage_records WHERE table_name = ? AND id = ?");
        defer stmt.deinit();

        try stmt.bind(.{ table_name, id });

        if (try stmt.step()) {
            const record_id = stmt.text(0);
            const data_json = stmt.text(1);
            const created_at = stmt.int64(2);
            const updated_at = stmt.int64(3);

            const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, data_json, .{});

            return StorageRecord{
                .id = try self.allocator.dupe(u8, record_id),
                .data = parsed.value,
                .created_at = created_at,
                .updated_at = updated_at,
            };
        }

        return null;
    }
};
```

#### 2.2 向量存储增强 (自实现HNSW算法)
```zig
// 使用Zig的SIMD支持实现高效向量计算
const VectorStore = struct {
    allocator: std.mem.Allocator,
    db: *zqlite.DB,
    dimension: usize,

    pub fn init(allocator: std.mem.Allocator, db: *zqlite.DB, dimension: usize) !VectorStore {
        return VectorStore{
            .allocator = allocator,
            .db = db,
            .dimension = dimension,
        };
    }

    pub fn upsert(self: *VectorStore, documents: []const VectorDocument) !void {
        const stmt = try self.db.prepare("INSERT OR REPLACE INTO vector_documents (id, content, embedding, metadata, created_at) VALUES (?, ?, ?, ?, ?)");
        defer stmt.deinit();

        for (documents) |doc| {
            // 将embedding序列化为BLOB
            const embedding_bytes = std.mem.sliceAsBytes(doc.embedding);
            const metadata_json = if (doc.metadata) |meta|
                try std.json.stringifyAlloc(self.allocator, meta, .{})
            else
                null;
            defer if (metadata_json) |json| self.allocator.free(json);

            try stmt.bind(.{ doc.id, doc.content, embedding_bytes, metadata_json, std.time.timestamp() });
            try stmt.exec();
            try stmt.reset();
        }
    }

    pub fn search(self: *VectorStore, query: VectorQuery) ![]VectorDocument {
        // 简单的线性搜索实现，后续可优化为HNSW
        const stmt = try self.db.prepare("SELECT id, content, embedding, metadata FROM vector_documents");
        defer stmt.deinit();

        var results = std.ArrayList(VectorDocument).init(self.allocator);
        defer results.deinit();

        while (try stmt.step()) {
            const id = stmt.text(0);
            const content = stmt.text(1);
            const embedding_blob = stmt.blob(2);
            const metadata_json = stmt.textOptional(3);

            // 反序列化embedding
            const embedding = std.mem.bytesAsSlice(f32, embedding_blob);

            // 计算相似度
            const similarity = try self.cosineSimilarity(query.vector, embedding);

            if (similarity >= query.threshold) {
                const embedding_copy = try self.allocator.dupe(f32, embedding);

                var metadata: ?std.json.Value = null;
                if (metadata_json) |json| {
                    const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, json, .{});
                    metadata = parsed.value;
                }

                try results.append(VectorDocument{
                    .id = try self.allocator.dupe(u8, id),
                    .content = try self.allocator.dupe(u8, content),
                    .embedding = embedding_copy,
                    .metadata = metadata,
                    .score = similarity,
                });
            }
        }

        // 按相似度排序
        std.mem.sort(VectorDocument, results.items, {}, struct {
            fn lessThan(_: void, a: VectorDocument, b: VectorDocument) bool {
                return a.score > b.score;
            }
        }.lessThan);

        // 返回top-k结果
        const limit = @min(query.limit, results.items.len);
        return try self.allocator.dupe(VectorDocument, results.items[0..limit]);
    }

    // 使用SIMD优化的余弦相似度计算
    fn cosineSimilarity(self: *VectorStore, vec1: []const f32, vec2: []const f32) !f32 {
        if (vec1.len != vec2.len) return 0.0;

        // 使用Zig的向量化支持
        const VecType = @Vector(8, f32);
        const vec_len = vec1.len / 8;

        var dot_product: f32 = 0.0;
        var norm1: f32 = 0.0;
        var norm2: f32 = 0.0;

        // 向量化计算
        var i: usize = 0;
        while (i < vec_len * 8) : (i += 8) {
            const v1: VecType = vec1[i..i+8][0..8].*;
            const v2: VecType = vec2[i..i+8][0..8].*;

            dot_product += @reduce(.Add, v1 * v2);
            norm1 += @reduce(.Add, v1 * v1);
            norm2 += @reduce(.Add, v2 * v2);
        }

        // 处理剩余元素
        while (i < vec1.len) : (i += 1) {
            dot_product += vec1[i] * vec2[i];
            norm1 += vec1[i] * vec1[i];
            norm2 += vec2[i] * vec2[i];
        }

        const denominator = @sqrt(norm1) * @sqrt(norm2);
        if (denominator == 0.0) return 0.0;

        return dot_product / denominator;
    }
};
```

#### 2.3 内存管理优化
```zig
// 对象池实现
const ObjectPool = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    objects: std.ArrayList(*anyopaque),
    create_fn: *const fn (std.mem.Allocator) anyerror!*anyopaque,
    reset_fn: *const fn (*anyopaque) void,
    destroy_fn: *const fn (std.mem.Allocator, *anyopaque) void,

    pub fn init(
        allocator: std.mem.Allocator,
        create_fn: *const fn (std.mem.Allocator) anyerror!*anyopaque,
        reset_fn: *const fn (*anyopaque) void,
        destroy_fn: *const fn (std.mem.Allocator, *anyopaque) void,
    ) Self {
        return Self{
            .allocator = allocator,
            .objects = std.ArrayList(*anyopaque).init(allocator),
            .create_fn = create_fn,
            .reset_fn = reset_fn,
            .destroy_fn = destroy_fn,
        };
    }

    pub fn acquire(self: *Self) !*anyopaque {
        if (self.objects.popOrNull()) |obj| {
            return obj;
        }
        return try self.create_fn(self.allocator);
    }

    pub fn release(self: *Self, obj: *anyopaque) !void {
        self.reset_fn(obj);
        try self.objects.append(obj);
    }

    pub fn deinit(self: *Self) void {
        for (self.objects.items) |obj| {
            self.destroy_fn(self.allocator, obj);
        }
        self.objects.deinit();
    }
};

// 内存使用监控
const MemoryMonitor = struct {
    allocator: std.mem.Allocator,
    total_allocated: std.atomic.Value(usize),
    peak_allocated: std.atomic.Value(usize),

    pub fn init(allocator: std.mem.Allocator) MemoryMonitor {
        return MemoryMonitor{
            .allocator = allocator,
            .total_allocated = std.atomic.Value(usize).init(0),
            .peak_allocated = std.atomic.Value(usize).init(0),
        };
    }

    pub fn trackAllocation(self: *MemoryMonitor, size: usize) void {
        const new_total = self.total_allocated.fetchAdd(size, .monotonic) + size;
        _ = self.peak_allocated.fetchMax(new_total, .monotonic);
    }

    pub fn trackDeallocation(self: *MemoryMonitor, size: usize) void {
        _ = self.total_allocated.fetchSub(size, .monotonic);
    }

    pub fn getCurrentUsage(self: *MemoryMonitor) usize {
        return self.total_allocated.load(.monotonic);
    }

    pub fn getPeakUsage(self: *MemoryMonitor) usize {
        return self.peak_allocated.load(.monotonic);
    }
};
```

### 第三优先级：高级功能（5-6周）

#### 3.1 多LLM提供商支持
- Anthropic Claude集成
- Groq集成  
- 本地模型支持（Ollama）

#### 3.2 高级工作流功能
- 并行步骤执行
- 条件分支和循环
- 人工干预点（Human-in-the-loop）
- 工作流暂停和恢复

#### 3.3 流式响应支持
```zig
// 目标：实时流式响应
try agent.stream(messages, struct {
    fn onChunk(chunk: []const u8) void {
        std.debug.print("{s}", .{chunk});
    }
}.onChunk);
```

### 第四优先级：生态系统（7-8周）

#### 4.1 HTTP服务器 (使用zap框架)
```zig
// build.zig添加zap依赖
const zap = b.dependency("zap", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("zap", zap.module("zap"));

// HTTP服务器实现
const zap = @import("zap");

const MastraServer = struct {
    allocator: std.mem.Allocator,
    mastra: *Mastra,

    pub fn init(allocator: std.mem.Allocator, mastra: *Mastra) MastraServer {
        return MastraServer{
            .allocator = allocator,
            .mastra = mastra,
        };
    }

    pub fn start(self: *MastraServer, port: u16) !void {
        var listener = zap.HttpListener.init(.{
            .port = port,
            .on_request = onRequest,
            .log = true,
        });
        defer listener.deinit();

        listener.setUserData(self);

        try listener.listen();

        std.debug.print("Mastra server listening on port {d}\n", .{port});

        // 启动事件循环
        zap.start(.{
            .threads = 2,
            .workers = 2,
        });
    }

    fn onRequest(r: zap.Request) void {
        const self = @ptrCast(*MastraServer, @alignCast(r.getUserData()));

        if (r.path) |path| {
            if (std.mem.startsWith(u8, path, "/api/agents/")) {
                self.handleAgentRequest(r) catch |err| {
                    std.log.err("Agent request error: {}", .{err});
                    r.setStatus(.internal_server_error);
                    r.sendBody("Internal server error") catch {};
                };
            } else if (std.mem.startsWith(u8, path, "/api/workflows/")) {
                self.handleWorkflowRequest(r) catch |err| {
                    std.log.err("Workflow request error: {}", .{err});
                    r.setStatus(.internal_server_error);
                    r.sendBody("Internal server error") catch {};
                };
            } else {
                r.setStatus(.not_found);
                r.sendBody("Not found") catch {};
            }
        }
    }

    fn handleAgentRequest(self: *MastraServer, r: zap.Request) !void {
        if (r.method == .POST) {
            // POST /api/agents/{agent_name}/generate
            const path_parts = std.mem.split(u8, r.path.?[12..], "/"); // 跳过 "/api/agents/"
            const agent_name = path_parts.next() orelse return error.InvalidPath;

            if (self.mastra.getAgent(agent_name)) |agent| {
                const body = r.body orelse return error.MissingBody;

                const parsed = try std.json.parseFromSlice(struct {
                    messages: []Message,
                }, self.allocator, body, .{});
                defer parsed.deinit();

                const response = try agent.generate(parsed.value.messages);
                defer response.deinit();

                const response_json = try std.json.stringifyAlloc(self.allocator, response, .{});
                defer self.allocator.free(response_json);

                r.setHeader("Content-Type", "application/json");
                try r.sendBody(response_json);
            } else {
                r.setStatus(.not_found);
                try r.sendBody("Agent not found");
            }
        }
    }

    fn handleWorkflowRequest(self: *MastraServer, r: zap.Request) !void {
        if (r.method == .POST) {
            // POST /api/workflows/{workflow_name}/execute
            const path_parts = std.mem.split(u8, r.path.?[15..], "/"); // 跳过 "/api/workflows/"
            const workflow_name = path_parts.next() orelse return error.InvalidPath;

            if (self.mastra.getWorkflow(workflow_name)) |workflow| {
                const body = r.body orelse return error.MissingBody;

                const input = try std.json.parseFromSlice(std.json.Value, self.allocator, body, .{});
                defer input.deinit();

                const run = try workflow.execute(input.value);
                defer run.deinit();

                const response_json = try std.json.stringifyAlloc(self.allocator, .{
                    .id = run.id,
                    .status = @tagName(run.status),
                    .started_at = run.started_at,
                    .completed_at = run.completed_at,
                }, .{});
                defer self.allocator.free(response_json);

                r.setHeader("Content-Type", "application/json");
                try r.sendBody(response_json);
            } else {
                r.setStatus(.not_found);
                try r.sendBody("Workflow not found");
            }
        }
    }
};
```

#### 4.2 CLI工具 (使用std.process原生解析)
```zig
// CLI实现 - 零依赖纯Zig方案
const std = @import("std");

const CliError = error{
    InvalidCommand,
    MissingArgument,
    InvalidArgument,
};

const Command = enum {
    init,
    dev,
    build,
    deploy,
    help,
    version,

    pub fn fromString(str: []const u8) ?Command {
        const commands = std.ComptimeStringMap(Command, .{
            .{ "init", .init },
            .{ "dev", .dev },
            .{ "build", .build },
            .{ "deploy", .deploy },
            .{ "help", .help },
            .{ "version", .version },
            .{ "-h", .help },
            .{ "--help", .help },
            .{ "-v", .version },
            .{ "--version", .version },
        });
        return commands.get(str);
    }
};

const CliArgs = struct {
    command: Command,
    positional_args: [][]const u8,
    flags: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator) CliArgs {
        return CliArgs{
            .command = .help,
            .positional_args = &[_][]const u8{},
            .flags = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *CliArgs) void {
        self.flags.deinit();
    }

    pub fn hasFlag(self: *CliArgs, flag: []const u8) bool {
        return self.flags.contains(flag);
    }

    pub fn getFlagValue(self: *CliArgs, flag: []const u8) ?[]const u8 {
        return self.flags.get(flag);
    }
};

fn parseArgs(allocator: std.mem.Allocator) !CliArgs {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var cli_args = CliArgs.init(allocator);
    errdefer cli_args.deinit();

    if (args.len < 2) {
        cli_args.command = .help;
        return cli_args;
    }

    // 解析命令
    const command_str = args[1];
    cli_args.command = Command.fromString(command_str) orelse {
        std.debug.print("Error: Unknown command '{s}'\n", .{command_str});
        return CliError.InvalidCommand;
    };

    // 解析剩余参数
    var positional = std.ArrayList([]const u8).init(allocator);
    defer positional.deinit();

    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.startsWith(u8, arg, "--")) {
            // 长选项 --key=value 或 --key value
            if (std.mem.indexOf(u8, arg, "=")) |eq_pos| {
                const key = arg[2..eq_pos];
                const value = arg[eq_pos + 1..];
                try cli_args.flags.put(try allocator.dupe(u8, key), try allocator.dupe(u8, value));
            } else {
                const key = arg[2..];
                if (i + 1 < args.len and !std.mem.startsWith(u8, args[i + 1], "-")) {
                    i += 1;
                    try cli_args.flags.put(try allocator.dupe(u8, key), try allocator.dupe(u8, args[i]));
                } else {
                    try cli_args.flags.put(try allocator.dupe(u8, key), "");
                }
            }
        } else if (std.mem.startsWith(u8, arg, "-") and arg.len > 1) {
            // 短选项 -k value
            const key = arg[1..];
            if (i + 1 < args.len and !std.mem.startsWith(u8, args[i + 1], "-")) {
                i += 1;
                try cli_args.flags.put(try allocator.dupe(u8, key), try allocator.dupe(u8, args[i]));
            } else {
                try cli_args.flags.put(try allocator.dupe(u8, key), "");
            }
        } else {
            // 位置参数
            try positional.append(try allocator.dupe(u8, arg));
        }
    }

    cli_args.positional_args = try positional.toOwnedSlice();
    return cli_args;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var cli_args = parseArgs(allocator) catch |err| switch (err) {
        CliError.InvalidCommand => {
            try printHelp();
            return;
        },
        else => return err,
    };
    defer cli_args.deinit();

    switch (cli_args.command) {
        .help => try printHelp(),
        .version => try printVersion(),
        .init => try initProject(allocator, cli_args),
        .dev => try startDevServer(allocator, cli_args),
        .build => try buildProject(allocator, cli_args),
        .deploy => try deployProject(allocator, cli_args),
    }
}

fn printHelp() !void {
    const help_text =
        \\Mastra.zig - AI应用开发框架
        \\
        \\用法:
        \\    mastra <COMMAND> [OPTIONS] [ARGS]
        \\
        \\命令:
        \\    init [PROJECT_NAME]     初始化新项目
        \\    dev                     启动开发服务器
        \\    build                   构建项目
        \\    deploy                  部署项目
        \\    help                    显示帮助信息
        \\    version                 显示版本信息
        \\
        \\选项:
        \\    -h, --help              显示帮助信息
        \\    -v, --version           显示版本信息
        \\    --port <PORT>           指定端口号 (dev命令)
        \\    --target <TARGET>       指定部署目标 (deploy命令)
        \\
        \\示例:
        \\    mastra init my-ai-app
        \\    mastra dev --port 3000
        \\    mastra deploy --target vercel
        \\
    ;

    try std.io.getStdOut().writeAll(help_text);
}

fn printVersion() !void {
    try std.io.getStdOut().writer().print("mastra-zig version 0.1.0\n");
}

fn initProject(allocator: std.mem.Allocator, cli_args: CliArgs) !void {
    const project_name = if (cli_args.positional_args.len > 0)
        cli_args.positional_args[0]
    else
        "my-mastra-project";

    std.debug.print("正在初始化Mastra项目: {s}\n", .{project_name});

    // 创建项目目录结构
    try std.fs.cwd().makeDir(project_name);

    var project_dir = try std.fs.cwd().openDir(project_name, .{});
    defer project_dir.close();

    // 创建build.zig.zon
    const build_zig_zon_content =
        \\.{
        \\    .name = "my-mastra-app",
        \\    .version = "0.1.0",
        \\    .minimum_zig_version = "0.12.0",
        \\    .dependencies = .{
        \\        .mastra = .{
        \\            .url = "https://github.com/mastra-ai/mastra.zig/archive/main.tar.gz",
        \\            .hash = "1220...", // 实际hash值
        \\        },
        \\    },
        \\    .paths = .{
        \\        "build.zig",
        \\        "build.zig.zon",
        \\        "src",
        \\    },
        \\}
    ;

    try project_dir.writeFile(.{ .sub_path = "build.zig.zon", .data = build_zig_zon_content });

    // 创建build.zig
    const build_zig_content =
        \\const std = @import("std");
        \\
        \\pub fn build(b: *std.Build) void {
        \\    const target = b.standardTargetOptions(.{});
        \\    const optimize = b.standardOptimizeOption(.{});
        \\
        \\    const mastra = b.dependency("mastra", .{
        \\        .target = target,
        \\        .optimize = optimize,
        \\    });
        \\
        \\    const exe = b.addExecutable(.{
        \\        .name = "app",
        \\        .root_source_file = b.path("src/main.zig"),
        \\        .target = target,
        \\        .optimize = optimize,
        \\    });
        \\
        \\    exe.root_module.addImport("mastra", mastra.module("mastra"));
        \\    exe.linkLibC();
        \\    exe.linkSystemLibrary("sqlite3");
        \\
        \\    b.installArtifact(exe);
        \\
        \\    const run_cmd = b.addRunArtifact(exe);
        \\    run_cmd.step.dependOn(b.getInstallStep());
        \\    if (b.args) |args| {
        \\        run_cmd.addArgs(args);
        \\    }
        \\
        \\    const run_step = b.step("run", "Run the app");
        \\    run_step.dependOn(&run_cmd.step);
        \\}
    ;

    try project_dir.writeFile(.{ .sub_path = "build.zig", .data = build_zig_content });

    // 创建src目录和main.zig
    try project_dir.makeDir("src");
    var src_dir = try project_dir.openDir("src", .{});
    defer src_dir.close();

    const main_zig_content =
        \\const std = @import("std");
        \\const mastra = @import("mastra");
        \\
        \\pub fn main() !void {
        \\    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        \\    defer _ = gpa.deinit();
        \\    const allocator = gpa.allocator();
        \\
        \\    // 初始化Mastra
        \\    var m = try mastra.Mastra.init(allocator, .{});
        \\    defer m.deinit();
        \\
        \\    // 创建LLM
        \\    const llm = try mastra.LLM.init(allocator, .{
        \\        .provider = .openai,
        \\        .model = "gpt-4",
        \\        .api_key = std.process.getEnvVarOwned(allocator, "OPENAI_API_KEY") catch null,
        \\    });
        \\    defer llm.deinit();
        \\
        \\    // 创建Agent
        \\    const agent = try mastra.Agent.init(allocator, .{
        \\        .name = "助手",
        \\        .model = llm,
        \\        .instructions = "你是一个有用的AI助手",
        \\    });
        \\    defer agent.deinit();
        \\
        \\    // 注册Agent
        \\    try m.registerAgent("assistant", agent);
        \\
        \\    std.debug.print("Mastra项目初始化成功！\n", .{});
        \\    std.debug.print("请设置OPENAI_API_KEY环境变量\n", .{});
        \\}
    ;

    try src_dir.writeFile(.{ .sub_path = "main.zig", .data = main_zig_content });

    // 创建.env.example文件
    const env_example_content =
        \\# OpenAI API密钥
        \\OPENAI_API_KEY=sk-your-api-key-here
        \\
        \\# Anthropic API密钥 (可选)
        \\ANTHROPIC_API_KEY=your-anthropic-key-here
        \\
        \\# 日志级别
        \\LOG_LEVEL=info
        \\
        \\# 数据库路径
        \\DATABASE_URL=data.db
    ;

    try project_dir.writeFile(.{ .sub_path = ".env.example", .data = env_example_content });

    // 创建README.md
    const readme_content =
        \\# My Mastra App
        \\
        \\使用Mastra.zig构建的AI应用
        \\
        \\## 快速开始
        \\
        \\1. 复制环境变量文件：
        \\   ```bash
        \\   cp .env.example .env
        \\   ```
        \\
        \\2. 编辑`.env`文件，设置你的API密钥
        \\
        \\3. 运行应用：
        \\   ```bash
        \\   zig build run
        \\   ```
        \\
        \\## 开发
        \\
        \\- `zig build` - 构建项目
        \\- `zig build run` - 运行项目
        \\- `zig build test` - 运行测试
        \\
        \\## 部署
        \\
        \\项目构建后会生成单个可执行文件，可以直接部署到任何支持的平台。
    ;

    try project_dir.writeFile(.{ .sub_path = "README.md", .data = readme_content });

    std.debug.print("项目 '{s}' 创建成功！\n", .{project_name});
    std.debug.print("运行 'cd {s} && zig build run' 启动你的项目。\n", .{project_name});
}

fn startDevServer(allocator: std.mem.Allocator, cli_args: CliArgs) !void {
    _ = allocator;

    const port = if (cli_args.getFlagValue("port")) |port_str|
        std.fmt.parseInt(u16, port_str, 10) catch 8080
    else
        8080;

    std.debug.print("正在启动开发服务器，端口: {d}...\n", .{port});
    // TODO: 实现开发服务器逻辑
}

fn buildProject(allocator: std.mem.Allocator, cli_args: CliArgs) !void {
    _ = allocator;
    _ = cli_args;

    std.debug.print("正在构建项目...\n", .{});
    // TODO: 实现构建逻辑
}

fn deployProject(allocator: std.mem.Allocator, cli_args: CliArgs) !void {
    _ = allocator;

    const target = cli_args.getFlagValue("target") orelse "local";

    std.debug.print("正在部署项目到: {s}...\n", .{target});
    // TODO: 实现部署逻辑
}
```

## 技术架构设计

### 核心设计原则
1. **零成本抽象** - 使用Zig的编译时特性
2. **内存安全** - 显式分配器管理，无隐藏分配
3. **性能优先** - 最小化分配，优先使用栈分配
4. **类型安全** - 所有配置和数据结构强类型化
5. **可组合性** - 模块化设计，支持混合搭配

### 关键架构模式
1. **构建器模式** - 用于配置复杂对象
2. **策略模式** - 用于不同的LLM提供商和存储后端
3. **观察者模式** - 用于遥测和事件处理
4. **工厂模式** - 用于创建不同类型的工具和集成
5. **依赖注入** - 使用Zig的结构体组合

### 性能优化策略
1. **连接池** - HTTP客户端和数据库连接
2. **内存池** - 频繁分配的对象
3. **流式处理** - 大数据集和响应
4. **延迟加载** - 昂贵的资源
5. **缓存机制** - 频繁访问的数据

## API设计示例

### 简单Agent使用
```zig
const std = @import("std");
const mastra = @import("mastra");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 初始化Mastra
    var m = try mastra.Mastra.init(allocator, .{});
    defer m.deinit();

    // 创建LLM
    const llm = try mastra.LLM.init(allocator, .{
        .provider = .openai,
        .model = "gpt-4",
        .api_key = std.os.getenv("OPENAI_API_KEY"),
    });
    defer llm.deinit();

    // 创建Agent
    const agent = try mastra.Agent.init(allocator, .{
        .name = "助手",
        .model = llm,
        .instructions = "你是一个有用的AI助手",
    });
    defer agent.deinit();

    // 注册Agent
    try m.registerAgent("assistant", agent);

    // 使用Agent
    const messages = [_]mastra.Message{
        .{ .role = "user", .content = "你好！" },
    };
    
    const response = try agent.generate(&messages);
    defer response.deinit();
    
    std.debug.print("回复: {s}\n", .{response.content});
}
```

### 工作流使用示例
```zig
// 创建工作流
const workflow = try mastra.Workflow.init(allocator, .{
    .id = "data_analysis",
    .name = "数据分析工作流",
    .steps = &[_]mastra.StepConfig{
        .{
            .id = "fetch_data",
            .name = "获取数据",
            .description = "从API获取数据",
        },
        .{
            .id = "analyze_data", 
            .name = "分析数据",
            .description = "使用AI分析数据",
            .depends_on = &[_][]const u8{"fetch_data"},
        },
        .{
            .id = "generate_report",
            .name = "生成报告", 
            .description = "生成分析报告",
            .depends_on = &[_][]const u8{"analyze_data"},
        },
    },
}, m.getLogger());
defer workflow.deinit();

// 设置步骤执行器
_ = workflow.setStepExecutor("fetch_data", fetchDataStep);
_ = workflow.setStepExecutor("analyze_data", analyzeDataStep);
_ = workflow.setStepExecutor("generate_report", generateReportStep);

// 执行工作流
const input = std.json.Value{ .object = std.json.ObjectMap.init(allocator) };
const run = try workflow.execute(input);
defer run.deinit();

std.debug.print("工作流状态: {s}\n", .{@tagName(run.status)});
```

## 里程碑和成功标准

### MVP里程碑（第4周）
- ✅ 可工作的OpenAI集成和真实API调用
- ✅ 功能性Agent可以执行工具
- ✅ 基础工作流执行
- ✅ SQLite存储集成
- ✅ 全面的测试套件
- ✅ 文档和示例

### 生产就绪（第8周）
- ✅ 多LLM提供商支持
- ✅ 高级工作流功能
- ✅ 向量数据库集成
- ✅ HTTP服务器和REST API
- ✅ 遥测和监控
- ✅ 性能基准测试

### 生态系统完整（第10周）
- ✅ CLI工具和项目脚手架
- ✅ 部署自动化
- ✅ 插件系统
- ✅ 全面文档
- ✅ 社区示例和模板

### 成功标准
1. **性能**: 比TypeScript版本快10倍
2. **内存**: 比Node.js版本少用50%内存
3. **可靠性**: 生产环境零运行时崩溃
4. **易用性**: 简单易学的API
5. **兼容性**: 与现有Mastra生态系统协作

## 风险缓解

### 技术风险
1. **Zig生态系统成熟度** - 使用稳定库，回馈社区
2. **学习曲线** - 提供优秀文档和示例
3. **集成复杂性** - 从简单集成开始，逐步构建复杂性
4. **性能期望** - 设置现实基准，持续测量

### 项目风险
1. **范围蔓延** - 严格按照优先级执行
2. **资源限制** - 专注MVP，延后非关键功能
3. **质量保证** - 每个里程碑都有测试和文档要求

## 依赖库配置 (build.zig.zon)

```zig
.{
    .name = "mastra",
    .version = "0.1.0",
    .minimum_zig_version = "0.12.0",
    .dependencies = .{
        .libxev = .{
            .url = "https://github.com/mitchellh/libxev/archive/main.tar.gz",
            .hash = "1220...", // 实际hash值
        },
        .zap = .{
            .url = "https://github.com/zigzap/zap/archive/main.tar.gz",
            .hash = "1220...",
        },
        .zqlite = .{
            .url = "https://github.com/karlseguin/zqlite.zig/archive/main.tar.gz",
            .hash = "1220...",
        },
        .log = .{
            .url = "https://github.com/karlseguin/log.zig/archive/main.tar.gz",
            .hash = "1220...",
        },
        .zul = .{
            .url = "https://github.com/karlseguin/zul/archive/main.tar.gz",
            .hash = "1220...",
        },

    },
    .paths = .{
        "build.zig",
        "build.zig.zon",
        "src",
        "test",
    },
}
```

## 更新的build.zig配置

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 添加依赖
    const libxev = b.dependency("libxev", .{
        .target = target,
        .optimize = optimize,
    });

    const zap = b.dependency("zap", .{
        .target = target,
        .optimize = optimize,
    });

    const zqlite = b.dependency("zqlite", .{
        .target = target,
        .optimize = optimize,
    });

    const log_zig = b.dependency("log", .{
        .target = target,
        .optimize = optimize,
    });

    const zul = b.dependency("zul", .{
        .target = target,
        .optimize = optimize,
    });



    // 主库
    const lib = b.addStaticLibrary(.{
        .name = "mastra",
        .root_source_file = b.path("src/mastra.zig"),
        .target = target,
        .optimize = optimize,
    });

    // 添加模块导入
    lib.root_module.addImport("xev", libxev.module("xev"));
    lib.root_module.addImport("zap", zap.module("zap"));
    lib.root_module.addImport("zqlite", zqlite.module("zqlite"));
    lib.root_module.addImport("log", log_zig.module("log"));
    lib.root_module.addImport("zul", zul.module("zul"));

    // 链接SQLite
    lib.linkLibC();
    lib.linkSystemLibrary("sqlite3");

    b.installArtifact(lib);

    // 可执行文件
    const exe = b.addExecutable(.{
        .name = "mastra",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("xev", libxev.module("xev"));
    exe.root_module.addImport("zap", zap.module("zap"));
    exe.root_module.addImport("zqlite", zqlite.module("zqlite"));
    exe.root_module.addImport("log", log_zig.module("log"));
    exe.root_module.addImport("zul", zul.module("zul"));

    exe.linkLibC();
    exe.linkSystemLibrary("sqlite3");

    b.installArtifact(exe);

    // CLI工具 (零依赖)
    const cli = b.addExecutable(.{
        .name = "mastra-cli",
        .root_source_file = b.path("src/cli.zig"),
        .target = target,
        .optimize = optimize,
    });

    cli.root_module.addImport("zul", zul.module("zul"));

    b.installArtifact(cli);

    // 运行命令
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // 测试
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/mastra.zig"),
        .target = target,
        .optimize = optimize,
    });

    unit_tests.root_module.addImport("xev", libxev.module("xev"));
    unit_tests.root_module.addImport("zap", zap.module("zap"));
    unit_tests.root_module.addImport("zqlite", zqlite.module("zqlite"));
    unit_tests.root_module.addImport("log", log_zig.module("log"));
    unit_tests.root_module.addImport("zul", zul.module("zul"));

    unit_tests.linkLibC();
    unit_tests.linkSystemLibrary("sqlite3");

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // 基准测试
    const bench = b.addExecutable(.{
        .name = "bench",
        .root_source_file = b.path("bench/main.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });

    bench.root_module.addImport("mastra", &lib.root_module);

    const run_bench = b.addRunArtifact(bench);
    const bench_step = b.step("bench", "Run benchmarks");
    bench_step.dependOn(&run_bench.step);
}
```

## 性能基准测试框架

```zig
// bench/main.zig
const std = @import("std");
const mastra = @import("mastra");

const BenchResult = struct {
    name: []const u8,
    iterations: u64,
    total_time_ns: u64,
    avg_time_ns: u64,
    ops_per_sec: f64,
};

fn benchmark(comptime name: []const u8, iterations: u64, func: anytype) !BenchResult {
    const start = std.time.nanoTimestamp();

    var i: u64 = 0;
    while (i < iterations) : (i += 1) {
        try func();
    }

    const end = std.time.nanoTimestamp();
    const total_time = @as(u64, @intCast(end - start));
    const avg_time = total_time / iterations;
    const ops_per_sec = @as(f64, @floatFromInt(iterations)) / (@as(f64, @floatFromInt(total_time)) / 1_000_000_000.0);

    return BenchResult{
        .name = name,
        .iterations = iterations,
        .total_time_ns = total_time,
        .avg_time_ns = avg_time,
        .ops_per_sec = ops_per_sec,
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Mastra.zig Performance Benchmarks\n");
    std.debug.print("==================================\n\n");

    // Vector similarity benchmark
    const vec_result = try benchmark("Vector Cosine Similarity", 100_000, struct {
        fn run() !void {
            const vec1 = [_]f32{1.0, 2.0, 3.0, 4.0} ** 384; // 1536 dimensions
            const vec2 = [_]f32{0.5, 1.5, 2.5, 3.5} ** 384;

            var dot_product: f32 = 0.0;
            var norm1: f32 = 0.0;
            var norm2: f32 = 0.0;

            for (vec1, vec2) |v1, v2| {
                dot_product += v1 * v2;
                norm1 += v1 * v1;
                norm2 += v2 * v2;
            }

            const similarity = dot_product / (@sqrt(norm1) * @sqrt(norm2));
            _ = similarity;
        }
    }.run);

    printBenchResult(vec_result);

    // JSON parsing benchmark
    const json_result = try benchmark("JSON Parse/Stringify", 10_000, struct {
        fn run() !void {
            const json_str =
                \\{"messages": [{"role": "user", "content": "Hello, world!"}], "model": "gpt-4", "temperature": 0.7}
            ;

            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer arena.deinit();
            const arena_allocator = arena.allocator();

            const parsed = try std.json.parseFromSlice(std.json.Value, arena_allocator, json_str, .{});
            const stringified = try std.json.stringifyAlloc(arena_allocator, parsed.value, .{});
            _ = stringified;
        }
    }.run);

    printBenchResult(json_result);
}

fn printBenchResult(result: BenchResult) void {
    std.debug.print("{s}:\n", .{result.name});
    std.debug.print("  Iterations: {d}\n", .{result.iterations});
    std.debug.print("  Total time: {d:.2} ms\n", .{@as(f64, @floatFromInt(result.total_time_ns)) / 1_000_000.0});
    std.debug.print("  Avg time: {d:.2} μs\n", .{@as(f64, @floatFromInt(result.avg_time_ns)) / 1_000.0});
    std.debug.print("  Ops/sec: {d:.0}\n\n", .{result.ops_per_sec});
}
```

## 跨平台编译支持分析

### 支持的目标平台

Zig具有出色的跨平台编译能力，可以通过`zig targets`命令查看所有支持的目标。主要支持的平台包括：

#### 桌面平台
- **Linux**: x86_64, aarch64, arm, riscv64
- **Windows**: x86_64, aarch64, x86
- **macOS**: x86_64, aarch64

#### 移动平台
- **Android**: aarch64-linux-android, armv7a-linux-androideabi, x86_64-linux-android
- **iOS**: aarch64-ios, x86_64-ios-simulator

#### 嵌入式和其他
- **WebAssembly**: wasm32-wasi, wasm32-freestanding
- **FreeBSD, OpenBSD, NetBSD**: 多架构支持
- **Embedded**: 各种ARM Cortex-M系列

### 鸿蒙系统编译支持

#### 当前状态
根据调研，Zig目前**不直接支持**鸿蒙系统(HarmonyOS NEXT)作为编译目标，但有以下可行方案：

#### 1. OpenHarmony支持 (推荐方案)
```bash
# OpenHarmony使用标准的Linux ABI
# 可以使用aarch64-linux-gnu目标编译
zig build -Dtarget=aarch64-linux-gnu

# 或者使用更具体的目标
zig build -Dtarget=aarch64-linux-musl
```

**优势:**
- OpenHarmony基于Linux内核，兼容性好
- 可以直接使用现有的aarch64-linux目标
- 支持标准的POSIX API

#### 2. 通过交叉编译支持
```zig
// build.zig中添加鸿蒙目标支持
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 检测是否为鸿蒙目标
    const is_harmonyos = b.option(bool, "harmonyos", "Build for HarmonyOS") orelse false;

    const actual_target = if (is_harmonyos)
        std.zig.CrossTarget{
            .cpu_arch = .aarch64,
            .os_tag = .linux,
            .abi = .gnu,
        }
    else
        target;

    const exe = b.addExecutable(.{
        .name = "mastra",
        .root_source_file = b.path("src/main.zig"),
        .target = actual_target,
        .optimize = optimize,
    });

    if (is_harmonyos) {
        // 鸿蒙特定的链接选项
        exe.linkLibC();
        // 可能需要特定的系统库
    }
}
```

#### 3. 未来原生支持计划
```zig
// 预期的鸿蒙目标格式 (未来可能支持)
// aarch64-harmonyos-ohos
// arm-harmonyos-ohos

// 使用方式 (假设未来支持)
zig build -Dtarget=aarch64-harmonyos-ohos
```

### 编译配置示例

#### 多平台构建脚本
```bash
#!/bin/bash
# build-all-platforms.sh

echo "构建所有支持的平台..."

# 桌面平台
zig build -Dtarget=x86_64-linux-gnu -Doptimize=ReleaseFast
zig build -Dtarget=x86_64-windows-gnu -Doptimize=ReleaseFast
zig build -Dtarget=x86_64-macos-none -Doptimize=ReleaseFast
zig build -Dtarget=aarch64-macos-none -Doptimize=ReleaseFast

# 移动平台
zig build -Dtarget=aarch64-linux-android -Doptimize=ReleaseFast
zig build -Dtarget=aarch64-ios-none -Doptimize=ReleaseFast

# 鸿蒙/OpenHarmony (使用Linux目标)
zig build -Dtarget=aarch64-linux-gnu -Doptimize=ReleaseFast -Dharmonyos=true

# WebAssembly
zig build -Dtarget=wasm32-wasi -Doptimize=ReleaseFast

echo "所有平台构建完成！"
```

#### 条件编译支持
```zig
// src/platform.zig
const std = @import("std");
const builtin = @import("builtin");

pub const Platform = enum {
    linux,
    windows,
    macos,
    android,
    ios,
    harmonyos,
    wasm,
    unknown,
};

pub fn getCurrentPlatform() Platform {
    return switch (builtin.os.tag) {
        .linux => if (isAndroid()) .android else if (isHarmonyOS()) .harmonyos else .linux,
        .windows => .windows,
        .macos => .macos,
        .ios => .ios,
        .wasi => .wasm,
        else => .unknown,
    };
}

fn isAndroid() bool {
    // 检测Android特有的特征
    return std.process.getEnvVarOwned(std.heap.page_allocator, "ANDROID_ROOT") != null;
}

fn isHarmonyOS() bool {
    // 检测鸿蒙特有的特征
    // 可以检查特定的系统属性或文件
    const harmonyos_marker = "/system/etc/harmony_version";
    return std.fs.accessAbsolute(harmonyos_marker, .{}) != error.FileNotFound;
}

// 平台特定的功能
pub fn getPlatformSpecificConfig() struct {
    max_connections: u32,
    default_port: u16,
    use_native_tls: bool,
} {
    return switch (getCurrentPlatform()) {
        .harmonyos => .{
            .max_connections = 100,  // 鸿蒙可能有连接限制
            .default_port = 8080,
            .use_native_tls = false, // 可能需要自定义TLS实现
        },
        .android => .{
            .max_connections = 50,
            .default_port = 8080,
            .use_native_tls = true,
        },
        else => .{
            .max_connections = 1000,
            .default_port = 8080,
            .use_native_tls = true,
        },
    };
}
```

### 部署和分发

#### 鸿蒙应用打包
```bash
# 1. 编译为鸿蒙兼容的二进制
zig build -Dtarget=aarch64-linux-gnu -Doptimize=ReleaseFast -Dharmonyos=true

# 2. 创建鸿蒙应用包结构
mkdir -p harmonyos-app/libs/arm64-v8a/
cp zig-out/bin/mastra harmonyos-app/libs/arm64-v8a/

# 3. 添加鸿蒙应用配置文件
# (需要使用DevEco Studio或相关工具)
```

### 限制和注意事项

#### 当前限制
1. **API兼容性**: 鸿蒙的某些API可能与标准Linux不同
2. **系统库**: 可能需要特定的鸿蒙系统库
3. **权限模型**: 鸿蒙的权限系统可能有特殊要求
4. **应用生命周期**: 需要适配鸿蒙的应用管理机制

#### 解决方案
1. **抽象层**: 创建平台抽象层处理差异
2. **条件编译**: 使用Zig的编译时特性处理平台差异
3. **动态加载**: 运行时检测和适配平台特性
4. **测试**: 在鸿蒙设备或模拟器上充分测试

## 下一步行动

### 立即行动（第1周）
1. **设置项目依赖** - 配置build.zig.zon和build.zig，移除clap依赖
2. **集成libxev** - 建立异步事件循环基础
3. **实现HTTP客户端** - 使用std.http.Client + libxev
4. **OpenAI API集成** - 实现真实的API调用
5. **配置管理** - 环境变量和配置文件支持
6. **结构化日志** - 集成log.zig库

### 第2周目标
1. **SQLite集成** - 使用zqlite.zig实现数据持久化
2. **向量存储** - 实现基础向量相似度搜索
3. **工具系统** - 支持函数调用和工具执行
4. **内存优化** - 对象池和内存监控

### 第3-4周目标
1. **HTTP服务器** - 使用zap框架构建REST API
2. **CLI工具** - 使用std.process原生实现项目管理
3. **流式响应** - 实现实时LLM交互
4. **多LLM支持** - 添加Anthropic等提供商
5. **跨平台测试** - 包括鸿蒙兼容性测试

### 技术验证里程碑
- **性能目标**: 比Node.js版本快5-10倍
- **内存目标**: 比Node.js版本少用30-50%内存
- **可靠性目标**: 零内存泄漏，零运行时崩溃
- **兼容性目标**: 与现有Mastra生态系统API兼容
- **跨平台目标**: 支持主流桌面、移动和鸿蒙平台

这个更新的计划移除了外部CLI依赖，使用纯Zig标准库实现，提高了跨平台兼容性，并为鸿蒙系统提供了可行的编译方案。
