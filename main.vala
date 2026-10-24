public class VViewApp : Adw.Application {
    private Adw.ApplicationWindow? win = null;
    private ConfigManager config_manager;
    private ImageCanvas canvas;
    private EditorManager editor;
    private ViewerController viewer;

    private Adw.HeaderBar header;
    private Gtk.Revealer edit_revealer;
    private Gtk.ToggleButton edit_toggle_button;
    private Gtk.Button save_button;
    private Gtk.Button zoom_label_btn;
    private PropertiesView properties_view;
    private Gtk.Revealer prop_revealer;
    private Gtk.ToggleButton properties_button;

    private string? target_path = null;
    private bool is_loading_settings = true;

    public VViewApp () {
        Object (
            application_id: "com.example.vView",
            flags: ApplicationFlags.HANDLES_COMMAND_LINE
        );
        config_manager = new ConfigManager ();
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
                viewer.load_images (target_path);
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

        config_manager.load ();

        Gtk.Window.set_default_icon_name ("vView");

        win = new Adw.ApplicationWindow (this);
        win.set_default_size (1000, 700);
        win.set_icon_name ("vView");
        win.close_request.connect (() => {
            save_window_settings ();
            win = null;
            return false;
        });

        header = new Adw.HeaderBar ();

        // Canvas widget for image display and drawing
        canvas = new ImageCanvas ();
        canvas.hexpand = true;
        canvas.vexpand = true;

        editor = new EditorManager (canvas, config_manager);
        editor.parent_window = win;

        // Save button (hidden until image is modified)
        save_button = new Gtk.Button.with_label ("Save");
        save_button.icon_name = "document-save-symbolic";
        save_button.add_css_class ("suggested-action");
        save_button.tooltip_text = "Save changes (Ctrl+S)";
        save_button.visible = false;

        // Edit mode toggle button
        edit_toggle_button = new Gtk.ToggleButton ();
        edit_toggle_button.icon_name = "document-edit-symbolic";
        edit_toggle_button.tooltip_text = "Toggle Annotation & Drawing Tools (E)";
        edit_toggle_button.toggled.connect (toggle_edit_mode);

        viewer = new ViewerController (win, canvas, editor, save_button, edit_toggle_button);
        save_button.clicked.connect (viewer.prompt_save_image);

        // Previous / Next buttons in HeaderBar
        var prev_button = new Gtk.Button.from_icon_name ("go-previous-symbolic");
        prev_button.tooltip_text = "Previous image (Left arrow / Scroll up)";
        prev_button.clicked.connect (() => {
            viewer.show_image (viewer.current_index - 1);
        });
        header.pack_start (prev_button);

        var next_button = new Gtk.Button.from_icon_name ("go-next-symbolic");
        next_button.tooltip_text = "Next image (Right arrow / Scroll down)";
        next_button.clicked.connect (() => {
            viewer.show_image (viewer.current_index + 1);
        });
        header.pack_start (next_button);

        header.pack_start (edit_toggle_button);

        // Zoom controls group in HeaderBar (visible in normal windowed mode)
        var zoom_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        zoom_box.add_css_class ("linked");
        zoom_box.margin_start = 6;

        var zoom_out_btn = new Gtk.Button.from_icon_name ("zoom-out-symbolic");
        zoom_out_btn.tooltip_text = "Zoom out (Ctrl + Wheel Down / Ctrl + -)";
        zoom_out_btn.clicked.connect (() => {
            int ww = canvas.get_width ();
            int wh = canvas.get_height ();
            canvas.zoom_at (ww / 2.0, wh / 2.0, 1.0 / 1.15);
        });
        zoom_box.append (zoom_out_btn);

        zoom_label_btn = new Gtk.Button.with_label ("100%");
        zoom_label_btn.tooltip_text = "View at 100% actual size (Ctrl + 0)";
        zoom_label_btn.clicked.connect (() => {
            canvas.toggle_zoom_100_or_fit ();
        });
        zoom_box.append (zoom_label_btn);

        var zoom_in_btn = new Gtk.Button.from_icon_name ("zoom-in-symbolic");
        zoom_in_btn.tooltip_text = "Zoom in (Ctrl + Wheel Up / Ctrl + +)";
        zoom_in_btn.clicked.connect (() => {
            int ww = canvas.get_width ();
            int wh = canvas.get_height ();
            canvas.zoom_at (ww / 2.0, wh / 2.0, 1.15);
        });
        zoom_box.append (zoom_in_btn);

        header.pack_start (zoom_box);

        canvas.zoom_changed.connect (update_zoom_label);

        // Fullscreen toggle button in HeaderBar
        var fs_button = new Gtk.Button.from_icon_name ("view-fullscreen-symbolic");
        fs_button.tooltip_text = "Fullscreen mode (F / Double click)";
        fs_button.clicked.connect (viewer.toggle_fullscreen);
        header.pack_end (fs_button);

        // Info / Shortcuts button
        var info_button = new Gtk.Button.from_icon_name ("help-browser-symbolic");
        info_button.tooltip_text = "Keyboard Shortcuts & Info (F1)";
        info_button.clicked.connect (viewer.show_shortcuts_dialog);
        header.pack_end (info_button);

        // Properties View & Revealer
        properties_view = new PropertiesView ();
        viewer.properties_view = properties_view;

        prop_revealer = new Gtk.Revealer ();
        prop_revealer.transition_type = Gtk.RevealerTransitionType.SLIDE_LEFT;
        prop_revealer.set_child (properties_view);
        prop_revealer.reveal_child = false;
        prop_revealer.hexpand = false;
        prop_revealer.vexpand = true;

        properties_button = new Gtk.ToggleButton ();
        properties_button.icon_name = "info-outline-symbolic";
        properties_button.tooltip_text = "Image Properties (Alt+Enter / Ctrl+I)";
        properties_button.toggled.connect (() => {
            prop_revealer.reveal_child = properties_button.active;
        });

        properties_view.close_requested.connect (() => {
            properties_button.active = false;
        });

        header.pack_end (properties_button);

        // Rotate clockwise button
        var rotate_cw_button = new Gtk.Button.from_icon_name ("object-rotate-right-symbolic");
        rotate_cw_button.tooltip_text = "Rotate clockwise (R)";
        rotate_cw_button.clicked.connect (() => viewer.rotate_image (true));
        header.pack_end (rotate_cw_button);

        // Rotate counter-clockwise button
        var rotate_ccw_button = new Gtk.Button.from_icon_name ("object-rotate-left-symbolic");
        rotate_ccw_button.tooltip_text = "Rotate counter-clockwise (L)";
        rotate_ccw_button.clicked.connect (() => viewer.rotate_image (false));
        header.pack_end (rotate_ccw_button);

        header.pack_end (save_button);

        // Build Edit Toolbar
        var edit_bar = editor.create_edit_toolbar ();
        edit_revealer = new Gtk.Revealer ();
        edit_revealer.transition_type = Gtk.RevealerTransitionType.SLIDE_DOWN;
        edit_revealer.set_child (edit_bar);
        edit_revealer.reveal_child = false;

        // Track fullscreen state changes
        win.notify["fullscreened"].connect (() => {
            header.visible = !win.fullscreened;
            if (win.fullscreened) {
                edit_revealer.reveal_child = false;
                prop_revealer.reveal_child = false;
                viewer.reset_cursor_inactivity_timer ();
            } else {
                if (edit_toggle_button.active) {
                    edit_revealer.reveal_child = true;
                }
                if (properties_button.active) {
                    prop_revealer.reveal_child = true;
                }
                viewer.show_cursor ();
                viewer.cancel_cursor_timer ();
            }
        });

        var main_hbox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        main_hbox.hexpand = true;
        main_hbox.vexpand = true;
        main_hbox.append (canvas);
        main_hbox.append (prop_revealer);

        var toolbar_view = new Adw.ToolbarView ();
        toolbar_view.add_top_bar (header);
        toolbar_view.add_top_bar (edit_revealer);
        toolbar_view.set_content (main_hbox);
        win.set_content (toolbar_view);

        // Track mouse motion for cursor visibility, inactivity timer, and zoom focus
        double last_cursor_x = 0;
        double last_cursor_y = 0;
        var motion_controller = new Gtk.EventControllerMotion ();
        motion_controller.motion.connect ((x, y) => {
            last_cursor_x = x;
            last_cursor_y = y;
            if (win.fullscreened) {
                viewer.show_cursor ();
                viewer.reset_cursor_inactivity_timer ();
            }
        });
        ((Gtk.Widget) win).add_controller (motion_controller);

        // Double click to toggle fullscreen mode
        var click_gesture = new Gtk.GestureClick ();
        click_gesture.pressed.connect ((n_press, x, y) => {
            if (edit_toggle_button.active) return;
            if (n_press == 2) {
                viewer.toggle_fullscreen ();
            }
        });
        ((Gtk.Widget) win).add_controller (click_gesture);

        // Mouse scroll wheel:
        // - With Ctrl: zoom in (up) / zoom out (down) between 5% and 250%
        // - Without Ctrl: next / previous image
        var scroll_controller = new Gtk.EventControllerScroll (Gtk.EventControllerScrollFlags.VERTICAL);
        scroll_controller.scroll.connect ((dx, dy) => {
            if (win.fullscreened) {
                viewer.show_cursor ();
                viewer.reset_cursor_inactivity_timer ();
            }

            var current_mods = scroll_controller.get_current_event_state ();
            if ((current_mods & Gdk.ModifierType.CONTROL_MASK) != 0) {
                if (dy < 0) {
                    // Wheel up: zoom in by 1.15x
                    canvas.zoom_at (last_cursor_x, last_cursor_y, 1.15);
                    return true;
                } else if (dy > 0) {
                    // Wheel down: zoom out by 1 / 1.15
                    canvas.zoom_at (last_cursor_x, last_cursor_y, 1.0 / 1.15);
                    return true;
                }
                return false;
            }

            if (!edit_toggle_button.active && viewer.image_files.length > 1) {
                if (dy > 0) {
                    viewer.show_image (viewer.current_index + 1);
                    return true;
                } else if (dy < 0) {
                    viewer.show_image (viewer.current_index - 1);
                    return true;
                }
            }
            return false;
        });
        ((Gtk.Widget) win).add_controller (scroll_controller);

        // Keyboard navigation & shortcuts
        var key_controller = new Gtk.EventControllerKey ();
        key_controller.key_pressed.connect ((keyval, keycode, state) => {
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

            // Undo on Ctrl+Z
            if ((state & Gdk.ModifierType.CONTROL_MASK) != 0 &&
                (latin_lower == Gdk.Key.z || key_lower == Gdk.Key.Cyrillic_ya)) {
                editor.undo ();
                return true;
            }

            // Redo on Ctrl+Y or Ctrl+Shift+Z
            if ((state & Gdk.ModifierType.CONTROL_MASK) != 0 &&
                (latin_lower == Gdk.Key.y || key_lower == Gdk.Key.Cyrillic_en ||
                 ((state & Gdk.ModifierType.SHIFT_MASK) != 0 && (latin_lower == Gdk.Key.z || key_lower == Gdk.Key.Cyrillic_ya)))) {
                editor.redo ();
                return true;
            }

            // Exit on Ctrl+Q
            if ((state & Gdk.ModifierType.CONTROL_MASK) != 0 &&
                (latin_lower == Gdk.Key.q || key_lower == Gdk.Key.Cyrillic_shorti)) {
                save_window_settings ();
                win = null;
                quit ();
                return true;
            }

            // Save on Ctrl+S (prompt) or Ctrl+Shift+S (direct Save As)
            if ((state & Gdk.ModifierType.CONTROL_MASK) != 0 &&
                (latin_lower == Gdk.Key.s || key_lower == Gdk.Key.Cyrillic_yeru)) {
                if (viewer.is_modified) {
                    if ((state & Gdk.ModifierType.SHIFT_MASK) != 0) {
                        viewer.show_save_as_dialog ();
                    } else {
                        viewer.prompt_save_image ();
                    }
                    return true;
                }
            }

            // Zoom toggle 100% / Fit on Ctrl+0
            if ((state & Gdk.ModifierType.CONTROL_MASK) != 0 &&
                (keyval == Gdk.Key.@0 || keyval == Gdk.Key.KP_0)) {
                canvas.toggle_zoom_100_or_fit ();
                return true;
            }

            // Zoom in on Ctrl++ / Ctrl+= / Ctrl+KP_Add
            if ((state & Gdk.ModifierType.CONTROL_MASK) != 0 &&
                (keyval == Gdk.Key.plus || keyval == Gdk.Key.equal || keyval == Gdk.Key.KP_Add)) {
                int ww = canvas.get_width ();
                int wh = canvas.get_height ();
                canvas.zoom_at (ww / 2.0, wh / 2.0, 1.15);
                return true;
            }

            // Zoom out on Ctrl+- / Ctrl+KP_Subtract
            if ((state & Gdk.ModifierType.CONTROL_MASK) != 0 &&
                (keyval == Gdk.Key.minus || keyval == Gdk.Key.KP_Subtract)) {
                int ww = canvas.get_width ();
                int wh = canvas.get_height ();
                canvas.zoom_at (ww / 2.0, wh / 2.0, 1.0 / 1.15);
                return true;
            }

            // Toggle edit mode with 'E'
            if (latin_lower == Gdk.Key.e || key_lower == Gdk.Key.Cyrillic_u) {
                edit_toggle_button.active = !edit_toggle_button.active;
                return true;
            }

            // Select & Move tool shortcut 'M'
            if (latin_lower == Gdk.Key.m || key_lower == Gdk.Key.Cyrillic_softsign) {
                if (!edit_toggle_button.active) {
                    edit_toggle_button.active = true;
                }
                editor.move_btn.active = true;
                return true;
            }

            // Check primary action keys
            if (latin_lower == Gdk.Key.f || key_lower == Gdk.Key.Cyrillic_a) {
                viewer.toggle_fullscreen ();
                return true;
            }

            if (latin_lower == Gdk.Key.r || key_lower == Gdk.Key.Cyrillic_ka) {
                viewer.rotate_image (true);
                return true;
            }

            if (latin_lower == Gdk.Key.l || key_lower == Gdk.Key.Cyrillic_de) {
                viewer.rotate_image (false);
                return true;
            }

            if (latin_lower == Gdk.Key.F1 || keyval == Gdk.Key.F1 || keyval == Gdk.Key.question) {
                viewer.show_shortcuts_dialog ();
                return true;
            }

            // Toggle Image Properties on Alt+Enter / Alt+Return or Ctrl+I
            if (((state & Gdk.ModifierType.ALT_MASK) != 0 &&
                 (keyval == Gdk.Key.Return || keyval == Gdk.Key.KP_Enter)) ||
                ((state & Gdk.ModifierType.CONTROL_MASK) != 0 &&
                 (latin_lower == Gdk.Key.i || key_lower == Gdk.Key.Cyrillic_sha))) {
                properties_button.active = !properties_button.active;
                return true;
            }

            switch (keyval) {
                case Gdk.Key.Escape:
                    if (win.fullscreened) {
                        win.unfullscreen ();
                        return true;
                    }
                    if (properties_button.active) {
                        properties_button.active = false;
                        return true;
                    }
                    if (edit_toggle_button.active) {
                        edit_toggle_button.active = false;
                        return true;
                    }
                    break;

                case Gdk.Key.Delete:
                case Gdk.Key.KP_Delete:
                    if ((state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.ALT_MASK)) == 0) {
                        if (edit_toggle_button.active && canvas.selected_shape != null) {
                            canvas.remove_shape (canvas.selected_shape);
                        } else {
                            viewer.prompt_trash_image ();
                        }
                        return true;
                    }
                    break;

                case Gdk.Key.Left:
                case Gdk.Key.Page_Up:
                    if (!edit_toggle_button.active) {
                        viewer.show_image (viewer.current_index - 1);
                        return true;
                    }
                    break;

                case Gdk.Key.Right:
                case Gdk.Key.Page_Down:
                case Gdk.Key.space:
                    if (!edit_toggle_button.active) {
                        viewer.show_image (viewer.current_index + 1);
                        return true;
                    }
                    break;

                case Gdk.Key.Home:
                    if (!edit_toggle_button.active) {
                        viewer.show_image (0);
                        return true;
                    }
                    break;

                case Gdk.Key.End:
                    if (!edit_toggle_button.active) {
                        viewer.show_image (viewer.image_files.length - 1);
                        return true;
                    }
                    break;
            }
            return false;
        });
        ((Gtk.Widget) win).add_controller (key_controller);

        // Restore persistent settings
        apply_loaded_settings ();

        // Load images if target_path was provided
        if (target_path != null) {
            viewer.load_images (target_path);
        } else {
            win.title = "vView";
        }

        win.present ();
    }

    private void toggle_edit_mode () {
        bool active = edit_toggle_button.active;
        edit_revealer.reveal_child = active;
        if (canvas != null) {
            if (!active) {
                canvas.current_tool = ToolType.NONE;
            } else {
                editor.apply_active_tool_to_canvas ();
            }
        }

        if (!is_loading_settings) {
            config_manager.edit_mode = active;
            config_manager.save ();
        }
    }

    private void apply_loaded_settings () {
        is_loading_settings = true;

        if (config_manager.window_width >= 300 && config_manager.window_height >= 200) {
            win.set_default_size (config_manager.window_width, config_manager.window_height);
        }
        if (config_manager.window_maximized) {
            win.maximize ();
        }

        editor.select_tool_by_name (config_manager.active_tool);

        Gdk.RGBA c = {};
        if (c.parse (config_manager.draw_color)) {
            canvas.draw_color = c;
            editor.color_btn.set_rgba (c);
        }

        Gdk.RGBA tc = {};
        if (tc.parse (config_manager.text_color)) {
            canvas.text_color = tc;
        }

        Gdk.RGBA bg = {};
        if (bg.parse (config_manager.text_bg_color)) {
            canvas.text_bg_color = bg;
        }

        canvas.line_width = config_manager.line_width;
        editor.width_spin.value = config_manager.line_width;

        canvas.font_desc = config_manager.font_desc;

        edit_toggle_button.active = config_manager.edit_mode;
        edit_revealer.reveal_child = config_manager.edit_mode;
        if (config_manager.edit_mode) {
            editor.apply_active_tool_to_canvas ();
        } else {
            canvas.current_tool = ToolType.NONE;
        }

        config_manager.is_ready_to_save = true;
        is_loading_settings = false;
    }

    private void update_zoom_label () {
        if (zoom_label_btn != null && canvas != null) {
            double effective_scale = canvas.get_current_scale ();
            int pct = (int) Math.round (effective_scale * 100.0);
            if (pct < 1) pct = 1;
            zoom_label_btn.label = "%d%%".printf (pct);

            if (Math.fabs (effective_scale - 1.0) < 0.01) {
                zoom_label_btn.tooltip_text = "Fit image to window (Ctrl + 0)";
            } else {
                zoom_label_btn.tooltip_text = "View at 100% actual size (Ctrl + 0)";
            }
        }
    }

    private void save_window_settings () {
        if (is_loading_settings || win == null) return;

        if (!win.fullscreened) {
            int w = win.get_width ();
            int h = win.get_height ();
            if (w < 200 || h < 200) {
                w = win.default_width;
                h = win.default_height;
            }
            if (w >= 200 && h >= 200) {
                config_manager.window_width = w;
                config_manager.window_height = h;
            }
            config_manager.window_maximized = win.maximized;
        }
        if (edit_toggle_button != null) {
            config_manager.edit_mode = edit_toggle_button.active;
        }
        config_manager.save ();
    }

    protected override void shutdown () {
        if (win != null) {
            save_window_settings ();
        }
        base.shutdown ();
    }

    public static int main (string[] args) {
        var app = new VViewApp ();
        return app.run (args);
    }
}
