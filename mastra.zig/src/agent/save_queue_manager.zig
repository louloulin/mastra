const std = @import("std");
const Storage = @import("../storage/storage.zig").Storage;

/// Types of save operations
pub const SaveOperationType = enum {
    message,
    memory,
    state,
    custom,
};

/// Save operation data
pub const SaveOperation = struct {
    id: []const u8,
    operation_type: SaveOperationType,
    table_name: []const u8,
    data: std.json.Value,
    priority: u8, // 0 = highest priority, 255 = lowest
    timestamp: i64,
    retry_count: u8,
    max_retries: u8,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        operation_type: SaveOperationType,
        table_name: []const u8,
        data: std.json.Value,
        priority: u8,
    ) !Self {
        const id = try std.fmt.allocPrint(allocator, "save_{d}_{d}", .{ std.time.timestamp(), std.crypto.random.int(u32) });

        return Self{
            .id = id,
            .operation_type = operation_type,
            .table_name = try allocator.dupe(u8, table_name),
            .data = data,
            .priority = priority,
            .timestamp = std.time.timestamp(),
            .retry_count = 0,
            .max_retries = 3,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.id);
        self.allocator.free(self.table_name);
    }

    /// Compare operations for priority queue (lower priority value = higher priority)
    pub fn compare(_: void, a: SaveOperation, b: SaveOperation) std.math.Order {
        if (a.priority != b.priority) {
            return std.math.order(a.priority, b.priority);
        }
        return std.math.order(a.timestamp, b.timestamp);
    }
};

/// Configuration for SaveQueueManager
pub const SaveQueueConfig = struct {
    max_queue_size: usize = 1000,
    worker_count: usize = 2,
    batch_size: usize = 10,
    flush_interval_ms: u64 = 1000,
    enable_batching: bool = true,
    enable_compression: bool = false,
};

/// Async save queue manager
pub const SaveQueueManager = struct {
    allocator: std.mem.Allocator,
    config: SaveQueueConfig,
    storage: *Storage,
    queue: std.PriorityQueue(SaveOperation, void, SaveOperation.compare),
    mutex: std.Thread.Mutex,
    condition: std.Thread.Condition,
    workers: []std.Thread,
    running: std.atomic.Value(bool),
    stats: SaveStats,

    const Self = @This();

    pub const SaveStats = struct {
        total_operations: std.atomic.Value(u64),
        successful_operations: std.atomic.Value(u64),
        failed_operations: std.atomic.Value(u64),
        retried_operations: std.atomic.Value(u64),
        queue_size: std.atomic.Value(usize),

        pub fn init() SaveStats {
            return SaveStats{
                .total_operations = std.atomic.Value(u64).init(0),
                .successful_operations = std.atomic.Value(u64).init(0),
                .failed_operations = std.atomic.Value(u64).init(0),
                .retried_operations = std.atomic.Value(u64).init(0),
                .queue_size = std.atomic.Value(usize).init(0),
            };
        }
    };

    pub fn init(allocator: std.mem.Allocator, config: SaveQueueConfig, storage: *Storage) !*Self {
        const manager = try allocator.create(Self);

        manager.* = Self{
            .allocator = allocator,
            .config = config,
            .storage = storage,
            .queue = std.PriorityQueue(SaveOperation, void, SaveOperation.compare).init(allocator, {}),
            .mutex = std.Thread.Mutex{},
            .condition = std.Thread.Condition{},
            .workers = try allocator.alloc(std.Thread, config.worker_count),
            .running = std.atomic.Value(bool).init(true),
            .stats = SaveStats.init(),
        };

        // Start worker threads
        for (manager.workers, 0..) |*worker, i| {
            worker.* = try std.Thread.spawn(.{}, workerThread, .{ manager, i });
        }

        return manager;
    }

    pub fn deinit(self: *Self) void {
        // Signal workers to stop
        self.running.store(false, .release);
        self.condition.broadcast();

        // Wait for workers to finish
        for (self.workers) |*worker| {
            worker.join();
        }

        // Clean up remaining operations
        self.mutex.lock();
        defer self.mutex.unlock();

        while (self.queue.removeOrNull()) |op| {
            var mutable_op = op;
            mutable_op.deinit();
        }

        self.queue.deinit();
        self.allocator.free(self.workers);
        self.allocator.destroy(self);
    }

    /// Queue a save operation
    pub fn queueSave(
        self: *Self,
        operation_type: SaveOperationType,
        table_name: []const u8,
        data: std.json.Value,
        priority: u8,
    ) !void {
        const operation = try SaveOperation.init(self.allocator, operation_type, table_name, data, priority);

        self.mutex.lock();
        defer self.mutex.unlock();

        // Check queue size limit
        if (self.queue.count() >= self.config.max_queue_size) {
            return error.QueueFull;
        }

        try self.queue.add(operation);
        self.stats.total_operations.fetchAdd(1, .acq_rel);
        self.stats.queue_size.store(self.queue.count(), .release);

        // Wake up a worker
        self.condition.signal();
    }

    /// Queue a message save operation (convenience method)
    pub fn queueMessageSave(self: *Self, thread_id: []const u8, message_data: std.json.Value) !void {
        const table_name = try std.fmt.allocPrint(self.allocator, "messages_{s}", .{thread_id});
        defer self.allocator.free(table_name);

        try self.queueSave(.message, table_name, message_data, 1); // High priority for messages
    }

    /// Queue a memory save operation (convenience method)
    pub fn queueMemorySave(self: *Self, memory_id: []const u8, memory_data: std.json.Value) !void {
        const table_name = try std.fmt.allocPrint(self.allocator, "memory_{s}", .{memory_id});
        defer self.allocator.free(table_name);

        try self.queueSave(.memory, table_name, memory_data, 2); // Medium priority for memory
    }

    /// Flush all pending operations (blocking)
    pub fn flush(self: *Self) !void {
        while (true) {
            self.mutex.lock();
            const queue_empty = self.queue.len == 0;
            self.mutex.unlock();

            if (queue_empty) break;

            // Wait a bit for workers to process
            std.time.sleep(10 * std.time.ns_per_ms);
        }
    }

    /// Get current statistics
    pub fn getStats(self: *Self) SaveStats {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.stats.queue_size.store(self.queue.len, .release);
        return self.stats;
    }

    /// Worker thread function
    fn workerThread(self: *Self, worker_id: usize) void {
        _ = worker_id; // Suppress unused parameter warning

        while (self.running.load(.acquire)) {
            var operations = std.ArrayList(SaveOperation).init(self.allocator);
            defer {
                for (operations.items) |*op| {
                    op.deinit();
                }
                operations.deinit();
            }

            // Get batch of operations
            {
                self.mutex.lock();
                defer self.mutex.unlock();

                // Wait for operations or shutdown signal
                while (self.queue.count() == 0 and self.running.load(.acquire)) {
                    self.condition.wait(&self.mutex);
                }

                if (!self.running.load(.acquire)) break;

                // Collect batch
                const batch_size = @min(self.config.batch_size, self.queue.count());
                for (0..batch_size) |_| {
                    if (self.queue.removeOrNull()) |op| {
                        operations.append(op) catch break;
                    }
                }

                self.stats.queue_size.store(self.queue.count(), .release);
            }

            // Process batch
            for (operations.items) |*operation| {
                self.processOperation(operation) catch |err| {
                    std.log.err("Failed to process save operation {s}: {}", .{ operation.id, err });

                    // Retry logic
                    if (operation.retry_count < operation.max_retries) {
                        operation.retry_count += 1;
                        _ = self.stats.retried_operations.fetchAdd(1, .acq_rel);

                        // Re-queue with lower priority
                        const retry_op = SaveOperation{
                            .id = operation.id,
                            .operation_type = operation.operation_type,
                            .table_name = operation.table_name,
                            .data = operation.data,
                            .priority = @min(255, operation.priority + 50), // Lower priority
                            .timestamp = std.time.timestamp(),
                            .retry_count = operation.retry_count,
                            .max_retries = operation.max_retries,
                            .allocator = operation.allocator,
                        };

                        self.mutex.lock();
                        self.queue.add(retry_op) catch {
                            _ = self.stats.failed_operations.fetchAdd(1, .acq_rel);
                        };
                        self.mutex.unlock();
                    } else {
                        _ = self.stats.failed_operations.fetchAdd(1, .acq_rel);
                    }
                };
            }
        }
    }

    /// Process a single save operation
    fn processOperation(self: *Self, operation: *SaveOperation) !void {
        _ = try self.storage.create(operation.table_name, operation.data);
        _ = self.stats.successful_operations.fetchAdd(1, .acq_rel);
    }
};

// Tests
test "SaveQueueManager basic operations" {
    const allocator = std.testing.allocator;

    // Create a mock storage
    const storage_config = @import("../storage/storage.zig").StorageConfig{
        .type = .memory,
    };
    var storage = try @import("../storage/storage.zig").Storage.init(allocator, storage_config);
    defer storage.deinit();

    const config = SaveQueueConfig{ .worker_count = 1 };
    var manager = try SaveQueueManager.init(allocator, config, storage);
    defer manager.deinit();

    // Queue some operations
    var data = std.json.ObjectMap.init(allocator);
    defer data.deinit();
    try data.put("test", std.json.Value{ .string = "value" });

    try manager.queueSave(.message, "test_table", std.json.Value{ .object = data }, 1);

    // Wait for processing
    std.time.sleep(100 * std.time.ns_per_ms);

    const stats = manager.getStats();
    try std.testing.expect(stats.total_operations.load(.acquire) > 0);
}

test "SaveQueueManager message save convenience" {
    const allocator = std.testing.allocator;

    const storage_config = @import("../storage/storage.zig").StorageConfig{
        .type = .memory,
    };
    var storage = try @import("../storage/storage.zig").Storage.init(allocator, storage_config);
    defer storage.deinit();

    const config = SaveQueueConfig{ .worker_count = 1 };
    var manager = try SaveQueueManager.init(allocator, config, storage);
    defer manager.deinit();

    var message_data = std.json.ObjectMap.init(allocator);
    defer message_data.deinit();
    try message_data.put("content", std.json.Value{ .string = "Hello" });

    try manager.queueMessageSave("thread_123", std.json.Value{ .object = message_data });

    std.time.sleep(100 * std.time.ns_per_ms);

    const stats = manager.getStats();
    try std.testing.expect(stats.total_operations.load(.acquire) > 0);
}
