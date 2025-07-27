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
pub const storage = @import("storage/storage.zig");
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

pub const Storage = storage.Storage;
pub const StorageConfig = storage.StorageConfig;
pub const StorageRecord = storage.StorageRecord;

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
