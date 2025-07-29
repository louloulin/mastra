# 工具系统示例

这个目录包含了Mastra.zig动态工具系统的示例和测试。

## 功能特性

### 1. 动态工具构建器 (ToolBuilder)
- 支持运行时创建工具定义
- 灵活的参数定义系统
- 类型安全的工具接口

### 2. 工具注册表 (ToolRegistry)
- 工具的注册和管理
- 工具发现和列举
- 工具执行和验证

### 3. MCP协议支持
- 标准化的AI模型与工具通信协议
- JSON-RPC 2.0协议实现
- 工具列表和调用接口

## 示例文件

- `test_dynamic_tools.zig` - 动态工具系统综合测试

## 运行示例

```bash
# 构建并运行动态工具测试
zig build run-dynamic-tools
```

## 工具类型支持

- **字符串工具**: 文本处理、格式化
- **数学工具**: 计算、统计
- **实用工具**: 通用功能
- **自定义工具**: 用户定义的工具

## MCP协议支持

支持以下MCP方法：
- `initialize` - 协议初始化
- `tools/list` - 列出可用工具
- `tools/call` - 调用指定工具

## 架构设计

```
ToolBuilder -> ToolDefinition -> ToolRegistry -> MCPServer
     ↓              ↓                ↓             ↓
  参数定义      工具元数据        工具管理      协议接口
```