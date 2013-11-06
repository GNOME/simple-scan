/*
 * Copyright (C) 2009-2011 Canonical Ltd.
 * Author: Robert Ancell <robert.ancell@canonical.com>
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later
 * version. See http://www.gnu.org/copyleft/gpl.html the full text of the
 * license.
 */

public enum ScanDirection
{
    TOP_TO_BOTTOM,
    LEFT_TO_RIGHT,
    BOTTOM_TO_TOP,
    RIGHT_TO_LEFT
}

public class Page
{
    /* Resolution of page */
    private int dpi;

    /* Number of rows in this page or -1 if currently unknown */
    private int expected_rows;

    /* Bit depth */
    private int depth;

    /* Color profile */
    private string? color_profile;

    /* Scanned image data */
    private int width;
    private int n_rows;
    private int rowstride;
    private int n_channels;
    private uchar[] pixels;

    /* Page is getting data */
    private bool scanning;

    /* true if have some page data */
    private bool has_data_;

    /* Expected next scan row */
    private int scan_line;

    /* Rotation of scanned data */
    private ScanDirection scan_direction = ScanDirection.TOP_TO_BOTTOM;

    /* Crop */
    private bool has_crop_;
    private string? crop_name;
    private int crop_x;
    private int crop_y;
    private int crop_width;
    private int crop_height;

    public signal void pixels_changed ();
    public signal void size_changed ();
    public signal void scan_line_changed ();
    public signal void scan_direction_changed ();
    public signal void crop_changed ();
    public signal void scan_finished ();

    public Page (int width, int height, int dpi, ScanDirection scan_direction)
    {
        if (scan_direction == ScanDirection.TOP_TO_BOTTOM || scan_direction == ScanDirection.BOTTOM_TO_TOP)
        {
            this.width = width;
            n_rows = height;
        }
        else
        {
            this.width = height;
            n_rows = width;
        }
        this.dpi = dpi;
        this.scan_direction = scan_direction;
    }

    public Page.from_data (int width,
                           int n_rows,
                           int rowstride,
                           int n_channels,
                           int depth,
                           int dpi,
                           ScanDirection scan_direction,
                           string? color_profile,
                           uchar[]? pixels,
                           bool has_crop,
                           string? crop_name,
                           int crop_x,
                           int crop_y,
                           int crop_width,
                           int crop_height)
    {
        this.width = width;
        this.n_rows = n_rows;
        this.expected_rows = n_rows;
        this.rowstride = rowstride;
        this.n_channels = n_channels;
        this.depth = depth;
        this.dpi = dpi;
        this.scan_direction = scan_direction;
        this.color_profile = color_profile;
        this.pixels = pixels;
        has_data_ = pixels != null;
        this.has_crop_ = has_crop;
        this.crop_name = crop_name;
        this.crop_x = crop_x;
        this.crop_y = crop_y;
        this.crop_width = crop_width;
        this.crop_height = crop_height;
    }

    public void set_page_info (ScanPageInfo info)
    {
        expected_rows = info.height;
        dpi = (int) info.dpi;

        /* Create a white page */
        width = info.width;
        n_rows = info.height;
        /* Variable height, try 50% of the width for now */
        if (n_rows < 0)
            n_rows = width / 2;
        depth = info.depth;
        n_channels = info.n_channels;
        rowstride = (width * depth * n_channels + 7) / 8;
        pixels.resize (n_rows * rowstride);
        return_if_fail (pixels != null);

        /* Fill with white */
        if (depth == 1)
            Memory.set (pixels, 0x00, n_rows * rowstride);
        else
            Memory.set (pixels, 0xFF, n_rows * rowstride);

        size_changed ();
        pixels_changed ();
    }

    public void start ()
    {
        scanning = true;
        scan_line_changed ();
    }

    public bool is_scanning ()
    {
        return scanning;
    }

    public bool has_data ()
    {
        return has_data_;
    }

    public bool is_color ()
    {
        return n_channels > 1;
    }

    public int get_scan_line ()
    {
        return scan_line;
    }

    private void parse_line (ScanLine line, int n, out bool size_changed)
    {
        int line_number;

        line_number = line.number + n;

        /* Extend image if necessary */
        size_changed = false;
        while (line_number >= get_scan_height ())
        {
            int rows;

            /* Extend image */
            rows = n_rows;
            n_rows = rows + width / 2;
            debug ("Extending image from %d lines to %d lines", rows, n_rows);
            pixels.resize (n_rows * rowstride);

            size_changed = true;
        }

        /* Copy in new row */
        var offset = line_number * rowstride;
        var line_offset = n * line.data_length;
        for (var i = 0; i < line.data_length; i++)
            pixels[offset+i] = line.data[line_offset+i];

        scan_line = line_number;
    }

    public void parse_scan_line (ScanLine line)
    {
        bool size_has_changed = false;
        for (var i = 0; i < line.n_lines; i++)
            parse_line (line, i, out size_has_changed);

        has_data_ = true;

        if (size_has_changed)
            size_changed ();
        scan_line_changed ();
        pixels_changed ();
    }

    public void finish ()
    {
        bool size_has_changed = false;

        /* Trim page */
        if (expected_rows < 0 &&
            scan_line != get_scan_height ())
        {
            int rows;

            rows = n_rows;
            n_rows = scan_line;
            pixels.resize (n_rows * rowstride);
            debug ("Trimming page from %d lines to %d lines", rows, n_rows);

            size_has_changed = true;
        }
        scanning = false;

        if (size_has_changed)
            size_changed ();
        scan_line_changed ();
        scan_finished ();
    }

    public ScanDirection get_scan_direction ()
    {
        return scan_direction;
    }

    private void set_scan_direction (ScanDirection direction)
    {
        int left_steps, t;
        bool size_has_changed = false;
        int width, height;

        if (scan_direction == direction)
            return;

        /* Work out how many times it has been rotated to the left */
        left_steps = direction - scan_direction;
        if (left_steps < 0)
            left_steps += 4;
        if (left_steps != 2)
            size_has_changed = true;

        width = get_width ();
        height = get_height ();

        /* Rotate crop */
        if (has_crop_)
        {
            switch (left_steps)
            {
            /* 90 degrees counter-clockwise */
            case 1:
                t = crop_x;
                crop_x = crop_y;
                crop_y = width - (t + crop_width);
                t = crop_width;
                crop_width = crop_height;
                crop_height = t;
                break;
            /* 180 degrees */
            case 2:
                crop_x = width - (crop_x + crop_width);
                crop_y = width - (crop_y + crop_height);
                break;
            /* 90 degrees clockwise */
            case 3:
                t = crop_y;
                crop_y = crop_x;
                crop_x = height - (t + crop_height);
                t = crop_width;
                crop_width = crop_height;
                crop_height = t;
                break;
            }
        }

        scan_direction = direction;
        if (size_has_changed)
            size_changed ();
        scan_direction_changed ();
        if (has_crop_)
            crop_changed ();
    }

    public void rotate_left ()
    {
        var direction = scan_direction;
        switch (direction)
        {
        case ScanDirection.TOP_TO_BOTTOM:
            direction = ScanDirection.LEFT_TO_RIGHT;
            break;
        case ScanDirection.LEFT_TO_RIGHT:
            direction = ScanDirection.BOTTOM_TO_TOP;
            break;
        case ScanDirection.BOTTOM_TO_TOP:
            direction = ScanDirection.RIGHT_TO_LEFT;
            break;
        case ScanDirection.RIGHT_TO_LEFT:
            direction = ScanDirection.TOP_TO_BOTTOM;
            break;
        }
        set_scan_direction (direction);
    }

    public void rotate_right ()
    {
        var direction = scan_direction;
        switch (direction)
        {
        case ScanDirection.TOP_TO_BOTTOM:
            direction = ScanDirection.RIGHT_TO_LEFT;
            break;
        case ScanDirection.LEFT_TO_RIGHT:
            direction = ScanDirection.TOP_TO_BOTTOM;
            break;
        case ScanDirection.BOTTOM_TO_TOP:
            direction = ScanDirection.LEFT_TO_RIGHT;
            break;
        case ScanDirection.RIGHT_TO_LEFT:
            direction = ScanDirection.BOTTOM_TO_TOP;
            break;
        }
        set_scan_direction (direction);
    }

    public int get_dpi ()
    {
        return dpi;
    }

    public bool is_landscape ()
    {
       return get_width () > get_height ();
    }

    public int get_width ()
    {
        if (scan_direction == ScanDirection.TOP_TO_BOTTOM || scan_direction == ScanDirection.BOTTOM_TO_TOP)
            return width;
        else
            return n_rows;
    }

    public int get_height ()
    {
        if (scan_direction == ScanDirection.TOP_TO_BOTTOM || scan_direction == ScanDirection.BOTTOM_TO_TOP)
            return n_rows;
        else
            return width;
    }

    public int get_depth ()
    {
        return depth;
    }

    public int get_n_channels ()
    {
        return n_channels;
    }

    public int get_rowstride ()
    {
        return rowstride;
    }

    public int get_scan_width ()
    {
        return width;
    }

    public int get_scan_height ()
    {
        return n_rows;
    }

    public void set_color_profile (string? color_profile)
    {
         this.color_profile = color_profile;
    }

    public string get_color_profile ()
    {
         return color_profile;
    }

    public void set_no_crop ()
    {
        if (!has_crop_)
            return;
        has_crop_ = false;
        crop_name = null;
        crop_x = 0;
        crop_y = 0;
        crop_width = 0;
        crop_height = 0;
        crop_changed ();
    }

    public void set_custom_crop (int width, int height)
    {
        //int pw, ph;

        return_if_fail (width >= 1);
        return_if_fail (height >= 1);

        if (crop_name == null && has_crop_ && crop_width == width && crop_height == height)
            return;
        crop_name = null;
        has_crop_ = true;

        crop_width = width;
        crop_height = height;

        /*pw = get_width ();
        ph = get_height ();
        if (crop_width < pw)
            crop_x = (pw - crop_width) / 2;
        else
            crop_x = 0;
        if (crop_height < ph)
            crop_y = (ph - crop_height) / 2;
        else
            crop_y = 0;*/

        crop_changed ();
    }

    public void set_named_crop (string name)
    {
        double width, height;
        switch (name)
        {
        case "A4":
            width = 8.3;
            height = 11.7;
            break;
        case "A5":
            width = 5.8;
            height = 8.3;
            break;
        case "A6":
            width = 4.1;
            height = 5.8;
            break;
        case "letter":
            width = 8.5;
            height = 11;
            break;
        case "legal":
            width = 8.5;
            height = 14;
            break;
        case "4x6":
            width = 4;
            height = 6;
            break;
        default:
            warning ("Unknown paper size '%s'", name);
            return;
        }

        crop_name = name;
        has_crop_ = true;

        var pw = get_width ();
        var ph = get_height ();

        /* Rotate to match original aspect */
        if (pw > ph)
        {
            double t;
            t = width;
            width = height;
            height = t;
        }

        /* Custom crop, make slightly smaller than original */
        crop_width = (int) (width * dpi + 0.5);
        crop_height = (int) (height * dpi + 0.5);

        if (crop_width < pw)
            crop_x = (pw - crop_width) / 2;
        else
            crop_x = 0;
        if (crop_height < ph)
            crop_y = (ph - crop_height) / 2;
        else
            crop_y = 0;
        crop_changed ();
    }

    public void move_crop (int x, int y)
    {
        return_if_fail (x >= 0);
        return_if_fail (y >= 0);
        return_if_fail (x < get_width ());
        return_if_fail (y < get_height ());

        crop_x = x;
        crop_y = y;
        crop_changed ();
    }

    public void rotate_crop ()
    {
        int t;

        if (!has_crop_)
            return;

        t = crop_width;
        crop_width = crop_height;
        crop_height = t;

        /* Clip custom crops */
        if (crop_name == null)
        {
            int w, h;

            w = get_width ();
            h = get_height ();

            if (crop_x + crop_width > w)
                crop_x = w - crop_width;
            if (crop_x < 0)
            {
                crop_x = 0;
                crop_width = w;
            }
            if (crop_y + crop_height > h)
                crop_y = h - crop_height;
            if (crop_y < 0)
            {
                crop_y = 0;
                crop_height = h;
            }
        }

        crop_changed ();
    }

    public bool has_crop ()
    {
        return has_crop_;
    }

    public void get_crop (out int x, out int y, out int width, out int height)
    {
        x = crop_x;
        y = crop_y;
        width = crop_width;
        height = crop_height;
    }

    public string get_named_crop ()
    {
        return crop_name;
    }

    public unowned uchar[] get_pixels ()
    {
        return pixels;
    }

    // FIXME: Copied from page-view, should be shared code
    private uchar get_sample (uchar[] pixels, int offset, int x, int depth, int n_channels, int channel)
    {
        // FIXME
        return 0xFF;
    }

    // FIXME: Copied from page-view, should be shared code
    private void get_pixel (int x, int y, uchar[] pixel, int offset)
    {
        switch (get_scan_direction ())
        {
        case ScanDirection.TOP_TO_BOTTOM:
            break;
        case ScanDirection.BOTTOM_TO_TOP:
            x = get_scan_width () - x - 1;
            y = get_scan_height () - y - 1;
            break;
        case ScanDirection.LEFT_TO_RIGHT:
            var t = x;
            x = get_scan_width () - y - 1;
            y = t;
            break;
        case ScanDirection.RIGHT_TO_LEFT:
            var t = x;
            x = y;
            y = get_scan_height () - t - 1;
            break;
        }

        var depth = get_depth ();
        var n_channels = get_n_channels ();
        var line_offset = get_rowstride () * y;

        /* Optimise for 8 bit images */
        if (depth == 8 && n_channels == 3)
        {
            var o = line_offset + x * n_channels;
            pixel[offset+0] = pixels[o];
            pixel[offset+1] = pixels[o+1];
            pixel[offset+2] = pixels[o+2];
            return;
        }
        else if (depth == 8 && n_channels == 1)
        {
            var p = pixels[line_offset + x];
            pixel[offset+0] = pixel[offset+1] = pixel[offset+2] = p;
            return;
        }

        /* Optimise for bitmaps */
        else if (depth == 1 && n_channels == 1)
        {
            var p = pixels[line_offset + (x / 8)];
            pixel[offset+0] = pixel[offset+1] = pixel[offset+2] = (p & (0x80 >> (x % 8))) != 0 ? 0x00 : 0xFF;
            return;
        }

        /* Optimise for 2 bit images */
        else if (depth == 2 && n_channels == 1)
        {
            int block_shift[4] = { 6, 4, 2, 0 };

            var p = pixels[line_offset + (x / 4)];
            var sample = (p >> block_shift[x % 4]) & 0x3;
            sample = sample * 255 / 3;

            pixel[offset+0] = pixel[offset+1] = pixel[offset+2] = (uchar) sample;
            return;
        }

        /* Use slow method */
        pixel[offset+0] = get_sample (pixels, line_offset, x, depth, n_channels, 0);
        pixel[offset+1] = get_sample (pixels, line_offset, x, depth, n_channels, 1);
        pixel[offset+2] = get_sample (pixels, line_offset, x, depth, n_channels, 2);
    }

    public Gdk.Pixbuf get_image (bool apply_crop)
    {
        int l, r, t, b;
        if (apply_crop && has_crop_)
        {
            l = crop_x;
            r = l + crop_width;
            t = crop_y;
            b = t + crop_height;

            if (l < 0)
                l = 0;
            if (r > get_width ())
                r = get_width ();
            if (t < 0)
                t = 0;
            if (b > get_height ())
                b = get_height ();
        }
        else
        {
            l = 0;
            r = get_width ();
            t = 0;
            b = get_height ();
        }

        var image = new Gdk.Pixbuf (Gdk.Colorspace.RGB, false, 8, r - l, b - t);
        unowned uint8[] image_pixels = image.get_pixels ();
        for (var y = t; y < b; y++)
        {
            var offset = image.get_rowstride () * (y - t);
            for (var x = l; x < r; x++)
                get_pixel (x, y, image_pixels, offset + (x - l) * 3);
        }

        return image;
    }

    private string? get_icc_data_encoded (string icc_profile_filename)
    {
        /* Get binary data */
        string contents;
        try
        {
            FileUtils.get_contents (icc_profile_filename, out contents);
        }
        catch (Error e)
        {
            warning ("failed to get icc profile data: %s", e.message);
            return null;
        }

        /* Encode into base64 */
        return Base64.encode ((uchar[]) contents.to_utf8 ());
    }

    public void save (string type, File file) throws Error
    {
        var stream = file.replace (null, false, FileCreateFlags.NONE, null);
        var writer = new PixbufWriter (stream);
        var image = get_image (true);

        string? icc_profile_data = null;
        if (color_profile != null)
            icc_profile_data = get_icc_data_encoded (color_profile);

        if (strcmp (type, "jpeg") == 0)
        {
            /* ICC profile is awaiting review in gtk2+ bugzilla */
            string[] keys = { "quality", /* "icc-profile", */ null };
            string[] values = { "90", /* icc_profile_data, */ null };
            writer.save (image, "jpeg", keys, values);
        }
        else if (strcmp (type, "png") == 0)
        {
            string[] keys = { "icc-profile", null };
            string[] values = { icc_profile_data, null };
            if (icc_profile_data == null)
                keys[0] = null;
            writer.save (image, "png", keys, values);
        }
        else if (strcmp (type, "tiff") == 0)
        {
            string[] keys = { "compression", "icc-profile", null };
            string[] values = { "8" /* Deflate compression */, icc_profile_data, null };
            if (icc_profile_data == null)
                keys[1] = null;
            writer.save (image, "tiff", keys, values);
        }
        else
            ; // FIXME: Throw Error
    }
}

public class PixbufWriter
{
    public FileOutputStream stream;

    public PixbufWriter (FileOutputStream stream)
    {
        this.stream = stream;
    }

    public void save (Gdk.Pixbuf image, string type, string[] option_keys, string[] option_values) throws Error
    {
        image.save_to_callbackv (write_pixbuf_data, type, option_keys, option_values);
    }

    private bool write_pixbuf_data (uint8[] buf) throws Error
    {
        stream.write_all (buf, null, null);
        return true;
    }
}
