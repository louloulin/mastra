const std = @import("std");
const mastra = @import("mastra");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("❌ 检测到内存泄漏！\n", .{});
        } else {
            std.debug.print("✅ 无内存泄漏！\n", .{});
        }
    }
    const allocator = gpa.allocator();

    std.debug.print("📊 简化性能监控系统测试\n", .{});
    std.debug.print("==================================================\n", .{});

    // 测试基本性能监控
    try testBasicPerformanceMonitoring(allocator);

    std.debug.print("\n🎉 简化性能监控系统测试完成！\n", .{});
    std.debug.print("==================================================\n", .{});
}

fn testBasicPerformanceMonitoring(allocator: std.mem.Allocator) !void {
    std.debug.print("\n1. 📈 基本性能监控测试\n", .{});
    std.debug.print("----------------------------------------\n", .{});

    const config = mastra.performance_monitor.PerformanceMonitorConfig{
        .enable_metrics = true,
        .enable_tracing = true,
        .metrics_buffer_size = 1000,
        .flush_interval_seconds = 60,
        .enable_system_metrics = true,
    };

    var monitor = try mastra.performance_monitor.PerformanceMonitor.init(allocator, config);
    defer monitor.deinit();

    std.debug.print("   ✅ 性能监控器初始化成功\n", .{});

    // 测试计数器
    try monitor.incrementCounter("test_counter", 1.0);
    try monitor.incrementCounter("test_counter", 2.0);
    try monitor.incrementCounter("api_requests", 5.0);

    std.debug.print("   ✅ 计数器指标记录成功\n", .{});

    // 测试仪表盘
    try monitor.setGauge("memory_usage", 1024.0 * 1024.0 * 50.0); // 50MB
    try monitor.setGauge("cpu_usage", 25.5); // 25.5%
    try monitor.setGauge("active_connections", 42.0);

    std.debug.print("   ✅ 仪表盘指标记录成功\n", .{});

    // 测试直方图
    try monitor.recordHistogram("response_time", 150.5);
    try monitor.recordHistogram("response_time", 200.3);
    try monitor.recordHistogram("response_time", 89.7);

    std.debug.print("   ✅ 直方图指标记录成功\n", .{});

    // 收集系统指标
    try monitor.collectSystemMetrics();
    std.debug.print("   ✅ 系统指标收集成功\n", .{});

    // 获取所有指标
    const metrics = try monitor.getMetrics();
    defer allocator.free(metrics);

    std.debug.print("   📊 当前指标数量: {}\n", .{metrics.len});
    for (metrics) |metric| {
        std.debug.print("      {s}: {d:.2} ({s})\n", .{ metric.name, metric.value, @tagName(metric.metric_type) });
    }

    // 测试Span跟踪
    const root_span = try monitor.startSpan("test_operation", null);
    std.time.sleep(10 * std.time.ns_per_ms); // 10ms
    try monitor.finishSpan(root_span);

    std.debug.print("   ✅ Span跟踪测试成功\n", .{});

    // 获取span摘要
    const span_summary = try monitor.getSpanSummary();
    std.debug.print("   📊 Span统计:\n", .{});
    std.debug.print("      总span数: {}\n", .{span_summary.total_spans});
    std.debug.print("      活跃span数: {}\n", .{span_summary.active_spans});
    std.debug.print("      平均持续时间: {d:.2} ms\n", .{span_summary.avg_duration_ms});

    // 生成性能报告
    var report = try monitor.generateReport();
    defer report.deinit(allocator);

    std.debug.print("   ✅ 性能报告生成成功\n", .{});
    std.debug.print("   📋 报告摘要:\n", .{});
    std.debug.print("      运行时间: {} 秒\n", .{report.uptime_seconds});
    std.debug.print("      指标数量: {}\n", .{report.metrics.len});
    std.debug.print("      内存使用: {d:.2} MB\n", .{@as(f64, @floatFromInt(report.system_metrics.memory_usage_bytes)) / 1024.0 / 1024.0});
    std.debug.print("      CPU使用率: {d:.1}%\n", .{report.system_metrics.cpu_usage_percent});

    std.debug.print("   🎯 基本性能监控测试完成\n", .{});
}
