//! Mastra 专用配置系统
//!
//! 提供类型安全的配置管理，支持：
//! - 环境变量加载
//! - JSON配置文件
//! - 默认值和验证
//! - 运行时配置更新

const std = @import("std");
const ConfigManager = @import("config.zig").ConfigManager;
const ConfigValue = @import("config.zig").ConfigValue;

/// 日志级别
pub const LogLevel = enum {
    debug,
    info,
    warn,
    err,

    pub fn fromString(str: []const u8) ?LogLevel {
        if (std.mem.eql(u8, str, "debug")) return .debug;
        if (std.mem.eql(u8, str, "info")) return .info;
        if (std.mem.eql(u8, str, "warn")) return .warn;
        if (std.mem.eql(u8, str, "error")) return .err;
        return null;
    }

    pub fn toString(self: LogLevel) []const u8 {
        return switch (self) {
            .debug => "debug",
            .info => "info",
            .warn => "warn",
            .err => "error",
        };
    }
};

/// LLM 提供商类型
pub const LLMProvider = enum {
    openai,
    anthropic,
    groq,
    ollama,

    pub fn fromString(str: []const u8) ?LLMProvider {
        if (std.mem.eql(u8, str, "openai")) return .openai;
        if (std.mem.eql(u8, str, "anthropic")) return .anthropic;
        if (std.mem.eql(u8, str, "groq")) return .groq;
        if (std.mem.eql(u8, str, "ollama")) return .ollama;
        return null;
    }
};

/// Mastra 配置结构
pub const MastraConfig = struct {
    // 基础配置
    allocator: std.mem.Allocator,
    config_manager: ConfigManager,

    // API 密钥
    openai_api_key: ?[]const u8 = null,
    anthropic_api_key: ?[]const u8 = null,
    groq_api_key: ?[]const u8 = null,

    // 日志配置
    log_level: LogLevel = .info,
    log_format: []const u8 = "json",

    // 数据库配置
    database_url: []const u8 = "data.db",
    database_pool_size: u32 = 10,

    // HTTP 配置
    http_timeout_ms: u32 = 30000,
    http_max_retries: u32 = 3,
    http_user_agent: []const u8 = "Mastra.zig/0.1.0",

    // 服务器配置
    server_port: u16 = 8080,
    server_host: []const u8 = "127.0.0.1",
    server_max_connections: u32 = 1000,

    // 向量存储配置
    vector_dimension: usize = 1536,
    vector_similarity_threshold: f32 = 0.7,
    vector_max_results: usize = 10,

    // 内存配置
    memory_max_messages: usize = 100,
    memory_enable_semantic_recall: bool = true,
    memory_working_memory_enabled: bool = false,

    // 工作流配置
    workflow_max_steps: u32 = 100,
    workflow_timeout_ms: u32 = 300000, // 5分钟

    // 遥测配置
    telemetry_enabled: bool = false,
    telemetry_endpoint: ?[]const u8 = null,

    const Self = @This();

    /// 初始化配置
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .config_manager = ConfigManager.init(allocator),
        };
    }

    /// 从环境变量和配置文件加载
    pub fn load(allocator: std.mem.Allocator, config_path: ?[]const u8) !Self {
        var config = Self.init(allocator);

        // 1. 加载环境变量
        try config.config_manager.loadFromEnv();

        // 2. 加载配置文件
        if (config_path) |path| {
            config.config_manager.loadFromFile(path) catch |err| switch (err) {
                error.FileNotFound => {
                    std.log.warn("Config file not found: {s}", .{path});
                },
                else => return err,
            };
        }

        // 3. 应用配置值
        try config.applyConfiguration();

        // 4. 验证配置
        try config.validate();

        return config;
    }

    /// 应用配置管理器中的值到结构体字段
    fn applyConfiguration(self: *Self) !void {
        // API 密钥
        self.openai_api_key = self.config_manager.getString("OPENAI_API_KEY", null);
        self.anthropic_api_key = self.config_manager.getString("ANTHROPIC_API_KEY", null);
        self.groq_api_key = self.config_manager.getString("GROQ_API_KEY", null);

        // 日志配置
        if (self.config_manager.getString("LOG_LEVEL", null)) |level_str| {
            if (LogLevel.fromString(level_str)) |level| {
                self.log_level = level;
            }
        }

        if (self.config_manager.getString("LOG_FORMAT", null)) |format| {
            self.log_format = format;
        }

        // 数据库配置
        if (self.config_manager.getString("DATABASE_URL", null)) |url| {
            self.database_url = url;
        }

        self.database_pool_size = @intCast(self.config_manager.getInteger("DATABASE_POOL_SIZE", 10));

        // HTTP 配置
        self.http_timeout_ms = @intCast(self.config_manager.getInteger("HTTP_TIMEOUT_MS", 30000));
        self.http_max_retries = @intCast(self.config_manager.getInteger("HTTP_MAX_RETRIES", 3));

        if (self.config_manager.getString("HTTP_USER_AGENT", null)) |ua| {
            self.http_user_agent = ua;
        }

        // 服务器配置
        self.server_port = @intCast(self.config_manager.getInteger("MASTRA_PORT", 8080));

        if (self.config_manager.getString("MASTRA_HOST", null)) |host| {
            self.server_host = host;
        }

        self.server_max_connections = @intCast(self.config_manager.getInteger("SERVER_MAX_CONNECTIONS", 1000));

        // 向量存储配置
        self.vector_dimension = @intCast(self.config_manager.getInteger("VECTOR_DIMENSION", 1536));
        self.vector_similarity_threshold = @floatCast(self.config_manager.getFloat("VECTOR_SIMILARITY_THRESHOLD", 0.7));
        self.vector_max_results = @intCast(self.config_manager.getInteger("VECTOR_MAX_RESULTS", 10));

        // 内存配置
        self.memory_max_messages = @intCast(self.config_manager.getInteger("MEMORY_MAX_MESSAGES", 100));
        self.memory_enable_semantic_recall = self.config_manager.getBool("MEMORY_ENABLE_SEMANTIC_RECALL", true);
        self.memory_working_memory_enabled = self.config_manager.getBool("MEMORY_WORKING_MEMORY_ENABLED", false);

        // 工作流配置
        self.workflow_max_steps = @intCast(self.config_manager.getInteger("WORKFLOW_MAX_STEPS", 100));
        self.workflow_timeout_ms = @intCast(self.config_manager.getInteger("WORKFLOW_TIMEOUT_MS", 300000));

        // 遥测配置
        self.telemetry_enabled = self.config_manager.getBool("TELEMETRY_ENABLED", false);
        self.telemetry_endpoint = self.config_manager.getString("TELEMETRY_ENDPOINT", null);
    }

    /// 验证配置
    pub fn validate(self: *const Self) !void {
        // 检查是否至少有一个 API 密钥
        if (self.openai_api_key == null and 
            self.anthropic_api_key == null and 
            self.groq_api_key == null) {
            std.log.warn("No API keys configured. At least one LLM provider API key is recommended.");
        }

        // 验证端口范围
        if (self.server_port == 0 or self.server_port > 65535) {
            return error.InvalidServerPort;
        }

        // 验证向量维度
        if (self.vector_dimension == 0) {
            return error.InvalidVectorDimension;
        }

        // 验证相似度阈值
        if (self.vector_similarity_threshold < 0.0 or self.vector_similarity_threshold > 1.0) {
            return error.InvalidSimilarityThreshold;
        }

        // 验证超时值
        if (self.http_timeout_ms == 0 or self.workflow_timeout_ms == 0) {
            return error.InvalidTimeout;
        }
    }

    /// 清理配置
    pub fn deinit(self: *Self) void {
        self.config_manager.deinit();
    }

    /// 获取指定提供商的 API 密钥
    pub fn getApiKey(self: *const Self, provider: LLMProvider) ?[]const u8 {
        return switch (provider) {
            .openai => self.openai_api_key,
            .anthropic => self.anthropic_api_key,
            .groq => self.groq_api_key,
            .ollama => null, // Ollama 通常不需要 API 密钥
        };
    }

    /// 检查提供商是否可用
    pub fn isProviderAvailable(self: *const Self, provider: LLMProvider) bool {
        return switch (provider) {
            .ollama => true, // Ollama 不需要 API 密钥
            else => self.getApiKey(provider) != null,
        };
    }

    /// 打印配置摘要（隐藏敏感信息）
    pub fn printSummary(self: *const Self) void {
        std.debug.print("Mastra Configuration Summary:\n");
        std.debug.print("  Log Level: {s}\n", .{self.log_level.toString()});
        std.debug.print("  Server: {s}:{d}\n", .{ self.server_host, self.server_port });
        std.debug.print("  Database: {s}\n", .{self.database_url});
        std.debug.print("  Vector Dimension: {d}\n", .{self.vector_dimension});
        
        std.debug.print("  Available Providers:\n");
        inline for (std.meta.fields(LLMProvider)) |field| {
            const provider = @field(LLMProvider, field.name);
            const available = self.isProviderAvailable(provider);
            std.debug.print("    {s}: {s}\n", .{ field.name, if (available) "✓" else "✗" });
        }
    }
};
