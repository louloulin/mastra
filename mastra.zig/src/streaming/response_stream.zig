const std = @import("std");
const stream = @import("stream.zig");

/// Server-Sent Events (SSE) format
pub const SSEEvent = struct {
    id: ?[]const u8 = null,
    event: ?[]const u8 = null,
    data: []const u8,
    retry: ?u32 = null,

    const Self = @This();

    pub fn format(self: *const Self, allocator: std.mem.Allocator) ![]const u8 {
        var result = std.ArrayList(u8).init(allocator);
        defer result.deinit();

        if (self.id) |id| {
            try result.writer().print("id: {s}\n", .{id});
        }

        if (self.event) |event_type| {
            try result.writer().print("event: {s}\n", .{event_type});
        }

        if (self.retry) |retry_ms| {
            try result.writer().print("retry: {d}\n", .{retry_ms});
        }

        // Handle multi-line data
        var lines = std.mem.splitScalar(u8, self.data, '\n');
        while (lines.next()) |line| {
            try result.writer().print("data: {s}\n", .{line});
        }

        try result.append('\n'); // Empty line to end the event

        return try result.toOwnedSlice();
    }
};

/// WebSocket message types
pub const WebSocketMessageType = enum {
    text,
    binary,
    ping,
    pong,
    close,
};

/// WebSocket message
pub const WebSocketMessage = struct {
    type: WebSocketMessageType,
    data: []const u8,

    pub fn text(allocator: std.mem.Allocator, data: []const u8) !WebSocketMessage {
        return WebSocketMessage{
            .type = .text,
            .data = try allocator.dupe(u8, data),
        };
    }

    pub fn binary(allocator: std.mem.Allocator, data: []const u8) !WebSocketMessage {
        return WebSocketMessage{
            .type = .binary,
            .data = try allocator.dupe(u8, data),
        };
    }

    pub fn deinit(self: *WebSocketMessage, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
    }
};

/// Response stream configuration
pub const ResponseStreamConfig = struct {
    format: StreamFormat = .json,
    enable_compression: bool = false,
    buffer_size: usize = 8192,
    flush_interval_ms: u32 = 100,
    heartbeat_interval_ms: u32 = 30000,
    max_connections: u32 = 1000,

    pub const StreamFormat = enum {
        json,
        sse,
        websocket,
        raw,
    };
};

/// Response stream for real-time data
pub const ResponseStream = struct {
    allocator: std.mem.Allocator,
    config: ResponseStreamConfig,
    underlying_stream: stream.Stream,
    connections: std.ArrayList(Connection),
    is_active: bool,
    heartbeat_timer: ?std.time.Timer = null,

    const Self = @This();

    const Connection = struct {
        id: []const u8,
        format: ResponseStreamConfig.StreamFormat,
        last_activity: i64,
        is_active: bool,

        pub fn deinit(self: *Connection, allocator: std.mem.Allocator) void {
            allocator.free(self.id);
        }
    };

    pub fn init(allocator: std.mem.Allocator, config: ResponseStreamConfig) Self {
        const stream_config = stream.StreamConfig{
            .buffer_size = config.buffer_size,
            .max_chunks = 1000,
            .timeout_ms = 30000,
            .enable_backpressure = true,
        };

        return Self{
            .allocator = allocator,
            .config = config,
            .underlying_stream = stream.Stream.init(allocator, stream_config),
            .connections = std.ArrayList(Connection).init(allocator),
            .is_active = false,
            .heartbeat_timer = null,
        };
    }

    pub fn deinit(self: *Self) void {
        self.stop();

        for (self.connections.items) |*conn| {
            conn.deinit(self.allocator);
        }
        self.connections.deinit();
        self.underlying_stream.deinit();
    }

    pub fn start(self: *Self) !void {
        if (self.is_active) {
            return error.AlreadyActive;
        }

        self.is_active = true;
        self.heartbeat_timer = try std.time.Timer.start();

        std.log.info("Response stream started", .{});
    }

    pub fn stop(self: *Self) void {
        if (!self.is_active) {
            return;
        }

        self.is_active = false;
        self.underlying_stream.close();

        std.log.info("Response stream stopped", .{});
    }

    pub fn addConnection(self: *Self, format: ResponseStreamConfig.StreamFormat) ![]const u8 {
        const connection_id = try std.fmt.allocPrint(self.allocator, "conn_{d}_{d}", .{ std.time.timestamp(), std.crypto.random.int(u32) });

        const connection = Connection{
            .id = connection_id,
            .format = format,
            .last_activity = std.time.timestamp(),
            .is_active = true,
        };

        try self.connections.append(connection);

        std.log.debug("Connection added: {s} (format: {})", .{ connection_id, format });

        return try self.allocator.dupe(u8, connection_id);
    }

    pub fn removeConnection(self: *Self, connection_id: []const u8) bool {
        for (self.connections.items, 0..) |*conn, i| {
            if (std.mem.eql(u8, conn.id, connection_id)) {
                conn.deinit(self.allocator);
                _ = self.connections.swapRemove(i);

                std.log.debug("Connection removed: {s}", .{connection_id});
                return true;
            }
        }
        return false;
    }

    pub fn sendData(self: *Self, data: std.json.Value) !void {
        if (!self.is_active) {
            return error.StreamNotActive;
        }

        // Format data for each connection type
        for (self.connections.items) |*conn| {
            if (!conn.is_active) continue;

            const formatted_data = try self.formatData(data, conn.format);
            defer self.allocator.free(formatted_data);

            const chunk = try stream.StreamChunk.initWithId(self.allocator, formatted_data, conn.id);
            try self.underlying_stream.writeChunk(chunk);

            conn.last_activity = std.time.timestamp();
        }
    }

    pub fn sendEvent(self: *Self, event_type: []const u8, data: std.json.Value) !void {
        if (!self.is_active) {
            return error.StreamNotActive;
        }

        for (self.connections.items) |*conn| {
            if (!conn.is_active) continue;

            const formatted_data = switch (conn.format) {
                .sse => blk: {
                    const data_str = try std.json.stringifyAlloc(self.allocator, data, .{});
                    defer self.allocator.free(data_str);

                    const sse_event = SSEEvent{
                        .event = event_type,
                        .data = data_str,
                    };

                    break :blk try sse_event.format(self.allocator);
                },
                .websocket => blk: {
                    var obj = std.json.ObjectMap.init(self.allocator);
                    defer obj.deinit();

                    try obj.put("type", std.json.Value{ .string = event_type });
                    try obj.put("data", data);

                    const json_value = std.json.Value{ .object = obj };
                    break :blk try std.json.stringifyAlloc(self.allocator, json_value, .{});
                },
                .json => try std.json.stringifyAlloc(self.allocator, data, .{}),
                .raw => try std.json.stringifyAlloc(self.allocator, data, .{}),
            };
            defer self.allocator.free(formatted_data);

            const chunk = try stream.StreamChunk.initWithId(self.allocator, formatted_data, conn.id);
            try self.underlying_stream.writeChunk(chunk);

            conn.last_activity = std.time.timestamp();
        }
    }

    pub fn sendHeartbeat(self: *Self) !void {
        if (!self.is_active) {
            return;
        }

        const now = std.time.timestamp();

        for (self.connections.items) |*conn| {
            if (!conn.is_active) continue;

            // Send heartbeat if connection has been idle
            if (now - conn.last_activity > self.config.heartbeat_interval_ms / 1000) {
                const heartbeat_data = switch (conn.format) {
                    .sse => try self.allocator.dupe(u8, ": heartbeat\n\n"),
                    .websocket => try self.allocator.dupe(u8, "{\"type\":\"heartbeat\"}"),
                    .json => try self.allocator.dupe(u8, "{\"heartbeat\":true}"),
                    .raw => try self.allocator.dupe(u8, "heartbeat"),
                };
                defer self.allocator.free(heartbeat_data);

                const chunk = try stream.StreamChunk.initWithId(self.allocator, heartbeat_data, conn.id);
                try self.underlying_stream.writeChunk(chunk);

                conn.last_activity = now;
            }
        }
    }

    pub fn getConnectionCount(self: *Self) usize {
        var active_count: usize = 0;
        for (self.connections.items) |conn| {
            if (conn.is_active) active_count += 1;
        }
        return active_count;
    }

    pub fn getStats(self: *Self) ResponseStreamStats {
        const stream_stats = self.underlying_stream.getStats();

        return ResponseStreamStats{
            .total_connections = self.connections.items.len,
            .active_connections = self.getConnectionCount(),
            .total_bytes_sent = stream_stats.total_bytes,
            .messages_sent = stream_stats.chunk_count,
            .is_active = self.is_active,
        };
    }

    fn formatData(self: *Self, data: std.json.Value, format: ResponseStreamConfig.StreamFormat) ![]const u8 {
        return switch (format) {
            .json => try std.json.stringifyAlloc(self.allocator, data, .{}),
            .sse => blk: {
                const data_str = try std.json.stringifyAlloc(self.allocator, data, .{});
                defer self.allocator.free(data_str);

                const sse_event = SSEEvent{
                    .data = data_str,
                };

                break :blk try sse_event.format(self.allocator);
            },
            .websocket => try std.json.stringifyAlloc(self.allocator, data, .{}),
            .raw => try std.json.stringifyAlloc(self.allocator, data, .{}),
        };
    }

    pub fn cleanupInactiveConnections(self: *Self, timeout_seconds: i64) usize {
        const now = std.time.timestamp();
        var removed_count: usize = 0;

        var i: usize = 0;
        while (i < self.connections.items.len) {
            const conn = &self.connections.items[i];
            if (now - conn.last_activity > timeout_seconds) {
                conn.deinit(self.allocator);
                _ = self.connections.swapRemove(i);
                removed_count += 1;
            } else {
                i += 1;
            }
        }

        if (removed_count > 0) {
            std.log.debug("Cleaned up {d} inactive connections", .{removed_count});
        }

        return removed_count;
    }
};

/// Response stream statistics
pub const ResponseStreamStats = struct {
    total_connections: usize,
    active_connections: usize,
    total_bytes_sent: usize,
    messages_sent: usize,
    is_active: bool,

    pub fn averageMessageSize(self: *const ResponseStreamStats) f64 {
        if (self.messages_sent == 0) return 0.0;
        return @as(f64, @floatFromInt(self.total_bytes_sent)) / @as(f64, @floatFromInt(self.messages_sent));
    }
};
