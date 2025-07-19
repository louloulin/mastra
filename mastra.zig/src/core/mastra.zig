//! Mastra核心模块 - 主要的框架入口点
//!
//! 集成所有子系统：
//! - 事件循环管理
//! - Agent和Workflow注册
//! - 存储和向量数据库
//! - 内存管理和遥测

const std = @import("std");
const Agent = @import("../agent/agent.zig").Agent;
const Workflow = @import("../workflow/workflow.zig").Workflow;
const Storage = @import("../storage/storage.zig").Storage;
const VectorStore = @import("../storage/vector.zig").VectorStore;
const Memory = @import("../memory/memory.zig").Memory;
const Telemetry = @import("../telemetry/telemetry.zig").Telemetry;
const Logger = @import("../utils/logger.zig").Logger;
const EventLoop = @import("event_loop.zig").EventLoop;
const HttpClient = @import("http.zig").HttpClient;

/// Mastra配置结构
pub const Config = struct {
    /// 是否启用事件循环
    enable_event_loop: bool = true,
    /// 事件循环线程数
    event_loop_threads: u32 = 1,
    /// HTTP客户端配置
    http_timeout_ms: u32 = 30000,
    /// 日志级别
    log_level: Logger.Level = .info,
    /// 存储配置
    storage: ?*Storage = null,
    vector: ?*VectorStore = null,
    memory: ?*Memory = null,
    telemetry: ?*Telemetry = null,
    logger: ?*Logger = null,
};

/// Mastra主类 - 框架的核心入口点
pub const Mastra = struct {
    allocator: std.mem.Allocator,
    agents: std.StringHashMap(*Agent),
    workflows: std.StringHashMap(*Workflow),
    storage: ?*Storage,
    vector: ?*VectorStore,
    memory: ?*Memory,
    telemetry: ?*Telemetry,
    logger: *Logger,
    event_loop: ?*EventLoop,
    http_client: ?*HttpClient,
    config: Config,

    /// 初始化Mastra实例
    pub fn init(allocator: std.mem.Allocator, config: Config) !Mastra {
        var agents = std.StringHashMap(*Agent).init(allocator);
        errdefer agents.deinit();

        var workflows = std.StringHashMap(*Workflow).init(allocator);
        errdefer workflows.deinit();

        // 初始化日志器
        var logger = if (config.logger) |l| l else blk: {
            const new_logger = try allocator.create(Logger);
            new_logger.* = try Logger.init(allocator, .{ .level = config.log_level });
            break :blk new_logger;
        };
        errdefer if (config.logger == null) {
            logger.deinit();
            allocator.destroy(logger);
        };

        // 初始化事件循环
        var event_loop: ?*EventLoop = null;
        if (config.enable_event_loop) {
            event_loop = try allocator.create(EventLoop);
            event_loop.?.* = try EventLoop.init(allocator);
        }
        errdefer if (event_loop) |loop| {
            loop.deinit();
            allocator.destroy(loop);
        };

        // 初始化HTTP客户端
        var http_client: ?*HttpClient = null;
        if (event_loop) |loop| {
            http_client = try allocator.create(HttpClient);
            http_client.?.* = HttpClient.init(allocator, loop);
        }
        errdefer if (http_client) |client| {
            client.deinit();
            allocator.destroy(client);
        };

        return Mastra{
            .allocator = allocator,
            .agents = agents,
            .workflows = workflows,
            .storage = config.storage,
            .vector = config.vector,
            .memory = config.memory,
            .telemetry = config.telemetry,
            .logger = logger,
            .event_loop = event_loop,
            .http_client = http_client,
            .config = config,
        };
    }

    /// 清理Mastra实例
    pub fn deinit(self: *Mastra) void {
        // 清理HTTP客户端
        if (self.http_client) |client| {
            client.deinit();
            self.allocator.destroy(client);
        }

        // 清理事件循环
        if (self.event_loop) |loop| {
            loop.deinit();
            self.allocator.destroy(loop);
        }

        // 清理agents
        var agent_iter = self.agents.iterator();
        while (agent_iter.next()) |entry| {
            entry.value_ptr.*.deinit();
        }
        self.agents.deinit();

        // 清理workflows
        var workflow_iter = self.workflows.iterator();
        while (workflow_iter.next()) |entry| {
            entry.value_ptr.*.deinit();
        }
        self.workflows.deinit();

        // 清理其他组件
        if (self.storage) |storage| {
            storage.deinit();
        }
        if (self.vector) |vector| {
            vector.deinit();
        }
        if (self.memory) |memory| {
            memory.deinit();
        }
        if (self.telemetry) |telemetry| {
            telemetry.deinit();
        }

        // 清理日志器（如果是我们创建的）
        if (self.config.logger == null) {
            self.logger.deinit();
            self.allocator.destroy(self.logger);
        }
    }

    pub fn getAgent(self: *Mastra, name: []const u8) ?*Agent {
        return self.agents.get(name);
    }

    pub fn getWorkflow(self: *Mastra, name: []const u8) ?*Workflow {
        return self.workflows.get(name);
    }

    pub fn registerAgent(self: *Mastra, name: []const u8, agent: *Agent) !void {
        try self.agents.put(name, agent);
        self.logger.info("Registered agent: {s}", .{name});
    }

    pub fn registerWorkflow(self: *Mastra, name: []const u8, workflow: *Workflow) !void {
        try self.workflows.put(name, workflow);
        self.logger.info("Registered workflow: {s}", .{name});
    }

    pub fn getStorage(self: *Mastra) ?*Storage {
        return self.storage;
    }

    pub fn getVector(self: *Mastra) ?*VectorStore {
        return self.vector;
    }

    pub fn getMemory(self: *Mastra) ?*Memory {
        return self.memory;
    }

    pub fn getTelemetry(self: *Mastra) ?*Telemetry {
        return self.telemetry;
    }

    pub fn getLogger(self: *Mastra) *Logger {
        return self.logger;
    }

    /// 获取事件循环
    pub fn getEventLoop(self: *Mastra) ?*EventLoop {
        return self.event_loop;
    }

    /// 获取HTTP客户端
    pub fn getHttpClient(self: *Mastra) ?*HttpClient {
        return self.http_client;
    }

    /// 启动事件循环（阻塞调用）
    pub fn run(self: *Mastra) !void {
        if (self.event_loop) |loop| {
            self.logger.info("Starting Mastra event loop", .{});
            try loop.run();
        } else {
            self.logger.warn("Event loop not enabled", .{});
        }
    }

    /// 停止事件循环
    pub fn stop(self: *Mastra) void {
        if (self.event_loop) |loop| {
            self.logger.info("Stopping Mastra event loop", .{});
            loop.stop();
        }
    }

    /// 检查事件循环是否正在运行
    pub fn isRunning(self: *const Mastra) bool {
        if (self.event_loop) |loop| {
            return loop.isRunning();
        }
        return false;
    }
};
