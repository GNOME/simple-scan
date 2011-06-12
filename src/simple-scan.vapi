// FIXME: Buf reference
public delegate bool PixbufSaveFunc (uint8[] buf, out GLib.Error error);
bool gdk_pixbuf_save_to_callbackv (Gdk.Pixbuf pixbuf, PixbufSaveFunc save_func, string type, [CCode (array_length = false)] string[] option_keys, [CCode (array_length = false)] string[] option_values) throws GLib.Error;

// Workaround for https://bugzilla.gnome.org/show_bug.cgi?id=652344
[CCode (lower_case_cprefix = "", cheader_filename = "zlib.h")]
namespace ZLib2 {
    [CCode (cname = "z_stream", destroy_function = "deflateEnd")]
    public struct Stream {
        [CCode (array_length_cname = "avail_in", array_length_type = "ulong")]
        public unowned uint8[] next_in;
        public uint avail_in;
        [CCode (array_length_cname = "avail_out", array_length_type = "ulong")]
        public unowned uint8[] next_out;
        public uint avail_out;
    }
    [CCode (cname = "z_stream", destroy_function = "deflateEnd")]
    public struct DeflateStream : Stream {
        [CCode (cname = "deflateInit")]
        public DeflateStream (int level);
        [CCode (cname = "deflate")]
        public int deflate (int flush);
    }
}
