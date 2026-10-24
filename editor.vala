public enum ToolType {
    NONE,
    MOVE,
    LINE,
    ARROW,
    RECTANGLE,
    CIRCLE,
    REDACT,
    TEXT
}

public class AnnotationItem : GLib.Object {
    public ToolType tool_type;
    public double x1;
    public double y1;
    public double x2;
    public double y2;
    public Gdk.RGBA stroke_color;
    public Gdk.RGBA bg_color;
    public double line_width;
    public string text;
    public string font_desc;

    public AnnotationItem (ToolType t = ToolType.NONE) {
        this.tool_type = t;
        this.stroke_color = Gdk.RGBA () { red = 1.0f, green = 0.0f, blue = 0.0f, alpha = 1.0f };
        this.bg_color = Gdk.RGBA () { red = 0.0f, green = 0.0f, blue = 0.0f, alpha = 0.0f };
        this.line_width = 4.0;
        this.text = "";
        this.font_desc = "Sans Bold 20";
    }

    public AnnotationItem copy () {
        var c = new AnnotationItem (this.tool_type);
        c.x1 = this.x1;
        c.y1 = this.y1;
        c.x2 = this.x2;
        c.y2 = this.y2;
        c.stroke_color = this.stroke_color;
        c.bg_color = this.bg_color;
        c.line_width = this.line_width;
        c.text = this.text;
        c.font_desc = this.font_desc;
        return c;
    }

    public void translate (double dx, double dy) {
        x1 += dx;
        y1 += dy;
        x2 += dx;
        y2 += dy;
    }

    public static string scale_font_desc (string font_str, double factor) {
        if (factor <= 0.0 || factor == 1.0) return font_str;
        var desc = Pango.FontDescription.from_string (font_str);
        int sz = desc.get_size ();
        if (desc.get_size_is_absolute ()) {
            desc.set_absolute_size (sz * factor);
        } else {
            desc.set_size ((int) Math.round (sz * factor));
        }
        return desc.to_string ();
    }

    public double get_font_size_px () {
        var desc = Pango.FontDescription.from_string (font_desc);
        int sz = desc.get_size ();
        if (desc.get_size_is_absolute ()) {
            return (double) sz / Pango.SCALE;
        } else {
            // Points to pixels: 1 pt = 4/3 px at 96 DPI
            return ((double) sz / Pango.SCALE) * (4.0 / 3.0);
        }
    }

    public void get_padding_and_radius (out double pad, out double radius) {
        double fs = get_font_size_px ();
        // Padding is at least one third of font size, minimum 8.0px
        pad = double.max (fs / 3.0, 8.0);
        // Slightly rounded corners: proportional to padding
        radius = double.max (pad * 0.6, 5.0);
    }

    public void get_bounds (Pango.Context? pango_ctx, out double bx, out double by, out double bw, out double bh) {
        if (tool_type == ToolType.TEXT) {
            double tw = 100.0, th = 30.0;
            if (pango_ctx != null) {
                var layout = new Pango.Layout (pango_ctx);
                var desc = Pango.FontDescription.from_string (font_desc);
                layout.set_font_description (desc);
                layout.set_text (text, -1);
                Pango.Rectangle logical_rect;
                layout.get_pixel_extents (null, out logical_rect);
                tw = (double) logical_rect.width;
                th = (double) logical_rect.height;
            }
            double pad, r;
            get_padding_and_radius (out pad, out r);
            bx = x1 - pad;
            by = y1 - pad;
            bw = tw + pad * 2.0;
            bh = th + pad * 2.0;
            return;
        }

        double min_x = double.min (x1, x2);
        double min_y = double.min (y1, y2);
        double max_x = double.max (x1, x2);
        double max_y = double.max (y1, y2);
        double pad = double.max (line_width / 2.0 + 8.0, 10.0);
        bx = min_x - pad;
        by = min_y - pad;
        bw = (max_x - min_x) + pad * 2.0;
        bh = (max_y - min_y) + pad * 2.0;
    }

    public bool hit_test (double px, double py, Pango.Context? pango_ctx) {
        double bx, by, bw, bh;
        get_bounds (pango_ctx, out bx, out by, out bw, out bh);
        return (px >= bx && px <= bx + bw && py >= by && py <= by + bh);
    }

    public void draw (Cairo.Context cr, double scale, double ox, double oy, Pango.Context pango_ctx) {
        double sx1 = ox + x1 * scale;
        double sy1 = oy + y1 * scale;
        double sx2 = ox + x2 * scale;
        double sy2 = oy + y2 * scale;
        double slw = line_width * scale;

        cr.save ();

        if (tool_type == ToolType.LINE) {
            cr.set_source_rgba (stroke_color.red, stroke_color.green, stroke_color.blue, stroke_color.alpha);
            cr.set_line_width (slw);
            cr.set_line_cap (Cairo.LineCap.ROUND);
            cr.move_to (sx1, sy1);
            cr.line_to (sx2, sy2);
            cr.stroke ();
        } else if (tool_type == ToolType.ARROW) {
            cr.set_source_rgba (stroke_color.red, stroke_color.green, stroke_color.blue, stroke_color.alpha);
            draw_arrow_cairo (cr, sx1, sy1, sx2, sy2, slw);
        } else if (tool_type == ToolType.RECTANGLE) {
            cr.set_source_rgba (stroke_color.red, stroke_color.green, stroke_color.blue, stroke_color.alpha);
            cr.set_line_width (slw);
            double rx = double.min (sx1, sx2);
            double ry = double.min (sy1, sy2);
            double rw = (sx1 - sx2).abs ();
            double rh = (sy1 - sy2).abs ();
            cr.rectangle (rx, ry, rw, rh);
            cr.stroke ();
        } else if (tool_type == ToolType.CIRCLE) {
            cr.set_source_rgba (stroke_color.red, stroke_color.green, stroke_color.blue, stroke_color.alpha);
            cr.set_line_width (slw);
            double rx = double.min (sx1, sx2);
            double ry = double.min (sy1, sy2);
            double rw = (sx1 - sx2).abs ();
            double rh = (sy1 - sy2).abs ();
            if (rw >= 1.0 && rh >= 1.0) {
                cr.new_path ();
                cr.save ();
                cr.translate (rx + rw / 2.0, ry + rh / 2.0);
                cr.scale (rw / 2.0, rh / 2.0);
                cr.new_sub_path ();
                cr.arc (0.0, 0.0, 1.0, 0.0, 2.0 * Math.PI);
                cr.close_path ();
                cr.restore ();
                cr.stroke ();
            }
        } else if (tool_type == ToolType.TEXT) {
            var layout = Pango.cairo_create_layout (cr);
            var desc = Pango.FontDescription.from_string (font_desc);
            int orig_size = desc.get_size ();
            bool is_absolute = desc.get_size_is_absolute ();
            if (scale != 1.0) {
                if (is_absolute) {
                    desc.set_absolute_size (orig_size * scale);
                } else {
                    desc.set_size ((int) (orig_size * scale));
                }
            }
            layout.set_font_description (desc);
            layout.set_text (text, -1);

            Pango.Rectangle logical_rect;
            layout.get_pixel_extents (null, out logical_rect);
            double tw = (double) logical_rect.width;
            double th = (double) logical_rect.height;

            if (bg_color.alpha > 0.0f) {
                double base_pad, base_r;
                get_padding_and_radius (out base_pad, out base_r);
                double pad = base_pad * scale;
                double r = base_r * scale;
                double bx = sx1 - pad;
                double by = sy1 - pad;
                double bw = tw + pad * 2.0;
                double bh = th + pad * 2.0;

                // Ensure corner radius does not exceed half the dimension
                r = double.min (r, double.min (bw / 2.0, bh / 2.0));

                cr.save ();
                cr.set_source_rgba (bg_color.red, bg_color.green, bg_color.blue, bg_color.alpha);
                cr.new_sub_path ();
                cr.arc (bx + bw - r, by + r, r, -Math.PI / 2.0, 0.0);
                cr.arc (bx + bw - r, by + bh - r, r, 0.0, Math.PI / 2.0);
                cr.arc (bx + r, by + bh - r, r, Math.PI / 2.0, Math.PI);
                cr.arc (bx + r, by + r, r, Math.PI, 3.0 * Math.PI / 2.0);
                cr.close_path ();
                cr.fill ();
                cr.restore ();
            }

            cr.set_source_rgba (stroke_color.red, stroke_color.green, stroke_color.blue, stroke_color.alpha);
            cr.move_to (sx1, sy1);
            Pango.cairo_show_layout (cr, layout);
        }

        cr.restore ();
    }

    public static void draw_arrow_cairo (Cairo.Context cr, double x1, double y1, double x2, double y2, double lw) {
        double dx = x2 - x1;
        double dy = y2 - y1;
        double dist = Math.hypot (dx, dy);
        if (dist < 2.0) return;

        double angle = Math.atan2 (dy, dx);
        double ux = Math.cos (angle);
        double uy = Math.sin (angle);
        double nx = -Math.sin (angle);
        double ny = Math.cos (angle);

        double hw = lw / 2.0;
        double head_len = double.max (lw * 2.8, 16.0);
        if (head_len > dist * 0.75) {
            head_len = dist * 0.75;
        }
        double head_half_w = double.max (head_len * 0.45, lw * 1.3);

        double base_x = x2 - head_len * ux;
        double base_y = y2 - head_len * uy;

        double wing1_x = base_x + head_half_w * nx;
        double wing1_y = base_y + head_half_w * ny;

        double wing2_x = base_x - head_half_w * nx;
        double wing2_y = base_y - head_half_w * ny;

        double shaft_attach_dist = head_len * 0.8;
        double attach_x = x2 - shaft_attach_dist * ux;
        double attach_y = y2 - shaft_attach_dist * uy;

        double base1_x = attach_x + hw * nx;
        double base1_y = attach_y + hw * ny;

        double base2_x = attach_x - hw * nx;
        double base2_y = attach_y - hw * ny;

        cr.new_path ();
        cr.move_to (x2, y2);
        cr.line_to (wing2_x, wing2_y);
        cr.line_to (base2_x, base2_y);

        double start_r_x = x1 - hw * nx;
        double start_r_y = y1 - hw * ny;
        cr.line_to (start_r_x, start_r_y);

        cr.arc_negative (x1, y1, hw, angle - Math.PI / 2.0, angle - 3.0 * Math.PI / 2.0);

        cr.line_to (base1_x, base1_y);
        cr.line_to (wing1_x, wing1_y);
        cr.close_path ();

        cr.fill ();
    }
}

public class EditorSnapshot : GLib.Object {
    public Gdk.Pixbuf base_pixbuf;
    public GLib.List<AnnotationItem> shapes;

    public EditorSnapshot (Gdk.Pixbuf pb, GLib.List<AnnotationItem> shps) {
        this.base_pixbuf = pb.copy ();
        this.shapes = new GLib.List<AnnotationItem> ();
        foreach (unowned AnnotationItem item in shps) {
            this.shapes.append (item.copy ());
        }
    }
}

public class ImageCanvas : Gtk.DrawingArea {
    private Gdk.Pixbuf? _base_pixbuf = null;
    private Cairo.ImageSurface? cached_surface = null;
    private Cairo.Pattern? cached_pattern = null;

    private int last_draw_width = 0;
    private int last_draw_height = 0;

    public signal void zoom_changed ();

    public Gdk.Pixbuf? base_pixbuf {
        get { return _base_pixbuf; }
        set {
            _base_pixbuf = value;
            update_cached_surface ();
            zoom_changed ();
            queue_draw ();
        }
    }

    public GLib.List<AnnotationItem> shapes;
    public AnnotationItem? selected_shape { get; set; default = null; }

    public ToolType current_tool { get; set; default = ToolType.NONE; }
    public Gdk.RGBA draw_color { get; set; }
    public Gdk.RGBA text_color { get; set; }
    public Gdk.RGBA text_bg_color { get; set; }
    public double line_width { get; set; default = 4.0; }
    public string font_desc { get; set; default = "Sans Bold 20"; }

    private bool is_dragging = false;
    private double start_x = 0;
    private double start_y = 0;
    private double current_x = 0;
    private double current_y = 0;

    // Moving element support
    private bool is_moving_element = false;
    private double move_prev_ix = 0;
    private double move_prev_iy = 0;
    private bool element_actually_moved = false;

    // Text creation/editing click vs drag support
    private bool text_pending_click = false;
    private bool is_dragging_text = false;
    private double text_pending_ix = 0;
    private double text_pending_iy = 0;
    private AnnotationItem? text_pending_item = null;

    public signal void before_action_applied ();
    public signal void image_modified ();
    public signal void text_requested (double img_x, double img_y, AnnotationItem? existing_item);
    public signal void delete_shape_requested (AnnotationItem item);

    public void remove_shape (AnnotationItem item) {
        before_action_applied ();
        unowned GLib.List<AnnotationItem>? link = shapes.find (item);
        if (link != null) {
            shapes.delete_link (link);
        }
        if (selected_shape == item) {
            selected_shape = null;
        }
        image_modified ();
        queue_draw ();
    }

    public void update_cached_surface () {
        if (_base_pixbuf == null) {
            cached_surface = null;
            cached_pattern = null;
            return;
        }
        int pw = _base_pixbuf.width;
        int ph = _base_pixbuf.height;
        cached_surface = new Cairo.ImageSurface (_base_pixbuf.has_alpha ? Cairo.Format.ARGB32 : Cairo.Format.RGB24, pw, ph);
        var cr = new Cairo.Context (cached_surface);
        Gdk.cairo_set_source_pixbuf (cr, _base_pixbuf, 0, 0);
        cr.paint ();
        cached_pattern = new Cairo.Pattern.for_surface (cached_surface);
        cached_pattern.set_filter (Cairo.Filter.FAST);
    }

    public ImageCanvas () {
        shapes = new GLib.List<AnnotationItem> ();
        set_draw_func (on_draw);
        this.resize.connect ((w, h) => {
            last_draw_width = w;
            last_draw_height = h;
            zoom_changed ();
        });

        var drag = new Gtk.GestureDrag ();
        drag.drag_begin.connect (on_drag_begin);
        drag.drag_update.connect (on_drag_update);
        drag.drag_end.connect (on_drag_end);
        drag.cancel.connect ((seq) => {
            is_dragging = false;
            is_moving_element = false;
            is_panning = false;
            text_pending_click = false;
            queue_draw ();
        });
        add_controller (drag);

        var click = new Gtk.GestureClick ();
        click.set_button (0);
        click.pressed.connect (on_click_pressed);
        add_controller (click);

        Gdk.RGBA red = { 1.0f, 0.0f, 0.0f, 1.0f };
        draw_color = red;
        text_color = red;

        Gdk.RGBA transparent = { 0.0f, 0.0f, 0.0f, 0.0f };
        text_bg_color = transparent;
    }

    public void clear_shapes () {
        shapes = new GLib.List<AnnotationItem> ();
        selected_shape = null;
        queue_draw ();
    }

    public void set_shapes_from_list (GLib.List<AnnotationItem> new_shapes) {
        shapes = new GLib.List<AnnotationItem> ();
        foreach (unowned AnnotationItem it in new_shapes) {
            shapes.append (it.copy ());
        }
        selected_shape = null;
        queue_draw ();
    }

    // Zoom & Pan support
    private double _zoom_factor = 1.0;
    public double zoom_factor {
        get { return _zoom_factor; }
        set {
            if (_zoom_factor != value) {
                _zoom_factor = value;
                notify_property ("zoom-factor");
                zoom_changed ();
            }
        }
    }
    public double pan_x { get; set; default = 0.0; }
    public double pan_y { get; set; default = 0.0; }
    private bool is_panning = false;
    private double pan_start_x = 0;
    private double pan_start_y = 0;
    private double pan_orig_x = 0;
    private double pan_orig_y = 0;

    public void reset_zoom () {
        zoom_factor = 1.0;
        pan_x = 0.0;
        pan_y = 0.0;
        queue_draw ();
        zoom_changed ();
    }

    private bool _always_fit_to_window = false;
    public bool always_fit_to_window {
        get { return _always_fit_to_window; }
        set {
            if (_always_fit_to_window != value) {
                _always_fit_to_window = value;
                queue_draw ();
                zoom_changed ();
            }
        }
    }

    public double get_base_scale (int widget_w, int widget_h) {
        if (base_pixbuf == null) return 1.0;
        int pw = base_pixbuf.width;
        int ph = base_pixbuf.height;
        int ww = widget_w > 0 ? widget_w : last_draw_width;
        int wh = widget_h > 0 ? widget_h : last_draw_height;
        if (ww <= 0 || wh <= 0 || pw <= 0 || ph <= 0) return 1.0;

        double fit_scale = double.min ((double) ww / pw, (double) wh / ph);
        if (_always_fit_to_window) {
            return fit_scale;
        }
        // If image fits completely within the current area at 100%, do not upscale
        return double.min (1.0, fit_scale);
    }

    public void zoom_to_100 () {
        if (base_pixbuf == null) return;
        int ww = get_width ();
        int wh = get_height ();
        if (ww <= 0) ww = last_draw_width;
        if (wh <= 0) wh = last_draw_height;
        if (ww <= 0 || wh <= 0) return;

        double base_scale = get_base_scale (ww, wh);
        if (base_scale <= 0.0) return;

        zoom_factor = 1.0 / base_scale;
        pan_x = 0.0;
        pan_y = 0.0;
        queue_draw ();
        zoom_changed ();
    }

    public void toggle_zoom_100_or_fit () {
        if (base_pixbuf == null) return;
        int ww = get_width ();
        int wh = get_height ();
        if (ww <= 0) ww = last_draw_width;
        if (wh <= 0) wh = last_draw_height;
        if (ww <= 0 || wh <= 0) return;

        double base_scale = get_base_scale (ww, wh);
        double fit_scale = double.min ((double) ww / base_pixbuf.width, (double) wh / base_pixbuf.height);
        if (base_scale <= 0.0 || fit_scale <= 0.0) return;

        double current_scale = base_scale * zoom_factor;
        if (Math.fabs (current_scale - 1.0) < 0.01) {
            // Already at 100%: toggle to fit
            zoom_factor = fit_scale / base_scale;
            pan_x = 0.0;
            pan_y = 0.0;
            queue_draw ();
            zoom_changed ();
        } else {
            // Not at 100%: toggle to 100% actual size
            zoom_to_100 ();
        }
    }

    public void zoom_at (double cursor_x, double cursor_y, double factor_multiplier) {
        if (base_pixbuf == null) return;

        int ww = get_width ();
        int wh = get_height ();
        if (ww <= 0) ww = last_draw_width;
        if (wh <= 0) wh = last_draw_height;
        if (ww <= 0 || wh <= 0) return;

        double base_scale = get_base_scale (ww, wh);
        if (base_scale <= 0.0) return;

        double old_zf = zoom_factor;
        double old_scale = base_scale * old_zf;
        double min_scale = double.min (0.01, base_scale * 0.05);
        double max_scale = double.max (50.0, base_scale * 10.0);
        double new_scale = (old_scale * factor_multiplier).clamp (min_scale, max_scale);
        if (new_scale == old_scale) return;

        double new_zf = new_scale / base_scale;

        double base_ox = (ww - base_pixbuf.width * old_scale) / 2.0 + pan_x;
        double base_oy = (wh - base_pixbuf.height * old_scale) / 2.0 + pan_y;

        // Image coordinates under cursor
        double ix = (cursor_x - base_ox) / old_scale;
        double iy = (cursor_y - base_oy) / old_scale;

        // New offset without pan
        double new_base_ox = (ww - base_pixbuf.width * new_scale) / 2.0;
        double new_base_oy = (wh - base_pixbuf.height * new_scale) / 2.0;

        // Solve for pan_x, pan_y so cursor stays at (ix, iy)
        pan_x = cursor_x - new_base_ox - ix * new_scale;
        pan_y = cursor_y - new_base_oy - iy * new_scale;

        zoom_factor = new_zf;
        queue_draw ();
    }

    public void get_image_bounds (int widget_w, int widget_h,
                                  out double offset_x, out double offset_y,
                                  out double drawn_w, out double drawn_h,
                                  out double scale) {
        if (base_pixbuf == null) {
            offset_x = 0; offset_y = 0; drawn_w = 0; drawn_h = 0; scale = 1.0;
            return;
        }
        int pw = base_pixbuf.width;
        int ph = base_pixbuf.height;
        if (widget_w <= 0) widget_w = last_draw_width;
        if (widget_h <= 0) widget_h = last_draw_height;
        if (widget_w <= 0 || widget_h <= 0 || pw <= 0 || ph <= 0) {
            offset_x = 0; offset_y = 0; drawn_w = (double) pw; drawn_h = (double) ph; scale = 1.0;
            return;
        }
        double base_scale = get_base_scale (widget_w, widget_h);
        scale = base_scale * zoom_factor;
        drawn_w = pw * scale;
        drawn_h = ph * scale;
        offset_x = (widget_w - drawn_w) / 2.0 + pan_x;
        offset_y = (widget_h - drawn_h) / 2.0 + pan_y;
    }

    public double get_current_scale () {
        double ox, oy, dw, dh, scale;
        get_image_bounds (get_width (), get_height (), out ox, out oy, out dw, out dh, out scale);
        return (scale > 0.0) ? scale : 1.0;
    }

    public void widget_to_image (double wx, double wy, out double ix, out double iy) {
        double ox, oy, dw, dh, scale;
        get_image_bounds (get_width (), get_height (), out ox, out oy, out dw, out dh, out scale);
        ix = (wx - ox) / scale;
        iy = (wy - oy) / scale;
        if (base_pixbuf != null) {
            ix = ix.clamp (0.0, (double) base_pixbuf.width);
            iy = iy.clamp (0.0, (double) base_pixbuf.height);
        }
    }

    private AnnotationItem? find_shape_at (double ix, double iy) {
        var pctx = get_pango_context ();
        int len = (int) shapes.length ();
        for (int i = len - 1; i >= 0; i--) {
            unowned AnnotationItem item = shapes.nth_data (i);
            if (item.hit_test (ix, iy, pctx)) {
                return item;
            }
        }
        return null;
    }

    private void on_click_pressed (Gtk.GestureClick gesture, int n_press, double x, double y) {
        var root = get_root ();
        if (root != null && root.get_focus () != null) {
            root.set_focus (null);
        }

        if (base_pixbuf == null || current_tool == ToolType.NONE) return;

        double ix, iy;
        widget_to_image (x, y, out ix, out iy);

        uint btn = gesture.get_current_button ();

        // Right click (button 3): prompt to delete clicked shape
        if (btn == 3) {
            var hit = find_shape_at (ix, iy);
            if (hit != null) {
                gesture.set_state (Gtk.EventSequenceState.CLAIMED);
                delete_shape_requested (hit);
            }
            return;
        }
    }

    private void on_drag_begin (double x, double y) {
        var root = get_root ();
        if (root != null && root.get_focus () != null) {
            root.set_focus (null);
        }

        if (base_pixbuf == null) return;

        if (current_tool == ToolType.NONE) {
            is_panning = true;
            pan_start_x = x;
            pan_start_y = y;
            pan_orig_x = pan_x;
            pan_orig_y = pan_y;
            return;
        }

        double ix, iy;
        widget_to_image (x, y, out ix, out iy);

        if (current_tool == ToolType.MOVE) {
            var hit = find_shape_at (ix, iy);
            selected_shape = hit;
            if (hit != null) {
                is_moving_element = true;
                element_actually_moved = false;
                start_x = x;
                start_y = y;
                move_prev_ix = ix;
                move_prev_iy = iy;
            } else {
                // Dragging empty space in MOVE tool pans the view
                is_panning = true;
                pan_start_x = x;
                pan_start_y = y;
                pan_orig_x = pan_x;
                pan_orig_y = pan_y;
            }
            queue_draw ();
            return;
        }

        if (current_tool == ToolType.TEXT) {
            var hit = find_shape_at (ix, iy);
            text_pending_click = true;
            is_dragging_text = false;
            text_pending_ix = ix;
            text_pending_iy = iy;
            text_pending_item = (hit != null && hit.tool_type == ToolType.TEXT) ? hit : null;
            start_x = x;
            start_y = y;
            if (text_pending_item != null) {
                selected_shape = text_pending_item;
                move_prev_ix = ix;
                move_prev_iy = iy;
            }
            queue_draw ();
            return;
        }

        selected_shape = null;
        is_dragging = true;
        start_x = x;
        start_y = y;
        current_x = x;
        current_y = y;
        queue_draw ();
    }

    private void on_drag_update (double offset_x, double offset_y) {
        if (text_pending_click) {
            // If mouse moved more than 4px while button is down, treat as drag
            if (Math.hypot (offset_x, offset_y) > 4.0) {
                if (!is_dragging_text && text_pending_item != null) {
                    before_action_applied ();
                }
                is_dragging_text = true;
                if (text_pending_item != null) {
                    double ix, iy;
                    widget_to_image (start_x + offset_x, start_y + offset_y, out ix, out iy);
                    double dx = ix - move_prev_ix;
                    double dy = iy - move_prev_iy;
                    if (dx != 0 || dy != 0) {
                        text_pending_item.translate (dx, dy);
                        move_prev_ix = ix;
                        move_prev_iy = iy;
                        element_actually_moved = true;
                        queue_draw ();
                    }
                }
            }
            return;
        }

        if (is_panning) {
            pan_x = pan_orig_x + offset_x;
            pan_y = pan_orig_y + offset_y;
            queue_draw ();
            return;
        }

        if (is_moving_element && selected_shape != null) {
            if (Math.hypot (offset_x, offset_y) > 4.0) {
                if (!element_actually_moved) {
                    before_action_applied ();
                }
                double ix, iy;
                widget_to_image (start_x + offset_x, start_y + offset_y, out ix, out iy);
                double dx = ix - move_prev_ix;
                double dy = iy - move_prev_iy;
                if (dx != 0 || dy != 0) {
                    selected_shape.translate (dx, dy);
                    move_prev_ix = ix;
                    move_prev_iy = iy;
                    element_actually_moved = true;
                    queue_draw ();
                }
            }
            return;
        }

        if (!is_dragging) return;
        current_x = start_x + offset_x;
        current_y = start_y + offset_y;
        queue_draw ();
    }

    private void on_drag_end (double offset_x, double offset_y) {
        if (is_panning) {
            is_panning = false;
            pan_x = pan_orig_x + offset_x;
            pan_y = pan_orig_y + offset_y;
            queue_draw ();
            return;
        }

        if (text_pending_click) {
            bool was_dragging = is_dragging_text;
            var item = text_pending_item;
            double px = text_pending_ix;
            double py = text_pending_iy;

            text_pending_click = false;
            is_dragging_text = false;
            text_pending_item = null;

            if (was_dragging) {
                if (element_actually_moved) {
                    element_actually_moved = false;
                    image_modified ();
                }
            } else {
                // It was a click (released without dragging)!
                if (item != null) {
                    text_requested (item.x1, item.y1, item);
                } else {
                    text_requested (px, py, null);
                }
            }
            queue_draw ();
            return;
        }

        if (is_moving_element) {
            is_moving_element = false;
            if (element_actually_moved) {
                element_actually_moved = false;
                image_modified ();
            } else {
                // Clicked without dragging: if clicked element is text, open edit dialog on mouse release
                if (selected_shape != null && selected_shape.tool_type == ToolType.TEXT) {
                    text_requested (selected_shape.x1, selected_shape.y1, selected_shape);
                }
            }
            queue_draw ();
            return;
        }

        if (!is_dragging) return;
        is_dragging = false;
        current_x = start_x + offset_x;
        current_y = start_y + offset_y;

        commit_current_shape ();
        queue_draw ();
    }

    private void commit_current_shape () {
        if (base_pixbuf == null) return;
        double x1, y1, x2, y2;
        widget_to_image (start_x, start_y, out x1, out y1);
        widget_to_image (current_x, current_y, out x2, out y2);

        if (current_tool == ToolType.REDACT) {
            int rx = (int) double.min (x1, x2);
            int ry = (int) double.min (y1, y2);
            int rw = (int) (x1 - x2).abs ();
            int rh = (int) (y1 - y2).abs ();
            if (rw > 1 && rh > 1) {
                before_action_applied ();
                apply_redact (rx, ry, rw, rh);
                image_modified ();
            }
            return;
        }

        if (current_tool == ToolType.LINE || current_tool == ToolType.ARROW ||
            current_tool == ToolType.RECTANGLE || current_tool == ToolType.CIRCLE) {
            if (Math.hypot (x2 - x1, y2 - y1) < 3.0) {
                return;
            }
            before_action_applied ();
            var item = new AnnotationItem (current_tool);
            item.x1 = x1;
            item.y1 = y1;
            item.x2 = x2;
            item.y2 = y2;
            item.stroke_color = draw_color;
            double cur_scale = get_current_scale ();
            item.line_width = line_width / cur_scale;
            shapes.append (item);
            selected_shape = item;
            image_modified ();
        }
    }

    public void add_or_update_text (string text, double ix, double iy, AnnotationItem? existing_item, string text_font_desc, Gdk.RGBA fg_color, Gdk.RGBA text_bg) {
        if (base_pixbuf == null) return;
        before_action_applied ();
        if (existing_item != null) {
            existing_item.text = text;
            existing_item.stroke_color = fg_color;
            existing_item.bg_color = text_bg;
            existing_item.font_desc = text_font_desc;
            selected_shape = existing_item;
        } else {
            var item = new AnnotationItem (ToolType.TEXT);
            item.x1 = ix;
            item.y1 = iy;
            item.text = text;
            item.stroke_color = fg_color;
            item.bg_color = text_bg;
            item.font_desc = text_font_desc;
            shapes.append (item);
            selected_shape = item;
        }
        image_modified ();
        queue_draw ();
    }

    public Gdk.Pixbuf? get_composed_pixbuf () {
        if (base_pixbuf == null) return null;
        int pw = base_pixbuf.width;
        int ph = base_pixbuf.height;
        var surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, pw, ph);
        var cr = new Cairo.Context (surface);
        Gdk.cairo_set_source_pixbuf (cr, base_pixbuf, 0, 0);
        cr.paint ();

        var pctx = get_pango_context ();
        foreach (unowned AnnotationItem item in shapes) {
            item.draw (cr, 1.0, 0.0, 0.0, pctx);
        }

        return Gdk.pixbuf_get_from_surface (surface, 0, 0, pw, ph);
    }

    private void bake_intersecting_shapes (double rx, double ry, double rw, double rh) {
        if (_base_pixbuf == null || shapes.length () == 0) return;

        var pctx = get_pango_context ();
        var intersecting = new GLib.List<AnnotationItem> ();
        foreach (unowned AnnotationItem item in shapes) {
            double bx, by, bw, bh;
            item.get_bounds (pctx, out bx, out by, out bw, out bh);
            if (!(bx + bw < rx || bx > rx + rw || by + bh < ry || by > ry + rh)) {
                intersecting.append (item);
            }
        }

        if (intersecting.length () == 0) return;

        int pw = _base_pixbuf.width;
        int ph = _base_pixbuf.height;
        var surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, pw, ph);
        var cr = new Cairo.Context (surface);
        Gdk.cairo_set_source_pixbuf (cr, _base_pixbuf, 0, 0);
        cr.paint ();

        foreach (unowned AnnotationItem item in intersecting) {
            item.draw (cr, 1.0, 0.0, 0.0, pctx);
            unowned GLib.List<AnnotationItem>? link = shapes.find (item);
            if (link != null) {
                shapes.delete_link (link);
            }
            if (selected_shape == item) {
                selected_shape = null;
            }
        }

        var new_base = Gdk.pixbuf_get_from_surface (surface, 0, 0, pw, ph);
        if (new_base != null) {
            _base_pixbuf = new_base;
        }
    }

    private void apply_redact (int rx, int ry, int rw, int rh) {
        if (_base_pixbuf == null) return;

        bake_intersecting_shapes ((double) rx, (double) ry, (double) rw, (double) rh);

        int w = _base_pixbuf.get_width ();
        int h = _base_pixbuf.get_height ();
        int n_channels = _base_pixbuf.get_n_channels ();
        int rowstride = _base_pixbuf.get_rowstride ();
        unowned uint8[] pixels = _base_pixbuf.get_pixels_with_length ();

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

                long sum_r = 0, sum_g = 0, sum_b = 0, sum_a = 0;
                for (int cy = 0; cy < bh; cy++) {
                    int row = (by + cy) * rowstride;
                    for (int cx = 0; cx < bw; cx++) {
                        int idx = row + (bx + cx) * n_channels;
                        sum_r += pixels[idx];
                        sum_g += pixels[idx + 1];
                        sum_b += pixels[idx + 2];
                        if (n_channels >= 4) {
                            sum_a += pixels[idx + 3];
                        }
                    }
                }

                uint8 avg_r = (uint8) (sum_r / count);
                uint8 avg_g = (uint8) (sum_g / count);
                uint8 avg_b = (uint8) (sum_b / count);
                uint8 avg_a = (n_channels >= 4) ? (uint8) (sum_a / count) : (uint8) 255;
                if (n_channels >= 4 && avg_a > 0) {
                    avg_a = (uint8) int.max ((int) avg_a, 255);
                }

                for (int cy = 0; cy < bh; cy++) {
                    int row = (by + cy) * rowstride;
                    for (int cx = 0; cx < bw; cx++) {
                        int idx = row + (bx + cx) * n_channels;
                        pixels[idx] = avg_r;
                        pixels[idx + 1] = avg_g;
                        pixels[idx + 2] = avg_b;
                        if (n_channels >= 4) {
                            pixels[idx + 3] = avg_a;
                        }
                    }
                }
            }
        }
        update_cached_surface ();
    }

    private void on_draw (Gtk.DrawingArea area, Cairo.Context cr, int width, int height) {
        last_draw_width = width;
        last_draw_height = height;
        if (base_pixbuf == null) return;

        double ox, oy, dw, dh, scale;
        get_image_bounds (width, height, out ox, out oy, out dw, out dh, out scale);

        // 1. Base image (fast rendering via cached Cairo pattern)
        cr.save ();
        cr.translate (ox, oy);
        cr.scale (scale, scale);
        if (cached_pattern != null) {
            cr.set_source (cached_pattern);
        } else {
            Gdk.cairo_set_source_pixbuf (cr, base_pixbuf, 0, 0);
        }
        cr.paint ();
        cr.restore ();

        // 2. Vector annotations
        var pctx = get_pango_context ();
        foreach (unowned AnnotationItem item in shapes) {
            item.draw (cr, scale, ox, oy, pctx);
        }

        // 3. Selection indicator for Move tool
        if (current_tool == ToolType.MOVE && selected_shape != null) {
            double bx, by, bw, bh;
            selected_shape.get_bounds (pctx, out bx, out by, out bw, out bh);
            double sbx = ox + bx * scale;
            double sby = oy + by * scale;
            double sbw = bw * scale;
            double sbh = bh * scale;

            cr.save ();
            cr.set_source_rgba (0.2, 0.5, 1.0, 0.8);
            cr.set_line_width (1.5);
            double[] dashes = { 4.0, 4.0 };
            cr.set_dash (dashes, 0.0);
            cr.rectangle (sbx, sby, sbw, sbh);
            cr.stroke ();
            cr.restore ();
        }

        // 4. Live interactive drag preview for creation
        if (is_dragging && current_tool != ToolType.NONE && current_tool != ToolType.MOVE) {
            cr.save ();
            if (current_tool == ToolType.REDACT) {
                double ix1, iy1, ix2, iy2;
                widget_to_image (start_x, start_y, out ix1, out iy1);
                widget_to_image (current_x, current_y, out ix2, out iy2);
                double rx = ox + double.min (ix1, ix2) * scale;
                double ry = oy + double.min (iy1, iy2) * scale;
                double rw = (ix1 - ix2).abs () * scale;
                double rh = (iy1 - iy2).abs () * scale;

                if (rw > 1.0 && rh > 1.0) {
                    // Semi-transparent blue fill
                    cr.set_source_rgba (0.15, 0.45, 0.95, 0.3);
                    cr.rectangle (rx, ry, rw, rh);
                    cr.fill ();

                    // High-contrast outer dark border (for light images)
                    cr.set_source_rgba (0.0, 0.0, 0.0, 0.85);
                    cr.set_line_width (2.0);
                    cr.rectangle (rx, ry, rw, rh);
                    cr.stroke ();

                    // High-contrast inner white dashed border (for dark images)
                    cr.set_source_rgba (1.0, 1.0, 1.0, 0.95);
                    cr.set_line_width (1.5);
                    double[] dashes = { 5.0, 5.0 };
                    cr.set_dash (dashes, 0.0);
                    cr.rectangle (rx, ry, rw, rh);
                    cr.stroke ();
                }
            } else {
                cr.set_source_rgba (draw_color.red, draw_color.green, draw_color.blue, draw_color.alpha);
                double preview_lw = line_width;

                if (current_tool == ToolType.LINE) {
                    cr.set_line_width (preview_lw);
                    cr.set_line_cap (Cairo.LineCap.ROUND);
                    cr.move_to (start_x, start_y);
                    cr.line_to (current_x, current_y);
                    cr.stroke ();
                } else if (current_tool == ToolType.ARROW) {
                    AnnotationItem.draw_arrow_cairo (cr, start_x, start_y, current_x, current_y, preview_lw);
                } else if (current_tool == ToolType.RECTANGLE) {
                    cr.set_line_width (preview_lw);
                    double rx = double.min (start_x, current_x);
                    double ry = double.min (start_y, current_y);
                    double rw = (start_x - current_x).abs ();
                    double rh = (start_y - current_y).abs ();
                    cr.rectangle (rx, ry, rw, rh);
                    cr.stroke ();
                } else if (current_tool == ToolType.CIRCLE) {
                    cr.set_line_width (preview_lw);
                    double rx = double.min (start_x, current_x);
                    double ry = double.min (start_y, current_y);
                    double rw = (start_x - current_x).abs ();
                    double rh = (start_y - current_y).abs ();
                    if (rw >= 1.0 && rh >= 1.0) {
                        cr.new_path ();
                        cr.save ();
                        cr.translate (rx + rw / 2.0, ry + rh / 2.0);
                        cr.scale (rw / 2.0, rh / 2.0);
                        cr.new_sub_path ();
                        cr.arc (0.0, 0.0, 1.0, 0.0, 2.0 * Math.PI);
                        cr.close_path ();
                        cr.restore ();
                        cr.stroke ();
                    }
                }
            }
            cr.restore ();
        }
    }
}

public class EditorManager : GLib.Object {
    public ImageCanvas canvas { get; construct set; }
    public ConfigManager config_manager { get; construct set; }
    public Gtk.Window? parent_window { get; set; default = null; }

    // Toolbar buttons
    public Gtk.Button undo_button;
    public Gtk.Button redo_button;
    public Gtk.ToggleButton move_btn;
    public Gtk.ToggleButton line_btn;
    public Gtk.ToggleButton arrow_btn;
    public Gtk.ToggleButton rect_btn;
    public Gtk.ToggleButton circle_btn;
    public Gtk.ToggleButton redact_btn;
    public Gtk.ToggleButton text_btn;

    public Gtk.ColorDialogButton color_btn;
    public Gtk.SpinButton width_spin;

    // Undo / Redo history
    private GLib.List<EditorSnapshot> undo_stack;
    private GLib.List<EditorSnapshot> redo_stack;
    private const uint MAX_HISTORY = 30;
    private bool is_updating_tools = false;

    public signal void state_changed ();

    public EditorManager (ImageCanvas canvas, ConfigManager config_manager) {
        Object (canvas: canvas, config_manager: config_manager);
        undo_stack = new GLib.List<EditorSnapshot> ();
        redo_stack = new GLib.List<EditorSnapshot> ();

        canvas.before_action_applied.connect (() => {
            push_undo_snapshot ();
        });

        canvas.image_modified.connect (() => {
            state_changed ();
        });

        canvas.text_requested.connect ((ix, iy, existing_item) => {
            prompt_text_dialog (ix, iy, existing_item);
        });

        canvas.delete_shape_requested.connect ((item) => {
            prompt_delete_shape_dialog (item);
        });
    }

    public void reset_history () {
        undo_stack = new GLib.List<EditorSnapshot> ();
        redo_stack = new GLib.List<EditorSnapshot> ();
        update_undo_redo_sensitivity ();
    }

    public void push_undo_snapshot () {
        if (canvas == null || canvas.base_pixbuf == null) return;
        var snap = new EditorSnapshot (canvas.base_pixbuf, canvas.shapes);
        undo_stack.append (snap);
        if (undo_stack.length () > MAX_HISTORY) {
            undo_stack.delete_link (undo_stack.first ());
        }
        redo_stack = new GLib.List<EditorSnapshot> ();
        update_undo_redo_sensitivity ();
    }

    public void undo () {
        if (undo_stack == null || undo_stack.length () == 0 || canvas == null || canvas.base_pixbuf == null) return;

        unowned GLib.List<EditorSnapshot> last_link = undo_stack.last ();
        var prev_snap = last_link.data;
        undo_stack.delete_link (last_link);

        var current_snap = new EditorSnapshot (canvas.base_pixbuf, canvas.shapes);
        redo_stack.append (current_snap);

        canvas.base_pixbuf = prev_snap.base_pixbuf.copy ();
        canvas.set_shapes_from_list (prev_snap.shapes);

        state_changed ();
        update_undo_redo_sensitivity ();
    }

    public void redo () {
        if (redo_stack == null || redo_stack.length () == 0 || canvas == null || canvas.base_pixbuf == null) return;

        unowned GLib.List<EditorSnapshot> last_link = redo_stack.last ();
        var next_snap = last_link.data;
        redo_stack.delete_link (last_link);

        var current_snap = new EditorSnapshot (canvas.base_pixbuf, canvas.shapes);
        undo_stack.append (current_snap);

        canvas.base_pixbuf = next_snap.base_pixbuf.copy ();
        canvas.set_shapes_from_list (next_snap.shapes);

        state_changed ();
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

    public Gtk.Widget create_edit_toolbar () {
        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
        box.margin_top = 4;
        box.margin_bottom = 6;
        box.margin_start = 12;
        box.margin_end = 12;

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

        move_btn = new Gtk.ToggleButton ();
        move_btn.add_css_class ("image-button");
        move_btn.set_child (create_tool_icon ("hand"));
        move_btn.tooltip_text = "Select & Move Elements (M)";
        move_btn.toggled.connect (() => on_tool_toggled (move_btn, ToolType.MOVE));
        box.append (move_btn);

        line_btn = new Gtk.ToggleButton ();
        line_btn.add_css_class ("image-button");
        line_btn.set_child (create_tool_icon ("line"));
        line_btn.tooltip_text = "Draw Straight Line";
        line_btn.toggled.connect (() => on_tool_toggled (line_btn, ToolType.LINE));
        box.append (line_btn);

        arrow_btn = new Gtk.ToggleButton ();
        arrow_btn.add_css_class ("image-button");
        arrow_btn.set_child (create_tool_icon ("arrow"));
        arrow_btn.tooltip_text = "Draw Arrow";
        arrow_btn.toggled.connect (() => on_tool_toggled (arrow_btn, ToolType.ARROW));
        box.append (arrow_btn);

        rect_btn = new Gtk.ToggleButton ();
        rect_btn.add_css_class ("image-button");
        rect_btn.set_child (create_tool_icon ("rect"));
        rect_btn.tooltip_text = "Draw Rectangle";
        rect_btn.toggled.connect (() => on_tool_toggled (rect_btn, ToolType.RECTANGLE));
        box.append (rect_btn);

        circle_btn = new Gtk.ToggleButton ();
        circle_btn.add_css_class ("image-button");
        circle_btn.set_child (create_tool_icon ("circle"));
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

        // Color Picker (Stroke & Drawing Color)
        var color_dialog = new Gtk.ColorDialog ();
        color_dialog.with_alpha = false;
        color_btn = new Gtk.ColorDialogButton (color_dialog);
        Gdk.RGBA red = { 1.0f, 0.0f, 0.0f, 1.0f };
        color_btn.set_rgba (red);
        color_btn.tooltip_text = "Choose Stroke & Drawing Color";
        color_btn.notify["rgba"].connect (() => {
            unowned Gdk.RGBA? c = color_btn.get_rgba ();
            if (c != null) {
                canvas.draw_color = c;
                config_manager.draw_color = c.to_string ();
                config_manager.save ();
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
            config_manager.line_width = width_spin.value;
            config_manager.save ();
        });

        // Unfocus width_spin on Enter / Return or Escape
        width_spin.activate.connect (() => {
            var root = width_spin.get_root ();
            if (root != null) {
                root.set_focus (null);
            }
        });

        var spin_key = new Gtk.EventControllerKey ();
        spin_key.key_pressed.connect ((keyval, keycode, state) => {
            if (keyval == Gdk.Key.Return || keyval == Gdk.Key.KP_Enter || keyval == Gdk.Key.Escape) {
                var root = width_spin.get_root ();
                if (root != null) {
                    root.set_focus (null);
                }
                return true;
            }
            return false;
        });
        width_spin.add_controller (spin_key);

        // When user clicks the increment / decrement (+ / -) buttons of the spin button, unfocus it
        for (var child = width_spin.get_first_child (); child != null; child = child.get_next_sibling ()) {
            if (child is Gtk.Button) {
                ((Gtk.Button) child).clicked.connect (() => {
                    var root = width_spin.get_root ();
                    if (root != null) {
                        root.set_focus (null);
                    }
                });
            }
        }

        box.append (width_spin);

        arrow_btn.active = true;

        return box;
    }

    public static Gtk.Widget create_tool_icon (string tool) {
        var da = new Gtk.DrawingArea ();
        da.set_content_width (16);
        da.set_content_height (16);
        da.halign = Gtk.Align.CENTER;
        da.valign = Gtk.Align.CENTER;
        da.can_target = false;
        da.set_draw_func ((area, cr, width, height) => {
            Gdk.RGBA fg = area.get_color ();
            cr.set_source_rgba (fg.red, fg.green, fg.blue, fg.alpha);

            double cx = width / 2.0;
            double cy = height / 2.0;

            if (tool == "hand") {
                cr.set_line_width (1.2);
                cr.set_line_cap (Cairo.LineCap.ROUND);
                cr.set_line_join (Cairo.LineJoin.ROUND);

                cr.save ();
                cr.translate (cx, cy);
                cr.scale (0.95, 0.95);
                cr.translate (-7.4, -8.6);

                cr.move_to (3.0, 10.0);
                cr.line_to (1.5, 7.5);
                cr.arc (2.5, 6.8, 1.2, Math.PI, 0);
                cr.line_to (4.0, 8.5);

                cr.line_to (4.0, 3.2);
                cr.arc (5.0, 3.2, 1.0, Math.PI, 0);
                cr.line_to (6.0, 7.0);

                cr.line_to (6.5, 2.2);
                cr.arc (7.5, 2.2, 1.0, Math.PI, 0);
                cr.line_to (8.5, 7.0);

                cr.line_to (9.0, 3.0);
                cr.arc (10.0, 3.0, 1.0, Math.PI, 0);
                cr.line_to (11.0, 8.0);

                cr.line_to (11.5, 5.0);
                cr.arc (12.5, 5.0, 1.0, Math.PI, 0);
                cr.line_to (13.5, 10.5);

                cr.arc (9.0, 11.5, 4.5, 0, Math.PI / 2.0);
                cr.line_to (4.5, 16.0);
                cr.close_path ();
                cr.stroke ();
                cr.restore ();
            } else if (tool == "line") {
                cr.set_line_width (2.0);
                cr.set_line_cap (Cairo.LineCap.ROUND);
                cr.move_to (cx - 5.5, cy + 5.5);
                cr.line_to (cx + 5.5, cy - 5.5);
                cr.stroke ();
            } else if (tool == "arrow") {
                cr.set_line_width (2.0);
                cr.set_line_cap (Cairo.LineCap.ROUND);
                cr.set_line_join (Cairo.LineJoin.ROUND);
                cr.move_to (cx - 5.5, cy + 5.5);
                cr.line_to (cx + 5.5, cy - 5.5);
                cr.stroke ();
                cr.move_to (cx - 1.0, cy - 5.5);
                cr.line_to (cx + 5.5, cy - 5.5);
                cr.line_to (cx + 5.5, cy + 1.0);
                cr.stroke ();
            } else if (tool == "rect") {
                cr.set_line_width (1.8);
                cr.set_line_cap (Cairo.LineCap.ROUND);
                cr.set_line_join (Cairo.LineJoin.ROUND);
                cr.rectangle (cx - 6.0, cy - 6.0, 12.0, 12.0);
                cr.stroke ();
            } else if (tool == "circle") {
                cr.set_line_width (1.8);
                cr.arc (cx, cy, 6.0, 0.0, 2.0 * Math.PI);
                cr.stroke ();
            }
        });
        return da;
    }

    private void on_tool_toggled (Gtk.ToggleButton active_btn, ToolType tool) {
        if (is_updating_tools) return;

        if (!active_btn.active) {
            // Keep the tool active if user tries to uncheck the active tool without picking another
            bool any_active = move_btn.active || line_btn.active || arrow_btn.active ||
                              rect_btn.active || circle_btn.active || redact_btn.active || text_btn.active;
            if (!any_active) {
                is_updating_tools = true;
                active_btn.active = true;
                is_updating_tools = false;
            }
            return;
        }

        is_updating_tools = true;
        if (active_btn != move_btn && move_btn.active) move_btn.active = false;
        if (active_btn != line_btn && line_btn.active) line_btn.active = false;
        if (active_btn != arrow_btn && arrow_btn.active) arrow_btn.active = false;
        if (active_btn != rect_btn && rect_btn.active) rect_btn.active = false;
        if (active_btn != circle_btn && circle_btn.active) circle_btn.active = false;
        if (active_btn != redact_btn && redact_btn.active) redact_btn.active = false;
        if (active_btn != text_btn && text_btn.active) text_btn.active = false;
        is_updating_tools = false;

        var root = active_btn.get_root ();
        if (root != null && root.get_focus () != null) {
            root.set_focus (null);
        }

        if (canvas != null) {
            canvas.current_tool = tool;
        }

        config_manager.active_tool = get_active_tool_name ();
        config_manager.save ();
    }

    public string get_active_tool_name () {
        if (move_btn.active) return "move";
        if (line_btn.active) return "line";
        if (rect_btn.active) return "rectangle";
        if (circle_btn.active) return "circle";
        if (redact_btn.active) return "redact";
        if (text_btn.active) return "text";
        return "arrow";
    }

    public void select_tool_by_name (string name) {
        is_updating_tools = true;
        move_btn.active = (name == "move");
        line_btn.active = (name == "line");
        arrow_btn.active = (name == "arrow");
        rect_btn.active = (name == "rectangle");
        circle_btn.active = (name == "circle");
        redact_btn.active = (name == "redact");
        text_btn.active = (name == "text");

        if (!move_btn.active && !line_btn.active && !arrow_btn.active && !rect_btn.active && !circle_btn.active && !redact_btn.active && !text_btn.active) {
            arrow_btn.active = true;
        }
        is_updating_tools = false;

        apply_active_tool_to_canvas ();
    }

    public void apply_active_tool_to_canvas () {
        if (canvas == null) return;
        if (move_btn.active) canvas.current_tool = ToolType.MOVE;
        else if (line_btn.active) canvas.current_tool = ToolType.LINE;
        else if (arrow_btn.active) canvas.current_tool = ToolType.ARROW;
        else if (rect_btn.active) canvas.current_tool = ToolType.RECTANGLE;
        else if (circle_btn.active) canvas.current_tool = ToolType.CIRCLE;
        else if (redact_btn.active) canvas.current_tool = ToolType.REDACT;
        else if (text_btn.active) canvas.current_tool = ToolType.TEXT;
        else {
            arrow_btn.active = true;
            canvas.current_tool = ToolType.ARROW;
        }
    }

    public void prompt_delete_shape_dialog (AnnotationItem item) {
        string shape_name = "element";
        switch (item.tool_type) {
            case ToolType.LINE:
                shape_name = "line";
                break;
            case ToolType.ARROW:
                shape_name = "arrow";
                break;
            case ToolType.RECTANGLE:
                shape_name = "rectangle";
                break;
            case ToolType.CIRCLE:
                shape_name = "circle";
                break;
            case ToolType.TEXT:
                shape_name = "text";
                break;
            default:
                shape_name = "element";
                break;
        }

        var dialog = new Adw.AlertDialog (
            "Delete Element",
            "Are you sure you want to delete this %s?".printf (shape_name)
        );
        dialog.add_response ("cancel", "Cancel");
        dialog.add_response ("delete", "Delete");
        dialog.set_response_appearance ("delete", Adw.ResponseAppearance.DESTRUCTIVE);
        dialog.set_default_response ("cancel");
        dialog.set_close_response ("cancel");

        dialog.choose.begin (parent_window, null, (obj, res) => {
            var resp = dialog.choose.end (res);
            if (resp == "delete") {
                canvas.remove_shape (item);
            }
        });
    }

    public void prompt_text_dialog (double ix, double iy, AnnotationItem? existing_item) {
        string title = existing_item != null ? "Edit Text" : "Insert Text";
        string heading = existing_item != null ? "Modify annotation text and formatting:" : "Enter multiline text and choose formatting:";
        var dialog = new Adw.AlertDialog (title, heading);

        var content_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 10);
        content_box.margin_top = 4;
        content_box.margin_bottom = 4;
        content_box.margin_start = 4;
        content_box.margin_end = 4;

        var scrolled = new Gtk.ScrolledWindow ();
        scrolled.min_content_width = 360;
        scrolled.min_content_height = 120;
        scrolled.max_content_height = 240;

        var text_view = new Gtk.TextView ();
        text_view.wrap_mode = Gtk.WrapMode.WORD_CHAR;
        if (existing_item != null) {
            text_view.buffer.text = existing_item.text;
        }
        scrolled.set_child (text_view);
        content_box.append (scrolled);

        // Options row 1: Font Picker
        var font_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
        font_box.hexpand = true;
        var font_label = new Gtk.Label ("Font:");
        font_box.append (font_label);

        var font_dialog = new Gtk.FontDialog ();
        var font_btn = new Gtk.FontDialogButton (font_dialog);
        font_btn.hexpand = true;
        double cur_scale = canvas != null ? canvas.get_current_scale () : 1.0;
        string initial_font;
        if (existing_item != null) {
            // Existing item stores font in image coordinates; scale down to screen points for the dialog
            initial_font = AnnotationItem.scale_font_desc (existing_item.font_desc, cur_scale);
        } else {
            // New item: use user's desired screen font size from config
            initial_font = config_manager.font_desc;
        }
        font_btn.font_desc = Pango.FontDescription.from_string (initial_font);
        font_btn.tooltip_text = "Choose Font Family & Size";
        font_box.append (font_btn);
        content_box.append (font_box);

        // Options row 2: Text Color Picker + Text Background Color Picker
        var colors_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 16);
        colors_box.halign = Gtk.Align.START;

        // Text Color Picker
        var fg_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
        var fg_label = new Gtk.Label ("Text Color:");
        fg_box.append (fg_label);

        var fg_color_dialog = new Gtk.ColorDialog ();
        fg_color_dialog.with_alpha = false;
        var text_fg_color_btn = new Gtk.ColorDialogButton (fg_color_dialog);
        Gdk.RGBA initial_fg = {};
        if (existing_item != null) {
            initial_fg = existing_item.stroke_color;
        } else {
            if (!initial_fg.parse (config_manager.text_color)) {
                initial_fg = Gdk.RGBA () { red = 1.0f, green = 0.0f, blue = 0.0f, alpha = 1.0f };
            }
        }
        text_fg_color_btn.set_rgba (initial_fg);
        text_fg_color_btn.tooltip_text = "Choose Text Color";
        fg_box.append (text_fg_color_btn);
        colors_box.append (fg_box);

        // Background Color Picker (with alpha)
        var bg_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
        var bg_label = new Gtk.Label ("Background:");
        bg_box.append (bg_label);

        var bg_color_dialog = new Gtk.ColorDialog ();
        bg_color_dialog.with_alpha = true;
        var text_bg_color_btn = new Gtk.ColorDialogButton (bg_color_dialog);
        Gdk.RGBA initial_bg = {};
        if (existing_item != null) {
            initial_bg = existing_item.bg_color;
        } else {
            if (!initial_bg.parse (config_manager.text_bg_color)) {
                initial_bg = Gdk.RGBA () { red = 0.0f, green = 0.0f, blue = 0.0f, alpha = 0.0f };
            }
        }
        text_bg_color_btn.set_rgba (initial_bg);
        text_bg_color_btn.tooltip_text = "Text Background Color (with transparency)";
        bg_box.append (text_bg_color_btn);
        colors_box.append (bg_box);

        content_box.append (colors_box);

        dialog.set_extra_child (content_box);
        dialog.add_response ("cancel", "Cancel");
        dialog.add_response ("ok", existing_item != null ? "Save" : "Add Text");
        dialog.set_response_appearance ("ok", Adw.ResponseAppearance.SUGGESTED);
        dialog.set_default_response ("ok");
        dialog.set_close_response ("cancel");

        dialog.choose.begin (parent_window, null, (obj, res) => {
            var resp = dialog.choose.end (res);
            if (resp == "ok") {
                Gtk.TextIter start_iter, end_iter;
                text_view.buffer.get_bounds (out start_iter, out end_iter);
                string txt = text_view.buffer.get_text (start_iter, end_iter, false);

                string selected_font = "Sans Bold 20";
                if (font_btn.font_desc != null) {
                    selected_font = font_btn.font_desc.to_string ();
                }

                Gdk.RGBA selected_fg = { 1.0f, 0.0f, 0.0f, 1.0f };
                unowned Gdk.RGBA? cfg = text_fg_color_btn.get_rgba ();
                if (cfg != null) {
                    selected_fg = cfg;
                }

                Gdk.RGBA selected_bg = { 0.0f, 0.0f, 0.0f, 0.0f };
                unowned Gdk.RGBA? cbg = text_bg_color_btn.get_rgba ();
                if (cbg != null) {
                    selected_bg = cbg;
                }

                // Persist screen-space choices into config_manager
                config_manager.font_desc = selected_font;
                config_manager.text_color = selected_fg.to_string ();
                config_manager.text_bg_color = selected_bg.to_string ();
                config_manager.save ();

                // Convert screen-space font size to image-space for storage on canvas
                double s = canvas != null ? canvas.get_current_scale () : 1.0;
                string image_font_desc = AnnotationItem.scale_font_desc (selected_font, 1.0 / s);

                // Also update canvas text defaults
                canvas.font_desc = image_font_desc;
                canvas.text_color = selected_fg;
                canvas.text_bg_color = selected_bg;

                if (txt.strip () != "") {
                    canvas.add_or_update_text (txt, ix, iy, existing_item, image_font_desc, selected_fg, selected_bg);
                }
            }
        });
    }
}
