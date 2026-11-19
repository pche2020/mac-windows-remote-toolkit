# 配置文档：Mac + AI 助手直连 Windows 电脑（远程操控与 ComfyUI）

> 本文档保留 2026-10-20 ~ 2026-10-21 的配置经验，当前环境按第 9 章重新验收。
> 目标读者：任何想在自己电脑上复现这套配置的人。每一步都写了「怎么做」和「可能出什么问题、怎么解决」。
> 配套：`scripts/setup-windows.ps1` 一键脚本、`docs/troubleshooting.md`（全部踩坑记录）、仓库内其余脚本。

---

## 第 0 章 最终形态（先看懂全貌再动手）

搭好之后你会得到：

- **Windows 电脑 24 小时开机待命**，ComfyUI 后端在任务绑定账号登录后启动，看门狗每 5 分钟检查端口并尝试补启动。
- **人在家**：Mac 上打开远程桌面（Windows App）双击直连操作 Windows；浏览器打开 `http://<Windows局域网IP>:8188` 就是 ComfyUI。
- **人在外面**：Mac 先连上 Tailscale，远程桌面和 ComfyUI 网页照常用（地址换成 Tailscale 的 100.x 地址），和在家没有区别。
- **AI 助手**：通过 SSH（走 Tailscale）直接在 Windows 上执行命令、启停 ComfyUI 后端、用接口提交生成任务、取回成片——不需要你守在电脑前，也不需要经过 Mac 中转。
- **访问范围**：生效入站规则限定到所需的局域网与 Tailnet 来源，路由器保持无公网端口映射。

数据流向（记住这张图，后面排障全靠它）：

```
Mac ──远程桌面(RDP 3389)──┐
Mac ──浏览器(8188)────────┤  在家: 局域网直连
AI助手 ──SSH(22)──────────┤  在外: 全部先穿 Tailscale 加密通道
                          ▼
              Windows 电脑 (24h 开机)
                ├─ sshd (OpenSSH)          :22
                ├─ 远程桌面服务             :3389
                ├─ portproxy               :8188 → 转发到 localhost:8189
                └─ ComfyUI 后端 (手动模式)  :8189  ← 真正干活的进程
```

**复现时填你自己的参数**：

| 项目 | 本例的值 |
|---|---|
| Windows 电脑 | Tailscale IP `<Windows Tailscale IP>`，局域网 IP `<Windows 局域网 IP>` |
| Mac | Tailscale IP `<Mac Tailscale IP>`，局域网 IP `<Mac 局域网 IP>` |
| AI 助手运行环境 | Tailscale IP `<助手 Tailscale IP>` |
| ComfyUI 安装目录 | `H:\Comfy-Desktop\ComfyUI-Installs\ComfyUI\ComfyUI` |
| ComfyUI 共享目录（模型/输入/输出） | `H:\Comfy-Desktop\ComfyUI-Shared` |
| 远程桌面专用账号 | 本地账号 `rdp`（密码只在 Windows 本机设置） |

---

## 第 1 章 前置条件

1. **Windows 电脑**：RDP 主机使用 Windows 10/11 **专业版或企业版**。家庭版按第 3、5 章分别配置 SSH 与 ComfyUI，跳过 RDP 和文件夹重定向（一键脚本的 `-SkipRdpUser` 只跳过建账号）。管理员账号可用。建议接有线网络或稳定的 Wi-Fi，并关闭睡眠（见第 5 章末）。
2. **Mac**：能装 App Store 应用即可。
3. **一个 Tailscale 账号**：免费版足够（3 台设备以内免费额度够用）。用一个你长期能登录的账号注册——
   - ⚠️ 注意：Tailscale 账号就是整套通道的钥匙，账号丢了等于全套重建。不要用有风险的账号。
4. **ComfyUI Desktop**（可选，只要远程操控电脑可以跳过第 5 章）：已安装并能本地正常打开。
5. **AI 助手一侧**：助手需要有一对 SSH 密钥。你只需在第 3 章把助手的**公钥**（一行以 `ssh-ed25519` 开头的文字）贴到 Windows 上，私钥永远只在助手那边。

---

## 第 2 章 Tailscale 组网（两台机器都装、同一账号登录）

这是整套配置的地基：先让所有设备进同一个私有网络，后面每一步都建在它上面。

### 2.1 Windows 侧

1. 到 tailscale.com 下载 Windows 版安装（或在已有安装的情况下直接打开）。
2. 安装后从开始菜单打开 Tailscale，用你的 Tailscale 账号登录。
3. 登录成功后，托盘（右下角）会出现 Tailscale 图标，状态为已连接。
4. 记住这台机器的 Tailscale IP：点托盘图标或打开界面能看到，形如 `100.x.x.x`。后面 RDP、网页、SSH 全用它。

### 2.2 Mac 侧

1. 在 App Store 安装 **Tailscale**，打开后点 `Start the Tailscale app` 一类引导，用**同一个账号**登录。
2. 系统会要求允许添加 VPN 配置——允许。
3. 打开「系统设置 → 通用 → 登录项」，确认列表里有 Tailscale（保证 Mac 登录后自动在网）。
   - ⚠️ **坑**：Tailscale 应用内设置里的「Launch Tailscale at login」复选框可能不回显勾选状态（本例实测点了也不显示变化），**以系统「登录项」列表为准**，不要在这个复选框上反复纠结。
4. 在 Tailscale 界面里应能看到三台设备（Windows、Mac、助手）都在线。

### 2.3 本章常见问题

| 现象 | 原因与解决 |
|---|---|
| 设备列表里看不到某一台 | 那台没登录同一个账号，或它的 Tailscale 没连上；在那台机器上打开 Tailscale 确认状态为 Connected |
| Mac 上状态显示 Not Connected | 点界面上的 **Reconnect**；还不行就完全退出 Tailscale 再打开。注意：远程控制工具去点这个按钮时，VPN 一连通 Mac 网络会切换、控制通道可能超时——按钮其实多半已经点中了，等十几秒再复查，不要连点 |
| 出门后连不上家里的 Windows | 先确认 Mac 的 Tailscale 是 Connected 状态，再确认 Windows 那台没睡着、没断网（见第 5 章电源设置） |

---

## 第 3 章 SSH 通道（助手直连 Windows 的入口）

`setup-windows.ps1` 会自动做完本章的 Windows 侧全部动作（装 OpenSSH、设自启、装公钥、修权限）。手动做的意义是出问题时知道查哪。

1. **安装 OpenSSH 服务器**（Windows 可选功能 `OpenSSH.Server`），把 `sshd` 服务设为自动启动并启动。核对生效的 SSH 入站规则，将来源收口到所需的 Tailnet（需要局域网访问时再纳入局域网）。安装脚本只登记公钥，不修改 SSH 防火墙规则或禁用密码登录。验收时检查服务端仅允许公钥认证。
2. **安装助手的公钥**：
   - 登录账号是**管理员**时，公钥必须放在 `C:\ProgramData\ssh\administrators_authorized_keys`（不是个人目录的 `.ssh\authorized_keys`，放错地方永远登录不上且不报错原因）。
   - 该文件的权限必须收紧：仅 SYSTEM 与 Administrators 可访问、关闭继承。`setup-windows.ps1` 已用 icacls 处理；手动放文件后如果 SSH 提示权限相关错误，先查这里。
   - 普通（非管理员）账号才用 `%USERPROFILE%\.ssh\authorized_keys`。
3. **助手侧连接方式**：`ssh <用户名>@<Windows的Tailscale IP>`，密钥登录。助手的环境如果没有到 tailnet 的直达路由，需要它自己解决转发——这是助手侧的实现细节，不影响 Windows 侧配置。
4. **验收**：助手能免密登录并执行命令（例如返回主机名）即通。

| 现象 | 原因与解决 |
|---|---|
| `Permission denied (publickey)` | 公钥放错文件（管理员账号查 `ProgramData\ssh\administrators_authorized_keys`）；或文件权限过宽被 sshd 拒绝；或贴公钥时被聊天软件折行——公钥必须完整一行 |
| 连接超时 | 先查两端 Tailscale 是否都 Connected、目标 IP 是否写对；再查 sshd 服务是否在运行 |
| 助手说「通道断了，报 proxy closed」 | 助手侧隧道或目标机 Tailscale 掉线。先在 Mac 的 Tailscale 设备列表看 Windows 那台是否在线：在线 = 助手侧隧道问题，等它自恢复或让助手换路径；不在线 = 去 Windows 机器上把 Tailscale 重新连上 |

---

## 第 4 章 远程桌面（RDP）

`setup-windows.ps1` 会自动完成开启、NLA、防火墙收口和专用账号创建。原理与坑如下。

### 4.1 Windows 侧开启

1. 注册表/设置开启远程桌面（`fDenyTSConnections=0`），开启 **NLA（网络级别身份验证）**，远程桌面服务设为自动。
2. **防火墙收口（重要）**：系统自带的「远程桌面」防火墙规则默认对所有来源开放，必须把远程地址限定为 `LocalSubnet` + Tailnet 网段（具体网段值见一键脚本 `setup-windows.ps1` 里的 `$TailnetRange`，是 Tailscale 的固定共享网段，所有用户都一样）。这样只有你家里局域网和你自己的 tailnet 能碰到 3389，**绝不做路由器公网端口映射**。

### 4.2 专用账号（本章最容易卡的一步）

- ⚠️ **大坑**：如果你的 Windows 主账号是**微软账号**，RDP 登录**只认微软账号的密码、不认 PIN**，而且让你在别的设备上输入微软账号密码既危险又麻烦（本例实测连试 3 次被拒，安全日志报密码错误 `0xC000006A`）。
- **正解**：在 Windows 本机新建一个**专用本地账号**（本例叫 `rdp`）：
  1. 在 Windows 本机（不要通过聊天传递密码）执行设密创建，或用 `setup-windows.ps1` 在本机控制台按提示输入密码。
  2. 把它加入 **Administrators** 和 **Remote Desktop Users** 两个组。
  3. 日常在本机还是用原账号 + PIN 登录；远程时用这个专用账号。两个账号互不影响。
- 注意：远程登录会把本机当前会话顶回登录界面（同一时刻一个账号一个交互会话），属正常现象，不是故障。

### 4.3 本章常见问题

| 现象 | 原因与解决 |
|---|---|
| 密码明明对却登录被拒 | 多半是微软账号 + PIN 的坑（见 4.2），改用专用本地账号；再查安全日志事件 4625 的子状态码确认是不是密码错 |
| 连上后黑屏/立即断开 | 会话被另一处登录顶掉；或显卡驱动在远程会话切换时异常，等 10 秒重连通常自愈 |
| 外网环境连不上、在家可以 | 外网必须先连 Tailscale 再连 RDP，且防火墙规则里要有 Tailnet 网段（见 4.1） |

---

## 第 5 章 ComfyUI 后端（局域网/远程可访问 + 自启 + 看门狗）

ComfyUI Desktop 自己运行时只监听本机，别的设备打不开。做法是：**不用 Desktop 的内置后端，改用一个手动启动的后端进程**，监听局域网可达的端口，并把输入/输出/模型指到 Desktop 的共享目录，两边共用同一套模型和产物。

### 5.1 端口拓扑（为什么是两个端口）

- 后端使用 **8189**，在 Windows 本机用 `http://localhost:8189/system_stats` 验活。核心脚本未显式设置监听地址，实际绑定待核。
- Windows 主机内的 portproxy 在所有 IPv4 接口监听 **8188**，转发到 `localhost:8189`。启用转发时 IP Helper 占用 8188 属于预期行为，冲突案例见故障台账第 1 条。
- 8188 的入站来源限定为局域网与 Tailnet。复查生效的防火墙规则（含已有规则）与监听地址，路由器保持无公网端口映射。

### 5.2 模型目录联接（第二个大坑）

- 手动启动的后端**只认安装目录下的 `models`**，而 Desktop 把模型放在共享目录 `ComfyUI-Shared\models`。不处理的话后端能起来、但报一堆 **Missing Models**。
- 解法：把安装目录 `models` 下的四个大文件夹 `diffusion_models`、`loras`、`vae`、`text_encoders` 改名备份后，用目录联接指到 Shared 的对应目录：
  `mklink /J "安装目录\models\diffusion_models" "共享目录\models\diffusion_models"`（其余三个同理）。
- 模型文件实体只有 Shared 里一份，Desktop 和手动后端看到的是同一套。`开启局域网模式.bat` 的第 4 步会自动检查并补建这些联接（幂等）。
- 后端起来后如果前端报 Missing Models，先核对联接目标和模型文件，再到 Issues 面板点 **Refresh**。

- 原目录优先保留为 `*_bak`，同名已存在时会另存为 `*_old_…`。切回 Desktop 前先停用看门狗，再用 `restore-desktop-mode.bat` 停后端、移除转发和联接。脚本只尝试恢复 `*_bak`，有多份备份时先确认应恢复哪份，保留 Shared 的模型实体。切回局域网模式后按需重新启用看门狗。
- 默认路径见附录 A。自定义安装路径时，除设置安装脚本参数，还要同步核心脚本和各批处理中的相应路径。后端启动命令当前未给路径加引号，含空格的路径兼容性待核。

### 5.3 后端启停

日常启停使用核心脚本 `comfy-backend.ps1`（放在 `ComfyUI-Shared\tools\`）：

- 参数 `-Action start / stop / status`；start 与 status 按 8189 是否监听判断，start 返回成功后还需验证 HTTP。
- 后端通过 WMI（`Win32_Process.Create`）启动，规避台账第 5 条记录的 SSH 会话结束后进程退出问题。其他长任务需单独安排后台执行与日志，并在断开后重新连接检查状态。
- 后端启动参数固定：`main.py --port 8189 --input-directory <Shared>\input --output-directory <Shared>\output`。
- 日志两份：后端自身输出 `ComfyUI-Shared\comfy-backend.log`；启停审计 `comfy-backend-control.log`（每次 start/stop/status 都记一行，出问题先看它）。
- ⚠️ **不要加 `--base-directory`**：加了会让目录关系错乱（本例实测踩过），只用上面两个 `--input/--output-directory` 参数。

### 5.4 自启与看门狗

- 计划任务 `ComfyUI-Backend-Autostart`：管理员账号**登录时**触发，调用核心脚本 start。
- 计划任务 `ComfyUI-Backend-Watchdog`：每 5 分钟调用一次核心脚本 start（幂等）。两个任务均以安装时的账号和交互式登录运行，重启后需登录该账号。恢复时间取决于任务是否能运行及后端启动结果。
  - 历史记录：2026-10-21 上午后端曾**静默消失**一次（无 stop 记录、无崩溃事件、日志结尾是正常启动输出，死因至今未定）。看门狗就是对这种「原因不明但影响明确」的兜底。
  - 看门狗的边界：它只检查端口是否在监听；进程假死（端口在、接口不响应）它查不出来。真遇假死，手动跑一次 stop 再 start。
- 桌面兜底按钮：公共桌面上有「启动ComfyUI后端.bat / 关闭ComfyUI后端.bat」，最终也是调核心脚本。

### 5.5 桌面工具摆放：公共桌面

- 机器上有多个账号时，工具必须放在 **`C:\Users\Public\Desktop`（公共桌面）**，所有账号登录都能看到；放在某个账号的个人桌面，其他账号（比如远程专用账号 `rdp`）看不见——本例实测在 rdp 桌面上找不到那几个 .bat，就是这个原因。
- 同理，想让所有账号桌面一致：把应用快捷方式统一放公共桌面（本例把 35 个常用软件快捷方式从主账号桌面挪进公共桌面，两边桌面从此一致）。个人文档不要挪，留在个人桌面即可。
- 工具母本只维护一份（随本工具包），改完同步到公共桌面并校验，别让多个副本各自漂移。

### 5.6 电源与待命

- Windows 电源计划设为**从不睡眠**（至少交流供电时），否则人一出门机器睡了，所有远程通道全断。
- 显示器可以关，不影响服务。

## 第 6 章 Mac 侧：Windows App 远程桌面（一次配置、双击直连）

1. Mac 的 App Store 安装微软官方 **Windows App**（旧名 Microsoft Remote Desktop）。
2. 添加 PC：地址填 Windows 的 **Tailscale IP**（在外在家都通）；在家也可以再加一个局域网 IP 的条目，但一个 Tailscale 条目就够全场景用。
3. **保存凭据并绑定（关键两步，缺一不可）**：
   1. 在 Windows App 的「设置 → 凭据」里新建一条凭据，账号填专用本地账号（本例 `rdp`），密码填你在 Windows 本机为它设的密码。
   2. 回到这台 PC 的「配置…」里，把凭据下拉从「在需要时询问」**改选为刚存的那条凭据**并保存。
   - ⚠️ 只做第 1 步不做第 2 步，连接时照样每次弹框要密码——本例实测就是卡在这里，绑定后双击即免密直连。
4. **证书**：第一次连接会弹出自签名证书警告（因为走的是 IP 直连、无域名证书）。通道本身有 Tailscale 加密兜底，确认目标 IP 是你的 Windows 机器后，勾选 **「始终信任」** 再继续，以后不再弹。
   - 能弹出证书框本身就证明 Mac 已经通过 tailnet 摸到了 Windows 的 3389 端口——弹框不是失败，是待确认。
5. 验收：在家双击 PC 图标 → 无密码框 → 直接进入 Windows 桌面。

| 现象 | 原因与解决 |
|---|---|
| 每次连接都要输密码 | 凭据只存了没绑定，去 PC 的「配置…」里把凭据下拉改选为已存凭据（见本章第 3 步） |
| 证书警告每次都弹 | 上次没勾「始终信任」就点了继续；重连一次，勾上再继续 |
| 提示连不上主机 | 按顺序查：Mac 的 Tailscale 是否 Connected → Windows 是否开机未睡 → 地址是不是 Tailscale IP（别用机器名乱试） |

---

## 第 7 章 两台机器之间传文件

先说结论：**用「文件夹重定向」通道，别指望跨桌面直接粘贴文件。**

- ⚠️ **实测**：在远程会话里复制 Windows 桌面上的文件、切回 Mac 往桌面粘贴，会报 Mac 的**错误 -43**（找不到项目）——Mac 版 Windows App 的文件剪贴板是个虚拟占位，访达取不到实体。这条路不要再试。文字和图片的剪贴板复制粘贴是正常的，坏的只是文件。

### 7.1 文件夹重定向（推荐，最稳）

1. 在 Mac 桌面建一个专用文件夹（本例：`Mac_Windows传输通道`）。
2. Windows App 里打开这台 PC 的「配置…」→「文件夹」标签 → 启用重定向 → 添加这个文件夹（不要勾只读，即双向可写）。
3. 连上远程桌面后，在 Windows 的「此电脑 → 网络位置」里会出现这个文件夹（地址是 `\\tsclient\Mac_Windows传输通道`）。
4. 往里放文件 = 立刻出现在 Mac 的那个文件夹里；反过来同理。当普通文件夹用即可。

### 7.2 其他传法（按场景选）

- **Taildrop**：Tailscale 自带的文件投递，在两台机器的 Tailscale 界面里选对方发送。适合偶尔传单个文件。
  - ⚠️ Windows 上 Tailscale 界面有个**单占规则**：一台机器同时只允许**一个用户会话**的界面程序接管（本例 rdp 会话里打开 Tailscale 报 `already in use by <主机名>\<主账号>`，就是主账号会话里的界面还占着）。处理：把另一个会话里的 Tailscale 界面进程关掉（只关界面、不停服务，不断网），这边再打开即可。若两个会话都有人用，则先开的一方为准。
- **让助手走 SSH 传**：大文件、批量文件时最省心，助手用 scp 在 Windows 与它自己的存储之间搬运，再转交给你。

---

## 第 8 章 助手侧操作方式（你只需知道这些）

- 你给助手下指令用平时的聊天即可（在家、出差都一样，消息先到助手、助手再走 SSH 操作 Windows，**不经过你的 Mac 中转**，所以你出差时 Mac 关不关机都不影响）。
- 助手操作 ComfyUI 的两只手：SSH 管进程与文件（启停后端、看日志、取成片）；HTTP 接口管生成（提交工作流、查队列、下载产物，走 Tailscale 地址 `http://<Windows Tailnet IP>:8188`）。
- **报错协议**：任何桌面工具（.bat）执行失败，窗口会明确写出失败步骤和原因，并把全过程记进同目录的日志文件。你什么都不用做，在聊天里对助手说一句 **「报错了」**，助手会自己去读日志定位修复——不要自己反复双击重试。
- 分层验活。先检查 Windows 本机的 8189 HTTP 接口，再从 Mac 分别验证局域网和 Tailnet 的 8188。需要确认生成能力时，再提交小工作流并检查队列和产物。助手环境的代理错误只说明该请求失败，按台账第 6 条检查路径。

---

## 第 9 章 验收清单（逐项打勾才算搭完）

- [ ] Mac 与 Windows 的 Tailscale 都显示 Connected，设备列表三台齐（Windows / Mac / 助手）
- [ ] 助手 SSH 免密登录 Windows 成功，能执行命令
- [ ] Windows 重启并登录任务绑定账号后，核验 8189 HTTP；测试看门狗时另查任务触发与 HTTP 恢复结果
- [ ] Mac 上双击 Windows App 的 PC 图标，免密直连、无证书弹框
- [ ] 远程会话里打开「此电脑 → 网络位置」，能看到重定向文件夹，双向各放一个文件验证
- [ ] 浏览器在家打开 `http://<局域网IP>:8188`、用 Tailscale 地址打开 `http://<Tailnet IP>:8188`，两边都是 ComfyUI 界面
- [ ] 防火墙复查：SSH、RDP 与 ComfyUI 生效规则只允许所需的局域网与 Tailnet 来源，路由器上无任何端口映射
- [ ] 公共桌面上工具齐全（模式工具、启停按钮），换另一个账号登录也能看到

---

## 第 10 章 安全与撤销

- **入口盘点**：SSH（22，验证仅公钥认证）、RDP（3389）和 ComfyUI（8188）。检查生效防火墙的来源范围，保持路由器无公网端口映射。
- **撤销助手访问**：移除 Tailscale 设备、停用 OpenSSH 或移除助手公钥。撤销后检查新连接与已建立的会话。
- **密码纪律**：由用户在 Windows 本机设置专用本地账号密码，在 Mac 的 Windows App 凭据库输入并绑定。密码和私钥留在凭据管理端，聊天、脚本与日志只记录非敏感信息。
- **账号纪律**：整套通道的根是 Tailscale 账号，务必用你能长期登录、且本身开了双重验证的账号。

---

## 附录 A 本例关键路径速查

| 用途 | 路径 |
|---|---|
| ComfyUI 安装目录 | `H:\Comfy-Desktop\ComfyUI-Installs\ComfyUI\ComfyUI` |
| 共享目录（模型/输入/输出/日志） | `H:\Comfy-Desktop\ComfyUI-Shared\` |
| 后端核心脚本 | `H:\Comfy-Desktop\ComfyUI-Shared\tools\comfy-backend.ps1` |
| 模式切换日志 | 公共桌面 `ComfyUI模式切换日志.txt` |
| 管理员公钥文件 | `C:\ProgramData\ssh\administrators_authorized_keys` |
| 公共桌面 | `C:\Users\Public\Desktop` |
| 助手侧 SSH 入口 | `ssh <管理员用户名>@<Windows Tailscale IP>`（密钥登录） |

## 附录 B 文档与记录

- 全部故障的完整台账：本仓库 `docs/troubleshooting.md`
