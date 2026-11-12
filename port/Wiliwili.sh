#!/bin/bash
# PORTMASTER: wiliwili-portmaster-a18project-v26.10.1.zip, Wiliwili.sh
#
# Wiliwili PortMaster Launch Script
# Reference: https://portmaster.games/packaging.html#the-launchscript-sh
#
# ============================================================
# muOS 修正版 v4 (音频修复 + 防自动省电)  2026-10-20
#
# 1) 音频修复：
#    ALSA 配置里 pcm.!default 指向 "type pipewire"，
#    动态定位 libasound_module_pcm_pipewire.so 并设置 ALSA_PLUGIN_DIR，
#    解决 mpv 打不开音频设备导致的「有画面无声音」问题。
#
# 2) 防自动省电 (muOS Ports 通用防闲置省电方案)：
#    在 /run/muos/global/settings/power/ 中临时延长 idle_display 和 idle_sleep，
#    避免长时间播放视频时因无手柄按键操作而触发自动息屏/休眠；
#    退出时通过 trap 自动恢复原始设置。
#
# 可回滚：删掉 /root/.asoundrc 即还原；本脚本不改 /etc/asound.conf
# ============================================================

XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}

if [ -d "/opt/system/Tools/PortMaster/" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
  controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
  controlfolder="$XDG_DATA_HOME/PortMaster"
elif [ -d "/mnt/sdcard/Roms/ports/PortMaster" ]; then
  controlfolder="/mnt/sdcard/Roms/ports/PortMaster"
elif [ -d "/mnt/sdcard/PortMaster" ]; then
  controlfolder="/mnt/sdcard/PortMaster"
elif [ -d "/mnt/mmc/MUOS/PortMaster" ]; then
  controlfolder="/mnt/mmc/MUOS/PortMaster"
else
  controlfolder="/roms/ports/PortMaster"
fi

source $controlfolder/control.txt 2>/dev/null || true
[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"

get_controls

DEVICE_ARCH="${DEVICE_ARCH:-aarch64}"

if [ -d "$controlfolder/../ports/wiliwili" ]; then
  GAMEDIR="$controlfolder/../ports/wiliwili"
elif [ -n "$directory" ] && [ -d "/$directory/ports/wiliwili" ]; then
  GAMEDIR="/$directory/ports/wiliwili"
else
  GAMEDIR="$(cd "$(dirname "$0")" && pwd)/wiliwili"
fi

CONFDIR="$GAMEDIR/conf"
mkdir -p "$CONFDIR/wiliwili"
cd "$GAMEDIR"

> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1

echo "=== Wiliwili v3 Launch ==="
echo "GAMEDIR: $GAMEDIR"
echo "HOME: $HOME  USER: $(id -un)  UID: $(id -u)"
echo "Date: $(date)"
echo ""

PLUGDIR="/usr/lib/aarch64-linux-gnu/alsa-lib"
PLUGSO="libasound_module_pcm_pipewire.so"

echo "=== 音频诊断 v3 ==="
echo "--- os-release ---"
cat /etc/os-release 2>&1 | head -6

echo "--- ALSA 环境变量 ---"
echo "ALSA_PLUGIN_DIR=${ALSA_PLUGIN_DIR:-(未设置)}"
echo "ALSA_CONFIG_PATH=${ALSA_CONFIG_PATH:-(未设置)}"
echo "ALSA_CONFIG_DIR=${ALSA_CONFIG_DIR:-(未设置)}"

echo "--- 默认插件目录 $PLUGDIR ---"
ls -la "$PLUGDIR" 2>&1 | head -30

echo "--- 其他可能的 alsa-lib 目录 ---"
ls -ld /usr/lib/alsa-lib /usr/lib/aarch64-linux-gnu/alsa-lib 2>&1

echo "--- 全盘搜索 $PLUGSO ---"
find /usr /opt /lib /usr/local -name "$PLUGSO" 2>/dev/null | head -10

echo "--- 搜索 pipewire-alsa 相关文件 ---"
find /usr /opt -name '*asound_module*pipewire*' -o -name '99-pipewire*' 2>/dev/null | head -10

echo "--- PipeWire 相关进程 ---"
ps aux 2>/dev/null | grep -Ei "pipewire|wireplumber|pulse" | grep -v grep

echo "--- pulse socket 是否存在 ---"
ls -la /run/pulse /run/pipewire-pulse /var/run/pulse ~/.config/pulse 2>&1 | head -12

echo "--- 谁占用了声卡 ---"
fuser -v /dev/snd/* 2>&1 | head -12

echo "--- muOS 音频脚本（若存在）---"
ls -la /opt/muos/script/system/pipewire.sh 2>&1
head -40 /opt/muos/script/system/pipewire.sh 2>/dev/null

echo "--- 当前 asound 配置 ---"
echo "[ /etc/asound.conf ]"; cat /etc/asound.conf 2>&1
echo "[ ~/.asoundrc ]"; cat "$HOME/.asoundrc" 2>&1
echo "=== 音频诊断 v3 结束 ==="
echo ""

# ============================================================
# 修正策略
# ============================================================
FOUND_PLUGIN=$(find /usr /opt /lib /usr/local -name "$PLUGSO" 2>/dev/null | head -1)

if [ -n "$FOUND_PLUGIN" ]; then
  echo ">>> 找到 pipewire ALSA 插件: $FOUND_PLUGIN"
  SRCDIR=$(dirname "$FOUND_PLUGIN")

  # 方案 A（首选，零侵入）：直接指定 ALSA 插件搜索目录
  # 系统升级/重刷后依然有效，不依赖 rootfs 里被复制过去的文件
  export ALSA_PLUGIN_DIR="$SRCDIR"
  echo "    已设置 ALSA_PLUGIN_DIR=$SRCDIR"

  # 方案 B（冗余兜底）：把插件补到内置 libasound 期望的目录
  if [ "$SRCDIR" != "$PLUGDIR" ] && [ ! -f "$PLUGDIR/$PLUGSO" ]; then
    mount -o remount,rw / 2>/dev/null || true
    if mkdir -p "$PLUGDIR" 2>/dev/null && cp -n "$FOUND_PLUGIN" "$PLUGDIR/" 2>/dev/null; then
      echo "    已复制到 $PLUGDIR/"
    else
      echo "    复制失败（已有 ALSA_PLUGIN_DIR 兜底，不影响）"
    fi
  fi

  cat > "$HOME/.asoundrc" <<'EOF'
pcm.!default {
    type plug
    slave.pcm { type pipewire }
    hint {
        show on
        description "Default Audio Device (PipeWire)"
    }
}
ctl.!default { type pipewire }
EOF
  echo "    已写入 $HOME/.asoundrc (type pipewire)"
else
  echo ">>> 未找到 pipewire ALSA 插件，改用硬件直连 hw:0,0 (audiocodec)"
  cat > "$HOME/.asoundrc" <<'EOF'
pcm.!default {
    type plug
    slave.pcm "hw:0,0"
}
ctl.!default {
    type hw
    card 0
}
EOF
  echo "    已写入 $HOME/.asoundrc (hw:0,0)"
fi

# mpv 音频输出（mpv 0.32 无 pipewire ao，故用 pulse,alsa）
MPVCONF="$CONFDIR/mpv"
mkdir -p "$MPVCONF"
cat > "$MPVCONF/mpv.conf" <<'MPV_EOF'
# muOS 音频：先试 PulseAudio 兼容层，再直连 ALSA
ao=pulse,alsa
audio-channels=stereo
MPV_EOF
echo "已写入 mpv 配置: $MPVCONF/mpv.conf"
echo ""

# ============================================================
# 原始启动逻辑
# ============================================================
export XDG_DATA_HOME="$CONFDIR"
export XDG_CONFIG_HOME="$CONFDIR"
export XDG_CACHE_HOME="$CONFDIR/cache"

bind_directories "$HOME/.config/wiliwili" "$CONFDIR/wiliwili"

export LD_LIBRARY_PATH="$GAMEDIR/libs.${DEVICE_ARCH}:$LD_LIBRARY_PATH"
export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"

if [ -f "$GAMEDIR/ca-certificates.crt" ]; then
  export SSL_CERT_FILE="$GAMEDIR/ca-certificates.crt"
  export CURL_CA_BUNDLE="$GAMEDIR/ca-certificates.crt"
fi

if [ -f "$GAMEDIR/libs.${DEVICE_ARCH}/libsdl_shim.so" ]; then
  export LD_PRELOAD="$GAMEDIR/libs.${DEVICE_ARCH}/libsdl_shim.so:$LD_PRELOAD"
fi

if [ -z "$SDL_VIDEODRIVER" ]; then
  if [ -e "/dev/dri/card0" ]; then
    export SDL_VIDEODRIVER=kmsdrm
  elif [ -e "/dev/mali0" ]; then
    export SDL_VIDEODRIVER=mali
  fi
fi

if [ "$SDL_VIDEODRIVER" != "wayland" ] && [ "$SDL_VIDEODRIVER" != "x11" ]; then
  if [ -f "${controlfolder}/libgl_${CFW_NAME}.txt" ]; then
    source "${controlfolder}/libgl_${CFW_NAME}.txt"
  elif [ -f "${controlfolder}/libgl_default.txt" ]; then
    source "${controlfolder}/libgl_default.txt"
  else
    export LD_LIBRARY_PATH="$GAMEDIR/gl4es.${DEVICE_ARCH}:$LD_LIBRARY_PATH"
  fi
fi

[ -z "$SDL_AUDIODRIVER" ] && export SDL_AUDIODRIVER=alsa

# muOS 启动器（SETUP_SDL_ENVIRONMENT）会额外导出 SDL_BLITTER_DISABLED=1。
# 这个变量会让 SDL 走直写 fb 的呈现路径，播放视频时偶发只把清屏帧送上屏
# （表现就是屏幕白屏闪烁）。必须 unset 掉；设成 0 也仍有残留闪烁，
# 只有完全移除该变量才稳定。
unset SDL_BLITTER_DISABLED

echo "SDL_AUDIODRIVER=$SDL_AUDIODRIVER"
echo "ALSA_PLUGIN_DIR=${ALSA_PLUGIN_DIR:-(默认)}"
echo ""

# ============================================================
# muOS Ports 通用防闲置省电方案
# ============================================================
POWER_DIR="/run/muos/global/settings/power"
DISPLAY_FILE="$POWER_DIR/idle_display"
SLEEP_FILE="$POWER_DIR/idle_sleep"

TIMEOUT=86400

OLD_DISPLAY=""
OLD_SLEEP=""
HAS_DISPLAY=0
HAS_SLEEP=0

if [ -r "$DISPLAY_FILE" ] && [ -w "$DISPLAY_FILE" ]; then
    OLD_DISPLAY=$(cat "$DISPLAY_FILE")
    HAS_DISPLAY=1
    echo "防省电: 保存原始 idle_display: $OLD_DISPLAY"
fi

if [ -r "$SLEEP_FILE" ] && [ -w "$SLEEP_FILE" ]; then
    OLD_SLEEP=$(cat "$SLEEP_FILE")
    HAS_SLEEP=1
    echo "防省电: 保存原始 idle_sleep: $OLD_SLEEP"
fi

restore_power() {
    trap - EXIT HUP INT TERM

    if [ "$HAS_DISPLAY" -eq 1 ]; then
        printf '%s\n' "$OLD_DISPLAY" > "$DISPLAY_FILE"
        echo "防省电: 已恢复 idle_display: $OLD_DISPLAY"
    fi

    if [ "$HAS_SLEEP" -eq 1 ]; then
        printf '%s\n' "$OLD_SLEEP" > "$SLEEP_FILE"
        echo "防省电: 已恢复 idle_sleep: $OLD_SLEEP"
    fi
}

trap 'restore_power' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if [ "$HAS_DISPLAY" -eq 1 ]; then
    printf '%s\n' "$TIMEOUT" > "$DISPLAY_FILE"
    echo "防省电: 临时延长 idle_display 至 $TIMEOUT 秒 (24小时)"
fi

if [ "$HAS_SLEEP" -eq 1 ]; then
    printf '%s\n' "$TIMEOUT" > "$SLEEP_FILE"
    echo "防省电: 临时延长 idle_sleep 至 $TIMEOUT 秒 (24小时)"
fi

$GPTOKEYB "wiliwili.${DEVICE_ARCH}" &
pm_platform_helper "$GAMEDIR/wiliwili.${DEVICE_ARCH}"

echo "Starting wiliwili.${DEVICE_ARCH}..."
./wiliwili.${DEVICE_ARCH}
EXIT_CODE=$?
echo "wiliwili exited with code: $EXIT_CODE"

pm_finish
