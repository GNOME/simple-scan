public class ScanDevice
{
    public ScanDevice ();
    public string name;
    public string label;
}

[CCode (cheader_filename = "book.h")]
public class Book : GLib.Object
{
    public int get_n_pages ();
    public Page get_page (int page_num);
    public Page append_page (int width, int height, int dpi, ScanDirection direction);
    public void delete_page (Page page);
    public void save (string format, GLib.File file) throws GLib.Error;
}

[CCode (cheader_filename = "page.h")]
public class Page : GLib.Object
{
    public bool has_data ();
    public void start ();
    public ScanDirection get_scan_direction ();
    public int get_width ();
    public int get_height ();
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
    public void save (string format, GLib.File file) throws GLib.Error;
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

public enum ScanMode
{
    DEFAULT,
    COLOR,
    GRAY,
    LINEART
}

public class ScanOptions
{
   public ScanMode scan_mode;
   public int dpi;
}

public class ScanLine
{
}

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
    TOP_TO_BOTTOM
}
