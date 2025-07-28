const std = @import("std");
const mastra = @import("mastra");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("❌ 检测到内存泄漏！\n", .{});
        } else {
            std.debug.print("✅ 无内存泄漏！\n", .{});
        }
    }
    const allocator = gpa.allocator();

    std.debug.print("🚀 简单内存测试\n", .{});

    // 只测试存储系统的基本操作
    const storage_config = mastra.storage.StorageConfig{
        .type = .memory,
    };
    var storage = try mastra.storage.Storage.init(allocator, storage_config);
    defer storage.deinit();

    std.debug.print("✅ 存储系统初始化成功\n", .{});

    const test_data = std.json.Value{ .string = "test_value" };
    const record_id = try storage.create("test_table", test_data);
    defer allocator.free(record_id);

    std.debug.print("✅ 创建记录成功: {s}\n", .{record_id});

    // 暂时不调用read，先测试create和deinit
    // const retrieved = try storage.read("test_table", record_id);
    // if (retrieved != null) {
    //     std.debug.print("✅ 读取记录成功\n", .{});
    // }

    std.debug.print("🎉 测试完成！\n", .{});
}
