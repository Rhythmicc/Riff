# 搜索匹配重设计（Human-First Matching）

> 状态：**Phase A 与 Phase B 已实现**——`SearchCandidate` 自动生成与统一特征打分已替换旧的“名字/包名分区”逻辑；搜索类查询（应用/快捷操作/系统操作）已合并为带类别标签的统一候选池，使用记录升级为 frecency 有界加分；Phase C（typo 容错、查询联想）待实施。

## 1. 现状：为什么补丁越来越多

当前搜索是“硬分区 + 分支修补”：

- `LauncherQueryClassifier` 先抢意图——系统操作和快捷操作命中后直接短路，应用搜索根本不执行（`ma` 命中 `mac 睡眠` 就只剩“睡眠”）。
- `ApplicationSearch` 把结果分成“显示名命中”和“包名命中”两组，组内再用使用记录排序；命中质量分数只在组内起作用。
- `FuzzyMatcher` 的 `10000/8000/6000` 是拍脑袋的权重，短查询边界、别名表、系统操作前缀阈值都是事后打的补丁。

补丁之间还会互相打架：短查询边界解决了 `we`，却让 `ma` 被系统操作抢走；别名表只覆盖微信和 Mail 两个案例。每来一个新投诉就要再加一条规则。

## 2. 目标：先理解用户想表达什么，再排序可能性

1. **候选不靠硬过滤，靠质量分 + 多样性上限。** 低质量命中可以排到很后面，而不是因为“查询太短”被一刀切。
2. **理解用户的输入习惯。** 中文应用名自动生成拼音（微信 → weixin / wx），英文名自动拆词和缩写（Visual Studio Code → vsc）。
3. **排序可解释、可调参。** 所有命中信号统一成特征分，不再按“命中哪个字段”分区。
4. **越用越准。** 用 frecency（频率 + 衰减）和“查询前缀 → 选择”联想做个性化。

## 3. 候选生成（Candidate Generation）

为每个应用生成统一的 `SearchCandidate`，所有字段都参与匹配：

```swift
struct SearchCandidate: Sendable {
    let application: ApplicationRecord
    let displayName: String
    let components: [String]      // 按空格 / 驼峰 / 分隔符拆分
    let initials: String          // 组件首字母：Visual Studio Code → vsc
    let aliases: [String]         // 策划别名 + 自动拼音 + 常见缩写
    let pinyin: String            // CFStringTransform：微信 → wei xin
    let bundleID: String?
}
```

每个字段独立打分，取该候选的最佳字段分。只要任一字段超过**长度归一化的质量下限**就进入候选池；下限是一条连续函数，而不是“少于 3 个字符必须边界”的特例规则。

## 3.1 陌生 App 的候选词自动生成

核心原则：**不为陌生 App 枚举“候选词”，而是从它自身可得的元数据里确定性生成一小撮“候选字段”**。字段是有限的、可解释的，打分时统一比较：

1. **名称家族**：`CFBundleDisplayName`、`CFBundleName`、bundle 文件名——任何 App 都有，覆盖默认场景。
2. **本地化显示名**：读取 `Contents/Resources/<lang>.lproj/InfoPlist.strings` 中的 `CFBundleDisplayName`/`CFBundleName`。中文 App 内置的英文名、英文 App 内置的中文名都可以直接拿到，不需要人工维护（微信的 `WeChat` 就来自这里）。
3. **拆词组件**：按空格、连字符、下划线、驼峰、数字边界拆分（`CleanShot X` → `[clean, shot, x]`，`OmniGraffle` → `[omni, graffle]`）。
4. **缩写**：组件首字母（`Visual Studio Code` → `vsc`，`CleanShot X` → `csx`）。
5. **拼音管线**：`CFStringTransform`（ToLatin + StripCombiningMarks）把中文名转成拼音，再生成三种形态——全拼带空格、连拼、首字母：

   | App | 全拼 | 连拼 | 首字母 |
   | --- | --- | --- | --- |
   | 微信 | wei xin | weixin | wx |
   | 哔哩哔哩 | bi li bi li | bilibili | blbl |
   | 网易云音乐 | wang yi yun yin le | wangyiyunyinle | wyyyl（`wyy` 前缀可命中） |
   | 飞书 | fei shu | feishu | fs |

   以上结果已在本机用 Swift 脚本实测验证。
6. **策划别名表只留“品牌名 ≠ 拼音/本地化名”的知名 App**（腾讯会议 → tencent meeting、抖音 → tiktok 这类），可以随版本更新扩充；长尾完全靠自动生成，不依赖人工维护。
7. **行为学习兜底**：用户选择结果后记录“查询前缀桶 → App”，陌生 App 用过一次就开始变准，覆盖所有自动规则都没想到的别名。

这样“陌生 App”的唯一成本是索引时多生成几个字符串，不涉及人工运营；无法自动推导的品牌名由本地化字段、小别名表和用户学习三层兜底。

## 4. 特征打分（Scoring）

```text
matchScore = base
           + boundaryBonus          // 词首 / 驼峰 / 数字→字母
           + coverageBonus          // 命中片段占名称/组件比例，鼓励短查询命中短名
           + pinyinAliasBonus       // 拼音与策划别名
           - spanPenalty            // 松散子序列按跨度衰减
           - typoPenalty            // 编辑距离 ≤ 1 的纠错（vsocde → vscode）
```

`base` 只有一档清晰的阶梯：exact > prefix > component-start > contiguous > subsequence。所有规则在任何查询长度下都生效，参数随长度**连续**变化，不再出现“`<3` 特殊处理”。

## 5. 统一结果池

- **确定性意图保留**：算式、汇率、函数图、随机密码这类输入本身有明确语法，不需要猜测，仍走原分类器。
- **搜索类查询**（应用、系统操作、快捷操作、便笺等）进入同一个候选池，结果带类别标签（App / 操作 / 快捷），按 `finalRank` 排序，并用多样性上限控制每类数量（例如短查询每类最多 3 个）。
- 这样 `ma` 同时展示 Mail、邮箱别名和可能的其它高置信候选，而不是被某一个意图独占；用户选择哪一个都可以，不再有“唯一匹配项”的奇怪体验。
- 没有高置信候选时再走 Google/AI fallback。

## 6. 个性化（Frecency + 查询联想）

```text
frecency(app) = hits(app) * exp(-age / τ)
finalRank = matchScore * (1 + α·frecency) + β·queryAssociation
```

- `LauncherUsageStore` 从“最近使用列表”升级为 frecency 记录。
- `queryAssociation` 记录“查询前缀桶 → 用户选择的候选”，同一前缀再次输入时加权；例如用户常输入 `ma` 选 Mail，之后 `ma` 的 Mail 会进一步提前。
- 数据只存本机、可清空，沿用现有体验指标的隐私边界。

## 7. 黄金测试集（Golden Tests）

把真实案例固化为“查询 → 期望结果（含顺序）”，防止任何规则倒退：

| 查询 | 期望 |
| --- | --- |
| `we` | 微信（weixin/wechat） |
| `ma` / `mai` | Apple Mail（含邮箱别名） |
| `vscode` / `vsocde` | Visual Studio Code |
| `睡` / `mac` | 睡眠 |
| `note` | 便笺快捷操作或 Notes |
| `saf` | Super App Finder（缩写子序列保留） |

测试断言**顺序**而不是“包含”，这样 `we` 的第一名是微信、CleanShot X 不出现在前 N 名这类体验才被守住。

## 8. 实施阶段

- **Phase A**：`SearchCandidate` + 特征打分，替换 `FuzzyMatcher`/`ApplicationSearch` 的分区逻辑；UI 形状不变；跑黄金测试集。
- **Phase B**：搜索类查询合并候选池（跨类别标签展示）+ frecency 排序。
- **Phase C**：拼音自动生成、缩写、typo 容错、查询联想；`AppAliasCatalog` 只保留极少数特例。

每个阶段保持全量测试通过，并把已生效的补丁规则逐步删掉（而不是叠加）。
