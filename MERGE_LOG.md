# 合并记录（MERGE LOG）

本仓库不做 fork，上游源码**不进入**本仓库的历史：每次构建按 `VERSION` 里的 tag 现场拉取上游、再打 `patches/`。
因此"合并上游"= 改版本号 + 让补丁继续能打上，天然没有 merge 冲突。

**规矩：每一次合并上游版本，都必须在这里追加一条记录，并更新顶部表格。**

## 时间线

| 日期 | 上游版本 | 上游提交 | 本地补丁 | 构建 | 上机测试 | 备注 |
|---|---|---|---|---|---|---|
| 2026-11-12 | v1.6.0 | 88e5876 | 0001, 0002 | ✅ | ✅ H700 | 首次导入 |
| 2026-11-12 | v1.6.0 | 88e5876 | 0001, 0002 | ✅ | ✅ H700 | 修复播放白闪（`v1.6.0-r1`） |

## 2026-11-12 · v1.6.0（首次导入）

- **上游**：`xfangfang/wiliwili`，分支 `yoga`，release `v1.6.0`，提交 `88e5876`
- **合并方式**：首次导入。仓库只保存补丁与打包脚本，构建时按 tag 拉源码
- **冲突**：无（首次）
- **本地补丁**：
  - `0001-dynamic-up-mid-as-string`：动态页 `up_list` 里 `mid` 可能是字符串，`NLOHMANN_DEFINE_TYPE_NON_INTRUSIVE` 会抛 `type must be number, but is string` 打挂整页，改为兼容两种类型
  - `0002-image-request-headers-and-retry`：图片请求没设请求头，libcurl 的 `User-Agent: curl/7.68.0` 在 B 站图床缓存未命中时被 ACL 判 403（`X-Error-Info: acls.access`），导致部分封面永久空白；补 `HTTP::HEADERS` + 最多 3 次重试
- **构建**：GitHub Actions `build-port`（ubuntu-24.04-arm + bionic 容器），run [43155311161](https://github.com/chaoes/wiliwili_rebuild_ports/actions/runs/43155311161) 成功（产物改名后重建，二进制可复现，md5 与上轮一致）
- **上机**：H700（muOS 2606.0 ANDROMEDA，Mali-G31 / GLES 3.2）通过 —— 测的就是 CI 产物 zip 解包后的二进制（7,276,320 字节，md5 `a585f8a831eb12c9cb61325972d54b83`）：首页 16 张封面全部加载、`image request failed` 0 条、动态页无 `type_error.302`、视频播放/全屏/弹幕/音频正常、退出码 0
- **产物**：`wiliwili-port-v1.6.0-aarch64.zip`（53,378,731 字节，sha256 `6dd64a2a5be3d02044856a3ee128514be5f9d43bb93e6d5c0a14287ca3180e7e`）
- **依赖**：`deps-v1.6.0`（libs.aarch64 188 个库 + gl4es v1.1.7）

## 2026-11-12 · v1.6.0-r1（修复播放视频时白屏闪烁）

- **上游**：不变，仍是 `v1.6.0` / `88e5876`（这次只动打包脚本，不涉及上游代码）
- **问题**：从系统的 Ports 列表启动后播放视频，屏幕会间歇闪出纯灰白空帧（实测连拍 40 帧有 3 帧是 16355 字节的纯色帧）
- **根因**：muOS 的启动脚本 `SETUP_SDL_ENVIRONMENT` 会导出 `SDL_BLITTER_DISABLED=1`。这个变量让 muOS 改过的 SDL2 走直写 fb 的呈现路径，偶发只把清屏帧送上屏
- **实测数据**（H700，同一诊断二进制，各连拍 40 帧统计 < 100 KB 的空帧）：
  - 无额外变量：0/40
  - 只有 `SDL_HQ_SCALER=0`：0/40
  - `SDL_BLITTER_DISABLED=1`：30/40（白闪）
  - `SDL_BLITTER_DISABLED=0`：2/40（仍有残留）
  - `unset SDL_BLITTER_DISABLED`：0/40
- **修复**：`port/Wiliwili.sh` 里在启动前 `unset SDL_BLITTER_DISABLED`（不是设 0，设 0 仍会闪）
- **验证**：改脚本后仍走系统列表路径（前端先退出，只有一个 fb0 写入者）播放视频，连拍 40 帧 **0 帧空帧**
- **产物**：`wiliwili-port-v1.6.0-r1-aarch64.zip`

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