const std = @import("std");
const testing = std.testing;

// Import from the main module to avoid path issues
const mastra = @import("../src/mastra.zig");

const DynamicArgument = mastra.DynamicArgument;
const DynamicString = mastra.DynamicString;
const RuntimeContext = mastra.RuntimeContext;
const MessageList = mastra.MessageList;
const MessageListConfig = mastra.MessageListConfig;
const MessageImportance = mastra.MessageImportance;
const SaveQueueManager = mastra.SaveQueueManager;
const SaveQueueConfig = mastra.SaveQueueConfig;
const AgentGenerateOptions = mastra.AgentGenerateOptions;
const AgentStreamOptions = mastra.AgentStreamOptions;
const Agent = mastra.Agent;
const AgentConfig = mastra.AgentConfig;
const Storage = mastra.Storage;
const StorageConfig = mastra.StorageConfig;
const LLM = mastra.LLM;
const LLMConfig = mastra.LLMConfig;
const Logger = mastra.Logger;

test "DynamicArgument static value" {
    const allocator = testing.allocator;
    var ctx = RuntimeContext.init(allocator);
    defer ctx.deinit();

    const arg = DynamicString.static("hello");
    const result = try arg.resolve(ctx);
    try testing.expectEqualStrings("hello", result);
    try testing.expect(arg.isStatic());
    try testing.expect(!arg.isDynamic());
}

test "DynamicArgument dynamic function" {
    const allocator = testing.allocator;
    var ctx = RuntimeContext.init(allocator);
    defer ctx.deinit();

    const func = struct {
        fn resolve(_: RuntimeContext) []const u8 {
            return "dynamic";
        }
    }.resolve;

    const arg = DynamicString.dynamic(func);
    const result = try arg.resolve(ctx);
    try testing.expectEqualStrings("dynamic", result);
    try testing.expect(!arg.isStatic());
    try testing.expect(arg.isDynamic());
}

test "DynamicArgument async dynamic function" {
    const allocator = testing.allocator;
    var ctx = RuntimeContext.init(allocator);
    defer ctx.deinit();

    const func = struct {
        fn resolve(_: RuntimeContext) anyerror![]const u8 {
            return "async_dynamic";
        }
    }.resolve;

    const arg = DynamicString.asyncDynamic(func);
    const result = try arg.resolve(ctx);
    try testing.expectEqualStrings("async_dynamic", result);
}

test "RuntimeContext variable management" {
    const allocator = testing.allocator;
    var ctx = RuntimeContext.init(allocator);
    defer ctx.deinit();

    try ctx.setVariable("test_var", std.json.Value{ .string = "test_value" });
    
    const value = ctx.getVariable("test_var");
    try testing.expect(value != null);
    try testing.expectEqualStrings("test_value", value.?.string);
}

test "MessageList basic operations" {
    const allocator = testing.allocator;
    const config = MessageListConfig{};
    
    var list = try MessageList.init(allocator, config, null);
    defer list.deinit();

    try list.addMessage("user", "Hello", .normal);
    try list.addMessage("assistant", "Hi there!", .normal);

    try testing.expectEqual(@as(usize, 2), list.getMessageCount());
    try testing.expect(list.getTotalTokens() > 0);
}

test "MessageList smart trimming" {
    const allocator = testing.allocator;
    const config = MessageListConfig{ .max_context_length = 10 }; // Very small limit
    
    var list = try MessageList.init(allocator, config, null);
    defer list.deinit();

    try list.addMessage("system", "You are helpful", .system);
    try list.addMessage("user", "Long message that should be trimmed", .normal);
    try list.addMessage("assistant", "Short", .normal);

    const context = try list.getContext(null);
    defer allocator.free(context);

    // Should preserve system message and recent messages
    try testing.expect(context.len >= 1);
}

test "AgentGenerateOptions creation and merging" {
    const options1 = AgentGenerateOptions.creative();
    const options2 = AgentGenerateOptions{ .max_tokens = 1000 };
    
    const merged = options1.merge(options2);
    
    try testing.expectEqual(@as(?u32, 1000), merged.max_tokens);
    try testing.expectEqual(@as(?f32, 0.8), merged.temperature);
}

test "AgentStreamOptions creation" {
    const stream_opts = AgentStreamOptions.realtime();
    
    try testing.expectEqual(true, stream_opts.stream);
    try testing.expectEqual(@as(?u32, 10), stream_opts.chunk_size);
    try testing.expectEqual(@as(?f32, 0.7), stream_opts.base.temperature);
}

test "SaveQueueManager basic operations" {
    const allocator = testing.allocator;
    
    // Create a mock storage
    const storage_config = StorageConfig{
        .type = .memory,
    };
    var storage = try Storage.init(allocator, storage_config);
    defer storage.deinit();

    const config = SaveQueueConfig{ .worker_count = 1 };
    var manager = try SaveQueueManager.init(allocator, config, storage);
    defer manager.deinit();

    // Queue some operations
    var data = std.json.ObjectMap.init(allocator);
    defer data.deinit();
    try data.put("test", std.json.Value{ .string = "value" });

    try manager.queueSave(.message, "test_table", std.json.Value{ .object = data }, 1);
    
    // Wait for processing
    std.time.sleep(100 * std.time.ns_per_ms);
    
    const stats = manager.getStats();
    try testing.expect(stats.total_operations.load(.acquire) > 0);
}

test "Enhanced Agent initialization" {
    const allocator = testing.allocator;
    
    // Create storage
    const storage_config = StorageConfig{ .type = .memory };
    var storage = try Storage.init(allocator, storage_config);
    defer storage.deinit();
    
    // Create LLM
    const llm_config = LLMConfig{
        .provider = .deepseek,
        .model = "deepseek-chat",
        .api_key = "test-key",
        .base_url = "https://api.deepseek.com",
    };
    var llm = try LLM.init(allocator, llm_config);
    defer llm.deinit();
    
    // Create enhanced agent config
    const agent_config = AgentConfig{
        .name = "test-agent",
        .model = llm,
        .instructions = DynamicString.static("You are a test assistant."),
        .storage = storage,
        .thread_id = "test-thread",
        .default_generate_options = AgentGenerateOptions.factual(),
    };
    
    var agent = try Agent.init(allocator, agent_config);
    defer agent.deinit();
    
    try testing.expectEqualStrings("test-agent", agent.name);
    
    // Test context variable management
    try agent.setContextVariable("user_name", std.json.Value{ .string = "Alice" });
    const user_name = agent.getContextVariable("user_name");
    try testing.expect(user_name != null);
    try testing.expectEqualStrings("Alice", user_name.?.string);
    
    // Test message stats
    const stats = agent.getMessageStats();
    try testing.expectEqual(@as(usize, 0), stats.count); // No messages yet
}

test "Agent dynamic instructions resolution" {
    const allocator = testing.allocator;
    
    // Create storage
    const storage_config = StorageConfig{ .type = .memory };
    var storage = try Storage.init(allocator, storage_config);
    defer storage.deinit();
    
    // Create LLM
    const llm_config = LLMConfig{
        .provider = .deepseek,
        .model = "deepseek-chat",
        .api_key = "test-key",
        .base_url = "https://api.deepseek.com",
    };
    var llm = try LLM.init(allocator, llm_config);
    defer llm.deinit();
    
    // Create dynamic instructions
    const dynamic_instructions = DynamicString.dynamic(struct {
        fn resolve(ctx: RuntimeContext) []const u8 {
            const user_name = ctx.getVariable("user_name");
            if (user_name) |name| {
                if (name == .string) {
                    return "You are a helpful assistant for Alice.";
                }
            }
            return "You are a helpful assistant.";
        }
    }.resolve);
    
    const agent_config = AgentConfig{
        .name = "dynamic-agent",
        .model = llm,
        .instructions = dynamic_instructions,
        .storage = storage,
    };
    
    var agent = try Agent.init(allocator, agent_config);
    defer agent.deinit();
    
    // Set context variable
    try agent.setContextVariable("user_name", std.json.Value{ .string = "Alice" });
    
    // Instructions should resolve dynamically
    const resolved = try agent.instructions.resolve(agent.runtime_context);
    try testing.expectEqualStrings("You are a helpful assistant for Alice.", resolved);
}
