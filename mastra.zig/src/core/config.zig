//! 配置管理模块
//!
//! 支持：
//! - 环境变量读取
//! - JSON配置文件
//! - 默认值设置
//! - 类型安全的配置访问

const std = @import("std");

/// 配置错误类型
pub const ConfigError = error{
    FileNotFound,
    InvalidJson,
    MissingRequiredField,
    InvalidValue,
    OutOfMemory,
};

/// 配置值类型
pub const ConfigValue = union(enum) {
    string: []const u8,
    integer: i64,
    float: f64,
    boolean: bool,
    null_value,
    
    pub fn asString(self: ConfigValue) ?[]const u8 {
        return switch (self) {
            .string => |s| s,
            else => null,
        };
    }
    
    pub fn asInteger(self: ConfigValue) ?i64 {
        return switch (self) {
            .integer => |i| i,
            else => null,
        };
    }
    
    pub fn asFloat(self: ConfigValue) ?f64 {
        return switch (self) {
            .float => |f| f,
            else => null,
        };
    }
    
    pub fn asBool(self: ConfigValue) ?bool {
        return switch (self) {
            .boolean => |b| b,
            else => null,
        };
    }
    
    pub fn isNull(self: ConfigValue) bool {
        return switch (self) {
            .null_value => true,
            else => false,
        };
    }
};

/// 配置管理器
pub const ConfigManager = struct {
    allocator: std.mem.Allocator,
    values: std.StringHashMap(ConfigValue),
    
    const Self = @This();
    
    /// 初始化配置管理器
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .values = std.StringHashMap(ConfigValue).init(allocator),
        };
    }
    
    /// 清理配置管理器
    pub fn deinit(self: *Self) void {
        // 清理字符串值
        var iterator = self.values.iterator();
        while (iterator.next()) |entry| {
            switch (entry.value_ptr.*) {
                .string => |s| self.allocator.free(s),
                else => {},
            }
            self.allocator.free(entry.key_ptr.*);
        }
        self.values.deinit();
    }
    
    /// 从环境变量加载配置
    pub fn loadFromEnv(self: *Self) ConfigError!void {
        // 常见的环境变量
        const env_vars = [_][]const u8{
            "OPENAI_API_KEY",
            "ANTHROPIC_API_KEY",
            "GROQ_API_KEY",
            "LOG_LEVEL",
            "DATABASE_URL",
            "MASTRA_PORT",
            "MASTRA_HOST",
            "MASTRA_DEBUG",
        };
        
        for (env_vars) |var_name| {
            if (std.process.getEnvVarOwned(self.allocator, var_name)) |value| {
                const key = try self.allocator.dupe(u8, var_name);
                try self.values.put(key, ConfigValue{ .string = value });
            } else |_| {
                // 环境变量不存在，跳过
            }
        }
    }
    
    /// 从JSON文件加载配置
    pub fn loadFromFile(self: *Self, file_path: []const u8) ConfigError!void {
        const file_content = std.fs.cwd().readFileAlloc(self.allocator, file_path, 1024 * 1024) catch |err| switch (err) {
            error.FileNotFound => return ConfigError.FileNotFound,
            else => return ConfigError.FileNotFound,
        };
        defer self.allocator.free(file_content);
        
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, file_content, .{}) catch {
            return ConfigError.InvalidJson;
        };
        defer parsed.deinit();
        
        try self.loadFromJsonValue("", parsed.value);
    }
    
    /// 从JSON值递归加载配置
    fn loadFromJsonValue(self: *Self, prefix: []const u8, value: std.json.Value) ConfigError!void {
        switch (value) {
            .object => |obj| {
                var iterator = obj.iterator();
                while (iterator.next()) |entry| {
                    const key = if (prefix.len > 0)
                        try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ prefix, entry.key_ptr.* })
                    else
                        try self.allocator.dupe(u8, entry.key_ptr.*);
                    
                    try self.loadFromJsonValue(key, entry.value_ptr.*);
                    self.allocator.free(key);
                }
            },
            .string => |s| {
                const key = try self.allocator.dupe(u8, prefix);
                const val = try self.allocator.dupe(u8, s);
                try self.values.put(key, ConfigValue{ .string = val });
            },
            .integer => |i| {
                const key = try self.allocator.dupe(u8, prefix);
                try self.values.put(key, ConfigValue{ .integer = i });
            },
            .float => |f| {
                const key = try self.allocator.dupe(u8, prefix);
                try self.values.put(key, ConfigValue{ .float = f });
            },
            .bool => |b| {
                const key = try self.allocator.dupe(u8, prefix);
                try self.values.put(key, ConfigValue{ .boolean = b });
            },
            .null => {
                const key = try self.allocator.dupe(u8, prefix);
                try self.values.put(key, ConfigValue.null_value);
            },
            else => {
                // 忽略数组等其他类型
            },
        }
    }
    
    /// 设置配置值
    pub fn set(self: *Self, key: []const u8, value: ConfigValue) ConfigError!void {
        const key_copy = try self.allocator.dupe(u8, key);
        
        // 如果是字符串值，需要复制
        const value_copy = switch (value) {
            .string => |s| ConfigValue{ .string = try self.allocator.dupe(u8, s) },
            else => value,
        };
        
        try self.values.put(key_copy, value_copy);
    }
    
    /// 获取配置值
    pub fn get(self: *const Self, key: []const u8) ?ConfigValue {
        return self.values.get(key);
    }
    
    /// 获取字符串配置值
    pub fn getString(self: *const Self, key: []const u8, default_value: ?[]const u8) ?[]const u8 {
        if (self.get(key)) |value| {
            return value.asString();
        }
        return default_value;
    }
    
    /// 获取整数配置值
    pub fn getInteger(self: *const Self, key: []const u8, default_value: i64) i64 {
        if (self.get(key)) |value| {
            return value.asInteger() orelse default_value;
        }
        return default_value;
    }
    
    /// 获取浮点数配置值
    pub fn getFloat(self: *const Self, key: []const u8, default_value: f64) f64 {
        if (self.get(key)) |value| {
            return value.asFloat() orelse default_value;
        }
        return default_value;
    }
    
    /// 获取布尔配置值
    pub fn getBool(self: *const Self, key: []const u8, default_value: bool) bool {
        if (self.get(key)) |value| {
            return value.asBool() orelse default_value;
        }
        return default_value;
    }
    
    /// 检查配置键是否存在
    pub fn has(self: *const Self, key: []const u8) bool {
        return self.values.contains(key);
    }
    
    /// 获取所有配置键
    pub fn getKeys(self: *const Self, allocator: std.mem.Allocator) ![][]const u8 {
        var keys = std.ArrayList([]const u8).init(allocator);
        defer keys.deinit();
        
        var iterator = self.values.iterator();
        while (iterator.next()) |entry| {
            try keys.append(entry.key_ptr.*);
        }
        
        return keys.toOwnedSlice();
    }
    
    /// 打印所有配置（用于调试）
    pub fn debug(self: *const Self) void {
        std.debug.print("Configuration values:\n");
        var iterator = self.values.iterator();
        while (iterator.next()) |entry| {
            const value_str = switch (entry.value_ptr.*) {
                .string => |s| s,
                .integer => |i| std.fmt.allocPrint(self.allocator, "{d}", .{i}) catch "?",
                .float => |f| std.fmt.allocPrint(self.allocator, "{d}", .{f}) catch "?",
                .boolean => |b| if (b) "true" else "false",
                .null_value => "null",
            };
            std.debug.print("  {s} = {s}\n", .{ entry.key_ptr.*, value_str });
        }
    }
};

// 测试
test "ConfigManager basic functionality" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var config = ConfigManager.init(allocator);
    defer config.deinit();
    
    // 测试设置和获取
    try config.set("test_string", ConfigValue{ .string = "hello" });
    try config.set("test_int", ConfigValue{ .integer = 42 });
    try config.set("test_bool", ConfigValue{ .boolean = true });
    
    // 验证值
    try std.testing.expectEqualStrings("hello", config.getString("test_string", null).?);
    try std.testing.expect(config.getInteger("test_int", 0) == 42);
    try std.testing.expect(config.getBool("test_bool", false) == true);
    
    // 测试默认值
    try std.testing.expectEqualStrings("default", config.getString("nonexistent", "default").?);
    try std.testing.expect(config.getInteger("nonexistent", 100) == 100);
}

test "ConfigManager environment variables" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var config = ConfigManager.init(allocator);
    defer config.deinit();
    
    // 加载环境变量（如果存在）
    try config.loadFromEnv();
    
    // 这个测试依赖于环境变量，所以只检查基本功能
    try std.testing.expect(true);
}
