[CCode (cheader_filename = "jpeglib.h", cprefix = "jpeg_")]
namespace JPEG {
    [CCode (cprefix = "JCS_")]
    public enum ColorSpace
    {
        UNKNOWN,
        GRAYSCALE,
        RGB,
        YCbCr,
        CMYK,
        YCCK
    }

    public ErrorManager std_error (out ErrorManager err);

    [CCode (cname = "struct jpeg_compress_struct", cprefix = "jpeg_", destroy_function = "jpeg_destroy_compress")]
    public struct Compress
    {
        public DestinationManager* dest;
        public int image_width;
        public int image_height;
        public int input_components;
        public ColorSpace in_color_space;
        public ErrorManager* err;

        public void create_compress ();
        public void set_defaults ();
        public void start_compress (bool write_all_tables);
        public void write_scanlines ([CCode (array_length = false)] uint8*[] scanlines, int num_Lines);
        public void finish_compress ();
    }

    [CCode (cname = "struct jpeg_error_mgr")]
    public struct ErrorManager
    {
        [CCode (cname = "jpeg_std_error")]
        public ErrorManager* std_error ();
    }

    [CCode (has_target = false)]
    public delegate void InitDestinationFunc (Compress cinfo);
    [CCode (has_target = false)]
    public delegate bool EmptyOutputBufferFunc (Compress cinfo);
    [CCode (has_target = false)]
    public delegate void TermDestinationFunc (Compress cinfo);

    [CCode (cname = "struct jpeg_destination_mgr")]
    public struct DestinationManager
    {
        [CCode (array_length = false)]
        public unowned uint8[] next_output_byte;
        public int free_in_buffer;
        public InitDestinationFunc init_destination;
        public EmptyOutputBufferFunc empty_output_buffer;
        public TermDestinationFunc term_destination;
    }
}
