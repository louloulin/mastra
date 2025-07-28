const std = @import("std");

/// Stream chunk data
pub const StreamChunk = struct {
    data: []const u8,
    metadata: ?std.json.Value = null,
    is_final: bool = false,
    chunk_id: ?[]const u8 = null,
    timestamp: i64,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, data: []const u8) !Self {
        return Self{
            .data = try allocator.dupe(u8, data),
            .metadata = null,
            .is_final = false,
            .chunk_id = null,
            .timestamp = std.time.timestamp(),
        };
    }

    pub fn initWithId(allocator: std.mem.Allocator, data: []const u8, chunk_id: []const u8) !Self {
        return Self{
            .data = try allocator.dupe(u8, data),
            .metadata = null,
            .is_final = false,
            .chunk_id = try allocator.dupe(u8, chunk_id),
            .timestamp = std.time.timestamp(),
        };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
        if (self.chunk_id) |id| {
            allocator.free(id);
        }
    }

    pub fn clone(self: *const Self, allocator: std.mem.Allocator) !Self {
        return Self{
            .data = try allocator.dupe(u8, self.data),
            .metadata = self.metadata,
            .is_final = self.is_final,
            .chunk_id = if (self.chunk_id) |id| try allocator.dupe(u8, id) else null,
            .timestamp = self.timestamp,
        };
    }
};

/// Stream error types
pub const StreamError = error{
    StreamClosed,
    BufferFull,
    InvalidChunk,
    TimeoutExceeded,
    ConnectionLost,
};

/// Stream configuration
pub const StreamConfig = struct {
    buffer_size: usize = 8192,
    max_chunks: usize = 1000,
    timeout_ms: u32 = 30000,
    enable_backpressure: bool = true,
    chunk_delimiter: ?[]const u8 = null,
    encoding: StreamEncoding = .utf8,

    pub const StreamEncoding = enum {
        utf8,
        binary,
        json,
        base64,
    };
};

/// Stream consumer callback
pub const StreamConsumer = *const fn (allocator: std.mem.Allocator, chunk: *const StreamChunk) anyerror!void;

/// Stream processor callback
pub const StreamProcessor = *const fn (allocator: std.mem.Allocator, input: *const StreamChunk) anyerror!?StreamChunk;

/// Bidirectional stream
pub const Stream = struct {
    allocator: std.mem.Allocator,
    config: StreamConfig,
    chunks: std.ArrayList(StreamChunk),
    consumers: std.ArrayList(StreamConsumer),
    processors: std.ArrayList(StreamProcessor),
    is_closed: bool,
    mutex: std.Thread.Mutex,
    condition: std.Thread.Condition,
    total_bytes: usize,
    chunk_count: usize,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: StreamConfig) Self {
        return Self{
            .allocator = allocator,
            .config = config,
            .chunks = std.ArrayList(StreamChunk).init(allocator),
            .consumers = std.ArrayList(StreamConsumer).init(allocator),
            .processors = std.ArrayList(StreamProcessor).init(allocator),
            .is_closed = false,
            .mutex = std.Thread.Mutex{},
            .condition = std.Thread.Condition{},
            .total_bytes = 0,
            .chunk_count = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.close();

        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.chunks.items) |*chunk| {
            chunk.deinit(self.allocator);
        }
        self.chunks.deinit();
        self.consumers.deinit();
        self.processors.deinit();
    }

    pub fn write(self: *Self, data: []const u8) !void {
        if (self.is_closed) {
            return StreamError.StreamClosed;
        }

        self.mutex.lock();
        defer self.mutex.unlock();

        // Check buffer limits
        if (self.config.enable_backpressure and self.chunks.items.len >= self.config.max_chunks) {
            return StreamError.BufferFull;
        }

        const chunk = try StreamChunk.init(self.allocator, data);

        // Process chunk through processors
        var processed_chunk = chunk;
        for (self.processors.items) |processor| {
            if (try processor(self.allocator, &processed_chunk)) |new_chunk| {
                if (processed_chunk.data.ptr != chunk.data.ptr) {
                    processed_chunk.deinit(self.allocator);
                }
                processed_chunk = new_chunk;
            }
        }

        try self.chunks.append(processed_chunk);
        self.total_bytes += processed_chunk.data.len;
        self.chunk_count += 1;

        // Notify consumers
        for (self.consumers.items) |consumer| {
            consumer(self.allocator, &processed_chunk) catch |err| {
                std.log.err("Stream consumer failed: {}", .{err});
            };
        }

        self.condition.broadcast();

        std.log.debug("Stream chunk written: {d} bytes", .{data.len});
    }

    pub fn writeChunk(self: *Self, chunk: StreamChunk) !void {
        if (self.is_closed) {
            return StreamError.StreamClosed;
        }

        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.config.enable_backpressure and self.chunks.items.len >= self.config.max_chunks) {
            return StreamError.BufferFull;
        }

        var processed_chunk = chunk;

        // Process chunk through processors
        for (self.processors.items) |processor| {
            if (try processor(self.allocator, &processed_chunk)) |new_chunk| {
                if (processed_chunk.data.ptr != chunk.data.ptr) {
                    processed_chunk.deinit(self.allocator);
                }
                processed_chunk = new_chunk;
            }
        }

        try self.chunks.append(processed_chunk);
        self.total_bytes += processed_chunk.data.len;
        self.chunk_count += 1;

        // Notify consumers
        for (self.consumers.items) |consumer| {
            consumer(self.allocator, &processed_chunk) catch |err| {
                std.log.err("Stream consumer failed: {}", .{err});
            };
        }

        self.condition.broadcast();
    }

    pub fn read(self: *Self) ?StreamChunk {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.chunks.items.len > 0) {
            return self.chunks.orderedRemove(0);
        }

        return null;
    }

    pub fn readBlocking(self: *Self, timeout_ms: ?u32) ?StreamChunk {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (timeout_ms) |timeout| {
            const deadline = std.time.milliTimestamp() + @as(i64, @intCast(timeout));

            while (self.chunks.items.len == 0 and !self.is_closed) {
                const now = std.time.milliTimestamp();
                if (now >= deadline) return null;

                const remaining_ms = @as(u32, @intCast(deadline - now));
                self.condition.timedWait(&self.mutex, remaining_ms * std.time.ns_per_ms) catch return null;
            }
        } else {
            while (self.chunks.items.len == 0 and !self.is_closed) {
                self.condition.wait(&self.mutex);
            }
        }

        if (self.chunks.items.len > 0) {
            return self.chunks.orderedRemove(0);
        }

        return null;
    }

    pub fn readAll(self: *Self) ![]StreamChunk {
        self.mutex.lock();
        defer self.mutex.unlock();

        const chunks = try self.allocator.dupe(StreamChunk, self.chunks.items);
        self.chunks.clearRetainingCapacity();

        return chunks;
    }

    pub fn peek(self: *Self) ?*const StreamChunk {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.chunks.items.len > 0) {
            return &self.chunks.items[0];
        }

        return null;
    }

    pub fn addConsumer(self: *Self, consumer: StreamConsumer) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.consumers.append(consumer);
    }

    pub fn addProcessor(self: *Self, processor: StreamProcessor) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.processors.append(processor);
    }

    pub fn close(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (!self.is_closed) {
            self.is_closed = true;
            self.condition.broadcast();
            std.log.debug("Stream closed", .{});
        }
    }

    pub fn isClosed(self: *Self) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.is_closed;
    }

    pub fn size(self: *Self) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.chunks.items.len;
    }

    pub fn isEmpty(self: *Self) bool {
        return self.size() == 0;
    }

    pub fn clear(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.chunks.items) |*chunk| {
            chunk.deinit(self.allocator);
        }
        self.chunks.clearRetainingCapacity();
        self.total_bytes = 0;
        self.chunk_count = 0;
    }

    pub fn getStats(self: *Self) StreamStats {
        self.mutex.lock();
        defer self.mutex.unlock();

        return StreamStats{
            .total_bytes = self.total_bytes,
            .chunk_count = self.chunk_count,
            .buffer_size = self.chunks.items.len,
            .is_closed = self.is_closed,
            .consumer_count = self.consumers.items.len,
            .processor_count = self.processors.items.len,
        };
    }
};

/// Stream statistics
pub const StreamStats = struct {
    total_bytes: usize,
    chunk_count: usize,
    buffer_size: usize,
    is_closed: bool,
    consumer_count: usize,
    processor_count: usize,

    pub fn averageChunkSize(self: *const StreamStats) f64 {
        if (self.chunk_count == 0) return 0.0;
        return @as(f64, @floatFromInt(self.total_bytes)) / @as(f64, @floatFromInt(self.chunk_count));
    }
};
