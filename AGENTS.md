# Project Rules & Guidelines for AI Agents

## Language Requirement
- **All code, comments, documentation, README files, tooltips, commit messages, and user-facing strings must be exclusively in English.**
- Never write Russian or other non-English languages in code comments, docstrings, UI labels, or documentation.

## Tech Stack & Architecture
- **Language:** Vala (compiled via `valac`)
- **UI Toolkit:** GTK4 + Libadwaita (`libadwaita-1`)
- **Build System:** Makefile / Meson (minimal dependencies, fast builds)
- **Target Platform:** Linux desktop (GNOME, KDE, XFCE, etc.)

## Development Conventions
- Follow GNOME Human Interface Guidelines (HIG).
- Keep the binary lightweight and compile times sub-second.
- Prefer GIO / GLib native APIs for I/O and event handling.
- Preserve clean separation of concerns and ensure all resource cleanups and event controllers are properly handled.

## Workflow & Testing
- **Local Installation:** Always run `./install.sh install-lite` (or `make install-lite`) upon completing changes so the user can immediately test the live application without redundant rebuilds.
- **Git Restrictions:** Do not run `git commit` or `git push` autonomously; all commits and pushes are handled directly by the user.
