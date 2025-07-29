//! CLI主程序入口
const std = @import("std");
const cli = @import("cli.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 获取命令行参数
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // 初始化CLI
    var cli_instance = try cli.Cli.init(allocator, null);
    defer cli_instance.deinit();

    // 解析参数（跳过程序名）
    if (args.len > 1) {
        // 转换参数类型
        var converted_args = std.ArrayList([]const u8).init(allocator);
        defer converted_args.deinit();
        
        for (args[1..]) |arg| {
            try converted_args.append(arg);
        }
        
        try cli_instance.parseArgs(converted_args.items);
    }

    // 执行命令
    try cli_instance.execute();
}