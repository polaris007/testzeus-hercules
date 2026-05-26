# Hercules Memory & Cache Mechanisms — 完整分析

> 文档版本: v1.0  
> 分析日期: 2026-05-26  
> 覆盖范围: `testzeus_hercules/` 全部内存与缓存子系统

---

## 目录

1. [概述：缓存与内存全景](#1-概述缓存与内存全景)
2. [Cache.disk — LLM 响应磁盘缓存](#2-cachedisk--llm-响应磁盘缓存)
3. [Agent 级 cache_seed — 死配置分析](#3-agent-级-cache_seed--死配置分析)
4. [DOM md 注入机制 — 缓存失效的根因](#4-dom-md-注入机制--缓存失效的根因)
5. [Dynamic LTM — RAG + ChromaDB 长期记忆](#5-dynamic-ltm--rag--chromadb-长期记忆)
6. [Static LTM — 文件型静态长期记忆](#6-static-ltm--文件型静态长期记忆)
7. [StateHandler — 内存态运行期记忆](#7-statehandler--内存态运行期记忆)
8. [ZeusTeachability — SQLite QA 记忆](#8-zeusteachability--sqlite-qa-记忆)
9. [URL 导航去重](#9-url-导航去重)
10. [Portkey 语义网关缓存](#10-portkey-语义网关缓存)
11. [JUnit 缓存统计](#11-junit-缓存统计)
12. [其他缓存点](#12-其他缓存点)
13. [瓶颈分析与加速建议](#13-瓶颈分析与加速建议)

---

## 1. 概述：缓存与内存全景

Hercules 共有 **7 个内存/缓存子系统**，按作用域和持久性划分如下：

| 子系统 | 持久性 | 默认启用 | 存储后端 | 作用域 |
|---|---|---|---|---|
| `Cache.disk(seed=5)` | 跨运行 (SQLite) | **硬编码启用** | SQLite (diskcache) | LLM API 响应 |
| `llm_config_params.cache_seed` | 跨运行 (SQLite) | **不启用** (null) | SQLite (diskcache) | LLM API 响应 (冗余) |
| Dynamic LTM | 跨运行 (ChromaDB) | **默认关闭** | ChromaDB + 文件分块 | 测试上下文记忆 |
| Static LTM | 跨运行 (文件) | **始终开启** | JSON/文本文件 | 测试数据 |
| StateHandler | 仅当前运行 | 始终开启 | 内存 (append-only str + deque) | 运行态状态 |
| ZeusTeachability | 跨运行 (SQLite) | 由 LLM 配置决定 | SQLite | QA 键值对 |
| URL 导航去重 | 仅当前运行 | 始终开启 | `set()` 内存 | 已访问 URL |

核心观察: **`Cache.disk(seed=5)` 是唯一实际有效的 LLM 响应缓存，但受 DOM 非确定性影响基本打不中。**

---

## 2. Cache.disk — LLM 响应磁盘缓存

### 2.1 位置与启用方式

**文件**: `testzeus_hercules/core/simple_hercules.py`

两处硬编码，**不可通过环境变量关闭**:

```python
# 第 399 行: 注册 nested chats
with Cache.disk(cache_seed=5) as cache:
    self.agents_map["user"].register_nested_chats([...], cache=cache)

# 第 1059 行: 主执行流
with Cache.disk(cache_seed=5) as cache:
    result = await self.agents_map["user"].a_initiate_chat(
        self.agents_map["planner_agent"],
        max_turns=..., message=prompt, cache=cache,
    )
```

### 2.2 物理存储

- 后端: Python `diskcache` 库 (SQLite + 大值文件)
- 路径: `./.cache/5/cache.db`
- Cache seed `5` 是目录名，所有缓存在 `.cache/5/` 下

### 2.3 缓存键生成

**源码**: `autogen/oai/openai_utils.py`

```python
NON_CACHE_KEY = [
    "api_key", "base_url", "api_type", "api_version",
    "azure_ad_token", "azure_ad_token_provider", "credentials",
]

def get_key(config: dict) -> str:
    copied = False
    for key in NON_CACHE_KEY:
        if key in config:
            config, copied = config.copy() if not copied else config, True
            config.pop(key)
    return to_jsonable_python(config)
```

键 = **完整 API 请求参数 dict（去认证字段）→ `pydantic_core.to_jsonable_python()` 序列化 → JSON 字符串**

包含:
- `model` 名称 (如 `gpt-4o`)
- **完整 `messages` 数组** (全部对话历史)
- `temperature`, `max_tokens`, `tools` 等参数

不包含:
- `api_key`, `base_url` 等认证字段

### 2.4 缓存粒度

**单次 LLM `client.create()` 调用级别**，不是对话级别也不是 turn 级别。

每次 agent 调用 LLM 时，`OpenAIWrapper.create()` 内部:

```python
# AG2 伪代码
cache_client = None
if cache is not None:           # 显式 cache → 优先
    cache_client = cache
elif cache_seed is not None:    # llm_config 中的 cache_seed → 后备
    cache_client = Cache.disk(cache_seed, LEGACY_CACHE_DIR)

if cache_client is not None:
    with cache_client as c:
        key = get_key(params)
        response = c.get(key, None)
        if response is not None:
            return response       # 缓存命中 → 直接返回
        response = self._client.create(**params)
        c.set(key, response)      # 缓存写入
        return response
```

### 2.5 为什么缓存几乎打不中

根因是 **DOM 的非确定性**:

1. md 注入使用全局递增计数器 (见第 4 节)
2. 每次打开页面, iframe/ad/cookie banner 数量和加载时序可能不同
3. `get_dom_with_content_type` 返回的 DOM JSON 中 md 值偏移
4. DOM JSON 作为 tool result 进入 `messages` 数组
5. `get_key()` 包含完整 `messages` → 内容变化 → key 变化 → **cache miss**

**理论唯一的命中窗口**: 第一次 DOM 捕获之前的 LLM 调用 (planning + 系统 prompt)，通常仅 1-2 次。

---

## 3. Agent 级 cache_seed — 死配置分析

### 3.1 配置流

**入口**: `agents_llm_config.json`

```json
{
  "planner_agent": {
    "llm_config_params": {
      "cache_seed": null,
      "temperature": 0.0
    }
  }
}
```

**环境变量映射**: `config_env_loader.py`

```python
ENV_TO_LLM_PARAMS_MAPPING = {
    "LLM_MODEL_CACHE_SEED": "cache_seed",  # 第 100 行
    ...
}
```

**默认值**: `config.py` 第 622 行

```python
self._config.setdefault("LLM_MODEL_CACHE_SEED", None)
```

### 3.2 AG2 内部优先级

当 `llm_config` 中设了 `cache_seed`（如 `1234`），且 agent 调用 LLM 时:

```
OpenAIWrapper.create() 缓存选择优先级:
1. 检查显式 cache 参数 (来自 initiate_chat(cache=...)) → 非 None → 使用
2. 检查 Cache._current_cache (ContextVar, 由 with Cache.disk() 设置) → 非 None → 使用
3. 检查 llm_config 中的 cache_seed → 创建 Cache.disk(cache_seed, ".cache")
```

在 Hercules 中:

- 主执行流 (`initiate_chat`) **永远传入显式 `cache=Cache.disk(5)`** → 第 1 步直接短路
- `Cache.disk(5)` 的 context manager 还设置了 `ContextVar` → 第 2 步也截住
- **`cache_seed` 永远不会被检查到**

### 3.3 结论

| 配置项 | 状态 |
|---|---|
| `cache_seed: null` (默认) | 无效果 |
| `cache_seed: 1234` (启用) | 仍无效果，被 `Cache.disk(5)` 覆盖 |
| 删除所有 `Cache.disk(5)` | 则 `cache_seed` 会独立生效, 路径 `.cache/1234/cache.db` |

**即便独立生效, 同样的精确匹配问题导致加速效果趋近于零。**

---

## 4. DOM md 注入机制 — 缓存失效的根因

### 4.1 源码位置

**文件**: `testzeus_hercules/utils/get_detailed_accessibility_tree.py`

核心函数:
- `__inject_attributes()` — 注入 md
- `isInteractiveElement()` — 判断交互元素
- `__cleanup_dom()` — 清理

### 4.2 注入逻辑

```python
def __inject_attributes():
    idCounter = 0
    elements = document.querySelectorAll('*')
    
    for element in elements:
        # 递归处理 shadow DOM
        if element.shadowRoot:
            process_shadow(element.shadowRoot)
        
        # 递归处理 iframe
        if element.tagName === 'IFRAME':
            process_iframe(element.contentDocument)
        
        # 判断交互元素
        if isInteractiveElement(element):
            idCounter += 1
            element.setAttribute('md', str(idCounter))
            element.setAttribute('aria-keyshortcuts', str(idCounter))
```

`isInteractiveElement()` 检查:
- tag 名称 (a, button, input, select, textarea 等)
- ARIA role (button, link, checkbox, combobox 等)
- `tabindex >= 0`
- `style.cursor === 'pointer'`
- `onclick`, `ng-click`, `@click`, `v-on:click`
- `getEventListeners(element)` 非空
- `draggable`
- 30+ ARIA 属性 (`aria-haspopup`, `aria-expanded` 等)

### 4.3 清理逻辑

```python
def __cleanup_dom():
    elements = document.querySelectorAll('[aria-keyshortcuts]')
    for element in elements:
        element.removeAttribute('aria-keyshortcuts')
    # ⚠️ md 属性没有被清理! 会残留在 DOM 中
```

### 4.4 浏览器工具定位

所有交互工具使用 `[md='N']` 选择器定位元素:
- `click_using_selector(md="42")` → `page.locator("[md='42']").click()`
- `enter_text(md="42", text="foo")` → `page.locator("[md='42']").fill("foo")`

### 4.5 非确定性来源

| 来源 | 影响 | 频率 |
|---|---|---|
| iframe 加载时序 | md 偏移 | 每次页面加载 |
| 广告注入 | md 数量变化 | 每次页面加载 |
| Cookie consent banner | md 偏移 | 首次访问 |
| A/B testing 变体 | DOM 结构不同 | 概率性 |
| 动态内容 (推荐/个性化) | 元素变化 | 页面刷新 |

### 4.6 跨运行 md 确定性评估

**同一 feature、同一 URL、立即重跑**:
- 若页面无动态内容 → 约 70% 概率 md 一致
- 若有广告/个性化 → < 30%

**跨运行且经过时间间隔**:
- Cookie/隐私横幅: 首次无横幅, 二次有 → md 全面偏移
- Session 过期: 重定向到登录页 → md 完全不同

---

## 5. Dynamic LTM — RAG + ChromaDB 长期记忆

### 5.1 源码位置

**文件**: `testzeus_hercules/core/memory/dynamic_ltm.py` (约 320 行)

### 5.2 架构

```
用户 prompt
    │
    ▼
query_memory(prompt) ──→ ChromaDB 相似度检索 ──→ 返回相关片段
    │
    ▼
向量嵌入模型 (通过 unstructured.io 分块)
```

### 5.3 默认禁用

```python
# config.py
USE_DYNAMIC_LTM = False  # 默认关闭
```

可通过环境变量或 CLI 参数启用:

```bash
export USE_DYNAMIC_LTM=true
# 或
export REUSE_VECTOR_DB=true  # 复用已有向量数据库
```

### 5.4 关键问题

```python
# ChromaDB 持久化路径 — 使用 tempfile!
self.persist_directory = tempfile.mkdtemp()
```

**每次启动创建临时目录** → 跨运行 ChromaDB 数据全部丢失。

除非 `REUSE_VECTOR_DB=true` 被设置，且手动指定固定路径。

### 5.5 工作流

1. `dynamic_ltm.py`: 将文本分块 (unstructured.io chunking)
2. 生成向量嵌入 (默认模型)
3. 写入 ChromaDB 集合
4. 查询时: `chroma_collection.similarity_search(query, k=3)`
5. 结果注入到 planner prompt 前: `prompt += "\n\nEXTRA INFORMATION: " + mem_fetch`

---

## 6. Static LTM — 文件型静态长期记忆

### 6.1 源码位置

**文件**: `testzeus_hercules/core/memory/static_ltm.py`

### 6.2 设计

```python
class StaticLTM:
    """文件型静态长期记忆。"""
    
    _instance = None  # 单例
    
    def get_test_data(self, test_case_id: str) -> dict:
        """根据测试用例 ID 读取对应的测试数据文件。"""
        file_path = self.test_data_dir / f"{test_case_id}.json"
        if file_path.exists():
            return json.loads(file_path.read_text())
        return {}
```

- **单例模式**，项目级共享
- 文件格式: JSON/文本，目录由 `test_data_path` 配置
- 始终启用，不可关闭
- 提供**测试数据**给 planner，不是通用的记忆存储

### 6.3 与其他系统的区别

| 特性 | Static LTM | Dynamic LTM |
|---|---|---|
| 数据来源 | 预置文件 | 运行时积累 |
| 检索方式 | 按 ID 精确匹配 | 向量相似度 |
| 持久性 | 始终持久 (文件) | 默认不持久 (tempdir) |
| 用途 | 测试数据 (变量替换) | 上下文记忆 |

---

## 7. StateHandler — 内存态运行期记忆

### 7.1 源码位置

**文件**: `testzeus_hercules/core/memory/state_handler.py`

### 7.2 设计

```python
from collections import deque

class StateHandler:
    def __init__(self):
        self._state_string: str = ""         # append-only 字符串
        self._state_dict: deque = deque(maxlen=2)  # 仅保留最近 2 条
    
    def update(self, key: str, value: Any):
        self._state_string += f"\n{key}: {value}"
        self._state_dict.append({key: value})
        if len(self._state_dict) > 2:
            self._state_dict.popleft()
    
    def get_state(self) -> str:
        return self._state_string[-2000:]  # 截断到 2000 字符
```

- **纯内存**, 运行结束即丢失
- `_state_dict` 仅保留最近 2 条 → 只用于当前步骤的状态传递
- 供 planner 读取当前运行状态: `current_url`, `last_action_result` 等

---

## 8. ZeusTeachability — SQLite QA 记忆

### 8.1 源码位置

**文件**: `testzeus_hercules/utils/llm_helper.py`

### 8.2 设计

```python
from autogen.agentchat.contrib.capabilities.teachability import Teachability

class ZeusTeachability:
    def __init__(self, agent, llm_config, db_path="teachability.db"):
        self.teachability = Teachability(
            agent=agent,
            llm_config=llm_config,
            db_path=db_path,  # SQLite
        )
    
    def teach(self, question: str, answer: str):
        """存入 QA 对。"""
        self.teachability.add_qa_pair(question, answer)
    
    def recall(self, question: str) -> str | None:
        """根据语义相似度检索 QA 对。"""
        return self.teachability.recall_answer(question)
```

- 后端: AutoGen 内置的 `Teachability` → SQLite
- 存储 QA 对 (问题-答案)
- 检索: 语义相似度 (LLM-based)
- 可跨运行持久化 (SQLite 文件)

### 8.3 当前使用状态

仅通过 `MultimodalConversableAgent` 间接使用，并非核心路径。主要用于保存 agent 在对话中学到的交互模式。

---

## 9. URL 导航去重

### 9.1 源码位置

**文件**: `testzeus_hercules/core/tools/open_url.py`

### 9.2 设计

```python
class OpenURLTool:
    _visited_urls: set = set()  # 类级别, 所有实例共享
    
    def open_url(self, url: str) -> dict:
        if url in self._visited_urls and self.from_cache:
            return {"status": "skipped", "reason": "already visited"}
        
        self._visited_urls.add(url)
        page.goto(url)
        return {"status": "success", "url": url}
```

- 行 84, 106, 158: `from_cache: True` 标记
- **仅当前进程**有效 (set 在内存中)
- 专门避免同一 URL 重复导航 (如多次重定向到登录页)
- 与 `Cache.disk` **完全独立**

---

## 10. Portkey 语义网关缓存

### 10.1 配置入口

**文件**: `testzeus_hercules/core/config_portkey_loader.py`

```python
class PortkeyConfigLoader:
    def load(self) -> dict:
        portkey_api_key = os.getenv("PORTKEY_API_KEY")
        if not portkey_api_key:
            return {}
        
        # Portkey 配置可以启用语义缓存
        return {
            "api_key": portkey_api_key,
            "mode": "fallback",  # 或 "force"
            "cache": {
                "type": "semantic",  # 语义缓存模式
                "strategy": "exact"  # 或 "semantic"
            }
        }
```

### 10.2 说明

- **Portkey** 是外部 LLM 网关服务
- 可配置语义缓存 (`strategy: "semantic"`) — 按语义相似度匹配，不要求精确一致
- 当前默认使用 `exact` 模式 → 同样受 DOM 非确定性影响
- 非默认启用的依赖 (需要 `PORTKEY_API_KEY`)

---

## 11. JUnit 缓存统计

### 11.1 源码位置

**文件**: `testzeus_hercules/utils/junit_helper.py`

### 11.2 报告字段

```python
class JUnitHelper:
    def add_test_case(self, name, status, ...):
        test_case.attrib["usage_including_cached_inference"] = str(total_usage)
        test_case.attrib["usage_excluding_cached_inference"] = str(actual_usage)
```

两个字段含义:
- `usage_including_cached_inference`: **包括**缓存命中的 token 消耗估算
- `usage_excluding_cached_inference`: **排除**缓存命中的实际 token 消耗

若缓存命中效果明显，两个值差距应显著。当前差距极小 → 佐证缓存基本无效。

---

## 12. 其他缓存点

### 12.1 Browser Extension / Nuclei 二进制缓存

- Nuclei 扫描器二进制下载后缓存 (路径: `~/.testzeus/nuclei/`)
- Browser 扩展文件缓存 (路径: `~/.testzeus/extensions/`)
- **一次性下载**, 不影响运行时性能

### 12.2 CI/CD uv 依赖缓存

- GitHub Actions 中 `astral-sh/setup-uv` 自动缓存 pip 依赖
- 仅加速 CI 安装，不影响运行

---

## 13. 瓶颈分析与加速建议

### 13.1 当前瓶颈排名

| 排名 | 瓶颈 | 影响 |
|---|---|---|
| 1 | **LLM 调用无法缓存** | 每次运行重新调用 API, 占运行时间 > 90% |
| 2 | **Dynamic LTM 默认关闭 + 临时目录** | 跨运行无法复用知识 |
| 3 | **顺序执行 feature/scenario** | 无法并行利用计算资源 |
| 4 | **全量 DOM 重提** | 每次 tool call 都重新蒸馏 DOM |
| 5 | **无 prompt 压缩** | `prompt_compressor.py` 是空 stub |

### 13.2 缺失的加速能力

| 能力 | 说明 | 优先级 |
|---|---|---|
| Test Result Cache | 按 feature 文件 hash + scenario hash 缓存测试结果 | P0 |
| Tool Execution Cache | 缓存 DOM 蒸馏结果 (URL + content_type 为 key) | P0 |
| 修复 Dynamic LTM | 默认启用 + 固定 ChromaDB 路径 | P1 |
| md 确定性注入 | 用 CSS 选择器 hash 替代递增计数器 | P1 |
| Prompt Compressor | 实现 LLM-based 或提取式摘要 | P2 |
| 并发 Feature 执行 | `for feat in list_of_feats` → async 并发 | P2 |
| 浏览器 Session 复用 | 跨 scenario 复用浏览器上下文 | P2 |

### 13.3 关键文件索引

| 文件 | 关键内容 |
|---|---|
| `simple_hercules.py:399,1059` | `Cache.disk(cache_seed=5)` 硬编码 |
| `get_detailed_accessibility_tree.py:48-238` | md 注入逻辑 |
| `get_detailed_accessibility_tree.py:1016-1160` | 可访问性树生成 |
| `get_detailed_accessibility_tree.py:638-688` | DOM 清理 (不清理 md) |
| `dynamic_ltm.py` | RAG + ChromaDB 长期记忆 |
| `static_ltm.py` | 文件型测试数据 |
| `state_handler.py` | 运行期状态 |
| `llm_helper.py` | ZeusTeachability |
| `config_env_loader.py:120-125` | cache_seed 环境变量解析 |
| `agent_config_types.py:45,100` | LLMConfigParams 类型定义 |
| `config.py` | USE_DYNAMIC_LTM, REUSE_VECTOR_DB |
| `prompt_compressor.py` | 空 stub (`pass`) |
| `open_url.py:84,106,158` | URL 去重 (from_cache) |
| `junit_helper.py` | 缓存命中统计输出 |
| `agents_llm_config.json` | 各 agent llm_config (cache_seed: null) |

---

## 附录: AG2 Cache 优先级源码参考

```python
# autogen/oai/client.py 中的 OpenAIWrapper.create()
extra_kwargs = {
    "agent", "cache", "cache_seed",  # ← cache 和 cache_seed 都是 extra_kwargs
    "filter_func", "allow_format_str_template",
    "context", "api_version", "api_type", "tags", "price",
}

# 在 _separate_create_config() 中:
# cache / cache_seed 被从 create_config 中移除 → 不会传给 OpenAI API
# 而是由 OpenAIWrapper 内部处理
```

```python
# autogen/cache/cache.py — Cache 的 ContextVar 机制

class Cache(AbstractCache):
    _current_cache: ContextVar[Cache] = ContextVar("current_cache", default=None)
    
    def __enter__(self) -> Cache:
        self._previous_cache = self.__class__._current_cache.get(None)
        self._token = self.__class__._current_cache.set(self)
        return self.cache.__enter__()
    
    def __exit__(self, ...):
        self.cache.__exit__(...)
        try:
            self.__class__._current_cache.reset(self._token)
        except RuntimeError:
            if self._previous_cache is not None:
                self.__class__._current_cache.set(self._previous_cache)
    
    @classmethod
    def get_current_cache(cls, cache=None) -> Cache | None:
        if cache is not None:
            return cache
        try:
            return cls._current_cache.get()
        except LookupError:
            return None
```

```python
# autogen/oai/openai_utils.py — get_key 实现

NON_CACHE_KEY = [
    "api_key", "base_url", "api_type", "api_version",
    "azure_ad_token", "azure_ad_token_provider", "credentials",
]

def get_key(config: dict) -> str:
    copied = False
    for key in NON_CACHE_KEY:
        if key in config:
            config, copied = config.copy() if not copied else config, True
            config.pop(key)
    return to_jsonable_python(config)
```
