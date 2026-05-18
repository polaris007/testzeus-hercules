# TestZeus Hercules 多 Agent 调度与通信机制

## 📋 目录

- [1. 系统架构概览](#1-系统架构概览)
- [2. Agent 角色与职责](#2-agent-角色与职责)
- [3. Agent 配置管理](#3-agent-配置管理)
- [4. 消息传递机制](#4-消息传递机制)
- [5. GroupChat 工作原理](#5-groupchat-工作原理)
- [6. 状态转换与路由](#6-状态转换与路由)
- [7. 完整执行流程](#7-完整执行流程)
- [8. 关键技术点](#8-关键技术点)
- [9. 数据结构详解](#9-数据结构详解)
- [10. 实战示例](#10-实战示例)

---

## 1. 系统架构概览

TestZeus Hercules 使用 **AutoGen 框架**实现多智能体协作，采用分层架构设计：

```
┌─────────────────────────────────────────────────────────────┐
│                    用户输入测试用例                           │
│              (Gherkin Feature 文件)                          │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│                  Runner (启动器)                             │
│  - 初始化 SimpleHercules                                    │
│  - 启动 Playwright 浏览器管理器                              │
│  - 加载 Agent 配置                                          │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│              SimpleHercules (核心引擎)                        │
│  - 创建所有 Agent 实例                                       │
│  - 设置 GroupChat 通信机制                                   │
│  - 配置状态转换逻辑                                          │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│                Agent 协作执行流程                             │
│                                                             │
│  ┌──────────────┐                                           │
│  │ Planner Agent │ ← 规划器（大脑）                          │
│  └──────┬───────┘                                           │
│         │ 生成计划和下一步指令                                │
│         ▼                                                   │
│  ┌──────────────┐                                           │
│  │   User Agent  │ ← 用户代理（协调者）                      │
│  └──────┬───────┘                                           │
│         │ 路由到对应的导航 Agent                              │
│         ▼                                                   │
│  ┌──────────────────────────────────────────┐               │
│  │      Nav Agent + Nav Executor            │               │
│  │  (根据 target_helper 选择)                │               │
│  │                                          │               │
│  │ • Browser Nav Agent    → 浏览器操作       │               │
│  │ • API Nav Agent        → API 测试        │               │
│  │ • SQL Nav Agent        → 数据库查询       │               │
│  │ • Security Nav Agent   → 安全测试        │               │
│  │ • Time Keeper Nav      → 时间相关操作     │               │
│  │ • MCP Nav Agent        → MCP 工具调用    │               │
│  │ • Executor Nav Agent   → 脚本执行        │               │
│  └──────────────────────────────────────────┘               │
│         │                                                   │
│         │ 循环执行直到任务完成                                │
│         └──────────────────────────────────┐                │
│                                            │                │
└────────────────────────────────────────────┼────────────────┘
                                             │
                                             ▼
                                  ┌──────────────────────┐
                                  │   生成测试报告         │
                                  │  (XML/HTML 格式)      │
                                  └──────────────────────┘
```

---

## 2. Agent 角色与职责

### 2.1 Agent 类型总览

| Agent 名称 | 角色 | 职责 | 配置来源 |
|-----------|------|------|---------|
| **Planner Agent** | 🧠 大脑 | 解析测试用例、生成计划、决策下一步 | `planner_agent` |
| **User Agent** | 📨 协调者 | 路由消息、协调 Agent 间通信 | 内置 |
| **Browser Nav Agent** | 🌐 浏览器专家 | 理解浏览器操作指令 | `nav_agent` |
| **Browser Nav Executor** | ⚙️ 浏览器执行器 | 执行浏览器自动化操作 | 无（UserProxyAgent） |
| **API Nav Agent** | 🔌 API 专家 | 理解 API 测试指令 | `nav_agent` |
| **API Nav Executor** | ⚙️ API 执行器 | 发送 HTTP 请求 | 无（UserProxyAgent） |
| **SQL Nav Agent** | 💾 数据库专家 | 理解数据库查询指令 | `nav_agent` |
| **SQL Nav Executor** | ⚙️ SQL 执行器 | 执行 SQL 查询 | 无（UserProxyAgent） |
| **Security Nav Agent** | 🔒 安全专家 | 理解安全测试指令 | `nav_agent` |
| **Security Nav Executor** | ⚙️ 安全执行器 | 执行安全扫描 | 无（UserProxyAgent） |
| **Time Keeper Nav Agent** | ⏰ 时间管理 | 处理时间相关操作 | `nav_agent` |
| **MCP Nav Agent** | 🔧 MCP 工具 | 调用 MCP 服务器工具 | `nav_agent` |
| **Executor Nav Agent** | 📜 脚本执行 | 执行 Python 脚本 | `nav_agent` |
| **Memory Agent** | 🧠 记忆管理 | 存储和检索测试上下文 | `mem_agent` |
| **Helper Agent** | 🛠️ 通用助手 | 处理特殊任务 | `helper_agent` |

### 2.2 分层架构

```
高层（战略规划）
└── Planner Agent
    ├── 解析 Gherkin 测试用例
    ├── 生成执行计划
    ├── 决定下一步操作
    └── 评估执行结果

中层（战术决策）
├── User Agent（协调者）
├── Browser Nav Agent
├── API Nav Agent
├── SQL Nav Agent
├── Security Nav Agent
├── Time Keeper Nav Agent
├── MCP Nav Agent
└── Executor Nav Agent

底层（具体执行）
├── Browser Nav Executor
├── API Nav Executor
├── SQL Nav Executor
├── Security Nav Executor
├── Time Keeper Nav Executor
├── MCP Nav Executor
└── Executor Nav Executor
```

---

## 3. Agent 配置管理

### 3.1 配置文件结构

所有 Agent 的配置定义在 `agents_llm_config.json` 文件中：

```json
{
  "agent_configs": [
    {
      "name": "planner_agent",
      "model_config_params": {
        "model": "deepseek-ai/DeepSeek-V3.2",
        "api_key": "${MODEL_API_KEY}",
        "base_url": "https://api-inference.modelscope.cn/v1",
        "model_api_type": "openai"
      },
      "llm_config_params": {
        "temperature": 0.7,
        "top_p": 0.95,
        "timeout": 180,
        "max_retries": 5
      },
      "other_settings": {
        "system_prompt": "自定义系统提示词..."
      }
    },
    {
      "name": "nav_agent",
      "model_config_params": {
        "model": "deepseek-ai/DeepSeek-V3.2",
        "api_key": "${MODEL_API_KEY}",
        "base_url": "https://api-inference.modelscope.cn/v1",
        "model_api_type": "openai"
      },
      "llm_config_params": {
        "temperature": 0.3,
        "top_p": 0.9,
        "timeout": 120
      },
      "other_settings": {
        "system_prompt": "你是浏览器自动化专家..."
      }
    },
    {
      "name": "mem_agent",
      "model_config_params": { ... },
      "llm_config_params": { ... },
      "other_settings": { ... }
    },
    {
      "name": "helper_agent",
      "model_config_params": { ... },
      "llm_config_params": { ... },
      "other_settings": { ... }
    }
  ]
}
```

### 3.2 配置共享机制

**重要特性**：所有导航 Agent 共享同一个 `nav_agent` 配置！

```python
# simple_hercules.py - 第 184-192 行

# 所有 Nav Agent 都使用同一个 nav_agent_config
self.browser_nav_agent_model_config = convert_model_config_to_autogen_format(
    self.nav_agent_config["model_config_params"]
)
self.api_nav_agent_model_config = convert_model_config_to_autogen_format(
    self.nav_agent_config["model_config_params"]
)
self.sec_nav_agent_model_config = convert_model_config_to_autogen_format(
    self.nav_agent_config["model_config_params"]
)
self.sql_nav_agent_model_config = convert_model_config_to_autogen_format(
    self.nav_agent_config["model_config_params"]
)
self.time_keeper_nav_agent_model_config = convert_model_config_to_autogen_format(
    self.nav_agent_config["model_config_params"]
)
self.mcp_nav_agent_model_config = convert_model_config_to_autogen_format(
    self.nav_agent_config["model_config_params"]
)
self.executor_nav_agent_model_config = convert_model_config_to_autogen_format(
    self.nav_agent_config["model_config_params"]
)
```

**配置映射关系**：

| 配置名称 | 被哪些 Agent 使用 | 说明 |
|---------|------------------|------|
| `planner_agent` | `planner_agent` | 规划器（大脑） |
| `nav_agent` | `browser_nav_agent`<br>`api_nav_agent`<br>`sec_nav_agent`<br>`sql_nav_agent`<br>`time_keeper_nav_agent`<br>`mcp_nav_agent`<br>`executor_nav_agent` | **所有导航 Agent 共享** |
| `mem_agent` | `mem_agent` | 记忆管理 |
| `helper_agent` | `helper_agent` | 通用助手 |

**设计优势**：
- ✅ 简化配置管理
- ✅ 统一行为风格
- ✅ 降低维护成本
- ✅ 便于批量调整参数

---

## 4. 消息传递机制

### 4.1 三种消息传递方式

```
┌─────────────────────────────────────────────────────────┐
│              AutoGen 消息传递机制                         │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ① GroupChat + state_transition (主要方式)              │
│     └─ 自动路由：User → Nav Agent → Executor → ...      │
│                                                         │
│  ② Nested Chat (嵌套聊天)                               │
│     └─ User Agent ↔ GroupChat Manager                   │
│                                                         │
│  ③ register_reply (回调函数)                            │
│     └─ 自定义消息处理和返回逻辑                          │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### 4.2 消息格式规范

#### Planner Agent 的消息（JSON 格式）

```json
{
  "plan": "详细的分步测试执行计划",
  "next_step": "下一步要执行的指令（字符串）",
  "terminate": "yes/no",
  "final_response": "最终结果",
  "is_assert": true/false,
  "assert_summary": "预期结果 vs 实际结果",
  "is_passed": true/false,
  "target_helper": "browser/api/sec/sql/time_keeper/agent/mcp/executor"
}
```

#### Nav Agent 的消息（自然语言）

```
TASK FOR HELPER: 打开 https://www.baidu.com ##target_helper: browser##
```

#### Executor 的消息（工具执行结果）

```
Page loaded: https://www.baidu.com, Title: 百度一下
```

### 4.3 特殊标记

| 标记 | 作用 | 示例 |
|------|------|------|
| `##target_helper: browser##` | 路由标记，指定目标 Helper | 用于 state_transition |
| `##TERMINATE TASK##` | 终止标记，结束当前任务 | 表示步骤完成 |
| `##FLAG::SAVE_IN_MEM##` | 记忆标记，保存到长期记忆 | 用于跨步骤上下文 |

---

## 5. GroupChat 工作原理

### 5.1 GroupChat 核心组件

```python
# AutoGen 内部结构（简化版）

class GroupChat:
    def __init__(self, agents, messages=[], max_round=500, speaker_selection_method=None):
        self.agents = agents  # List[ConversableAgent] - 所有参与的 Agent
        self.messages = []    # List[Dict] - 共享的消息历史（核心！）
        self.max_round = max_round
        self.speaker_selection_method = speaker_selection_method  # 状态转换函数

class GroupChatManager(ConversableAgent):
    def __init__(self, groupchat, llm_config=None):
        self.groupchat = groupchat
        super().__init__(llm_config=llm_config)
```

### 5.2 消息存储机制

#### 共享消息数组

```python
# GroupChat 内部
class GroupChat:
    def __init__(self):
        self.messages = []  # 独立的共享数组

# 消息格式
message = {
    "role": "assistant",  # 或 "user"
    "content": "消息内容",
    "name": "agent_name"  # 发送者名称
}
```

#### Agent 的 pairwise 消息存储

```python
# 每个 Agent 都有自己的 chat_messages 字典
class ConversableAgent:
    def __init__(self, name):
        self.name = name
        self.chat_messages = {}  # Dict[Agent, List[Message]]
        
        # 例如：
        # {
        #   <browser_nav_executor>: [msg1, msg2, ...],
        #   <user>: [msg3, msg4, ...]
        # }
```

### 5.3 消息同步机制

当 GroupChatManager "发送" 消息时，实际做了三件事：

```python
def add_message(message, sender, recipient):
    # ① 添加到共享数组
    groupchat.messages.append(message)
    
    # ② 拷贝到 sender 的 chat_messages
    sender.chat_messages[recipient].append(message.copy())  # 数据拷贝
    
    # ③ 拷贝到 recipient 的 chat_messages
    recipient.chat_messages[sender].append(message.copy())  # 数据拷贝
```

**关键点**：
- ❌ 不是指针/引用
- ✅ 是**实际的数据拷贝**
- ✅ 三个地方都有独立的消息副本

**为什么需要两份存储？**

| 存储位置 | 作用 | 优点 |
|---------|------|------|
| **GroupChat.messages** | 全局消息历史 | ✅ 所有 Agent 看到相同的上下文<br>✅ 便于 state_transition 决策 |
| **Agent.chat_messages** | Pairwise 对话历史 | ✅ 支持双边对话查询<br>✅ 兼容非 GroupChat 场景 |

---

## 6. 状态转换与路由

### 6.1 state_transition 函数

这是**最核心的路由逻辑**，决定下一个发言的 Agent：

```python
# simple_hercules.py - 第 354-372 行

def state_transition(last_speaker, groupchat) -> autogen.ConversableAgent | None:
    """
    根据最后一条消息和最后发言者，决定下一个发言的 Agent
    
    参数:
    - last_speaker: 最后发言的 Agent 对象
    - groupchat: GroupChat 对象，包含所有消息历史
    
    返回:
    - 下一个发言的 Agent 对象，或 None（终止对话）
    """
    
    # 从共享消息数组中获取最后一条消息
    last_message = groupchat.messages[-1]["content"]
    
    # 提取 target_helper 标记
    target_helper = extract_target_helper(last_message)
    
    # 规则 1：如果任务完成，终止对话
    if "##TERMINATE TASK##" in last_message.strip():
        return None
    
    # 规则 2：如果最后发言的是 User Agent，路由到对应的 Nav Agent
    if last_speaker is self.agents_map["user"]:
        if target_helper in nav_agents_names:
            return self.agents_map[f"{target_helper}_nav_agent"]
        return None
    
    # 规则 3：如果最后发言的是 Nav Agent，切换到对应的 Executor
    elif last_speaker in [self.agents_map[f"{agent_name}_nav_agent"] for agent_name in nav_agents_names]:
        # 获取基础名称（去掉 '_nav_agent' 后缀）
        base_name = last_speaker.name.rsplit("_nav_agent", 1)[0]
        return self.agents_map[f"{base_name}_nav_executor"]
    
    # 规则 4：如果最后发言的是 Executor，返回给 Nav Agent
    else:
        # 获取基础名称（去掉 '_nav_executor' 后缀）
        base_name = last_speaker.name.rsplit("_nav_executor", 1)[0]
        return self.agents_map[f"{base_name}_nav_agent"]
```

### 6.2 路由流程图

```
User Agent 发言
    ↓ (检测到 target_helper=browser)
Browser Nav Agent 发言
    ↓ (决定使用什么工具)
Browser Nav Executor 发言
    ↓ (执行 page.goto())
Browser Nav Agent 发言
    ↓ (分析执行结果)
User Agent 发言
    ↓ (总结并返回给 Planner)
Planner Agent 评估
    ↓ (决定下一步)
... 循环 ...
```

### 6.3 关键辅助函数

#### reflection_message（消息转换器）

```python
# simple_hercules.py - 第 312-337 行

def reflection_message(recipient, messages, sender, config):
    """将 Planner 的 JSON 响应转换为 Nav Agent 可理解的指令"""
    
    last_message = messages[-1]["content"]
    content_json = parse_response(last_message)
    
    next_step = content_json.get("next_step", None)
    target_helper = content_json.get("target_helper", "Not_Applicable")
    
    if next_step is None:
        logger.error("Message to nested chat returned None")
        return None
    
    # 如果是浏览器操作，添加当前 URL
    url = ""
    if "browser" in target_helper:
        url = get_url()
    
    # 构造最终消息，添加 target_helper 标记
    if target_helper.strip():
        next_step = next_step.strip() + " " + url + f" ##target_helper: {target_helper}##"
        
        # 查询历史记忆
        mem_fetch = asyncio.run(self._query_memory(next_step))
        
        actual_response = "\n\nTASK FOR HELPER: " + next_step
        if mem_fetch:
            actual_response += "\n\nSOME EXTRA INFORMATION: " + mem_fetch
        
        return actual_response
```

#### my_custom_summary_method（结果汇总）

```python
# simple_hercules.py - 第 261-310 行

def my_custom_summary_method(sender, recipient, summary_args={}):
    """汇总嵌套聊天的结果并返回给 Planner"""
    
    self.save_chat_log(sender, recipient)  # 保存日志
    
    # 获取最后一条消息
    if isinstance(recipient, autogen.GroupChatManager):
        last_message = recipient.last_message(recipient.last_speaker)["content"]
    else:
        last_message = recipient.last_message(sender)["content"]
    
    # 处理终止标记
    if "##TERMINATE TASK##" in last_message:
        last_message = last_message.replace("##TERMINATE TASK##", "")
        
        # 如果是浏览器操作，添加 URL
        if "browser" in recipient.last_speaker.name:
            last_message += " " + get_url()
        
        # 如果需要保存到记忆
        if "##FLAG::SAVE_IN_MEM##" in last_message:
            mem = "Context from execution: " + last_message
            self.save_to_memory(mem)
    
    # 通知 Planner 执行结果
    notify_planner_messages(
        last_message,
        message_type=MessageType.STEP,
        helper_name=target_helper,
        is_passed=is_passed,
        ...
    )
    
    return last_message  # 返回给 Planner
```

---

## 7. 完整执行流程

### 7.1 初始化阶段

```python
# runner.py - initialize()

async def initialize():
    # 1. 加载 Agent 配置
    config_manager = AgentsLLMConfigManager.get_instance()
    config_manager.initialize()
    
    planner_config = config_manager.get_agent_config("planner_agent")
    nav_config = config_manager.get_agent_config("nav_agent")
    mem_config = config_manager.get_agent_config("mem_agent")
    helper_config = config_manager.get_agent_config("helper_agent")
    
    # 2. 创建 SimpleHercules 实例
    simple_hercules = await SimpleHercules.create(
        stake_id,
        planner_config,
        nav_config,
        mem_config,
        helper_config,
        ...
    )
    
    # 3. 启动 Playwright 浏览器
    browser_manager = PlaywrightManager()
    await browser_manager.async_initialize()
```

### 7.2 Agent 创建阶段

```python
# simple_hercules.py - __initialize_agents()

async def __initialize_agents(self):
    agents_map = {}
    
    # 创建基础 Agent
    agents_map["mem_agent"] = self.__create_mem_agent()
    agents_map["helper_agent"] = self.__create_helper_agent()
    agents_map["user"] = await self.__create_user_delegate_agent()
    
    # 创建 Browser Agent 配对
    agents_map["browser_nav_executor"] = self.__create_browser_nav_executor_agent()
    agents_map["browser_nav_agent"] = self.__create_browser_nav_agent(
        agents_map["browser_nav_executor"]
    )
    
    # 创建 API Agent 配对
    agents_map["api_nav_executor"] = self.__create_api_nav_executor_agent()
    agents_map["api_nav_agent"] = self.__create_api_nav_agent(
        agents_map["api_nav_executor"]
    )
    
    # 创建其他 Agent 配对...
    agents_map["sec_nav_executor"] = self.__create_sec_nav_executor_agent()
    agents_map["sec_nav_agent"] = self.__create_sec_nav_agent(...)
    
    agents_map["sql_nav_executor"] = self.__create_sql_nav_executor_agent()
    agents_map["sql_nav_agent"] = self.__create_sql_nav_agent(...)
    
    agents_map["time_keeper_nav_executor"] = self.__create_time_keeper_nav_executor_agent()
    agents_map["time_keeper_nav_agent"] = self.__create_time_keeper_nav_agent(...)
    
    agents_map["mcp_nav_executor"] = self.__create_mcp_nav_executor_agent()
    agents_map["mcp_nav_agent"] = self.__create_mcp_nav_agent(...)
    
    agents_map["executor_nav_executor"] = self.__create_executor_nav_executor_agent()
    agents_map["executor_nav_agent"] = self.__create_executor_nav_agent(...)
    
    # 创建 Planner Agent（最后，因为它依赖 User Agent）
    agents_map["planner_agent"] = self.__create_planner_agent(agents_map["user"])
    
    return agents_map
```

### 7.3 GroupChat 设置阶段

```python
# simple_hercules.py - create() 方法中

# 1. 收集所有 Nav Agent 的名称
nav_agents_names = list(set([
    "_".join(agent_name.split("_")[:-2])
    for agent_name in self.agents_map.keys()
    if agent_name.endswith("_nav_agent") or agent_name.endswith("_nav_executor")
]))

# 2. 构建 GroupChat 参与者列表
group_participants_names = [
    f"{agent_name}_nav_agent" for agent_name in nav_agents_names
] + [
    f"{agent_name}_nav_executor" for agent_name in nav_agents_names
]

# 3. 创建 GroupChat
groupchat = autogen.GroupChat(
    agents=[self.agents_map[agent_name] for agent_name in group_participants_names],
    messages=[],
    max_round=self.planner_number_of_rounds,
    speaker_selection_method=state_transition,  # 自定义路由函数
)

# 4. 创建 GroupChatManager
manager = autogen.GroupChatManager(
    groupchat=groupchat,
    llm_config=gm_llm_config,
)

# 5. 注册嵌套聊天
self.agents_map["user"].register_nested_chats(
    [
        {
            "chat_id": uuid.uuid4(),
            "sender": self.agents_map["user"],
            "recipient": manager,
            "message": reflection_message,
            "max_turns": 1,
            "summary_method": my_custom_summary_method,
        }
    ],
    trigger=trigger_nested_chat,
    cache=cache,
)
```

### 7.4 命令执行阶段

```python
# simple_hercules.py - process_command()

async def process_command(self, command: str, current_url: str = None):
    """处理测试用例命令"""
    
    # 1. 构造提示词
    current_url_prompt_segment = ""
    if current_url:
        current_url_prompt_segment = f"Current Page: {current_url}"
    
    prompt = Template(LLM_PROMPTS["COMMAND_EXECUTION_PROMPT"]).substitute(
        command=command,
        current_url_prompt_segment=current_url_prompt_segment
    )
    
    # 2. 查询历史记忆（如果启用）
    config = get_global_conf()
    if config.should_use_dynamic_ltm():
        mem_fetch = await self._query_memory(prompt)
        prompt += "\n\nEXTRA INFORMATION: " + mem_fetch
    
    # 3. 发送给 Planner Agent，触发整个流程
    result = await self.agents_map["user"].initiate_chat(
        self.agents_map["planner_agent"],
        message=prompt
    )
    
    return result
```

---

## 8. 关键技术点

### 8.1 Nested Chat 机制

**作用**：隔离 Planner 和 Nav Agents 的对话上下文

```python
# 注册嵌套聊天
user_agent.register_nested_chats(
    [
        {
            "chat_id": uuid.uuid4(),
            "sender": user_agent,
            "recipient": groupchat_manager,
            "message": reflection_message,  # 消息转换函数
            "max_turns": 1,
            "summary_method": my_custom_summary_method,  # 结果汇总函数
        }
    ],
    trigger=trigger_nested_chat,  # 触发条件
)
```

**工作流程**：
1. User Agent 收到 Planner 的消息
2. `trigger_nested_chat` 判断是否启动嵌套聊天
3. 如果触发，调用 `reflection_message` 转换消息
4. 将转换后的消息发送给 GroupChatManager
5. GroupChat 内部进行多轮对话
6. 对话结束后，调用 `my_custom_summary_method` 汇总结果
7. 将汇总结果返回给 User Agent
8. User Agent 再返回给 Planner

### 8.2 消息访问方法

```python
# 访问消息历史

# 方法 1：通过 GroupChat
last_message = groupchat.messages[-1]

# 方法 2：通过 Agent 的 chat_messages
messages = agent.chat_messages[other_agent]

# 方法 3：通过 last_message() 方法
last_msg = agent.last_message(other_agent)

# 方法 4：在 GroupChatManager 中
last_msg = manager.last_message(manager.last_speaker)
```

### 8.3 工具调用机制

Nav Executor 是 **UserProxyAgent_SequentialFunctionExecution**，它会自动执行可用的工具函数：

```python
def __create_browser_nav_executor_agent(self):
    browser_nav_executor_agent = UserProxyAgent_SequentialFunctionExecution(
        name="browser_nav_executor",
        is_termination_msg=is_browser_executor_termination_message,
        human_input_mode="NEVER",  # 不需要人工输入
        llm_config=None,  # Executor 不使用 LLM
        max_consecutive_auto_reply=self.nav_agent_number_of_rounds,
        code_execution_config={
            "last_n_messages": 1,
            "work_dir": "tasks",
            "use_docker": False,
        },
    )
    return browser_nav_executor_agent
```

**工具调用流程**：
```python
# Nav Agent 发送消息
"点击登录按钮"

# Executor 自动匹配工具
click(element_selector="#login-btn")

# Playwright 执行
await page.click("#login-btn")

# 返回结果
"Clicked element: #login-btn"
```

### 8.4 记忆管理机制

```python
# 保存记忆
if "##FLAG::SAVE_IN_MEM##" in last_message:
    mem = "Context from execution: " + last_message
    self.save_to_memory(mem)
    store_run_data(mem)

# 查询记忆
mem_fetch = await self._query_memory(context)
if mem_fetch:
    prompt += "\n\nEXTRA INFORMATION: " + mem_fetch
```

---

## 9. 数据结构详解

### 9.1 内存中的数据结构示意图

```
┌─────────────────────────────────────────────────────────┐
│                   GroupChat                             │
│                                                         │
│  agents = [                                             │
│    <user>,                                              │
│    <browser_nav_agent>,                                 │
│    <browser_nav_executor>,                              │
│    ...                                                  │
│  ]                                                      │
│                                                         │
│  messages = [  ← 共享消息数组（核心！）                  │
│    {                                                    │
│      "role": "assistant",                               │
│      "content": "TASK FOR HELPER: 打开百度...",          │
│      "name": "user"                                     │
│    },                                                   │
│    {                                                    │
│      "role": "assistant",                               │
│      "content": "我将使用 page.goto()...",              │
│      "name": "browser_nav_agent"                        │
│    },                                                   │
│    ...                                                  │
│  ]                                                      │
└─────────────────────────────────────────────────────────┘
         ↓ 同步更新
         
┌─────────────────────────────────────────────────────────┐
│              User Agent                                 │
│                                                         │
│  chat_messages = {                                      │
│    <GroupChatManager>: [                                │
│      {"role": "assistant", "content": "...", ...},      │
│      {"role": "user", "content": "...", ...}            │
│    ]                                                    │
│  }                                                      │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│           Browser Nav Agent                             │
│                                                         │
│  chat_messages = {                                      │
│    <GroupChatManager>: [                                │
│      {"role": "user", "content": "TASK FOR HELPER...",  │
│       "name": "user"},                                  │
│      {"role": "assistant", "content": "我将使用...",    │
│       "name": "browser_nav_agent"}                      │
│    ],                                                   │
│    <browser_nav_executor>: [...]                        │
│  }                                                      │
└─────────────────────────────────────────────────────────┘
```

### 9.2 消息流转示例

以"打开百度首页"为例：

```
Round 1: Planner → User
┌────────────────────────────────────────────┐
│ Planner Agent 输出:                         │
│ {                                          │
│   "next_step": "打开 https://www.baidu.com",│
│   "target_helper": "browser"               │
│ }                                          │
└────────────────────────────────────────────┘
         ↓ trigger_nested_chat 触发
         
Round 2: User → GroupChatManager
┌────────────────────────────────────────────┐
│ reflection_message 转换:                    │
│ "TASK FOR HELPER: 打开 https://www.baidu.com│
│  ##target_helper: browser##"               │
└────────────────────────────────────────────┘
         ↓ state_transition 路由
         
Round 3: GroupChatManager → Browser Nav Agent
┌────────────────────────────────────────────┐
│ Browser Nav Agent 理解指令:                 │
│ "需要打开百度首页"                           │
└────────────────────────────────────────────┘
         ↓ state_transition 路由
         
Round 4: Browser Nav Agent → Browser Executor
┌────────────────────────────────────────────┐
│ Browser Nav Agent 决定:                     │
│ "调用 openurl 工具"                         │
└────────────────────────────────────────────┘
         ↓ Executor 自动执行工具
         
Round 5: Browser Executor 执行
┌────────────────────────────────────────────┐
│ Browser Executor 调用:                      │
│ await page.goto("https://www.baidu.com")   │
│                                            │
│ 返回: "Page loaded: https://www.baidu.com" │
└────────────────────────────────────────────┘
         ↓ state_transition 路由
         
Round 6: Browser Executor → Browser Nav Agent
┌────────────────────────────────────────────┐
│ Browser Nav Agent 分析结果:                 │
│ "页面加载成功，标题：百度一下"                │
│ 添加标记: "##TERMINATE TASK##"             │
└────────────────────────────────────────────┘
         ↓ state_transition 检测到终止标记
         
Round 7: Browser Nav Agent → User
┌────────────────────────────────────────────┐
│ my_custom_summary_method 汇总:              │
│ "百度首页已打开，标题：百度一下"              │
└────────────────────────────────────────────┘
         ↓ 返回给 Planner
         
Round 8: User → Planner
┌────────────────────────────────────────────┐
│ Planner 收到结果，评估:                      │
│ "第一步完成，生成下一步指令"                  │
└────────────────────────────────────────────┘
```

---

## 10. 实战示例

### 10.1 完整测试用例执行

**测试用例**：
```gherkin
Feature: Open Baidu and search

  Scenario: User searches for AI testing
    Given I navigate to "https://www.baidu.com"
    When I enter "AI 测试" in the search box
    And I click the search button
    Then I should see search results
```

**执行流程**：

```
Step 1: Planner 解析测试用例
┌────────────────────────────────────────────────┐
│ Plan:                                          │
│ 1. 导航到百度首页                               │
│ 2. 输入搜索词 "AI 测试"                        │
│ 3. 点击搜索按钮                                 │
│ 4. 验证搜索结果                                 │
│                                                │
│ next_step: "导航到 https://www.baidu.com"      │
│ target_helper: "browser"                       │
│ terminate: "no"                                │
└────────────────────────────────────────────────┘

Step 2: Browser Nav Agent 执行导航
┌────────────────────────────────────────────────┐
│ Task: "导航到 https://www.baidu.com"           │
│ Action: page.goto("https://www.baidu.com")     │
│ Result: "Page loaded, Title: 百度一下"         │
└────────────────────────────────────────────────┘

Step 3: Planner 评估并生成下一步
┌────────────────────────────────────────────────┐
│ next_step: "在搜索框输入 'AI 测试'"            │
│ target_helper: "browser"                       │
└────────────────────────────────────────────────┘

Step 4: Browser Nav Agent 执行输入
┌────────────────────────────────────────────────┐
│ Task: "在搜索框输入 'AI 测试'"                 │
│ Action: page.fill("#kw", "AI 测试")            │
│ Result: "Text entered successfully"            │
└────────────────────────────────────────────────┘

Step 5: Planner 生成下一步
┌────────────────────────────────────────────────┐
│ next_step: "点击搜索按钮"                       │
│ target_helper: "browser"                       │
└────────────────────────────────────────────────┘

Step 6: Browser Nav Agent 执行点击
┌────────────────────────────────────────────────┐
│ Task: "点击搜索按钮"                            │
│ Action: page.click("#su")                      │
│ Result: "Button clicked"                       │
└────────────────────────────────────────────────┘

Step 7: Planner 生成验证步骤
┌────────────────────────────────────────────────┐
│ next_step: "验证搜索结果页面包含相关内容"       │
│ target_helper: "browser"                       │
│ is_assert: true                                │
└────────────────────────────────────────────────┘

Step 8: Browser Nav Agent 执行验证
┌────────────────────────────────────────────────┐
│ Task: "验证搜索结果"                            │
│ Action: page.text_content("body")              │
│ Assertion: "AI 测试" in content                │
│ Result: "Assertion passed"                     │
└────────────────────────────────────────────────┘

Step 9: Planner 终止任务
┌────────────────────────────────────────────────┐
│ terminate: "yes"                               │
│ final_response: "测试通过"                      │
│ is_passed: true                                │
└────────────────────────────────────────────────┘
```

### 10.2 错误处理示例

**场景**：页面加载失败

```
Step 1: Browser Executor 尝试导航
┌────────────────────────────────────────────────┐
│ Action: page.goto("https://invalid-url.com")   │
│ Error: "net::ERR_NAME_NOT_RESOLVED"            │
└────────────────────────────────────────────────┘
         ↓
         
Step 2: Browser Nav Agent 分析错误
┌────────────────────────────────────────────────┐
│ Response:                                      │
│ "无法访问该网址，DNS 解析失败"                  │
│ ##TERMINATE TASK##                             │
└────────────────────────────────────────────────┘
         ↓
         
Step 3: Planner 评估失败
┌────────────────────────────────────────────────┐
│ terminate: "yes"                               │
│ final_response: "测试失败：无法访问目标网址"    │
│ is_passed: false                               │
│ assert_summary: "EXPECTED: 页面加载成功        │
│                 ACTUAL: DNS 解析失败"           │
└────────────────────────────────────────────────┘
```

---

## 📊 总结

### 核心设计理念

1. **分层架构**：Planner（战略）→ Nav Agents（战术）→ Executors（执行）
2. **关注点分离**：Planner 决定 WHAT，Nav Agents 决定 HOW，Executors 执行 DO
3. **共享消息历史**：GroupChat.messages 确保所有 Agent 看到一致的上下文
4. **智能路由**：state_transition 函数自动决定下一个发言者
5. **配置共享**：所有 Nav Agents 共享同一个配置，简化管理

### 关键技术

| 技术 | 作用 |
|------|------|
| **GroupChat** | 管理多 Agent 对话 |
| **state_transition** | 自动路由消息 |
| **register_nested_chats** | 嵌套聊天，隔离上下文 |
| **reflection_message** | 消息转换和增强 |
| **my_custom_summary_method** | 结果汇总和返回 |
| **trigger_nested_chat** | 控制何时启动嵌套聊天 |
| **chat_messages** | 存储历史消息 |
| **last_message** | 获取最后一条消息 |

### 优势

- ✅ **可扩展性**：新增测试类型只需添加新的 Nav Agent + Executor 配对
- ✅ **容错性**：每个步骤都有验证和断言
- ✅ **灵活性**：Planner 可以根据执行结果动态调整计划
- ✅ **一致性**：所有 Nav Agents 使用相同配置，行为风格一致
- ✅ **可追溯性**：完整的消息历史记录，便于调试和分析

---

**文档版本**: v1.0  
**最后更新**: 2026-05-18  
**适用项目**: TestZeus Hercules
