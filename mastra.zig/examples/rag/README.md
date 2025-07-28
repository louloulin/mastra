# RAG 系统示例

这个目录包含 RAG (检索增强生成) 系统的示例和测试。

## 主要文件

### RAG 系统测试
- `test_rag_system.zig` - RAG 系统综合测试 ✅ 推荐

## RAG 系统功能

### 文档处理
- 支持多种文档格式：text, markdown, html, json, csv
- 智能文档分块 (chunking)
- 文档元数据管理

### 向量化系统
- 1536 维向量嵌入生成
- 文本相似度计算
- 向量存储和检索

### 检索系统
- 语义检索
- 混合检索 (关键词 + 向量)
- 检索结果重排序
- 检索优化

### 图 RAG 支持
- 知识图谱构建
- 实体关系提取
- 图遍历算法
- 关系推理

## 运行示例

```bash
# 运行 RAG 系统测试
zig run examples/rag/test_rag_system.zig
```

## RAG 系统架构

RAG 系统包含以下核心组件：
1. **DocumentProcessor** - 文档处理器
2. **EmbeddingProvider** - 向量嵌入提供者
3. **VectorStore** - 向量存储
4. **RAGSystem** - RAG 工作流
5. **GraphRAG** - 图 RAG 系统
6. **EntityExtractor** - 实体提取器