[CCode (cheader_filename = "scanner.h")]
public class ScanDevice : GLib.Object
{
    public ScanDevice ();
    public string name;
    public string label;
}

[CCode (cheader_filename = "book.h")]
public class Book : GLib.Object
{
    public signal void page_added (Page page);
    public signal void page_removed (Page page);
    public signal void cleared ();
    public signal void reordered ();
    public Book ();
    public int get_n_pages ();
    public Page get_page (int page_num);
    public Page append_page (int width, int height, int dpi, ScanDirection direction);
    public void delete_page (Page page);
    public void save (string format, GLib.File file) throws GLib.Error;
    public int get_page_index (Page page);
    public bool get_needs_saving ();
    public void move_page (Page page, int index);
    public void set_needs_saving (bool needs_saving);
    public void clear ();
}

[CCode (cheader_filename = "page.h")]
public class Page : GLib.Object
{
    public signal void size_changed ();
    public signal void scan_direction_changed ();
    public signal void crop_changed ();
    public signal void pixels_changed ();
    public signal void scan_line_changed ();
    public bool has_data ();
    public void start ();
    public ScanDirection get_scan_direction ();
    public int get_width ();
    public int get_height ();
    public int get_scan_width ();
    public int get_scan_height ();
    public int get_depth ();
    public int get_n_channels ();
    [CCode (array_length = false)]
    public uchar[] get_pixels ();
    public int get_rowstride ();
    public int get_dpi ();
    public bool has_crop ();
    public string? get_named_crop ();
    public void set_named_crop (string name);
    public void set_custom_crop (int width, int height);
    public void move_crop (int x, int y);
    public void get_crop (out int cx, out int cy, out int cw, out int ch);
    public void set_page_info (ScanPageInfo info);
    public void set_color_profile (string profile);
    public void parse_scan_line (ScanLine line);
    public void finish ();
    public void rotate_crop ();
    public bool is_landscape ();
    public Gdk.Pixbuf get_image (bool apply_crop);
    public void save (string format, GLib.File file) throws GLib.Error;
    public void set_no_crop ();
    public void rotate_left ();
    public void rotate_right ();
    public bool is_scanning ();
    public int get_scan_line ();
}

[CCode (cheader_filename = "scanner.h")]
public class Scanner : GLib.Object
{
    public signal void update_devices (GLib.List<ScanDevice> devices);
    public signal void request_authorization (string resource);
    public signal void expect_page ();
    public signal void got_page_info (ScanPageInfo info);
    public signal void got_line (ScanLine line);
    public signal void page_done ();
    public signal void document_done ();
    public signal void scan_failed (GLib.Error error);
    public signal void scanning_changed ();

    public Scanner ();
    public void authorize (string username, string password);
    public bool is_scanning ();
    public void scan (string device, ScanOptions options);
    public void redetect ();
    public void start ();
    public void cancel ();
    public void free ();
}

[CCode (cheader_filename = "scanner.h")]
public enum ScanMode
{
    DEFAULT,
    COLOR,
    GRAY,
    LINEART
}

[CCode (cprefix = "SCAN_", cheader_filename = "scanner.h")]
public enum ScanType
{
    SINGLE,
    ADF_FRONT,
    ADF_BACK,
    ADF_BOTH
}

[CCode (cheader_filename = "scanner.h")]
public class ScanOptions : GLib.Object
{
   public ScanOptions();
   public int dpi;
   public ScanMode scan_mode;
   public int depth;
   public ScanType type;
   public int paper_width;
   public int paper_height;
}

[CCode (cheader_filename = "scanner.h")]
public class ScanLine
{
}

[CCode (cheader_filename = "scanner.h")]
public class ScanPageInfo
{
    public string device;
    public int width;
    public int height;
    public int depth;
}

[CCode (cprefix = "", cheader_filename = "page.h")]
public enum ScanDirection
{
    TOP_TO_BOTTOM,
    BOTTOM_TO_TOP,
    LEFT_TO_RIGHT,
    RIGHT_TO_LEFT
}
