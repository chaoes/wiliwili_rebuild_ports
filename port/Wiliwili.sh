#!/bin/bash
# PORTMASTER: wiliwili-portmaster-a18project-v26.10.1.zip, Wiliwili.sh
#
# Wiliwili PortMaster Launch Script
# Reference: https://portmaster.games/packaging.html#the-launchscript-sh
#
# ============================================================
# 修正版 v5 (音频修复 + 防自动省电)  2026-11-12
#  v5: 音频探测加缓存、只在需要时写 ~/.asoundrc 并备份、去掉 remount/写系统目录；
#      PortMaster 辅助函数全部加存在性判断，脱离 PortMaster 前端也能启动。
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
# 可回滚：删掉 $HOME/.asoundrc（或还原同目录下的 .bak-wiliwili）即还原；本脚本不改 /etc/asound.conf，
#         也不改系统目录（不做 remount、不往 /usr/lib 里写文件）
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

command -v get_controls >/dev/null 2>&1 && get_controls

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

PLUGSO="libasound_module_pcm_pipewire.so"
PLUG_CACHE="$GAMEDIR/.alsa_plugin_dir"

echo "=== 音频准备 ==="
echo "ALSA_PLUGIN_DIR=${ALSA_PLUGIN_DIR:-(未设置)}"

# 找 pipewire ALSA 插件：先查常见目录（快），都没命中才做一次浅层 find。
# 结果缓存到包目录，下次启动直接命中，避免每次启动都全盘搜索（旧版要 40-60 秒）。
find_plugin_dir() {
  d=$(cat "$PLUG_CACHE" 2>/dev/null)
  if [ -n "$d" ] && [ -f "$d/$PLUGSO" ]; then echo "$d"; return 0; fi

  for d in "${ALSA_PLUGIN_DIR:-}" \
           /usr/lib/alsa-lib /usr/lib/aarch64-linux-gnu/alsa-lib /usr/lib64/alsa-lib \
           /usr/local/lib/alsa-lib /opt/muos/lib/alsa-lib /lib/alsa-lib; do
    [ -n "$d" ] && [ -f "$d/$PLUGSO" ] && { echo "$d"; return 0; }
  done

  for d in /usr/lib/*/alsa-lib /usr/lib/*/*/alsa-lib; do
    [ -f "$d/$PLUGSO" ] && { echo "$d"; return 0; }
  done

  hit=$(find /usr/lib /usr/local/lib /lib /opt -maxdepth 5 -name "$PLUGSO" 2>/dev/null | head -1)
  [ -n "$hit" ] && dirname "$hit"
}

FOUND_PLUGIN=$(find_plugin_dir)

if [ -n "$FOUND_PLUGIN" ]; then
  SRCDIR="$FOUND_PLUGIN"
  echo ">>> pipewire ALSA 插件: $FOUND_PLUGIN"

  # 零侵入方案：只指定插件搜索目录，不改系统文件、不做 remount
  export ALSA_PLUGIN_DIR="$SRCDIR"
  echo "    ALSA_PLUGIN_DIR=$SRCDIR"
  [ "$(cat "$PLUG_CACHE" 2>/dev/null)" = "$SRCDIR" ] || printf '%s\n' "$SRCDIR" > "$PLUG_CACHE" 2>/dev/null

  ASOUNDRC="$HOME/.asoundrc"
  if ! grep -qsE 'type[[:space:]]+pipewire' "$ASOUNDRC" 2>/dev/null; then
    [ -f "$ASOUNDRC" ] && cp -n "$ASOUNDRC" "$ASOUNDRC.bak-wiliwili" 2>/dev/null
    cat > "$ASOUNDRC" <<'EOF'
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
    echo "    $HOME/.asoundrc 已指向 pipewire，跳过"
  fi
else
  echo ">>> 未找到 pipewire ALSA 插件，沿用系统默认音频输出"
fi

echo ""

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

if command -v bind_directories >/dev/null 2>&1; then
  bind_directories "$HOME/.config/wiliwili" "$CONFDIR/wiliwili"
fi

export LD_LIBRARY_PATH="$GAMEDIR/libs.${DEVICE_ARCH}:$LD_LIBRARY_PATH"
[ -n "${sdl_controllerconfig:-}" ] && export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"

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

[ -n "${GPTOKEYB:-}" ] && $GPTOKEYB "wiliwili.${DEVICE_ARCH}" &
command -v pm_platform_helper >/dev/null 2>&1 && pm_platform_helper "$GAMEDIR/wiliwili.${DEVICE_ARCH}"

echo "Starting wiliwili.${DEVICE_ARCH}..."
./wiliwili.${DEVICE_ARCH}
EXIT_CODE=$?
echo "wiliwili exited with code: $EXIT_CODE"

command -v pm_finish >/dev/null 2>&1 && pm_finish
