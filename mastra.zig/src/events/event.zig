const std = @import("std");

/// Event priority levels
pub const EventPriority = enum(u8) {
    low = 0,
    normal = 1,
    high = 2,
    critical = 3,

    pub fn compare(self: EventPriority, other: EventPriority) std.math.Order {
        return std.math.order(@intFromEnum(self), @intFromEnum(other));
    }
};

/// Event metadata
pub const EventMetadata = struct {
    timestamp: i64,
    source: []const u8,
    correlation_id: ?[]const u8 = null,
    user_id: ?[]const u8 = null,
    session_id: ?[]const u8 = null,
    tags: [][]const u8 = &[_][]const u8{},

    pub fn init(allocator: std.mem.Allocator, source: []const u8) EventMetadata {
        _ = allocator;
        return EventMetadata{
            .timestamp = std.time.timestamp(),
            .source = source,
            .tags = &[_][]const u8{},
        };
    }

    pub fn deinit(self: *EventMetadata, allocator: std.mem.Allocator) void {
        if (self.correlation_id) |id| allocator.free(id);
        if (self.user_id) |id| allocator.free(id);
        if (self.session_id) |id| allocator.free(id);
        for (self.tags) |tag| {
            allocator.free(tag);
        }
        allocator.free(self.tags);
    }
};

/// Base event structure
pub const Event = struct {
    id: []const u8,
    event_type: []const u8,
    data: std.json.Value,
    metadata: EventMetadata,
    priority: EventPriority = .normal,
    retry_count: u32 = 0,
    max_retries: u32 = 3,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, event_type: []const u8, data: std.json.Value, source: []const u8) !Self {
        const id = try std.fmt.allocPrint(allocator, "{s}_{d}_{d}", .{ event_type, std.time.timestamp(), std.crypto.random.int(u32) });

        return Self{
            .id = id,
            .event_type = try allocator.dupe(u8, event_type),
            .data = data,
            .metadata = EventMetadata.init(allocator, source),
            .priority = .normal,
            .retry_count = 0,
            .max_retries = 3,
        };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.event_type);
        self.metadata.deinit(allocator);
    }

    pub fn clone(self: *const Self, allocator: std.mem.Allocator) !Self {
        return Self{
            .id = try allocator.dupe(u8, self.id),
            .event_type = try allocator.dupe(u8, self.event_type),
            .data = self.data, // JSON values are typically immutable
            .metadata = self.metadata, // Shallow copy for now
            .priority = self.priority,
            .retry_count = self.retry_count,
            .max_retries = self.max_retries,
        };
    }

    pub fn shouldRetry(self: *const Self) bool {
        return self.retry_count < self.max_retries;
    }

    pub fn incrementRetry(self: *Self) void {
        self.retry_count += 1;
    }

    pub fn toJson(self: *const Self, allocator: std.mem.Allocator) ![]const u8 {
        var obj = std.json.ObjectMap.init(allocator);
        defer obj.deinit();

        try obj.put("id", std.json.Value{ .string = self.id });
        try obj.put("event_type", std.json.Value{ .string = self.event_type });
        try obj.put("data", self.data);
        try obj.put("priority", std.json.Value{ .integer = @intFromEnum(self.priority) });
        try obj.put("retry_count", std.json.Value{ .integer = @intCast(self.retry_count) });
        try obj.put("max_retries", std.json.Value{ .integer = @intCast(self.max_retries) });

        // Add metadata
        var metadata_obj = std.json.ObjectMap.init(allocator);
        defer metadata_obj.deinit();

        try metadata_obj.put("timestamp", std.json.Value{ .integer = self.metadata.timestamp });
        try metadata_obj.put("source", std.json.Value{ .string = self.metadata.source });

        if (self.metadata.correlation_id) |id| {
            try metadata_obj.put("correlation_id", std.json.Value{ .string = id });
        }

        try obj.put("metadata", std.json.Value{ .object = metadata_obj });

        const json_value = std.json.Value{ .object = obj };
        return try std.json.stringifyAlloc(allocator, json_value, .{});
    }
};

/// Event handler function signature
pub const EventHandler = *const fn (allocator: std.mem.Allocator, event: *const Event) anyerror!void;

/// Event filter function signature
pub const EventFilter = *const fn (event: *const Event) bool;

/// Event subscription
pub const EventSubscription = struct {
    id: []const u8,
    event_type: []const u8,
    handler: EventHandler,
    filter: ?EventFilter = null,
    priority: EventPriority = .normal,
    active: bool = true,
    created_at: i64,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, event_type: []const u8, handler: EventHandler) !Self {
        const id = try std.fmt.allocPrint(allocator, "sub_{d}_{d}", .{ std.time.timestamp(), std.crypto.random.int(u32) });

        return Self{
            .id = id,
            .event_type = try allocator.dupe(u8, event_type),
            .handler = handler,
            .filter = null,
            .priority = .normal,
            .active = true,
            .created_at = std.time.timestamp(),
        };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.event_type);
    }

    pub fn matches(self: *const Self, event: *const Event) bool {
        if (!self.active) return false;

        // Check event type match (support wildcards)
        if (!self.matchesEventType(event.event_type)) return false;

        // Apply custom filter if present
        if (self.filter) |filter| {
            return filter(event);
        }

        return true;
    }

    fn matchesEventType(self: *const Self, event_type: []const u8) bool {
        // Exact match
        if (std.mem.eql(u8, self.event_type, event_type)) return true;

        // Wildcard match (e.g., "user.*" matches "user.created", "user.updated")
        if (std.mem.endsWith(u8, self.event_type, ".*")) {
            const prefix = self.event_type[0 .. self.event_type.len - 2];
            return std.mem.startsWith(u8, event_type, prefix);
        }

        return false;
    }
};

/// Event queue for async processing
pub const EventQueue = struct {
    allocator: std.mem.Allocator,
    events: std.PriorityQueue(Event, void, compareEventPriority),
    mutex: std.Thread.Mutex,
    condition: std.Thread.Condition,
    max_size: usize,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, max_size: usize) Self {
        return Self{
            .allocator = allocator,
            .events = std.PriorityQueue(Event, void, compareEventPriority).init(allocator, {}),
            .mutex = std.Thread.Mutex{},
            .condition = std.Thread.Condition{},
            .max_size = max_size,
        };
    }

    pub fn deinit(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Clean up remaining events
        while (self.events.removeOrNull()) |event| {
            var mut_event = event;
            mut_event.deinit(self.allocator);
        }

        self.events.deinit();
    }

    pub fn enqueue(self: *Self, event: Event) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Check queue size limit
        if (self.events.count() >= self.max_size) {
            return error.QueueFull;
        }

        try self.events.add(event);
        self.condition.signal();
    }

    pub fn dequeue(self: *Self) ?Event {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.events.removeOrNull();
    }

    pub fn dequeueBlocking(self: *Self, timeout_ms: ?u32) ?Event {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (timeout_ms) |timeout| {
            const deadline = std.time.milliTimestamp() + @as(i64, @intCast(timeout));

            while (self.events.count() == 0) {
                const now = std.time.milliTimestamp();
                if (now >= deadline) return null;

                const remaining_ms = @as(u32, @intCast(deadline - now));
                self.condition.timedWait(&self.mutex, remaining_ms * std.time.ns_per_ms) catch return null;
            }
        } else {
            while (self.events.count() == 0) {
                self.condition.wait(&self.mutex);
            }
        }

        return self.events.removeOrNull();
    }

    pub fn size(self: *Self) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.events.count();
    }

    pub fn isEmpty(self: *Self) bool {
        return self.size() == 0;
    }

    pub fn clear(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        while (self.events.removeOrNull()) |event| {
            var mut_event = event;
            mut_event.deinit(self.allocator);
        }
    }

    fn compareEventPriority(_: void, a: Event, b: Event) std.math.Order {
        // Higher priority events come first
        return b.priority.compare(a.priority);
    }
};

/// Event statistics
pub const EventStats = struct {
    total_events_published: u64 = 0,
    total_events_processed: u64 = 0,
    total_events_failed: u64 = 0,
    total_subscriptions: u64 = 0,
    active_subscriptions: u64 = 0,
    queue_size: usize = 0,
    processing_errors: u64 = 0,

    pub fn successRate(self: *const EventStats) f64 {
        if (self.total_events_processed == 0) return 0.0;
        return @as(f64, @floatFromInt(self.total_events_processed - self.total_events_failed)) / @as(f64, @floatFromInt(self.total_events_processed));
    }
};
