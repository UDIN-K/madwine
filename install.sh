#!/usr/bin/env bash
# madwine - Run Madium on Linux via Wine/Proton
# https://github.com/UDIN-K/madwine
set -euo pipefail

# ── Config ──────────────────────────────────────────────────────────
MADWINE_DIR="${MADWINE_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/madwine}"
WINEPREFIX="${WINEPREFIX:-$MADWINE_DIR/prefix}"
WINE="${WINE:-wine}"

DOTNET_URL="https://builds.dotnet.microsoft.com/dotnet/WindowsDesktop/8.0.34/windowsdesktop-runtime-8.0.34-win-x64.exe"
WEBVIEW2_URL="https://go.microsoft.com/fwlink/p/?LinkId=2124701"  # offline standalone x64
WEBVIEW2_GUID="{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}"
MADIUM_CDN="https://165.245.199.89"
MADIUM_MANIFEST="$MADIUM_CDN/manifest.json"

# ── Helpers ─────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

info()  { printf "${CYAN}[*]${NC} %s\n" "$*"; }
ok()    { printf "${GREEN}[✓]${NC} %s\n" "$*"; }
warn()  { printf "${YELLOW}[!]${NC} %s\n" "$*"; }
die()   { printf "${RED}[✗]${NC} %s\n" "$*" >&2; exit 1; }

fetch() {
    local url="$1" dest="$2"
    if command -v curl &>/dev/null; then
        curl -fL# -A "Mozilla/5.0" -o "$dest" "$url"
    elif command -v wget &>/dev/null; then
        wget --show-progress -O "$dest" "$url"
    else
        die "curl or wget required"
    fi
}

get() {
    if command -v curl &>/dev/null; then
        curl -fsSL "$1"
    else
        wget -qO- "$1"
    fi
}

# ── Checks ──────────────────────────────────────────────────────────
check_deps() {
    info "Checking system dependencies..."
    local missing=()
    command -v wine &>/dev/null || missing+=(wine)
    command -v wineserver &>/dev/null || missing+=(wineserver)
    { command -v curl &>/dev/null || command -v wget &>/dev/null; } || missing+=(curl)

    if [ ${#missing[@]} -gt 0 ]; then
        die "Missing: ${missing[*]}. Install them first."
    fi
    ok "System dependencies OK"
}

# ── Wine prefix setup ──────────────────────────────────────────────
setup_prefix() {
    if [ ! -d "$WINEPREFIX/drive_c" ]; then
        info "Creating Wine prefix at $WINEPREFIX..."
        WINEPREFIX="$WINEPREFIX" "$WINE" wineboot -u 2>/dev/null
        ok "Wine prefix created"
    else
        ok "Wine prefix exists"
    fi
}

# ── .NET 8 Desktop Runtime ─────────────────────────────────────────
install_dotnet() {
    # Check if already installed
    if [ -f "$WINEPREFIX/drive_c/Program Files/dotnet/dotnet.exe" ]; then
        ok ".NET 8 Desktop Runtime already installed"
        return 0
    fi

    info "Installing .NET 8 Desktop Runtime..."
    local tmp="$MADWINE_DIR/cache/dotnet-8-desktop-runtime.exe"
    mkdir -p "$MADWINE_DIR/cache"

    if [ ! -f "$tmp" ]; then
        info "Downloading .NET 8 Desktop Runtime..."
        fetch "$DOTNET_URL" "$tmp"
    fi

    info "Running .NET 8 installer (this may take a minute)..."
    WINEPREFIX="$WINEPREFIX" "$WINE" "$tmp" /install /quiet /norestart 2>/dev/null || true

    if [ -f "$WINEPREFIX/drive_c/Program Files/dotnet/dotnet.exe" ]; then
        ok ".NET 8 Desktop Runtime installed"
    else
        warn ".NET 8 install may have partially failed — Madium might still work"
    fi
}

# ── WebView2 Runtime ───────────────────────────────────────────────
install_webview2() {
    # Check if already installed
    local wv2_app="$WINEPREFIX/drive_c/Program Files (x86)/Microsoft/EdgeWebView/Application"
    if [ -d "$wv2_app" ] && find "$wv2_app" -name "msedgewebview2.exe" -print -quit 2>/dev/null | grep -q .; then
        ok "WebView2 Runtime already installed"
        register_webview2
        return 0
    fi

    info "Installing WebView2 Runtime (offline, ~280MB)..."
    local tmp="$MADWINE_DIR/cache/MicrosoftEdgeWebView2RuntimeInstallerX64.exe"
    mkdir -p "$MADWINE_DIR/cache"

    if [ ! -f "$tmp" ]; then
        info "Downloading WebView2 offline installer..."
        fetch "$WEBVIEW2_URL" "$tmp"
    fi

    info "Running WebView2 installer..."
    WINEPREFIX="$WINEPREFIX" "$WINE" "$tmp" /silent /install 2>/dev/null || true

    # The installer often half-completes under Wine.
    # It unpacks into EdgeCore but may not copy to EdgeWebView/Application.
    # Fix it manually if needed.
    local edge_core="$WINEPREFIX/drive_c/Program Files (x86)/Microsoft/EdgeCore"
    if [ -d "$edge_core" ] && [ ! -d "$wv2_app" ]; then
        warn "WebView2 installer didn't finish — completing manually..."
        local ver_dir
        ver_dir=$(find "$edge_core" -mindepth 1 -maxdepth 1 -type d -not -name "*.old" | sort -V | tail -1)
        if [ -n "$ver_dir" ]; then
            local ver
            ver=$(basename "$ver_dir")
            mkdir -p "$wv2_app/$ver"
            cp -a "$ver_dir/." "$wv2_app/$ver/"
            ok "WebView2 Runtime files copied to Application/$ver"
        fi
    fi

    if find "$wv2_app" -name "msedgewebview2.exe" -print -quit 2>/dev/null | grep -q .; then
        register_webview2
        ok "WebView2 Runtime installed"
    else
        warn "WebView2 install failed — Madium UI may not work"
        warn "Try: WINEPREFIX=$WINEPREFIX wine '$tmp' (run manually)"
    fi
}

register_webview2() {
    local wv2_app="$WINEPREFIX/drive_c/Program Files (x86)/Microsoft/EdgeWebView/Application"
    local ver_dir
    ver_dir=$(find "$wv2_app" -mindepth 1 -maxdepth 1 -type d -not -name "SetupMetrics" -not -name "ResiliencyLinks" 2>/dev/null | sort -V | tail -1)
    [ -n "$ver_dir" ] || return 0
    local ver
    ver=$(basename "$ver_dir")

    info "Registering WebView2 v$ver in registry..."
    for key in \
        "HKLM\\SOFTWARE\\WOW6432Node\\Microsoft\\EdgeUpdate\\Clients\\$WEBVIEW2_GUID" \
        "HKLM\\SOFTWARE\\Microsoft\\EdgeUpdate\\Clients\\$WEBVIEW2_GUID" \
        "HKCU\\SOFTWARE\\Microsoft\\EdgeUpdate\\Clients\\$WEBVIEW2_GUID"; do
        WINEPREFIX="$WINEPREFIX" "$WINE" reg add "$key" /v pv /t REG_SZ /d "$ver" /f &>/dev/null || true
        WINEPREFIX="$WINEPREFIX" "$WINE" reg add "$key" /v name /t REG_SZ /d "Microsoft Edge WebView2 Runtime" /f &>/dev/null || true
    done
    ok "WebView2 registry keys set (v$ver)"
}

# ── Madium CDN files ────────────────────────────────────────────────
fetch_madium_files() {
    # Wine can't reach the Madium CDN (SSL to bare IP fails).
    # Download manifest + files from the host and place them in the prefix.
    local madium_dir=""
    for user_dir in "$WINEPREFIX/drive_c/users/"*/; do
        if [ -d "$user_dir/AppData/Local/Madium" ]; then
            madium_dir="$user_dir/AppData/Local/Madium"
            break
        fi
    done

    if [ -z "$madium_dir" ]; then
        # Create default location
        local wine_user
        wine_user=$(WINEPREFIX="$WINEPREFIX" "$WINE" cmd /c "echo %USERNAME%" 2>/dev/null | tr -d '\r\n') || wine_user="$(whoami)"
        madium_dir="$WINEPREFIX/drive_c/users/$wine_user/AppData/Local/Madium"
        mkdir -p "$madium_dir/Bin"
    fi

    local bin_dir="$madium_dir/Bin"
    mkdir -p "$bin_dir" "$MADWINE_DIR/cache"

    # Fetch manifest
    info "Fetching Madium CDN manifest..."
    local manifest
    manifest=$(get "$MADIUM_MANIFEST" 2>/dev/null) || {
        warn "Could not reach Madium CDN ($MADIUM_CDN)"
        warn "Check your internet connection or try again later."
        return 1
    }

    local version
    version=$(echo "$manifest" | grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | grep -o '"[^"]*"$' | tr -d '"')
    info "Madium CDN version: $version"

    # Parse files from manifest and download each
    local names urls sizes sha256s
    names=$(echo "$manifest" | grep -o '"name"[[:space:]]*:[[:space:]]*"[^"]*"' | grep -o '"[^"]*"$' | tr -d '"')
    urls=$(echo "$manifest" | grep -o '"url"[[:space:]]*:[[:space:]]*"[^"]*"' | grep -o '"[^"]*"$' | tr -d '"')
    sha256s=$(echo "$manifest" | grep -o '"sha256"[[:space:]]*:[[:space:]]*"[^"]*"' | grep -o '"[^"]*"$' | tr -d '"')

    local name_arr=() url_arr=() sha_arr=()
    while IFS= read -r line; do name_arr+=("$line"); done <<< "$names"
    while IFS= read -r line; do url_arr+=("$line"); done <<< "$urls"
    while IFS= read -r line; do sha_arr+=("$line"); done <<< "$sha256s"

    local i total=${#name_arr[@]} failed=0
    for ((i=0; i<total; i++)); do
        local fname="${name_arr[$i]}"
        local furl="${url_arr[$i]}"
        local fsha="${sha_arr[$i]}"
        local dest="$bin_dir/$fname"
        local cache="$MADWINE_DIR/cache/$fname"

        # Check if file exists and matches SHA256
        if [ -f "$dest" ] && command -v sha256sum &>/dev/null; then
            local existing_sha
            existing_sha=$(sha256sum "$dest" | awk '{print $1}')
            if [ "$existing_sha" = "$fsha" ]; then
                ok "$fname already up to date"
                continue
            fi
        fi

        info "Downloading $fname ($((i+1))/$total)..."

        # Download to cache first (resume-friendly), then copy to prefix
        if ! fetch "$furl" "$cache"; then
            warn "Failed to download $fname"
            ((failed++))
            continue
        fi

        # Verify SHA256
        if command -v sha256sum &>/dev/null; then
            local dl_sha
            dl_sha=$(sha256sum "$cache" | awk '{print $1}')
            if [ "$dl_sha" != "$fsha" ]; then
                warn "$fname SHA256 mismatch (expected $fsha, got $dl_sha)"
                rm -f "$cache"
                ((failed++))
                continue
            fi
        fi

        cp -f "$cache" "$dest"
        ok "$fname downloaded and verified"
    done

    if [ $failed -gt 0 ]; then
        warn "$failed file(s) failed to download"
        return 1
    fi

    ok "All Madium CDN files installed (v$version)"
}

# ── Madium installer ───────────────────────────────────────────────
install_madium() {
    # Find or create Madium directory
    local madium_exe=""
    for user_dir in "$WINEPREFIX/drive_c/users/"*/; do
        local candidate="$user_dir/AppData/Local/Madium/Bin/Madium.exe"
        if [ -f "$candidate" ]; then
            madium_exe="$candidate"
            break
        fi
    done

    local installer_url repo="UDIN-K/madwine"

    if [ -z "$madium_exe" ]; then
        # Try to get the installer from releases or madium.net
        info "Fetching Madium installer..."
        local madium_installer="$MADWINE_DIR/cache/MadiumInstaller.exe"

        if [ ! -f "$madium_installer" ]; then
            installer_url=$(get "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null \
                | grep -o 'https://[^"]*MadiumInstaller[^"]*\.exe' | head -1) || true

            if [ -n "$installer_url" ]; then
                fetch "$installer_url" "$madium_installer"
            else
                warn "No installer found in releases."
                warn "Download MadiumInstaller.exe manually from https://madium.net"
                warn "Then place it at: $madium_installer"
                warn "And re-run this script."
                return 1
            fi
        fi

        info "Running Madium installer..."
        info "  → Select 'Custom Installation'"
        info "  → Untick 'Auto exclude from Windows Defender'"
        info "  → Continue with install"
        WINEPREFIX="$WINEPREFIX" "$WINE" "$madium_installer" 2>/dev/null || true
    else
        ok "Madium.exe found"
    fi

    # Fetch CDN files (DLLs + cache) — Wine can't do this itself
    info "Fetching Madium executor files from CDN..."
    fetch_madium_files
}

# ── Launch ──────────────────────────────────────────────────────────
launch_madium() {
    # Find Madium.exe - check common locations
    local madium_exe=""
    for user_dir in "$WINEPREFIX/drive_c/users/"*/; do
        local candidate="$user_dir/AppData/Local/Madium/Bin/Madium.exe"
        if [ -f "$candidate" ]; then
            madium_exe="$candidate"
            break
        fi
    done

    if [ -z "$madium_exe" ]; then
        die "Madium.exe not found. Run '$0 install' first."
    fi

    info "Launching Madium..."
    WINEPREFIX="$WINEPREFIX" \
    WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS="--disable-gpu --no-sandbox --disable-gpu-compositing" \
    "$WINE" "$madium_exe" "$@" 2>/dev/null &
    ok "Madium launched (PID: $!)"
}

# ── Desktop entry ──────────────────────────────────────────────────
create_desktop_entry() {
    local desktop_file="${XDG_DATA_HOME:-$HOME/.local/share}/applications/madwine.desktop"
    local script_path
    script_path=$(realpath "$0")

    cat > "$desktop_file" << EOF
[Desktop Entry]
Name=Madium (Wine)
Comment=Run Madium on Linux via Wine
Exec=$script_path launch
Type=Application
Categories=Game;
Terminal=false
EOF

    if command -v update-desktop-database &>/dev/null; then
        update-desktop-database "${XDG_DATA_HOME:-$HOME/.local/share}/applications" 2>/dev/null || true
    fi
    ok "Desktop entry created: $desktop_file"
}

# ── Main ────────────────────────────────────────────────────────────
usage() {
    cat << EOF
madwine - Run Madium on Linux

Usage: $0 <command>

Commands:
  install     Full install: prefix + .NET 8 + WebView2 + Madium + CDN files
  update      Update Madium CDN files (DLLs + cache)
  deps        Install dependencies only (.NET 8 + WebView2)
  launch      Launch Madium
  desktop     Create desktop shortcut
  prefix      Show Wine prefix path
  status      Check installation status
  clean       Remove Wine prefix and cache
  help        Show this help

Environment:
  WINEPREFIX  Wine prefix path (default: ~/.local/share/madwine/prefix)
  WINE        Wine executable (default: wine)
  MADWINE_DIR Data directory (default: ~/.local/share/madwine)

EOF
}

cmd_update() {
    info "Updating Madium CDN files..."
    fetch_madium_files
}

cmd_install() {
    info "madwine installer"
    echo ""
    check_deps
    setup_prefix
    install_dotnet
    install_webview2
    install_madium
    echo ""
    ok "Installation complete!"
    info "Run: $0 launch"
}

cmd_deps() {
    check_deps
    setup_prefix
    install_dotnet
    install_webview2
    echo ""
    ok "Dependencies installed!"
}

cmd_status() {
    echo "madwine status"
    echo "─────────────────────────────────────"
    echo "Prefix:    $WINEPREFIX"
    echo "Wine:      $(command -v "$WINE" 2>/dev/null || echo 'not found')"
    echo ""

    # .NET 8
    if [ -f "$WINEPREFIX/drive_c/Program Files/dotnet/dotnet.exe" ]; then
        ok ".NET 8 Desktop Runtime"
    else
        warn ".NET 8 Desktop Runtime: NOT INSTALLED"
    fi

    # WebView2
    local wv2_app="$WINEPREFIX/drive_c/Program Files (x86)/Microsoft/EdgeWebView/Application"
    if find "$wv2_app" -name "msedgewebview2.exe" -print -quit 2>/dev/null | grep -q .; then
        local ver_dir
        ver_dir=$(find "$wv2_app" -mindepth 1 -maxdepth 1 -type d -not -name "SetupMetrics" -not -name "ResiliencyLinks" 2>/dev/null | sort -V | tail -1)
        ok "WebView2 Runtime ($(basename "$ver_dir" 2>/dev/null || echo 'unknown'))"
    else
        warn "WebView2 Runtime: NOT INSTALLED"
    fi

    # Madium
    local found=0
    for user_dir in "$WINEPREFIX/drive_c/users/"*/; do
        if [ -f "$user_dir/AppData/Local/Madium/Bin/Madium.exe" ]; then
            ok "Madium.exe"
            # Check CDN files
            local bin_dir="$user_dir/AppData/Local/Madium/Bin"
            for f in Madium.dll RobloxPlayerBeta.dll cache.bin; do
                if [ -f "$bin_dir/$f" ]; then
                    ok "  $f"
                else
                    warn "  $f: MISSING"
                fi
            done
            found=1
            break
        fi
    done
    [ $found -eq 1 ] || warn "Madium: NOT INSTALLED"
}

cmd_clean() {
    warn "This will delete:"
    warn "  $WINEPREFIX"
    warn "  $MADWINE_DIR/cache"
    printf "Continue? [y/N] "
    read -r answer
    if [[ "$answer" =~ ^[Yy] ]]; then
        rm -rf "$WINEPREFIX" "$MADWINE_DIR/cache"
        ok "Cleaned"
    else
        info "Cancelled"
    fi
}

case "${1:-help}" in
    install)  cmd_install ;;
    update)   cmd_update ;;
    deps)     cmd_deps ;;
    launch)   shift; launch_madium "$@" ;;
    desktop)  create_desktop_entry ;;
    prefix)   echo "$WINEPREFIX" ;;
    status)   cmd_status ;;
    clean)    cmd_clean ;;
    help|-h|--help) usage ;;
    *)        die "Unknown command: $1 (try '$0 help')" ;;
esac
