#!/usr/bin/env bash
set -e

APP_NAME="vView"
BIN_DIR="${HOME}/.local/bin"
DESKTOP_DIR="${HOME}/.local/share/applications"
DESKTOP_FILE="${DESKTOP_DIR}/${APP_NAME}.desktop"

install_app() {
    echo "==> Building ${APP_NAME}..."
    make build

    echo "==> Installing binary to ${BIN_DIR}..."
    mkdir -p "${BIN_DIR}"
    cp -f "${APP_NAME}" "${BIN_DIR}/${APP_NAME}"
    chmod 755 "${BIN_DIR}/${APP_NAME}"

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
Icon=image-viewer
Categories=Graphics;Viewer;GTK;
MimeType=image/jpeg;image/png;image/gif;image/webp;
StartupNotify=true
EOF
    chmod 644 "${DESKTOP_FILE}"

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
    install|"")
        install_app
        ;;
    *)
        echo "Usage: $0 [install|uninstall]"
        exit 1
        ;;
esac
