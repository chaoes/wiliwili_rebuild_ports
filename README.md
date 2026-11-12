# wiliwili_rebuild_ports

给 **aarch64 掌机** 用的 wiliwili Ports（PortMaster 规范）打包仓库。

> 本仓库**不是** wiliwili 的分支，也不包含上游源码。
> 它只保存「Ports 打包脚本 + 本地补丁」，每次构建时按 `VERSION` 里的 tag 现场拉取上游源码再打补丁。
> 想了解 wiliwili 本身、提功能需求、报上游 bug，请去上游仓库。

## 上游

- 项目：[**xfangfang/wiliwili**](https://github.com/xfangfang/wiliwili) —— 一个用 C++ 写的 B 站客户端
- 当前跟踪版本：`v1.6.0`（分支 `yoga`，提交 `88e5876`），见 [`VERSION`](VERSION)
- 许可证：**GPL-3.0**（见 [`LICENSE`](LICENSE)）

**本仓库不主张任何原创权利**：程序本体、资源、界面、全部代码与文档的著作权归上游作者与贡献者所有。
本仓库的补丁以同样许可证（GPL-3.0）发布，属于上游作品的衍生部分；一旦被上游采纳，这里就会删掉对应补丁。
打包脚本、CI 配置等纯打包内容不涉及上游著作权，但也同样在 GPL-3.0 下提供，供随意取用。

## 修了什么（本地补丁）

这两个问题**在上游源码里就存在**，与交叉编译无关，属于移植时顺手修掉的真实缺陷。
补丁在 [`patches/`](patches)，构建时以 `git apply` 打到上游源码上。

### 0001 · 动态页整页崩溃（`type must be number, but is string`）

B 站关注列表接口有时返回 `"mid":"356307984"` 这种**字符串**，而上游用
`NLOHMANN_DEFINE_TYPE_NON_INTRUSIVE(DynamicUpResult, ..., mid)` 按数字解析，
于是「动态」页整页抛 `json.exception.type_error.302`，什么都显示不出来。

改成手写 `from_json`：字符串走 `std::stoull`，数字照旧 `get_to`，两种都能解析。

### 0002 · 部分视频封面永远空白

同一个页面上总有几张封面永久是灰底占位图，滚走再回来依旧空。原因：

- 图片请求这条路径**没有设置任何请求头**，cpr/libcurl 于是带上了自己的默认 UA（Ubuntu 18.04 的 libcurl 是 `curl/7.68.0`）；
- B 站图床的 CDN 在**缓存未命中**时会对这个 UA 直接返回 `403`（`X-Error-Info: acls.access`），命中缓存时则不做校验；
- 上游请求一次就不再重试，于是这几张图永远留白。

改法：图片请求补上与其它接口一致的 `bilibili::HTTP::HEADERS`（UA `wiliwili`，带 Referer/Origin），
并加最多 3 次、间隔 0.5s/1.0s 的重试，最终失败时打一条带状态码/URL 的 warning。

## 兼容性

Ports 包本身跨平台，只要是下面这类设备都能跑：

- **aarch64**（arm64），glibc **≥ 2.27**
- 装了 **PortMaster** 或同类 Ports 前端（muOS / ArkOS / JELOS / ROCKNIX / Knulli 等布局都兼容）
- 系统有 **SDL2 ≥ 2.28**（包内不带 SDL，复用系统的）
- 有 OpenGL ES 2.0/3.x 的 GL 驱动

当前**实测过的设备**只有一台：**H700（muOS 2606.0 ANDROMEDA，Mali-G31 / GLES 3.2）**。
其它 aarch64 设备理论上可用但没验过；启动脚本里 muOS 专用的部分（pipewire 音频修复、防自动省电）都有存在性判断，换平台不会报错，只是不生效。

## 测试情况

**已在 H700（muOS 2606.0 ANDROMEDA，Mali-G31 / GLES 3.2）上实测通过**：

- 首页 16 张卡片封面全部真实加载，日志 `image request failed` = 0 条
- 「动态」页正常显示关注列表与动态流，无 `type_error.302`
- 视频播放：播放页 → 全屏，进度/清晰度/弹幕/字幕正常，音频设备状态为 `RUNNING`
- 退出走正常路径：`Exiting...` → `mainLoop done` → `exited with code: 0`

上机验证用的就是这里 Release 的 CI 产物（`v1.6.0` 的 zip，sha256 `6dd64a2a…`），不是本地另编的二进制。

每次合并上游都会重新上机复测，结论记录在 [`MERGE_LOG.md`](MERGE_LOG.md)。

## 安装

从 [Releases](../../releases) 下载 `wiliwili-port-<版本>-aarch64.zip`，解压到设备的 Ports 目录
（muOS 常见 `/mnt/mmc/ports/`，其它系统常见 `/roms/ports/` 或 `$XDG_DATA_HOME/PortMaster/ports/`）：

```sh
unzip wiliwili-port-v1.6.0-aarch64.zip -d /mnt/mmc/ports/   # 按自己设备改路径
```

然后从设备前端的 **Ports** 分类里启动；也可以直接执行包内的 `Wiliwili.sh`。

- 首次启动会在 `wiliwili/conf/` 生成配置，登录态存本机
- 卸载：删掉 `/mnt/mmc/ports/wiliwili` 即可
- 包内 `SHA256SUMS` 可用于校验

## 构建

CI 在 **ubuntu-24.04-arm** 原生 arm64 上跑，容器里是 `arm64v8/ubuntu:18.04`（glibc 2.27，压低运行库要求，老一些的 Ports 设备也能跑），
**不需要 qemu 用户态，也不需要注册 binfmt**。

- 工作流：[`.github/workflows/build.yml`](.github/workflows/build.yml)
- 触发：推 `v*` tag，或在 Actions 页手动 `workflow_dispatch`
- 产物：`wiliwili-port-<版本>-aarch64.zip` + `SHA256SUMS`，直接发布到 Release

本地复现（需要 arm64 主机，或 x86 + binfmt）：

```sh
# 1. 依赖资产（libs.aarch64 + gl4es.aarch64）来自 release，按 deps.lock 校验
set -a; . ./deps.lock; set +a
curl -LO "https://github.com/<owner>/<repo>/releases/download/$DEPS_TAG/$DEPS_ASSET"

# 2. 上游源码 + 补丁
git clone --depth 1 --branch "$(cat VERSION)" \
  --recurse-submodules --shallow-submodules \
  https://github.com/xfangfang/wiliwili.git src
for p in patches/*.patch; do git -C src apply "$p"; done

# 3. 编译
docker build -f docker/Dockerfile -t wiliwili-bionic .
docker run --rm --platform linux/arm64 -v "$PWD:/work" -w /work \
  -e WORK=/work -e SRC=/work/src -e LIBS=/work/deps/libs.aarch64 \
  -e OUT=/work/out -e BUILD=/work/cache \
  wiliwili-bionic bash /work/docker/build.sh
```

编译参数（只在 Ports 平台）：`PLATFORM_DESKTOP + USE_SDL2 + USE_GLES2 + USE_SYSTEM_SDL2 + USE_SYSTEM_CURL + USE_LIBROMFS=OFF`。
SDL2 只用于编译期头文件与链接，运行期用设备自带的 `libSDL2-2.0.so.0`。

## 合并上游

**目标：永远不产生 merge 冲突。** 上游源码不进本仓库，所以"合并"只是让补丁在新版本上继续能打上。

```sh
scripts/merge-upstream.sh v1.7.0     # 逐条检查补丁能否干净 apply
echo "v1.7.0" > VERSION              # 改版本
# 在 MERGE_LOG.md 追加一条记录
git commit -am "merge upstream v1.7.0"
git tag v1.7.0 && git push origin main v1.7.0
```

推 tag 后 CI 自动出包；上机复测通过后，把结论补进那条合并记录。
补丁失效时脚本会指出是哪一条，手动 rebase 后更新 `patches/` 即可。

每周还有一个 [`upstream-check`](.github/workflows/upstream-check.yml) 任务盯上游 release，有新版本会自动开 issue。

## 目录结构

```
VERSION                 # 跟踪的上游 tag，构建时按它拉源码
deps.lock               # 运行时依赖资产（libs.aarch64 + gl4es.aarch64）的地址与 sha256
patches/                # 本地补丁，构建时 git apply 到上游源码
docker/                 # bionic 构建镜像与编译脚本
third_party/            # mpv 0.32 / curl 7.68 的头文件（只用于编译）
port/                   # Ports 打包内容：启动脚本、元数据、conf、licenses
scripts/                # 合并上游的辅助脚本
MERGE_LOG.md            # 每次合并上游的记录（必填）
```

## 已知限制

- `HighlightProgress` 偶发报错（message 为空）：更像上游接口返回 403/412，未处理
- 硬件解码在 H700 上不可用（已实测）：该机 muOS 内核 4.9.170 没有 V4L2 M2M 节点（`/dev/video*` 只有 CSI 的 subdev），
  也没有 DRM render node；H700 的 VPU 只通过 BSP 的 `/dev/cedar_dev` 暴露，FFmpeg/mpv 都不认这套接口。
  设置里打开「硬件解码」后 `hwdec-current` 仍是 `no`；系统自带的 mpv 0.35.1（原生支持 `v4l2m2m`）跑同一文件同样报
  `DR failed - disabling`。所以包里只提供软解，开关保留但不生效
- 封面修复依赖 B 站当前的 UA 策略，对方若再调整可能还需要跟进

## 致谢

感谢 [xfangfang](https://github.com/xfangfang) 和 wiliwili 的所有贡献者，以及
[borealis](https://github.com/xfangfang/borealis)、mpv、FFmpeg、SDL2、gl4es 等上游项目。
没有它们就没有这个包。