const std = @import("std");
const testing = std.testing;

// Import components directly
const DynamicArgument = @import("agent/dynamic_argument.zig").DynamicArgument;
const DynamicString = @import("agent/dynamic_argument.zig").DynamicString;
const RuntimeContext = @import("agent/dynamic_argument.zig").RuntimeContext;
const AgentGenerateOptions = @import("agent/agent_options.zig").AgentGenerateOptions;
const AgentStreamOptions = @import("agent/agent_options.zig").AgentStreamOptions;
const GenerationUsage = @import("agent/agent_options.zig").GenerationUsage;

test "DynamicArgument comprehensive test" {
    const allocator = testing.allocator;
    var ctx = RuntimeContext.init(allocator);
    defer ctx.deinit();

    // Test static value
    const static_arg = DynamicString.static("hello");
    const static_result = try static_arg.resolve(ctx);
    try testing.expectEqualStrings("hello", static_result);
    try testing.expect(static_arg.isStatic());

    // Test dynamic function
    const dynamic_func = struct {
        fn resolve(_: RuntimeContext) []const u8 {
            return "dynamic";
        }
    }.resolve;
    const dynamic_arg = DynamicString.dynamic(dynamic_func);
    const dynamic_result = try dynamic_arg.resolve(ctx);
    try testing.expectEqualStrings("dynamic", dynamic_result);
    try testing.expect(dynamic_arg.isDynamic());

    // Test async dynamic function
    const async_func = struct {
        fn resolve(_: RuntimeContext) anyerror![]const u8 {
            return "async_dynamic";
        }
    }.resolve;
    const async_arg = DynamicString.asyncDynamic(async_func);
    const async_result = try async_arg.resolve(ctx);
    try testing.expectEqualStrings("async_dynamic", async_result);
}

test "RuntimeContext variable and metadata management" {
    const allocator = testing.allocator;
    var ctx = RuntimeContext.init(allocator);
    defer ctx.deinit();

    // Test variable management
    try ctx.setVariable("name", std.json.Value{ .string = "Alice" });
    try ctx.setVariable("age", std.json.Value{ .integer = 25 });
    try ctx.setVariable("active", std.json.Value{ .bool = true });

    const name = ctx.getVariable("name");
    try testing.expect(name != null);
    try testing.expectEqualStrings("Alice", name.?.string);

    const age = ctx.getVariable("age");
    try testing.expect(age != null);
    try testing.expectEqual(@as(i64, 25), age.?.integer);

    const active = ctx.getVariable("active");
    try testing.expect(active != null);
    try testing.expectEqual(true, active.?.bool);

    // Test metadata management
    try ctx.setMetadata("session_id", std.json.Value{ .string = "sess_123" });
    const session_id = ctx.getMetadata("session_id");
    try testing.expect(session_id != null);
    try testing.expectEqualStrings("sess_123", session_id.?.string);

    // Test non-existent keys
    try testing.expect(ctx.getVariable("nonexistent") == null);
    try testing.expect(ctx.getMetadata("nonexistent") == null);
}

test "AgentGenerateOptions creation and manipulation" {
    // Test default options
    const default_opts = AgentGenerateOptions.default();
    try testing.expect(default_opts.max_tokens == null);
    try testing.expect(default_opts.temperature == null);
    try testing.expect(default_opts.include_usage == true);
    try testing.expect(default_opts.enable_tools == true);

    // Test creative options
    const creative_opts = AgentGenerateOptions.creative();
    try testing.expectEqual(@as(?f32, 0.8), creative_opts.temperature);
    try testing.expectEqual(@as(?f32, 0.9), creative_opts.top_p);
    try testing.expectEqual(@as(?f32, 0.1), creative_opts.frequency_penalty);

    // Test factual options
    const factual_opts = AgentGenerateOptions.factual();
    try testing.expectEqual(@as(?f32, 0.2), factual_opts.temperature);
    try testing.expectEqual(@as(?f32, 0.8), factual_opts.top_p);
    try testing.expectEqual(@as(?f32, 0.0), factual_opts.frequency_penalty);

    // Test code options
    const code_opts = AgentGenerateOptions.code();
    try testing.expectEqual(@as(?f32, 0.1), code_opts.temperature);
    try testing.expectEqual(@as(?f32, 0.95), code_opts.top_p);
    try testing.expect(code_opts.enable_tools == true);

    // Test merging options
    const base_opts = AgentGenerateOptions{ .temperature = 0.5 };
    const override_opts = AgentGenerateOptions{ .max_tokens = 1000, .top_p = 0.9 };
    const merged = base_opts.merge(override_opts);
    
    try testing.expectEqual(@as(?f32, 0.5), merged.temperature); // From base
    try testing.expectEqual(@as(?u32, 1000), merged.max_tokens); // From override
    try testing.expectEqual(@as(?f32, 0.9), merged.top_p); // From override
}

test "AgentStreamOptions creation and configuration" {
    // Test default streaming options
    const default_stream = AgentStreamOptions.default();
    try testing.expect(default_stream.stream == true);
    try testing.expect(default_stream.chunk_size == null);
    try testing.expect(default_stream.include_deltas == true);

    // Test realtime streaming options
    const realtime_stream = AgentStreamOptions.realtime();
    try testing.expectEqual(@as(?u32, 10), realtime_stream.chunk_size);
    try testing.expectEqual(@as(usize, 1024), realtime_stream.buffer_size);
    try testing.expectEqual(@as(?f32, 0.7), realtime_stream.base.temperature);

    // Test long-form streaming options
    const longform_stream = AgentStreamOptions.longForm();
    try testing.expectEqual(@as(?u32, 50), longform_stream.chunk_size);
    try testing.expectEqual(@as(usize, 8192), longform_stream.buffer_size);
    try testing.expect(longform_stream.include_deltas == false);

    // Test with custom base options
    const custom_base = AgentGenerateOptions{ .temperature = 0.3, .max_tokens = 500 };
    const custom_stream = AgentStreamOptions.withBase(custom_base);
    try testing.expectEqual(@as(?f32, 0.3), custom_stream.base.temperature);
    try testing.expectEqual(@as(?u32, 500), custom_stream.base.max_tokens);
}

test "GenerationUsage calculation" {
    const usage = GenerationUsage.init(100, 50);
    
    try testing.expectEqual(@as(u32, 100), usage.prompt_tokens);
    try testing.expectEqual(@as(u32, 50), usage.completion_tokens);
    try testing.expectEqual(@as(u32, 150), usage.total_tokens);

    // Test with zero values
    const zero_usage = GenerationUsage.init(0, 0);
    try testing.expectEqual(@as(u32, 0), zero_usage.total_tokens);

    // Test with large values
    const large_usage = GenerationUsage.init(10000, 5000);
    try testing.expectEqual(@as(u32, 15000), large_usage.total_tokens);
}

test "DynamicArgument type conversions" {
    const allocator = testing.allocator;
    var ctx = RuntimeContext.init(allocator);
    defer ctx.deinit();

    // Test integer dynamic argument
    const DynamicInt = DynamicArgument(i64);
    const int_arg = DynamicInt.static(42);
    const int_result = try int_arg.resolve(ctx);
    try testing.expectEqual(@as(i64, 42), int_result);

    // Test float dynamic argument
    const DynamicFloat = DynamicArgument(f64);
    const float_arg = DynamicFloat.static(3.14);
    const float_result = try float_arg.resolve(ctx);
    try testing.expectEqual(@as(f64, 3.14), float_result);

    // Test boolean dynamic argument
    const DynamicBool = DynamicArgument(bool);
    const bool_arg = DynamicBool.static(true);
    const bool_result = try bool_arg.resolve(ctx);
    try testing.expectEqual(true, bool_result);
}

test "Complex dynamic argument scenarios" {
    const allocator = testing.allocator;
    var ctx = RuntimeContext.init(allocator);
    defer ctx.deinit();

    // Set up context variables
    try ctx.setVariable("user_name", std.json.Value{ .string = "Alice" });
    try ctx.setVariable("user_level", std.json.Value{ .integer = 5 });
    try ctx.setVariable("is_premium", std.json.Value{ .bool = true });

    // Test dynamic string that depends on context
    const context_dependent_func = struct {
        fn resolve(context: RuntimeContext) []const u8 {
            const name = context.getVariable("user_name");
            const level = context.getVariable("user_level");
            const premium = context.getVariable("is_premium");
            
            if (name != null and level != null and premium != null) {
                if (premium.?.bool) {
                    return "You are a premium AI assistant for Alice.";
                } else {
                    return "You are an AI assistant for Alice.";
                }
            }
            return "You are an AI assistant.";
        }
    }.resolve;

    const dynamic_instructions = DynamicString.dynamic(context_dependent_func);
    const result = try dynamic_instructions.resolve(ctx);
    try testing.expectEqualStrings("You are a premium AI assistant for Alice.", result);

    // Test with modified context
    try ctx.setVariable("is_premium", std.json.Value{ .bool = false });
    const result2 = try dynamic_instructions.resolve(ctx);
    try testing.expectEqualStrings("You are an AI assistant for Alice.", result2);
}

test "Error handling in dynamic arguments" {
    const allocator = testing.allocator;
    var ctx = RuntimeContext.init(allocator);
    defer ctx.deinit();

    // Test async function that can fail
    const failing_func = struct {
        fn resolve(_: RuntimeContext) anyerror![]const u8 {
            return error.TestError;
        }
    }.resolve;

    const failing_arg = DynamicString.asyncDynamic(failing_func);
    const result = failing_arg.resolve(ctx);
    try testing.expectError(error.TestError, result);
}
