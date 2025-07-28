const std = @import("std");
const mastra = @import("mastra");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("❌ 检测到内存泄漏！\n", .{});
            std.process.exit(1);
        } else {
            std.debug.print("✅ 无内存泄漏！内存管理完美！\n", .{});
        }
    }
    const allocator = gpa.allocator();

    std.debug.print("🚀 最终内存泄漏修复验证\n", .{});
    std.debug.print("==================================================\n", .{});

    try testMemoryManagement(allocator);

    std.debug.print("\n🎉 内存管理测试完成！\n", .{});
    std.debug.print("==================================================\n", .{});
}

fn testMemoryManagement(allocator: std.mem.Allocator) !void {
    std.debug.print("\n📋 内存管理验证测试\n", .{});
    std.debug.print("----------------------------------------\n", .{});

    // 测试1: 基本存储操作
    std.debug.print("1. 测试基本存储操作...\n", .{});
    {
        const storage_config = mastra.storage.StorageConfig{
            .type = .memory,
        };
        var storage = try mastra.storage.Storage.init(allocator, storage_config);
        defer storage.deinit();

        const test_data = std.json.Value{ .string = "test_value" };
        const record_id = try storage.create("test_table", test_data);
        defer allocator.free(record_id);

        std.debug.print("   ✅ 创建记录: {s}\n", .{record_id});

        const retrieved = try storage.read("test_table", record_id);
        if (retrieved != null) {
            std.debug.print("   ✅ 读取记录成功\n", .{});
        }
    }
    std.debug.print("   ✅ 基本存储操作测试完成\n", .{});

    // 测试2: 多记录操作
    std.debug.print("2. 测试多记录操作...\n", .{});
    {
        const storage_config = mastra.storage.StorageConfig{
            .type = .memory,
        };
        var storage = try mastra.storage.Storage.init(allocator, storage_config);
        defer storage.deinit();

        var record_ids = std.ArrayList([]const u8).init(allocator);
        defer {
            for (record_ids.items) |id| {
                allocator.free(id);
            }
            record_ids.deinit();
        }

        // 创建多个记录
        for (0..3) |i| {
            const test_data = std.json.Value{ .integer = @intCast(i) };
            const record_id = try storage.create("test_table", test_data);
            try record_ids.append(record_id);
            std.debug.print("   ✅ 创建记录 {}: {s}\n", .{ i + 1, record_id });
        }

        // 读取所有记录
        for (record_ids.items, 0..) |id, i| {
            const retrieved = try storage.read("test_table", id);
            if (retrieved != null) {
                std.debug.print("   ✅ 读取记录 {} 成功\n", .{i + 1});
            }
        }
    }
    std.debug.print("   ✅ 多记录操作测试完成\n", .{});

    // 测试3: 复杂数据类型
    std.debug.print("3. 测试复杂数据类型...\n", .{});
    {
        const storage_config = mastra.storage.StorageConfig{
            .type = .memory,
        };
        var storage = try mastra.storage.Storage.init(allocator, storage_config);
        defer storage.deinit();

        // 测试不同的JSON值类型
        const test_cases = [_]std.json.Value{
            std.json.Value{ .string = "字符串值" },
            std.json.Value{ .integer = 42 },
            std.json.Value{ .float = 3.14 },
            std.json.Value{ .bool = true },
            std.json.Value{ .null = {} },
        };

        var record_ids = std.ArrayList([]const u8).init(allocator);
        defer {
            for (record_ids.items) |id| {
                allocator.free(id);
            }
            record_ids.deinit();
        }

        for (test_cases, 0..) |test_data, i| {
            const record_id = try storage.create("test_table", test_data);
            try record_ids.append(record_id);
            std.debug.print("   ✅ 创建复杂数据记录 {}\n", .{i + 1});
        }

        // 验证读取
        for (record_ids.items, 0..) |id, i| {
            const retrieved = try storage.read("test_table", id);
            if (retrieved != null) {
                std.debug.print("   ✅ 读取复杂数据记录 {} 成功\n", .{i + 1});
            }
        }
    }
    std.debug.print("   ✅ 复杂数据类型测试完成\n", .{});

    // 测试4: 更新操作
    std.debug.print("4. 测试更新操作...\n", .{});
    {
        const storage_config = mastra.storage.StorageConfig{
            .type = .memory,
        };
        var storage = try mastra.storage.Storage.init(allocator, storage_config);
        defer storage.deinit();

        const initial_data = std.json.Value{ .string = "初始值" };
        const record_id = try storage.create("test_table", initial_data);
        defer allocator.free(record_id);

        std.debug.print("   ✅ 创建初始记录\n", .{});

        const updated_data = std.json.Value{ .string = "更新值" };
        _ = try storage.update("test_table", record_id, updated_data);
        std.debug.print("   ✅ 更新记录成功\n", .{});

        const retrieved = try storage.read("test_table", record_id);
        if (retrieved != null) {
            std.debug.print("   ✅ 读取更新后记录成功\n", .{});
        }
    }
    std.debug.print("   ✅ 更新操作测试完成\n", .{});

    std.debug.print("   🎯 所有内存管理测试完成\n", .{});
}
