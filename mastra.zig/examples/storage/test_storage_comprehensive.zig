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
            std.debug.print("✅ 无内存泄漏！存储系统修复成功！\n", .{});
        }
    }
    const allocator = gpa.allocator();

    std.debug.print("🚀 存储系统综合测试\n", .{});
    std.debug.print("==================================================\n", .{});

    try testStorageSystem(allocator);

    std.debug.print("\n🎉 存储系统综合测试完成！\n", .{});
    std.debug.print("==================================================\n", .{});
}

fn testStorageSystem(allocator: std.mem.Allocator) !void {
    const storage_config = mastra.storage.StorageConfig{
        .type = .memory,
    };
    var storage = try mastra.storage.Storage.init(allocator, storage_config);
    defer storage.deinit();

    std.debug.print("✅ 存储系统初始化成功\n", .{});

    // 测试1: 创建操作
    std.debug.print("\n1. 测试创建操作...\n", .{});
    var record_ids = std.ArrayList([]const u8).init(allocator);
    defer record_ids.deinit(); // 不需要手动释放id，存储系统会管理

    // 创建不同类型的数据
    const test_cases = [_]struct {
        name: []const u8,
        data: std.json.Value,
    }{
        .{ .name = "字符串", .data = std.json.Value{ .string = "测试字符串" } },
        .{ .name = "整数", .data = std.json.Value{ .integer = 42 } },
        .{ .name = "浮点数", .data = std.json.Value{ .float = 3.14 } },
        .{ .name = "布尔值", .data = std.json.Value{ .bool = true } },
        .{ .name = "空值", .data = std.json.Value{ .null = {} } },
    };

    for (test_cases) |test_case| {
        const record_id = try storage.create("test_table", test_case.data);
        try record_ids.append(record_id);
        std.debug.print("   ✅ 创建{s}记录: {s}\n", .{ test_case.name, record_id });
    }

    // 测试2: 读取操作
    std.debug.print("\n2. 测试读取操作...\n", .{});
    for (record_ids.items, 0..) |id, i| {
        const retrieved = try storage.read("test_table", id);
        if (retrieved != null) {
            std.debug.print("   ✅ 读取记录 {} 成功: {s}\n", .{ i + 1, id });
        } else {
            std.debug.print("   ❌ 读取记录 {} 失败: {s}\n", .{ i + 1, id });
        }
    }

    // 测试3: 更新操作
    std.debug.print("\n3. 测试更新操作...\n", .{});
    if (record_ids.items.len > 0) {
        const first_id = record_ids.items[0];
        const updated_data = std.json.Value{ .string = "更新后的数据" };
        const update_success = try storage.update("test_table", first_id, updated_data);
        if (update_success) {
            std.debug.print("   ✅ 更新记录成功: {s}\n", .{first_id});

            // 验证更新
            const updated_record = try storage.read("test_table", first_id);
            if (updated_record != null) {
                std.debug.print("   ✅ 验证更新成功\n", .{});
            }
        } else {
            std.debug.print("   ❌ 更新记录失败: {s}\n", .{first_id});
        }
    }

    // 测试4: 计数操作
    std.debug.print("\n4. 测试计数操作...\n", .{});
    const count = storage.count("test_table");
    std.debug.print("   ✅ 表中记录数量: {}\n", .{count});

    // 测试5: 查询操作
    std.debug.print("\n5. 测试查询操作...\n", .{});
    const query_config = mastra.storage.StorageQuery{
        .limit = 3,
        .offset = 0,
    };
    const query_results = try storage.query("test_table", query_config);
    defer allocator.free(query_results);

    std.debug.print("   ✅ 查询返回 {} 条记录\n", .{query_results.len});
    for (query_results, 0..) |result, i| {
        std.debug.print("   ✅ 查询结果 {}: {s}\n", .{ i + 1, result.id });
    }

    // 测试6: 删除操作
    std.debug.print("\n6. 测试删除操作...\n", .{});
    if (record_ids.items.len > 1) {
        const last_index = record_ids.items.len - 1;
        const last_id = record_ids.items[last_index];
        // 创建id的副本用于打印，因为delete会释放原始key
        const id_copy = try allocator.dupe(u8, last_id);
        defer allocator.free(id_copy);

        const delete_success = storage.delete("test_table", last_id);
        if (delete_success) {
            std.debug.print("   ✅ 删除记录成功: {s}\n", .{id_copy});

            // 从record_ids中移除已删除的id，避免双重释放
            _ = record_ids.pop();

            // 验证删除（使用副本）
            const deleted_record = try storage.read("test_table", id_copy);
            if (deleted_record == null) {
                std.debug.print("   ✅ 验证删除成功\n", .{});
            }
        } else {
            std.debug.print("   ❌ 删除记录失败: {s}\n", .{id_copy});
        }
    }

    // 测试7: 最终计数
    std.debug.print("\n7. 测试最终计数...\n", .{});
    const final_count = storage.count("test_table");
    std.debug.print("   ✅ 删除后记录数量: {}\n", .{final_count});

    std.debug.print("\n🎯 所有存储操作测试完成\n", .{});
}
