public class ConfigManager : GLib.Object {
    public int window_width { get; set; default = 1000; }
    public int window_height { get; set; default = 700; }
    public bool window_maximized { get; set; default = false; }
    public string active_tool { get; set; default = "arrow"; }
    public string draw_color { get; set; default = "rgb(255,0,0)"; }
    public string text_color { get; set; default = "rgb(255,0,0)"; }
    public string text_bg_color { get; set; default = "rgba(0,0,0,0)"; }
    public double line_width { get; set; default = 4.0; }
    public string font_desc { get; set; default = "Sans Bold 20"; }
    public bool edit_mode { get; set; default = false; }
    public bool is_ready_to_save { get; set; default = false; }

    public static string get_config_file_path () {
        return GLib.Path.build_filename (GLib.Environment.get_user_config_dir (), "vView", "config");
    }

    public void load () {
        var kf = new GLib.KeyFile ();
        var path = get_config_file_path ();

        try {
            kf.load_from_file (path, GLib.KeyFileFlags.NONE);
        } catch (Error e) {
            return;
        }

        try {
            int w = kf.get_integer ("Window", "width");
            int h = kf.get_integer ("Window", "height");
            if (w >= 300 && h >= 200) {
                window_width = w;
                window_height = h;
            }
        } catch (Error e) {}

        try {
            window_maximized = kf.get_boolean ("Window", "maximized");
        } catch (Error e) {}

        try {
            string t = kf.get_string ("Editor", "tool");
            if (t != null && t.strip () != "") {
                active_tool = t;
            }
        } catch (Error e) {}

        try {
            string c = kf.get_string ("Editor", "color");
            if (c != null && c.strip () != "") {
                draw_color = c;
            }
        } catch (Error e) {}

        try {
            string tc = kf.get_string ("Editor", "text_color");
            if (tc != null && tc.strip () != "") {
                text_color = tc;
            }
        } catch (Error e) {}

        try {
            string bg = kf.get_string ("Editor", "text_bg_color");
            if (bg != null && bg.strip () != "") {
                text_bg_color = bg;
            }
        } catch (Error e) {}

        try {
            double lw = kf.get_double ("Editor", "line_width");
            if (lw >= 1.0 && lw <= 50.0) {
                line_width = lw;
            }
        } catch (Error e) {}

        try {
            string fd = kf.get_string ("Editor", "font_desc");
            if (fd != null && fd.strip () != "") {
                font_desc = fd;
            }
        } catch (Error e) {}

        try {
            edit_mode = kf.get_boolean ("Editor", "edit_mode");
        } catch (Error e) {}
    }

    public void save () {
        if (!is_ready_to_save) return;
        var kf = new GLib.KeyFile ();
        var path = get_config_file_path ();

        try {
            kf.load_from_file (path, GLib.KeyFileFlags.NONE);
        } catch (Error e) {}

        kf.set_integer ("Window", "width", window_width);
        kf.set_integer ("Window", "height", window_height);
        kf.set_boolean ("Window", "maximized", window_maximized);

        kf.set_string ("Editor", "tool", active_tool);
        kf.set_string ("Editor", "color", draw_color);
        kf.set_string ("Editor", "text_color", text_color);
        kf.set_string ("Editor", "text_bg_color", text_bg_color);
        kf.set_double ("Editor", "line_width", line_width);
        kf.set_string ("Editor", "font_desc", font_desc);
        kf.set_boolean ("Editor", "edit_mode", edit_mode);

        try {
            string dir = GLib.Path.get_dirname (path);
            GLib.DirUtils.create_with_parents (dir, 0755);
            kf.save_to_file (path);
        } catch (Error e) {
            warning ("Failed to save config to '%s': %s", path, e.message);
        }
    }
}
