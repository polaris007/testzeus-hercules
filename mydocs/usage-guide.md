# TestZeus Hercules 使用指南

## 📋 目录

- [1. 项目概述](#1-项目概述)
- [2. 输入文件处理机制](#2-输入文件处理机制)
- [3. Gherkin 文件处理流程](#3-gherkin-文件处理流程)
- [4. 测试数据（test_data）使用](#4-测试数据test_data使用)
- [5. 多 Agent 调度与通信](#5-多-agent-调度与通信)
- [6. 内网环境配置](#6-内网环境配置)
- [7. 常见问题与最佳实践](#7-常见问题与最佳实践)

---

## 1. 项目概述

TestZeus Hercules 是一个基于 AI 的端到端自动化测试框架，使用以下核心技术：

- **Playwright**：浏览器自动化工具
- **AutoGen/AG2**：多智能体协作框架
- **Gherkin BDD**：测试用例描述语言
- **LLM（大语言模型）**：智能理解和执行测试

### 核心架构

```
用户输入 (Gherkin Feature)
    ↓
Planner Agent（规划器 - 大脑）
    ↓
Nav Agents（导航代理 - 战术层）
    ↓
Executors（执行器 - 执行层）
    ↓
测试结果报告
```

---

## 2. 输入文件处理机制

### 2.1 单文件模式（默认）

**目录结构**：
```
opt/
└── input/
    └── test.feature    # ← 只处理这一个文件
```

**运行命令**：
```bash
python -m testzeus_hercules
```

**特点**：
- ✅ 只处理 `input/test.feature` 单个文件
- ❌ 不会自动扫描 input 目录下的其他 `.feature` 文件
- ✅ 如果一个 feature 文件包含多个 Scenario，会拆分成多个测试用例执行

---

### 2.2 命令行指定文件

**运行命令**：
```bash
python -m testzeus_hercules --input-file ./my_tests/login.feature
```

**特点**：
- ✅ 可以指定任意路径的单个 `.feature` 文件
- ❌ 仍然只能处理一个文件

---

### 2.3 批量模式（--bulk）⭐ 推荐用于多文件

**目录结构要求**：
```
tests/
├── login_test/                    # 文件夹名
│   ├── input/
│   │   └── login_test.feature     # ← 文件名必须与文件夹名相同！
│   └── test_data/
│       └── test_data.txt
├── search_functionality/          # 文件夹名
│   ├── input/
│   │   └── search_functionality.feature  # ← 文件名必须与文件夹名相同！
│   └── test_data/
└── checkout_process/              # 文件夹名
    ├── input/
    │   └── checkout_process.feature      # ← 文件名必须与文件夹名相同！
    └── test_data/
```

**运行命令**：
```bash
python -m testzeus_hercules --bulk
```

**代码逻辑**：
```python
# __main__.py - process_test_directory()
test_dir_name = os.path.basename(test_dir)
test_config = {
    "PROJECT_SOURCE_ROOT": test_dir,
    "INPUT_GHERKIN_FILE_PATH": os.path.join(
        test_dir, "input", f"{test_dir_name}.feature"  # ← 强制使用文件夹名
    ),
    "TEST_DATA_PATH": os.path.join(test_dir, "test_data"),
}
```

**重要提醒**：
- ⚠️ **.feature 文件名必须与文件夹名完全一致**
- ❌ 错误的命名会导致文件找不到，执行失败

---

### 2.4 为什么不支持 input 目录下多个 .feature 文件？

**当前设计原因**：
1. **简化配置管理**：单一入口点，避免歧义
2. **明确的执行顺序**：批量模式下按目录遍历，顺序可控
3. **隔离测试上下文**：每个测试用例有独立的 test_data

**如果想处理多个文件**：
- ✅ **方案 1**：将所有 Scenario 写到一个 `test.feature` 文件中
- ✅ **方案 2**：使用 `--bulk` 模式，按规范组织目录结构

---

## 3. Gherkin 文件处理流程

### 3.1 两阶段处理架构

```
┌─────────────────────────────────────────────────────────┐
│  阶段 1: 预处理（gherkin_helper.py）                     │
│  - split_feature_file()                                 │
│  - serialize_feature_file()                             │
│                                                          │
│  【纯文本处理，不理解语义】                                │
└──────────────────────┬──────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────┐
│  阶段 2: 智能理解（Planner Agent）                       │
│  - high_level_planner_agent.py                          │
│  - LLM 推理和理解                                        │
│                                                          │
│  【真正的智能化处理】                                      │
└─────────────────────────────────────────────────────────┘
```

---

### 3.2 阶段 1：预处理（机械转换）

#### **split_feature_file()**

**功能**：将单个 feature 文件拆分成多个 scenario 文件

**处理步骤**：
1. 读取原始 feature 文件内容
2. 使用正则表达式找到所有 Scenario
3. 按 Scenario 分割文件
4. 提取 Feature 头部（Feature: xxx）
5. 处理注释行（# 开头的行）
6. 处理重复的 Scenario 名称
7. 为每个 Scenario 生成独立的 .feature 文件
8. 保存到 `tmp_gherkin` 目录

**示例**：

**输入** (`opt/input/test.feature`)：
```gherkin
Feature: Open Baidu and search

  Scenario: User opens Baidu homepage
    Given I navigate to "https://www.baidu.com"
    Then I should see the Baidu homepage

  Scenario: User searches for AI testing
    When I enter "AI 测试" in the search box
    And I click the search button
    Then I should see search results
```

**输出**：
```
opt/tmp_gherkin/
├── User_opens_Baidu_homepage.feature
└── User_searches_for_AI_testing.feature
```

---

#### **serialize_feature_file()**

**功能**：将拆分后的场景文件转换成单行命令字符串

**处理步骤**：
1. 读取场景文件内容
2. 移除 `;skip;` 标记后的内容
3. 压缩多余的空格和空行
4. 将换行符替换为 ` ;next; `

**示例**：

**输入**：
```gherkin
Feature: Login Test
  Scenario: User login
    Given I navigate to "/login"
    When I enter credentials
    Then I should be logged in
```

**输出**：
```
Feature: Login Test ;next; Scenario: User login ;next; Given I navigate to "/login" ;next; When I enter credentials ;next; Then I should be logged in
```

---

### 3.3 特殊功能

#### **`;skip;` 标记**

允许在测试用例中添加调试信息或注释，执行时会自动忽略：

```gherkin
Scenario: Test with skip marker
  Given I navigate to "https://example.com" ;skip; this is a comment
  When I click login
  Then I should be logged in
```

**处理后**：
```
Given I navigate to "https://example.com" ;next; When I click login ;next; Then I should be logged in
```

---

#### **`dont_append_header` 参数**

控制是否在每个场景文件中都包含 Feature 头部：

- **True**：只有第一个场景文件包含 Feature 头部
- **False**：所有场景文件都包含 Feature 头部

---

### 3.4 阶段 2：智能理解（Planner Agent）

**这是真正的智能化处理！**

**Planner Agent 会做的事情**：

| 功能 | 说明 | 示例 |
|------|------|------|
| **解析 Gherkin** | 理解 BDD 语义 | `Given I navigate to "https://baidu.com"` → 理解为"打开百度首页" |
| **生成详细计划** | 将模糊的步骤细化 | `When I click button` → `"找到登录按钮并点击，然后验证页面跳转到个人中心"` |
| **补充缺失步骤** | 添加必要的上下文 | 自动添加"等待页面加载完成"的步骤 |
| **添加断言** | 补充验证逻辑 | `Then it works` → `"验证页面上显示'操作成功'的提示消息"` |
| **处理数据驱动** | 分析测试数据 | 根据 test_data.txt 生成多次迭代的测试计划 |
| **条件分支** | 处理不同场景 | 如果元素不存在，尝试备用方案 |

---

### 3.5 关键区别总结

| 维度 | gherkin_helper.py | Planner Agent |
|------|------------------|---------------|
| **处理方式** | 规则-based（正则表达式、字符串替换） | AI-based（LLM 推理） |
| **是否理解语义** | ❌ 否 | ✅ 是 |
| **是否优化内容** | ❌ 否 | ✅ 是 |
| **是否补充细节** | ❌ 否 | ✅ 是 |
| **是否添加断言** | ❌ 否 | ✅ 是 |
| **是否处理数据** | ❌ 否 | ✅ 是 |
| **执行时机** | 预处理阶段（启动时） | 运行时（每个步骤） |
| **依赖** | 无（纯 Python） | LLM API（需要配置模型） |
| **速度** | 快（毫秒级） | 慢（秒级，取决于 LLM） |

---

## 4. 测试数据（test_data）使用

### 4.1 数据加载机制

**加载时机**：系统启动时

**加载流程**：
```
系统启动
    ↓
StaticLTM._initialize()
    ↓
load_data() - 读取 test_data 目录下的所有文件
    ↓
合并成一个字符串
    ↓
注入到所有 Agent 的系统提示词中
```

---

### 4.2 支持的文件格式

| 扩展名 | 处理方式 | 示例 |
|--------|---------|------|
| `.txt` | 纯文本，清理空行 | `test_data.txt` |
| `.json` | 解析 JSON，压缩格式 | `users.json` |
| `.yaml` / `.yml` | 解析 YAML，压缩格式 | `config.yaml` |
| `.csv` | 作为纯文本处理 | `data.csv` |
| `.rft` | 作为纯文本处理 | `template.rft` |

**注意**：其他格式的文件会被跳过。

---

### 4.3 文件处理逻辑

#### **TXT/CSV/RFT 文件**

**处理**：移除冗余的空行

**示例输入** (`test_data.txt`)：
```txt
username: admin
password: 123456

email: test@example.com


phone: 1234567890
```

**处理后**：
```
following is test_data from TEST_DATA_TXT
username: admin
password: 123456
email: test@example.com
phone: 1234567890
```

---

#### **JSON 文件**

**处理**：解析 JSON，然后用最小分隔符压缩

**示例输入** (`users.json`)：
```json
{
  "users": [
    {
      "username": "admin",
      "password": "123456"
    }
  ]
}
```

**处理后**：
```
following is test_data from USERS_JSON
{"users":[{"username":"admin","password":"123456"}]}
```

---

#### **YAML 文件**

**处理**：解析 YAML，然后用最小格式输出

**示例输入** (`config.yaml`)：
```yaml
database:
  host: localhost
  port: 5432
```

**处理后**：
```
following is test_data from CONFIG_YAML
{database: {host: localhost, port: 5432}}
```

---

### 4.4 文件名标准化

文件名会被转换成大写，并替换特殊字符为下划线：

```python
sanitized_filename = (
    filename.replace(".", "_")
    .replace(" ", "_")
    .replace("-", "_")
    .upper()
)
```

**示例**：
- `test-data.json` → `TEST_DATA_JSON`
- `user credentials.txt` → `USER_CREDENTIALS_TXT`

---

### 4.5 数据注入到 Agent

**注入方式**：通过模板替换

```python
# base_nav_agent.py
user_ltm = get_user_ltm()  # 获取测试数据
system_message = Template(system_prompt).substitute(
    basic_test_information=user_ltm
)
```

**最终效果**：

所有 Agent 的系统提示词末尾都会包含：

```python
"""
你是浏览器自动化专家...
[其他提示词内容]

Available Test Data: 
following is test_data from TEST_DATA_TXT
username: admin
password: 123456

following is test_data from USERS_JSON
{"users":[{"username":"admin","password":"123456"}]}

helper_spec_file_paths: /path/to/users.json
"""
```

---

### 4.6 在测试用例中使用 test_data

#### **方式 A：直接描述（推荐）**

**test_data/credentials.json**：
```json
{
  "admin": {
    "username": "admin",
    "password": "Admin@123"
  }
}
```

**input/test.feature**：
```gherkin
Feature: User Login Test

  Scenario: Admin user logs in successfully
    Given I navigate to the login page
    When I enter username "admin" and password "Admin@123"
    And I click the login button
    Then I should see the admin dashboard
```

**Planner Agent 会自动从 test_data 中看到这些数据**，并在执行时使用正确的凭据。

---

#### **方式 B：明确提及数据来源**

```gherkin
Feature: User Login Test

  Scenario: Admin user logs in using credentials from test data
    Given I navigate to the login page
    When I use the admin credentials from test_data to log in
    Then I should be logged in successfully
```

**Planner 会理解你的意图**，从 test_data 中提取 admin 的凭据并使用。

---

#### **方式 C：数据驱动测试（多个用户）**

```gherkin
Feature: Multiple User Login Tests

  Scenario: Admin user logs in
    Given I navigate to the login page
    When I enter username "admin" and password "Admin@123"
    Then I should see the admin dashboard

  Scenario: Normal user logs in
    Given I navigate to the login page
    When I enter username "user1" and password "User@456"
    Then I should see the user homepage
```

---

### 4.7 完整示例

#### **目录结构**

```
opt/
├── input/
│   └── test.feature
└── test_data/
    ├── credentials.json
    └── api_config.yaml
```

---

#### **test_data/credentials.json**

```json
{
  "admin": {
    "username": "admin",
    "password": "Admin@123",
    "role": "administrator"
  },
  "user": {
    "username": "testuser",
    "password": "Test@456",
    "role": "regular_user"
  }
}
```

---

#### **test_data/api_config.yaml**

```yaml
base_url: https://api.example.com
endpoints:
  login: /auth/login
  profile: /api/profile
headers:
  Content-Type: application/json
  Accept: application/json
```

---

#### **input/test.feature**

```gherkin
Feature: User Authentication and Profile Access

  Scenario: Admin logs in and accesses profile
    Given I navigate to the login page at "https://app.example.com"
    When I enter the admin username and password from test data
    And I click the login button
    Then I should see the admin dashboard
    And I should see my role displayed as "administrator"

  Scenario: Regular user logs in via API
    Given I have the API base URL from test data
    When I send a POST request to the login endpoint with user credentials
    Then I should receive a successful authentication response
    And the response should contain an access token
```

---

### 4.8 最佳实践建议

1. **集中管理测试数据**：将所有测试相关的数据放在 `test_data` 目录下
2. **使用结构化格式**：优先使用 JSON/YAML，便于 Agent 理解
3. **命名清晰**：文件名要有意义，如 `login_credentials.json`
4. **避免过大文件**：LLM 上下文窗口有限，不要放入过多数据
5. **数据分类**：可以按功能拆分多个文件，如 `users.json`、`products.json`、`config.yaml`
6. **敏感数据处理**：
   - ❌ **不要**在生产环境使用真实密码
   - ✅ **使用**测试环境的专用凭据
   - ✅ **考虑**使用环境变量或密钥管理服务

---

## 5. 多 Agent 调度与通信

### 5.1 Agent 角色与职责

| Agent 名称 | 角色 | 职责 |
|-----------|------|------|
| **Planner Agent** | 🧠 大脑 | 解析测试用例、生成计划、决策下一步 |
| **User Agent** | 📨 协调者 | 路由消息、协调 Agent 间通信 |
| **Browser Nav Agent** | 🌐 浏览器专家 | 理解浏览器操作指令 |
| **Browser Nav Executor** | ⚙️ 浏览器执行器 | 执行浏览器自动化操作 |
| **API Nav Agent** | 🔌 API 专家 | 理解 API 测试指令 |
| **API Nav Executor** | ⚙️ API 执行器 | 发送 HTTP 请求 |
| **SQL Nav Agent** | 💾 数据库专家 | 理解数据库查询指令 |
| **Security Nav Agent** | 🔒 安全专家 | 理解安全测试指令 |
| **Time Keeper Nav Agent** | ⏰ 时间管理 | 处理时间相关操作 |
| **MCP Nav Agent** | 🔧 MCP 工具 | 调用 MCP 服务器工具 |
| **Executor Nav Agent** | 📜 脚本执行 | 执行 Python 脚本 |
| **Memory Agent** | 🧠 记忆管理 | 存储和检索测试上下文 |

---

### 5.2 Agent 配置共享机制

**重要特性**：所有导航 Agent 共享同一个 `nav_agent` 配置！

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

### 5.3 消息传递机制

#### **三种消息传递方式**

1. **GroupChat + state_transition**（主要方式）
   - 自动路由：User → Nav Agent → Executor → ...

2. **Nested Chat**（嵌套聊天）
   - User Agent ↔ GroupChat Manager

3. **register_reply**（回调函数）
   - 自定义消息处理和返回逻辑

---

### 5.4 GroupChat 工作原理

#### **共享消息数组**

```python
# GroupChat 内部
class GroupChat:
    def __init__(self):
        self.messages = []  # 独立的共享数组
```

#### **Agent 的 pairwise 消息存储**

```python
# 每个 Agent 都有自己的 chat_messages 字典
class ConversableAgent:
    def __init__(self, name):
        self.name = name
        self.chat_messages = {}  # Dict[Agent, List[Message]]
```

#### **消息同步机制**

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

---

### 5.5 状态转换与路由

#### **state_transition 函数**

这是**最核心的路由逻辑**，决定下一个发言的 Agent：

```python
def state_transition(last_speaker, groupchat):
    """
    根据最后一条消息和最后发言者，决定下一个发言的 Agent
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
        base_name = last_speaker.name.rsplit("_nav_agent", 1)[0]
        return self.agents_map[f"{base_name}_nav_executor"]
    
    # 规则 4：如果最后发言的是 Executor，返回给 Nav Agent
    else:
        base_name = last_speaker.name.rsplit("_nav_executor", 1)[0]
        return self.agents_map[f"{base_name}_nav_agent"]
```

---

### 5.6 路由流程图

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

---

### 5.7 特殊标记

| 标记 | 作用 | 示例 |
|------|------|------|
| `##target_helper: browser##` | 路由标记，指定目标 Helper | 用于 state_transition |
| `##TERMINATE TASK##` | 终止标记，结束当前任务 | 表示步骤完成 |
| `##FLAG::SAVE_IN_MEM##` | 记忆标记，保存到长期记忆 | 用于跨步骤上下文 |

---

## 6. 内网环境配置

### 6.1 网络限制问题

在内网环境下，外网网站可能无法访问，导致以下问题：

1. **浏览器验证步骤超时**：Planner 尝试打开 Google.com 或 example.com 来验证浏览器可用性
2. **LLM API 不可达**：如果使用外部的 LLM 服务
3. **资源加载失败**：CDN、外部图片等

---

### 6.2 解决方案

#### **方案 1：修改测试用例（推荐）**

去掉 `Given I have a web browser open` 这一行：

```gherkin
# 修改前
Feature: Open 百度 homepage
  Scenario: User opens Baidu homepage
    Given I have a web browser open  # ← 删除这一行
    When I navigate to "https://www.baidu.com"
    Then I should see the Baidu homepage

# 修改后
Feature: Open 百度 homepage
  Scenario: User opens Baidu homepage
    When I navigate to "https://www.baidu.com"
    Then I should see the Baidu homepage
```

**原因**：Planner 看到 `Given I have a web browser open` 后，会自动生成验证浏览器的步骤，并尝试打开外网网站来验证。

---

#### **方案 2：修改 Planner 系统提示词**

在 `high_level_planner_agent.py` 的 prompt 中添加内网环境说明：

```python
prompt = """# Test Execution Task Planner

## Network Environment Constraints
- IMPORTANT: This system may be running in an INTRANET/INTERNAL NETWORK environment
- DO NOT assume external websites (google.com, example.com, etc.) are accessible
- When verifying browser readiness, ONLY use the target URL specified in the test case
- NEVER attempt to open external validation URLs unless explicitly specified in the test
- If browser initialization is needed, directly navigate to the test target URL

[原有提示词内容...]
"""
```

---

#### **方案 3：在测试数据中指定内网可用的验证URL**

**test_data/config.yaml**：
```yaml
browser_validation_url: http://intranet.example.com/health
```

然后在测试用例中引用这个配置。

---

### 6.3 LLM API 配置

#### **ModelScope（魔搭社区）配置示例**

**agents_llm_config.json**：
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
      }
    }
  ]
}
```

**重要提醒**：
- ⚠️ **必须包含 `model_api_type` 字段**，否则 AutoGen 无法识别
- ✅ 设置合理的 `timeout`（推荐 180 秒）
- ✅ 设置 `max_retries`（推荐 5 次）

---

### 6.4 环境变量配置

#### **浏览器分辨率**

```bash
# ✅ 正确的方式
export BROWSER_RESOLUTION=1920,1080

# ❌ 错误的方式（不支持）
export BROWSER_WIDTH=1920
export BROWSER_HEIGHT=1080
```

**格式**：`宽度,高度`（逗号分隔，无空格）

---

#### **其他常用环境变量**

```bash
# LLM 配置
export LLM_MODEL_NAME="deepseek-ai/DeepSeek-V3.2"
export LLM_MODEL_API_KEY="your-api-key"
export LLM_MODEL_BASE_URL="https://api-inference.modelscope.cn/v1"

# 浏览器配置
export BROWSER_TYPE="chromium"
export HEADLESS="false"
export RECORD_VIDEO="true"

# 项目路径
export PROJECT_SOURCE_ROOT="./opt"
export INPUT_GHERKIN_FILE_PATH="./opt/input/test.feature"
export TEST_DATA_PATH="./opt/test_data"
```

---

## 7. 常见问题与最佳实践

### 7.1 常见问题

#### **Q1: 为什么程序要验证 browser 是否可用？**

**A**: 这是 Planner Agent 根据测试用例自动生成的步骤，不是代码写死的。当测试用例包含 `Given I have a web browser open` 时，Planner 会生成验证步骤，并尝试打开一个"可靠的网站"（通常是外网网站）来验证浏览器可用性。

**解决方案**：去掉 `Given I have a web browser open` 这一行。

---

#### **Q2: input 目录下可以放多个 .feature 文件吗？**

**A**: 默认情况下，只会处理 `test.feature` 这一个文件。如果要处理多个文件，需要使用 `--bulk` 模式，并按照规范的目录结构组织文件。

---

#### **Q3: test_data 文件是如何被使用的？**

**A**: 
1. 系统启动时，`load_data()` 函数读取 `test_data` 目录下的所有文件
2. 文件内容被合并成一个字符串
3. 通过模板替换注入到所有 Agent 的系统提示词中
4. Agent 在执行测试时，可以从提示词中看到这些数据并使用

---

#### **Q4: 可以在 test.feature 中引用 test_data 文件的内容吗？**

**A**: 是的！你可以用自然语言描述，例如：
```gherkin
When I use the admin credentials from test_data to log in
```
Planner Agent 会自动从 test_data 中提取相应的数据并使用。

---

#### **Q5: 批量模式下，.feature 文件名必须和文件夹名一致吗？**

**A**: 是的，必须完全一致。代码逻辑强制使用文件夹名作为文件名：
```python
test_dir_name = os.path.basename(test_dir)
INPUT_GHERKIN_FILE_PATH = os.path.join(test_dir, "input", f"{test_dir_name}.feature")
```

---

### 7.2 最佳实践

#### **1. 编写清晰的 Gherkin 测试用例**

```gherkin
# ✅ 好的写法
Scenario: Admin user logs in successfully
  Given I navigate to the login page at "https://app.example.com"
  When I enter username "admin" and password "Admin@123"
  And I click the login button
  Then I should see the admin dashboard with welcome message

# ❌ 不好的写法（模糊不清）
Scenario: User login
  Given I open browser
  When I click button
  Then it works
```

---

#### **2. 合理使用 test_data**

- ✅ 将测试数据集中管理在 `test_data` 目录
- ✅ 使用结构化格式（JSON/YAML）
- ✅ 文件名要有意义
- ❌ 不要在 test_data 中存放敏感信息（生产环境密码等）

---

#### **3. 内网环境适配**

- ✅ 去掉 `Given I have a web browser open` 这类步骤
- ✅ 使用内网可访问的 URL
- ✅ 配置内网可用的 LLM API（如 ModelScope）
- ❌ 不要依赖外网资源（Google、CDN 等）

---

#### **4. 批量测试组织**

```
tests/
├── module_a/
│   ├── input/
│   │   └── module_a.feature
│   └── test_data/
│       ├── config.yaml
│       └── users.json
├── module_b/
│   ├── input/
│   │   └── module_b.feature
│   └── test_data/
└── module_c/
    ├── input/
    │   └── module_c.feature
    └── test_data/
```

**运行**：
```bash
python -m testzeus_hercules --bulk
```

---

#### **5. 调试技巧**

- ✅ 查看日志文件：`log_files/{test_id}/{timestamp}/`
- ✅ 查看截图：`proofs/{test_id}/{timestamp}/`
- ✅ 查看 JUnit 报告：`output/{timestamp}/`
- ✅ 使用 `;skip;` 标记临时禁用某些步骤

---

### 7.3 性能优化建议

1. **减少不必要的验证步骤**：去掉 `Given I have a web browser open`
2. **合理设置 timeout**：根据网络情况调整（内网可以设置更短）
3. **复用浏览器实例**：使用 `--reuse-browser` 参数（如果支持）
4. **并行执行**：未来版本可能支持并行执行多个测试用例

---

### 7.4 安全建议

1. **不要在代码中硬编码密码**：使用 test_data 或环境变量
2. **定期轮换测试凭据**：特别是共享的测试环境
3. **限制 test_data 文件的访问权限**：使用文件系统权限控制
4. **使用密钥管理服务**：对于高度敏感的信息，考虑使用 Vault 等服务

---

## 📚 附录

### A. 常用命令

```bash
# 单文件模式
python -m testzeus_hercules

# 指定文件
python -m testzeus_hercules --input-file ./my_tests/login.feature

# 批量模式
python -m testzeus_hercules --bulk

# 指定输出路径
python -m testzeus_hercules --output-path ./results

# 指定测试数据路径
python -m testzeus_hercules --test-data-path ./my_test_data
```

---

### B. 配置文件位置

| 文件 | 路径 | 说明 |
|------|------|------|
| agents_llm_config.json | `./agents_llm_config-example.json` | Agent LLM 配置示例 |
| .env-example | `./.env-example` | 环境变量示例 |
| mcp_servers.example.json | `./mcp_servers.example.json` | MCP 服务器配置示例 |

---

### C. 目录结构说明

```
testzeus-hercules/
├── opt/                      # 项目源文件根目录
│   ├── input/               # 输入 feature 文件
│   ├── test_data/           # 测试数据文件
│   ├── output/              # 测试结果输出
│   ├── proofs/              # 截图和视频
│   ├── log_files/           # 日志文件
│   └── tmp_gherkin/         # 临时 gherkin 文件
├── tests/                   # 批量测试目录
│   └── test_folder/
│       ├── input/
│       └── test_data/
├── testzeus_hercules/       # 核心代码
│   ├── core/
│   │   ├── agents/          # Agent 实现
│   │   ├── tools/           # 工具函数
│   │   └── memory/          # 记忆管理
│   └── utils/               # 辅助工具
└── docs/                    # 文档
```

---

### D. 相关文档

- [GPT5_USAGE.md](../docs/GPT5_USAGE.md)
- [MCP_Usage.md](../docs/MCP_Usage.md)
- [environment_variables.md](../docs/environment_variables.md)
- [python_sandbox_execution.md](../docs/python_sandbox_execution.md)
- [run_guide.md](../docs/run_guide.md)
- [sandbox_quick_reference.md](../docs/sandbox_quick_reference.md)

---

**文档版本**: v1.0  
**最后更新**: 2026-05-18  
**适用项目**: TestZeus Hercules
