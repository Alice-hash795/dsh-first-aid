# dsh-first-aid

DSH（DeepSeek Harness）**自救工具** —— 不依赖 DSH 运行，崩溃时的最后一道防线。

当 DSH 启动就弹红框、进不去任何会话时，用它：

- 把会话、记忆、数据**安全备份**出来
- 把配置**回滚**到上次可用版本
- 或者用**最小配置**把系统拉起来（只留官方两个包）

> 设计原则：**真正的安全系统，永远不依赖它所要保护的系统本身。**

---

## 为什么需要它

DSH 崩溃时（BOM 污染配置、插件死锁、凭据格式错误……），你进不了任何会话，
也就没法让 AI 帮你备份、查日志、改配置——**工具本身得能在系统外运行**。

这个脚本就是那个"外部"：一个纯 PowerShell 文件，双击就能用。

---

## 快速开始

```powershell
# 只备份（最安全，随时可跑）
.\dsh-first-aid.ps1 -Action snapshot

# 备份 + 回滚配置 + 启动 DSH
.\dsh-first-aid.ps1 -Action rescue

# 极简启动：bundles 只剩官方两个包，完整配置保留为 package.full.json
.\dsh-first-aid.ps1 -Action minimal

# 配置体检（JSON/YAML 合法性、BOM、bundles 是否齐全），不写任何文件
.\dsh-first-aid.ps1 -Action check
```

双击 `dsh-first-aid.cmd` 也可以，会显示菜单。

---

## 备份内容

| 类别 | 内容 |
|---|---|
| 会话 | `sessions/` 全部会话记录（zstd 格式） |
| 数据 | `storages/`、`memory/` |
| 记忆 | `evolve/memory.db` —— **SQLite 热备份**（先 `wal_checkpoint` 再 `backup()`，正在被占用也安全） |
| 插件家 | 通过 `extraHomes` 配置（比如大肥鱼的 `D:/肥鱼小窝2`） |
| 配置 | `cordis.patch.yml`、`package.json`、`pnpm-lock.yaml` |

备份是带时间戳的 ZIP（`backups/rescue-<时间戳>.zip`），默认保留最近 10 个。
`node_modules` 不备份（可重装，省 700MB+）。

---

## 配置（targets.json）

不配置也能用（内置探测），想精确控制就复制 `targets.example.json` 为 `targets.json`：

```json
{
  "dshHome": "D:/DSH",
  "profileName": "desktop",
  "dshExe": "D:/deep seek/DeepSeek Harness.exe",
  "dataDirs": ["sessions", "storages", "memory", "evolve"],
  "extraHomes": ["D:/肥鱼小窝2"],
  "evolveDb": "evolve/memory.db",
  "backupDir": "D:/backups/dsh-first-aid",
  "keep": 10
}
```

目录探测顺序：`targets.json` → `DSH_HOME` 环境变量 → `~/.dsh` → `D:/DSH` → 运行中进程反推 → 弹窗手选。

---

## 安全说明

- **只读复制**数据目录，从不删除、从不修改
- 回滚前会把当前配置备份成 `.before-rescue`
- 极简启动用「重命名 + 复制预置文件」，不直接重写 JSON（断电也不会写坏）
- 所有文件 UTF-8 无 BOM，脚本自带 `#Requires -Version 5.1`
- 不含任何凭据：本仓库的配置模板已脱敏（token → `YOUR_TOKEN_HERE`）

---

## 环境要求

- Windows + PowerShell 5.1 或更高（系统自带即可，PS7 更好）
- 可选：Python 3（用于 `memory.db` 热备份，没有会退化为普通复制）

---

## 排障

崩溃日志位置：

```
%APPDATA%\@deepseek-ai\dsh-desktop\logs\crash-*.log
```

如果 `rescue` 和 `minimal` 都不行：

1. 把 `profiles/desktop/cordis.patch.yml` 改名成 `.broken`
2. 再启动一次（回到最原始配置，能进）

---

## License

MIT
