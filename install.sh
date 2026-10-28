#!/bin/bash
#
# Beltoclogin installer/updater for Linux (x64).
#   Install or update:  curl -fsSL https://raw.githubusercontent.com/Maraoui21/beltoclogin_releases/main/install.sh | sudo bash
# Run with no argument and it installs when missing, updates when a newer release
# exists, and does nothing when already up to date. `remove` uninstalls.
#
set -e

REPO="Maraoui21/beltoclogin_releases"
INSTALL_DIR="/opt/Beltoclogin"
APP_DIR="$INSTALL_DIR/app"
VERSION_FILE="$INSTALL_DIR/.version"

# ── helpers ─────────────────────────────────────────────────────────────────────
get_latest_version() {
    curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
        | grep '"tag_name"' | sed 's/.*"tag_name": *"\(.*\)".*/\1/'
}
get_installed_version() { [ -f "$VERSION_FILE" ] && cat "$VERSION_FILE" || echo "none"; }

install_system_deps() {
    echo "[+] Installing system dependencies..."
    apt-get update -qq || true
    # Electron runtime libs. Installed one by one so a package renamed between
    # Debian/Ubuntu versions (e.g. libasound2 vs libasound2t64) never aborts the rest.
    for pkg in libgtk-3-0 libnotify4 libnss3 libxss1 libxtst6 xdg-utils \
               libatspi2.0-0 libdrm2 libgbm1 libasound2 libasound2t64 \
               libsecret-1-0 unzip curl; do
        apt-get install -y --no-install-recommends "$pkg" 2>/dev/null || true
    done
    echo "[OK] System dependencies installed"
}

download_and_install() {
    local version=$1
    local url="https://github.com/$REPO/releases/download/$version/Beltoclogin-linux.zip"
    cd /tmp   # never sit inside a directory we are about to rm -rf

    echo "[+] Downloading Beltoclogin $version..."
    curl -fsSL "$url" -o /tmp/Beltoclogin-linux.zip

    echo "[+] Extracting..."
    rm -rf /tmp/Beltoclogin-extract && mkdir -p /tmp/Beltoclogin-extract
    unzip -q /tmp/Beltoclogin-linux.zip -d /tmp/Beltoclogin-extract

    # The zip holds a Beltoclogin-linux-x64/ folder with the `beltoclogin` binary.
    local bin inner_dir
    bin=$(find /tmp/Beltoclogin-extract -maxdepth 2 -type f -name beltoclogin | head -1)
    [ -z "$bin" ] && bin=$(find /tmp/Beltoclogin-extract -maxdepth 2 -type f -iname 'beltoclogin' | head -1)
    [ -z "$bin" ] && { echo "[x] Could not find the Beltoclogin binary in the download"; exit 1; }
    inner_dir=$(dirname "$bin")

    rm -rf "$APP_DIR"
    mkdir -p "$INSTALL_DIR"
    mv "$inner_dir" "$APP_DIR"
    rm -rf /tmp/Beltoclogin-extract /tmp/Beltoclogin-linux.zip

    chmod +x "$APP_DIR/beltoclogin" 2>/dev/null || true
    # The app lives in /opt (root-owned); the launcher runs as a normal user, so
    # make the whole tree readable + traversable + executable for everyone.
    chmod -R a+rX "$APP_DIR"
    # chrome-sandbox must be owned by root and setuid, otherwise Chromium refuses
    # to start; the launcher falls back to --no-sandbox if this ever isn't the case.
    if [ -f "$APP_DIR/chrome-sandbox" ]; then
        chown root:root "$APP_DIR/chrome-sandbox"
        chmod 4755 "$APP_DIR/chrome-sandbox"
    fi

    echo "$version" > "$VERSION_FILE"
    echo "[OK] Beltoclogin $version installed"
}

create_launcher() {
    cat > /usr/local/bin/beltoclogin <<EOF
#!/bin/bash
# Prefer the sandboxed binary; fall back to --no-sandbox where chrome-sandbox
# can't be setuid root (some RDP/container environments).
if [ -u "$APP_DIR/chrome-sandbox" ]; then
    exec "$APP_DIR/beltoclogin" "\$@"
else
    exec "$APP_DIR/beltoclogin" --no-sandbox "\$@"
fi
EOF
    chmod +x /usr/local/bin/beltoclogin

    cat > /usr/local/bin/beltoclogin-update <<'EOF'
#!/bin/bash
curl -fsSL https://raw.githubusercontent.com/Maraoui21/beltoclogin_releases/main/install.sh | sudo bash
EOF
    chmod +x /usr/local/bin/beltoclogin-update
    echo "[OK] Launcher: beltoclogin   ·   Updater: sudo beltoclogin-update"
}

create_desktop_entry() {
    local icon="$APP_DIR/resources/app/assets/icon.png"
    [ ! -f "$icon" ] && icon="application-x-executable"
    cat > /usr/share/applications/beltoclogin.desktop <<EOF
[Desktop Entry]
Name=Beltoclogin
Comment=Facebook profiles & groups automation
Exec=/usr/local/bin/beltoclogin
Icon=$icon
Type=Application
Categories=Utility;Network;
StartupNotify=true
Terminal=false
EOF
    update-desktop-database /usr/share/applications 2>/dev/null || true
    echo "[OK] Desktop shortcut created"
}

# ── commands ──────────────────────────────────────────────────────────────────
cmd_setup() {
    echo "=== Beltoclogin installer ==="
    local latest installed
    latest=$(get_latest_version)
    installed=$(get_installed_version)
    [ -z "$latest" ] && { echo "[x] Could not reach GitHub for the latest version"; exit 1; }
    echo "[i] Installed: $installed    Latest: $latest"

    if [ "$installed" = "none" ]; then
        install_system_deps
        download_and_install "$latest"
    elif [ "$installed" != "$latest" ]; then
        echo "[+] Updating $installed -> $latest..."
        pkill -x beltoclogin 2>/dev/null || true
        download_and_install "$latest"
    else
        echo "[OK] Already up to date"
    fi
    create_launcher
    create_desktop_entry
    echo ""
    echo "Done. Launch it with:  beltoclogin"
    echo "Update later with:     sudo beltoclogin-update"
}

cmd_remove() {
    echo "=== Beltoclogin uninstaller ==="
    pkill -x beltoclogin 2>/dev/null || true
    rm -rf "$INSTALL_DIR"
    rm -f /usr/local/bin/beltoclogin /usr/local/bin/beltoclogin-update
    rm -f /usr/share/applications/beltoclogin.desktop
    update-desktop-database /usr/share/applications 2>/dev/null || true
    echo "[OK] Beltoclogin removed"
}

# ── entry point ─────────────────────────────────────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
    echo "Please run with sudo:  curl -fsSL https://raw.githubusercontent.com/$REPO/main/install.sh | sudo bash"
    exit 1
fi
case "${1:-setup}" in
    setup|install|update) cmd_setup ;;
    remove|uninstall)     cmd_remove ;;
    *) echo "Usage: install.sh [setup|update|remove]"; exit 1 ;;
esac
