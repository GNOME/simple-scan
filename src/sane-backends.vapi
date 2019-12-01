[CCode (cprefix = "SANE_", lower_case_cprefix = "sane_", cheader_filename = "sane/sane.h")]
namespace Sane {
    [SimpleType]
    [BooleanType]
    public struct Bool
    {
    }

    [SimpleType]
    [IntegerType (rank = 9)]
    public struct Int
    {
    }

    [SimpleType]
    [IntegerType (rank = 9)]
    public struct Fixed
    {
    }

    [SimpleType]
    [IntegerType (rank = 9)]
    public struct Word
    {
    }

    [CCode (ref_function = "", unref_function = "")]
    public class Device
    {
        public string name;
        public string vendor;
        public string model;
        public string type;
    }

    public enum Status
    {
        GOOD,
        UNSUPPORTED,
        CANCELLED,
        DEVICE_BUSY,
        INVAL,
        EOF,
        JAMMED,
        NO_DOCS,
        COVER_OPEN,
        IO_ERROR,
        NO_MEM,
        ACCESS_DENIED
    }

    public static string status_to_string (Status status)
    {
        switch (status)
        {
        case Status.GOOD:
            return "SANE_STATUS_GOOD";
        case Status.UNSUPPORTED:
            return "SANE_STATUS_UNSUPPORTED";
        case Status.CANCELLED:
            return "SANE_STATUS_CANCELLED";
        case Status.DEVICE_BUSY:
            return "SANE_STATUS_DEVICE_BUSY";
        case Status.INVAL:
            return "SANE_STATUS_INVAL";
        case Status.EOF:
            return "SANE_STATUS_EOF";
        case Status.JAMMED:
            return "SANE_STATUS_JAMMED";
        case Status.NO_DOCS:
            return "SANE_STATUS_NO_DOCS";
        case Status.COVER_OPEN:
            return "SANE_STATUS_COVER_OPEN";
        case Status.IO_ERROR:
            return "SANE_STATUS_IO_ERROR";
        case Status.NO_MEM:
            return "SANE_STATUS_NO_MEM";
        case Status.ACCESS_DENIED:
            return "SANE_STATUS_ACCESS_DENIED";
        default:
            return "SANE_STATUS(%d)".printf (status);
        }
    }

    public enum Action
    {
        GET_VALUE,
        SET_VALUE,
        SET_AUTO
    }

    public enum Frame
    {
        GRAY,
        RGB,
        RED,
        GREEN,
        BLUE
    }

    public static string frame_to_string (Frame frame)
    {
        switch (frame)
        {
        case Frame.GRAY:
            return "SANE_FRAME_GRAY";
        case Frame.RGB:
            return "SANE_FRAME_RGB";
        case Frame.RED:
            return "SANE_FRAME_RED";
        case Frame.GREEN:
            return "SANE_FRAME_GREEN";
        case Frame.BLUE:
            return "SANE_FRAME_BLUE";
        default:
            return "SANE_FRAME(%d)".printf (frame);
        }
    }

    public struct Parameters
    {
        Frame format;
        bool last_frame;
        int bytes_per_line;
        int pixels_per_line;
        int lines;
        int depth;
    }

    [CCode (cname = "SANE_MAX_USERNAME_LEN")]
    public int MAX_USERNAME_LEN;

    [CCode (cname = "SANE_MAX_USERNAME_LEN")]
    public int MAX_PASSWORD_LEN;

    [CCode (cname = "SANE_Value_Type", cprefix = "SANE_TYPE_")]
    public enum ValueType
    {
        BOOL,
        INT,
        FIXED,
        STRING,
        BUTTON,
        GROUP
    }

    public enum Unit
    {
        NONE,
        PIXEL,
        BIT,
        MM,
        DPI,
        PERCENT,
        MICROSECOND
    }

    [CCode (cname = "SANE_Constraint_Type", cprefix = "SANE_CONSTRAINT_")]
    public enum ConstraintType
    {
        NONE,
        RANGE,
        WORD_LIST,
        STRING_LIST
    }

    public class Range
    {
        public Word min;
        public Word max;
        public Word quant;
    }

    [CCode (cprefix = "SANE_CAP_")]
    public enum Capability
    {
        SOFT_SELECT,
        HARD_SELECT,
        SOFT_DETECT,
        EMULATED,
        AUTOMATIC,
        INACTIVE,
        ADVANCED
    }

    [CCode (cname = "SANE_Option_Descriptor", ref_function = "", unref_function = "")]
    public class OptionDescriptor
    {
        public unowned string name;
        public unowned string title;
        public unowned string desc;
        public ValueType type;
        public Unit unit;
        public Int size;
        public Int cap;

        public ConstraintType constraint_type;
        [CCode (cname = "constraint.string_list", array_length = false, array_null_terminated = true)]
        public string[] string_list;
        [CCode (cname = "constraint.word_list", array_length = false)]
        public Word[] word_list;
        [CCode (cname = "constraint.range")]
        public Range range;
    }

    [CCode (type = "Int", cprefix = "SANE_INFO_")]
    public enum Info
    {
        INEXACT,
        RELOAD_OPTIONS,
        RELOAD_PARAMS
    }

    [SimpleType]
    public struct Handle
    {
    }

    [CCode (has_target = false)]
    public delegate void AuthCallback (string resource, [CCode (array_length = false)] char[] username, [CCode (array_length = false)] char[] password);

    [CCode (cname = "SANE_VERSION_MAJOR")]
    public int VERSION_MAJOR (Int code);
    [CCode (cname = "SANE_VERSION_MINOR")]
    public int VERSION_MINOR (Int code);
    [CCode (cname = "SANE_VERSION_BUILD")]
    public int VERSION_BUILD (Int code);

    [CCode (cname = "SANE_FIX")]
    public Fixed FIX (double d);
    [CCode (cname = "SANE_UNFIX")]
    public double UNFIX (Fixed w);

    [CCode (cname = "SANE_I18N")]
    public unowned string I18N (string value);

    public Status init (out Int version_code, AuthCallback callback);
    public void exit ();
    public Status get_devices ([CCode (array_length = false, null_terminated = true)] out unowned Device[] device_list, bool local_only);
    public unowned string strstatus (Status status);
    public Status open (string devicename, out Handle handle);
    public void close (Handle handle);
    public unowned OptionDescriptor? get_option_descriptor (Handle handle, Int option);
    public Status control_option (Handle handle, Int option, Action action, void *value, out Info? info = null);
    public Status get_parameters (Handle handle, out Parameters params);
    public Status start (Handle handle);
    public Status read (Handle handle, uint8* data, Int max_length, out Int length);
    public void cancel (Handle handle);
    public Status set_io_mode (Handle handle, bool non_blocking);
    public Status get_select_fd (Handle handle, out int fd);

    [CCode (cname = "SANE_NAME_STANDARD", cheader_filename = "sane/saneopts.h")]
    public static string NAME_STANDARD;
    [CCode (cname = "SANE_NAME_GEOMETRY", cheader_filename = "sane/saneopts.h")]
    public static string NAME_GEOMETRY;
    [CCode (cname = "SANE_NAME_ENHANCEMENT", cheader_filename = "sane/saneopts.h")]
    public static string NAME_ENHANCEMENT;
    [CCode (cname = "SANE_NAME_ADVANCED", cheader_filename = "sane/saneopts.h")]
    public static string NAME_ADVANCED;
    [CCode (cname = "SANE_NAME_SENSORS", cheader_filename = "sane/saneopts.h")]
    public static string NAME_SENSORS;
    [CCode (cname = "SANE_NAME_PREVIEW", cheader_filename = "sane/saneopts.h")]
    public static string NAME_PREVIEW;
    [CCode (cname = "SANE_NAME_GRAY_PREVIEW", cheader_filename = "sane/saneopts.h")]
    public static string NAME_GRAY_PREVIEW;
    [CCode (cname = "SANE_NAME_BIT_DEPTH", cheader_filename = "sane/saneopts.h")]
    public static string NAME_BIT_DEPTH;
    [CCode (cname = "SANE_NAME_SCAN_MODE", cheader_filename = "sane/saneopts.h")]
    public static string NAME_SCAN_MODE;
    [CCode (cname = "SANE_NAME_SCAN_SPEED", cheader_filename = "sane/saneopts.h")]
    public static string NAME_SCAN_SPEED;
    [CCode (cname = "SANE_NAME_SCAN_SOURCE", cheader_filename = "sane/saneopts.h")]
    public static string NAME_SCAN_SOURCE;
    [CCode (cname = "SANE_NAME_BACKTRACK", cheader_filename = "sane/saneopts.h")]
    public static string NAME_BACKTRACK;
    [CCode (cname = "SANE_NAME_SCAN_TL_X", cheader_filename = "sane/saneopts.h")]
    public static string NAME_SCAN_TL_X;
    [CCode (cname = "SANE_NAME_SCAN_TL_Y", cheader_filename = "sane/saneopts.h")]
    public static string NAME_SCAN_TL_Y;
    [CCode (cname = "SANE_NAME_SCAN_BR_X", cheader_filename = "sane/saneopts.h")]
    public static string NAME_SCAN_BR_X;
    [CCode (cname = "SANE_NAME_SCAN_BR_Y", cheader_filename = "sane/saneopts.h")]
    public static string NAME_SCAN_BR_Y;
    [CCode (cname = "SANE_NAME_SCAN_RESOLUTION", cheader_filename = "sane/saneopts.h")]
    public static string NAME_SCAN_RESOLUTION;
    [CCode (cname = "SANE_NAME_SCAN_X_RESOLUTION", cheader_filename = "sane/saneopts.h")]
    public static string NAME_SCAN_X_RESOLUTION;
    [CCode (cname = "SANE_NAME_SCAN_Y_RESOLUTION", cheader_filename = "sane/saneopts.h")]
    public static string NAME_SCAN_Y_RESOLUTION;
    [CCode (cname = "SANE_NAME_PAGE_WIDTH", cheader_filename = "sane/saneopts.h")]
    public static string NAME_PAGE_WIDTH;
    [CCode (cname = "SANE_NAME_PAGE_HEIGHT", cheader_filename = "sane/saneopts.h")]
    public static string NAME_PAGE_HEIGHT;
    [CCode (cname = "SANE_NAME_CUSTOM_GAMMA", cheader_filename = "sane/saneopts.h")]
    public static string NAME_CUSTOM_GAMMA;
    [CCode (cname = "SANE_NAME_GAMMA_VECTOR", cheader_filename = "sane/saneopts.h")]
    public static string NAME_GAMMA_VECTOR;
    [CCode (cname = "SANE_NAME_GAMMA_VECTOR_R", cheader_filename = "sane/saneopts.h")]
    public static string NAME_GAMMA_VECTOR_R;
    [CCode (cname = "SANE_NAME_GAMMA_VECTOR_G", cheader_filename = "sane/saneopts.h")]
    public static string NAME_GAMMA_VECTOR_G;
    [CCode (cname = "SANE_NAME_GAMMA_VECTOR_B", cheader_filename = "sane/saneopts.h")]
    public static string NAME_GAMMA_VECTOR_B;
    [CCode (cname = "SANE_NAME_BRIGHTNESS", cheader_filename = "sane/saneopts.h")]
    public static string NAME_BRIGHTNESS;
    [CCode (cname = "SANE_NAME_CONTRAST", cheader_filename = "sane/saneopts.h")]
    public static string NAME_CONTRAST;
    [CCode (cname = "SANE_NAME_GRAIN_SIZE", cheader_filename = "sane/saneopts.h")]
    public static string NAME_GRAIN_SIZE;
    [CCode (cname = "SANE_NAME_HALFTONE", cheader_filename = "sane/saneopts.h")]
    public static string NAME_HALFTONE;
    [CCode (cname = "SANE_NAME_BLACK_LEVEL", cheader_filename = "sane/saneopts.h")]
    public static string NAME_BLACK_LEVEL;
    [CCode (cname = "SANE_NAME_WHITE_LEVEL", cheader_filename = "sane/saneopts.h")]
    public static string NAME_WHITE_LEVEL;
    [CCode (cname = "SANE_NAME_WHITE_LEVEL_R", cheader_filename = "sane/saneopts.h")]
    public static string NAME_WHITE_LEVEL_R;
    [CCode (cname = "SANE_NAME_WHITE_LEVEL_G", cheader_filename = "sane/saneopts.h")]
    public static string NAME_WHITE_LEVEL_G;
    [CCode (cname = "SANE_NAME_WHITE_LEVEL_B", cheader_filename = "sane/saneopts.h")]
    public static string NAME_WHITE_LEVEL_B;
    [CCode (cname = "SANE_NAME_SHADOW", cheader_filename = "sane/saneopts.h")]
    public static string NAME_SHADOW;
    [CCode (cname = "SANE_NAME_SHADOW_R", cheader_filename = "sane/saneopts.h")]
    public static string NAME_SHADOW_R;
    [CCode (cname = "SANE_NAME_SHADOW_G", cheader_filename = "sane/saneopts.h")]
    public static string NAME_SHADOW_G;
    [CCode (cname = "SANE_NAME_SHADOW_B", cheader_filename = "sane/saneopts.h")]
    public static string NAME_SHADOW_B;
    [CCode (cname = "SANE_NAME_HIGHLIGHT", cheader_filename = "sane/saneopts.h")]
    public static string NAME_HIGHLIGHT;
    [CCode (cname = "SANE_NAME_HIGHLIGHT_R", cheader_filename = "sane/saneopts.h")]
    public static string NAME_HIGHLIGHT_R;
    [CCode (cname = "SANE_NAME_HIGHLIGHT_G", cheader_filename = "sane/saneopts.h")]
    public static string NAME_HIGHLIGHT_G;
    [CCode (cname = "SANE_NAME_HIGHLIGHT_B", cheader_filename = "sane/saneopts.h")]
    public static string NAME_HIGHLIGHT_B;
    [CCode (cname = "SANE_NAME_HUE", cheader_filename = "sane/saneopts.h")]
    public static string NAME_HUE;
    [CCode (cname = "SANE_NAME_SATURATION", cheader_filename = "sane/saneopts.h")]
    public static string NAME_SATURATION;
    [CCode (cname = "SANE_NAME_FILE", cheader_filename = "sane/saneopts.h")]
    public static string NAME_FILE;
    [CCode (cname = "SANE_NAME_HALFTONE_DIMENSION", cheader_filename = "sane/saneopts.h")]
    public static string NAME_HALFTONE_DIMENSION;
    [CCode (cname = "SANE_NAME_HALFTONE_PATTERN", cheader_filename = "sane/saneopts.h")]
    public static string NAME_HALFTONE_PATTERN;
    [CCode (cname = "SANE_NAME_RESOLUTION_BIND", cheader_filename = "sane/saneopts.h")]
    public static string NAME_RESOLUTION_BIND;
    [CCode (cname = "SANE_NAME_NEGATIVE", cheader_filename = "sane/saneopts.h")]
    public static string NAME_NEGATIVE;
    [CCode (cname = "SANE_NAME_QUALITY_CAL", cheader_filename = "sane/saneopts.h")]
    public static string NAME_QUALITY_CAL;
    [CCode (cname = "SANE_NAME_DOR", cheader_filename = "sane/saneopts.h")]
    public static string NAME_DOR;
    [CCode (cname = "SANE_NAME_RGB_BIND", cheader_filename = "sane/saneopts.h")]
    public static string NAME_RGB_BIND;
    [CCode (cname = "SANE_NAME_THRESHOLD", cheader_filename = "sane/saneopts.h")]
    public static string NAME_THRESHOLD;
    [CCode (cname = "SANE_NAME_ANALOG_GAMMA", cheader_filename = "sane/saneopts.h")]
    public static string NAME_ANALOG_GAMMA;
    [CCode (cname = "SANE_NAME_ANALOG_GAMMA_R", cheader_filename = "sane/saneopts.h")]
    public static string NAME_ANALOG_GAMMA_R;
    [CCode (cname = "SANE_NAME_ANALOG_GAMMA_G", cheader_filename = "sane/saneopts.h")]
    public static string NAME_ANALOG_GAMMA_G;
    [CCode (cname = "SANE_NAME_ANALOG_GAMMA_B", cheader_filename = "sane/saneopts.h")]
    public static string NAME_ANALOG_GAMMA_B;
    [CCode (cname = "SANE_NAME_ANALOG_GAMMA_BIND", cheader_filename = "sane/saneopts.h")]
    public static string NAME_ANALOG_GAMMA_BIND;
    [CCode (cname = "SANE_NAME_WARMUP", cheader_filename = "sane/saneopts.h")]
    public static string NAME_WARMUP;
    [CCode (cname = "SANE_NAME_CAL_EXPOS_TIME", cheader_filename = "sane/saneopts.h")]
    public static string NAME_CAL_EXPOS_TIME;
    [CCode (cname = "SANE_NAME_CAL_EXPOS_TIME_R", cheader_filename = "sane/saneopts.h")]
    public static string NAME_CAL_EXPOS_TIME_R;
    [CCode (cname = "SANE_NAME_CAL_EXPOS_TIME_G", cheader_filename = "sane/saneopts.h")]
    public static string NAME_CAL_EXPOS_TIME_G;
    [CCode (cname = "SANE_NAME_CAL_EXPOS_TIME_B", cheader_filename = "sane/saneopts.h")]
    public static string NAME_CAL_EXPOS_TIME_B;
    [CCode (cname = "SANE_NAME_SCAN_EXPOS_TIME", cheader_filename = "sane/saneopts.h")]
    public static string NAME_SCAN_EXPOS_TIME;
    [CCode (cname = "SANE_NAME_SCAN_EXPOS_TIME_R", cheader_filename = "sane/saneopts.h")]
    public static string NAME_SCAN_EXPOS_TIME_R;
    [CCode (cname = "SANE_NAME_SCAN_EXPOS_TIME_G", cheader_filename = "sane/saneopts.h")]
    public static string NAME_SCAN_EXPOS_TIME_G;
    [CCode (cname = "SANE_NAME_SCAN_EXPOS_TIME_B", cheader_filename = "sane/saneopts.h")]
    public static string NAME_SCAN_EXPOS_TIME_B;
    [CCode (cname = "SANE_NAME_SELECT_EXPOSURE_TIME", cheader_filename = "sane/saneopts.h")]
    public static string NAME_SELECT_EXPOSURE_TIME;
    [CCode (cname = "SANE_NAME_CAL_LAMP_DEN", cheader_filename = "sane/saneopts.h")]
    public static string NAME_CAL_LAMP_DEN;
    [CCode (cname = "SANE_NAME_SCAN_LAMP_DEN", cheader_filename = "sane/saneopts.h")]
    public static string NAME_SCAN_LAMP_DEN;
    [CCode (cname = "SANE_NAME_SELECT_LAMP_DENSITY", cheader_filename = "sane/saneopts.h")]
    public static string NAME_SELECT_LAMP_DENSITY;
    [CCode (cname = "SANE_NAME_LAMP_OFF_AT_EXIT", cheader_filename = "sane/saneopts.h")]
    public static string NAME_LAMP_OFF_AT_EXIT;
    [CCode (cname = "SANE_NAME_SCAN", cheader_filename = "sane/saneopts.h")]
    public static string NAME_SCAN;
    [CCode (cname = "SANE_NAME_EMAIL", cheader_filename = "sane/saneopts.h")]
    public static string NAME_EMAIL;
    [CCode (cname = "SANE_NAME_FAX", cheader_filename = "sane/saneopts.h")]
    public static string NAME_FAX;
    [CCode (cname = "SANE_NAME_COPY", cheader_filename = "sane/saneopts.h")]
    public static string NAME_COPY;
    [CCode (cname = "SANE_NAME_PDF", cheader_filename = "sane/saneopts.h")]
    public static string NAME_PDF;
    [CCode (cname = "SANE_NAME_CANCEL", cheader_filename = "sane/saneopts.h")]
    public static string NAME_CANCEL;
    [CCode (cname = "SANE_NAME_PAGE_LOADED", cheader_filename = "sane/saneopts.h")]
    public static string NAME_PAGE_LOADED;
    [CCode (cname = "SANE_NAME_COVER_OPEN", cheader_filename = "sane/saneopts.h")]
    public static string NAME_COVER_OPEN;
    [CCode (cname = "SANE_TITLE_NUM_OPTIONS", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_NUM_OPTIONS;
    [CCode (cname = "SANE_TITLE_STANDARD", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_STANDARD;
    [CCode (cname = "SANE_TITLE_GEOMETRY", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_GEOMETRY;
    [CCode (cname = "SANE_TITLE_ENHANCEMENT", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_ENHANCEMENT;
    [CCode (cname = "SANE_TITLE_ADVANCED", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_ADVANCED;
    [CCode (cname = "SANE_TITLE_SENSORS", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_SENSORS;
    [CCode (cname = "SANE_TITLE_PREVIEW", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_PREVIEW;
    [CCode (cname = "SANE_TITLE_GRAY_PREVIEW", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_GRAY_PREVIEW;
    [CCode (cname = "SANE_TITLE_BIT_DEPTH", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_BIT_DEPTH;
    [CCode (cname = "SANE_TITLE_SCAN_MODE", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_SCAN_MODE;
    [CCode (cname = "SANE_TITLE_SCAN_SPEED", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_SCAN_SPEED;
    [CCode (cname = "SANE_TITLE_SCAN_SOURCE", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_SCAN_SOURCE;
    [CCode (cname = "SANE_TITLE_BACKTRACK", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_BACKTRACK;
    [CCode (cname = "SANE_TITLE_SCAN_TL_X", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_SCAN_TL_X;
    [CCode (cname = "SANE_TITLE_SCAN_TL_Y", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_SCAN_TL_Y;
    [CCode (cname = "SANE_TITLE_SCAN_BR_X", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_SCAN_BR_X;
    [CCode (cname = "SANE_TITLE_SCAN_BR_Y", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_SCAN_BR_Y;
    [CCode (cname = "SANE_TITLE_SCAN_RESOLUTION", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_SCAN_RESOLUTION;
    [CCode (cname = "SANE_TITLE_SCAN_X_RESOLUTION", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_SCAN_X_RESOLUTION;
    [CCode (cname = "SANE_TITLE_SCAN_Y_RESOLUTION", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_SCAN_Y_RESOLUTION;
    [CCode (cname = "SANE_TITLE_PAGE_WIDTH", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_PAGE_WIDTH;
    [CCode (cname = "SANE_TITLE_PAGE_HEIGHT", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_PAGE_HEIGHT;
    [CCode (cname = "SANE_TITLE_CUSTOM_GAMMA", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_CUSTOM_GAMMA;
    [CCode (cname = "SANE_TITLE_GAMMA_VECTOR", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_GAMMA_VECTOR;
    [CCode (cname = "SANE_TITLE_GAMMA_VECTOR_R", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_GAMMA_VECTOR_R;
    [CCode (cname = "SANE_TITLE_GAMMA_VECTOR_G", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_GAMMA_VECTOR_G;
    [CCode (cname = "SANE_TITLE_GAMMA_VECTOR_B", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_GAMMA_VECTOR_B;
    [CCode (cname = "SANE_TITLE_BRIGHTNESS", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_BRIGHTNESS;
    [CCode (cname = "SANE_TITLE_CONTRAST", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_CONTRAST;
    [CCode (cname = "SANE_TITLE_GRAIN_SIZE", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_GRAIN_SIZE;
    [CCode (cname = "SANE_TITLE_HALFTONE", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_HALFTONE;
    [CCode (cname = "SANE_TITLE_BLACK_LEVEL", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_BLACK_LEVEL;
    [CCode (cname = "SANE_TITLE_WHITE_LEVEL", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_WHITE_LEVEL;
    [CCode (cname = "SANE_TITLE_WHITE_LEVEL_R", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_WHITE_LEVEL_R;
    [CCode (cname = "SANE_TITLE_WHITE_LEVEL_G", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_WHITE_LEVEL_G;
    [CCode (cname = "SANE_TITLE_WHITE_LEVEL_B", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_WHITE_LEVEL_B;
    [CCode (cname = "SANE_TITLE_SHADOW", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_SHADOW;
    [CCode (cname = "SANE_TITLE_SHADOW_R", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_SHADOW_R;
    [CCode (cname = "SANE_TITLE_SHADOW_G", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_SHADOW_G;
    [CCode (cname = "SANE_TITLE_SHADOW_B", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_SHADOW_B;
    [CCode (cname = "SANE_TITLE_HIGHLIGHT", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_HIGHLIGHT;
    [CCode (cname = "SANE_TITLE_HIGHLIGHT_R", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_HIGHLIGHT_R;
    [CCode (cname = "SANE_TITLE_HIGHLIGHT_G", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_HIGHLIGHT_G;
    [CCode (cname = "SANE_TITLE_HIGHLIGHT_B", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_HIGHLIGHT_B;
    [CCode (cname = "SANE_TITLE_HUE", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_HUE;
    [CCode (cname = "SANE_TITLE_SATURATION", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_SATURATION;
    [CCode (cname = "SANE_TITLE_FILE", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_FILE;
    [CCode (cname = "SANE_TITLE_HALFTONE_DIMENSION", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_HALFTONE_DIMENSION;
    [CCode (cname = "SANE_TITLE_HALFTONE_PATTERN", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_HALFTONE_PATTERN;
    [CCode (cname = "SANE_TITLE_RESOLUTION_BIND", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_RESOLUTION_BIND;
    [CCode (cname = "SANE_TITLE_NEGATIVE", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_NEGATIVE;
    [CCode (cname = "SANE_TITLE_QUALITY_CAL", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_QUALITY_CAL;
    [CCode (cname = "SANE_TITLE_DOR", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_DOR;
    [CCode (cname = "SANE_TITLE_RGB_BIND", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_RGB_BIND;
    [CCode (cname = "SANE_TITLE_THRESHOLD", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_THRESHOLD;
    [CCode (cname = "SANE_TITLE_ANALOG_GAMMA", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_ANALOG_GAMMA;
    [CCode (cname = "SANE_TITLE_ANALOG_GAMMA_R", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_ANALOG_GAMMA_R;
    [CCode (cname = "SANE_TITLE_ANALOG_GAMMA_G", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_ANALOG_GAMMA_G;
    [CCode (cname = "SANE_TITLE_ANALOG_GAMMA_B", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_ANALOG_GAMMA_B;
    [CCode (cname = "SANE_TITLE_ANALOG_GAMMA_BIND", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_ANALOG_GAMMA_BIND;
    [CCode (cname = "SANE_TITLE_WARMUP", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_WARMUP;
    [CCode (cname = "SANE_TITLE_CAL_EXPOS_TIME", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_CAL_EXPOS_TIME;
    [CCode (cname = "SANE_TITLE_CAL_EXPOS_TIME_R", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_CAL_EXPOS_TIME_R;
    [CCode (cname = "SANE_TITLE_CAL_EXPOS_TIME_G", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_CAL_EXPOS_TIME_G;
    [CCode (cname = "SANE_TITLE_CAL_EXPOS_TIME_B", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_CAL_EXPOS_TIME_B;
    [CCode (cname = "SANE_TITLE_SCAN_EXPOS_TIME", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_SCAN_EXPOS_TIME;
    [CCode (cname = "SANE_TITLE_SCAN_EXPOS_TIME_R", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_SCAN_EXPOS_TIME_R;
    [CCode (cname = "SANE_TITLE_SCAN_EXPOS_TIME_G", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_SCAN_EXPOS_TIME_G;
    [CCode (cname = "SANE_TITLE_SCAN_EXPOS_TIME_B", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_SCAN_EXPOS_TIME_B;
    [CCode (cname = "SANE_TITLE_SELECT_EXPOSURE_TIME", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_SELECT_EXPOSURE_TIME;
    [CCode (cname = "SANE_TITLE_CAL_LAMP_DEN", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_CAL_LAMP_DEN;
    [CCode (cname = "SANE_TITLE_SCAN_LAMP_DEN", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_SCAN_LAMP_DEN;
    [CCode (cname = "SANE_TITLE_SELECT_LAMP_DENSITY", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_SELECT_LAMP_DENSITY;
    [CCode (cname = "SANE_TITLE_LAMP_OFF_AT_EXIT", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_LAMP_OFF_AT_EXIT;
    [CCode (cname = "SANE_TITLE_SCAN", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_SCAN;
    [CCode (cname = "SANE_TITLE_EMAIL", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_EMAIL;
    [CCode (cname = "SANE_TITLE_FAX", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_FAX;
    [CCode (cname = "SANE_TITLE_COPY", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_COPY;
    [CCode (cname = "SANE_TITLE_PDF", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_PDF;
    [CCode (cname = "SANE_TITLE_CANCEL", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_CANCEL;
    [CCode (cname = "SANE_TITLE_PAGE_LOADED", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_PAGE_LOADED;
    [CCode (cname = "SANE_TITLE_COVER_OPEN", cheader_filename = "sane/saneopts.h")]
    public static string TITLE_COVER_OPEN;
    [CCode (cname = "SANE_DESC_NUM_OPTIONS", cheader_filename = "sane/saneopts.h")]
    public static string DESC_NUM_OPTIONS;
    [CCode (cname = "SANE_DESC_STANDARD", cheader_filename = "sane/saneopts.h")]
    public static string DESC_STANDARD;
    [CCode (cname = "SANE_DESC_GEOMETRY", cheader_filename = "sane/saneopts.h")]
    public static string DESC_GEOMETRY;
    [CCode (cname = "SANE_DESC_ENHANCEMENT", cheader_filename = "sane/saneopts.h")]
    public static string DESC_ENHANCEMENT;
    [CCode (cname = "SANE_DESC_ADVANCED", cheader_filename = "sane/saneopts.h")]
    public static string DESC_ADVANCED;
    [CCode (cname = "SANE_DESC_SENSORS", cheader_filename = "sane/saneopts.h")]
    public static string DESC_SENSORS;
    [CCode (cname = "SANE_DESC_PREVIEW", cheader_filename = "sane/saneopts.h")]
    public static string DESC_PREVIEW;
    [CCode (cname = "SANE_DESC_GRAY_PREVIEW", cheader_filename = "sane/saneopts.h")]
    public static string DESC_GRAY_PREVIEW;
    [CCode (cname = "SANE_DESC_BIT_DEPTH", cheader_filename = "sane/saneopts.h")]
    public static string DESC_BIT_DEPTH;
    [CCode (cname = "SANE_DESC_SCAN_MODE", cheader_filename = "sane/saneopts.h")]
    public static string DESC_SCAN_MODE;
    [CCode (cname = "SANE_DESC_SCAN_SPEED", cheader_filename = "sane/saneopts.h")]
    public static string DESC_SCAN_SPEED;
    [CCode (cname = "SANE_DESC_SCAN_SOURCE", cheader_filename = "sane/saneopts.h")]
    public static string DESC_SCAN_SOURCE;
    [CCode (cname = "SANE_DESC_BACKTRACK", cheader_filename = "sane/saneopts.h")]
    public static string DESC_BACKTRACK;
    [CCode (cname = "SANE_DESC_SCAN_TL_X", cheader_filename = "sane/saneopts.h")]
    public static string DESC_SCAN_TL_X;
    [CCode (cname = "SANE_DESC_SCAN_TL_Y", cheader_filename = "sane/saneopts.h")]
    public static string DESC_SCAN_TL_Y;
    [CCode (cname = "SANE_DESC_SCAN_BR_X", cheader_filename = "sane/saneopts.h")]
    public static string DESC_SCAN_BR_X;
    [CCode (cname = "SANE_DESC_SCAN_BR_Y", cheader_filename = "sane/saneopts.h")]
    public static string DESC_SCAN_BR_Y;
    [CCode (cname = "SANE_DESC_SCAN_RESOLUTION", cheader_filename = "sane/saneopts.h")]
    public static string DESC_SCAN_RESOLUTION;
    [CCode (cname = "SANE_DESC_SCAN_X_RESOLUTION", cheader_filename = "sane/saneopts.h")]
    public static string DESC_SCAN_X_RESOLUTION;
    [CCode (cname = "SANE_DESC_SCAN_Y_RESOLUTION", cheader_filename = "sane/saneopts.h")]
    public static string DESC_SCAN_Y_RESOLUTION;
    [CCode (cname = "SANE_DESC_PAGE_WIDTH", cheader_filename = "sane/saneopts.h")]
    public static string DESC_PAGE_WIDTH;
    [CCode (cname = "SANE_DESC_PAGE_HEIGHT", cheader_filename = "sane/saneopts.h")]
    public static string DESC_PAGE_HEIGHT;
    [CCode (cname = "SANE_DESC_CUSTOM_GAMMA", cheader_filename = "sane/saneopts.h")]
    public static string DESC_CUSTOM_GAMMA;
    [CCode (cname = "SANE_DESC_GAMMA_VECTOR", cheader_filename = "sane/saneopts.h")]
    public static string DESC_GAMMA_VECTOR;
    [CCode (cname = "SANE_DESC_GAMMA_VECTOR_R", cheader_filename = "sane/saneopts.h")]
    public static string DESC_GAMMA_VECTOR_R;
    [CCode (cname = "SANE_DESC_GAMMA_VECTOR_G", cheader_filename = "sane/saneopts.h")]
    public static string DESC_GAMMA_VECTOR_G;
    [CCode (cname = "SANE_DESC_GAMMA_VECTOR_B", cheader_filename = "sane/saneopts.h")]
    public static string DESC_GAMMA_VECTOR_B;
    [CCode (cname = "SANE_DESC_BRIGHTNESS", cheader_filename = "sane/saneopts.h")]
    public static string DESC_BRIGHTNESS;
    [CCode (cname = "SANE_DESC_CONTRAST", cheader_filename = "sane/saneopts.h")]
    public static string DESC_CONTRAST;
    [CCode (cname = "SANE_DESC_GRAIN_SIZE", cheader_filename = "sane/saneopts.h")]
    public static string DESC_GRAIN_SIZE;
    [CCode (cname = "SANE_DESC_HALFTONE", cheader_filename = "sane/saneopts.h")]
    public static string DESC_HALFTONE;
    [CCode (cname = "SANE_DESC_BLACK_LEVEL", cheader_filename = "sane/saneopts.h")]
    public static string DESC_BLACK_LEVEL;
    [CCode (cname = "SANE_DESC_WHITE_LEVEL", cheader_filename = "sane/saneopts.h")]
    public static string DESC_WHITE_LEVEL;
    [CCode (cname = "SANE_DESC_WHITE_LEVEL_R", cheader_filename = "sane/saneopts.h")]
    public static string DESC_WHITE_LEVEL_R;
    [CCode (cname = "SANE_DESC_WHITE_LEVEL_G", cheader_filename = "sane/saneopts.h")]
    public static string DESC_WHITE_LEVEL_G;
    [CCode (cname = "SANE_DESC_WHITE_LEVEL_B", cheader_filename = "sane/saneopts.h")]
    public static string DESC_WHITE_LEVEL_B;
    [CCode (cname = "SANE_DESC_SHADOW", cheader_filename = "sane/saneopts.h")]
    public static string DESC_SHADOW;
    [CCode (cname = "SANE_DESC_SHADOW_R", cheader_filename = "sane/saneopts.h")]
    public static string DESC_SHADOW_R;
    [CCode (cname = "SANE_DESC_SHADOW_G", cheader_filename = "sane/saneopts.h")]
    public static string DESC_SHADOW_G;
    [CCode (cname = "SANE_DESC_SHADOW_B", cheader_filename = "sane/saneopts.h")]
    public static string DESC_SHADOW_B;
    [CCode (cname = "SANE_DESC_HIGHLIGHT", cheader_filename = "sane/saneopts.h")]
    public static string DESC_HIGHLIGHT;
    [CCode (cname = "SANE_DESC_HIGHLIGHT_R", cheader_filename = "sane/saneopts.h")]
    public static string DESC_HIGHLIGHT_R;
    [CCode (cname = "SANE_DESC_HIGHLIGHT_G", cheader_filename = "sane/saneopts.h")]
    public static string DESC_HIGHLIGHT_G;
    [CCode (cname = "SANE_DESC_HIGHLIGHT_B", cheader_filename = "sane/saneopts.h")]
    public static string DESC_HIGHLIGHT_B;
    [CCode (cname = "SANE_DESC_HUE", cheader_filename = "sane/saneopts.h")]
    public static string DESC_HUE;
    [CCode (cname = "SANE_DESC_SATURATION", cheader_filename = "sane/saneopts.h")]
    public static string DESC_SATURATION;
    [CCode (cname = "SANE_DESC_FILE", cheader_filename = "sane/saneopts.h")]
    public static string DESC_FILE;
    [CCode (cname = "SANE_DESC_HALFTONE_DIMENSION", cheader_filename = "sane/saneopts.h")]
    public static string DESC_HALFTONE_DIMENSION;
    [CCode (cname = "SANE_DESC_HALFTONE_PATTERN", cheader_filename = "sane/saneopts.h")]
    public static string DESC_HALFTONE_PATTERN;
    [CCode (cname = "SANE_DESC_RESOLUTION_BIND", cheader_filename = "sane/saneopts.h")]
    public static string DESC_RESOLUTION_BIND;
    [CCode (cname = "SANE_DESC_NEGATIVE", cheader_filename = "sane/saneopts.h")]
    public static string DESC_NEGATIVE;
    [CCode (cname = "SANE_DESC_QUALITY_CAL", cheader_filename = "sane/saneopts.h")]
    public static string DESC_QUALITY_CAL;
    [CCode (cname = "SANE_DESC_DOR", cheader_filename = "sane/saneopts.h")]
    public static string DESC_DOR;
    [CCode (cname = "SANE_DESC_RGB_BIND", cheader_filename = "sane/saneopts.h")]
    public static string DESC_RGB_BIND;
    [CCode (cname = "SANE_DESC_THRESHOLD", cheader_filename = "sane/saneopts.h")]
    public static string DESC_THRESHOLD;
    [CCode (cname = "SANE_DESC_ANALOG_GAMMA", cheader_filename = "sane/saneopts.h")]
    public static string DESC_ANALOG_GAMMA;
    [CCode (cname = "SANE_DESC_ANALOG_GAMMA_R", cheader_filename = "sane/saneopts.h")]
    public static string DESC_ANALOG_GAMMA_R;
    [CCode (cname = "SANE_DESC_ANALOG_GAMMA_G", cheader_filename = "sane/saneopts.h")]
    public static string DESC_ANALOG_GAMMA_G;
    [CCode (cname = "SANE_DESC_ANALOG_GAMMA_B", cheader_filename = "sane/saneopts.h")]
    public static string DESC_ANALOG_GAMMA_B;
    [CCode (cname = "SANE_DESC_ANALOG_GAMMA_BIND", cheader_filename = "sane/saneopts.h")]
    public static string DESC_ANALOG_GAMMA_BIND;
    [CCode (cname = "SANE_DESC_WARMUP", cheader_filename = "sane/saneopts.h")]
    public static string DESC_WARMUP;
    [CCode (cname = "SANE_DESC_CAL_EXPOS_TIME", cheader_filename = "sane/saneopts.h")]
    public static string DESC_CAL_EXPOS_TIME;
    [CCode (cname = "SANE_DESC_CAL_EXPOS_TIME_R", cheader_filename = "sane/saneopts.h")]
    public static string DESC_CAL_EXPOS_TIME_R;
    [CCode (cname = "SANE_DESC_CAL_EXPOS_TIME_G", cheader_filename = "sane/saneopts.h")]
    public static string DESC_CAL_EXPOS_TIME_G;
    [CCode (cname = "SANE_DESC_CAL_EXPOS_TIME_B", cheader_filename = "sane/saneopts.h")]
    public static string DESC_CAL_EXPOS_TIME_B;
    [CCode (cname = "SANE_DESC_SCAN_EXPOS_TIME", cheader_filename = "sane/saneopts.h")]
    public static string DESC_SCAN_EXPOS_TIME;
    [CCode (cname = "SANE_DESC_SCAN_EXPOS_TIME_R", cheader_filename = "sane/saneopts.h")]
    public static string DESC_SCAN_EXPOS_TIME_R;
    [CCode (cname = "SANE_DESC_SCAN_EXPOS_TIME_G", cheader_filename = "sane/saneopts.h")]
    public static string DESC_SCAN_EXPOS_TIME_G;
    [CCode (cname = "SANE_DESC_SCAN_EXPOS_TIME_B", cheader_filename = "sane/saneopts.h")]
    public static string DESC_SCAN_EXPOS_TIME_B;
    [CCode (cname = "SANE_DESC_SELECT_EXPOSURE_TIME", cheader_filename = "sane/saneopts.h")]
    public static string DESC_SELECT_EXPOSURE_TIME;
    [CCode (cname = "SANE_DESC_CAL_LAMP_DEN", cheader_filename = "sane/saneopts.h")]
    public static string DESC_CAL_LAMP_DEN;
    [CCode (cname = "SANE_DESC_SCAN_LAMP_DEN", cheader_filename = "sane/saneopts.h")]
    public static string DESC_SCAN_LAMP_DEN;
    [CCode (cname = "SANE_DESC_SELECT_LAMP_DENSITY", cheader_filename = "sane/saneopts.h")]
    public static string DESC_SELECT_LAMP_DENSITY;
    [CCode (cname = "SANE_DESC_LAMP_OFF_AT_EXIT", cheader_filename = "sane/saneopts.h")]
    public static string DESC_LAMP_OFF_AT_EXIT;
    [CCode (cname = "SANE_DESC_SCAN", cheader_filename = "sane/saneopts.h")]
    public static string DESC_SCAN;
    [CCode (cname = "SANE_DESC_EMAIL", cheader_filename = "sane/saneopts.h")]
    public static string DESC_EMAIL;
    [CCode (cname = "SANE_DESC_FAX", cheader_filename = "sane/saneopts.h")]
    public static string DESC_FAX;
    [CCode (cname = "SANE_DESC_COPY", cheader_filename = "sane/saneopts.h")]
    public static string DESC_COPY;
    [CCode (cname = "SANE_DESC_PDF", cheader_filename = "sane/saneopts.h")]
    public static string DESC_PDF;
    [CCode (cname = "SANE_DESC_CANCEL", cheader_filename = "sane/saneopts.h")]
    public static string DESC_CANCEL;
    [CCode (cname = "SANE_DESC_PAGE_LOADED", cheader_filename = "sane/saneopts.h")]
    public static string DESC_PAGE_LOADED;
    [CCode (cname = "SANE_DESC_COVER_OPEN", cheader_filename = "sane/saneopts.h")]
    public static string DESC_COVER_OPEN;
    [CCode (cname = "SANE_VALUE_SCAN_MODE_COLOR", cheader_filename = "sane/saneopts.h")]
    public static string VALUE_SCAN_MODE_COLOR;
    [CCode (cname = "SANE_VALUE_SCAN_MODE_COLOR_LINEART", cheader_filename = "sane/saneopts.h")]
    public static string VALUE_SCAN_MODE_COLOR_LINEART;
    [CCode (cname = "SANE_VALUE_SCAN_MODE_COLOR_HALFTONE", cheader_filename = "sane/saneopts.h")]
    public static string VALUE_SCAN_MODE_COLOR_HALFTONE;
    [CCode (cname = "SANE_VALUE_SCAN_MODE_GRAY", cheader_filename = "sane/saneopts.h")]
    public static string VALUE_SCAN_MODE_GRAY;
    [CCode (cname = "SANE_VALUE_SCAN_MODE_HALFTONE", cheader_filename = "sane/saneopts.h")]
    public static string VALUE_SCAN_MODE_HALFTONE;
    [CCode (cname = "SANE_VALUE_SCAN_MODE_LINEART", cheader_filename = "sane/saneopts.h")]
    public static string VALUE_SCAN_MODE_LINEART;
}
