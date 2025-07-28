# Mastra.zig Examples

这个目录包含了 Mastra.zig 框架的各种示例和测试代码，按功能模块组织。

## 目录结构

### 📁 basic/
基础功能示例和测试
- `final_verification.zig` - 最终功能验证测试
- `comprehensive_test.zig` - 综合功能测试
- `minimal_test.zig` - 最小化测试示例
- `cache_test.zig` - 缓存系统测试
- `deepseek_*.zig` - DeepSeek API 集成测试
- `http_debug.zig` - HTTP 客户端调试
- `network_diagnostic.zig` - 网络诊断工具
- `single_call_test.zig` - 单次调用测试
- `run_test.sh` - 测试运行脚本
- `curl_test.sh` - cURL 测试脚本

### 📁 agent/
AI Agent 系统示例
- `complete_agent_example.zig` - 完整的 Agent 使用示例
- `debug_agent_step_by_step.zig` - Agent 逐步调试示例
- `test_agent_simple.zig` - 简单 Agent 测试

### 📁 workflow/
工作流引擎示例
- `test_parallel_workflow.zig` - 并行工作流测试

### 📁 storage/
存储系统示例
- `test_storage_comprehensive.zig` - 存储系统综合测试
- `test_storage_debug.zig` - 存储系统调试
- `test_storage_isolation.zig` - 存储隔离测试
- `test_storage_minimal.zig` - 最小存储测试

### 📁 memory/
内存管理示例和测试
- `test_memory_leak_fix.zig` - 内存泄漏修复测试
- `final_memory_fix.zig` - 最终内存修复
- `debug_memory.zig` - 内存调试工具
- `http_memory_test.zig` - HTTP 内存测试
- `simple_memory.zig` - 简单内存测试
- `test_double_free_fix.zig` - 双重释放修复测试
- `test_hashmap_fix.zig` - HashMap 修复测试
- `test_memory_*.zig` - 各种内存管理测试

### 📁 rag/
RAG (检索增强生成) 系统示例
- `test_rag_system.zig` - RAG 系统测试

### 📁 features/
功能特性测试
- `test_all_features.zig` - 所有功能测试
- `test_current_features.zig` - 当前功能测试
- `test_p1_features.zig` - P1 级别功能测试
- `test_plan3_*.zig` - Plan3 实现相关测试
- `test_simple_features.zig` - 简单功能测试

## 使用方法

由于 Zig 的模块系统限制，examples 目录下的文件需要通过构建系统运行：

### 运行基础测试
```bash
cd mastra.zig
zig build run-final-verification
```

### 运行内存测试
```bash
zig build run-memory-leak-fix
```

### 运行 Agent 示例
```bash
zig build run-agent-complete
```

### 运行存储测试
```bash
zig build run-storage-comprehensive
```

### 运行 RAG 系统测试
```bash
zig build run-rag-system
```

### 运行工作流测试
```bash
zig build run-parallel-workflow
```

### 查看所有可用的构建目标
```bash
zig build --help
```

## 测试分类

### ✅ 稳定测试
- `examples/basic/final_verification.zig` - 最终验证，所有核心功能
- `examples/memory/test_memory_leak_fix.zig` - 内存泄漏修复验证
- `examples/agent/complete_agent_example.zig` - 完整 Agent 示例

### 🔧 调试工具
- `examples/memory/debug_memory.zig` - 内存调试
- `examples/basic/http_debug.zig` - HTTP 调试
- `examples/basic/network_diagnostic.zig` - 网络诊断

### 🧪 实验性测试
- `examples/features/test_plan3_*.zig` - Plan3 实现测试
- `examples/workflow/test_parallel_workflow.zig` - 并行工作流测试

## 注意事项

1. **内存管理**: 所有示例都包含内存泄漏检测
2. **错误处理**: 示例展示了正确的错误处理模式
3. **资源清理**: 确保所有资源都被正确释放
4. **并发安全**: 多线程示例展示了线程安全的使用方式

## 贡献指南

添加新示例时请遵循以下规范：
1. 将示例放在合适的子目录中
2. 包含详细的注释说明
3. 添加内存泄漏检测
4. 更新此 README 文件