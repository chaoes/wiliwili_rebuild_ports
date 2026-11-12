#!/bin/bash
# 在 arm64 bionic 容器内编译 wiliwili（aarch64 Ports 平台通用）
#
# 链接策略：
#   C/C++ 运行库来自 bionic（glibc 2.27，压低目标设备要求）
#   libmpv / libcurl / libssl / libwebp 使用 deps 资产里已验证的 aarch64 预编译库
#   SDL2 现场编译，但只用于头文件与链接，运行期用设备自带的 libSDL2-2.0.so.0
set -euo pipefail

SRC=${SRC:-/work/src}
WORK=${WORK:-/work}
LIBS=${LIBS:-/work/deps/libs.aarch64}
MPV_HEADERS=${MPV_HEADERS:-/work/third_party/mpv/include/mpv}
CURL_HEADERS=${CURL_HEADERS:-/work/third_party/curl/include/curl}
OUT=${OUT:-/work/out}
BUILD=${BUILD:-/work/cache}
DEPS=$BUILD/deps

mkdir -p "$DEPS/include" "$DEPS/lib" "$DEPS/lib/pkgconfig" "$DEPS/bin" "$OUT" "$BUILD"

log() { echo "=== $* ==="; }

log "1/6 准备 mpv 头文件（0.32.0，与运行时 libmpv.so.1 对应）"
mkdir -p "$DEPS/include/mpv"
cp "$MPV_HEADERS"/*.h "$DEPS/include/mpv/"

log "2/6 准备 libmpv（deps 资产内的 aarch64 预编译库）"
cp -f "$LIBS/libmpv.so.1" "$DEPS/lib/libmpv.so.1"
chmod +x "$DEPS/lib/libmpv.so.1"
ln -sf libmpv.so.1 "$DEPS/lib/libmpv.so"
printf '%s\n' \
  "prefix=$DEPS" \
  'libdir=${prefix}/lib' \
  'includedir=${prefix}/include' \
  '' \
  'Name: mpv' \
  'Description: mpv media player client library' \
  'Version: 0.32.0' \
  'Libs: -L${libdir} -lmpv' \
  'Cflags: -I${includedir}' > "$DEPS/lib/pkgconfig/mpv.pc"

log "3/6 准备 libcurl 7.68.0（头文件 + 预编译库）"
mkdir -p "$DEPS/include/curl"
cp "$CURL_HEADERS"/*.h "$DEPS/include/curl/"
cp -f "$LIBS/libcurl.so.4" "$DEPS/lib/libcurl.so.4"
chmod +x "$DEPS/lib/libcurl.so.4"
ln -sf libcurl.so.4 "$DEPS/lib/libcurl.so"
# 注意：不要提供 libcurl.pc。CMake 的 FindCURL 一旦通过 pkg-config 命中 curl，
# 就会跳过 curl-config，导致 HTTP/HTTPS 组件检测为空而报 "Curl not found"。
cat > "$DEPS/bin/curl-config" <<CURL_CONFIG
#!/bin/sh
prefix=$DEPS
case "\$1" in
  --version)     echo 7.68.0 ;;
  --protocols)   printf 'HTTP\nHTTPS\nFTP\nFILE\n' ;;
  --feature|--features) printf 'SSL\nIPv6\nAsynchDNS\nlibz\nHTTP2\nTLS-SRP\n' ;;
  --libs)        echo "-L\$prefix/lib -lcurl" ;;
  --static-libs) echo "-L\$prefix/lib -lcurl" ;;
  --cflags)      echo "-I\$prefix/include" ;;
  *)             echo 7.68.0 ;;
esac
CURL_CONFIG
chmod +x "$DEPS/bin/curl-config"
export PATH="$DEPS/bin:$PATH"
export PKG_CONFIG_PATH="$DEPS/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"

log "4/6 编译 SDL 2.28.5（仅编译期使用，不随包发布）"
if [ ! -f "$DEPS/lib/libSDL2-2.0.so.0" ]; then
  cmake -S "$SRC/library/borealis/library/lib/extern/SDL" -B "$BUILD/sdl" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$DEPS" \
    -DCMAKE_C_COMPILER=gcc-8 -DCMAKE_CXX_COMPILER=g++-8 \
    -DSDL_SHARED=ON -DSDL_STATIC=OFF -DSDL_TEST=OFF \
    -DSDL_X11=OFF -DSDL_WAYLAND=OFF -DSDL_KMSDRM=ON \
    -DSDL_IBUS=OFF
  cmake --build "$BUILD/sdl" -j"$(nproc)"
  cmake --install "$BUILD/sdl"
fi

# 容器内以 root 读取挂载目录时 git 会因 dubious ownership 拒绝执行，
# 导致 BUILD_TAG_VERSION 为空、程序里显示不了版本号。
git config --global --add safe.directory '*' 2>/dev/null || true

log "5/6 配置 wiliwili（PLATFORM_DESKTOP + SDL2 + GLES2）"
cmake -S "$SRC" -B "$BUILD/wiliwili" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER=gcc-8 -DCMAKE_CXX_COMPILER=g++-8 \
  -DCMAKE_PREFIX_PATH="$DEPS" \
  -DHOMEBREW_MPV="$DEPS" \
  -DCURL_INCLUDE_DIR="$DEPS/include" \
  -DCURL_LIBRARY="$DEPS/lib/libcurl.so.4" \
  -DPLATFORM_DESKTOP=ON \
  -DMPV_NO_FB=ON \
  -DUSE_SDL2=ON \
  -DUSE_GLES2=ON \
  -DUSE_SYSTEM_SDL2=ON \
  -DUSE_SYSTEM_CURL=ON \
  -DUSE_LIBROMFS=OFF \
  -DBRLS_UNITY_BUILD=ON \
  -DCMAKE_CXX_STANDARD_LIBRARIES='-lstdc++fs' \
  -DCMAKE_EXE_LINKER_FLAGS='-Wl,--allow-shlib-undefined' \
  -DCMAKE_INSTALL_RPATH='$ORIGIN/libs.aarch64:$ORIGIN/libs' \
  -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON

log "6/6 编译 wiliwili"
cmake --build "$BUILD/wiliwili" -j"$(nproc)"

cp -f "$BUILD/wiliwili/wiliwili" "$OUT/wiliwili.aarch64"
strip "$OUT/wiliwili.aarch64" || true
chmod +x "$OUT/wiliwili.aarch64"
cp -f /etc/ssl/certs/ca-certificates.crt "$OUT/ca-certificates.crt"

echo "=== 产物 ==="
ls -lh "$OUT/wiliwili.aarch64"
readelf -d "$OUT/wiliwili.aarch64" | grep -E 'NEEDED|RUNPATH|RPATH' || true