public enum ToolType {
    NONE,
    ARROW,
    RECTANGLE,
    CIRCLE,
    REDACT,
    TEXT
}

public delegate void TextEnteredCallback (string text);

public class ImageCanvas : Gtk.DrawingArea {
    public Gdk.Pixbuf? pixbuf { get; set; default = null; }
    public ToolType current_tool { get; set; default = ToolType.NONE; }
    public Gdk.RGBA draw_color { get; set; }
    public double line_width { get; set; default = 4.0; }
    public string font_desc { get; set; default = "Sans Bold 20"; }

    private bool is_dragging = false;
    private double start_x = 0;
    private double start_y = 0;
    private double current_x = 0;
    private double current_y = 0;

    public signal void image_modified ();
    public signal void text_requested (double img_x, double img_y);

    public ImageCanvas () {
        set_draw_func (on_draw);

        var drag = new Gtk.GestureDrag ();
        drag.drag_begin.connect (on_drag_begin);
        drag.drag_update.connect (on_drag_update);
        drag.drag_end.connect (on_drag_end);
        add_controller (drag);

        Gdk.RGBA red = { 1.0f, 0.0f, 0.0f, 1.0f };
        draw_color = red;
    }

    public void get_image_bounds (int widget_w, int widget_h,
                                  out double offset_x, out double offset_y,
                                  out double drawn_w, out double drawn_h,
                                  out double scale) {
        if (pixbuf == null) {
            offset_x = 0; offset_y = 0; drawn_w = 0; drawn_h = 0; scale = 1.0;
            return;
        }
        int pw = pixbuf.width;
        int ph = pixbuf.height;
        scale = double.min ((double) widget_w / pw, (double) widget_h / ph);
        drawn_w = pw * scale;
        drawn_h = ph * scale;
        offset_x = (widget_w - drawn_w) / 2.0;
        offset_y = (widget_h - drawn_h) / 2.0;
    }

    public void widget_to_image (double wx, double wy, out double ix, out double iy) {
        double ox, oy, dw, dh, scale;
        get_image_bounds (get_width (), get_height (), out ox, out oy, out dw, out dh, out scale);
        ix = (wx - ox) / scale;
        iy = (wy - oy) / scale;
        if (pixbuf != null) {
            ix = ix.clamp (0.0, (double) pixbuf.width);
            iy = iy.clamp (0.0, (double) pixbuf.height);
        }
    }

    private void on_drag_begin (double x, double y) {
        if (pixbuf == null || current_tool == ToolType.NONE) return;
        if (current_tool == ToolType.TEXT) {
            double ix, iy;
            widget_to_image (x, y, out ix, out iy);
            text_requested (ix, iy);
            return;
        }

        is_dragging = true;
        start_x = x;
        start_y = y;
        current_x = x;
        current_y = y;
        queue_draw ();
    }

    private void on_drag_update (double offset_x, double offset_y) {
        if (!is_dragging) return;
        current_x = start_x + offset_x;
        current_y = start_y + offset_y;
        queue_draw ();
    }

    private void on_drag_end (double offset_x, double offset_y) {
        if (!is_dragging) return;
        is_dragging = false;
        current_x = start_x + offset_x;
        current_y = start_y + offset_y;

        commit_current_shape ();
        queue_draw ();
    }

    private void commit_current_shape () {
        if (pixbuf == null) return;
        double x1, y1, x2, y2;
        widget_to_image (start_x, start_y, out x1, out y1);
        widget_to_image (current_x, current_y, out x2, out y2);

        if (current_tool == ToolType.REDACT) {
            int rx = (int) double.min (x1, x2);
            int ry = (int) double.min (y1, y2);
            int rw = (int) (x1 - x2).abs ();
            int rh = (int) (y1 - y2).abs ();
            if (rw > 1 && rh > 1) {
                apply_redact (rx, ry, rw, rh);
                image_modified ();
            }
            return;
        }

        var surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, pixbuf.width, pixbuf.height);
        var cr = new Cairo.Context (surface);
        Gdk.cairo_set_source_pixbuf (cr, pixbuf, 0, 0);
        cr.paint ();

        cr.set_source_rgba (draw_color.red, draw_color.green, draw_color.blue, draw_color.alpha);
        cr.set_line_width (line_width);

        if (current_tool == ToolType.ARROW) {
            draw_arrow_cairo (cr, x1, y1, x2, y2, line_width);
        } else if (current_tool == ToolType.RECTANGLE) {
            double rx = double.min (x1, x2);
            double ry = double.min (y1, y2);
            double rw = (x1 - x2).abs ();
            double rh = (y1 - y2).abs ();
            cr.rectangle (rx, ry, rw, rh);
            cr.stroke ();
        } else if (current_tool == ToolType.CIRCLE) {
            double rx = double.min (x1, x2);
            double ry = double.min (y1, y2);
            double rw = (x1 - x2).abs ();
            double rh = (y1 - y2).abs ();
            cr.save ();
            cr.translate (rx + rw / 2.0, ry + rh / 2.0);
            cr.scale (rw / 2.0, rh / 2.0);
            cr.arc (0.0, 0.0, 1.0, 0.0, 2.0 * Math.PI);
            cr.restore ();
            cr.stroke ();
        }

        var new_pb = Gdk.pixbuf_get_from_surface (surface, 0, 0, pixbuf.width, pixbuf.height);
        if (new_pb != null) {
            pixbuf = new_pb;
            image_modified ();
        }
    }

    public void add_text_at (string text, double ix, double iy) {
        if (pixbuf == null) return;
        var surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, pixbuf.width, pixbuf.height);
        var cr = new Cairo.Context (surface);
        Gdk.cairo_set_source_pixbuf (cr, pixbuf, 0, 0);
        cr.paint ();

        cr.set_source_rgba (draw_color.red, draw_color.green, draw_color.blue, draw_color.alpha);
        var layout = Pango.cairo_create_layout (cr);
        var desc = Pango.FontDescription.from_string (font_desc);
        layout.set_font_description (desc);
        layout.set_text (text, -1);

        cr.move_to (ix, iy);
        Pango.cairo_show_layout (cr, layout);

        var new_pb = Gdk.pixbuf_get_from_surface (surface, 0, 0, pixbuf.width, pixbuf.height);
        if (new_pb != null) {
            pixbuf = new_pb;
            image_modified ();
            queue_draw ();
        }
    }

    private void apply_redact (int rx, int ry, int rw, int rh) {
        int w = pixbuf.get_width ();
        int h = pixbuf.get_height ();
        int n_channels = pixbuf.get_n_channels ();
        int rowstride = pixbuf.get_rowstride ();
        unowned uint8[] pixels = pixbuf.get_pixels_with_length ();

        int x1 = int.max (0, rx);
        int y1 = int.max (0, ry);
        int x2 = int.min (w, rx + rw);
        int y2 = int.min (h, ry + rh);
        int block_size = 12;

        for (int by = y1; by < y2; by += block_size) {
            for (int bx = x1; bx < x2; bx += block_size) {
                int bw = int.min (block_size, x2 - bx);
                int bh = int.min (block_size, y2 - by);
                int count = bw * bh;
                if (count == 0) continue;

                long sum_r = 0, sum_g = 0, sum_b = 0;
                for (int cy = 0; cy < bh; cy++) {
                    int row = (by + cy) * rowstride;
                    for (int cx = 0; cx < bw; cx++) {
                        int idx = row + (bx + cx) * n_channels;
                        sum_r += pixels[idx];
                        sum_g += pixels[idx + 1];
                        sum_b += pixels[idx + 2];
                    }
                }

                uint8 avg_r = (uint8) (sum_r / count);
                uint8 avg_g = (uint8) (sum_g / count);
                uint8 avg_b = (uint8) (sum_b / count);

                for (int cy = 0; cy < bh; cy++) {
                    int row = (by + cy) * rowstride;
                    for (int cx = 0; cx < bw; cx++) {
                        int idx = row + (bx + cx) * n_channels;
                        pixels[idx] = avg_r;
                        pixels[idx + 1] = avg_g;
                        pixels[idx + 2] = avg_b;
                    }
                }
            }
        }
    }

    private void draw_arrow_cairo (Cairo.Context cr, double x1, double y1, double x2, double y2, double lw) {
        double angle = Math.atan2 (y2 - y1, x2 - x1);
        double arrow_len = double.max (15.0, lw * 3.5);
        double arrow_angle = Math.PI / 6.0;

        cr.set_line_width (lw);
        cr.set_line_cap (Cairo.LineCap.ROUND);
        cr.set_line_join (Cairo.LineJoin.ROUND);

        cr.move_to (x1, y1);
        cr.line_to (x2, y2);
        cr.stroke ();

        cr.move_to (x2, y2);
        cr.line_to (x2 - arrow_len * Math.cos (angle - arrow_angle),
                    y2 - arrow_len * Math.sin (angle - arrow_angle));
        cr.line_to (x2 - (arrow_len * 0.75) * Math.cos (angle),
                    y2 - (arrow_len * 0.75) * Math.sin (angle));
        cr.line_to (x2 - arrow_len * Math.cos (angle + arrow_angle),
                    y2 - arrow_len * Math.sin (angle + arrow_angle));
        cr.close_path ();
        cr.fill ();
    }

    private void on_draw (Gtk.DrawingArea area, Cairo.Context cr, int width, int height) {
        if (pixbuf == null) return;

        double ox, oy, dw, dh, scale;
        get_image_bounds (width, height, out ox, out oy, out dw, out dh, out scale);

        cr.save ();
        cr.translate (ox, oy);
        cr.scale (scale, scale);
        Gdk.cairo_set_source_pixbuf (cr, pixbuf, 0, 0);
        cr.paint ();
        cr.restore ();

        if (is_dragging && current_tool != ToolType.NONE) {
            cr.save ();
            if (current_tool == ToolType.REDACT) {
                double rx = double.min (start_x, current_x);
                double ry = double.min (start_y, current_y);
                double rw = (start_x - current_x).abs ();
                double rh = (start_y - current_y).abs ();

                cr.set_source_rgba (0.2, 0.4, 0.8, 0.3);
                cr.rectangle (rx, ry, rw, rh);
                cr.fill ();

                cr.set_source_rgba (0.2, 0.5, 1.0, 0.9);
                cr.set_line_width (1.5);
                double[] dashes = { 4.0, 4.0 };
                cr.set_dash (dashes, 0.0);
                cr.rectangle (rx, ry, rw, rh);
                cr.stroke ();
            } else {
                cr.set_source_rgba (draw_color.red, draw_color.green, draw_color.blue, draw_color.alpha);
                double scaled_lw = line_width * scale;

                if (current_tool == ToolType.ARROW) {
                    draw_arrow_cairo (cr, start_x, start_y, current_x, current_y, scaled_lw);
                } else if (current_tool == ToolType.RECTANGLE) {
                    cr.set_line_width (scaled_lw);
                    double rx = double.min (start_x, current_x);
                    double ry = double.min (start_y, current_y);
                    double rw = (start_x - current_x).abs ();
                    double rh = (start_y - current_y).abs ();
                    cr.rectangle (rx, ry, rw, rh);
                    cr.stroke ();
                } else if (current_tool == ToolType.CIRCLE) {
                    cr.set_line_width (scaled_lw);
                    double rx = double.min (start_x, current_x);
                    double ry = double.min (start_y, current_y);
                    double rw = (start_x - current_x).abs ();
                    double rh = (start_y - current_y).abs ();
                    cr.save ();
                    cr.translate (rx + rw / 2.0, ry + rh / 2.0);
                    cr.scale (rw / 2.0, rh / 2.0);
                    cr.arc (0.0, 0.0, 1.0, 0.0, 2.0 * Math.PI);
                    cr.restore ();
                    cr.stroke ();
                }
            }
            cr.restore ();
        }
    }
}

public class VViewApp : Adw.Application {
    private Adw.ApplicationWindow? win = null;
    private ImageCanvas canvas;
    private Adw.HeaderBar header;
    private Gtk.Revealer edit_revealer;
    private Gtk.ToggleButton edit_toggle_button;
    private Gtk.Button save_button;
    private Gtk.Button undo_button;
    private Gtk.Button redo_button;

    // Tool toggle buttons
    private Gtk.ToggleButton arrow_btn;
    private Gtk.ToggleButton rect_btn;
    private Gtk.ToggleButton circle_btn;
    private Gtk.ToggleButton redact_btn;
    private Gtk.ToggleButton text_btn;

    // Pickers
    private Gtk.ColorDialogButton color_btn;
    private Gtk.FontDialogButton font_btn;
    private Gtk.SpinButton width_spin;

    // Undo / Redo history
    private GLib.List<Gdk.Pixbuf> undo_stack;
    private GLib.List<Gdk.Pixbuf> redo_stack;
    private const uint MAX_HISTORY = 30;

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
        undo_stack = new GLib.List<Gdk.Pixbuf> ();
        redo_stack = new GLib.List<Gdk.Pixbuf> ();
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

        // Edit mode toggle button
        edit_toggle_button = new Gtk.ToggleButton ();
        edit_toggle_button.icon_name = "document-edit-symbolic";
        edit_toggle_button.tooltip_text = "Toggle Annotation & Drawing Tools (E)";
        edit_toggle_button.toggled.connect (toggle_edit_mode);
        header.pack_start (edit_toggle_button);

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

        // Save button (hidden until image is modified)
        save_button = new Gtk.Button.with_label ("Save");
        save_button.icon_name = "document-save-symbolic";
        save_button.add_css_class ("suggested-action");
        save_button.tooltip_text = "Save changes (Ctrl+S)";
        save_button.visible = false;
        save_button.clicked.connect (prompt_save_image);
        header.pack_end (save_button);

        // Build Edit Toolbar
        var edit_bar = create_edit_toolbar ();
        edit_revealer = new Gtk.Revealer ();
        edit_revealer.transition_type = Gtk.RevealerTransitionType.SLIDE_DOWN;
        edit_revealer.set_child (edit_bar);
        edit_revealer.reveal_child = false;

        // Track fullscreen state changes
        win.notify["fullscreened"].connect (() => {
            header.visible = !win.fullscreened;
            if (win.fullscreened) {
                edit_revealer.reveal_child = false;
                reset_cursor_inactivity_timer ();
            } else {
                if (edit_toggle_button.active) {
                    edit_revealer.reveal_child = true;
                }
                show_cursor ();
                cancel_cursor_timer ();
            }
        });

        var toolbar_view = new Adw.ToolbarView ();
        toolbar_view.add_top_bar (header);
        toolbar_view.add_top_bar (edit_revealer);

        // Canvas widget for image display and drawing
        canvas = new ImageCanvas ();
        canvas.hexpand = true;
        canvas.vexpand = true;

        canvas.image_modified.connect (() => {
            if (current_pixbuf != null) {
                push_undo_snapshot (current_pixbuf);
            }
            current_pixbuf = canvas.pixbuf;
            mark_modified ();
        });

        canvas.text_requested.connect ((ix, iy) => {
            prompt_text_dialog (ix, iy);
        });

        toolbar_view.set_content (canvas);
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

            if (!edit_toggle_button.active && image_files.length > 1) {
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
                undo ();
                return true;
            }

            // Redo on Ctrl+Y or Ctrl+Shift+Z
            if ((state & Gdk.ModifierType.CONTROL_MASK) != 0 &&
                (latin_lower == Gdk.Key.y || key_lower == Gdk.Key.Cyrillic_en ||
                 ((state & Gdk.ModifierType.SHIFT_MASK) != 0 && (latin_lower == Gdk.Key.z || key_lower == Gdk.Key.Cyrillic_ya)))) {
                redo ();
                return true;
            }

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

            // Toggle edit mode with 'E'
            if (latin_lower == Gdk.Key.e || key_lower == Gdk.Key.Cyrillic_u) {
                edit_toggle_button.active = !edit_toggle_button.active;
                return true;
            }

            // Check primary action keys
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
                    if (edit_toggle_button.active) {
                        edit_toggle_button.active = false;
                        return true;
                    }
                    break;

                case Gdk.Key.Left:
                case Gdk.Key.Page_Up:
                    if (!edit_toggle_button.active) {
                        show_image (current_index - 1);
                        return true;
                    }
                    break;

                case Gdk.Key.Right:
                case Gdk.Key.Page_Down:
                case Gdk.Key.space:
                    if (!edit_toggle_button.active) {
                        show_image (current_index + 1);
                        return true;
                    }
                    break;

                case Gdk.Key.Home:
                    if (!edit_toggle_button.active) {
                        show_image (0);
                        return true;
                    }
                    break;

                case Gdk.Key.End:
                    if (!edit_toggle_button.active) {
                        show_image (image_files.length - 1);
                        return true;
                    }
                    break;
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

    private Gtk.Widget create_edit_toolbar () {
        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
        box.margin_top = 4;
        box.margin_bottom = 6;
        box.margin_start = 12;
        box.margin_end = 12;

        // Undo & Redo buttons
        undo_button = new Gtk.Button.from_icon_name ("edit-undo-symbolic");
        undo_button.tooltip_text = "Undo last action (Ctrl+Z)";
        undo_button.sensitive = false;
        undo_button.clicked.connect (undo);
        box.append (undo_button);

        redo_button = new Gtk.Button.from_icon_name ("edit-redo-symbolic");
        redo_button.tooltip_text = "Redo action (Ctrl+Y)";
        redo_button.sensitive = false;
        redo_button.clicked.connect (redo);
        box.append (redo_button);

        box.append (new Gtk.Separator (Gtk.Orientation.VERTICAL));

        // Drawing tool group
        arrow_btn = new Gtk.ToggleButton ();
        arrow_btn.icon_name = "call-start-symbolic";
        arrow_btn.tooltip_text = "Draw Arrow";
        arrow_btn.toggled.connect (() => on_tool_toggled (arrow_btn, ToolType.ARROW));
        box.append (arrow_btn);

        rect_btn = new Gtk.ToggleButton ();
        rect_btn.icon_name = "checkbox-symbolic";
        rect_btn.tooltip_text = "Draw Rectangle";
        rect_btn.toggled.connect (() => on_tool_toggled (rect_btn, ToolType.RECTANGLE));
        box.append (rect_btn);

        circle_btn = new Gtk.ToggleButton ();
        circle_btn.icon_name = "media-record-symbolic";
        circle_btn.tooltip_text = "Draw Circle";
        circle_btn.toggled.connect (() => on_tool_toggled (circle_btn, ToolType.CIRCLE));
        box.append (circle_btn);

        redact_btn = new Gtk.ToggleButton ();
        redact_btn.icon_name = "view-conceal-symbolic";
        redact_btn.tooltip_text = "Redact / Censor Zone (Pixelate mosaic)";
        redact_btn.toggled.connect (() => on_tool_toggled (redact_btn, ToolType.REDACT));
        box.append (redact_btn);

        text_btn = new Gtk.ToggleButton ();
        text_btn.icon_name = "insert-text-symbolic";
        text_btn.tooltip_text = "Add Text";
        text_btn.toggled.connect (() => on_tool_toggled (text_btn, ToolType.TEXT));
        box.append (text_btn);

        box.append (new Gtk.Separator (Gtk.Orientation.VERTICAL));

        // Color Picker
        var color_dialog = new Gtk.ColorDialog ();
        color_dialog.with_alpha = false;
        color_btn = new Gtk.ColorDialogButton (color_dialog);
        Gdk.RGBA red = { 1.0f, 0.0f, 0.0f, 1.0f };
        color_btn.set_rgba (red);
        color_btn.tooltip_text = "Choose Stroke & Text Color";
        color_btn.notify["rgba"].connect (() => {
            unowned Gdk.RGBA? c = color_btn.get_rgba ();
            if (c != null) {
                canvas.draw_color = c;
            }
        });
        box.append (color_btn);

        // Line width SpinButton
        var width_label = new Gtk.Label ("Width:");
        box.append (width_label);

        width_spin = new Gtk.SpinButton.with_range (1, 50, 1);
        width_spin.value = 4;
        width_spin.tooltip_text = "Line / Border Width (px)";
        width_spin.value_changed.connect (() => {
            canvas.line_width = width_spin.value;
        });
        box.append (width_spin);

        box.append (new Gtk.Separator (Gtk.Orientation.VERTICAL));

        // Font Picker
        var font_dialog = new Gtk.FontDialog ();
        font_btn = new Gtk.FontDialogButton (font_dialog);
        font_btn.font_desc = Pango.FontDescription.from_string ("Sans Bold 20");
        font_btn.tooltip_text = "Choose Font Family & Size";
        font_btn.notify["font-desc"].connect (() => {
            if (font_btn.font_desc != null) {
                canvas.font_desc = font_btn.font_desc.to_string ();
            }
        });
        box.append (font_btn);

        // Default tool: Arrow
        arrow_btn.active = true;

        return box;
    }

    private void on_tool_toggled (Gtk.ToggleButton active_btn, ToolType tool) {
        if (!active_btn.active) {
            if (canvas.current_tool == tool) {
                canvas.current_tool = ToolType.NONE;
            }
            return;
        }

        if (active_btn != arrow_btn && arrow_btn.active) arrow_btn.active = false;
        if (active_btn != rect_btn && rect_btn.active) rect_btn.active = false;
        if (active_btn != circle_btn && circle_btn.active) circle_btn.active = false;
        if (active_btn != redact_btn && redact_btn.active) redact_btn.active = false;
        if (active_btn != text_btn && text_btn.active) text_btn.active = false;

        canvas.current_tool = tool;
    }

    private void toggle_edit_mode () {
        bool active = edit_toggle_button.active;
        edit_revealer.reveal_child = active;
        if (!active) {
            canvas.current_tool = ToolType.NONE;
        } else {
            if (arrow_btn.active) canvas.current_tool = ToolType.ARROW;
            else if (rect_btn.active) canvas.current_tool = ToolType.RECTANGLE;
            else if (circle_btn.active) canvas.current_tool = ToolType.CIRCLE;
            else if (redact_btn.active) canvas.current_tool = ToolType.REDACT;
            else if (text_btn.active) canvas.current_tool = ToolType.TEXT;
            else {
                arrow_btn.active = true;
                canvas.current_tool = ToolType.ARROW;
            }
        }
    }

    private void prompt_text_dialog (double ix, double iy) {
        var dialog = new Adw.AlertDialog ("Insert Text", "Enter text to add to the image:");
        var entry = new Gtk.Entry ();
        entry.placeholder_text = "Type text here…";
        dialog.set_extra_child (entry);
        dialog.add_response ("cancel", "Cancel");
        dialog.add_response ("add", "Add Text");
        dialog.set_response_appearance ("add", Adw.ResponseAppearance.SUGGESTED);
        dialog.set_default_response ("add");
        dialog.set_close_response ("cancel");

        dialog.choose.begin (win, null, (obj, res) => {
            var resp = dialog.choose.end (res);
            if (resp == "add" && entry.text.strip () != "") {
                if (current_pixbuf != null) {
                    push_undo_snapshot (current_pixbuf);
                }
                canvas.add_text_at (entry.text, ix, iy);
                current_pixbuf = canvas.pixbuf;
                mark_modified ();
            }
        });
    }

    private void push_undo_snapshot (Gdk.Pixbuf pb) {
        undo_stack.append (pb.copy ());
        if (undo_stack.length () > MAX_HISTORY) {
            undo_stack.delete_link (undo_stack.first ());
        }
        redo_stack = new GLib.List<Gdk.Pixbuf> ();
        update_undo_redo_sensitivity ();
    }

    private void undo () {
        if (undo_stack == null || undo_stack.length () == 0) return;

        unowned GLib.List<Gdk.Pixbuf> last_link = undo_stack.last ();
        var prev_pb = last_link.data;
        undo_stack.delete_link (last_link);

        if (current_pixbuf != null) {
            redo_stack.append (current_pixbuf.copy ());
        }

        current_pixbuf = prev_pb;
        canvas.pixbuf = current_pixbuf;
        canvas.queue_draw ();

        mark_modified ();
        update_undo_redo_sensitivity ();
    }

    private void redo () {
        if (redo_stack == null || redo_stack.length () == 0) return;

        unowned GLib.List<Gdk.Pixbuf> last_link = redo_stack.last ();
        var next_pb = last_link.data;
        redo_stack.delete_link (last_link);

        if (current_pixbuf != null) {
            undo_stack.append (current_pixbuf.copy ());
        }

        current_pixbuf = next_pb;
        canvas.pixbuf = current_pixbuf;
        canvas.queue_draw ();

        mark_modified ();
        update_undo_redo_sensitivity ();
    }

    private void update_undo_redo_sensitivity () {
        if (undo_button != null) {
            undo_button.sensitive = (undo_stack != null && undo_stack.length () > 0);
        }
        if (redo_button != null) {
            redo_button.sensitive = (redo_stack != null && redo_stack.length () > 0);
        }
    }

    private void mark_modified () {
        is_modified = true;
        save_button.visible = true;
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
        add_shortcut_row (group, "Toggle Editing Toolbar", "E");
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

    private void rotate_image (bool clockwise) {
        if (current_pixbuf == null || image_files.length == 0) return;

        push_undo_snapshot (current_pixbuf);

        var rot = clockwise ? Gdk.PixbufRotation.CLOCKWISE : Gdk.PixbufRotation.COUNTERCLOCKWISE;
        current_pixbuf = current_pixbuf.rotate_simple (rot);
        canvas.pixbuf = current_pixbuf;
        canvas.queue_draw ();

        mark_modified ();
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
            canvas.pixbuf = null;
            canvas.queue_draw ();
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
            canvas.pixbuf = null;
            canvas.queue_draw ();
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
        undo_stack = new GLib.List<Gdk.Pixbuf> ();
        redo_stack = new GLib.List<Gdk.Pixbuf> ();
        update_undo_redo_sensitivity ();

        var path = image_files[current_index];
        try {
            current_pixbuf = new Gdk.Pixbuf.from_file (path);
            canvas.pixbuf = current_pixbuf;
            canvas.queue_draw ();
        } catch (Error e) {
            warning ("Could not load image '%s': %s", path, e.message);
            current_pixbuf = null;
            canvas.pixbuf = null;
            canvas.queue_draw ();
        }

        win.title = "vView - %s".printf (path);
    }

    public static int main (string[] args) {
        var app = new VViewApp ();
        return app.run (args);
    }
}
