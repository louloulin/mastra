const std = @import("std");
const testing = std.testing;

test "Debug: 测试mastra模块导入" {
    // 尝试导入mastra模块
    _ = @import("mastra");

    // 如果能到这里，说明导入成功
    try testing.expect(true);
}

test "Debug: 测试Mastra初始化" {
    const mastra = @import("mastra");

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 尝试初始化Mastra
    var m = try mastra.Mastra.init(allocator, .{});
    defer m.deinit();

    try testing.expect(true);
}

test "Debug: 测试Storage初始化" {
    const mastra = @import("mastra");

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 尝试初始化Storage
    var storage = try mastra.Storage.init(allocator, .{ .type = .memory });
    defer storage.deinit();

    try testing.expect(true);
}

test "Debug: 测试VectorStore初始化" {
    const mastra = @import("mastra");

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 尝试初始化VectorStore
    var vector_store = try mastra.VectorStore.init(allocator, .{ .type = .memory, .dimension = 3 });
    defer vector_store.deinit();

    try testing.expect(true);
}
