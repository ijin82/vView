public class ViewerController : GLib.Object {
    public Adw.ApplicationWindow win { get; construct set; }
    public ImageCanvas canvas { get; construct set; }
    public EditorManager editor { get; construct set; }
    public Gtk.Button save_button { get; construct set; }
    public Gtk.ToggleButton edit_toggle_button { get; construct set; }

    public string[] image_files;
    public int current_index = 0;
    public Gdk.Pixbuf? current_pixbuf = null;
    public bool is_modified = false;
    private uint cursor_timeout_id = 0;

    public ViewerController (Adw.ApplicationWindow win, ImageCanvas canvas, EditorManager editor, Gtk.Button save_button, Gtk.ToggleButton edit_toggle_button) {
        Object (
            win: win,
            canvas: canvas,
            editor: editor,
            save_button: save_button,
            edit_toggle_button: edit_toggle_button
        );

        image_files = {};

        editor.state_changed.connect (() => {
            mark_modified ();
        });
    }

    public void mark_modified () {
        is_modified = true;
        save_button.visible = true;
    }

    public void rotate_image (bool clockwise) {
        if (canvas == null || canvas.base_pixbuf == null || image_files.length == 0) return;

        editor.push_undo_snapshot ();

        var rot = clockwise ? Gdk.PixbufRotation.CLOCKWISE : Gdk.PixbufRotation.COUNTERCLOCKWISE;
        var composed = canvas.get_composed_pixbuf ();
        if (composed != null) {
            canvas.base_pixbuf = composed.rotate_simple (rot);
            canvas.clear_shapes ();
            current_pixbuf = canvas.base_pixbuf;
            canvas.queue_draw ();
            mark_modified ();
        }
    }

    public void prompt_save_image () {
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

    public void show_save_as_dialog () {
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

    public void save_to_path (string dest_path) {
        if (canvas == null || canvas.base_pixbuf == null) return;
        var save_pb = canvas.get_composed_pixbuf ();
        if (save_pb == null) return;
        var lower = dest_path.down ();

        try {
            if (lower.has_suffix (".jpg") || lower.has_suffix (".jpeg")) {
                save_pb.save (dest_path, "jpeg", "quality", "95", null);
            } else if (lower.has_suffix (".webp")) {
                save_pb.save (dest_path, "webp", "quality", "95", null);
            } else if (lower.has_suffix (".png")) {
                save_pb.save (dest_path, "png", null);
            } else if (lower.has_suffix (".gif")) {
                save_pb.save (dest_path, "gif", null);
            } else {
                save_pb.save (dest_path + ".jpg", "jpeg", "quality", "95", null);
            }

            is_modified = false;
            save_button.visible = false;
            win.title = "vView - %s".printf (dest_path);
        } catch (Error e) {
            warning ("Error saving image '%s': %s", dest_path, e.message);
        }
    }

    public void toggle_fullscreen () {
        if (win.fullscreened) {
            win.unfullscreen ();
        } else {
            win.fullscreen ();
        }
    }

    public void show_cursor () {
        win.set_cursor (null);
    }

    public void hide_cursor () {
        win.set_cursor_from_name ("none");
    }

    public void cancel_cursor_timer () {
        if (cursor_timeout_id != 0) {
            Source.remove (cursor_timeout_id);
            cursor_timeout_id = 0;
        }
    }

    public void reset_cursor_inactivity_timer () {
        cancel_cursor_timer ();
        cursor_timeout_id = Timeout.add_seconds (2, () => {
            if (win.fullscreened) {
                hide_cursor ();
            }
            cursor_timeout_id = 0;
            return Source.REMOVE;
        });
    }

    public void load_images (string target_file) {
        var file = File.new_for_path (target_file);

        if (!file.query_exists ()) {
            image_files = {};
            current_pixbuf = null;
            canvas.base_pixbuf = null;
            canvas.clear_shapes ();
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
            canvas.base_pixbuf = null;
            canvas.clear_shapes ();
            win.title = "vView - No images";
            return;
        }

        list.sort (strcmp);
        string[] files = {};
        foreach (var item in list) {
            files += item;
        }
        image_files = files;

        current_index = 0;
        for (int i = 0; i < image_files.length; i++) {
            if (image_files[i] == initial_filename) {
                current_index = i;
                break;
            }
        }

        show_image (current_index);
    }

    public void show_image (int index) {
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
        editor.reset_history ();

        var path = image_files[current_index];
        try {
            current_pixbuf = new Gdk.Pixbuf.from_file (path);
            canvas.base_pixbuf = current_pixbuf;
            canvas.clear_shapes ();
            canvas.reset_zoom ();
        } catch (Error e) {
            warning ("Could not load image '%s': %s", path, e.message);
            current_pixbuf = null;
            canvas.base_pixbuf = null;
            canvas.clear_shapes ();
            canvas.reset_zoom ();
        }

        win.title = "vView - %s".printf (path);
    }

    public void show_shortcuts_dialog () {
        var dialog = new Adw.AlertDialog ("vView", "Keyboard Shortcuts & Controls");
        dialog.add_response ("close", "Close");
        dialog.set_default_response ("close");
        dialog.set_close_response ("close");

        var group = new Adw.PreferencesGroup ();

        add_shortcut_row (group, "Toggle Fullscreen", "F / Double Click");
        add_shortcut_row (group, "Exit Fullscreen", "Escape");
        add_shortcut_row (group, "Next Image", "→ / Space / Scroll Down");
        add_shortcut_row (group, "Previous Image", "← / Scroll Up");
        add_shortcut_row (group, "Zoom In / Out", "Ctrl + Wheel / Ctrl + [+/-]");
        add_shortcut_row (group, "Reset Zoom", "Ctrl + 0");
        add_shortcut_row (group, "Rotate Clockwise", "R");
        add_shortcut_row (group, "Rotate Counter-Clockwise", "L");
        add_shortcut_row (group, "Toggle Editing Toolbar", "E");
        add_shortcut_row (group, "Select & Move Elements", "M");
        add_shortcut_row (group, "Undo Drawing", "Ctrl + Z");
        add_shortcut_row (group, "Redo Drawing", "Ctrl + Y / Ctrl + Shift + Z");
        add_shortcut_row (group, "Save (Prompt)", "Ctrl + S");
        add_shortcut_row (group, "Save As…", "Ctrl + Shift + S");
        add_shortcut_row (group, "First / Last Image", "Home / End");
        add_shortcut_row (group, "Shortcuts & Info", "F1");
        add_shortcut_row (group, "Quit", "Ctrl + Q");

        var scrolled = new Gtk.ScrolledWindow ();
        scrolled.propagate_natural_height = true;
        scrolled.max_content_height = 500;
        scrolled.min_content_width = 720;
        scrolled.width_request = 720;
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
}
