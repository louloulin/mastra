//! Mastra.zig - AI应用开发框架
//!
//! 基于Zig实现的高性能AI应用开发框架，支持：
//! - 异步事件循环 (libxev)
//! - LLM集成 (OpenAI, Anthropic等)
//! - 工具系统和函数调用
//! - 工作流引擎
//! - 向量存储和相似度搜索
//! - 内存管理和持久化

const std = @import("std");

// 核心模块
pub const Mastra = @import("core/mastra.zig").Mastra;
pub const Config = @import("core/mastra.zig").Config;

// 子模块
pub const agent = @import("agent/agent.zig");
pub const workflow = @import("workflow/workflow.zig");
pub const tools = @import("tools/tool.zig");
pub const tool_builder = @import("tools/tool_builder.zig");
pub const mcp = @import("tools/mcp.zig");
pub const storage = @import("storage/storage.zig");
pub const rag = @import("rag/rag.zig");
pub const document = @import("rag/document.zig");
pub const embeddings = @import("rag/embeddings.zig");
pub const events = @import("events/event.zig");
pub const event_bus = @import("events/event_bus.zig");
pub const streaming = @import("streaming/stream.zig");
pub const response_stream = @import("streaming/response_stream.zig");
pub const graph_rag = @import("rag/graph_rag.zig");
pub const evaluator = @import("evaluation/evaluator.zig");
pub const integration = @import("integration/auth.zig");
pub const postgresql = @import("storage/postgresql.zig");
pub const mongodb = @import("storage/mongodb.zig");
pub const memory = @import("memory/memory.zig");
pub const llm = @import("llm/llm.zig");
pub const telemetry = @import("telemetry/telemetry.zig");
pub const vector = @import("storage/vector.zig");
pub const utils = @import("utils/logger.zig");
pub const cache = @import("utils/cache.zig");

// HTTP客户端和网络
pub const http = @import("core/http.zig");
pub const EventLoop = @import("core/event_loop.zig").EventLoop;

pub const Agent = agent.Agent;
pub const AgentConfig = agent.AgentConfig;
pub const Message = agent.Message;
pub const AgentResponse = agent.AgentResponse;

// Enhanced agent components
pub const DynamicArgument = @import("agent/dynamic_argument.zig").DynamicArgument;
pub const DynamicString = @import("agent/dynamic_argument.zig").DynamicString;
pub const RuntimeContext = @import("agent/dynamic_argument.zig").RuntimeContext;
pub const MessageList = @import("agent/message_list.zig").MessageList;
pub const MessageListConfig = @import("agent/message_list.zig").MessageListConfig;
pub const MessageImportance = @import("agent/message_list.zig").MessageImportance;
pub const SaveQueueManager = @import("agent/save_queue_manager.zig").SaveQueueManager;
pub const SaveQueueConfig = @import("agent/save_queue_manager.zig").SaveQueueConfig;
pub const AgentGenerateOptions = @import("agent/agent_options.zig").AgentGenerateOptions;
pub const AgentStreamOptions = @import("agent/agent_options.zig").AgentStreamOptions;
pub const AgentGenerateResponse = @import("agent/agent_options.zig").AgentGenerateResponse;

pub const Workflow = workflow.Workflow;
pub const WorkflowConfig = workflow.WorkflowConfig;
pub const WorkflowRun = workflow.WorkflowRun;
pub const StepConfig = workflow.StepConfig;
pub const StepStatus = workflow.StepStatus;
pub const StepResult = workflow.StepResult;

// Enhanced workflow components
pub const ExecutionEngine = @import("workflow/execution_engine.zig").ExecutionEngine;
pub const StepFlowEntry = @import("workflow/execution_engine.zig").StepFlowEntry;
pub const StepFlowType = @import("workflow/execution_engine.zig").StepFlowType;
pub const ConditionFunc = @import("workflow/execution_engine.zig").ConditionFunc;
pub const LoopConfig = @import("workflow/execution_engine.zig").LoopConfig;
pub const ForeachConfig = @import("workflow/execution_engine.zig").ForeachConfig;
pub const ParallelExecutor = @import("workflow/parallel_executor.zig").ParallelExecutor;
pub const ThreadPool = @import("workflow/parallel_executor.zig").ThreadPool;
pub const ThreadPoolConfig = @import("workflow/parallel_executor.zig").ThreadPoolConfig;

pub const Tool = tools.Tool;
pub const ToolConfig = tools.ToolSchema;
pub const ToolInput = tools.ToolInput;
pub const ToolOutput = tools.ToolOutput;
pub const ToolBuilder = tool_builder.ToolBuilder;
pub const ToolRegistry = tool_builder.ToolRegistry;
pub const DynamicToolDefinition = tool_builder.DynamicToolDefinition;
pub const MCPServer = mcp.MCPServer;

// RAG System exports
pub const RAGSystem = rag.RAGSystem;
pub const RAGConfig = rag.RAGConfig;
pub const RAGContext = rag.RAGContext;
pub const DocumentProcessor = document.DocumentProcessor;
pub const DocumentType = document.DocumentType;
pub const DocumentChunk = document.DocumentChunk;
pub const EmbeddingProvider = embeddings.EmbeddingProvider;
pub const RAGVectorStore = embeddings.VectorStore;
pub const SearchResult = embeddings.SearchResult;

// Event System exports
pub const Event = events.Event;
pub const EventBus = event_bus.EventBus;
pub const EventSubscription = events.EventSubscription;
pub const EventHandler = events.EventHandler;
pub const EventPriority = events.EventPriority;

// Streaming exports
pub const Stream = streaming.Stream;
pub const StreamChunk = streaming.StreamChunk;
pub const ResponseStream = response_stream.ResponseStream;
pub const SSEEvent = response_stream.SSEEvent;
pub const WebSocketMessage = response_stream.WebSocketMessage;

// Graph RAG exports
pub const GraphRAG = graph_rag.GraphRAG;
pub const KnowledgeGraph = graph_rag.KnowledgeGraph;
pub const Entity = graph_rag.Entity;
pub const Relationship = graph_rag.Relationship;

// Evaluation exports
pub const EvaluationSession = evaluator.EvaluationSession;
pub const EvaluationResult = evaluator.EvaluationResult;
pub const TestCase = evaluator.TestCase;

// Integration exports
pub const AuthProvider = integration.AuthProvider;
pub const ServiceRegistry = integration.ServiceRegistry;
pub const IntegrationManager = integration.IntegrationManager;

pub const Storage = storage.Storage;
pub const StorageConfig = storage.StorageConfig;
pub const StorageRecord = storage.StorageRecord;
pub const PostgreSQLStorage = postgresql.PostgreSQLStorage;
pub const PostgreSQLConfig = postgresql.PostgreSQLConfig;
pub const MongoDBStorage = mongodb.MongoDBStorage;
pub const MongoDBConfig = mongodb.MongoDBConfig;

pub const Memory = memory.Memory;
pub const MemoryConfig = memory.MemoryConfig;

pub const LLM = llm.LLM;
pub const LLMConfig = llm.LLMConfig;
pub const LLMProvider = llm.LLMProvider;

pub const Telemetry = telemetry.Telemetry;
pub const TelemetryConfig = telemetry.TelemetryConfig;

pub const VectorStore = vector.VectorStore;
pub const VectorStoreConfig = vector.VectorStoreConfig;
pub const VectorDocument = vector.VectorDocument;

pub const Logger = utils.Logger;

pub const LRUCache = cache.LRUCache;
pub const CacheConfig = cache.CacheConfig;
pub const CacheStats = cache.CacheStats;

// DeepSeek API 支持
pub const DeepSeekClient = llm.DeepSeekClient;
pub const DeepSeekRequest = llm.DeepSeekRequest;
pub const DeepSeekResponse = llm.DeepSeekResponse;
pub const DeepSeekMessage = llm.DeepSeekMessage;
