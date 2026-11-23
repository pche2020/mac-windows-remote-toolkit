# Mac 配置与验收

这一流程可以在 Mac 上单独完成。准备 Apple silicon Mac、macOS 14 或更新、可用网络、足够的统一内存和目标磁盘空间。

## 1. 检查 Mac 及本地模型档位

在本指南目录打开「终端」。

```bash
bash ./install-macos.sh --check
```

记录 macOS 版本、CPU／GPU、总统一内存、当前可用统一内存和存放模型的盘。脚本查看用户目录所在盘。如果计划把文件放到其他盘，用 `df -h "/Volumes/你的磁盘名"` 检查那个盘。脚本用 `vm_stat` 的 free、inactive、speculative 页估算可用量。Linger 还会检查 Metal 的工作集和内存压力，截图上的「空闲」可能是不同口径。驱动随 macOS 提供。

- **16 GiB** 通常从 Spark-X2.6-4B `Q4_K_M` 64K 起步。坚持 27B 时先停下来核对硬件限制。
- **24 GiB** 的 27B 起点为 `UD-IQ3_S` 64K、`llama.cpp + Metal`。官方模拟约需 21 GiB 可用统一内存。
- **32 GiB** 的参考档位为 `UD-Q4_K_M` 128K。48 或 64 GiB 的参考上下文为 200,000 tokens。具体下载大小、缓存和磁盘需求看本机安装计划。 [官方硬件表](https://docs.heylinger.com/hardware/compatibility)

## 2. 校验并安装桌面应用

```bash
bash ./install-macos.sh
```

脚本下载、校验固定版本的官方 ARM64 DMG，把 `Linger.app` 放入 `~/Applications`。发现已有 Linger 时复用它。手动安装时从同一发布页取 `.dmg` 和 `SHA256SUMS.txt`，用 `shasum -a 256` 对照后在 Finder 中拖入「应用程序」。首次遇到发布者无法验证，按官方文档到「系统设置 → 隐私与安全性」对这个应用确认。 [官方发布](https://github.com/simplexai-labs/linger/releases/tag/desktop-v0.1.6) · [官方 Mac 安装](https://docs.heylinger.com/install/desktop-app)

## 3. 选账号、执行机和 Runtime

1. 打开 Linger。Mac 单机部署选 **Quick Install**，向导建立本机服务并连接本机。已有账号和服务时选 **Server address**，填平时打开 Linger 的地址，在登录页使用该账号。
2. Quick Install 的完成页有 **Your account on this computer**，需要再次登录时在本机点 **Show** 查看该安装生成的凭据。在「计算机／Computers」检查 Mac 已连接。若两端共用账号，在设备列表核对各自的显示名。
3. 在设置中选择此 Mac 的 **Local model**。使用 Linger 托管的 Pi 跑本地模型。想额外安装 Codex、Claude Code、Pi CLI 或 Antigravity，可按[智能体执行手册](../AGENTS.md)安装并核对用途。

## 4. 下载、固定默认模型及按需加载

1. 查看计划的模型名、权重量化、Metal、共享上下文、并发槽、磁盘和内存。只为 27B 部署时，计划降到其他模型就暂停确认。
2. 走 **设置 → 模型** 的 Mac 条目。若已有本地模型库，选 **Download** 准备文件，等待校验结束。首次向导的 **Install and start** 会做首次加载和真实自检，完成后再卸载。在模型详情记录实际下载位置。Quick Install 0.1.6 本地栈的默认模型根目录是 `~/.simplexai/runtime/localmodels/models`，自定义安装目录和其他模型导入以实际路径为准。
3. 需要运行时，先在终端重测。下面是 24 GiB Mac、`UD-IQ3_S` 64K 档位的官方模拟初筛。其他档位改成实际计划要求。

   ```bash
   bash ./install-macos.sh --check --minimum-memory-gib 21
   ```

4. 回到模型页点 **Recheck memory**，确认 Metal 和内存检查通过。点指定 27B 的 **Load**，在 Agent 或计算机的模型来源里确认还指向 27B，并把执行机设为此 Mac。资源不够时记录缺口，保留目标模型，等用户保存工作并自行释放资源后再重试。

## 5. 推理验收与停止

- 新建一条不含隐私的短测试，例如「把 `apple, pear, banana` 分成三个项目列出」。发出前核对 Agent 的计算机是 Mac、Runtime 是本地 Pi、模型名是 `Qwen3.8-27B`。有回答后检查模型状态和 Mac 的资源变化，三项一并记录。
- 在模型页确认任务已完成、内容已保存，再执行 **Unload**。看到 **Downloaded** 后重跑 `--check`，记录释放后的统一内存。模型文件继续留在磁盘。
- 在「系统设置 → 通用 → 登录项」和 Linger 自身的开机设置里关闭 Linger 自启。待保存了工作再试一次退出并重开，检查模型是否仍为 **Downloaded**。版本 0.1.6 的桌面恢复逻辑可能启动已批准的模型栈。若重开即加载，交付时标记这一项未达到「打开应用仍不加载」，并明确下次何时会触发加载。 [桌面恢复逻辑](https://github.com/simplexai-labs/linger/blob/desktop-v0.1.6/apps/desktop/src/main/local-server.ts)
