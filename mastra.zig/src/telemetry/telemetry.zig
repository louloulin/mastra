const std = @import("std");
const Logger = @import("../utils/logger.zig").Logger;

pub const TelemetryLevel = enum {
    none,
    basic,
    detailed,
    debug,
};

pub const TelemetryConfig = struct {
    level: TelemetryLevel = .basic,
    endpoint: ?[]const u8 = null,
    api_key: ?[]const u8 = null,
    service_name: []const u8 = "mastra",
    service_version: []const u8 = "1.0.0",
    enable_metrics: bool = true,
    enable_tracing: bool = true,
    enable_logs: bool = true,
};

pub const Span = struct {
    id: []const u8,
    name: []const u8,
    start_time: i64,
    end_time: ?i64 = null,
    attributes: std.StringHashMap(std.json.Value),
    status: []const u8 = "ok",
    parent_id: ?[]const u8 = null,

    pub fn deinit(self: *Span) void {
        // JSON Values don't need explicit deinitialization in newer Zig versions
        self.attributes.deinit();
    }
};

pub const Metric = struct {
    name: []const u8,
    value: f64,
    timestamp: i64,
    labels: std.StringHashMap([]const u8),
    metric_type: []const u8 = "counter",
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Metric) void {
        var iter = self.labels.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.labels.deinit();
    }
};

pub const Telemetry = struct {
    allocator: std.mem.Allocator,
    config: TelemetryConfig,
    logger: *Logger,
    spans: std.ArrayList(Span),
    metrics: std.ArrayList(Metric),
    active_spans: std.StringHashMap(Span),
    mutex: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator, config: TelemetryConfig, logger: *Logger) !*Telemetry {
        const telemetry = try allocator.create(Telemetry);
        const spans = std.ArrayList(Span).init(allocator);
        const metrics = std.ArrayList(Metric).init(allocator);
        const active_spans = std.StringHashMap(Span).init(allocator);

        telemetry.* = Telemetry{
            .allocator = allocator,
            .config = config,
            .logger = logger,
            .spans = spans,
            .metrics = metrics,
            .active_spans = active_spans,
            .mutex = std.Thread.Mutex{},
        };

        logger.info("Telemetry initialized at level: {s}", .{@tagName(config.level)});
        return telemetry;
    }

    pub fn deinit(self: *Telemetry) void {
        for (self.spans.items) |*span| {
            span.deinit();
        }
        self.spans.deinit();

        for (self.metrics.items) |*metric| {
            metric.deinit();
        }
        self.metrics.deinit();

        var span_iter = self.active_spans.iterator();
        while (span_iter.next()) |entry| {
            // 清理值
            entry.value_ptr.deinit();
        }
        self.active_spans.deinit();

        self.allocator.destroy(self);
    }

    pub fn startSpan(self: *Telemetry, name: []const u8, attributes: ?std.json.Value) ![]const u8 {
        if (@intFromEnum(self.config.level) < @intFromEnum(TelemetryLevel.basic)) {
            return "";
        }

        self.mutex.lock();
        defer self.mutex.unlock();

        const span_id = try std.fmt.allocPrint(self.allocator, "span_{d}", .{std.time.timestamp()});

        var span_attributes = std.StringHashMap(std.json.Value).init(self.allocator);
        if (attributes) |attrs| {
            if (attrs == .object) {
                var iter = attrs.object.iterator();
                while (iter.next()) |entry| {
                    try span_attributes.put(entry.key_ptr.*, entry.value_ptr.*);
                }
            }
        }

        const span = Span{
            .id = span_id,
            .name = name,
            .start_time = std.time.timestamp(),
            .attributes = span_attributes,
        };

        try self.spans.append(span);
        try self.active_spans.put(span_id, span);

        self.logger.debug("Started span: {s}", .{name});
        return span_id;
    }

    pub fn endSpan(self: *Telemetry, span_id: []const u8, status: ?[]const u8, attributes: ?std.json.Value) !void {
        if (@intFromEnum(self.config.level) < @intFromEnum(TelemetryLevel.basic)) {
            return;
        }

        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.active_spans.fetchRemove(span_id)) |kv| {
            var span = kv.value;
            span.end_time = std.time.timestamp();
            if (status) |s| {
                span.status = s;
            }

            if (attributes) |attrs| {
                if (attrs == .object) {
                    var iter = attrs.object.iterator();
                    while (iter.next()) |entry| {
                        try span.attributes.put(entry.key_ptr.*, entry.value_ptr.*);
                    }
                }
            }

            self.logger.debug("Ended span: {s}", .{span.name});

            // 释放span_id字符串（由startSpan中的allocPrint分配）
            self.allocator.free(kv.key);
        }
    }

    pub fn recordMetric(self: *Telemetry, name: []const u8, value: f64, labels: ?std.json.Value, metric_type: ?[]const u8) void {
        if (@intFromEnum(self.config.level) < @intFromEnum(TelemetryLevel.basic)) {
            return;
        }

        self.mutex.lock();
        defer self.mutex.unlock();

        var metric_labels = std.StringHashMap([]const u8).init(self.allocator);
        if (labels) |lbls| {
            if (lbls == .object) {
                var iter = lbls.object.iterator();
                while (iter.next()) |entry| {
                    if (entry.value_ptr.* == .string) {
                        const label_value = try self.allocator.dupe(u8, entry.value_ptr.*.string);
                        try metric_labels.put(entry.key_ptr.*, label_value);
                    }
                }
            }
        }

        const metric = Metric{
            .name = name,
            .value = value,
            .timestamp = std.time.timestamp(),
            .labels = metric_labels,
            .metric_type = metric_type orelse "counter",
        };

        try self.metrics.append(metric);
        self.logger.debug("Recorded metric: {s} = {d}", .{ name, value });
    }

    pub fn incrementCounter(self: *Telemetry, name: []const u8, labels: ?std.json.Value) void {
        self.recordMetric(name, 1.0, labels, "counter");
    }

    pub fn recordHistogram(self: *Telemetry, name: []const u8, value: f64, labels: ?std.json.Value) void {
        self.recordMetric(name, value, labels, "histogram");
    }

    pub fn recordGauge(self: *Telemetry, name: []const u8, value: f64, labels: ?std.json.Value) void {
        self.recordMetric(name, value, labels, "gauge");
    }

    pub fn log(self: *Telemetry, level: []const u8, message: []const u8, fields: ?std.json.Value) void {
        if (@intFromEnum(self.config.level) < @intFromEnum(TelemetryLevel.basic)) {
            return;
        }

        self.mutex.lock();
        defer self.mutex.unlock();

        self.logger.info("[{s}] {s}", .{ level, message });

        if (fields) |fs| {
            if (fs == .object) {
                var iter = fs.object.iterator();
                while (iter.next()) |entry| {
                    self.logger.debug("  {s}: {any}", .{ entry.key_ptr.*, entry.value_ptr.* });
                }
            }
        }
    }

    pub fn getSpans(self: *Telemetry) []const Span {
        return self.spans.items;
    }

    pub fn getMetrics(self: *Telemetry) []const Metric {
        return self.metrics.items;
    }

    pub fn flush(self: *Telemetry) void {
        if (@intFromEnum(self.config.level) < @intFromEnum(TelemetryLevel.basic)) {
            return;
        }

        self.mutex.lock();
        defer self.mutex.unlock();

        self.logger.info("Flushing telemetry data", .{});

        // In a real implementation, this would send data to telemetry backend
        // For now, just log summary
        self.logger.info("Flushed {d} spans and {d} metrics", .{ self.spans.items.len, self.metrics.items.len });
    }

    pub fn getConfig(self: *Telemetry) TelemetryConfig {
        return self.config;
    }
};
