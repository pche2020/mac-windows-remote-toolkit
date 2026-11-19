# 给智能体的执行手册（Agent Playbook）

> **这份文件是写给智能体读的，不是给人读的。**
> 适用对象：Claude Code、Codex、Antigravity、Grok Bot、豆包工作、WorkBuddy、LobsterAI 等主流 agent。
> Claude Code / Codex / Antigravity 会自动读取仓库根目录的 `AGENTS.md`；LobsterAI 按底层 OpenClaw 的机制读取工作区里的 `AGENTS.md`；
> 其他 agent（Grok Bot、豆包工作、WorkBuddy）请把本文件全文发给它，再附上文末的「启动词」。
> 场景：一位新手用户把本工具包交给你，请你在他的电脑上装好「Mac + AI 助手直连 Windows」这套远程操控配置（架构与原理见同仓库《docs/setup-guide.md》）。
> 你的任务：按下面阶段 A→F 顺序执行（H3 部署见可选阶段 G），能自动做的全做完；只能由用户本人做的动作，停下来用一句话告诉他点哪里、输入什么，等他做完再继续。
> 配套文件都在本仓库内：Windows 侧一键脚本 `scripts/setup-windows.ps1`、后端核心脚本 `scripts/comfy-backend.ps1`、4 个桌面模式工具 `scripts/*.bat`、配置文档 `docs/setup-guide.md`、故障速查 `docs/troubleshooting.md`、H3 部署 `docs/h3-deployment.md`（可选阶段 G）。

---

## 总原则（执行全程有效）

1. **先自检、后动手**：阶段 A 只读取、不改任何东西，报告给用户看过再进阶段 B。
2. **每步都要验收**：每个阶段末尾列了验活命令/检查点，不过关不许进下一阶段，先查《docs/troubleshooting.md》对应条目。
3. **失败处理顺序固定**：查台账 → 按台账解法处理 → 同一问题最多试 2 次，仍失败就停下来，把现象和你试过什么原样报告给用户，不要自行发挥试错。
4. **必须停下来等用户的动作只有四类**（其余全部你来做）：
   - 登录账号（Tailscale 等，用户自己的账号凭据只许他本人输入，你不许经手、不许记录）；
   - 点管理员授权弹窗（UAC 的「是」）；
   - 设定密码（RDP 专用账号的密码由用户本人输入，你不许生成、不许保存）；
   - 下载几十 GB 的大文件之前，确认存放磁盘。
5. **安全边界（不许突破）**：不开任何公网端口映射；防火墙只放行 Tailscale 网段与局域网；不把用户的密码、密钥写进任何文件或日志；不关闭 Windows 防火墙与杀毒软件（只加放行规则）。
6. **每完成一个阶段，向用户汇报一次**：做了什么、验收结果、下一阶段要做什么。用用户的语言汇报，不要甩命令原文。

---

## 阶段 A：环境自检（只读，零修改）

在 Windows 电脑上收集并报告：
- Windows 版本与版本类型（RDP 主机按专业版或企业版配置，家庭版见本阶段末尾的降级说明）；
- GPU 型号、显存、驱动版本（按目标模型核验，H3 硬件要求待核）；
- 内存、各磁盘剩余空间（按实际模板下载量及产物预留空间，优先空间最富余的盘）；
- 现状盘点：是否已装 Tailscale、ComfyUI Desktop、OpenSSH Server；是否已有管理员本地账号。

**降级说明**：家庭版跳过 RDP 与文件夹重定向，按配置指南第 3、5 章分别处理 SSH 和 ComfyUI。一键脚本的 `-SkipRdpUser` 只跳过建账号，仍会尝试配置 RDP。模型运行条件不足时单独跳过 ComfyUI，得到用户确认后再继续。

## 阶段 B：需要用户本人先做的两件事（你只引导）

1. **Tailscale 账号**：两台电脑（Windows 与 Mac）要登录**同一个** Tailscale 账号。引导用户在 Windows 上安装 Tailscale 并登录（没有账号就注册一个）；登录动作由用户完成。装好后记录这台机的 Tailscale IP（100.x.x.x），阶段 E 要用。
2. **（如果要跑本地 AI 模型）ComfyUI Desktop**：从官网安装，模型目录选阶段 A 里空间最富余的盘。安装向导由用户点，路径选择按你的推荐值提示他。模型文件几十 GB，开始下载前再跟用户确认一次。

## 阶段 C：Windows 侧自动配置（核心阶段）

以**管理员身份**运行本仓库 `scripts/setup-windows.ps1`（弹窗 UAC 时请用户点「是」）。它会幂等完成：OpenSSH Server 安装与公钥位、RDP 开启 + NLA + 防火墙收口（仅 Tailscale 网段与局域网）、RDP 专用本地账号骨架、ComfyUI 后端自启计划任务 + 每 5 分钟看门狗、把 4 个模式工具拷到公共桌面。

- 涉及**给 rdp 账号设密码**时：停下来，让用户本人输入，你背过身去（不要读取、不要记录）。
- 脚本报错时：先查台账条目 1、5、9；不要改脚本参数重试。

**本阶段验收**（按已选功能验收，全过才继续）：
- 按配置指南同步自定义路径后启动后端，本机 `http://localhost:8189/system_stats` 返回 HTTP 200；
- 计划任务里有后端自启与看门狗两项；
- 核对 SSH、RDP 和 8188 生效入站规则的来源范围，并验证 SSH 服务端仅公钥登录。

## 阶段 D：ComfyUI 目录与后端定型

按《docs/setup-guide.md》第 5 章处理（要点复述，防你漏读）：
- 后端唯一入口是 `comfy-backend.ps1`，启动参数固定 `--port 8189 --input-directory <Shared>\input --output-directory <Shared>\output`，**不要加 `--base-directory`**；
- 安装目录 `models` 下 `diffusion_models / loras / vae / text_encoders` 四个目录用**目录联接**指向 `<Shared>\models` 对应目录，保留 `*_bak` 与可能出现的 `*_old_…`，回退见配置指南第 5.2 节；
- 局域网与 Tailnet 入口走 Windows 主机内的 portproxy `8188 → localhost:8189`（8188 被 IP Helper 占用是正常现象，台账条目 1）。

**验收**：局域网另一台设备打开 `http://<Windows局域网IP>:8188` 能进 ComfyUI 界面，工作流里模型不报 Missing（先核对联接目标和模型文件，再在 Issues 面板点 Refresh）。

## 阶段 E：Mac 侧配置（家庭版跳过 RDP 与重定向）

1. Mac 装 Tailscale 并登录**同一账号**，确认状态 Connected、设备列表里能看到 Windows 那台；
2. Mac 安装微软 **Windows App**，新建 PC：地址填 Windows 的 **Tailscale IP**；凭据新建一条并**绑定到这个 PC 的配置里**（只存不绑定会每次弹密码框，台账条目 10）；确认目标主机的证书后再勾「始终信任」；
3. 文件夹重定向挂一个 Mac 本地文件夹用于互传文件（跨桌面直接粘贴文件不通，台账条目 17/19）；
4. Windows 的 Tailscale 设置开机自启，Mac 侧在「系统设置 → 通用 → 登录项」确认有 Tailscale（应用内复选框不回显是 bug，台账条目 16）。

**验收**：双击该 PC 配置免密进入 Windows 桌面；在重定向文件夹里放一个文件，Windows 侧 `\\tsclient\` 下能看到。

## 阶段 F：端到端总验收（按已选功能逐项验收）

- [ ] Windows 重启并登录任务绑定账号后，检查后端自动启动并通过 8189 HTTP 验活；
- [ ] Mac 双击直连 RDP 免密进入；
- [ ] 互传文件双向各一次成功；
- [ ] 在 Mac 浏览器打开 Tailscale IP 的 8188 端口能进 ComfyUI；
- [ ] 4 个模式工具都在 Windows 公共桌面、双账号登录都可见；
- [ ] 向用户交代「报错协议」：以后工具出问题，他只需说一句「报错了」，由智能体读同目录日志定位处理；
- [ ] 保持两台电脑的 Tailscale 在线，重启或变更会话后复查。两个任务依赖交互式登录，看门狗只检查端口。

---

## 阶段 G（可选）：本地部署 MiniMax H3

按 `docs/h3-deployment.md` 操作：装 ComfyUI Desktop → 核对 H3 的 T2V 模板、正式模型名及来源后下载模型 → R2V 另下 ref2va 模型与 turbo LoRA → 核对模板的分辨率映射（既有记录为 0.9）→ 按模板核对步数（官方示例默认 20 步，可选 Turbo 示例为 FL2VA 8 步、R2V 4 步） → R2V 接线（核对 ref_video 的输入类型，按既有记录先拆帧为 IMAGE）→ 换人走两段式。

- 按模板版本和依赖清单核对下载量，开始下载前跟用户确认存放磁盘。
- 渲染分工按 `docs/h3-deployment.md` 第 7 节：小样 Mac 本地出、批量长段 Windows 并行、最终 Mac 定稿。

**验收**：T2V 跑通 5 秒成片；R2V 两段式跑通，人物未漂移、背景已换、动作保留。

---

## 给用户的启动词（用户把下面这段话连同本工具包一起发给智能体即可）

> 请阅读这个仓库里的《AGENTS.md》，按阶段顺序在我的电脑上完成配置。先只做阶段 A 的环境自检，把报告给我看，我确认后再继续。需要我本人操作的步骤，停下来一步一步告诉我点哪里。全程按手册的验收标准自检，做完一个阶段向我汇报一次。
