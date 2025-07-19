const std = @import("std");

pub const LogLevel = enum {
    debug,
    info,
    warn,
    error_level,
};

pub const LoggerConfig = struct {
    level: LogLevel = .info,
    output: ?std.fs.File.Writer = null,
};

pub const Logger = struct {
    allocator: std.mem.Allocator,
    config: LoggerConfig,
    mutex: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator, config: LoggerConfig) !*Logger {
        var logger = try allocator.create(Logger);
        logger.* = Logger{
            .allocator = allocator,
            .config = config,
            .mutex = std.Thread.Mutex{},
        };
        return logger;
    }

    pub fn deinit(self: *Logger) void {
        self.allocator.destroy(self);
    }

    pub fn debug(self: *Logger, comptime format: []const u8, args: anytype) void {
        if (@intFromEnum(self.config.level) <= @intFromEnum(LogLevel.debug)) {
            self.log("DEBUG", format, args);
        }
    }

    pub fn info(self: *Logger, comptime format: []const u8, args: anytype) void {
        if (@intFromEnum(self.config.level) <= @intFromEnum(LogLevel.info)) {
            self.log("INFO", format, args);
        }
    }

    pub fn warn(self: *Logger, comptime format: []const u8, args: anytype) void {
        if (@intFromEnum(self.config.level) <= @intFromEnum(LogLevel.warn)) {
            self.log("WARN", format, args);
        }
    }

    pub fn err(self: *Logger, comptime format: []const u8, args: anytype) void {
        if (@intFromEnum(self.config.level) <= @intFromEnum(LogLevel.error)) {
            self.log("ERROR", format, args);
        }
    }

    fn log(self: *Logger, level: []const u8, comptime format: []const u8, args: anytype) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const timestamp = std.time.timestamp();
        const output = self.config.output orelse std.io.getStdOut().writer();
        
        output.print("[{s}] [{d}] " ++ format ++ "\n", .{ level, timestamp } ++ args) catch {};
    }
    }
};