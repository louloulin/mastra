const std = @import("std");
const event = @import("event.zig");

/// Event bus configuration
pub const EventBusConfig = struct {
    max_queue_size: usize = 10000,
    worker_threads: u32 = 4,
    enable_persistence: bool = false,
    enable_metrics: bool = true,
    retry_delay_ms: u32 = 1000,
    max_retry_delay_ms: u32 = 30000,
    dead_letter_queue: bool = true,
};

/// Event bus for publish-subscribe pattern
pub const EventBus = struct {
    allocator: std.mem.Allocator,
    config: EventBusConfig,
    subscriptions: std.StringHashMap(std.ArrayList(event.EventSubscription)),
    event_queue: event.EventQueue,
    dead_letter_queue: event.EventQueue,
    worker_threads: []std.Thread,
    running: std.atomic.Value(bool),
    stats: event.EventStats,
    stats_mutex: std.Thread.Mutex,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: EventBusConfig) !*Self {
        const bus = try allocator.create(Self);

        bus.* = Self{
            .allocator = allocator,
            .config = config,
            .subscriptions = std.StringHashMap(std.ArrayList(event.EventSubscription)).init(allocator),
            .event_queue = event.EventQueue.init(allocator, config.max_queue_size),
            .dead_letter_queue = event.EventQueue.init(allocator, config.max_queue_size / 10),
            .worker_threads = try allocator.alloc(std.Thread, config.worker_threads),
            .running = std.atomic.Value(bool).init(false),
            .stats = event.EventStats{},
            .stats_mutex = std.Thread.Mutex{},
        };

        return bus;
    }

    pub fn deinit(self: *Self) void {
        self.stop();

        // Clean up subscriptions
        var iter = self.subscriptions.iterator();
        while (iter.next()) |entry| {
            for (entry.value_ptr.items) |*subscription| {
                subscription.deinit(self.allocator);
            }
            entry.value_ptr.deinit();
        }
        self.subscriptions.deinit();

        // Clean up queues
        self.event_queue.deinit();
        self.dead_letter_queue.deinit();

        self.allocator.free(self.worker_threads);
        self.allocator.destroy(self);
    }

    pub fn start(self: *Self) !void {
        if (self.running.load(.acquire)) {
            return error.AlreadyRunning;
        }

        self.running.store(true, .release);

        // Start worker threads
        for (self.worker_threads, 0..) |*thread, i| {
            thread.* = try std.Thread.spawn(.{}, workerLoop, .{ self, i });
        }

        std.log.info("Event bus started with {d} worker threads", .{self.config.worker_threads});
    }

    pub fn stop(self: *Self) void {
        if (!self.running.load(.acquire)) {
            return;
        }

        self.running.store(false, .release);

        // Wait for worker threads to finish
        for (self.worker_threads) |*thread| {
            thread.join();
        }

        std.log.info("Event bus stopped", .{});
    }

    pub fn subscribe(self: *Self, event_type: []const u8, handler: event.EventHandler) ![]const u8 {
        const subscription = try event.EventSubscription.init(self.allocator, event_type, handler);

        const result = try self.subscriptions.getOrPut(event_type);
        if (!result.found_existing) {
            result.value_ptr.* = std.ArrayList(event.EventSubscription).init(self.allocator);
        }

        try result.value_ptr.append(subscription);

        // Update stats
        self.stats_mutex.lock();
        defer self.stats_mutex.unlock();
        self.stats.total_subscriptions += 1;
        self.stats.active_subscriptions += 1;

        std.log.debug("Subscription created: {s} for event type: {s}", .{ subscription.id, event_type });

        return try self.allocator.dupe(u8, subscription.id);
    }

    pub fn subscribeWithFilter(self: *Self, event_type: []const u8, handler: event.EventHandler, filter: event.EventFilter) ![]const u8 {
        var subscription = try event.EventSubscription.init(self.allocator, event_type, handler);
        subscription.filter = filter;

        const result = try self.subscriptions.getOrPut(event_type);
        if (!result.found_existing) {
            result.value_ptr.* = std.ArrayList(event.EventSubscription).init(self.allocator);
        }

        try result.value_ptr.append(subscription);

        // Update stats
        self.stats_mutex.lock();
        defer self.stats_mutex.unlock();
        self.stats.total_subscriptions += 1;
        self.stats.active_subscriptions += 1;

        return try self.allocator.dupe(u8, subscription.id);
    }

    pub fn unsubscribe(self: *Self, subscription_id: []const u8) bool {
        var iter = self.subscriptions.iterator();
        while (iter.next()) |entry| {
            for (entry.value_ptr.items, 0..) |*subscription, i| {
                if (std.mem.eql(u8, subscription.id, subscription_id)) {
                    subscription.deinit(self.allocator);
                    _ = entry.value_ptr.swapRemove(i);

                    // Update stats
                    self.stats_mutex.lock();
                    defer self.stats_mutex.unlock();
                    self.stats.active_subscriptions -= 1;

                    std.log.debug("Subscription removed: {s}", .{subscription_id});
                    return true;
                }
            }
        }
        return false;
    }

    pub fn publish(self: *Self, event_type: []const u8, data: std.json.Value, source: []const u8) !void {
        const new_event = try event.Event.init(self.allocator, event_type, data, source);

        try self.event_queue.enqueue(new_event);

        // Update stats
        self.stats_mutex.lock();
        defer self.stats_mutex.unlock();
        self.stats.total_events_published += 1;
        self.stats.queue_size = self.event_queue.size();

        std.log.debug("Event published: {s} (type: {s})", .{ new_event.id, event_type });
    }

    pub fn publishWithPriority(self: *Self, event_type: []const u8, data: std.json.Value, source: []const u8, priority: event.EventPriority) !void {
        var new_event = try event.Event.init(self.allocator, event_type, data, source);
        new_event.priority = priority;

        try self.event_queue.enqueue(new_event);

        // Update stats
        self.stats_mutex.lock();
        defer self.stats_mutex.unlock();
        self.stats.total_events_published += 1;
        self.stats.queue_size = self.event_queue.size();
    }

    pub fn publishSync(self: *Self, event_type: []const u8, data: std.json.Value, source: []const u8) !void {
        var new_event = try event.Event.init(self.allocator, event_type, data, source);
        defer new_event.deinit(self.allocator);

        try self.processEvent(&new_event);
    }

    pub fn getStats(self: *Self) event.EventStats {
        self.stats_mutex.lock();
        defer self.stats_mutex.unlock();

        var stats = self.stats;
        stats.queue_size = self.event_queue.size();
        return stats;
    }

    pub fn getSubscriptionCount(self: *Self, event_type: []const u8) usize {
        if (self.subscriptions.get(event_type)) |subscriptions| {
            return subscriptions.items.len;
        }
        return 0;
    }

    pub fn listEventTypes(self: *Self) ![][]const u8 {
        var types = std.ArrayList([]const u8).init(self.allocator);
        defer types.deinit();

        var iter = self.subscriptions.iterator();
        while (iter.next()) |entry| {
            try types.append(try self.allocator.dupe(u8, entry.key_ptr.*));
        }

        return try types.toOwnedSlice();
    }

    fn workerLoop(self: *Self, worker_id: usize) void {
        std.log.debug("Event worker {d} started", .{worker_id});

        while (self.running.load(.acquire)) {
            if (self.event_queue.dequeueBlocking(1000)) |current_event| {
                var event_copy = current_event;
                self.processEventWithRetry(&event_copy) catch |err| {
                    std.log.err("Worker {d} failed to process event {s}: {}", .{ worker_id, event_copy.id, err });

                    // Move to dead letter queue if max retries exceeded
                    if (!event_copy.shouldRetry()) {
                        self.dead_letter_queue.enqueue(event_copy) catch {
                            // If dead letter queue is full, just drop the event
                            event_copy.deinit(self.allocator);
                        };
                    } else {
                        // Re-queue for retry
                        event_copy.incrementRetry();
                        self.event_queue.enqueue(event_copy) catch {
                            // If queue is full, move to dead letter queue
                            self.dead_letter_queue.enqueue(event_copy) catch {
                                event_copy.deinit(self.allocator);
                            };
                        };
                    }
                };
            }
        }

        std.log.debug("Event worker {d} stopped", .{worker_id});
    }

    fn processEventWithRetry(self: *Self, current_event: *event.Event) !void {
        self.processEvent(current_event) catch |err| {
            // Update error stats
            self.stats_mutex.lock();
            self.stats.processing_errors += 1;
            self.stats_mutex.unlock();

            if (current_event.shouldRetry()) {
                // Calculate exponential backoff delay
                const base_delay = self.config.retry_delay_ms;
                const delay = @min(base_delay * (@as(u32, 1) << @intCast(current_event.retry_count)), self.config.max_retry_delay_ms);

                std.log.warn("Event {s} failed, retrying in {d}ms (attempt {d}/{d})", .{ current_event.id, delay, current_event.retry_count + 1, current_event.max_retries });

                // Sleep before retry
                std.time.sleep(delay * std.time.ns_per_ms);

                return err;
            } else {
                std.log.err("Event {s} failed after {d} retries, moving to dead letter queue", .{ current_event.id, current_event.max_retries });

                // Update failure stats
                self.stats_mutex.lock();
                self.stats.total_events_failed += 1;
                self.stats_mutex.unlock();

                return err;
            }
        };

        // Event processed successfully
        self.stats_mutex.lock();
        defer self.stats_mutex.unlock();
        self.stats.total_events_processed += 1;

        current_event.deinit(self.allocator);
    }

    fn processEvent(self: *Self, current_event: *const event.Event) !void {
        // Find matching subscriptions
        var matching_subscriptions = std.ArrayList(*event.EventSubscription).init(self.allocator);
        defer matching_subscriptions.deinit();

        // Check exact event type matches
        if (self.subscriptions.get(current_event.event_type)) |subscriptions| {
            for (subscriptions.items) |*subscription| {
                if (subscription.matches(current_event)) {
                    try matching_subscriptions.append(subscription);
                }
            }
        }

        // Check wildcard matches
        var iter = self.subscriptions.iterator();
        while (iter.next()) |entry| {
            if (std.mem.endsWith(u8, entry.key_ptr.*, ".*")) {
                for (entry.value_ptr.items) |*subscription| {
                    if (subscription.matches(current_event)) {
                        try matching_subscriptions.append(subscription);
                    }
                }
            }
        }

        // Execute handlers
        for (matching_subscriptions.items) |subscription| {
            subscription.handler(self.allocator, current_event) catch |err| {
                std.log.err("Handler failed for subscription {s}: {}", .{ subscription.id, err });
                return err;
            };
        }

        std.log.debug("Event {s} processed by {d} handlers", .{ current_event.id, matching_subscriptions.items.len });
    }
};
