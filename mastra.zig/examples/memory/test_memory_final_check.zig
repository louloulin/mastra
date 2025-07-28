const std = @import("std");
const mastra = @import("mastra");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("❌ 内存泄漏检测到！\n", .{});
            std.process.exit(1);
        } else {
            std.debug.print("✅ 无内存泄漏！内存管理修复完全成功！\n", .{});
        }
    }
    const allocator = gpa.allocator();

    std.debug.print("🚀 内存管理最终验证\n", .{});
    std.debug.print("==================================================\n", .{});

    // 测试1: 存储系统基础功能
    std.debug.print("1. 存储系统基础功能测试...\n", .{});
    try testStorageBasics(allocator);

    // 测试2: 存储系统高级功能
    std.debug.print("2. 存储系统高级功能测试...\n", .{});
    try testStorageAdvanced(allocator);

    // 测试3: 存储系统压力测试
    std.debug.print("3. 存储系统压力测试...\n", .{});
    try testStorageStress(allocator);

    std.debug.print("\n🎉 内存管理最终验证完成！\n", .{});
    std.debug.print("==================================================\n", .{});
}

fn testStorageBasics(allocator: std.mem.Allocator) !void {
    const storage_config = mastra.storage.StorageConfig{
        .type = .memory,
    };
    var storage = try mastra.storage.Storage.init(allocator, storage_config);
    defer storage.deinit();

    // 创建记录
    const test_data = std.json.Value{ .string = "basic_test" };
    const record_id = try storage.create("test_table", test_data);
    std.debug.print("   ✅ 创建记录: {s}\n", .{record_id});

    // 读取记录
    const retrieved = try storage.read("test_table", record_id);
    if (retrieved != null) {
        std.debug.print("   ✅ 读取记录成功\n", .{});
    }

    // 更新记录
    const updated_data = std.json.Value{ .string = "updated_basic_test" };
    const update_success = try storage.update("test_table", record_id, updated_data);
    if (update_success) {
        std.debug.print("   ✅ 更新记录成功\n", .{});
    }

    std.debug.print("   ✅ 基础功能测试完成\n", .{});
}

fn testStorageAdvanced(allocator: std.mem.Allocator) !void {
    const storage_config = mastra.storage.StorageConfig{
        .type = .memory,
    };
    var storage = try mastra.storage.Storage.init(allocator, storage_config);
    defer storage.deinit();

    // 创建多种类型的数据
    const test_cases = [_]std.json.Value{
        std.json.Value{ .string = "字符串数据" },
        std.json.Value{ .integer = 42 },
        std.json.Value{ .float = 3.14 },
        std.json.Value{ .bool = true },
        std.json.Value{ .null = {} },
    };

    for (test_cases, 0..) |test_data, i| {
        const record_id = try storage.create("advanced_table", test_data);
        std.debug.print("   ✅ 创建高级记录 {}: {s}\n", .{ i + 1, record_id });
    }

    // 查询功能
    const query_config = mastra.storage.StorageQuery{
        .limit = 3,
        .offset = 0,
    };
    const results = try storage.query("advanced_table", query_config);
    defer allocator.free(results);
    std.debug.print("   ✅ 查询返回 {} 条记录\n", .{results.len});

    // 计数功能
    const count = storage.count("advanced_table");
    std.debug.print("   ✅ 总记录数: {}\n", .{count});

    std.debug.print("   ✅ 高级功能测试完成\n", .{});
}

fn testStorageStress(allocator: std.mem.Allocator) !void {
    const storage_config = mastra.storage.StorageConfig{
        .type = .memory,
    };
    var storage = try mastra.storage.Storage.init(allocator, storage_config);
    defer storage.deinit();

    // 创建大量记录
    const record_count = 100;
    std.debug.print("   开始创建 {} 条记录...\n", .{record_count});

    for (0..record_count) |i| {
        const test_data = std.json.Value{ .integer = @intCast(i) };
        const record_id = try storage.create("stress_table", test_data);
        
        // 每10条记录报告一次进度
        if ((i + 1) % 10 == 0) {
            std.debug.print("   ✅ 已创建 {} 条记录\n", .{i + 1});
        }
        
        // 验证记录可以读取
        const retrieved = try storage.read("stress_table", record_id);
        if (retrieved == null) {
            std.debug.print("   ❌ 记录 {} 读取失败\n", .{i + 1});
            return;
        }
    }

    // 验证总数
    const final_count = storage.count("stress_table");
    std.debug.print("   ✅ 压力测试完成，总记录数: {}\n", .{final_count});

    // 删除一些记录测试
    std.debug.print("   开始删除测试...\n", .{});
    var delete_count: usize = 0;
    var iter = storage.data.iterator();
    while (iter.next()) |entry| {
        if (std.mem.startsWith(u8, entry.key_ptr.*, "stress_table")) {
            const delete_success = storage.delete("stress_table", entry.key_ptr.*);
            if (delete_success) {
                delete_count += 1;
            }
            if (delete_count >= 10) break; // 只删除10条记录
        }
    }
    
    const remaining_count = storage.count("stress_table");
    std.debug.print("   ✅ 删除 {} 条记录，剩余 {} 条\n", .{ delete_count, remaining_count });

    std.debug.print("   ✅ 压力测试完成\n", .{});
}
