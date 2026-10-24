public class VViewApp : Adw.Application {
    private Adw.ApplicationWindow? win = null;
    private Gtk.Picture picture;
    private Adw.HeaderBar header;
    private string[] image_files;
    private int current_index = 0;
    private uint cursor_timeout_id = 0;
    private string target_path = "/home/ijin/Yandex.Disk/images/1920x1080/RDR2/PRDR31796521339_1.jpg";

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
        }

        if (win == null) {
            activate ();
        } else {
            load_images (target_path);
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

        // Keyboard navigation (Ctrl+Q, F, Escape, Left, Right, etc.)
        var key_controller = new Gtk.EventControllerKey ();
        key_controller.key_pressed.connect ((keyval, keycode, state) => {
            // Exit on Ctrl+Q
            if ((state & Gdk.ModifierType.CONTROL_MASK) != 0 &&
                (keyval == Gdk.Key.q || keyval == Gdk.Key.Q)) {
                quit ();
                return true;
            }

            switch (keyval) {
                case Gdk.Key.f:
                case Gdk.Key.F:
                    toggle_fullscreen ();
                    return true;

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

        // Load images from directory
        load_images (target_path);

        win.present ();
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
            picture.set_filename (null);
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

        var path = image_files[current_index];
        picture.set_filename (path);

        win.title = "vView - %s".printf (path);
    }

    public static int main (string[] args) {
        var app = new VViewApp ();
        return app.run (args);
    }
}
