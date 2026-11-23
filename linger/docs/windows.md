# Windows 配置与验收

这一流程可以在 Windows 上单独完成。准备 Windows 11 x64、受 Linger 支持的 NVIDIA 驱动和显卡、可用网络、目标磁盘空间。用普通用户的 PowerShell 操作。

## 1. 实测 Windows、驱动、内存和显存

在本指南目录打开 PowerShell。

```powershell
.\install-windows.ps1 -CheckOnly
```

保存 Windows 版本及构建号、CPU、物理内存和可用 RAM、各盘剩余容量、GPU 型号和驱动、独立显存和当前空闲显存。脚本使用系统 CIM 查询硬件，用 `nvidia-smi` 读取独显。需要独立核对时使用：

```powershell
nvidia-smi --query-gpu=index,name,driver_version,memory.total,memory.free --format=csv
```

如果 `nvidia-smi` 报错或无法读数，先核对驱动，从 NVIDIA 官方更新合适的驱动，再在 Linger 向导点 **Check again**。Windows 若没有支持的 NVIDIA GPU，先说明 Linger 当前内置本地模型的限制，由使用者决定是否选其他方案。 [NVIDIA 驱动](https://www.nvidia.com/Download/index.aspx) · [官方硬件表](https://docs.heylinger.com/hardware/compatibility)

## 2. 选择计划并安装桌面应用

参考 **RTX 4070 Ti SUPER 16 GiB + 32 GiB RAM** 的配置，先核对 `Qwen3.8-27B UD-IQ3_S`、64K 共享上下文、原生 `llama.cpp + CUDA`。24 GiB 卡的参考是 `UD-Q4_K_M` 128K。8 或 12 GiB 卡的官方默认档位是候选的 Spark 4B。当前空闲显存不足时，即使铭牌是 16 GiB，计划也可能只出现 4B。

```powershell
.\install-windows.ps1
```

脚本核对官方安装包 SHA-256 后启动交互式安装器，遇到已安装版本时跳过安装。手动安装也可以从同一发布取 `.exe` 或便携 ZIP，并用 `Get-FileHash -Algorithm SHA256` 对照 `SHA256SUMS.txt`。若组织策略阻止安装，交由管理员处理。向导如果允许选盘，先核对该盘可用空间、用户写权限和计划显示的下载总量。 [官方发布](https://github.com/simplexai-labs/linger/releases/tag/desktop-v0.1.6) · [官方 Windows 安装](https://docs.heylinger.com/install/desktop-app)

若脚本受到 Windows PowerShell 执行策略限制，先核对策略和脚本来源。个人设备上可在当前会话用 `Set-ExecutionPolicy -Scope Process RemoteSigned`，如果 ZIP 解压出的脚本仍带下载标记，审阅脚本后对该文件运行 `Unblock-File -LiteralPath .\install-windows.ps1`。组织策略以管理员配置为准。 [PowerShell 执行策略](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_execution_policies)

## 3. 登录账号和登记这台 Windows

1. 打开 Linger。独立在 Windows 上搭服务时用 **Quick Install**。已经有可以访问的同一 Linger 账号时，用 **Server address** 输入该账号实际登录的服务地址，再登录已有账号。无论 Mac 是否也登录同一账号，都要在 **Computers／计算机** 确认 Windows 设备已连接。
2. Quick Install 生成的默认邮箱可以相同，密码由各自安装生成。本机账号在对应安装完成页 **Your account on this computer → Show** 查阅。需要用户输入的密码与登录确认留在本地界面。
3. 打开 **设置 → 模型**，选择 Windows 设备和 **Local model**。Windows 本地模型使用 Pi Runtime。额外的 Codex、Claude Code 或 Antigravity 等按[智能体执行手册](../AGENTS.md)安装。在 Agent 的设置里选择这台 Windows 作为执行机。

## 4. 下载 27B、检查缺口并按需加载

1. 核对窗口显示的模型、量化、CUDA、共享上下文、计划所需 RAM、VRAM 和所选盘空间。目标只有 27B 时，向导给 4B 就停在确认前。资源紧张时先保存内容，等使用者决定何时释放其他程序。
2. 在 Windows 设备的 27B 项点 **Download**，等校验结束。若使用了首次向导的一体化安装流程，它会加载并自检一次。记录实际的模型文件位置。Quick Install 0.1.6 管理的模型根目录是所选 Linger 数据根目录下的 `runtime\localmodels\models`。默认数据根目录为 `$env:USERPROFILE\.simplexai`，自定义目录以日志和模型详情为准。
3. 加载前重测。以下是 16 GiB 卡这档的示例初筛，18.25 GiB 是同档 Linux 27B 模拟给出的 RAM 参考，正式值以 Windows 的计划为准。多卡时带 `-GpuIndex`，并使用计划指定的 GPU 编号。

   ```powershell
   .\install-windows.ps1 -CheckOnly -MinimumRamGiB 18.25 -MinimumVramGiB 14.5
   ```

   PowerShell 会分别给出 RAM、显存缺口。遇到不足或无法测量先停下。使用者释放资源后复测，不把 RAM 和显存相加。
4. 模型页点 **Recheck memory**，等应用判定可加载后点 Windows 对应 27B 的 **Load**。选择这条 27B 作为 Agent 使用的模型。后续启动重复预检和 **Load**，保留原模型选择。

## 5. 真实推理、释放资源与开机验证

1. 加载前记录空闲内存与显存。加载后核对 Windows 模型状态和 **Loaded** 的 27B 标识。同时用 `nvidia-smi` 观察空闲显存变化。
2. 在 Agent 所在房间发不含隐私的短测试，例如「回复 `Windows local test` 再用一行概括 2+3 的结果」。验收三件事：执行位置是该 Windows，27B 真实返回测试结果，Windows 显存使用或推理日志与时间相符。部分 WDDM 驱动不会返回每个进程的显存，结合整体显存和应用日志查看。
3. 确认测试结束、没有未保存内容或其他待完成的任务，再在模型页点 **Unload**。模型状态应回到 **Downloaded**。再次执行 `-CheckOnly`，记录回收后的 RAM、VRAM，并确认文件仍在原目录。必要时在托盘选择 **Quit**，先确认活动任务与保存状态。
4. 到「设置 → 应用 → 启动」检查 Linger 是关闭状态。如果组织部署另加了 Linger 登录启动项，也要核对这一项。之后在获准的维护时间验证重新登录／启动和手动重开 Linger 两个场景。若重开自动恢复已批准的 27B 栈，报告其触发条件，按需验收保留为待解决。 [官方发布的退出行为](https://github.com/simplexai-labs/linger/releases/tag/desktop-v0.1.6) · [桌面恢复逻辑](https://github.com/simplexai-labs/linger/blob/desktop-v0.1.6/apps/desktop/src/main/local-server.ts)
