#!/bin/bash

echo "🚀 开始编译和运行存储系统测试..."

# 编译测试
echo "📦 编译测试文件..."
zig build-exe test_storage_comprehensive.zig

if [ $? -eq 0 ]; then
    echo "✅ 编译成功！"
    
    # 运行测试
    echo "🏃 运行测试..."
    ./test_storage_comprehensive
    
    if [ $? -eq 0 ]; then
        echo "🎉 测试完成！"
    else
        echo "❌ 测试失败！"
    fi
else
    echo "❌ 编译失败！"
fi

echo "🏁 测试脚本执行完毕"
