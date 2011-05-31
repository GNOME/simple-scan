[CCode (cheader_filename = "scanner.h")]
public class ScanDevice : GLib.Object
{
    public ScanDevice ();
    public string name;
    public string label;
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
    public int number;
    public int n_lines;
    public uchar[] data;
    public int data_length;
}

[CCode (cheader_filename = "scanner.h")]
public class ScanPageInfo
{
    public string device;
    public int width;
    public int height;
    public int depth;
    public int dpi;
    public int n_channels;
}

// FIXME: Buf reference
public delegate bool PixbufSaveFunc (uint8[] buf, out GLib.Error error);
bool gdk_pixbuf_save_to_callbackv (Gdk.Pixbuf pixbuf, PixbufSaveFunc save_func, string type, [CCode (array_length = false)] string[] option_keys, [CCode (array_length = false)] string[] option_values) throws GLib.Error;
