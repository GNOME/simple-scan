/*
 * Copyright (C) 2009-2015 Canonical Ltd.
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

public class Page : Object
{
    /* Width of the page in pixels after rotation applied */
    public int width
    {
        get
        {
            if (scan_direction == ScanDirection.TOP_TO_BOTTOM || scan_direction == ScanDirection.BOTTOM_TO_TOP)
                return scan_width;
            else
                return scan_height;
        }
    }

    /* Height of the page in pixels after rotation applied */
    public int height
    {
        get
        {
            if (scan_direction == ScanDirection.TOP_TO_BOTTOM || scan_direction == ScanDirection.BOTTOM_TO_TOP)
                return scan_height;
            else
                return scan_width;
        }
    }

    /* true if the page is landscape (wider than the height) */
    public bool is_landscape { get { return width > height; } }

    /* Resolution of page */
    public int dpi { get; private set; }

    /* Number of rows in this page or -1 if currently unknown */
    private int expected_rows;

    /* Bit depth */
    public int depth { get; private set; }

    /* Color profile */
    public string? color_profile { get; set; }

    /* Width of raw scan data in pixels */
    public int scan_width { get; private set; }

    /* Height of raw scan data in pixels */
    public int scan_height { get; private set; }

    /* Offset between rows in scan data */
    public int rowstride { get; private set; }

    /* Number of color channels */
    public int n_channels { get; private set; }

    /* Pixel data */
    private uchar[] pixels;

    /* Page is getting data */
    public bool is_scanning { get; private set; }

    /* true if have some page data */
    public bool has_data { get; private set; }

    /* Expected next scan row */
    public int scan_line { get; private set; }

    /* true if scan contains color information */
    public bool is_color { get { return n_channels > 1; } }

    /* Rotation of scanned data */
    private ScanDirection scan_direction_ = ScanDirection.TOP_TO_BOTTOM;
    public ScanDirection scan_direction
    {
        get { return scan_direction_; }

        set
        {
            if (scan_direction_ == value)
                return;

            /* Work out how many times it has been rotated to the left */
            var size_has_changed = false;
            var left_steps = (int) (value - scan_direction_);
            if (left_steps < 0)
                left_steps += 4;
            if (left_steps != 2)
                size_has_changed = true;

            /* Rotate crop */
            if (has_crop)
            {
                switch (left_steps)
                {
                /* 90 degrees counter-clockwise */
                case 1:
                    var t = crop_x;
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
                    var t = crop_y;
                    crop_y = crop_x;
                    crop_x = height - (t + crop_height);
                    t = crop_width;
                    crop_width = crop_height;
                    crop_height = t;
                    break;
                }
            }

            scan_direction_ = value;
            if (size_has_changed)
                size_changed ();
            scan_direction_changed ();
            if (has_crop)
                crop_changed ();
        }
    }

    /* True if the page has a crop set */
    public bool has_crop { get; private set; }

    /* Name of the crop if using a named crop */
    public string? crop_name { get; private set; }

    /* X co-ordinate of top left crop corner */
    public int crop_x { get; private set; }

    /* Y co-ordinate of top left crop corner */
    public int crop_y { get; private set; }

    /* Width of crop in pixels */
    public int crop_width { get; private set; }

    /* Height of crop in pixels*/
    public int crop_height { get; private set; }

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
            scan_width = width;
            scan_height = height;
        }
        else
        {
            scan_width = height;
            scan_height = width;
        }
        this.dpi = dpi;
        this.scan_direction = scan_direction;
    }

    public Page.from_data (int scan_width,
                           int scan_height,
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
        this.scan_width = scan_width;
        this.scan_height = scan_height;
        this.expected_rows = scan_height;
        this.rowstride = rowstride;
        this.n_channels = n_channels;
        this.depth = depth;
        this.dpi = dpi;
        this.scan_direction = scan_direction;
        this.color_profile = color_profile;
        this.pixels = pixels;
        has_data = pixels != null;
        this.has_crop = has_crop;
        this.crop_name = crop_name;
        this.crop_x = crop_x;
        this.crop_y = crop_y;
        this.crop_width = (crop_x + crop_width > scan_width) ? scan_width : crop_width;
        this.crop_height = (crop_y + crop_height > scan_height) ? scan_height : crop_height;
    }
    
    public Page copy()
    {
        var copy = new Page.from_data (
            scan_width,
            scan_height,
            rowstride,
            n_channels,
            depth,
            dpi,
            scan_direction,
            color_profile,
            pixels,
            has_crop,
            crop_name,
            crop_x,
            crop_y,
            crop_width,
            crop_height
        );
        
        copy.scan_line = scan_line;
        
        return copy;
    }

    public void set_page_info (ScanPageInfo info)
    {
        expected_rows = info.height;
        dpi = (int) info.dpi;

        /* Create a white page */
        scan_width = info.width;
        scan_height = info.height;
        /* Variable height, try 50% of the width for now */
        if (scan_height < 0)
            scan_height = scan_width / 2;
        depth = info.depth;
        n_channels = info.n_channels;
        rowstride = (scan_width * depth * n_channels + 7) / 8;
        pixels.resize (scan_height * rowstride);
        return_if_fail (pixels != null);

        /* Fill with white */
        if (depth == 1)
            Memory.set (pixels, 0x00, scan_height * rowstride);
        else
            Memory.set (pixels, 0xFF, scan_height * rowstride);

        size_changed ();
        pixels_changed ();
    }

    public void start ()
    {
        is_scanning = true;
        scan_line_changed ();
    }

    private void parse_line (ScanLine line, int n, out bool size_changed)
    {
        var line_number = line.number + n;

        /* Extend image if necessary */
        size_changed = false;
        while (line_number >= scan_height)
        {
            /* Extend image */
            var rows = scan_height;
            scan_height = rows + scan_width / 2;
            debug ("Extending image from %d lines to %d lines", rows, scan_height);
            pixels.resize (scan_height * rowstride);

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

        has_data = true;

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
            scan_line != scan_height)
        {
            var rows = scan_height;
            scan_height = scan_line;
            pixels.resize (scan_height * rowstride);
            debug ("Trimming page from %d lines to %d lines", rows, scan_height);

            size_has_changed = true;
        }
        is_scanning = false;

        if (size_has_changed)
            size_changed ();
        scan_line_changed ();
        scan_finished ();
    }

    public void rotate_left ()
    {
        switch (scan_direction)
        {
        case ScanDirection.TOP_TO_BOTTOM:
            scan_direction = ScanDirection.LEFT_TO_RIGHT;
            break;
        case ScanDirection.LEFT_TO_RIGHT:
            scan_direction = ScanDirection.BOTTOM_TO_TOP;
            break;
        case ScanDirection.BOTTOM_TO_TOP:
            scan_direction = ScanDirection.RIGHT_TO_LEFT;
            break;
        case ScanDirection.RIGHT_TO_LEFT:
            scan_direction = ScanDirection.TOP_TO_BOTTOM;
            break;
        }
    }

    public void rotate_right ()
    {
        switch (scan_direction)
        {
        case ScanDirection.TOP_TO_BOTTOM:
            scan_direction = ScanDirection.RIGHT_TO_LEFT;
            break;
        case ScanDirection.LEFT_TO_RIGHT:
            scan_direction = ScanDirection.TOP_TO_BOTTOM;
            break;
        case ScanDirection.BOTTOM_TO_TOP:
            scan_direction = ScanDirection.LEFT_TO_RIGHT;
            break;
        case ScanDirection.RIGHT_TO_LEFT:
            scan_direction = ScanDirection.BOTTOM_TO_TOP;
            break;
        }
    }

    public void set_no_crop ()
    {
        if (!has_crop)
            return;
        has_crop = false;
        crop_name = null;
        crop_x = 0;
        crop_y = 0;
        crop_width = 0;
        crop_height = 0;
        crop_changed ();
    }

    public void set_custom_crop (int width, int height)
    {
        return_if_fail (width >= 1);
        return_if_fail (height >= 1);

        if (crop_name == null && has_crop && crop_width == width && crop_height == height)
            return;
        crop_name = null;
        has_crop = true;

        crop_width = width;
        crop_height = height;

        /*var pw = width;
        var ph = height;
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
        double w, h;
        switch (name)
        {
        case "A3":
            w = 11.692;
            h = 16.535;
            break;
        case "A4":
            w = 8.267;
            h = 11.692;
            break;
        case "A5":
            w = 5.846;
            h = 8.267;
            break;
        case "A6":
            w = 4.1335;
            h = 5.846;
            break;
        case "letter":
            w = 8.5;
            h = 11;
            break;
        case "legal":
            w = 8.5;
            h = 14;
            break;
        case "4x6":
            w = 4;
            h = 6;
            break;
        default:
            warning ("Unknown paper size '%s'", name);
            return;
        }

        crop_name = name;
        has_crop = true;

        var pw = width;
        var ph = height;

        /* Rotate to match original aspect */
        if (pw > ph)
        {
            var t = w;
            w = h;
            h = t;
        }

        /* Custom crop, make slightly smaller than original */
        crop_width = (int) (w * dpi + 0.5);
        crop_height = (int) (h * dpi + 0.5);

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
        return_if_fail (x < width);
        return_if_fail (y < height);

        crop_x = x;
        crop_y = y;
        crop_changed ();
    }

    public void rotate_crop ()
    {
        if (!has_crop)
            return;

        var t = crop_width;
        crop_width = crop_height;
        crop_height = t;

        /* Clip custom crops */
        if (crop_name == null)
        {
            var w = width;
            var h = height;

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
        switch (scan_direction)
        {
        case ScanDirection.TOP_TO_BOTTOM:
            break;
        case ScanDirection.BOTTOM_TO_TOP:
            x = scan_width - x - 1;
            y = scan_height - y - 1;
            break;
        case ScanDirection.LEFT_TO_RIGHT:
            var t = x;
            x = scan_width - y - 1;
            y = t;
            break;
        case ScanDirection.RIGHT_TO_LEFT:
            var t = x;
            x = y;
            y = scan_height - t - 1;
            break;
        }

        var line_offset = rowstride * y;

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
        if (apply_crop && has_crop)
        {
            l = crop_x;
            r = l + crop_width;
            t = crop_y;
            b = t + crop_height;

            if (l < 0)
                l = 0;
            if (r > width)
                r = width;
            if (t < 0)
                t = 0;
            if (b > height)
                b = height;
        }
        else
        {
            l = 0;
            r = width;
            t = 0;
            b = height;
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

    public string? get_icc_data_encoded ()
    {
        if (color_profile == null)
            return null;

        /* Get binary data */
        string contents;
        try
        {
            FileUtils.get_contents (color_profile, out contents);
        }
        catch (Error e)
        {
            warning ("failed to get icc profile data: %s", e.message);
            return null;
        }

        /* Encode into base64 */
        return Base64.encode ((uchar[]) contents.to_utf8 ());
    }

    public void copy_to_clipboard (Gtk.Window window)
    {
        var clipboard = window.get_clipboard();
        var image = get_image (true);
        clipboard.set_value (image);
    }

    public void save_png (File file) throws Error
    {
        var stream = file.replace (null, false, FileCreateFlags.NONE, null);
        var image = get_image (true);

        string? icc_profile_data = null;
        if (color_profile != null)
            icc_profile_data = get_icc_data_encoded ();

        string[] keys = { "x-dpi", "y-dpi", "icc-profile", null };
        string[] values = { "%d".printf (dpi), "%d".printf (dpi), icc_profile_data, null };
        if (icc_profile_data == null)
            keys[2] = null;

        image.save_to_callbackv ((buf) =>
        {
            stream.write_all (buf, null, null);
            return true;
        }, "png", keys, values);
    }
}
