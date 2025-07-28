# AI Agent 系统示例

这个目录包含 AI Agent 系统的使用示例和测试。

## 主要文件

### 完整示例
- `complete_agent_example.zig` - 完整的 Agent 使用示例 ✅ 推荐
- `debug_agent_step_by_step.zig` - Agent 逐步调试示例

### 基础测试
- `test_agent_simple.zig` - 简单 Agent 功能测试

## 功能特性

这些示例展示了：
- Agent 的创建和配置
- 动态指令支持 (DynamicArgument)
- 消息列表管理 (MessageList)
- 异步保存队列 (SaveQueueManager)
- 运行时上下文 (RuntimeContext)
- 生成选项配置

## 运行示例

```bash
# 运行完整 Agent 示例
zig run examples/agent/complete_agent_example.zig

# 运行逐步调试示例
zig run examples/agent/debug_agent_step_by_step.zig

# 运行简单测试
zig run examples/agent/test_agent_simple.zig
```

## Agent 系统架构

Agent 系统包含以下核心组件：
1. **DynamicArgument** - 动态参数解析
2. **MessageList** - 智能消息管理
3. **SaveQueueManager** - 异步保存队列
4. **RuntimeContext** - 运行时上下文管理