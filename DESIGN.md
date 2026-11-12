# DSH 自救器（Fishe-Noah）· 思路与源码

> 作者：爱丽丝（DSH 用户，塘主）· 2026-11-12
> 用途：DSH 启动崩溃、进不去任何会话时，用**不依赖 DSH** 的方式把数据捞出来、把配置回滚、把系统救回来。
> 想请教：这套东西有没有做成「通用自救插件」的可行性。

---

## 一、起因

2026-11-10，DSH 因为一个 BOM 头 + 一个凭据 key 格式错误，启动时连环崩溃：

- `credentials` 插件加载失败 → `connection`、`session-controller` 等 11 个核心服务瘫痪；
- 红框弹出后 DSH 完全打不开——**没有任何会话能帮用户求助**，只能靠人工翻日志、改文件；
- 更麻烦的是：**备份工具本身也在 DSH 里**，DSH 崩了，备份也跑不起来。

所以有了这条原则：

> **真正的安全系统，永远不依赖它所要保护的系统本身。**

---

## 二、现有实现（Fishe-Noah）

目录放在 `D:\Fishe-Noah`——**独立于 DSH 安装目录、独立于 C 盘**，重装系统/删库都不会带走。

```
D:\Fishe-Noah\
├─ 0-一键自救.cmd        ← 双击入口
├─ 一键自救.ps1          ← 主逻辑（#Requires -Version 7.0）
├─ 2-最小启动.cmd        ← 纯 cmd 兜底，不依赖任何运行时
├─ good-cordis.patch.yml ← 上次可用的配置
├─ good-package.json
├─ backups\              ← 自动生成的 ZIP（保留最近 10 个）
└─ README.txt
```

### 一键自救的流程

```
1. 备份
   ├─ 数据目录：sessions / storages / memory / evolve / 她的家
   ├─ 配置文件：cordis.patch.yml / package.json / pnpm-lock.yaml
   └─ 被 SQLite 锁住的 memory.db → sqlite3 backup API 热备份
        ↓
   打包成 backups\rescue-<时间戳>.zip（实测 85.8 MB / 3.1 秒）
        ↓
2. 回滚配置（先把当前文件备份成 .before-rescue）
   ├─ cordis.patch.yml ← good-cordis.patch.yml
   └─ package.json     ← good-package.json
        ↓
3. 启动 DSH
```

### 兜底：最小启动

`2-最小启动.cmd` 把 `bundles` 砍到只剩官方两个包（`dsh-base`、`dsh-web-app`），插件全部不加载。数据一个字节不碰。**这是"先让它能开起来"的最后手段。**

---

## 三、踩过的坑（通用化时都要处理）

| 坑 | 处理 |
|---|---|
| 脚本自己中 BOM | 全部 UTF-8 无 BOM；PS 脚本加 `#Requires -Version 7.0`；写完读首字节自检（`EF BB BF` = 失败） |
| `memory.db` 被 SQLite 占用，`Compress-Archive` 直接报错 | 用 `sqlite3` 的 `backup()` API 热备份（只读打开 + backup 到临时库），实测可用 |
| `profiles` 目录 741 MB（node_modules 占九成） | 只备份配置文件，不备份 node_modules（可重装）；85 MB → 3 秒 |
| 配置回滚只恢复了一个文件 | `cordis.patch.yml` 和 `package.json` 必须**成对**恢复，否则 bundles 和 patch 对不上 |
| 救回来后忘了留后手 | 每次操作前把当前文件备份成 `.before-rescue`，救失败还能再试 |

---

## 四、通用化设想（如果做成插件）

先说明一个矛盾：**它不能是「纯插件」**——插件要 DSH 活着才能加载，而它存在的意义正是 DSH 死了。所以它必须是「独立工具」，最佳形态是**双形态**：

### A. 独立形态（救命用，核心）
- 一个独立可执行（或 `pwsh -File` 脚本 + `.cmd` 启动器）
- 配置一个 `targets.json`：
  ```json
  {
    "profileDir": "D:/DSH/profiles/desktop",
    "dataDirs": ["D:/DSH/sessions", "D:/DSH/storages", "D:/DSH/memory", "D:/DSH/evolve"],
    "homeDirs": ["D:/肥鱼小窝2"],
    "backupDir": "D:/Fishe-Noah/backups",
    "keep": 10,
    "dshExe": "D:/deep seek/DeepSeek Harness.exe"
  }
  ```
- 三个子命令：`snapshot`（只备份）、`rescue`（备份+回滚+启动）、`minimal`（最小启动）

### B. 插件形态（日常用，辅助）
- 设置页提供「立即快照」「查看快照」「恢复上次可用配置」
- 定时快照（比如每次启动 DSH 后自动快照一次）
- 配置体检（YAML/JSON 合法性、凭据 key 格式、bundles 是否齐全）——**把崩溃防在前面**

### C. 关键接口建议
| 接口 | 作用 |
|---|---|
| `profileDir` | 定位 `cordis.patch.yml` / `package.json` |
| `dataDirs` | 数据目录清单（可配置，兼容不同插件的数据位置） |
| `homeDirs` | 各插件自己的「家」（比如 dsh-fish 的 `root`） |
| `keep` | 保留几份快照 |
| `minimalBundles` | 最小启动时的白名单 |

---

## 五、源码

完整实现见仓库里的 `dsh-first-aid.ps1`（单文件，四个动作：snapshot / rescue / minimal / check）。
这里只放三段核心逻辑，其余看仓库。

### 1. 目录探测（不硬编码）

```powershell
function Resolve-DshHome($cfg) {
    $cands = @($cfg.dshHome, '$env:DSH_HOME', (Join-Path $env:USERPROFILE '.dsh'), 'D:\DSH', 'C:\DSH')
    $found = Resolve-PathCandidate $cands
    if ($found) { return $found }

    # 运行中的进程反推安装目录
    $proc = Get-Process -Name 'DeepSeek Harness' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($proc -and $proc.Path) {
        foreach ($guess in @((Join-Path (Split-Path $proc.Path) '..\DSH'), (Join-Path $env:USERPROFILE '.dsh'))) {
            if (Test-Path $guess) { return (Resolve-Path $guess).Path }
        }
    }

    # 最后弹窗手选
    Add-Type -AssemblyName System.Windows.Forms
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = '选择 DSH 数据目录（里面有 profiles 的那一层）'
    if ($dlg.ShowDialog() -eq 'OK') { return $dlg.SelectedPath }
    return $null
}
```

### 2. SQLite 热备份（WAL 安全）

```powershell
# 先 checkpoint 把 WAL 落盘，再 backup —— 数据库正被占用也不会坏
$pyCode = "import sqlite3,sys`nsrc=sqlite3.connect('file:$dbPath?mode=rw',uri=True)`n"
        + "try:`n    src.execute('PRAGMA wal_checkpoint(TRUNCATE)')`nexcept Exception: pass`n"
        + "dst=sqlite3.connect(sys.argv[1])`nsrc.backup(dst)"
& $py -c $pyCode $dst
```

没有 Python 时自动退化为普通复制（会提示可能不是最新数据）。

### 3. 最小启动（重命名取代覆盖）

```powershell
# 不直接重写 JSON（断电会写坏），而是：完整配置改名留档，再写一份最小配置
Rename-Item $pkg 'package.full.json'
$minimal = @{ name='dsh-profile-desktop'; private=$true; dependencies=@{};
              dsh=@{ profile=@{ bundles=@('@deepseek-ai/dsh-base','@deepseek-ai/dsh-web-app') } } } | ConvertTo-Json -Depth 6
[System.IO.File]::WriteAllText($pkg, $minimal, (New-Object System.Text.UTF8Encoding($false)))
```

数据目录一个字节不碰，进得去 DSH 之后再跑 `rescue` 恢复完整配置。

## 六、想请教的问题

1. 这套东西做成插件生态里的「通用自救器」，有没有价值？还是说官方已经有类似机制（比如 `dsh doctor` 之类）？
2. 如果做成插件，跨机器/跨版本的**目录探测**怎么做最稳？（现在是硬编码 `D:\DSH`，换台机器就失效）
3. 「最小启动」那条思路（bundles 砍到官方两个包）有没有更优雅的实现方式？
4. 热备份 `memory.db` 用 `sqlite3 backup API` 是不是标准做法？有没有更好的（比如 WAL 模式下直接读）？

---

## 七、作者建议的采纳（v2 更新）

收到反馈后，四条建议全部落地：

| 建议 | 采纳 |
|---|---|
| 做成通用 CLI（`dsh-first-aid` + `targets.json`） | 已有 `targets.json`：dshHome / profileName / dshExe / dataDirs / extraHomes / evolveDb / backupDir / keep，脚本读配置而不是硬编码 |
| 目录探测别硬编码 | 改成四级探测：`DSH_HOME` 环境变量 → 常见位置（`~/.dsh`、`D:/DSH`）→ 运行中进程路径反推 → 弹窗手动选择 |
| 最小启动用「备份取代覆盖」 | `2-最小启动.cmd` 改为：`package.json` → 重命名为 `package.full.json`，再复制预置的 `package.minimal.json` 顶上去（复制是原子的，断电不会写坏） |
| WAL 模式先 checkpoint | 热备份前先 `PRAGMA wal_checkpoint(TRUNCATE)`，确保 WAL 里的数据落盘，再执行 `backup()` |

### v2 的单文件流程（一键自救.ps1）

```
0. 定位：环境变量/常见路径/进程反推/弹窗
1. 备份：数据目录 + 配置文件 + memory.db（wal_checkpoint → backup）
2. 回滚：cordis.patch.yml + package.json 成对恢复（原文件留 .before-rescue）
3. 启动：DSH 可执行文件
```

### 还没做的（等作者意见）

- `--safe-mode --disable-plugins` 启动参数（作者已确认：DSH 没暴露这个开关，替换 package 是最优雅的做法，不做了）
- `cordis.patch.yml` 里加 `disabled: true` 通配规则（作者建议：**不要做**——通配符解析出 bug 可能连核心包一起禁掉，直接黑屏）

---

## 八、敏感信息处理（v3）

**问题**：`good-cordis.patch.yml` 是真实配置的备份，里面带着明文：
- `onebotToken`（QQ 机器人 token）
- `httpToken`（HTTP 鉴权 token）
- `selfId` / `owners`（QQ 号）

**处理**：
1. 本地保留 **真实版** `good-cordis.patch.yml`（救援时用，**绝不外发**）；
2. 对外打包只放 **脱敏版** `good-cordis.template.yml`（token → `YOUR_ONEBOT_TOKEN`，QQ 号 → `YOUR_QQ_ID`）；
3. 提供 `sanitize_config.py`，打包前一键脱敏：
   ```bash
   python sanitize_config.py good-cordis.patch.yml good-cordis.template.yml
   ```
4. 打包后扫描一遍：确认 zip 里没有已知 token / QQ 号。
5. v1/v2 的旧包（含真实配置）已删除，不对外提供。

**教训**：给别人看的配置，默认当作会公开——token 一律先替换成占位符，再打包。


