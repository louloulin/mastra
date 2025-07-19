const std = @import("std");
const core = @import("core/mastra.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    
    const allocator = gpa.allocator();
    
    var mastra = try core.Mastra.init(allocator, .{});
    defer mastra.deinit();
    
    std.debug.print("Mastra initialized successfully\n", .{});
}