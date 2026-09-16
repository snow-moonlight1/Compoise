# MatrixFlow AI: 数据兼容性与版本演进契约规范 (DATA_COMPATIBILITY.md)

本文档规范 MatrixFlow AI 的本地存储 Schema、备份导出载荷版本契约（ExportData Versioning）、数据迁移机制以及跨平台/跨版本互通规则。

---

## 1. 架构总览与核心设计原则

MatrixFlow AI 是以“本地优先”（Local-First）为核心原则构建的艾森豪威尔四象限待办应用。

- **本地存储持久化**：应用直接将状态保存于设备本地持久化存储（Android / Windows 统一基于 `SharedPreferences`）。
- **零强制后端**：待办数据不依赖云端账户或中央服务器，支持离线运行，用户隐私与数据完全归属本地。
- **BYOK 隐私保护**：用户配置的 AI 密钥仅在本地安全保存与直接请求所选模型服务商，**严禁将 API 密钥或备份内容输出至日志或版本控制**。
- **备份即互通**：通过自包含的标准 JSON 备份文件（ExportData）实现用户手动导出、跨设备导入、换机迁移与故障恢复。

---

## 2. 本地持久化 Schema（核心四键不可变契约）

无论外部导出格式或应用版本如何演进，MatrixFlow 本地存储的**核心存储键名（Key）保持严格恒定**，不引入重命名：

| 本地存储键名 (`key`) | 数据结构 | 对应模型 | 说明与兜底策略 |
|---|---|---|---|
| `matrixflow-tasks` | JSON 数组字符串 | `List<Task>` | 任务列表（包含层级嵌套的 `List<SubTask>`）。若读取损坏回退空列表并设置 `corruptNotice`。 |
| `matrixflow-boards` | JSON 数组字符串 | `List<Board>` | 看板元数据列表。若为空自动初始化首个默认看板。 |
| `matrixflow-config` | JSON 字典字符串 | `AIConfig` | AI 服务商与端点配置。缺省时安全回退默认 DeepSeek 预设。 |
| `matrixflow-settings` | JSON 字典字符串 | `AppSettings` | 用户偏好设置。读取时按字段白名单解析并提供显式安全默认值。 |
| `matrixflow-active-board` | 字符串 | `String` | 当前激活看板 ID。若引用失效或不存在，自动重定向至首个有效看板。 |

### 本地 Schema 读取与演进原则
1. **显式默认兜底（Default Fallback）**：本地读取反序列化时，任何新增字段在旧存档中不存在时，必须具备明确、安全且符合用户预期的默认值（例如显示设置回退系统/标准，开关回退 `false`）。
2. **容错解析（Fault-Tolerant Parsing）**：单个损坏的记录项被跳过并计数，杜绝因个别字段格式异常导致整个待办库无法启动。
3. **控制器/临时态隔离**：搜索临时关键字、输入框草稿、撤销计时快照、命令面板打开状态、网络请求临时缓存等纯运行时状态**严禁写入持久化四键**。

---

## 3. 备份载荷版本契约（ExportData Versions）

备份数据是一份包含任务、看板、设置与配置的完整 JSON 导出对象。

```json
{
  "version": 2,
  "timestamp": 1726322400000,
  "boards": [ ... ],
  "tasks": [ ... ],
  "settings": { ... },
  "aiConfig": { ... }
}
```

### 版本定义

- **ExportData v1（历史格式）**：
  - 范围：早期 React Web 及 Native V0.3-A 前使用的版本（`version: 1`）。
  - 特点：包含基础待办与设置，未包含后续新增的桌面壳设置（如 `closeToTray`、`globalShortcut`）以及显示偏好（`viewMode`、`fontSize`、`fontFamily`）。
- **ExportData v2（当前标准格式，WP11-N 起生效）**：
  - 范围：Flutter Android 与 Windows 的标准导出格式（`version: 2`）。
  - 特点：完整序列化当前客户端全部功能字段（含多视图模式、字体字号体系、Windows 托盘与快捷键配置），并作为后续任务字段演进（如 WP22-C 人工紧急性、WP13-A 备注、WP27-B 完成时间戳、WP25 提醒）的基础载荷标准。
- **未知高版本（`version > 2`）**：
  - 属于未来客户端产出的高版本数据，当前客户端无法识别其中的新语义，**必须严格拒绝覆盖并抛出 `UnsupportedDataVersionException`**，避免因字段剥离造成隐性数据损坏。

---

## 4. 双向兼容性矩阵（Compatibility Matrix）

| 来源版本 / 客户端 | 目标版本 / 客户端 | 兼容状态 | 行为描述与数据处理 |
|---|---|---|---|
| **ExportData v1** (Web / 旧 Native) | **Flutter v2** (Android / Windows) | **无损升级 (Full Migration)** | 自动识别 `version: 1`（或无 version 的旧存档）。`data_migrations.dart` 自动补齐 v2 新字段安全默认值，清洗去重 ID，纠正孤儿任务归宿。 |
| **Flutter v2** (Android / Windows) | **Flutter v2** (Windows / Android) | **完全互通 (100% Lossless)** | 双平台采用完全一致的 Dart 模型与序列化逻辑，通过 JSON 文件可无缝跨平台恢复。 |
| **Flutter v2** (Android / Windows) | **ExportData v1** (旧 Native 客户端) | **拒绝导入 (Strict Reject)** | 旧 Native 客户端校验 `version == 1`，遇到 v2 会抛出 `bad export shape` 拦截，防止旧版本错误覆写。 |
| **Flutter v2** (Android / Windows) | **旧 React Web** (冻结保留端) | **不承诺无损 (Lossy / Unsupported)** | 冻结的 React Web 缺少严格版本拒绝门禁，直接载入会丢弃 v2 特有设置。**路线明确不为此继续修改旧 Web**。 |
| **Flutter v2 (降级导出 v1)** | **旧 React Web / 旧 Native** | **降级支持 (Downgrade Export)** | 客户端提供 `exportJson(version: 1)` 降级导出能力，显式剔除 v2 独有配置，使旧版能合规解析。 |
| **未知未来版本 (v > 2)** | **Flutter v2** (Android / Windows) | **严格拒收 (Safety Gate)** | 抛出 `UnsupportedDataVersionException`，弹窗提示用户升级 MatrixFlow，现有本地数据保持 100% 完好不变。 |

---

## 5. 小型迁移引擎契约 (`data_migrations.dart`)

数据导入采用“先验证、全解析、后应用”的**原子事务原则**：

1. **版本前置检查**：
   - 若 `version` 缺省：按 v1 格式解析。
   - 若 `version` 为 1 或 2：通过版本门禁进入解析阶段。
   - 若 `version` 不是整数或 `version > 2` 或 `version < 1`：立刻抛出异常，中止导入流程。
2. **数据清洗与防御性处理**：
   - **ID 冲突去重**：同一备份包内若出现重复看板 ID 或任务 ID，仅保留首项，并在迁移结果中记录警告。
   - **孤儿任务处理**：
     - 在 `overwrite` 模式：任务所属看板必须存在于导入的看板集合中（若 `boardId` 为空则归入首个有效看板；若指向不存在的看板，拒绝导入）。
     - 在 `merge` 模式：仅导入能与当前有效看板集合匹配的任务，孤儿任务被自动忽略，杜绝悬挂引用。
   - **设置白名单过滤**：
     - 仅提取受支持的合法设置键值，非法或未知设置键自动忽略，杜绝未经验证的脏属性污染 `AppSettings`。
3. **失败原子回滚（Failure Atomicity）**：
   - 只要校验或迁移过程抛出任何异常，现有的 `Store.boards`、`Store.tasks`、`Store.settings`、`Store.aiConfig` 以及本地代次 `boardEpoch` 均**绝对不发生改变**。

---

## 6. 后续工作包新字段接入规范

后续实施包在引入新数据字段时，必须严格遵守以下演进步骤：

1. **确定所属模型与可空性**：
   - 任务级字段（如 WP22-C `urgencyMode`、WP13-A `notesMarkdown`、WP25 `reminderAt`、WP27-B `completedAt`）：在 `Task` / `SubTask` 中声明为带有默认值的字段或可空类型（`?`）。
     - WP13-A-N 已在 `Task` 与 `SubTask` 中接入可选 `notesMarkdown`（`String?`），空或仅空白时不序列化，v2 导出包含该字段，v1 降级导出时安全剔除。
     - WP25-R 已定义 `Task` 与 `SubTask` 的可选 `reminderAt`（`int?`，毫秒时间戳）与 `Task.reminderTimezone`（`String?`），由后续 WP25-N 落地实施；v2 导出包含该字段，v1 降级导出时安全剔除。
     - WP27-B-N 已在 `Task` 与 `SubTask` 中接入可选 `completedAt`（`int?`，毫秒时间戳），记录任务完成时刻；未完成或反选时为 `null`；v2 导出包含该字段，v1 降级导出时安全剔除；旧备份缺失时回退 `null`，严禁借 `createdAt` 伪造时间。
   - 设置级字段（如显示偏好、开关）：在 `AppSettings` 中声明并提供显式默认参数。
2. **实现 `fromJson` 缺省兜底**：
   - 反序列化处严禁假定字段必填，必须使用 `(j['field'] as T?) ?? defaultVal` 或枚举安全匹配 `firstWhere(..., orElse: () => defaultVal)`。
3. **加入 `toJson` 与导出白名单**：
   - 在 `toJson` 中输出字段；若字段具有版本特异性，在 `toJson({int? targetVersion})` 中根据目标版本决定是否剥离。
4. **单元回归测试必须包含**：
   - 验证无该字段的 v1/v2 旧 JSON 传入时，模型能安全构建并回退至默认值。
   - 验证往返序列化后该字段值被准确保留。

