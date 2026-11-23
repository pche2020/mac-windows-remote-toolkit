# Linger 安装与验收执行手册

适用对象是能在目标设备运行命令的 Codex、Claude Code、Pi、Antigravity、Cursor、Copilot、WorkBuddy 等。可自动读项目说明的客户端以当前目录作为工作区。其他客户端把本文件交给智能体，并附上对应系统的完整流程。能照本手册实施部署，与 Linger 本身是否支持某客户端作为运行时，是两件事。

## 执行顺序

1. **定位机器。** 让使用者确认执行设备、当前登录身份、目标模型及是否已允许连接。如果通过远程通道连接，先说明方式、用途和操作范围，等待同意。根据目标环境用 [Mac 流程](docs/mac.md) 或 [Windows 流程](docs/windows.md)。
2. **只读采集。** 在目标机运行下方检查命令。记录 OS、CPU、GPU、驱动、总量和当前可用量、目标盘空间。统一内存只计一次，Windows 的 RAM 与独立 VRAM 分别核算。目标盘可能与系统盘不同。
3. **安装并读取计划。** 用本项目脚本安装校验通过的上游桌面包。复用已有安装、设备和账号。使用者自己在登录页输入密码或完成 OAuth。应用内核对具体计算机、模型、量化、上下文、内存及下载容量。
4. **固定目标。** 若目标是 27B，遇到 4B 或其他模型先暂停。报告差多少 RAM 或显存、是否由容量或驱动限制。不改默认选择，不关进程替用户腾资源。关闭应用前先核实保存状态和活动任务，可能丢弃内容时等使用者许可。
5. **按需加载。** 下载后检查完整性状态，记录实际文件位置。重新测可用量，再在指定设备的模型项点 **Load**。首次向导把安装和加载合并时，记录首次自检，完成后卸载。禁止用单个 HTTP 200、模型名或登录成功代替本地推理验收。
6. **交付验收。** 发送一条无隐私测试。检查执行设备及 Runtime、模型名、回答和本机资源或推理日志。停止时使用 **Unload**，比对资源变化、确认文件保留并关闭系统自启。核对重开应用是否会恢复计划。实机未执行的项目标为待验，每一项都以实测为准。

```bash
# 在目标 Mac 上
bash ./install-macos.sh --check
bash ./install-macos.sh
```

```powershell
# 在目标 Windows 的普通用户 PowerShell 中
.\install-windows.ps1 -CheckOnly
.\install-windows.ps1
```

## 安装 Linger 支持的 Runtime

| Runtime | 脚本参数 | 安装和登录要点 |
| --- | --- | --- |
| Pi | `pi` | 跑 Linger 内置本地模型时，优先用 Linger 配置的 Pi。额外安装独立 `pi` 适合单独调用。核对用途与实际模型来源。 [Pi 官方仓库](https://github.com/earendil-works/pi/tree/main/packages/coding-agent) |
| Codex | `codex` | 核对 `codex --version`，按需要由使用者运行 `codex login`。通过订阅使用时按远程模型的数据流处理。 [Codex CLI](https://learn.chatgpt.com/docs/codex/cli) |
| Claude Code | `claude` | 核对 `claude --version`，运行 `claude` 并按提示完成登录。npm 是官方安装选项之一。 [Claude Code 安装](https://code.claude.com/docs/en/setup) |
| Antigravity CLI | `antigravity` | 核对 `agy --version`，按官方教程完成 Google 登录或配置凭据。Linger `0.1.6` 发布说明列出支持，以本机能识别 `agy` 为准。 [Google CLI](https://antigravity.google/docs/cli/tutorial/) · [Linger 0.1.6](https://github.com/simplexai-labs/linger/releases/tag/desktop-v0.1.6) |

Mac 和 Windows 的脚本任选一个 Runtime 参数。已有可识别的 CLI 会保留。通过 npm 的选项需要已有兼容版本的 Node.js 和 npm，推荐当前 Node.js LTS。用户也可通过表中的上游文档直接安装。Antigravity 使用 Google 的操作系统安装器。外部 CLI 的安装、更新、授权和版本兼容按各上游负责。Linger 桌面包按本仓库固定格式核验 SHA-256。第三方 Runtime 支持与使用 Linger 原生本地模型的 Pi 模式应分开验证。

```bash
bash ./install-macos.sh --runtime codex
```

```powershell
.\install-windows.ps1 -Runtime codex
```

在目标机新开终端，若 `linger-computer` 在 PATH 中，先运行 `linger-computer runtime check`。`READY` 表示 Runtime 检查通过。需要测试账号模型时再用 `linger-computer runtime check codex --live`，这是一次实际模型调用。Linger 管理的本地模型验收仍按应用内设备与推理日志进行。Cursor、Copilot、WorkBuddy 等可以作为阅读本手册的执行助手，Linger 的原生 Runtime 以官方版本说明为准。 [官方 Runtime 检查](https://docs.heylinger.com/models/choose-a-runtime)

## 给其他 Agent 的启动词

> 请先读 `AGENTS.md`。在我指定的设备按对应的 `docs/mac.md` 或 `docs/windows.md` 进行。先做只读硬件盘点，再提交模型计划。坚持我选的模型，资源不足暂停并报告差额。未经确认不连接其他设备或放弃未保存内容。完成一次真实推理后卸载模型并保留文件。最后报告各项实测结果。

## 交付记录

| 项目 | 要填的结果 |
| --- | --- |
| 目标设备 | OS、CPU、RAM、GPU、VRAM、驱动和目标盘余量 |
| 安装 | 桌面和工具包版本、安装来源、SHA-256 结果 |
| 模型 | 模型来源、名称、量化、引擎、共享上下文、并发槽、权重路径 |
| 加载前 | RAM、VRAM 或统一内存读数，计划门槛、差额和处理结果 |
| 推理 | 测试时间、执行设备、Runtime、模型来源、回答与资源／日志证据 |
| 停止及重启 | 卸载状态、资源回收量、权重是否保留、开机及重开状态、启动入口 |
