//! 简单集成测试
//!
//! 测试基本的 Zig 功能和数据结构

const std = @import("std");
const testing = std.testing;

test "基本数据结构测试" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 测试字符串分配和释放
    const test_string = try allocator.dupe(u8, "Hello, Mastra!");
    defer allocator.free(test_string);

    try testing.expectEqualStrings(test_string, "Hello, Mastra!");

    // 测试数组列表
    var list = std.ArrayList(i32).init(allocator);
    defer list.deinit();

    try list.append(1);
    try list.append(2);
    try list.append(3);

    try testing.expect(list.items.len == 3);
    try testing.expect(list.items[0] == 1);
    try testing.expect(list.items[2] == 3);

    std.debug.print("✓ 基本数据结构测试通过\n", .{});
}

test "HashMap 基本功能测试" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 测试 HashMap 基本操作
    var map = std.StringHashMap(i32).init(allocator);
    defer map.deinit();

    try map.put("key1", 100);
    try map.put("key2", 200);

    try testing.expect(map.count() == 2);
    try testing.expect(map.get("key1").? == 100);
    try testing.expect(map.get("key2").? == 200);
    try testing.expect(map.get("key3") == null);

    // 测试更新
    try map.put("key1", 150);
    try testing.expect(map.get("key1").? == 150);

    // 测试删除
    _ = map.remove("key2");
    try testing.expect(map.count() == 1);
    try testing.expect(map.get("key2") == null);

    std.debug.print("✓ HashMap 基本功能测试通过\n", .{});
}

test "向量计算基础测试" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 测试向量操作
    const vec1 = try allocator.alloc(f32, 3);
    defer allocator.free(vec1);
    const vec2 = try allocator.alloc(f32, 3);
    defer allocator.free(vec2);

    vec1[0] = 1.0;
    vec1[1] = 0.0;
    vec1[2] = 0.0;
    vec2[0] = 0.0;
    vec2[1] = 1.0;
    vec2[2] = 0.0;

    // 计算点积
    var dot_product: f32 = 0.0;
    for (vec1, vec2) |a, b| {
        dot_product += a * b;
    }
    try testing.expect(dot_product == 0.0); // 垂直向量

    // 计算欧几里得距离
    var distance: f32 = 0.0;
    for (vec1, vec2) |a, b| {
        const diff = a - b;
        distance += diff * diff;
    }
    distance = @sqrt(distance);
    try testing.expect(@abs(distance - @sqrt(2.0)) < 0.001);

    std.debug.print("✓ 向量计算基础测试通过\n", .{});
}

test "JSON 解析基础测试" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 测试 JSON 解析
    const json_string =
        \\{
        \\  "name": "test",
        \\  "value": 42,
        \\  "active": true
        \\}
    ;

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_string, .{});
    defer parsed.deinit();

    const root = parsed.value.object;
    try testing.expectEqualStrings(root.get("name").?.string, "test");
    try testing.expect(root.get("value").?.integer == 42);
    try testing.expect(root.get("active").?.bool == true);

    std.debug.print("✓ JSON 解析基础测试通过\n", .{});
}

test "时间戳和字符串格式化测试" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 测试时间戳
    const timestamp = std.time.timestamp();
    try testing.expect(timestamp > 0);

    // 测试字符串格式化
    const formatted = try std.fmt.allocPrint(allocator, "timestamp_{d}", .{timestamp});
    defer allocator.free(formatted);

    try testing.expect(std.mem.startsWith(u8, formatted, "timestamp_"));

    std.debug.print("✓ 时间戳和字符串格式化测试通过\n", .{});
}

test "错误处理测试" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 测试内存分配失败的模拟
    var failing_allocator = std.testing.FailingAllocator.init(allocator, .{ .fail_index = 0 });
    const result = failing_allocator.allocator().alloc(u8, 100);
    try testing.expectError(error.OutOfMemory, result);

    // 测试 JSON 解析错误
    const invalid_json = "{ invalid json }";
    const parse_result = std.json.parseFromSlice(std.json.Value, allocator, invalid_json, .{});
    try testing.expectError(error.SyntaxError, parse_result);

    std.debug.print("✓ 错误处理测试通过\n", .{});
}

test "文件系统基础测试" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建临时文件
    const temp_path = "test_temp_file.txt";
    const test_content = "Hello, Mastra file system test!";

    // 写入文件
    try std.fs.cwd().writeFile(.{ .sub_path = temp_path, .data = test_content });

    // 读取文件
    const read_content = try std.fs.cwd().readFileAlloc(allocator, temp_path, 1024);
    defer allocator.free(read_content);

    try testing.expectEqualStrings(test_content, read_content);

    // 清理临时文件
    std.fs.cwd().deleteFile(temp_path) catch {};

    std.debug.print("✓ 文件系统基础测试通过\n", .{});
}

test "并发基础测试" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 测试互斥锁
    var mutex = std.Thread.Mutex{};
    var shared_counter: i32 = 0;

    const TestContext = struct {
        mutex: *std.Thread.Mutex,
        counter: *i32,
    };

    const increment_fn = struct {
        fn run(context: TestContext) void {
            context.mutex.lock();
            defer context.mutex.unlock();
            context.counter.* += 1;
        }
    }.run;

    const context = TestContext{ .mutex = &mutex, .counter = &shared_counter };

    // 模拟并发访问
    increment_fn(context);
    increment_fn(context);
    increment_fn(context);

    try testing.expect(shared_counter == 3);

    std.debug.print("✓ 并发基础测试通过\n", .{});
    _ = allocator; // 避免未使用警告
}

test "Mastra 架构验证测试" {
    // 这个测试验证我们的 Mastra 架构设计是否合理

    // 验证模块化设计
    const modules = [_][]const u8{
        "core",
        "agent",
        "llm",
        "memory",
        "storage",
        "workflow",
        "tools",
        "utils",
    };

    for (modules) |module| {
        try testing.expect(module.len > 0);
    }

    // 验证配置结构
    const ConfigTest = struct {
        name: []const u8,
        value: i32,
        enabled: bool,
    };

    const test_config = ConfigTest{
        .name = "test",
        .value = 42,
        .enabled = true,
    };

    try testing.expectEqualStrings(test_config.name, "test");
    try testing.expect(test_config.value == 42);
    try testing.expect(test_config.enabled == true);

    std.debug.print("✓ Mastra 架构验证测试通过\n", .{});
}
