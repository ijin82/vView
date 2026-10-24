public class VViewApp : Adw.Application {
    private Adw.ApplicationWindow? win = null;
    private Gtk.Picture picture;
    private Adw.HeaderBar header;
    private Gtk.Button save_button;
    private Gdk.Pixbuf? current_pixbuf = null;
    private bool is_modified = false;
    private string[] image_files;
    private int current_index = 0;
    private uint cursor_timeout_id = 0;
    private string? target_path = null;

    public VViewApp () {
        Object (
            application_id: "com.example.vView",
            flags: ApplicationFlags.HANDLES_COMMAND_LINE
        );
    }

    protected override int command_line (ApplicationCommandLine cmd) {
        var args = cmd.get_arguments ();
        if (args.length > 1) {
            var file = cmd.create_file_for_arg (args[1]);
            target_path = file.get_path ();
        } else {
            target_path = null;
        }

        if (win == null) {
            activate ();
        } else {
            if (target_path != null) {
                load_images (target_path);
            }
            win.present ();
        }

        return 0;
    }

    protected override void activate () {
        if (win != null) {
            win.present ();
            return;
        }

        win = new Adw.ApplicationWindow (this);
        win.set_default_size (1000, 700);

        header = new Adw.HeaderBar ();

        // Previous / Next buttons in HeaderBar
        var prev_button = new Gtk.Button.from_icon_name ("go-previous-symbolic");
        prev_button.tooltip_text = "Previous image (Left arrow / Scroll up)";
        prev_button.clicked.connect (() => {
            show_image (current_index - 1);
        });
        header.pack_start (prev_button);

        var next_button = new Gtk.Button.from_icon_name ("go-next-symbolic");
        next_button.tooltip_text = "Next image (Right arrow / Scroll down)";
        next_button.clicked.connect (() => {
            show_image (current_index + 1);
        });
        header.pack_start (next_button);

        // Fullscreen toggle button in HeaderBar
        var fs_button = new Gtk.Button.from_icon_name ("view-fullscreen-symbolic");
        fs_button.tooltip_text = "Fullscreen mode (F / Double click)";
        fs_button.clicked.connect (toggle_fullscreen);
        header.pack_end (fs_button);

        // Info / Shortcuts button
        var info_button = new Gtk.Button.from_icon_name ("dialog-information-symbolic");
        info_button.tooltip_text = "Keyboard Shortcuts & Info (F1)";
        info_button.clicked.connect (show_shortcuts_dialog);
        header.pack_end (info_button);

        // Rotate clockwise button
        var rotate_cw_button = new Gtk.Button.from_icon_name ("object-rotate-right-symbolic");
        rotate_cw_button.tooltip_text = "Rotate clockwise (R)";
        rotate_cw_button.clicked.connect (() => rotate_image (true));
        header.pack_end (rotate_cw_button);

        // Rotate counter-clockwise button
        var rotate_ccw_button = new Gtk.Button.from_icon_name ("object-rotate-left-symbolic");
        rotate_ccw_button.tooltip_text = "Rotate counter-clockwise (L)";
        rotate_ccw_button.clicked.connect (() => rotate_image (false));
        header.pack_end (rotate_ccw_button);

        // Save button (hidden until image is rotated)
        save_button = new Gtk.Button.with_label ("Save");
        save_button.icon_name = "document-save-symbolic";
        save_button.add_css_class ("suggested-action");
        save_button.tooltip_text = "Save rotated image (Ctrl+S)";
        save_button.visible = false;
        save_button.clicked.connect (prompt_save_image);
        header.pack_end (save_button);

        // Track fullscreen state changes
        win.notify["fullscreened"].connect (() => {
            header.visible = !win.fullscreened;
            if (win.fullscreened) {
                reset_cursor_inactivity_timer ();
            } else {
                show_cursor ();
                cancel_cursor_timer ();
            }
        });

        var toolbar_view = new Adw.ToolbarView ();
        toolbar_view.add_top_bar (header);

        // Image display widget
        picture = new Gtk.Picture ();
        picture.can_shrink = true;
        picture.content_fit = Gtk.ContentFit.CONTAIN;

        toolbar_view.set_content (picture);
        win.set_content (toolbar_view);

        // Track mouse motion for cursor visibility and inactivity timer
        var motion_controller = new Gtk.EventControllerMotion ();
        motion_controller.motion.connect ((x, y) => {
            if (win.fullscreened) {
                show_cursor ();
                reset_cursor_inactivity_timer ();
            }
        });
        ((Gtk.Widget) win).add_controller (motion_controller);

        // Double click to toggle fullscreen mode
        var click_gesture = new Gtk.GestureClick ();
        click_gesture.pressed.connect ((n_press, x, y) => {
            if (n_press == 2) {
                if (win.fullscreened) {
                    win.unfullscreen ();
                } else {
                    win.fullscreen ();
                }
            }
        });
        ((Gtk.Widget) win).add_controller (click_gesture);

        // Mouse scroll wheel: down -> next image, up -> previous image
        var scroll_controller = new Gtk.EventControllerScroll (Gtk.EventControllerScrollFlags.VERTICAL);
        scroll_controller.scroll.connect ((dx, dy) => {
            if (win.fullscreened) {
                show_cursor ();
                reset_cursor_inactivity_timer ();
            }

            if (image_files.length > 1) {
                if (dy > 0) {
                    show_image (current_index + 1);
                    return true;
                } else if (dy < 0) {
                    show_image (current_index - 1);
                    return true;
                }
            }
            return false;
        });
        ((Gtk.Widget) win).add_controller (scroll_controller);

        // Keyboard navigation (Ctrl+Q, Ctrl+S, F, Escape, Left, Right, R, L)
        var key_controller = new Gtk.EventControllerKey ();
        key_controller.key_pressed.connect ((keyval, keycode, state) => {
            // Translate keycode to primary Latin layout (group 0) for layout independence
            uint latin_keyval = keyval;
            var display = Gdk.Display.get_default ();
            if (display != null) {
                uint translated;
                int eff_group, level;
                Gdk.ModifierType consumed;
                if (display.translate_key (keycode, 0, 0, out translated, out eff_group, out level, out consumed)) {
                    if (translated != 0) {
                        latin_keyval = translated;
                    }
                }
            }

            uint latin_lower = Gdk.keyval_to_lower (latin_keyval);
            uint key_lower = Gdk.keyval_to_lower (keyval);

            // Exit on Ctrl+Q (works across all layouts)
            if ((state & Gdk.ModifierType.CONTROL_MASK) != 0 &&
                (latin_lower == Gdk.Key.q || key_lower == Gdk.Key.Cyrillic_shorti)) {
                quit ();
                return true;
            }

            // Save on Ctrl+S (prompt) or Ctrl+Shift+S (direct Save As)
            if ((state & Gdk.ModifierType.CONTROL_MASK) != 0 &&
                (latin_lower == Gdk.Key.s || key_lower == Gdk.Key.Cyrillic_yeru)) {
                if (is_modified) {
                    if ((state & Gdk.ModifierType.SHIFT_MASK) != 0) {
                        show_save_as_dialog ();
                    } else {
                        prompt_save_image ();
                    }
                    return true;
                }
            }

            // Check primary action keys by translated Latin key or direct Cyrillic key
            if (latin_lower == Gdk.Key.f || key_lower == Gdk.Key.Cyrillic_a) {
                toggle_fullscreen ();
                return true;
            }

            if (latin_lower == Gdk.Key.r || key_lower == Gdk.Key.Cyrillic_ka) {
                rotate_image (true);
                return true;
            }

            if (latin_lower == Gdk.Key.l || key_lower == Gdk.Key.Cyrillic_de) {
                rotate_image (false);
                return true;
            }

            if (latin_lower == Gdk.Key.F1 || keyval == Gdk.Key.F1 || keyval == Gdk.Key.question) {
                show_shortcuts_dialog ();
                return true;
            }

            switch (keyval) {
                case Gdk.Key.Escape:
                    if (win.fullscreened) {
                        win.unfullscreen ();
                        return true;
                    }
                    break;

                case Gdk.Key.Left:
                case Gdk.Key.Page_Up:
                    show_image (current_index - 1);
                    return true;

                case Gdk.Key.Right:
                case Gdk.Key.Page_Down:
                case Gdk.Key.space:
                    show_image (current_index + 1);
                    return true;

                case Gdk.Key.Home:
                    show_image (0);
                    return true;

                case Gdk.Key.End:
                    show_image (image_files.length - 1);
                    return true;
            }
            return false;
        });
        ((Gtk.Widget) win).add_controller (key_controller);

        // Load images if target_path was provided
        if (target_path != null) {
            load_images (target_path);
        } else {
            win.title = "vView";
        }

        win.present ();
    }

    private void show_shortcuts_dialog () {
        var dialog = new Adw.AlertDialog ("vView", "Keyboard Shortcuts & Controls");
        dialog.add_response ("close", "Close");
        dialog.set_default_response ("close");
        dialog.set_close_response ("close");

        var group = new Adw.PreferencesGroup ();

        add_shortcut_row (group, "Toggle Fullscreen", "F / Double Click");
        add_shortcut_row (group, "Exit Fullscreen", "Escape");
        add_shortcut_row (group, "Next Image", "→ / Space / Scroll Down");
        add_shortcut_row (group, "Previous Image", "← / Scroll Up");
        add_shortcut_row (group, "Rotate Clockwise", "R");
        add_shortcut_row (group, "Rotate Counter-Clockwise", "L");
        add_shortcut_row (group, "Save (Prompt)", "Ctrl + S");
        add_shortcut_row (group, "Save As…", "Ctrl + Shift + S");
        add_shortcut_row (group, "First / Last Image", "Home / End");
        add_shortcut_row (group, "Shortcuts & Info", "F1");
        add_shortcut_row (group, "Quit", "Ctrl + Q");

        var scrolled = new Gtk.ScrolledWindow ();
        scrolled.propagate_natural_height = true;
        scrolled.max_content_height = 450;
        scrolled.set_child (group);

        dialog.set_extra_child (scrolled);
        dialog.choose.begin (win, null, null);
    }

    private void add_shortcut_row (Adw.PreferencesGroup group, string title, string shortcut) {
        var row = new Adw.ActionRow ();
        row.title = title;
        var badge = new Gtk.Label ("<tt><b>%s</b></tt>".printf (shortcut));
        badge.use_markup = true;
        badge.add_css_class ("dim-label");
        row.add_suffix (badge);
        group.add (row);
    }

    private void rotate_image (bool clockwise) {
        if (current_pixbuf == null || image_files.length == 0) return;

        var rot = clockwise ? Gdk.PixbufRotation.CLOCKWISE : Gdk.PixbufRotation.COUNTERCLOCKWISE;
        current_pixbuf = current_pixbuf.rotate_simple (rot);
        picture.set_paintable (Gdk.Texture.for_pixbuf (current_pixbuf));

        is_modified = true;
        save_button.visible = true;
    }

    private void prompt_save_image () {
        if (current_pixbuf == null || image_files.length == 0 || !is_modified) return;

        var path = image_files[current_index];
        var filename = Path.get_basename (path);

        var dialog = new Adw.AlertDialog (
            "Save Image",
            "Do you want to overwrite \"%s\" or save as a new file?".printf (filename)
        );
        dialog.add_response ("cancel", "Cancel");
        dialog.add_response ("save_as", "Save As…");
        dialog.add_response ("overwrite", "Overwrite");
        dialog.set_response_appearance ("overwrite", Adw.ResponseAppearance.SUGGESTED);
        dialog.set_default_response ("overwrite");
        dialog.set_close_response ("cancel");

        dialog.choose.begin (win, null, (obj, res) => {
            var response = dialog.choose.end (res);
            if (response == "overwrite") {
                save_to_path (path);
            } else if (response == "save_as") {
                show_save_as_dialog ();
            }
        });
    }

    private void show_save_as_dialog () {
        if (current_pixbuf == null || image_files.length == 0) return;

        var current_path = image_files[current_index];
        var current_file = File.new_for_path (current_path);
        var parent_dir = current_file.get_parent ();
        var filename = current_file.get_basename ();

        var file_dialog = new Gtk.FileDialog ();
        file_dialog.title = "Save Image As";
        file_dialog.set_initial_name (filename);
        if (parent_dir != null) {
            file_dialog.set_initial_folder (parent_dir);
        }

        var filter_all = new Gtk.FileFilter ();
        filter_all.name = "All Supported Images (*.jpg, *.png, *.webp, *.gif)";
        filter_all.add_pattern ("*.jpg");
        filter_all.add_pattern ("*.jpeg");
        filter_all.add_pattern ("*.png");
        filter_all.add_pattern ("*.webp");
        filter_all.add_pattern ("*.gif");

        var filters = new GLib.ListStore (typeof (Gtk.FileFilter));
        filters.append (filter_all);
        file_dialog.set_filters (filters);

        file_dialog.save.begin (win, null, (obj, res) => {
            try {
                var dest_file = file_dialog.save.end (res);
                if (dest_file != null) {
                    var dest_path = dest_file.get_path ();
                    if (dest_path != null) {
                        save_to_path (dest_path);
                        load_images (dest_path);
                    }
                }
            } catch (Error e) {
                // User cancelled the file dialog
            }
        });
    }

    private void save_to_path (string dest_path) {
        if (current_pixbuf == null) return;
        var lower = dest_path.down ();

        try {
            if (lower.has_suffix (".jpg") || lower.has_suffix (".jpeg")) {
                current_pixbuf.save (dest_path, "jpeg", "quality", "95", null);
            } else if (lower.has_suffix (".webp")) {
                current_pixbuf.save (dest_path, "webp", "quality", "95", null);
            } else if (lower.has_suffix (".png")) {
                current_pixbuf.save (dest_path, "png", null);
            } else if (lower.has_suffix (".gif")) {
                current_pixbuf.save (dest_path, "gif", null);
            } else {
                current_pixbuf.save (dest_path + ".jpg", "jpeg", "quality", "95", null);
            }

            is_modified = false;
            save_button.visible = false;
            win.title = "vView - %s".printf (dest_path);
        } catch (Error e) {
            warning ("Error saving image '%s': %s", dest_path, e.message);
        }
    }

    private void toggle_fullscreen () {
        if (win.fullscreened) {
            win.unfullscreen ();
        } else {
            win.fullscreen ();
        }
    }

    private void show_cursor () {
        win.set_cursor (null);
    }

    private void hide_cursor () {
        win.set_cursor_from_name ("none");
    }

    private void cancel_cursor_timer () {
        if (cursor_timeout_id != 0) {
            Source.remove (cursor_timeout_id);
            cursor_timeout_id = 0;
        }
    }

    private void reset_cursor_inactivity_timer () {
        cancel_cursor_timer ();
        cursor_timeout_id = Timeout.add_seconds (2, () => {
            if (win.fullscreened) {
                hide_cursor ();
            }
            cursor_timeout_id = 0;
            return Source.REMOVE;
        });
    }

    private void load_images (string target_file) {
        var file = File.new_for_path (target_file);

        if (!file.query_exists ()) {
            image_files = {};
            current_pixbuf = null;
            picture.set_paintable (null);
            win.title = "vView";
            return;
        }

        string dir_path;
        string initial_filename;

        if (file.query_file_type (FileQueryInfoFlags.NONE) == FileType.DIRECTORY) {
            dir_path = target_file;
            initial_filename = "";
        } else {
            dir_path = Path.get_dirname (target_file);
            initial_filename = target_file;
        }

        GLib.List<string> list = null;

        try {
            var dir = Dir.open (dir_path);
            string? name = null;
            while ((name = dir.read_name ()) != null) {
                var lower = name.down ();
                // Support jpg, jpeg, png, gif, webp
                if (lower.has_suffix (".jpg") || lower.has_suffix (".jpeg") ||
                    lower.has_suffix (".png") || lower.has_suffix (".gif")  ||
                    lower.has_suffix (".webp")) {
                    list.prepend (Path.build_filename (dir_path, name));
                }
            }
        } catch (FileError e) {
            warning ("Error reading directory: %s", e.message);
        }

        if (list == null) {
            image_files = {};
            current_pixbuf = null;
            picture.set_paintable (null);
            win.title = "vView - No images";
            return;
        }

        list.sort (strcmp);
        image_files = {};
        foreach (var item in list) {
            image_files += item;
        }

        // Find starting image index
        current_index = 0;
        for (int i = 0; i < image_files.length; i++) {
            if (image_files[i] == initial_filename) {
                current_index = i;
                break;
            }
        }

        show_image (current_index);
    }

    private void show_image (int index) {
        if (image_files.length == 0) return;

        if (index < 0) {
            current_index = image_files.length - 1;
        } else if (index >= image_files.length) {
            current_index = 0;
        } else {
            current_index = index;
        }

        is_modified = false;
        save_button.visible = false;

        var path = image_files[current_index];
        try {
            current_pixbuf = new Gdk.Pixbuf.from_file (path);
            picture.set_paintable (Gdk.Texture.for_pixbuf (current_pixbuf));
        } catch (Error e) {
            warning ("Could not load image '%s': %s", path, e.message);
            current_pixbuf = null;
            picture.set_paintable (null);
        }

        win.title = "vView - %s".printf (path);
    }

    public static int main (string[] args) {
        var app = new VViewApp ();
        return app.run (args);
    }
}
