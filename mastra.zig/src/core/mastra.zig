const std = @import("std");
const Agent = @import("../agent/agent.zig").Agent;
const Workflow = @import("../workflow/workflow.zig").Workflow;
const Storage = @import("../storage/storage.zig").Storage;
const VectorStore = @import("../storage/vector.zig").VectorStore;
const Memory = @import("../memory/memory.zig").Memory;
const Telemetry = @import("../telemetry/telemetry.zig").Telemetry;
const Logger = @import("../utils/logger.zig").Logger;

pub const Config = struct {
    agents: std.StringHashMap(*Agent) = undefined,
    workflows: std.StringHashMap(*Workflow) = undefined,
    storage: ?*Storage = null,
    vector: ?*VectorStore = null,
    memory: ?*Memory = null,
    telemetry: ?*Telemetry = null,
    logger: ?*Logger = null,
};

pub const Mastra = struct {
    allocator: std.mem.Allocator,
    agents: std.StringHashMap(*Agent),
    workflows: std.StringHashMap(*Workflow),
    storage: ?*Storage,
    vector: ?*VectorStore,
    memory: ?*Memory,
    telemetry: ?*Telemetry,
    logger: *Logger,

    pub fn init(allocator: std.mem.Allocator, config: Config) !Mastra {
        var agents = std.StringHashMap(*Agent).init(allocator);
        errdefer agents.deinit();

        var workflows = std.StringHashMap(*Workflow).init(allocator);
        errdefer workflows.deinit();

        var logger = try Logger.init(allocator, .{ .level = .info });
        errdefer logger.deinit();

        return Mastra{
            .allocator = allocator,
            .agents = agents,
            .workflows = workflows,
            .storage = config.storage,
            .vector = config.vector,
            .memory = config.memory,
            .telemetry = config.telemetry,
            .logger = logger,
        };
    }

    pub fn deinit(self: *Mastra) void {
        var agent_iter = self.agents.iterator();
        while (agent_iter.next()) |entry| {
            entry.value_ptr.*.deinit();
        }
        self.agents.deinit();

        var workflow_iter = self.workflows.iterator();
        while (workflow_iter.next()) |entry| {
            entry.value_ptr.*.deinit();
        }
        self.workflows.deinit();

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
        self.logger.deinit();
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
};