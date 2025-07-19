#!/bin/bash

# 测试DeepSeek API的curl命令
# 用于验证API密钥和请求格式是否正确

echo "🔍 使用curl测试DeepSeek API..."
echo "=================================="

API_KEY="sk-bf82ef56c5c44ef6867bf4199d084706"
URL="https://api.deepseek.com/v1/chat/completions"

echo "📤 发送请求到: $URL"
echo "🔑 API密钥: ${API_KEY:0:8}...${API_KEY: -8}"

# 构建JSON请求
REQUEST_JSON='{
  "model": "deepseek-chat",
  "messages": [
    {"role": "user", "content": "Hello, how are you?"}
  ],
  "max_tokens": 10,
  "temperature": 0.7
}'

echo "📄 请求体:"
echo "$REQUEST_JSON"
echo ""

echo "🔄 发送请求..."

# 发送curl请求，显示详细头部信息
curl -X POST "$URL" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -H "User-Agent: curl/8.4.0" \
  -H "Accept: */*" \
  -d "$REQUEST_JSON" \
  -v \
  --http1.1 \
  --max-time 30

echo ""
echo "✅ curl测试完成"
