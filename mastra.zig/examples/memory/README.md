# 内存管理示例

这个目录包含内存管理相关的测试和调试工具。

## 主要文件

### 内存泄漏测试
- `test_memory_leak_fix.zig` - 内存泄漏修复验证 ✅ 推荐
- `final_memory_fix.zig` - 最终内存修复测试
- `test_memory_final_check.zig` - 最终内存检查

### 内存调试工具
- `debug_memory.zig` - 内存调试工具
- `simple_memory.zig` - 简单内存测试

### 特定问题修复
- `test_double_free_fix.zig` - 双重释放问题修复
- `test_hashmap_fix.zig` - HashMap 内存问题修复
- `http_memory_test.zig` - HTTP 客户端内存测试

### 内存管理测试套件
- `test_memory_fix.zig` - 内存修复测试
- `test_memory_fix_final.zig` - 最终内存修复测试
- `test_memory_final.zig` - 内存最终测试

## 运行示例

```bash
# 推荐：运行内存泄漏修复测试
zig run examples/memory/test_memory_leak_fix.zig

# 运行内存调试工具
zig run examples/memory/debug_memory.zig

# 运行双重释放修复测试
zig run examples/memory/test_double_free_fix.zig
```

## 内存管理最佳实践

这些示例展示了：
1. 正确的内存分配和释放
2. 避免内存泄漏的技巧
3. 双重释放问题的解决方案
4. HashMap 等数据结构的安全使用