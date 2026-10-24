# vView (Vala View)

**vView** is a lightweight, blazing-fast, and minimalist image viewer for Linux, built with **Vala**, **GTK4**, and **Libadwaita**.

It seamlessly integrates with GNOME desktop environments following the GNOME Human Interface Guidelines (HIG), while functioning smoothly across all other desktop environments (KDE Plasma, XFCE, etc.).

The compiled binary is only **~45 KB**, and compile times are under **1 second**.

---

## Features

* 🎨 **Native GNOME Experience:** Rounded window corners, adaptive `Adw.HeaderBar`, and automatic system dark/light style support.
* 🖥️ **Fullscreen Mode:**
  * Toggle using the `F` key or double-clicking the mouse.
  * The header bar automatically hides in fullscreen.
  * **Auto-hiding cursor:** The mouse cursor vanishes after 2 seconds of inactivity and reappears upon movement.
* 📁 **Smart Directory Navigation:**
  * Opens the requested image and gathers all supported images in the same directory.
  * Infinite looping (navigating past the last image loops back to the first).
  * Supported formats: **JPEG** (`.jpg`, `.jpeg`), **PNG** (`.png`), **GIF** (`.gif`), **WebP** (`.webp`).
* 🔄 **In-Memory Rotation & Flexible Saving:**
  * Rotate images clockwise (`R`) or counter-clockwise (`L`) in-memory without altering the original file immediately.
  * A prominent **Save** button appears in the header bar as soon as changes are made.
  * Choice between **Overwrite** (save directly into the current file) and **Save As…** (choose directory and filename via native `Gtk.FileDialog`).
  * Preserves original file format and high visual fidelity (JPEG/WebP quality 95, lossless PNG/GIF).
* 🖱️ **Mouse Scroll Navigation:** Instantly switch to the next/previous image by scrolling the mouse wheel.
* ⌨️ **Ergonomic Shortcuts:** Intuitive keyboard navigation.
* 🏷️ **Clear Window Title:** Displays the full path of the current image: `vView - /path/to/image.jpg`.

---

## Controls

### Keyboard

| Key | Action |
| :--- | :--- |
| `F` | Toggle fullscreen mode |
| `Escape` | Exit fullscreen mode |
| `R` | Rotate image clockwise (90°) |
| `L` | Rotate image counter-clockwise (90°) |
| `Ctrl + S` | Save image (prompt: Overwrite or Save As…) |
| `Ctrl + Shift + S` | Direct "Save As…" (file chooser dialog) |
| `→` / `Space` / `Page Down` | Next image |
| `←` / `Page Up` | Previous image |
| `Home` | Jump to first image in directory |
| `End` | Jump to last image in directory |
| `F1` | Show keyboard shortcuts & info dialog |
| `Ctrl + Q` | Quit application |

### Mouse

| Action | Description |
| :--- | :--- |
| **Scroll Wheel Down** | Next image |
| **Scroll Wheel Up** | Previous image |
| **Double Click (Left Button)** | Toggle fullscreen mode |
| **Idle for 2 seconds (Fullscreen)** | Automatically hide cursor |

---

## Prerequisites & Setup (e.g. ALT Linux)

To clone, build, and continue development on a fresh machine (such as **ALT Linux Workstation / p10 / p11**), install the essential build tools, compiler, and development libraries:

### ALT Linux

Run the following command to install all necessary packages (including WebP image decoding support):

```bash
sudo apt-get update && sudo apt-get install -y \
    git \
    make \
    gcc \
    vala \
    libgtk4-devel \
    libadwaita-devel \
    libwebp-pixbuf-loader
```

*(Optional: install `gobject-introspection-devel` and `meson` if you plan to introduce GObject Introspection bindings or switch to the Meson build system).*

---

### Other Distributions

* **Ubuntu / Debian:**
  ```bash
  sudo apt update && sudo apt install -y git make gcc valac libgtk-4-dev libadwaita-1-dev webp-pixbuf-loader
  ```

* **Fedora:**
  ```bash
  sudo dnf install -y git make gcc vala gtk4-devel libadwaita-devel webp-pixbuf-loader
  ```

* **Arch Linux:**
  ```bash
  sudo pacman -S --needed git make gcc vala gtk4 libadwaita webp-pixbuf-loader
  ```

---

## Building and Running

Compile the binary:

```bash
make build
```

Compile and run immediately:

```bash
make run
```

Clean build artifacts:

```bash
make clean
```

---

## Installation & Desktop Integration

To install `vView` to `~/.local/bin` and register it with the GNOME desktop environment (so it appears in application menus and Nautilus "Open With..." for image files):

```bash
./install.sh install
# or
make install
```

To remove the binary and unregister desktop integration:

```bash
./install.sh uninstall
# or
make uninstall
```

---

## Command Line Usage

vView can be launched with a file or directory path argument (absolute or relative):

```bash
# Open a specific image
./vView /path/to/picture.jpg

# Open relative to the current directory
./vView ./photo.png

# Open a directory (opens the first supported image in the directory)
./vView ~/Pictures/
```

If launched without arguments, it opens a clean window with no image loaded.

---

## Troubleshooting & Tips

### Missing WebP Thumbnails in Nautilus / File Manager
If you previously viewed folders containing `.webp` files before installing `libwebp-pixbuf-loader`, Nautilus caches failed generation attempts in `~/.cache/thumbnails/fail/`. 

To reset the thumbnail cache and force immediate thumbnail generation for all WebP files, run:

```bash
rm -rf ~/.cache/thumbnails/fail/ && nautilus -q
```
