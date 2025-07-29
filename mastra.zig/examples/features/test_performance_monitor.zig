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

    std.debug.print("📊 性能监控系统测试\n", .{});
    std.debug.print("==================================================\n", .{});

    // 测试基本性能监控
    try testBasicPerformanceMonitoring(allocator);

    // 测试Span跟踪
    try testSpanTracing(allocator);

    // 测试性能中间件
    try testPerformanceMiddleware(allocator);

    // 测试性能报告
    try testPerformanceReport(allocator);

    std.debug.print("\n🎉 性能监控系统测试完成！\n", .{});
    std.debug.print("==================================================\n", .{});
}

fn testBasicPerformanceMonitoring(allocator: std.mem.Allocator) !void {
    std.debug.print("\n1. 📈 基本性能监控测试\n", .{});
    std.debug.print("----------------------------------------\n", .{});

    const config = mastra.telemetry.PerformanceMonitorConfig{
        .enable_metrics = true,
        .enable_tracing = true,
        .metrics_buffer_size = 1000,
        .flush_interval_seconds = 60,
        .enable_system_metrics = true,
    };

    var monitor = try mastra.telemetry.PerformanceMonitor.init(allocator, config);
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

    std.debug.print("   🎯 基本性能监控测试完成\n", .{});
}

fn testSpanTracing(allocator: std.mem.Allocator) !void {
    std.debug.print("\n2. ⏱️ Span跟踪测试\n", .{});
    std.debug.print("----------------------------------------\n", .{});

    const config = mastra.telemetry.PerformanceMonitorConfig{};
    var monitor = try mastra.telemetry.PerformanceMonitor.init(allocator, config);
    defer monitor.deinit();

    // 创建根span
    const root_span = try monitor.startSpan("http_request", null);
    try root_span.addTag("method", "GET");
    try root_span.addTag("path", "/api/users");

    std.debug.print("   ✅ 创建根span: http_request\n", .{});

    // 模拟一些工作
    std.time.sleep(10 * std.time.ns_per_ms); // 10ms

    // 创建子span
    const db_span = try monitor.startSpan("database_query", root_span);
    try db_span.addTag("query", "SELECT * FROM users");
    try db_span.addTag("table", "users");

    std.debug.print("   ✅ 创建子span: database_query\n", .{});

    // 模拟数据库查询
    std.time.sleep(50 * std.time.ns_per_ms); // 50ms

    try monitor.finishSpan(db_span);
    std.debug.print("   ✅ 完成数据库查询span\n", .{});

    // 创建另一个子span
    const cache_span = try monitor.startSpan("cache_lookup", root_span);
    try cache_span.addTag("key", "user:123");

    // 模拟缓存查找
    std.time.sleep(5 * std.time.ns_per_ms); // 5ms

    try monitor.finishSpan(cache_span);
    std.debug.print("   ✅ 完成缓存查找span\n", .{});

    try monitor.finishSpan(root_span);
    std.debug.print("   ✅ 完成根span\n", .{});

    // 获取span摘要
    const span_summary = try monitor.getSpanSummary();
    std.debug.print("   📊 Span统计:\n", .{});
    std.debug.print("      总span数: {}\n", .{span_summary.total_spans});
    std.debug.print("      活跃span数: {}\n", .{span_summary.active_spans});
    std.debug.print("      平均持续时间: {d:.2} ms\n", .{span_summary.avg_duration_ms});
    std.debug.print("      最小持续时间: {d:.2} ms\n", .{span_summary.min_duration_ms});
    std.debug.print("      最大持续时间: {d:.2} ms\n", .{span_summary.max_duration_ms});

    std.debug.print("   🎯 Span跟踪测试完成\n", .{});
}

fn testPerformanceMiddleware(allocator: std.mem.Allocator) !void {
    std.debug.print("\n3. 🔧 性能中间件测试\n", .{});
    std.debug.print("----------------------------------------\n", .{});

    const config = mastra.telemetry.PerformanceMonitorConfig{};
    var monitor = try mastra.telemetry.PerformanceMonitor.init(allocator, config);
    defer monitor.deinit();

    var middleware = mastra.telemetry.PerformanceMiddleware.init(monitor);

    // 测试函数性能测量
    const result = try middleware.measureFunction("test_function", testFunction, .{42});
    std.debug.print("   ✅ 函数性能测量: 结果 = {}\n", .{result});

    // 测试HTTP请求记录
    try middleware.recordRequest("GET", "/api/users", 200, 150.5);
    try middleware.recordRequest("POST", "/api/users", 201, 200.3);
    try middleware.recordRequest("GET", "/api/users/123", 404, 50.1);
    try middleware.recordRequest("DELETE", "/api/users/123", 500, 300.7);

    std.debug.print("   ✅ HTTP请求记录完成\n", .{});

    // 获取指标验证
    const metrics = try monitor.getMetrics();
    defer allocator.free(metrics);

    var requests_total: f64 = 0;
    var errors_total: f64 = 0;
    var function_calls: f64 = 0;

    for (metrics) |metric| {
        if (std.mem.eql(u8, metric.name, "requests_total")) {
            requests_total = metric.value;
        } else if (std.mem.eql(u8, metric.name, "errors_total")) {
            errors_total = metric.value;
        } else if (std.mem.eql(u8, metric.name, "function_calls_total")) {
            function_calls = metric.value;
        }
    }

    std.debug.print("   📊 中间件统计:\n", .{});
    std.debug.print("      总请求数: {d:.0}\n", .{requests_total});
    std.debug.print("      错误数: {d:.0}\n", .{errors_total});
    std.debug.print("      函数调用数: {d:.0}\n", .{function_calls});

    std.debug.print("   🎯 性能中间件测试完成\n", .{});
}

fn testPerformanceReport(allocator: std.mem.Allocator) !void {
    std.debug.print("\n4. 📋 性能报告测试\n", .{});
    std.debug.print("----------------------------------------\n", .{});

    const config = mastra.telemetry.PerformanceMonitorConfig{
        .enable_system_metrics = true,
    };
    var monitor = try mastra.telemetry.PerformanceMonitor.init(allocator, config);
    defer monitor.deinit();

    // 生成一些测试数据
    try monitor.incrementCounter("total_requests", 1000.0);
    try monitor.incrementCounter("successful_requests", 950.0);
    try monitor.incrementCounter("failed_requests", 50.0);

    try monitor.setGauge("active_users", 123.0);
    try monitor.setGauge("queue_size", 45.0);

    try monitor.recordHistogram("api_latency", 120.5);
    try monitor.recordHistogram("api_latency", 89.3);
    try monitor.recordHistogram("api_latency", 200.1);

    // 创建一些spans
    const span1 = try monitor.startSpan("operation_1", null);
    std.time.sleep(20 * std.time.ns_per_ms);
    try monitor.finishSpan(span1);

    const span2 = try monitor.startSpan("operation_2", null);
    std.time.sleep(30 * std.time.ns_per_ms);
    try monitor.finishSpan(span2);

    // 收集系统指标
    try monitor.collectSystemMetrics();

    // 生成性能报告
    var report = try monitor.generateReport();
    defer report.deinit(allocator);

    std.debug.print("   ✅ 性能报告生成成功\n", .{});

    // 打印报告
    report.printReport();

    std.debug.print("   🎯 性能报告测试完成\n", .{});
}

// 测试函数
fn testFunction(value: i32) i32 {
    // 模拟一些计算工作
    var result: i32 = value;
    var i: i32 = 0;
    while (i < 1000) : (i += 1) {
        result = result * 2 / 2 + 1 - 1;
    }
    return result;
}
