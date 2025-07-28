# 工作流引擎示例

这个目录包含工作流引擎的示例和测试。

## 主要文件

### 并行工作流
- `test_parallel_workflow.zig` - 并行工作流测试 ✅ 推荐

## 工作流功能特性

- **并行执行** - 多线程并发执行工作流步骤
- **条件执行** - 基于条件的分支执行
- **循环执行** - 支持 loop 和 foreach 循环
- **事件等待** - waitForEvent 异步事件处理
- **睡眠控制** - sleep 和 sleepUntil 时间控制
- **错误恢复** - 异常处理和重试机制

## 运行示例

```bash
# 运行并行工作流测试
zig run examples/workflow/test_parallel_workflow.zig
```

## 工作流引擎架构

工作流引擎包含以下核心组件：
1. **ExecutionEngine** - 执行引擎
2. **ThreadPool** - 线程池管理
3. **ParallelExecutor** - 并行执行器
4. **StepFlowEntry** - 步骤流程控制
5. **ConditionalExecutor** - 条件执行器