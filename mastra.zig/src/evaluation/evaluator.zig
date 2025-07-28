const std = @import("std");

/// Evaluation metric types
pub const MetricType = enum {
    accuracy,
    precision,
    recall,
    f1_score,
    bleu_score,
    rouge_score,
    latency,
    throughput,
    memory_usage,
    custom,
};

/// Evaluation result
pub const EvaluationResult = struct {
    metric_type: MetricType,
    name: []const u8,
    value: f64,
    timestamp: i64,
    metadata: ?std.json.Value = null,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, metric_type: MetricType, name: []const u8, value: f64) !Self {
        return Self{
            .metric_type = metric_type,
            .name = try allocator.dupe(u8, name),
            .value = value,
            .timestamp = std.time.timestamp(),
            .metadata = null,
        };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
    }
};

/// Test case for evaluation
pub const TestCase = struct {
    id: []const u8,
    input: std.json.Value,
    expected_output: ?std.json.Value = null,
    metadata: std.json.Value,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, input: std.json.Value) !Self {
        const id = try std.fmt.allocPrint(allocator, "test_{d}_{d}", .{ std.time.timestamp(), std.crypto.random.int(u32) });

        return Self{
            .id = id,
            .input = input,
            .expected_output = null,
            .metadata = std.json.Value{ .object = std.json.ObjectMap.init(allocator) },
        };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
    }
};

/// Evaluation configuration
pub const EvaluationConfig = struct {
    metrics: []MetricType = &[_]MetricType{ .accuracy, .latency },
    sample_size: usize = 100,
    timeout_ms: u32 = 30000,
    parallel_execution: bool = true,
    save_results: bool = true,
    result_path: []const u8 = "evaluation_results.json",
};

/// Function to be evaluated
pub const EvaluationTarget = *const fn (allocator: std.mem.Allocator, input: std.json.Value) anyerror!std.json.Value;

/// Evaluation session
pub const EvaluationSession = struct {
    allocator: std.mem.Allocator,
    config: EvaluationConfig,
    test_cases: std.ArrayList(TestCase),
    results: std.ArrayList(EvaluationResult),
    session_id: []const u8,
    start_time: i64,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: EvaluationConfig) !Self {
        const session_id = try std.fmt.allocPrint(allocator, "eval_session_{d}", .{std.time.timestamp()});

        return Self{
            .allocator = allocator,
            .config = config,
            .test_cases = std.ArrayList(TestCase).init(allocator),
            .results = std.ArrayList(EvaluationResult).init(allocator),
            .session_id = session_id,
            .start_time = std.time.timestamp(),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.test_cases.items) |*test_case| {
            test_case.deinit(self.allocator);
        }
        self.test_cases.deinit();

        for (self.results.items) |*result| {
            result.deinit(self.allocator);
        }
        self.results.deinit();

        self.allocator.free(self.session_id);
    }

    pub fn addTestCase(self: *Self, test_case: TestCase) !void {
        try self.test_cases.append(test_case);
    }

    pub fn evaluate(self: *Self, target: EvaluationTarget) !EvaluationSummary {
        std.log.info("Starting evaluation session: {s}", .{self.session_id});

        var correct_predictions: usize = 0;
        var total_latency: f64 = 0.0;

        const sample_size = @min(self.config.sample_size, self.test_cases.items.len);

        for (self.test_cases.items[0..sample_size]) |test_case| {
            const start_time = std.time.nanoTimestamp();

            // Execute target function
            const result = target(self.allocator, test_case.input) catch |err| {
                std.log.err("Evaluation failed for test case {s}: {}", .{ test_case.id, err });
                continue;
            };

            const end_time = std.time.nanoTimestamp();
            const latency_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;
            total_latency += latency_ms;

            // Check accuracy if expected output is provided
            if (test_case.expected_output) |expected| {
                if (self.compareResults(result, expected)) {
                    correct_predictions += 1;
                }
            }

            // Record latency
            const latency_result = try EvaluationResult.init(self.allocator, .latency, "response_time", latency_ms);
            try self.results.append(latency_result);
        }

        // Calculate metrics
        const accuracy = if (sample_size > 0) @as(f64, @floatFromInt(correct_predictions)) / @as(f64, @floatFromInt(sample_size)) else 0.0;
        const avg_latency = if (sample_size > 0) total_latency / @as(f64, @floatFromInt(sample_size)) else 0.0;

        // Record aggregate metrics
        const accuracy_result = try EvaluationResult.init(self.allocator, .accuracy, "overall_accuracy", accuracy);
        try self.results.append(accuracy_result);

        const avg_latency_result = try EvaluationResult.init(self.allocator, .latency, "average_latency", avg_latency);
        try self.results.append(avg_latency_result);

        // Save results if configured
        if (self.config.save_results) {
            try self.saveResults();
        }

        std.log.info("Evaluation completed: {d} test cases, {d:.2}% accuracy, {d:.2}ms avg latency", .{ sample_size, accuracy * 100.0, avg_latency });

        return EvaluationSummary{
            .session_id = try self.allocator.dupe(u8, self.session_id),
            .test_cases_count = sample_size,
            .accuracy = accuracy,
            .average_latency_ms = avg_latency,
            .total_results = self.results.items.len,
            .duration_seconds = std.time.timestamp() - self.start_time,
        };
    }

    pub fn evaluateRAG(self: *Self, rag_system: anytype, queries: [][]const u8) !RAGEvaluationResult {
        var relevance_scores = std.ArrayList(f64).init(self.allocator);
        defer relevance_scores.deinit();

        var response_times = std.ArrayList(f64).init(self.allocator);
        defer response_times.deinit();

        for (queries) |query| {
            const start_time = std.time.nanoTimestamp();

            const context = rag_system.query(query) catch |err| {
                std.log.err("RAG query failed: {}", .{err});
                continue;
            };
            defer context.deinit(self.allocator);

            const end_time = std.time.nanoTimestamp();
            const latency_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;
            try response_times.append(latency_ms);

            // Calculate relevance score (simplified)
            const relevance = self.calculateRelevanceScore(query, context.context_text);
            try relevance_scores.append(relevance);
        }

        // Calculate averages
        const avg_relevance = if (relevance_scores.items.len > 0)
            self.calculateAverage(relevance_scores.items)
        else
            0.0;
        const avg_latency = if (response_times.items.len > 0)
            self.calculateAverage(response_times.items)
        else
            0.0;

        return RAGEvaluationResult{
            .queries_evaluated = queries.len,
            .average_relevance_score = avg_relevance,
            .average_response_time_ms = avg_latency,
            .success_rate = @as(f64, @floatFromInt(relevance_scores.items.len)) / @as(f64, @floatFromInt(queries.len)),
        };
    }

    fn compareResults(self: *Self, actual: std.json.Value, expected: std.json.Value) bool {
        _ = self;

        // Simple comparison (in production, would be more sophisticated)
        switch (actual) {
            .string => |actual_str| {
                switch (expected) {
                    .string => |expected_str| return std.mem.eql(u8, actual_str, expected_str),
                    else => return false,
                }
            },
            .integer => |actual_int| {
                switch (expected) {
                    .integer => |expected_int| return actual_int == expected_int,
                    else => return false,
                }
            },
            .float => |actual_float| {
                switch (expected) {
                    .float => |expected_float| return @abs(actual_float - expected_float) < 0.001,
                    else => return false,
                }
            },
            else => return false,
        }
    }

    fn calculateRelevanceScore(self: *Self, query: []const u8, context: []const u8) f64 {
        _ = self;

        // Simple keyword overlap score (in production, would use semantic similarity)
        var query_words = std.mem.tokenize(u8, query, " \t\n\r");
        var overlap_count: usize = 0;
        var total_words: usize = 0;

        while (query_words.next()) |word| {
            total_words += 1;
            if (std.mem.indexOf(u8, context, word) != null) {
                overlap_count += 1;
            }
        }

        return if (total_words > 0) @as(f64, @floatFromInt(overlap_count)) / @as(f64, @floatFromInt(total_words)) else 0.0;
    }

    fn calculateAverage(self: *Self, values: []f64) f64 {
        _ = self;

        if (values.len == 0) return 0.0;

        var sum: f64 = 0.0;
        for (values) |value| {
            sum += value;
        }

        return sum / @as(f64, @floatFromInt(values.len));
    }

    fn saveResults(self: *Self) !void {
        // Save evaluation results to file (simplified implementation)
        var file = std.fs.cwd().createFile(self.config.result_path, .{}) catch |err| {
            std.log.err("Failed to create results file: {}", .{err});
            return;
        };
        defer file.close();

        var writer = file.writer();
        try writer.print("{{\"session_id\":\"{s}\",\"results\":[", .{self.session_id});

        for (self.results.items, 0..) |result, i| {
            if (i > 0) try writer.print(",");
            try writer.print("{{\"name\":\"{s}\",\"value\":{d},\"timestamp\":{d}}}", .{ result.name, result.value, result.timestamp });
        }

        try writer.print("]}}\n");

        std.log.info("Evaluation results saved to: {s}", .{self.config.result_path});
    }

    pub fn getResults(self: *Self) []EvaluationResult {
        return self.results.items;
    }

    pub fn generateReport(self: *Self) !EvaluationReport {
        var metrics_summary = std.StringHashMap(f64).init(self.allocator);
        defer metrics_summary.deinit();

        // Aggregate metrics by type
        for (self.results.items) |result| {
            const existing = metrics_summary.get(result.name) orelse 0.0;
            try metrics_summary.put(result.name, existing + result.value);
        }

        return EvaluationReport{
            .session_id = try self.allocator.dupe(u8, self.session_id),
            .total_test_cases = self.test_cases.items.len,
            .total_results = self.results.items.len,
            .duration_seconds = std.time.timestamp() - self.start_time,
            .summary = "Evaluation completed successfully",
        };
    }
};

/// Evaluation summary
pub const EvaluationSummary = struct {
    session_id: []const u8,
    test_cases_count: usize,
    accuracy: f64,
    average_latency_ms: f64,
    total_results: usize,
    duration_seconds: i64,

    pub fn deinit(self: *EvaluationSummary, allocator: std.mem.Allocator) void {
        allocator.free(self.session_id);
    }
};

/// RAG evaluation result
pub const RAGEvaluationResult = struct {
    queries_evaluated: usize,
    average_relevance_score: f64,
    average_response_time_ms: f64,
    success_rate: f64,
};

/// Evaluation report
pub const EvaluationReport = struct {
    session_id: []const u8,
    total_test_cases: usize,
    total_results: usize,
    duration_seconds: i64,
    summary: []const u8,

    pub fn deinit(self: *EvaluationReport, allocator: std.mem.Allocator) void {
        allocator.free(self.session_id);
    }
};
