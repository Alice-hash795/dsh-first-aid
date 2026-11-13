# dsh-first-aid 使用说明（群友版）

> 一句话：**DSH 崩了、打不开，用这个工具把数据捞出来、把配置救回来。**
> 它不依赖 DSH 运行，所以哪怕 DSH 完全起不来也能用。

---

## 一、什么情况下用

遇到下面这些情况，先别急着重装：

| 症状 | 用哪个动作 |
|---|---|
| DSH 一启动就弹红框 / 闪退 | `rescue` |
| 能打开但插件全没了、设置页空白 | `check` 先体检，再 `rescue` |
| 想日常备份一下数据 | `snapshot` |
| `rescue` 之后还是起不来 | `minimal`（极简启动） |
| 误删了数据 / 想退回到某个时间点 | `restore`（从备份恢复） |

> 注意：如果只是偶尔卡一下，先等它自己恢复，别一上来就动配置。

---

## 二、怎么下载

1. 打开：<https://github.com/Alice-hash795/dsh-first-aid>
2. 点绿色的 **Code** 按钮 → **Download ZIP**
3. 解压到一个**不在 DSH 安装目录、也不在 C 盘用户文件夹**的地方
   （推荐 `D:\Fishe-Noah` 这种独立目录，重装系统也不会丢）

---

## 三、怎么用

### 方法一：双击（最简单）

双击 `dsh-first-aid.cmd`，按提示选：

```
dsh-first-aid.cmd snapshot   只备份（最安全，随时可跑）
dsh-first-aid.cmd check      体检（不写任何文件）
dsh-first-aid.cmd rescue     备份 + 回滚配置 + 启动
dsh-first-aid.cmd minimal    极简启动
```

### 方法二：命令行

```powershell
# 在解压出来的目录里
.\dsh-first-aid.ps1 -Action check
.\dsh-first-aid.ps1 -Action snapshot
.\dsh-first-aid.ps1 -Action rescue
.\dsh-first-aid.ps1 -Action minimal
```

---

## 四、每个动作干什么

### `snapshot` —— 只备份

把下面这些东西打个 ZIP 存起来：

- `sessions/`（所有会话记录）
- `storages/`、`memory/`
- `evolve/memory.db`（**热备份**，数据库正在用也能安全复制）
- 各插件自己的家目录（通过配置指定）
- `cordis.patch.yml`、`package.json`

存到 `backups/rescue-<时间戳>.zip`，默认保留最近 10 个。

**这个动作最安全，随时可以跑，跑一百次也不会弄坏任何东西。**

### `check` —— 配置体检

检查：

- `package.json` 是否合法、有没有 BOM
- `cordis.patch.yml` 有没有 BOM
- bundles 里列出的插件是不是都装了

只读不写。崩之前用它看看，能提前发现问题。

### `rescue` —— 备份 + 回滚 + 启动

1. 先跑一遍 `snapshot`
2. 把 `cordis.patch.yml` 和 `package.json` 恢复成"上次可用"的版本
   （原来的文件会留一份 `.before-rescue` 备份）
3. 启动 DSH

### `minimal` —— 极简启动

把 `package.json` 重命名为 `package.full.json` 留档，然后写一份只带官方两个包的配置，
插件全部不加载。**数据一个字节不碰。**

进得去 DSH 之后，再跑 `rescue` 恢复完整配置。

### `restore` —— 从备份恢复

误删了数据、或者想退回到某个时间点：

```powershell
.\dsh-first-aid.ps1 -Action restore                      # 列出 backups 里的备份，选一个
.\dsh-first-aid.ps1 -Action restore -Backup D:\xxx.zip   # 直接指定
```

恢复前会**自动把当前状态再备份一份**（`pre-restore-*.zip`），万一恢复错了还能再来一次。
恢复内容：sessions / storages / memory / memory.db / 配置文件。

---

## 五、需要配置吗

**不需要**，内置探测会自己找：

```
DSH_HOME 环境变量 → ~/.dsh → D:/DSH → 运行中的进程反推 → 弹窗手选
```

想精确控制就复制 `targets.example.json` 为 `targets.json` 改：

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

## 六、安全说明

- **只读**：备份是复制，从不删除、从不修改你的数据
- 回滚前会先备份当前配置
- 极简启动用「重命名 + 复制」，不会写坏 JSON
- 所有文件 UTF-8 无 BOM，脚本自带 `#Requires -Version 5.1`
- 不含任何凭据，配置模板里都是 `YOUR_XXX` 占位符

---

## 七、常见问题

**Q：没有 PowerShell 7 能用吗？**
能。脚本兼容 5.1（Windows 自带），有 7 就用 7。

**Q：没有 Python 能备份 memory.db 吗？**
能，会退化为普通复制（可能不是最新数据）。主流程不受影响。

**Q：`rescue` 之后还是起不来？**
跑 `minimal`。如果还不行，把 `profiles/desktop/cordis.patch.yml` 改名成 `.broken` 再启动。

**Q：备份会不会占满硬盘？**
只保留最近 10 个，超出的自动删。

**Q：崩了怎么看日志？**
`%APPDATA%\@deepseek-ai\dsh-desktop\logs\crash-*.log`，最新的那个就是原因。

---

## 八、原理（给好奇的人）

> **真正的安全系统，永远不依赖它所要保护的系统本身。**

DSH 崩溃时，你进不了任何会话，也就没法让 AI 帮你备份、查日志、改配置——
所以工具箱必须能在系统外面运行。这个脚本就是那个"外面"。

完整设计说明见仓库里的 `DESIGN.md`。
## 自动备份（可选）

装一次，之后每天 03:00 自动备份：

```powershell
.\dsh-first-aid.ps1 -Action install-task
```

删掉：`.\dsh-first-aid.ps1 -Action uninstall-task`

（计划任务名 `DSH-FirstAid-Snapshot`，用 PowerShell 7 运行。）