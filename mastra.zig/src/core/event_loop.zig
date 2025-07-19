//! 事件循环模块 - 简化版异步事件处理
//!
//! 提供基础的异步任务调度：
//! - 任务队列管理
//! - 定时器支持
//! - 线程池集成

const std = @import("std");

/// 事件循环错误类型
pub const EventLoopError = error{
    InitializationFailed,
    LoopRunFailed,
    TaskSubmissionFailed,
    OutOfMemory,
};

/// 异步任务回调函数类型
pub const TaskCallback = *const fn (ctx: ?*anyopaque) anyerror!void;

/// 异步任务结构
pub const Task = struct {
    callback: TaskCallback,
    context: ?*anyopaque,
    delay_ms: u64,
    scheduled_time: i64,

    pub fn init(callback: TaskCallback, context: ?*anyopaque) Task {
        return Task{
            .callback = callback,
            .context = context,
            .delay_ms = 0,
            .scheduled_time = std.time.milliTimestamp(),
        };
    }

    pub fn initWithDelay(callback: TaskCallback, context: ?*anyopaque, delay_ms: u64) Task {
        return Task{
            .callback = callback,
            .context = context,
            .delay_ms = delay_ms,
            .scheduled_time = std.time.milliTimestamp() + @as(i64, @intCast(delay_ms)),
        };
    }

    pub fn isReady(self: *const Task) bool {
        return std.time.milliTimestamp() >= self.scheduled_time;
    }
};

/// 事件循环包装器
pub const EventLoop = struct {
    allocator: std.mem.Allocator,
    task_queue: std.ArrayList(*Task),
    running: bool,
    mutex: std.Thread.Mutex,

    const Self = @This();

    /// 初始化事件循环
    pub fn init(allocator: std.mem.Allocator) EventLoopError!Self {
        return Self{
            .allocator = allocator,
            .task_queue = std.ArrayList(*Task).init(allocator),
            .running = false,
            .mutex = std.Thread.Mutex{},
        };
    }

    /// 清理事件循环
    pub fn deinit(self: *Self) void {
        self.task_queue.deinit();
    }

    /// 运行事件循环
    pub fn run(self: *Self) EventLoopError!void {
        self.running = true;
        defer self.running = false;

        while (self.running) {
            self.processTasks();
            std.time.sleep(1 * std.time.ns_per_ms); // 1ms sleep
        }
    }

    /// 停止事件循环
    pub fn stop(self: *Self) void {
        self.running = false;
    }

    /// 提交异步任务
    pub fn submitTask(self: *Self, task: *Task) EventLoopError!void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.task_queue.append(task);
    }

    /// 延迟执行任务
    pub fn scheduleTask(self: *Self, task: *Task, delay_ms: u64) EventLoopError!void {
        task.* = Task.initWithDelay(task.callback, task.context, delay_ms);
        return self.submitTask(task);
    }

    /// 处理任务队列
    fn processTasks(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var i: usize = 0;
        while (i < self.task_queue.items.len) {
            const task = self.task_queue.items[i];
            if (task.isReady()) {
                // 执行任务
                task.callback(task.context) catch |err| {
                    std.log.err("Task execution failed: {}", .{err});
                };

                // 从队列中移除
                _ = self.task_queue.swapRemove(i);
            } else {
                i += 1;
            }
        }
    }

    /// 检查事件循环是否正在运行
    pub fn isRunning(self: *const Self) bool {
        return self.running;
    }
};

/// 全局事件循环实例
var global_loop: ?*EventLoop = null;

/// 获取全局事件循环实例
pub fn getGlobalLoop() ?*EventLoop {
    return global_loop;
}

/// 设置全局事件循环实例
pub fn setGlobalLoop(loop: *EventLoop) void {
    global_loop = loop;
}

/// 便捷函数：在全局事件循环中提交任务
pub fn submitGlobalTask(task: *Task) EventLoopError!void {
    if (global_loop) |loop| {
        return loop.submitTask(task);
    }
    return EventLoopError.TaskSubmissionFailed;
}

/// 便捷函数：在全局事件循环中延迟执行任务
pub fn scheduleGlobalTask(task: *Task, delay_ms: u64) EventLoopError!void {
    if (global_loop) |loop| {
        return loop.scheduleTask(task, delay_ms);
    }
    return EventLoopError.TaskSubmissionFailed;
}

// 测试
test "EventLoop basic functionality" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var loop = try EventLoop.init(allocator);
    defer loop.deinit();

    // 测试基本功能
    try std.testing.expect(!loop.isRunning());

    // 创建简单任务
    var executed = false;
    const TestContext = struct {
        executed: *bool,

        fn callback(ctx: ?*anyopaque) !void {
            if (ctx) |c| {
                const test_ctx: *@This() = @ptrCast(@alignCast(c));
                test_ctx.executed.* = true;
            }
        }
    };

    var test_ctx = TestContext{ .executed = &executed };
    var task = Task.init(TestContext.callback, &test_ctx);

    // 提交任务并运行
    try loop.submitTask(&task);

    // 在单独的线程中运行事件循环
    const thread = try std.Thread.spawn(.{}, struct {
        fn run(event_loop: *EventLoop) void {
            event_loop.run() catch {};
        }
    }.run, .{&loop});

    // 等待一段时间后停止
    std.time.sleep(10 * std.time.ns_per_ms);
    loop.stop();
    thread.join();

    try std.testing.expect(executed);
}

test "EventLoop task scheduling" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var loop = try EventLoop.init(allocator);
    defer loop.deinit();

    var executed = false;
    const TestContext = struct {
        executed: *bool,

        fn callback(ctx: ?*anyopaque) !void {
            if (ctx) |c| {
                const test_ctx: *@This() = @ptrCast(@alignCast(c));
                test_ctx.executed.* = true;
            }
        }
    };

    var test_ctx = TestContext{ .executed = &executed };
    var task = Task.init(TestContext.callback, &test_ctx);

    // 延迟执行任务
    try loop.scheduleTask(&task, 5); // 5ms延迟

    const thread = try std.Thread.spawn(.{}, struct {
        fn run(event_loop: *EventLoop) void {
            event_loop.run() catch {};
        }
    }.run, .{&loop});

    std.time.sleep(20 * std.time.ns_per_ms);
    loop.stop();
    thread.join();

    try std.testing.expect(executed);
}
