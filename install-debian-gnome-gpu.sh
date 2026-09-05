#!/data/data/com.termux/files/usr/bin/bash

set -Eeuo pipefail

readonly TOTAL_STEPS=8
CURRENT_STEP=0
GPU_ACCELERATION=0
INSTALL_LOG=""
DEBIAN_USER="root"
readonly DISTRO="debian-gnome"
readonly DEBIAN_IMAGE="debian:13"
readonly DISPLAY_NUM=":2"

# ============== HELPERS ==============
update_progress() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    local percent=$((CURRENT_STEP * 100 / TOTAL_STEPS))
    local filled=$((percent / 5))
    local empty=$((20 - filled))
    local bar="["
    local i

    for ((i=0; i<filled; i++)); do bar+="="; done
    for ((i=0; i<empty; i++)); do bar+="-"; done
    bar+="]"

    echo ""
    echo "------------------------------------------------------------"
    echo "  ${CURRENT_STEP}/${TOTAL_STEPS} - ${percent}%"
    echo "------------------------------------------------------------"
    echo ""
}

spinner() {
    local pid=$1
    local message=$2
    local spin='|/-\'
    local i=0

    while kill -0 "$pid" 2>/dev/null; do
        i=$(((i + 1) % 4))
        printf "\r  %s %s  " "$message" "${spin:$i:1}"
        sleep 0.1
    done

    local exit_code
    if wait "$pid"; then
        printf "\r  OK: %s                    \n" "$message"
        return 0
    else
        exit_code=$?
    fi

    printf "\r  ERROR: %s (failed)     \n" "$message" >&2
    if [ -s "$INSTALL_LOG" ]; then
        echo "  Last installer output:" >&2
        tail -n 20 "$INSTALL_LOG" >&2
    fi
    return "$exit_code"
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        printf "ERROR: Required command not found: %s\n" "$1" >&2
        exit 1
    fi
}

preflight() {
    if [ -z "${PREFIX:-}" ] || [ -z "${TMPDIR:-}" ]; then
        echo "ERROR: Run this installer from a Termux environment." >&2
        exit 1
    fi

    require_command pkg
    require_command getprop

    INSTALL_LOG="${TMPDIR}/debian-gnome-installer.log"
    : > "$INSTALL_LOG"
}

prompt_debian_user() {
    local requested_user

    while true; do
        read -r -p "Debian username [root]: " requested_user
        requested_user=${requested_user:-root}

        if [[ "$requested_user" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
            DEBIAN_USER="$requested_user"
            break
        fi

        echo "  Enter a lowercase Linux username using letters, numbers, underscores, or hyphens."
    done

    echo "  Debian session user: ${DEBIAN_USER}"
    echo ""
}

create_debian_user() {
    if [ "$DEBIAN_USER" = "root" ]; then
        return
    fi

    debian_apt_install "sudo" "sudo"

    echo "  Configuring Debian user: ${DEBIAN_USER}"
    debian_run "
        set -e
        if ! id -u '${DEBIAN_USER}' >/dev/null 2>&1; then
            useradd --create-home --user-group --shell /bin/bash '${DEBIAN_USER}'
        fi

        usermod --append --groups sudo '${DEBIAN_USER}'

        for group in audio video render plugdev; do
            if getent group \"\$group\" >/dev/null 2>&1; then
                usermod --append --groups \"\$group\" '${DEBIAN_USER}'
            fi
        done
    "

    if debian_run "passwd --status '${DEBIAN_USER}' | grep -Eq ' (L|NP) '"; then
        echo ""
        echo "Set a Debian password for ${DEBIAN_USER}. This password will be used by sudo."
        debian_run "passwd '${DEBIAN_USER}'"
        echo ""
    fi

    echo "  OK: Debian user and sudo access are ready"
}

install_pkg() {
    local pkg=$1
    local name=${2:-$pkg}
    (pkg install "$pkg" -y > "$INSTALL_LOG" 2>&1) &
    spinner $! "Installing ${name}..."
}

debian_run() {
    # --shared-tmp lets the Debian guest use Termux:X11's X socket.
    proot-distro login "$DISTRO" --shared-tmp -- /bin/bash -lc "$1"
}

debian_apt_install() {
    local packages="$1"
    local name="$2"
    (
        proot-distro login "$DISTRO" --shared-tmp -- /bin/bash -lc \
            "export DEBIAN_FRONTEND=noninteractive; apt-get install -y --no-install-recommends $packages" \
            > "$INSTALL_LOG" 2>&1
    ) &
    spinner $! "Installing ${name} in Debian..."
}

install_termux_command() {
    local command_name=$1
    local launcher_name=$2
    local command_path="${PREFIX}/bin/${command_name}"
    local marker="# Managed by the Debian GNOME installer"

    if [ -e "$command_path" ] && ! grep -Fqx "$marker" "$command_path" 2>/dev/null; then
        echo "  WARNING: ${command_path} already exists and was not replaced."
        return
    fi

    {
        echo '#!/data/data/com.termux/files/usr/bin/bash'
        echo "$marker"
        printf 'exec bash "$HOME/%s" "$@"\n' "$launcher_name"
    } > "$command_path"
    chmod +x "$command_path"

    echo "  OK: Installed command: ${command_name}"
}

install_termux_commands() {
    install_termux_command "debian" "start-debian-gnome.sh"
    install_termux_command "debian-shell" "debian-shell.sh"
    install_termux_command "debian-stop" "stop-debian-gnome.sh"
}

show_banner() {
    cat << 'BANNER'
    ----------------------------------------
    DEBIAN GNOME
    Debian + Termux:X11
    ----------------------------------------
BANNER
}

# ============== DEVICE DETECTION ==============
detect_device() {
    echo "[*] Detecting your device..."
    echo ""

    DEVICE_MODEL=$(getprop ro.product.model 2>/dev/null || echo "Unknown")
    DEVICE_BRAND=$(getprop ro.product.brand 2>/dev/null || echo "Unknown")
    ANDROID_VERSION=$(getprop ro.build.version.release 2>/dev/null || echo "Unknown")
    CPU_ABI=$(getprop ro.product.cpu.abi 2>/dev/null || echo "arm64-v8a")

    # GPU detection: do NOT infer Adreno merely from the phone brand.
    GPU_TEXT="$({
        getprop ro.hardware.egl 2>/dev/null
        getprop ro.hardware.vulkan 2>/dev/null
        getprop ro.board.platform 2>/dev/null
        getprop ro.soc.manufacturer 2>/dev/null
        getprop ro.soc.model 2>/dev/null
    } | tr '[:upper:]' '[:lower:]')"

    echo "  Device: ${DEVICE_BRAND} ${DEVICE_MODEL}"
    echo "  Android: ${ANDROID_VERSION}"
    echo "  CPU: ${CPU_ABI}"

    if [[ "$GPU_TEXT" == *"adreno"* ]] || [[ "$GPU_TEXT" == *"qualcomm"* ]] || [[ "$GPU_TEXT" == *"qcom"* ]]; then
        GPU_DRIVER="freedreno"
        echo "  GPU path: Qualcomm/Adreno - Freedreno/KGSL + Turnip"
    else
        GPU_DRIVER="swrast"
        echo "  GPU path: software Mesa fallback"
    fi

    echo ""
}

# ============== STEP 1 ==============
step_update() {
    update_progress
    echo "[Step ${CURRENT_STEP}/${TOTAL_STEPS}] Updating Termux..."
    echo ""

    (pkg update -y > "$INSTALL_LOG" 2>&1) &
    spinner $! "Updating Termux package lists..."
}

# ============== STEP 2 ==============
step_repository() {
    update_progress
    echo "[Step ${CURRENT_STEP}/${TOTAL_STEPS}] Enabling the Termux X11 repository..."
    echo ""

    install_pkg "x11-repo" "X11 Repository"
}

# ============== STEP 3 ==============
step_x11() {
    update_progress
    echo "[Step ${CURRENT_STEP}/${TOTAL_STEPS}] Installing Termux:X11 and proot-distro..."
    echo ""

    install_pkg "termux-x11-nightly" "Termux:X11 display server"
    install_pkg "proot-distro" "proot-distro"
}

# ============== STEP 4 ==============
step_desktop() {
    update_progress
    echo "[Step ${CURRENT_STEP}/${TOTAL_STEPS}] Installing Debian + GNOME..."
    echo ""

    if proot-distro list --quiet 2>/dev/null | grep -qx "$DISTRO"; then
        echo "  OK: Debian is already installed"
    else
        echo "  Installing Debian root filesystem..."
        if ! proot-distro install "$DEBIAN_IMAGE" --name "$DISTRO"; then
            echo "  ERROR: Debian installation failed."
            exit 1
        fi
        echo "  OK: Debian installed"
    fi

    echo "  Updating Debian package lists..."
    debian_run 'export DEBIAN_FRONTEND=noninteractive; apt-get update'

    # Keep the install deliberately smaller than Debian's full `gnome` task.
    # GNOME session provides the Xorg session entries; gnome-shell is the shell.
    debian_apt_install \
        "dbus-x11 dbus-user-session gnome-shell gnome-session gnome-session-xsession gnome-settings-daemon gnome-control-center gnome-terminal nautilus gnome-tweaks adwaita-icon-theme-full fonts-dejavu-core polkitd xdg-utils" \
        "GNOME desktop"

    # GNOME expects logind/systemd on a normal Debian machine. PRoot has neither.
    # Disable D-Bus activation for login1 when present so GNOME doesn't wait on it.
    debian_run '
        for f in \
          /usr/share/dbus-1/system-services/org.freedesktop.login1.service \
          /usr/share/dbus-1/system.d/org.freedesktop.login1.conf; do
            if [ -e "$f" ] && [ ! -e "$f.proot-disabled" ]; then
                mv "$f" "$f.proot-disabled"
            fi
        done
        mkdir -p /run/dbus
    '

    echo "  OK: Debian GNOME installed"
}

# ============== STEP 5 ==============
step_gpu() {
    update_progress
    echo "[Step ${CURRENT_STEP}/${TOTAL_STEPS}] Configuring graphics support..."
    echo ""

    if [ "$GPU_DRIVER" != "freedreno" ]; then
        echo "  WARNING: Qualcomm/Adreno was not detected. Debian will use its normal Mesa fallback."
        return
    fi

    if [ "$CPU_ABI" != "arm64-v8a" ]; then
        echo "  WARNING: The available KGSL/Turnip build requires ARM64. Debian will use its normal Mesa fallback."
        return
    fi

    # Debian needs its OWN glibc-compatible Mesa/Turnip build.  Termux's bionic
    # libraries cannot simply be LD_LIBRARY_PATH'd into a Debian proot.
    echo "  Installing Debian GPU prerequisites..."
    debian_run 'export DEBIAN_FRONTEND=noninteractive; apt-get install -y --no-install-recommends python3 ca-certificates curl tar xz-utils mesa-utils vulkan-tools libvulkan1'

    echo "  Fetching current KGSL-enabled Mesa + Turnip builds for Debian 13..."
    if debian_run 'set -e
TMP=/tmp/debian-gnome-mesa-kgsl
rm -rf "$TMP"
mkdir -p "$TMP"
cd "$TMP"

python3 - <<"PYGPU"
import hashlib
import json
import sys
import urllib.request

api="https://api.github.com/repos/lfdevs/mesa-for-android-container/releases?per_page=50"
req=urllib.request.Request(api, headers={"User-Agent":"termux-debian-gnome-installer"})
with urllib.request.urlopen(req, timeout=30) as r:
    releases=json.load(r)

standard=None
turnip=None
for rel in releases:
    if rel.get("draft") or rel.get("prerelease"):
        continue
    for asset in rel.get("assets", []):
        name=asset.get("name", "")
        url=asset.get("browser_download_url")
        if not url:
            continue
        if standard is None and name.startswith("mesa-for-android-container_") and name.endswith("_debian_trixie_arm64.tar.gz"):
            standard=(name,url,asset.get("digest"))
        if turnip is None and name.startswith("turnip_") and name.endswith("_debian_trixie_arm64.tar.gz"):
            turnip=(name,url,asset.get("digest"))
    if standard and turnip:
        break

if not standard or not turnip:
    print("Could not locate current Debian Trixie ARM64 Mesa/Turnip assets", file=sys.stderr)
    sys.exit(2)

for label,(name,url,digest) in (("standard",standard),("turnip",turnip)):
    print(f"{label}={name}")
    hasher=hashlib.sha256()
    with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent":"termux-debian-gnome-installer"}), timeout=120) as r, open(name,"wb") as f:
        while True:
            chunk=r.read(1024*1024)
            if not chunk: break
            f.write(chunk)
            hasher.update(chunk)
    if digest:
        algorithm, expected=digest.split(":", 1)
        if algorithm != "sha256" or hasher.hexdigest() != expected:
            print(f"Checksum verification failed for {name}", file=sys.stderr)
            sys.exit(3)
    open(label+".name","w").write(name)
PYGPU

STANDARD=$(cat standard.name)
TURNIP=$(cat turnip.name)

echo "Installing $STANDARD"
tar -xzf "$STANDARD" -C /
ldconfig

echo "Installing $TURNIP"
tar -xzf "$TURNIP" -C /
ldconfig

# Find the Freedreno/Turnip ICD installed by the release.  Do not assume one
# exact filename because it has changed between Mesa packaging revisions.
ICD=$(find /usr/share/vulkan/icd.d /etc/vulkan/icd.d -maxdepth 1 -type f \
    \( -iname "*freedreno*.json" -o -iname "*turnip*.json" \) 2>/dev/null | head -n1 || true)

mkdir -p /etc/profile.d
cat > /etc/profile.d/90-debian-gnome-adreno.sh <<EOF
export MESA_LOADER_DRIVER_OVERRIDE=kgsl
EOF
if [ -n "$ICD" ]; then
    printf "export VK_ICD_FILENAMES=%q\n" "$ICD" >> /etc/profile.d/90-debian-gnome-adreno.sh
fi
chmod 644 /etc/profile.d/90-debian-gnome-adreno.sh

rm -rf "$TMP"
' ; then
        GPU_ACCELERATION=1
        echo "  OK: Debian KGSL/Turnip stack installed"
    else
        echo "  WARNING: Could not install the current KGSL Mesa build automatically."
        echo "  WARNING: GNOME will still run, but may fall back to llvmpipe until GPU Mesa is installed."
    fi
}

# ============== STEP 6 ==============
step_audio() {
    update_progress
    echo "[Step ${CURRENT_STEP}/${TOTAL_STEPS}] Installing audio support..."
    echo ""

    install_pkg "pulseaudio" "PulseAudio"
    debian_apt_install "pulseaudio-utils" "PulseAudio client utilities"
}

# ============== STEP 7 ==============
step_apps() {
    update_progress
    echo "[Step ${CURRENT_STEP}/${TOTAL_STEPS}] Installing Debian desktop applications..."
    echo ""

    debian_apt_install \
        "firefox-esr git wget curl ca-certificates nano less file procps psmisc" \
        "Firefox and base utilities"
}

# ============== STEP 8 ==============
step_launchers() {
    update_progress
    echo "[Step ${CURRENT_STEP}/${TOTAL_STEPS}] Configuring the user and launcher commands..."
    echo ""

    create_debian_user

    cat > "$HOME/start-debian-gnome.sh" << 'LAUNCHEREOF'
#!/data/data/com.termux/files/usr/bin/bash

set -u

DISTRO="debian-gnome"
DISPLAY_NUM=":2"
DEBIAN_USER="__DEBIAN_USER__"
STATE_DIR="${TMPDIR}/debian-gnome"
X11_PID_FILE="${STATE_DIR}/termux-x11.pid"
X11_LOG="${STATE_DIR}/termux-x11.log"
SYSTEM_DBUS_PID_FILE="${STATE_DIR}/system-dbus.pid"
SYSTEM_DBUS_SOCKET="${TMPDIR}/debian-gnome-system-bus"
SYSTEM_DBUS_ADDRESS="unix:path=/tmp/debian-gnome-system-bus"
X11_DISPLAY_ID="${DISPLAY_NUM#:}"
X11_SOCKET="${TMPDIR}/.X11-unix/X${X11_DISPLAY_ID}"
X11_LOCK="${TMPDIR}/.X${X11_DISPLAY_ID}-lock"

echo ""
echo "Starting Debian GNOME"
echo ""

mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR"

# Clean up the previous desktop and X server. Termux:X11 must be launched from
# this Termux environment so PRoot can access its display through --shared-tmp.
echo "Cleaning up previous desktop session..."
pkill -f 'gnome-shell' 2>/dev/null || true
pkill -f 'gnome-session' 2>/dev/null || true
pkill termux-x11 2>/dev/null || true

for ((attempt=0; attempt<20; attempt++)); do
    if ! pgrep -x termux-x11 >/dev/null 2>&1; then
        break
    fi
    sleep 0.1
done
if pgrep -x termux-x11 >/dev/null 2>&1; then
    pkill -9 termux-x11 2>/dev/null || true
    sleep 0.5
fi

rm -f "$X11_PID_FILE"
rm -f "$X11_SOCKET" "$X11_LOCK"

# PulseAudio remains on the Termux side; Debian connects over localhost.
unset PULSE_SERVER
pulseaudio --kill 2>/dev/null || true
sleep 0.5

echo "Starting PulseAudio..."
pulseaudio --start --exit-idle-time=-1
sleep 1
pactl load-module module-native-protocol-tcp \
    listen=127.0.0.1 auth-ip-acl=127.0.0.1 auth-anonymous=1 >/dev/null 2>&1 || true

# Termux:X11 / PRoot share the Termux tmp directory.
export XDG_RUNTIME_DIR="${TMPDIR}"
export DISPLAY="${DISPLAY_NUM}"
termux-wake-lock 2>/dev/null || true

echo "Starting Termux:X11..."
: > "$X11_LOG"
termux-x11 "$DISPLAY_NUM" -ac >"$X11_LOG" 2>&1 &
x11_pid=$!
echo "$x11_pid" > "$X11_PID_FILE"

for ((attempt=0; attempt<30; attempt++)); do
    if [ -S "$X11_SOCKET" ]; then
        break
    fi
    if ! kill -0 "$x11_pid" 2>/dev/null; then
        break
    fi
    sleep 0.1
done

if [ ! -S "$X11_SOCKET" ]; then
    echo "ERROR: Termux:X11 did not create ${X11_SOCKET}." >&2
    if [ -s "$X11_LOG" ]; then
        tail -n 20 "$X11_LOG" >&2
    fi
    rm -f "$X11_PID_FILE"
    exit 1
fi
echo "Started Termux:X11 on ${DISPLAY_NUM}."

# Open/focus the Termux:X11 Android activity when `am` is available.
am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity >/dev/null 2>&1 || true
sleep 1

echo "Launching GNOME Shell (X11) in Debian..."
echo ""
echo "-----------------------------------------------"
echo "  Open Termux:X11 to view the desktop"
echo "  Guest: Debian"
echo "  Desktop: GNOME (X11)"
echo "  Audio: PulseAudio over localhost"
echo "-----------------------------------------------"
echo ""

# Clean up a bus left by an older launcher revision. The new compatibility bus
# runs inside the same regular-user PRoot session as GNOME.
if [ -r "$SYSTEM_DBUS_PID_FILE" ]; then
    read -r previous_system_dbus_pid < "$SYSTEM_DBUS_PID_FILE"
    if kill -0 "$previous_system_dbus_pid" 2>/dev/null \
        && [ -r "/proc/${previous_system_dbus_pid}/cmdline" ] \
        && tr '\0' ' ' < "/proc/${previous_system_dbus_pid}/cmdline" | grep -q 'dbus-daemon --system'; then
        kill "$previous_system_dbus_pid" 2>/dev/null || true
    fi
    rm -f "$SYSTEM_DBUS_PID_FILE"
fi
rm -f "$SYSTEM_DBUS_SOCKET"

exec proot-distro login "$DISTRO" --shared-tmp \
    --user "$DEBIAN_USER" \
    --env DISPLAY="$DISPLAY_NUM" \
    --env PULSE_SERVER="tcp:127.0.0.1" \
    --env DBUS_SYSTEM_BUS_ADDRESS="$SYSTEM_DBUS_ADDRESS" \
    --env XDG_SESSION_TYPE="x11" \
    --env XDG_CURRENT_DESKTOP="GNOME" \
    --env XDG_SESSION_DESKTOP="gnome" \
    -- /bin/bash -lc '
        export DISPLAY=:2
        export PULSE_SERVER=tcp:127.0.0.1
        export DBUS_SYSTEM_BUS_ADDRESS=unix:path=/tmp/debian-gnome-system-bus
        export XDG_SESSION_TYPE=x11
        export XDG_CURRENT_DESKTOP=GNOME
        export XDG_SESSION_DESKTOP=gnome
        export GDK_BACKEND=x11
        export QT_QPA_PLATFORM=xcb

        # GNOME expects a reachable system bus even though systemd-logind is
        # unavailable in PRoot. Start a permissive session-configured bus at
        # the system-bus address. Keeping it in this same PRoot session avoids
        # Unix-credential translation between separate PRoot supervisors.
        system_bus_socket=/tmp/debian-gnome-system-bus
        system_bus_address=unix:path="$system_bus_socket"
        system_bus_pid_file=/tmp/debian-gnome-system-bus.pid
        system_bus_log=/tmp/debian-gnome-system-bus.log
        rm -f "$system_bus_socket" "$system_bus_pid_file" "$system_bus_log"

        echo "Starting Debian D-Bus compatibility bus..."
        if ! dbus-daemon --session --fork --nopidfile --nosyslog \
            --address="$system_bus_address" --print-address=1 --print-pid=3 \
            3>"$system_bus_pid_file" >"$system_bus_log" 2>&1; then
            echo "ERROR: Could not launch the Debian D-Bus compatibility bus." >&2
            cat "$system_bus_log" >&2 2>/dev/null || true
            exit 1
        fi
        read -r system_bus_pid < "$system_bus_pid_file"
        cleanup_system_bus() {
            kill "$system_bus_pid" 2>/dev/null || true
            rm -f "$system_bus_socket" "$system_bus_pid_file"
        }
        trap cleanup_system_bus EXIT INT TERM

        if ! dbus-send --bus="$system_bus_address" \
            --type=method_call --print-reply --reply-timeout=3000 \
            --dest=org.freedesktop.DBus / org.freedesktop.DBus.ListNames \
            >/dev/null 2>"$system_bus_log.probe"; then
            echo "ERROR: Debian D-Bus compatibility bus did not respond." >&2
            cat "$system_bus_log" "$system_bus_log.probe" >&2 2>/dev/null || true
            exit 1
        fi
        echo "Debian D-Bus compatibility bus is ready."

        # Load Debian-side Adreno/Turnip settings when the KGSL Mesa package was installed.
        [ -r /etc/profile.d/90-debian-gnome-adreno.sh ] && . /etc/profile.d/90-debian-gnome-adreno.sh

        # Show the renderer before starting GNOME. This makes acceleration status obvious.
        echo ""
        echo "GPU probe inside Debian:"
        if command -v vulkaninfo >/dev/null 2>&1; then
            vulkaninfo --summary 2>/dev/null | grep -E -m3 "deviceName|driverName|driverInfo" || true
        fi
        if command -v glxinfo >/dev/null 2>&1; then
            glxinfo -B 2>/dev/null | grep -E "OpenGL vendor|OpenGL renderer|OpenGL version" || true
        fi
        echo ""

        # Runtime dir normally comes from systemd-logind, which PRoot does not run.
        export XDG_RUNTIME_DIR="/tmp/runtime-${USER:-root}"
        mkdir -p "$XDG_RUNTIME_DIR"
        chmod 700 "$XDG_RUNTIME_DIR"

        # GNOME 48 normally delegates session startup to systemd-logind, which
        # is unavailable in PRoot. Start Shell directly in a private session bus.
        dbus-run-session -- bash -lc "
            export DISPLAY=:2
            export PULSE_SERVER=tcp:127.0.0.1
            export DBUS_SYSTEM_BUS_ADDRESS=unix:path=/tmp/debian-gnome-system-bus
            export XDG_RUNTIME_DIR=/tmp/runtime-${USER:-root}
            export XDG_SESSION_TYPE=x11
            export XDG_CURRENT_DESKTOP=GNOME
            export XDG_SESSION_DESKTOP=gnome
            export GDK_BACKEND=x11
            [ -r /etc/profile.d/90-debian-gnome-adreno.sh ] && . /etc/profile.d/90-debian-gnome-adreno.sh
            exec gnome-shell --x11
        "
        gnome_status=$?
        exit "$gnome_status"
    '
LAUNCHEREOF
    sed -i "s/__DEBIAN_USER__/${DEBIAN_USER}/g" "$HOME/start-debian-gnome.sh"
    chmod +x "$HOME/start-debian-gnome.sh"

    cat > "$HOME/debian-shell.sh" << 'DEBEOF'
#!/data/data/com.termux/files/usr/bin/bash
DEBIAN_USER="__DEBIAN_USER__"
exec proot-distro login debian-gnome --shared-tmp --user "$DEBIAN_USER"
DEBEOF
    sed -i "s/__DEBIAN_USER__/${DEBIAN_USER}/g" "$HOME/debian-shell.sh"
    chmod +x "$HOME/debian-shell.sh"

    cat > "$HOME/stop-debian-gnome.sh" << 'STOPEOF'
#!/data/data/com.termux/files/usr/bin/bash

set -u

STATE_DIR="${TMPDIR}/debian-gnome"
X11_PID_FILE="${STATE_DIR}/termux-x11.pid"
SYSTEM_DBUS_PID_FILE="${STATE_DIR}/system-dbus.pid"
SYSTEM_DBUS_SOCKET="${TMPDIR}/debian-gnome-system-bus"

echo "Stopping Debian GNOME."
pkill -f 'gnome-shell' 2>/dev/null || true
pkill -f 'gnome-session' 2>/dev/null || true
pkill termux-x11 2>/dev/null || true
rm -f "$X11_PID_FILE"
if [ -r "$SYSTEM_DBUS_PID_FILE" ]; then
    read -r system_dbus_pid < "$SYSTEM_DBUS_PID_FILE"
    if kill -0 "$system_dbus_pid" 2>/dev/null \
        && [ -r "/proc/${system_dbus_pid}/cmdline" ] \
        && tr '\0' ' ' < "/proc/${system_dbus_pid}/cmdline" | grep -q 'dbus-daemon --system'; then
        kill "$system_dbus_pid" 2>/dev/null || true
    fi
    rm -f "$SYSTEM_DBUS_PID_FILE"
fi
rm -f "$SYSTEM_DBUS_SOCKET"
pulseaudio --kill 2>/dev/null || true
termux-wake-unlock 2>/dev/null || true
echo "Desktop stopped."
STOPEOF
    chmod +x "$HOME/stop-debian-gnome.sh"

    echo "  OK: Created ~/start-debian-gnome.sh"
    echo "  OK: Created ~/stop-debian-gnome.sh"
    echo "  OK: Created ~/debian-shell.sh"

    install_termux_commands
}

show_completion() {
    echo ""
    cat << 'COMPLETE'
    ---------------------------------------------------------------
    INSTALLATION COMPLETE
    Debian + GNOME + Termux:X11
    ---------------------------------------------------------------
COMPLETE

    echo "Start GNOME:"
    echo "   debian"
    echo ""
    echo "Enter Debian shell:"
    echo "   debian-shell"
    echo ""
    echo "Stop desktop:"
    echo "   debian-stop"
    echo ""
    echo "NOTE: The separate Termux:X11 Android app must also be installed."
    echo "NOTE: GNOME in PRoot is less lightweight than XFCE; first startup can take a while."
    echo "Debian session user: ${DEBIAN_USER}"
    if [ "$GPU_ACCELERATION" -eq 1 ]; then
        echo "GPU: Debian is configured for Freedreno/KGSL OpenGL and Turnip Vulkan."
        echo "Verify: Start GNOME and check the GPU probe output; the renderer should not say llvmpipe."
    fi
}

main() {
    preflight
    show_banner
    echo "This installs a Debian GNOME desktop inside PRoot and uses"
    echo "Termux:X11 + PulseAudio on the Android/Termux side."
    echo ""
    echo "Press Enter to start, or Ctrl+C to cancel..."
    read -r
    echo ""

    prompt_debian_user

    detect_device
    step_update
    step_repository
    step_x11
    step_desktop
    step_gpu
    step_audio
    step_apps
    step_launchers
    show_completion
}

main "$@"
