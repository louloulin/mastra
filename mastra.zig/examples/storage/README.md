# 存储系统示例

这个目录包含存储系统的测试和示例。

## 主要文件

### 综合测试
- `test_storage_comprehensive.zig` - 存储系统综合测试 ✅ 推荐
- `test_storage_minimal.zig` - 最小存储功能测试

### 调试和隔离测试
- `test_storage_debug.zig` - 存储系统调试
- `test_storage_isolation.zig` - 存储隔离测试

## 支持的存储后端

- **内存存储** - 基于内存的快速存储 ✅ 已实现
- **PostgreSQL** - 关系型数据库存储 🔧 架构完成
- **MongoDB** - 文档型数据库存储 🔧 架构完成
- **SQLite** - 轻量级文件数据库 🔧 架构完成

## 运行示例

```bash
# 运行综合存储测试
zig run examples/storage/test_storage_comprehensive.zig

# 运行最小存储测试
zig run examples/storage/test_storage_minimal.zig

# 运行存储调试
zig run examples/storage/test_storage_debug.zig
```

## 存储系统特性

- 统一的存储接口
- 支持 CRUD 操作
- 查询和过滤功能
- 事务支持（PostgreSQL）
- 索引管理（MongoDB）
- 连接池管理