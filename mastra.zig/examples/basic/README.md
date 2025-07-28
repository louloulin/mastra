# 基础功能示例

这个目录包含 Mastra.zig 的基础功能示例和测试。

## 主要文件

### 核心测试
- `final_verification.zig` - 最终功能验证，测试所有核心模块
- `comprehensive_test.zig` - 综合功能测试
- `minimal_test.zig` - 最小化功能测试

### API 集成测试
- `deepseek_debug.zig` - DeepSeek API 调试
- `deepseek_direct.zig` - DeepSeek 直接调用测试
- `deepseek_only_test.zig` - 仅 DeepSeek 功能测试

### 网络和 HTTP
- `http_debug.zig` - HTTP 客户端调试
- `network_diagnostic.zig` - 网络连接诊断
- `single_call_test.zig` - 单次 HTTP 调用测试

### 工具脚本
- `run_test.sh` - 批量测试运行脚本
- `curl_test.sh` - cURL 测试脚本

## 运行示例

```bash
# 运行最终验证测试
zig run examples/basic/final_verification.zig

# 运行最小化测试
zig run examples/basic/minimal_test.zig

# 运行 DeepSeek 调试
zig run examples/basic/deepseek_debug.zig
```