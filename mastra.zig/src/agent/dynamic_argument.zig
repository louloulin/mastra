const std = @import("std");

/// Runtime context for dynamic argument resolution
pub const RuntimeContext = struct {
    allocator: std.mem.Allocator,
    variables: std.StringHashMap(std.json.Value),
    metadata: std.StringHashMap(std.json.Value),
    timestamp: i64,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .variables = std.StringHashMap(std.json.Value).init(allocator),
            .metadata = std.StringHashMap(std.json.Value).init(allocator),
            .timestamp = std.time.timestamp(),
        };
    }

    pub fn deinit(self: *Self) void {
        self.variables.deinit();
        self.metadata.deinit();
    }

    pub fn setVariable(self: *Self, key: []const u8, value: std.json.Value) !void {
        try self.variables.put(key, value);
    }

    pub fn getVariable(self: *const Self, key: []const u8) ?std.json.Value {
        return self.variables.get(key);
    }

    pub fn setMetadata(self: *Self, key: []const u8, value: std.json.Value) !void {
        try self.metadata.put(key, value);
    }

    pub fn getMetadata(self: *const Self, key: []const u8) ?std.json.Value {
        return self.metadata.get(key);
    }
};

/// Dynamic argument that can be resolved at runtime
pub fn DynamicArgument(comptime T: type) type {
    return union(enum) {
        /// Static value that never changes
        static_value: T,

        /// Dynamic value resolved by a function
        dynamic_func: *const fn (RuntimeContext) T,

        /// Async dynamic value resolved by an async function
        async_dynamic_func: *const fn (RuntimeContext) anyerror!T,

        const Self = @This();

        /// Resolve the dynamic argument to its concrete value
        pub fn resolve(self: Self, ctx: RuntimeContext) !T {
            return switch (self) {
                .static_value => |value| value,
                .dynamic_func => |func| func(ctx),
                .async_dynamic_func => |func| try func(ctx),
            };
        }

        /// Check if the argument is static (never changes)
        pub fn isStatic(self: Self) bool {
            return switch (self) {
                .static_value => true,
                else => false,
            };
        }

        /// Check if the argument is dynamic (can change at runtime)
        pub fn isDynamic(self: Self) bool {
            return !self.isStatic();
        }

        /// Create a static dynamic argument
        pub fn static(value: T) Self {
            return Self{ .static_value = value };
        }

        /// Create a dynamic argument from a function
        pub fn dynamic(func: *const fn (RuntimeContext) T) Self {
            return Self{ .dynamic_func = func };
        }

        /// Create an async dynamic argument from an async function
        pub fn asyncDynamic(func: *const fn (RuntimeContext) anyerror!T) Self {
            return Self{ .async_dynamic_func = func };
        }
    };
}

/// Specialized dynamic argument for strings (most common use case)
pub const DynamicString = DynamicArgument([]const u8);

/// Specialized dynamic argument for integers
pub const DynamicInt = DynamicArgument(i64);

/// Specialized dynamic argument for floats
pub const DynamicFloat = DynamicArgument(f64);

/// Specialized dynamic argument for booleans
pub const DynamicBool = DynamicArgument(bool);

/// Helper functions for common dynamic argument patterns
/// Create a dynamic string that interpolates variables from context
pub fn dynamicStringTemplate(comptime template: []const u8) DynamicString {
    const func = struct {
        fn resolve(ctx: RuntimeContext) []const u8 {
            // Simple template interpolation - in a real implementation,
            // this would parse the template and substitute variables
            _ = ctx;
            return template;
        }
    }.resolve;

    return DynamicString.dynamic(func);
}

/// Create a dynamic argument that reads from context variables
pub fn dynamicFromVariable(comptime T: type, comptime variable_name: []const u8) DynamicArgument(T) {
    const func = struct {
        fn resolve(ctx: RuntimeContext) anyerror!T {
            const value = ctx.getVariable(variable_name) orelse return error.VariableNotFound;

            // Type conversion based on T
            return switch (T) {
                []const u8 => switch (value) {
                    .string => |s| s,
                    else => error.InvalidType,
                },
                i64 => switch (value) {
                    .integer => |i| i,
                    else => error.InvalidType,
                },
                f64 => switch (value) {
                    .float => |f| f,
                    else => error.InvalidType,
                },
                bool => switch (value) {
                    .bool => |b| b,
                    else => error.InvalidType,
                },
                else => error.UnsupportedType,
            };
        }
    }.resolve;

    return DynamicArgument(T).asyncDynamic(func);
}

/// Create a dynamic argument that combines multiple values
pub fn dynamicCombine(comptime T: type, args: []const DynamicArgument(T), combine_fn: *const fn ([]const T) T) DynamicArgument(T) {
    const func = struct {
        fn resolve(ctx: RuntimeContext) anyerror!T {
            var values = std.ArrayList(T).init(ctx.allocator);
            defer values.deinit();

            for (args) |arg| {
                const value = try arg.resolve(ctx);
                try values.append(value);
            }

            return combine_fn(values.items);
        }
    }.resolve;

    return DynamicArgument(T).asyncDynamic(func);
}

// Tests
test "DynamicArgument static value" {
    const allocator = std.testing.allocator;
    var ctx = RuntimeContext.init(allocator);
    defer ctx.deinit();

    const arg = DynamicString.static("hello");
    const result = try arg.resolve(ctx);
    try std.testing.expectEqualStrings("hello", result);
    try std.testing.expect(arg.isStatic());
    try std.testing.expect(!arg.isDynamic());
}

test "DynamicArgument dynamic function" {
    const allocator = std.testing.allocator;
    var ctx = RuntimeContext.init(allocator);
    defer ctx.deinit();

    const func = struct {
        fn resolve(_: RuntimeContext) []const u8 {
            return "dynamic";
        }
    }.resolve;

    const arg = DynamicString.dynamic(func);
    const result = try arg.resolve(ctx);
    try std.testing.expectEqualStrings("dynamic", result);
    try std.testing.expect(!arg.isStatic());
    try std.testing.expect(arg.isDynamic());
}

test "DynamicArgument async dynamic function" {
    const allocator = std.testing.allocator;
    var ctx = RuntimeContext.init(allocator);
    defer ctx.deinit();

    const func = struct {
        fn resolve(_: RuntimeContext) anyerror![]const u8 {
            return "async_dynamic";
        }
    }.resolve;

    const arg = DynamicString.asyncDynamic(func);
    const result = try arg.resolve(ctx);
    try std.testing.expectEqualStrings("async_dynamic", result);
}

test "DynamicArgument from context variable" {
    const allocator = std.testing.allocator;
    var ctx = RuntimeContext.init(allocator);
    defer ctx.deinit();

    try ctx.setVariable("test_var", std.json.Value{ .string = "from_context" });

    const arg = dynamicFromVariable([]const u8, "test_var");
    const result = try arg.resolve(ctx);
    try std.testing.expectEqualStrings("from_context", result);
}
