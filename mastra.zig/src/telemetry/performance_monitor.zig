const std = @import("std");

/// 性能指标类型
pub const MetricType = enum {
    counter,
    gauge,
    histogram,
    timer,
};

/// 性能指标
pub const Metric = struct {
    name: []const u8,
    metric_type: MetricType,
    value: f64,
    timestamp: i64,
    tags: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator, name: []const u8, metric_type: MetricType) Metric {
        return Metric{
            .name = name,
            .metric_type = metric_type,
            .value = 0.0,
            .timestamp = std.time.timestamp(),
            .tags = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Metric) void {
        self.tags.deinit();
    }

    pub fn addTag(self: *Metric, key: []const u8, value: []const u8) !void {
        try self.tags.put(key, value);
    }

    pub fn setValue(self: *Metric, value: f64) void {
        self.value = value;
        self.timestamp = std.time.timestamp();
    }

    pub fn increment(self: *Metric, delta: f64) void {
        self.value += delta;
        self.timestamp = std.time.timestamp();
    }
};

/// 性能监控配置
pub const PerformanceMonitorConfig = struct {
    enable_metrics: bool = true,
    enable_tracing: bool = true,
    metrics_buffer_size: usize = 10000,
    flush_interval_seconds: u64 = 60,
    enable_system_metrics: bool = true,
    enable_memory_metrics: bool = true,
    enable_cpu_metrics: bool = true,
};

/// 系统指标
pub const SystemMetrics = struct {
    memory_usage_bytes: u64,
    memory_peak_bytes: u64,
    cpu_usage_percent: f64,
    thread_count: u32,
    gc_count: u64,
    gc_time_ms: u64,
    uptime_seconds: u64,

    pub fn collect() SystemMetrics {
        // 简化的系统指标收集
        return SystemMetrics{
            .memory_usage_bytes = getCurrentMemoryUsage(),
            .memory_peak_bytes = getPeakMemoryUsage(),
            .cpu_usage_percent = getCPUUsage(),
            .thread_count = getThreadCount(),
            .gc_count = 0, // Zig没有GC
            .gc_time_ms = 0,
            .uptime_seconds = getUptime(),
        };
    }

    fn getCurrentMemoryUsage() u64 {
        // 简化实现，实际应该使用系统API
        return 1024 * 1024 * 50; // 50MB
    }

    fn getPeakMemoryUsage() u64 {
        return 1024 * 1024 * 100; // 100MB
    }

    fn getCPUUsage() f64 {
        // 简化实现
        return 15.5; // 15.5%
    }

    fn getThreadCount() u32 {
        return @intCast(std.Thread.getCpuCount() catch 4);
    }

    fn getUptime() u64 {
        // 简化实现
        return 3600; // 1小时
    }
};

/// 性能跟踪span
pub const Span = struct {
    name: []const u8,
    start_time: i64,
    end_time: ?i64,
    duration_ns: ?u64,
    tags: std.StringHashMap([]const u8),
    parent_span: ?*Span,
    children: std.ArrayList(*Span),

    pub fn init(allocator: std.mem.Allocator, name: []const u8, parent: ?*Span) !*Span {
        const span = try allocator.create(Span);
        span.* = Span{
            .name = name,
            .start_time = @intCast(std.time.nanoTimestamp()),
            .end_time = null,
            .duration_ns = null,
            .tags = std.StringHashMap([]const u8).init(allocator),
            .parent_span = parent,
            .children = std.ArrayList(*Span).init(allocator),
        };

        if (parent) |p| {
            try p.children.append(span);
        }

        return span;
    }

    pub fn deinit(self: *Span, allocator: std.mem.Allocator) void {
        self.tags.deinit();
        for (self.children.items) |child| {
            child.deinit(allocator);
            allocator.destroy(child);
        }
        self.children.deinit();
    }

    pub fn finish(self: *Span) void {
        if (self.end_time == null) {
            self.end_time = @intCast(std.time.nanoTimestamp());
            self.duration_ns = @intCast(self.end_time.? - self.start_time);
        }
    }

    pub fn addTag(self: *Span, key: []const u8, value: []const u8) !void {
        try self.tags.put(key, value);
    }

    pub fn getDurationMs(self: *const Span) ?f64 {
        if (self.duration_ns) |duration| {
            return @as(f64, @floatFromInt(duration)) / 1_000_000.0;
        }
        return null;
    }
};

/// 性能监控器
pub const PerformanceMonitor = struct {
    allocator: std.mem.Allocator,
    config: PerformanceMonitorConfig,
    metrics: std.StringHashMap(*Metric),
    active_spans: std.ArrayList(*Span),
    completed_spans: std.ArrayList(*Span),
    mutex: std.Thread.Mutex,
    start_time: i64,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: PerformanceMonitorConfig) !*Self {
        const monitor = try allocator.create(Self);
        monitor.* = Self{
            .allocator = allocator,
            .config = config,
            .metrics = std.StringHashMap(*Metric).init(allocator),
            .active_spans = std.ArrayList(*Span).init(allocator),
            .completed_spans = std.ArrayList(*Span).init(allocator),
            .mutex = std.Thread.Mutex{},
            .start_time = std.time.timestamp(),
        };

        // 初始化基础指标
        try monitor.initializeBaseMetrics();

        return monitor;
    }

    pub fn deinit(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // 清理指标
        var metrics_iter = self.metrics.iterator();
        while (metrics_iter.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.metrics.deinit();

        // 清理spans
        for (self.active_spans.items) |span| {
            span.deinit(self.allocator);
            self.allocator.destroy(span);
        }
        self.active_spans.deinit();

        for (self.completed_spans.items) |span| {
            span.deinit(self.allocator);
            self.allocator.destroy(span);
        }
        self.completed_spans.deinit();

        self.allocator.destroy(self);
    }

    fn initializeBaseMetrics(self: *Self) !void {
        // 请求计数器
        const request_counter = try self.allocator.create(Metric);
        request_counter.* = Metric.init(self.allocator, "requests_total", .counter);
        try self.metrics.put("requests_total", request_counter);

        // 响应时间直方图
        const response_time = try self.allocator.create(Metric);
        response_time.* = Metric.init(self.allocator, "response_time_ms", .histogram);
        try self.metrics.put("response_time_ms", response_time);

        // 错误计数器
        const error_counter = try self.allocator.create(Metric);
        error_counter.* = Metric.init(self.allocator, "errors_total", .counter);
        try self.metrics.put("errors_total", error_counter);

        // 活跃连接数
        const active_connections = try self.allocator.create(Metric);
        active_connections.* = Metric.init(self.allocator, "active_connections", .gauge);
        try self.metrics.put("active_connections", active_connections);
    }

    pub fn incrementCounter(self: *Self, name: []const u8, delta: f64) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.metrics.get(name)) |metric| {
            metric.increment(delta);
        } else {
            const new_metric = try self.allocator.create(Metric);
            new_metric.* = Metric.init(self.allocator, name, .counter);
            new_metric.setValue(delta);
            try self.metrics.put(name, new_metric);
        }
    }

    pub fn setGauge(self: *Self, name: []const u8, value: f64) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.metrics.get(name)) |metric| {
            metric.setValue(value);
        } else {
            const new_metric = try self.allocator.create(Metric);
            new_metric.* = Metric.init(self.allocator, name, .gauge);
            new_metric.setValue(value);
            try self.metrics.put(name, new_metric);
        }
    }

    pub fn recordHistogram(self: *Self, name: []const u8, value: f64) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.metrics.get(name)) |metric| {
            // 简化的直方图实现，实际应该维护桶
            metric.setValue(value);
        } else {
            const new_metric = try self.allocator.create(Metric);
            new_metric.* = Metric.init(self.allocator, name, .histogram);
            new_metric.setValue(value);
            try self.metrics.put(name, new_metric);
        }
    }

    pub fn startSpan(self: *Self, name: []const u8, parent: ?*Span) !*Span {
        self.mutex.lock();
        defer self.mutex.unlock();

        const span = try Span.init(self.allocator, name, parent);
        try self.active_spans.append(span);
        return span;
    }

    pub fn finishSpan(self: *Self, span: *Span) !void {
        span.finish();

        // 获取持续时间，避免在锁内调用recordHistogram
        const duration = span.getDurationMs();

        self.mutex.lock();
        defer self.mutex.unlock();

        // 从活跃spans中移除
        for (self.active_spans.items, 0..) |active_span, i| {
            if (active_span == span) {
                _ = self.active_spans.orderedRemove(i);
                break;
            }
        }

        // 添加到完成的spans
        try self.completed_spans.append(span);

        // 记录span持续时间到指标（在锁内直接设置，避免递归锁）
        if (duration) |d| {
            if (self.metrics.get("span_duration_ms")) |metric| {
                metric.setValue(d);
            } else {
                const new_metric = try self.allocator.create(Metric);
                new_metric.* = Metric.init(self.allocator, "span_duration_ms", .histogram);
                new_metric.setValue(d);
                try self.metrics.put("span_duration_ms", new_metric);
            }
        }
    }

    pub fn collectSystemMetrics(self: *Self) !void {
        if (!self.config.enable_system_metrics) return;

        const system_metrics = SystemMetrics.collect();

        try self.setGauge("system_memory_usage_bytes", @floatFromInt(system_metrics.memory_usage_bytes));
        try self.setGauge("system_memory_peak_bytes", @floatFromInt(system_metrics.memory_peak_bytes));
        try self.setGauge("system_cpu_usage_percent", system_metrics.cpu_usage_percent);
        try self.setGauge("system_thread_count", @floatFromInt(system_metrics.thread_count));
        try self.setGauge("system_uptime_seconds", @floatFromInt(system_metrics.uptime_seconds));
    }

    pub fn getMetrics(self: *Self) ![]Metric {
        self.mutex.lock();
        defer self.mutex.unlock();

        var metrics_list = std.ArrayList(Metric).init(self.allocator);
        defer metrics_list.deinit();

        var iter = self.metrics.iterator();
        while (iter.next()) |entry| {
            try metrics_list.append(entry.value_ptr.*.*);
        }

        return metrics_list.toOwnedSlice();
    }

    pub fn getSpanSummary(self: *Self) !SpanSummary {
        self.mutex.lock();
        defer self.mutex.unlock();

        var total_spans: u64 = 0;
        var total_duration_ms: f64 = 0.0;
        var min_duration_ms: f64 = std.math.inf(f64);
        var max_duration_ms: f64 = 0.0;

        for (self.completed_spans.items) |span| {
            if (span.getDurationMs()) |duration| {
                total_spans += 1;
                total_duration_ms += duration;
                min_duration_ms = @min(min_duration_ms, duration);
                max_duration_ms = @max(max_duration_ms, duration);
            }
        }

        const avg_duration_ms = if (total_spans > 0) total_duration_ms / @as(f64, @floatFromInt(total_spans)) else 0.0;

        return SpanSummary{
            .total_spans = total_spans,
            .active_spans = self.active_spans.items.len,
            .avg_duration_ms = avg_duration_ms,
            .min_duration_ms = if (min_duration_ms == std.math.inf(f64)) 0.0 else min_duration_ms,
            .max_duration_ms = max_duration_ms,
        };
    }

    pub fn generateReport(self: *Self) !PerformanceReport {
        const metrics = try self.getMetrics();
        const span_summary = try self.getSpanSummary();
        const system_metrics = SystemMetrics.collect();

        return PerformanceReport{
            .timestamp = std.time.timestamp(),
            .uptime_seconds = std.time.timestamp() - self.start_time,
            .metrics = metrics,
            .span_summary = span_summary,
            .system_metrics = system_metrics,
        };
    }
};

/// Span摘要
pub const SpanSummary = struct {
    total_spans: u64,
    active_spans: usize,
    avg_duration_ms: f64,
    min_duration_ms: f64,
    max_duration_ms: f64,
};

/// 性能报告
pub const PerformanceReport = struct {
    timestamp: i64,
    uptime_seconds: i64,
    metrics: []Metric,
    span_summary: SpanSummary,
    system_metrics: SystemMetrics,

    pub fn deinit(self: *PerformanceReport, allocator: std.mem.Allocator) void {
        allocator.free(self.metrics);
    }

    pub fn printReport(self: *const PerformanceReport) void {
        std.debug.print("\n📊 性能监控报告\n", .{});
        std.debug.print("==================================================\n", .{});
        std.debug.print("时间戳: {}\n", .{self.timestamp});
        std.debug.print("运行时间: {} 秒\n", .{self.uptime_seconds});

        std.debug.print("\n📈 指标统计:\n", .{});
        for (self.metrics) |metric| {
            std.debug.print("  {s}: {d:.2} ({s})\n", .{ metric.name, metric.value, @tagName(metric.metric_type) });
        }

        std.debug.print("\n⏱️ Span统计:\n", .{});
        std.debug.print("  总Span数: {}\n", .{self.span_summary.total_spans});
        std.debug.print("  活跃Span数: {}\n", .{self.span_summary.active_spans});
        std.debug.print("  平均持续时间: {d:.2} ms\n", .{self.span_summary.avg_duration_ms});
        std.debug.print("  最小持续时间: {d:.2} ms\n", .{self.span_summary.min_duration_ms});
        std.debug.print("  最大持续时间: {d:.2} ms\n", .{self.span_summary.max_duration_ms});

        std.debug.print("\n🖥️ 系统指标:\n", .{});
        std.debug.print("  内存使用: {d:.2} MB\n", .{@as(f64, @floatFromInt(self.system_metrics.memory_usage_bytes)) / 1024.0 / 1024.0});
        std.debug.print("  内存峰值: {d:.2} MB\n", .{@as(f64, @floatFromInt(self.system_metrics.memory_peak_bytes)) / 1024.0 / 1024.0});
        std.debug.print("  CPU使用率: {d:.1}%\n", .{self.system_metrics.cpu_usage_percent});
        std.debug.print("  线程数: {}\n", .{self.system_metrics.thread_count});
        std.debug.print("  系统运行时间: {} 秒\n", .{self.system_metrics.uptime_seconds});
    }
};

/// 性能监控中间件
pub const PerformanceMiddleware = struct {
    monitor: *PerformanceMonitor,

    pub fn init(monitor: *PerformanceMonitor) PerformanceMiddleware {
        return PerformanceMiddleware{
            .monitor = monitor,
        };
    }

    pub fn measureFunction(self: *PerformanceMiddleware, comptime name: []const u8, func: anytype, args: anytype) !@TypeOf(@call(.auto, func, args)) {
        const span = try self.monitor.startSpan(name, null);
        defer self.monitor.finishSpan(span) catch {};

        try self.monitor.incrementCounter("function_calls_total", 1.0);

        const result = @call(.auto, func, args);

        return result;
    }

    pub fn recordRequest(self: *PerformanceMiddleware, method: []const u8, path: []const u8, status_code: u16, duration_ms: f64) !void {
        try self.monitor.incrementCounter("requests_total", 1.0);
        try self.monitor.recordHistogram("request_duration_ms", duration_ms);

        if (status_code >= 400) {
            try self.monitor.incrementCounter("errors_total", 1.0);
        }

        // 创建带标签的span
        const span = try self.monitor.startSpan("http_request", null);
        try span.addTag("method", method);
        try span.addTag("path", path);
        try span.addTag("status_code", try std.fmt.allocPrint(self.monitor.allocator, "{}", .{status_code}));
        try self.monitor.finishSpan(span);
    }
};
