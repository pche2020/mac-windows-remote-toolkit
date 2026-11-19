# 本地部署 MiniMax H3：ComfyUI + INT8 量化

> 现场参数和耗时沿用既有记录。本次未复跑工作流，模板、节点与模型文件须按实际安装版本核验。
> 远程操控通道（Tailscale + SSH + RDP + ComfyUI 局域网）见 `docs/setup-guide.md`；通用故障速查见 `docs/troubleshooting.md`。本文只讲 H3 本身。

## 1. 模型身份与来源

本文沿用仓库中的 MiniMax H3 称呼。正式名称、发布版本、参数规模、本地输出规格、API 能力及部署支持范围待核。MiniMax 部署文档将 ComfyUI 模板指向 `Comfy-Org/MiniMax-H3` 的裁剪和量化制品（含 INT8/NVFP4）。MiniMax 原始检查点采用混合 BF16/FP32。实际模板文件与修订待核。[MiniMax 本地部署文档](https://platform.minimax.io/docs/guides/local-deploy-h3)

社区许可排除美国、欧盟、英国和韩国。商业产品或服务须显著标注 MiniMax H3，相关年收入超过 2,000 万美元须事先取得书面授权。再分发须遵守地区与可接受使用政策，并按条款附协议副本、注明修改及提供 NOTICE。ComfyUI 指南对本地生成结果的商用另有许可说明，两者如何适用于具体用途待核。[社区许可全文](https://huggingface.co/MiniMaxAI/MiniMax-H3/raw/main/LICENSE) · [ComfyUI 指南](https://docs.comfy.org/tutorials/video/minimax/minimax-h3)

## 2. 硬件与测量口径（待核）

既有主机快照记录了 16G 显存和 32 GB 物理内存（16 GB × 2）。另一条记录提到约 44 GB 内存占用，未注明指标、进程或系统范围，也未注明测量时间。通用最低配置、实际占用和复现条件均待核。

复核时记录 GPU 型号、显存、物理内存、驱动、Desktop 与后端版本、模型文件、工作流、分辨率、时长和内存指标。

## 3. 部署步骤

### 3.1 前置条件

1. 本地生成需核对工作流的硬件及软件要求。使用 RDP 时，另按[配置指南](setup-guide.md)核对 Windows 版本。
2. 下载量按所用模板版本和依赖清单核算，并给输出和中间文件预留空间。
3. 使用 NVENC 时，核对所装 ffmpeg 构建的 NVENC API 与驱动兼容性。原记录中的版本组合待核。

### 3.2 安装 ComfyUI Desktop

1. 装 ComfyUI Desktop，安装器里没有"本地部署 / 镜像加速"选项时不用找，直接下一步。
2. 运行方式页选"本地"，再选 NVIDIA GPU，界面记录来自 Desktop v0.42.1，模板和后端版本待核。
3. 预装工作流页点第一张 MiniMax H3 Text to Video 卡片（标注"推荐"），点安装，下载前核对模板以及实际下载量。
4. 验证：运行 T2V 工作流，检查能否生成 5 秒视频，结果待复核。

找模型目录时，若当前版本和既有 Desktop v0.42.1 记录一样缺少 Help → Open Folder 入口，可用文件搜索。直接在文件资源管理器里搜一个已有的模型文件名，右键"打开文件所在的位置"即到 `diffusion_models`。模板库在左侧边栏的四宫格图标里，Video 分类下原记录列出 MiniMax H3 T2V / 图生视频 / 参考生视频三个模板。

### 3.3 三条工作流的关系

| 工作流 | 模型关系 | 是否要另下载 |
|---|---|---|
| Text to Video（T2V） | 主模型 FL2VA | 随预装工作流下载，容量待核 |
| Image to Video（I2V） | 与 T2V 共用同一套 FL2VA 模型 | 不用重下。同一节点两种用法：first_frame 留空就是文生视频，接一张首帧图就是图生视频 |
| Reference to Video（R2V） | 独立的 ref2va 模型 | 要另下载，见下 |

R2V 的两个关键文件：

- 主模型：`minimax_h3_ref2va_pruned_int8_convrot.safetensors`（MiniMax 部署文档所列 Comfy-Org 转换文件，本机实际修订待核），放进 `<Shared>\models\diffusion_models`。
- 可选加速使用与模板匹配的 Turbo LoRA。既有试样实际使用的文件修订、强度和节点配置待核。

## 4. 分辨率与步数

| 设置 | 工作流说明 |
|---|---|
| Resolution Selector | 0.9 对应 1280×736，映射与像素上限随所用模板核对（待核） |
| 标准模式 | 官方示例默认 20 步。实际模板的步数设置待核 |
| turbo 模式 | 可选 Turbo LoRA 示例为 FL2VA 8 步、R2V 4 步。[MiniMax 部署文档](https://platform.minimax.io/docs/guides/local-deploy-h3) |

可先用低分辨率试样，再按实际模板支持的分辨率生成成片。

## 5. R2V 接线与两段式换人

### 5.1 接线

既有记录中，`MiniMaxH3ReferenceToVideo` 的 `ref_video` 接收 IMAGE 帧图。以当前安装节点的输入类型为准（待核）。

正确接法：

```
LoadVideo 的 VIDEO 输出
  → GetVideoComponents（获取视频元素）的 video 输入
    → 它的 images（帧图）输出 → ref_video_0
    → 它的 audio 输出 → ref_video_audio_0（可选，给参考视频配原声）
```

直接把 VIDEO 输出拖到 ref_video_0 必失败，套接字圆点颜色也能佐证：IMAGE 是蓝色，和 ref_image 同色。

其他 R2V 要点：

- 参考素材上限以当前模板和模型说明为准（待核）。
- 提示词用中文写，但 `<Picture 1>` / `<Video 1>` / `<Audio 1>` 这类标签保持英文原样，且标签序号必须和连线顺序一致。
- 模板本身不带"加载视频"和"获取视频元素"节点，这两个是手动加的。
- Load Video 选文件要在节点本体上选 input 目录里的纯文件名。在右侧 Nodes 面板文本框里改值不写回节点本体，白改。文件不在 input 时，先把文件拷进共享目录的 input 文件夹，再在节点本体点 file 字段选纯文件名。
- 成片取法：SaveVideo 的 history outputs 挂在 images 键下，不是 videos；产物在 output 文件夹。

### 5.2 R2V 两段式换人

既有记录中，带清晰正脸的参考视频曾导致换人失败。可按以下两段分别验收，复现条件待核。

- **第一段：只换人，背景不动。** 用参考视频 + 目标人物肖像，产出 1280×736、5 秒左右带原声的换人版。核验标准：主角确已换成目标人物，舞蹈和背景不变。
- **第二段：再以第一段成片为 Video 参考，做三合一合成。** 先让参考素材中的人物身份一致。核验三要素：人物未漂移、背景换成目标背景（例如赛博朋克街道）、原版舞蹈动作保留。

## 6. 既有生成耗时记录（1280×736、5 秒）

硬件、模型版本、计时边界和复现结果待核。20 步计时来自纯图片参考。第二阶段视频参考有 Turbo 试样记录，20 步标准正式版是否完成待核。

| 任务 | 模式 | 记录耗时 |
|---|---|---|
| R2V 纯图片参考 | 20 步标准 | 约 12.6 分钟 |
| R2V 纯图片参考 | turbo 4 步 | 约 2.7 分钟 |
| R2V 带视频参考（第二段） | turbo | 约 11–12 分钟 |


## 7. Mac / Windows 渲染分工（ffmpeg NVENC）

总原则：Mac 当大脑和审片台，Windows 当 GPU 渲染和生成机。Mac 是脚本、EDL、成片的唯一真源；Windows 只出渲染结果和生成素材，不改 Mac 的源文件和 EDL。大视频文件别来回传，任务放素材所在的那边做，只传回成片和日志。

- **小样 Mac 本地出、批量长段 Windows 并行、最终 Mac 定稿。**
- 日常：剪完一段，先在 Mac 用 VideoToolbox 出小样立即审，不走隧道、不等传输。
- Windows 并行与批量（满足任一才用）：要同时出多版本、单段较长、或 Mac 要继续剪不能被渲染占住时，把源片一次性发 Windows，用 NVENC p7、8M 渲，只回传成片 MP4 与渲染日志，Mac 继续剪不用等。
- 传输规则：源片只发一次、文件名锁定；不来回传中间文件；回传只传成片，不传工程与中间帧；传输走后台 scp，不阻塞剪辑。
- 最终成片（锁在 Mac）：VideoToolbox，720p 用 8M、1080p 用 10M，yuv420p、30fps，音频直接复制或 AAC 192k，参数冻结后不再换编码器与码率。
- 命名：`<项目>-<日期>-draft-<编码器>-<码率>-v<n>.mp4`；每渲一次记一笔：源片、参数、耗时、大小、审片结论，下次直接复用，不重新试参数。

既有编码记录（复现待核，30 秒合成小样与真实口播素材，同定码率对照）：Windows NVENC 比 Mac VideoToolbox 快约 1.4–1.5 倍；同定 8M 时 Mac 实际码率约高 14%，同码率下肉眼基本分辨不出差别，成片经平台再压后差别基本会被抹平。

**概念纠正：渲染不经过大模型，agent 只是写命令的人，执行的是 ffmpeg 的编码器（NVENC / VideoToolbox）。画质差距不是本地部署模型导致的。**

## 8. H3 专属坑速查

| 症状 | 定位与处理 |
|---|---|
| 分辨率 1.0 报错 / 生成失败 | 核对当前模板的分辨率限制，按第 4 节复核 0.9 |
| 找不到 steps 滑杆 | 核对模板的默认步数与对应的 Turbo 配置 |
| ref_video 连不上 / 报类型错 | ref_video 是 IMAGE 不是 VIDEO，参考视频先经 GetVideoComponents 拆成帧图再连 ref_video_0 |
| R2V 成片人物不是目标人物 | 照片抢不过视频，走两段式：先只换人、背景不动，再以换人版为参考合成 |
| 前端报 Missing Models | 先确认四个模型联接还在，再点 Issues 的 Refresh，不必整页刷新 |
| Load Video 选不到文件 / 值改了没用 | 文件先拷进共享 input 文件夹，在节点本体选纯文件名；右侧面板改值不写回本体 |
| 成片找不到 | SaveVideo 的 history outputs 挂在 images 键下，不是 videos；去 output 文件夹找 |
| ffmpeg 报 NVENC API 版本不支持 | 比对当前 ffmpeg 构建要求和驱动实际支持的 NVENC API |
