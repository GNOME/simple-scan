// Workaround for https://bugzilla.gnome.org/show_bug.cgi?id=652344
// Fixed in 0.12.1
[CCode (lower_case_cprefix = "", cheader_filename = "zlib.h")]
namespace ZLibFixes {
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
