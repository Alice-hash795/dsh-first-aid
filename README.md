# dsh-first-aid

**DSH（DeepSeek Harness）崩溃时的自救工具 —— 不依赖 DSH 运行。**

DSH 启动弹红框、闪退、插件全没、设置页空白……数据往往还在，只是你进不去了。这个工具从系统外面把数据备份出来、把配置救回来，或者用最小配置先让它开起来。

> 设计原则：**真正的安全系统，永远不依赖它所要保护的系统本身。**

---

## 什么情况下用

| 症状 | 先做这个 |
|---|---|
| 想日常备份一下 | `snapshot`（最安全，随时可跑） |
| 启动弹红框 / 闪退 | `rescue` |
| 插件全没 / 设置页空白 | `check` 体检，再 `rescue` |
| `rescue` 之后还起不来 | `minimal`（极简启动） |
| 想从某个备份恢复数据 | `restore`（恢复前会自动再备份当前状态） |

> 只是偶尔卡一下，先等它自己恢复，别一上来就动配置。

---

## 快速开始

**双击** `dsh-first-aid.cmd`，按提示选；或者命令行：

```powershell
.\dsh-first-aid.ps1 -Action snapshot   # 只备份
.\dsh-first-aid.ps1 -Action check      # 体检（不写文件）
.\dsh-first-aid.ps1 -Action rescue     # 备份 + 回滚配置 + 启动
.\dsh-first-aid.ps1 -Action minimal    # 极简启动（只留官方两个包）
.\dsh-first-aid.ps1 -Action restore    # 从备份恢复（会列出可选备份）
.\dsh-first-aid.ps1 -Action restore -Backup D:\backups\rescue-xxx.zip   # 指定备份
.\dsh-first-aid.ps1 -Action install-task    # 装成计划任务，每天 03:00 自动备份
.\dsh-first-aid.ps1 -Action uninstall-task  # 删掉计划任务
```

不配置也能用——内置探测：`DSH_HOME` → `~/.dsh` → `D:/DSH` → 运行中进程反推 → 弹窗手选。

---

## 备份什么

- `sessions/`（会话记录）、`storages/`、`memory/`
- `evolve/memory.db` —— **SQLite 热备份**（先 `wal_checkpoint` 再 `backup()`，数据库正被占用也安全）
- 各插件自己的家目录（可配置）
- `cordis.patch.yml` / `package.json` / `pnpm-lock.yaml`

存成 `backups/rescue-<时间戳>.zip`，默认保留最近 10 个。
`node_modules` 不备份（可重装，省 700MB+）。

---

## 自动备份（可选）

装一次，之后每天 03:00 自动备份，不用手动跑：

```powershell
.\dsh-first-aid.ps1 -Action install-task
```

它会创建一个 Windows 计划任务 `DSH-FirstAid-Snapshot`（用 PowerShell 7 运行）。
删掉：

```powershell
.\dsh-first-aid.ps1 -Action uninstall-task
```

---

## 需要配置吗

不需要。想精确控制就复制 `targets.example.json` 为 `targets.json`：

```json
{
  "dshHome": "D:/DSH",
  "profileName": "desktop",
  "dshExe": "D:/deep seek/DeepSeek Harness.exe",
  "dataDirs": ["sessions", "storages", "memory", "evolve"],
  "extraHomes": ["D:/你的插件家目录"],
  "backupDir": "D:/你的备份目录",
  "keep": 10
}
```

---

## 安全说明

- **只读**：备份是复制，从不删除、从不修改你的数据
- 回滚前先备份当前配置（`.before-rescue`）
- 极简启动用「重命名 + 复制预置文件」，不直接重写 JSON
- 所有文件 UTF-8 无 BOM，脚本自带 `#Requires -Version 5.1`
- 仓库不含任何凭据（配置模板里都是 `YOUR_XXX` 占位符）

---

## 环境要求

- Windows + PowerShell 5.1 或更高（系统自带即可，有 7 更好）
- 可选：Python 3（用于 `memory.db` 热备份，没有会退化为普通复制）

---

## 排障

崩溃日志：

```
%APPDATA%\@deepseek-ai\dsh-desktop\logs\crash-*.log
```

`rescue` 和 `minimal` 都不行：

1. 把 `profiles/desktop/cordis.patch.yml` 改名成 `.broken`
2. 再启动一次（回到最原始配置，能进）

---

## 文档

- [USAGE.md](USAGE.md) —— 使用说明（群友版，含常见问题）
- [DESIGN.md](DESIGN.md) —— 设计思路与踩到的坑
- [targets.example.json](targets.example.json) —— 配置模板
- [tools/sanitize_config.py](sanitize_config.py) —— 配置脱敏工具（对外发布前剔除 token / QQ 号）

---

## License

MIT
