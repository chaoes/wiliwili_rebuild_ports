# 合并记录（MERGE LOG）

本仓库不做 fork，上游源码**不进入**本仓库的历史：每次构建按 `VERSION` 里的 tag 现场拉取上游、再打 `patches/`。
因此"合并上游"= 改版本号 + 让补丁继续能打上，天然没有 merge 冲突。

**规矩：每一次合并上游版本，都必须在这里追加一条记录，并更新顶部表格。**

## 时间线

| 日期 | 上游版本 | 上游提交 | 本地补丁 | 构建 | 上机测试 | 备注 |
|---|---|---|---|---|---|---|
| 2026-11-12 | v1.6.0 | 88e5876 | 0001, 0002 | ✅ | ✅ H700 | 首次导入 |
| 2026-11-12 | v1.6.0 | 88e5876 | 0001, 0002, 0003 | ✅ | ✅ H700 | `v1.6.0-r3`：修白闪、窗口钳制、启动脚本 v5 |
| 2026-11-12 | v1.6.0 | 88e5876 | 0001, 0002, 0003, 0004 | ✅ | ✅ H700 | `v1.6.0-r4`：关于页补移植项目地址 |

## 2026-11-12 · v1.6.0（首次导入）

- **上游**：`xfangfang/wiliwili`，分支 `yoga`，release `v1.6.0`，提交 `88e5876`
- **合并方式**：首次导入。仓库只保存补丁与打包脚本，构建时按 tag 拉源码
- **冲突**：无（首次）
- **本地补丁**：
  - `0001-dynamic-up-mid-as-string`：动态页 `up_list` 里 `mid` 可能是字符串，`NLOHMANN_DEFINE_TYPE_NON_INTRUSIVE` 会抛 `type must be number, but is string` 打挂整页，改为兼容两种类型
  - `0002-image-request-headers-and-retry`：图片请求没设请求头，libcurl 的 `User-Agent: curl/7.68.0` 在 B 站图床缓存未命中时被 ACL 判 403（`X-Error-Info: acls.access`），导致部分封面永久空白；补 `HTTP::HEADERS` + 最多 3 次重试
- **构建**：GitHub Actions `build-port`（ubuntu-24.04-arm + bionic 容器），run [43155311161](https://github.com/chaoes/wiliwili_rebuild_ports/actions/runs/43155311161) 成功（二进制可复现，md5 `a585f8a831eb12c9cb61325972d54b83`）
- **上机**：H700（muOS 2606.0 ANDROMEDA，Mali-G31 / GLES 3.2）通过 —— 测的就是 CI 产物 zip 解包后的二进制：首页 16 张封面全部加载、`image request failed` 0 条、动态页无 `type_error.302`、视频播放/全屏/弹幕/音频正常、退出码 0
- **产物**：`wiliwili-port-v1.6.0-aarch64.zip`（53,378,731 字节，sha256 `6dd64a2a5be3d02044856a3ee128514be5f9d43bb93e6d5c0a14287ca3180e7e`）
- **依赖**：`deps-v1.6.0`（libs.aarch64 188 个库 + gl4es v1.1.7）

## 2026-11-12 · v1.6.0-r3

- **上游**：不变，仍是 `v1.6.0` / `88e5876`。本轮只改构建选项、补一个补丁、清理启动脚本
- **改动一 · 播放时闪白帧（构建选项 `-DMPV_NO_FB=ON`）**
  - 现象：从系统 Ports 列表启动，播放视频时间歇闪出整屏纯灰白空帧
  - 根因：默认构建把视频渲染到独立 FBO，再由应用把该纹理贴到屏幕；在 gl4es 下，这条「纹理 → 默认帧缓冲」的全屏 blit 会触发其内部的交换 hack，偶尔把刚清完屏、还没画内容的那一帧送上屏。让 mpv 直接渲染默认帧缓冲（`MPV_NO_FB`）即可绕开这段路径
  - 实测（H700，连拍 40 帧统计 < 100 KB 的空帧）：不开该选项 30/40，开启后 0/40；对照的上游风格构建同样为 0/40
  - 该选项只影响渲染路径，不改环境变量、不改窗口尺寸
- **改动二 · 新增 `0003-window-size-clamp-to-display`**
  - 现象：窗口状态里记录的尺寸大于面板时，画面被驱动等比缩放，出现黑边、比例不对
  - 根因：部分掌机 SDL 视频驱动按窗口尺寸创建 GL 渲染表面（muOS 的 `mali-fbdev` blitter 路径即是），而 wiliwili 记录的默认窗口是 1280x720、H700 面板是 720x720
  - 修复：`createWindow` 之前用 `SDL_GetDesktopDisplayMode` 把 `VideoContext::sizeW/sizeH` 钳制到显示模式之内；桌面等大屏设备窗口本就小于屏幕，不触发
- **改动三 · 启动脚本 v5（`port/Wiliwili.sh`）**
  - 音频插件探测改为「缓存 + 常见目录 + 浅层 find」，启动从 40–60 秒降到 1 秒内
  - 不再 `mount -o remount,rw /`、不再往 `/usr/lib` 拷插件，只设 `ALSA_PLUGIN_DIR`
  - `~/.asoundrc` 仅在检测到 pipewire 插件且未指向 pipewire 时写入，写前备份；找不到插件时交还系统默认配置
  - `get_controls` / `bind_directories` / `pm_platform_helper` / `pm_finish` / `$GPTOKEYB` 全部加存在性判断，脱离 PortMaster 前端也能启动
- **构建**：build-port，run [43192590181](https://github.com/chaoes/wiliwili_rebuild_ports/actions/runs/43192590181) 成功（含启动脚本 v5 的最终包）
- **上机**（H700，系统 Ports 分类启动）：首页封面全真实、动态页正常；播放视频连拍 40 帧 0 空帧、音频 `RUNNING`；退出码 0
- **产物**：`wiliwili-port-v1.6.0-r3-aarch64.zip`（53,378,056 字节，sha256 `ec44b7d27fa9d0f0dbf7c0c64c5fac749cc2d989e0b92d66a64b77a84d668aac`），二进制 7,280,400 字节 md5 `bf69d98a0c3f77a6f78d55c0895343e4`
- **依赖**：沿用 `deps-v1.6.0`

## 2026-11-12 · v1.6.0-r4

- **上游**：不变，仍是 `v1.6.0` / `88e5876`。本轮只补一处资源文案
- **本地补丁**：新增 `0004-about-port-project-link`
  - 「关于更多」页面原本只有「开源地址」（上游仓库），在它下面补一行「移植项目地址」指向本仓库
  - 改动范围：`resources/xml/fragment/settings_about.xml` 加 Header + Label；7 个语言的 `wiliwili.json` 补 `setting.about.port_repository`
  - 纯资源改动，二进制不变
- **冲突**：无
- **构建**：build-port，run [43217968317](https://github.com/chaoes/wiliwili_rebuild_ports/actions/runs/43217968317)
- **上机**（H700，系统 Ports 分类启动）：「关于更多」页面显示「移植项目地址」与仓库链接，其余页面不受影响
- **产物**：`wiliwili-port-v1.6.0-r4-aarch64.zip`（53,378,207 字节，sha256 `59ad1cf84d0dd24c9a7e4789403442d188d01a68a70a32e0ebdc4d7b8282aa65`），二进制 7,280,400 字节 md5 `bf69d98a0c3f77a6f78d55c0895343e4`
- **依赖**：沿用 `deps-v1.6.0`

---

## 新记录模板（复制这段）

```markdown
## YYYY-MM-DD · vX.Y.Z

- **上游**：`xfangfang/wiliwili` release `vX.Y.Z`，提交 `xxxxxxx`
- **合并方式**：`scripts/merge-upstream.sh vX.Y.Z` 检查 → 改 VERSION → tag 推送
- **冲突**：无 / 补丁 0002 需 rebase（说明改了什么）
- **本地补丁**：0001 ✅ / 0002 ✅ / 新增 0003（说明）
- **构建**：build-port 运行链接
- **上机**：H700 复测结论（改了哪些页面、封面、播放、退出）
- **产物**：zip 名称
- **依赖**：是否沿用 deps-vX.Y.Z，或为何升级
```