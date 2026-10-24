#!/usr/bin/env bash
set -e

APP_NAME="vView"
BIN_DIR="${HOME}/.local/bin"
DESKTOP_DIR="${HOME}/.local/share/applications"
DESKTOP_FILE="${DESKTOP_DIR}/${APP_NAME}.desktop"
ICON_DIR="${HOME}/.local/share/icons/hicolor/scalable/apps"

copy_files() {
    if [ ! -f "${APP_NAME}" ]; then
        echo "==> Binary ${APP_NAME} not found, building..."
        make build
    fi

    echo "==> Installing binary to ${BIN_DIR}..."
    mkdir -p "${BIN_DIR}"
    cp -f "${APP_NAME}" "${BIN_DIR}/${APP_NAME}"
    chmod 755 "${BIN_DIR}/${APP_NAME}"

    echo "==> Installing application icon to ${ICON_DIR}..."
    mkdir -p "${ICON_DIR}"
    cp -f "${APP_NAME}.svg" "${ICON_DIR}/${APP_NAME}.svg"
    cp -f "${APP_NAME}.svg" "${ICON_DIR}/com.example.${APP_NAME}.svg"

    # Generate raster PNG icons (16, 24, 32, 48, 64, 128, 256, 512) for window managers/alt-tab
    python3 - << 'PYEOF' 2>/dev/null || true
import gi
try:
    gi.require_version('Rsvg', '2.0')
    from gi.repository import Rsvg
    import cairo, os

    handle = Rsvg.Handle.new_from_file("vView.svg")
    base_icon_dir = os.path.expanduser("~/.local/share/icons/hicolor")
    for size in [16, 24, 32, 48, 64, 128, 256, 512]:
        target_dir = os.path.join(base_icon_dir, f"{size}x{size}/apps")
        os.makedirs(target_dir, exist_ok=True)
        surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, size, size)
        cr = cairo.Context(surface)
        vp = Rsvg.Rectangle()
        vp.x = 0
        vp.y = 0
        vp.width = size
        vp.height = size
        handle.render_document(cr, vp)
        surface.write_to_png(os.path.join(target_dir, "vView.png"))
        surface.write_to_png(os.path.join(target_dir, "com.example.vView.png"))
except Exception as e:
    pass
PYEOF

    if command -v gtk-update-icon-cache >/dev/null 2>&1; then
        gtk-update-icon-cache "${HOME}/.local/share/icons/hicolor" 2>/dev/null || true
    fi

    echo "==> Registering desktop application in ${DESKTOP_DIR}..."
    mkdir -p "${DESKTOP_DIR}"
    cat <<EOF > "${DESKTOP_FILE}"
[Desktop Entry]
Name=vView
GenericName=Image Viewer
Comment=Fast and lightweight image viewer
Exec=${BIN_DIR}/${APP_NAME} %F
Terminal=false
Type=Application
Icon=${APP_NAME}
Categories=Graphics;Viewer;GTK;
MimeType=image/jpeg;image/png;image/gif;image/webp;
StartupNotify=true
StartupWMClass=com.example.vView
EOF
    chmod 644 "${DESKTOP_FILE}"
    ln -sf "${APP_NAME}.desktop" "${DESKTOP_DIR}/com.example.${APP_NAME}.desktop"

    if command -v update-desktop-database >/dev/null 2>&1; then
        echo "==> Updating desktop database..."
        update-desktop-database "${DESKTOP_DIR}"
    fi

    echo ""
    echo "✓ ${APP_NAME} successfully installed!"
    echo "  Binary:  ${BIN_DIR}/${APP_NAME}"
    echo "  Desktop: ${DESKTOP_FILE}"
    echo "  It will now appear in GNOME/Nautilus 'Open With...' for images."
}

install_app() {
    echo "==> Building ${APP_NAME}..."
    make build
    copy_files
}

uninstall_app() {
    echo "==> Uninstalling ${APP_NAME}..."
    if [ -f "${BIN_DIR}/${APP_NAME}" ]; then
        rm -f "${BIN_DIR}/${APP_NAME}"
        echo "  Removed ${BIN_DIR}/${APP_NAME}"
    fi

    if [ -f "${DESKTOP_FILE}" ]; then
        rm -f "${DESKTOP_FILE}"
        echo "  Removed ${DESKTOP_FILE}"
    fi
    if [ -f "${DESKTOP_DIR}/com.example.${APP_NAME}.desktop" ]; then
        rm -f "${DESKTOP_DIR}/com.example.${APP_NAME}.desktop"
    fi

    if [ -f "${ICON_DIR}/${APP_NAME}.svg" ]; then
        rm -f "${ICON_DIR}/${APP_NAME}.svg"
        rm -f "${ICON_DIR}/com.example.${APP_NAME}.svg"
        echo "  Removed ${ICON_DIR}/${APP_NAME}.svg"
        base_icon_dir="${HOME}/.local/share/icons/hicolor"
        for size in 16 24 32 48 64 128 256 512; do
            rm -f "${base_icon_dir}/${size}x${size}/apps/${APP_NAME}.png"
            rm -f "${base_icon_dir}/${size}x${size}/apps/com.example.${APP_NAME}.png"
        done
        if command -v gtk-update-icon-cache >/dev/null 2>&1; then
            gtk-update-icon-cache "${HOME}/.local/share/icons/hicolor" 2>/dev/null || true
        fi
    fi

    if command -v update-desktop-database >/dev/null 2>&1; then
        echo "==> Updating desktop database..."
        update-desktop-database "${DESKTOP_DIR}"
    fi

    echo ""
    echo "✓ ${APP_NAME} successfully uninstalled."
}

case "$1" in
    uninstall)
        uninstall_app
        ;;
    install-lite)
        copy_files
        ;;
    install|"")
        install_app
        ;;
    *)
        echo "Usage: $0 [install|install-lite|uninstall]"
        exit 1
        ;;
esac
