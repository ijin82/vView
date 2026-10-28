/* properties_view.vala - Image metadata and properties panel for vView */

public class ImageMetadata : GLib.Object {
    public string file_name = "";
    public string folder_path = "";
    public string full_path = "";
    public string format_name = "";
    public string mime_type = "";
    public int64 file_size_bytes = 0;
    public string file_size_str = "";

    // Real image dimensions
    public int width = 0;
    public int height = 0;
    public string resolution_str = "";
    public string megapixels_str = "";
    public string color_depth_str = "";

    // Dates
    public string modified_str = "";
    public string created_str = "";

    // Camera / EXIF (optional)
    public bool has_exif = false;
    public string? camera_model = null;
    public string? lens_model = null;
    public string? date_taken = null;
    public string? exposure_time = null;
    public string? f_number = null;
    public string? iso_speed = null;
    public string? focal_length = null;
    public string? flash = null;
    public string? gps_coords = null;

    public static ImageMetadata load_from (string path, Gdk.Pixbuf? pixbuf) {
        var meta = new ImageMetadata ();
        meta.full_path = path;
        meta.file_name = GLib.Path.get_basename (path);
        meta.folder_path = GLib.Path.get_dirname (path);

        // 1. Pixbuf dimensions (real resolution)
        if (pixbuf != null) {
            meta.width = pixbuf.width;
            meta.height = pixbuf.height;
            double mp = (double) (meta.width * meta.height) / 1000000.0;
            if (mp >= 0.1) {
                meta.megapixels_str = " (%.1f MP)".printf (mp);
            }
            meta.resolution_str = "%d × %d px%s".printf (meta.width, meta.height, meta.megapixels_str);

            int bits = pixbuf.get_bits_per_sample ();
            int channels = pixbuf.get_n_channels ();
            bool alpha = pixbuf.get_has_alpha ();
            meta.color_depth_str = "%d-bit %s%s".printf (
                bits * channels,
                alpha ? "RGBA" : "RGB",
                alpha ? " (Transparent)" : ""
            );
        }

        // 2. Query file information via GIO
        var file = GLib.File.new_for_path (path);
        try {
            var info = file.query_info (
                "standard::*,time::*",
                GLib.FileQueryInfoFlags.NONE,
                null
            );

            meta.file_size_bytes = info.get_size ();
            string formatted_size = GLib.format_size (meta.file_size_bytes);
            meta.file_size_str = "%s (%s bytes)".printf (formatted_size, meta.file_size_bytes.to_string ());

            meta.mime_type = info.get_content_type ();
            if (meta.mime_type != null && meta.mime_type.length > 0) {
                string desc = GLib.ContentType.get_description (meta.mime_type);
                if (desc != null && desc.length > 0) {
                    meta.format_name = "%s (%s)".printf (desc, meta.mime_type);
                } else {
                    meta.format_name = meta.mime_type;
                }
            } else {
                string ext = meta.file_name.last_index_of (".") >= 0 ? meta.file_name.substring (meta.file_name.last_index_of (".") + 1).up () : "Image";
                meta.format_name = "%s image".printf (ext);
            }

            var mod_dt = info.get_modification_date_time ();
            if (mod_dt != null) {
                meta.modified_str = mod_dt.format ("%Y-%m-%d  %H:%M:%S");
            }

            var cr_dt = info.get_creation_date_time ();
            if (cr_dt != null) {
                meta.created_str = cr_dt.format ("%Y-%m-%d  %H:%M:%S");
            }
        } catch (Error e) {
            // Fallback to basic file info
            meta.format_name = "Image";
            meta.file_size_str = "Unknown";
        }

        // 3. Extract EXIF for JPEG files if available
        meta.parse_jpeg_exif (path);

        return meta;
    }

    private void parse_jpeg_exif (string path) {
        var file = GLib.File.new_for_path (path);
        uint8[] buffer = new uint8[65536];
        size_t bytes_read = 0;

        try {
            var stream = file.read (null);
            stream.read_all (buffer, out bytes_read, null);
        } catch (Error e) {
            return;
        }

        if (bytes_read < 14 || buffer[0] != 0xFF || buffer[1] != 0xD8) {
            return;
        }

        size_t pos = 2;
        while (pos + 4 <= bytes_read) {
            if (buffer[pos] != 0xFF) break;
            uint8 marker = buffer[pos + 1];
            if (marker == 0xD8 || marker == 0x01) {
                pos += 2;
                continue;
            }
            if (marker == 0xDA || marker == 0xD9) {
                break;
            }

            uint length = ((uint) buffer[pos + 2] << 8) | (uint) buffer[pos + 3];
            if (pos + 2 + length > bytes_read) break;

            // Marker APP1 (0xE1) with Exif\0\0 header
            if (marker == 0xE1 && length >= 14) {
                if (buffer[pos + 4] == 'E' && buffer[pos + 5] == 'x' &&
                    buffer[pos + 6] == 'i' && buffer[pos + 7] == 'f' &&
                    buffer[pos + 8] == 0 && buffer[pos + 9] == 0) {
                    size_t tiff_offset = pos + 10;
                    size_t tiff_len = 2 + length - 10;
                    parse_tiff_header (buffer, tiff_offset, tiff_len);
                    break;
                }
            }

            pos += 2 + length;
        }
    }

    private uint16 read_u16 (uint8[] data, size_t off, bool le) {
        if (off + 2 > data.length) return 0;
        return le ? (uint16) (data[off] | (data[off + 1] << 8)) :
                    (uint16) ((data[off] << 8) | data[off + 1]);
    }

    private uint32 read_u32 (uint8[] data, size_t off, bool le) {
        if (off + 4 > data.length) return 0;
        return le ? (uint32) (data[off] | (data[off + 1] << 8) | (data[off + 2] << 16) | (data[off + 3] << 24)) :
                    (uint32) ((data[off] << 24) | (data[off + 1] << 16) | (data[off + 2] << 8) | data[off + 3]);
    }

    private string read_ascii (uint8[] data, size_t off, size_t len) {
        if (off >= data.length) return "";
        size_t actual_len = size_t.min (len, data.length - off);
        var sb = new StringBuilder ();
        for (size_t i = 0; i < actual_len; i++) {
            char c = (char) data[off + i];
            if (c == '\0') break;
            if (c >= 32 && c <= 126) {
                sb.append_c (c);
            }
        }
        return sb.str.strip ();
    }

    private void parse_tiff_header (uint8[] data, size_t tiff_start, size_t tiff_len) {
        if (tiff_len < 8) return;
        bool le = (data[tiff_start] == 'I' && data[tiff_start + 1] == 'I');
        bool be = (data[tiff_start] == 'M' && data[tiff_start + 1] == 'M');
        if (!le && !be) return;

        uint16 magic = read_u16 (data, tiff_start + 2, le);
        if (magic != 42) return;

        uint32 ifd0_offset = read_u32 (data, tiff_start + 4, le);
        if (ifd0_offset >= tiff_len) return;

        string? make = null;
        string? model = null;
        uint32 exif_ifd_offset = 0;
        uint32 gps_ifd_offset = 0;

        parse_ifd (data, tiff_start, tiff_start + ifd0_offset, le, (tag, type_val, count, val_off, val_inline) => {
            if (tag == 0x010F) { // Make
                make = read_ascii (data, val_off, count);
            } else if (tag == 0x0110) { // Model
                model = read_ascii (data, val_off, count);
            } else if (tag == 0x0132 && date_taken == null) { // DateTime
                date_taken = read_ascii (data, val_off, count);
            } else if (tag == 0x8769) { // ExifIFD Offset
                exif_ifd_offset = val_inline;
            } else if (tag == 0x8825) { // GPS IFD Offset
                gps_ifd_offset = val_inline;
            }
        });

        if (make != null || model != null) {
            has_exif = true;
            if (make != null && model != null) {
                if (model.has_prefix (make)) {
                    camera_model = model;
                } else {
                    camera_model = "%s, %s".printf (make, model);
                }
            } else {
                camera_model = (model != null) ? model : make;
            }
        }

        // Parse Exif sub-IFD
        if (exif_ifd_offset > 0 && exif_ifd_offset < tiff_len) {
            parse_ifd (data, tiff_start, tiff_start + exif_ifd_offset, le, (tag, type_val, count, val_off, val_inline) => {
                has_exif = true;
                if (tag == 0x829A) { // ExposureTime (rational)
                    uint32 num = read_u32 (data, val_off, le);
                    uint32 den = read_u32 (data, val_off + 4, le);
                    if (den > 0 && num > 0) {
                        if (num < den && den % num == 0) {
                            exposure_time = "1/%u s".printf (den / num);
                        } else if (num < den) {
                            exposure_time = "%.3f s".printf ((double) num / den);
                        } else {
                            exposure_time = "%.1f s".printf ((double) num / den);
                        }
                    }
                } else if (tag == 0x829D) { // FNumber (rational)
                    uint32 num = read_u32 (data, val_off, le);
                    uint32 den = read_u32 (data, val_off + 4, le);
                    if (den > 0) {
                        double f = (double) num / den;
                        f_number = "f/%.1f".printf (f);
                    }
                } else if (tag == 0x8827) { // ISO Speed
                    uint iso = (type_val == 3) ? (uint) read_u16 (data, val_off, le) : (uint) val_inline;
                    if (iso > 0) {
                        iso_speed = "ISO %u".printf (iso);
                    }
                } else if (tag == 0x9003) { // DateTimeOriginal
                    date_taken = read_ascii (data, val_off, count);
                } else if (tag == 0x920A) { // FocalLength (rational)
                    uint32 num = read_u32 (data, val_off, le);
                    uint32 den = read_u32 (data, val_off + 4, le);
                    if (den > 0) {
                        focal_length = "%.1f mm".printf ((double) num / den);
                    }
                } else if (tag == 0xA434) { // LensModel
                    lens_model = read_ascii (data, val_off, count);
                }
            });
        }
    }

    private delegate void IfdEntryCallback (uint16 tag, uint16 type_val, uint32 count, size_t val_offset, uint32 val_inline);

    private void parse_ifd (uint8[] data, size_t tiff_start, size_t ifd_pos, bool le, IfdEntryCallback cb) {
        if (ifd_pos + 2 > data.length) return;
        uint16 num_entries = read_u16 (data, ifd_pos, le);
        size_t cur = ifd_pos + 2;

        for (uint16 i = 0; i < num_entries; i++) {
            if (cur + 12 > data.length) break;
            uint16 tag = read_u16 (data, cur, le);
            uint16 type_val = read_u16 (data, cur + 2, le);
            uint32 count = read_u32 (data, cur + 4, le);

            size_t type_size = 1;
            if (type_val == 3) type_size = 2; // SHORT
            else if (type_val == 4 || type_val == 9) type_size = 4; // LONG / SLONG
            else if (type_val == 5 || type_val == 10) type_size = 8; // RATIONAL

            size_t total_size = (size_t) count * type_size;
            size_t val_offset;
            uint32 val_inline = read_u32 (data, cur + 8, le);
            if (total_size <= 4) {
                val_offset = cur + 8;
            } else {
                val_offset = tiff_start + val_inline;
            }

            cb (tag, type_val, count, val_offset, val_inline);
            cur += 12;
        }
    }
}

public class PropertiesView : Gtk.Box {
    public signal void close_requested ();

    private Adw.ActionRow folder_row;
    private Adw.ActionRow name_row;
    private Adw.ActionRow path_row;

    private Adw.ActionRow size_row;
    private Adw.ActionRow format_row;
    private Adw.ActionRow file_size_row;
    private Adw.ActionRow color_row;

    private Adw.PreferencesGroup dates_group;
    private Adw.ActionRow modified_row;
    private Adw.ActionRow created_row;

    private Adw.PreferencesGroup camera_group;
    private Adw.ActionRow camera_row;
    private Adw.ActionRow lens_row;
    private Adw.ActionRow date_taken_row;
    private Adw.ActionRow exposure_row;
    private Adw.ActionRow aperture_row;
    private Adw.ActionRow iso_row;
    private Adw.ActionRow focal_row;

    private string current_file_path = "";
    private string current_folder_path = "";

    public PropertiesView () {
        GLib.Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);

        width_request = 360;
        hexpand = false;
        vexpand = true;
        add_css_class ("view");
        add_css_class ("background");

        // Top Header
        var header_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
        header_box.margin_start = 16;
        header_box.margin_end = 12;
        header_box.margin_top = 12;
        header_box.margin_bottom = 8;

        var title_label = new Gtk.Label ("Image Properties");
        title_label.add_css_class ("title-3");
        title_label.add_css_class ("heading");
        title_label.hexpand = true;
        title_label.halign = Gtk.Align.START;
        header_box.append (title_label);

        var close_btn = new Gtk.Button.from_icon_name ("window-close-symbolic");
        close_btn.tooltip_text = "Close Panel (Alt+Enter)";
        close_btn.add_css_class ("flat");
        close_btn.add_css_class ("circular");
        close_btn.clicked.connect (() => {
            close_requested ();
        });
        header_box.append (close_btn);
        append (header_box);

        var scrolled = new Gtk.ScrolledWindow ();
        scrolled.vexpand = true;
        scrolled.hexpand = false;
        scrolled.hscrollbar_policy = Gtk.PolicyType.NEVER;
        scrolled.propagate_natural_width = false;

        var content_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 16);
        content_box.margin_start = 14;
        content_box.margin_end = 14;
        content_box.margin_top = 8;
        content_box.margin_bottom = 20;

        // Group 1: Image Details (Real resolution prioritized)
        var image_group = new Adw.PreferencesGroup ();
        image_group.title = "Image";

        size_row = new Adw.ActionRow ();
        size_row.title = "Resolution";
        size_row.subtitle = "—";
        size_row.subtitle_selectable = true;
        image_group.add (size_row);

        format_row = new Adw.ActionRow ();
        format_row.title = "Format";
        format_row.subtitle = "—";
        format_row.subtitle_selectable = true;
        image_group.add (format_row);

        file_size_row = new Adw.ActionRow ();
        file_size_row.title = "File Size";
        file_size_row.subtitle = "—";
        file_size_row.subtitle_selectable = true;
        image_group.add (file_size_row);

        color_row = new Adw.ActionRow ();
        color_row.title = "Color Depth";
        color_row.subtitle = "—";
        color_row.subtitle_selectable = true;
        image_group.add (color_row);

        content_box.append (image_group);

        // Group 2: File Info
        var file_group = new Adw.PreferencesGroup ();
        file_group.title = "File";

        name_row = new Adw.ActionRow ();
        name_row.title = "File Name";
        name_row.subtitle = "—";
        name_row.subtitle_selectable = true;
        file_group.add (name_row);

        folder_row = new Adw.ActionRow ();
        folder_row.title = "Folder";
        folder_row.subtitle = "—";
        folder_row.subtitle_selectable = true;

        var open_folder_btn = new Gtk.Button.from_icon_name ("folder-open-symbolic");
        open_folder_btn.tooltip_text = "Open Containing Folder";
        open_folder_btn.valign = Gtk.Align.CENTER;
        open_folder_btn.add_css_class ("flat");
        open_folder_btn.clicked.connect (open_containing_folder);
        folder_row.add_suffix (open_folder_btn);
        file_group.add (folder_row);

        path_row = new Adw.ActionRow ();
        path_row.title = "Full Path";
        path_row.subtitle = "—";
        path_row.subtitle_selectable = true;

        var copy_path_btn = new Gtk.Button.from_icon_name ("edit-copy-symbolic");
        copy_path_btn.tooltip_text = "Copy Path to Clipboard";
        copy_path_btn.valign = Gtk.Align.CENTER;
        copy_path_btn.add_css_class ("flat");
        copy_path_btn.clicked.connect (copy_full_path);
        path_row.add_suffix (copy_path_btn);
        file_group.add (path_row);

        content_box.append (file_group);

        // Group 3: Dates
        dates_group = new Adw.PreferencesGroup ();
        dates_group.title = "Dates";

        modified_row = new Adw.ActionRow ();
        modified_row.title = "Modified";
        modified_row.subtitle = "—";
        modified_row.subtitle_selectable = true;
        dates_group.add (modified_row);

        created_row = new Adw.ActionRow ();
        created_row.title = "Created";
        created_row.subtitle = "—";
        created_row.subtitle_selectable = true;
        dates_group.add (created_row);

        content_box.append (dates_group);

        // Group 4: Camera & EXIF (shown when EXIF available)
        camera_group = new Adw.PreferencesGroup ();
        camera_group.title = "Camera &amp; Details";

        camera_row = new Adw.ActionRow ();
        camera_row.title = "Camera";
        camera_row.subtitle_selectable = true;
        camera_group.add (camera_row);

        lens_row = new Adw.ActionRow ();
        lens_row.title = "Lens";
        lens_row.subtitle_selectable = true;
        camera_group.add (lens_row);

        date_taken_row = new Adw.ActionRow ();
        date_taken_row.title = "Date Taken";
        date_taken_row.subtitle_selectable = true;
        camera_group.add (date_taken_row);

        exposure_row = new Adw.ActionRow ();
        exposure_row.title = "Exposure";
        exposure_row.subtitle_selectable = true;
        camera_group.add (exposure_row);

        aperture_row = new Adw.ActionRow ();
        aperture_row.title = "Aperture";
        aperture_row.subtitle_selectable = true;
        camera_group.add (aperture_row);

        iso_row = new Adw.ActionRow ();
        iso_row.title = "ISO Sensitivity";
        iso_row.subtitle_selectable = true;
        camera_group.add (iso_row);

        focal_row = new Adw.ActionRow ();
        focal_row.title = "Focal Length";
        focal_row.subtitle_selectable = true;
        camera_group.add (focal_row);

        content_box.append (camera_group);
        camera_group.visible = false;

        scrolled.set_child (content_box);
        append (scrolled);
    }

    public void update_metadata (string? path, Gdk.Pixbuf? pixbuf) {
        if (path == null || path.length == 0) {
            current_file_path = "";
            current_folder_path = "";
            name_row.subtitle = "No image loaded";
            folder_row.subtitle = "—";
            path_row.subtitle = "—";
            size_row.subtitle = "—";
            format_row.subtitle = "—";
            file_size_row.subtitle = "—";
            color_row.subtitle = "—";
            modified_row.subtitle = "—";
            created_row.subtitle = "—";
            camera_group.visible = false;
            return;
        }

        current_file_path = path;
        var meta = ImageMetadata.load_from (path, pixbuf);
        current_folder_path = meta.folder_path;

        name_row.subtitle = meta.file_name;
        folder_row.subtitle = meta.folder_path;
        path_row.subtitle = meta.full_path;

        size_row.subtitle = meta.resolution_str;
        format_row.subtitle = meta.format_name;
        file_size_row.subtitle = meta.file_size_str;
        color_row.subtitle = meta.color_depth_str;

        modified_row.subtitle = meta.modified_str.length > 0 ? meta.modified_str : "—";
        created_row.subtitle = meta.created_str.length > 0 ? meta.created_str : "—";
        created_row.visible = (meta.created_str.length > 0);

        if (meta.has_exif) {
            camera_group.visible = true;

            camera_row.visible = (meta.camera_model != null);
            if (meta.camera_model != null) camera_row.subtitle = meta.camera_model;

            lens_row.visible = (meta.lens_model != null);
            if (meta.lens_model != null) lens_row.subtitle = meta.lens_model;

            date_taken_row.visible = (meta.date_taken != null);
            if (meta.date_taken != null) date_taken_row.subtitle = meta.date_taken;

            exposure_row.visible = (meta.exposure_time != null);
            if (meta.exposure_time != null) exposure_row.subtitle = meta.exposure_time;

            aperture_row.visible = (meta.f_number != null);
            if (meta.f_number != null) aperture_row.subtitle = meta.f_number;

            iso_row.visible = (meta.iso_speed != null);
            if (meta.iso_speed != null) iso_row.subtitle = meta.iso_speed;

            focal_row.visible = (meta.focal_length != null);
            if (meta.focal_length != null) focal_row.subtitle = meta.focal_length;
        } else {
            camera_group.visible = false;
        }
    }

    private void open_containing_folder () {
        if (current_folder_path.length == 0) return;
        try {
            string uri = GLib.Filename.to_uri (current_folder_path);
            GLib.AppInfo.launch_default_for_uri (uri, null);
        } catch (Error e) {
            warning ("Could not open directory '%s': %s", current_folder_path, e.message);
        }
    }

    private void copy_full_path () {
        if (current_file_path.length == 0) return;
        var display = Gdk.Display.get_default ();
        if (display != null) {
            display.get_clipboard ().set_text (current_file_path);
        }
    }
}
