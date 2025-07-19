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

// HTTP客户端和网络
pub const http = @import("core/http.zig");
pub const EventLoop = @import("core/event_loop.zig").EventLoop;

pub const Agent = agent.Agent;
pub const AgentConfig = agent.AgentConfig;
pub const Message = agent.Message;
pub const AgentResponse = agent.AgentResponse;

pub const Workflow = workflow.Workflow;
pub const WorkflowConfig = workflow.WorkflowConfig;
pub const WorkflowRun = workflow.WorkflowRun;
pub const StepConfig = workflow.StepConfig;
pub const StepStatus = workflow.StepStatus;
pub const StepResult = workflow.StepResult;

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
