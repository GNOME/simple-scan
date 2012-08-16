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

public enum CropLocation
{
    NONE = 0,
    MIDDLE,
    TOP,
    BOTTOM,
    LEFT,
    RIGHT,
    TOP_LEFT,
    TOP_RIGHT,
    BOTTOM_LEFT,
    BOTTOM_RIGHT
}

public class PageView
{
    /* Page being rendered */
    private Page page;

    /* Image to render at current resolution */
    private Gdk.Pixbuf? image = null;

    /* Border around image */
    private bool selected;
    private int border_width = 1;

    /* True if image needs to be regenerated */
    private bool update_image = true;

    /* Direction of currently scanned image */
    private ScanDirection scan_direction;

    /* Next scan line to render */
    private int scan_line;

    /* Dimensions of image to generate */
    private int width;
    private int height;

    /* Location to place this page */
    private int x_offset;
    private int y_offset;

    private CropLocation crop_location;
    private double selected_crop_px;
    private double selected_crop_py;
    private int selected_crop_x;
    private int selected_crop_y;
    private int selected_crop_w;
    private int selected_crop_h;

    /* Cursor over this page */
    private Gdk.CursorType cursor = Gdk.CursorType.ARROW;

    private int animate_n_segments = 7;
    private int animate_segment;
    private uint animate_timeout;

    public signal void size_changed ();
    public signal void changed ();

    public PageView (Page page)
    {
        this.page = page;
        page.pixels_changed.connect (page_pixels_changed_cb);
        page.size_changed.connect (page_size_changed_cb);
        page.crop_changed.connect (page_overlay_changed_cb);
        page.scan_line_changed.connect (page_overlay_changed_cb);
        page.scan_direction_changed.connect (scan_direction_changed_cb);
    }

    ~PageView ()
    {
        page.pixels_changed.disconnect (page_pixels_changed_cb);
        page.size_changed.disconnect (page_size_changed_cb);
        page.crop_changed.disconnect (page_overlay_changed_cb);
        page.scan_line_changed.disconnect (page_overlay_changed_cb);
        page.scan_direction_changed.disconnect (scan_direction_changed_cb);
    }

    public Page get_page ()
    {
        return page;
    }

    public void set_selected (bool selected)
    {
        if ((this.selected && selected) || (!this.selected && !selected))
            return;
        this.selected = selected;
        changed ();
    }

    public bool get_selected ()
    {
        return selected;
    }

    public void set_x_offset (int offset)
    {
        x_offset = offset;
    }

    public void set_y_offset (int offset)
    {
        y_offset = offset;
    }

    public int get_x_offset ()
    {
        return x_offset;
    }

    public int get_y_offset ()
    {
        return y_offset;
    }

    private uchar get_sample (uchar[] pixels, int offset, int x, int depth, int sample)
    {
        // FIXME
        return 0xFF;
    }

    private void get_pixel (Page page, int x, int y, uchar[] pixel)
    {
        switch (page.get_scan_direction ())
        {
        case ScanDirection.TOP_TO_BOTTOM:
            break;
        case ScanDirection.BOTTOM_TO_TOP:
            x = page.get_scan_width () - x - 1;
            y = page.get_scan_height () - y - 1;
            break;
        case ScanDirection.LEFT_TO_RIGHT:
            var t = x;
            x = page.get_scan_width () - y - 1;
            y = t;
            break;
        case ScanDirection.RIGHT_TO_LEFT:
            var t = x;
            x = y;
            y = page.get_scan_height () - t - 1;
            break;
        }

        var depth = page.get_depth ();
        var n_channels = page.get_n_channels ();
        unowned uchar[] pixels = page.get_pixels ();
        var offset = page.get_rowstride () * y;

        /* Optimise for 8 bit images */
        if (depth == 8 && n_channels == 3)
        {
            var o = offset + x * n_channels;
            pixel[0] = pixels[o];
            pixel[1] = pixels[o+1];
            pixel[2] = pixels[o+2];
            return;
        }
        else if (depth == 8 && n_channels == 1)
        {
            pixel[0] = pixel[1] = pixel[2] = pixels[offset + x];
            return;
        }

        /* Optimise for bitmaps */
        else if (depth == 1 && n_channels == 1)
        {
            var o = offset + (x / 8);
            pixel[0] = pixel[1] = pixel[2] = (pixels[o] & (0x80 >> (x % 8))) != 0 ? 0x00 : 0xFF;
            return;
        }

        /* Optimise for 2 bit images */
        else if (depth == 2 && n_channels == 1)
        {
            int block_shift[4] = { 6, 4, 2, 0 };

            var o = offset + (x / 4);
            var sample = (pixels[o] >> block_shift[x % 4]) & 0x3;
            sample = sample * 255 / 3;

            pixel[0] = pixel[1] = pixel[2] = (uchar) sample;
            return;
        }

        /* Use slow method */
        pixel[0] = get_sample (pixels, offset, x, depth, x * n_channels);
        pixel[1] = get_sample (pixels, offset, x, depth, x * n_channels + 1);
        pixel[2] = get_sample (pixels, offset, x, depth, x * n_channels + 2);
    }

    private void set_pixel (Page page, double l, double r, double t, double b, uchar[] output, int offset)
    {
        /* Decimation:
         *
         * Target pixel is defined by (t,l)-(b,r)
         * It touches 16 pixels in original image
         * It completely covers 4 pixels in original image (T,L)-(B,R)
         * Add covered pixels and add weighted partially covered pixels.
         * Divide by total area.
         *
         *      l  L           R   r
         *   +-----+-----+-----+-----+
         *   |     |     |     |     |
         * t |  +--+-----+-----+---+ |
         * T +--+--+-----+-----+---+-+
         *   |  |  |     |     |   | |
         *   |  |  |     |     |   | |
         *   +--+--+-----+-----+---+-+
         *   |  |  |     |     |   | |
         *   |  |  |     |     |   | |
         * B +--+--+-----+-----+---+-+
         *   |  |  |     |     |   | |
         * b |  +--+-----+-----+---+ |
         *   +-----+-----+-----+-----+
         *
         *
         * Interpolation:
         *
         *             l    r
         *   +-----+-----+-----+-----+
         *   |     |     |     |     |
         *   |     |     |     |     |
         *   +-----+-----+-----+-----+
         * t |     |   +-+--+  |     |
         *   |     |   | |  |  |     |
         *   +-----+---+-+--+--+-----+
         * b |     |   +-+--+  |     |
         *   |     |     |     |     |
         *   +-----+-----+-----+-----+
         *   |     |     |     |     |
         *   |     |     |     |     |
         *   +-----+-----+-----+-----+
         *
         * Same again, just no completely covered pixels.
         */

        var L = (int) l;
        if (L != l)
            L++;
        var R = (int) r;
        var T = (int) t;
        if (T != t)
            T++;
        var B = (int) b;

        var red = 0.0;
        var green = 0.0;
        var blue = 0.0;

        /* Target can fit inside one source pixel
         * +-----+
         * |     |
         * | +--+|      +-----+-----+      +-----+      +-----+      +-----+
         * +-+--++  or  |   +-++    |  or  | +-+ |  or  | +--+|  or  |  +--+
         * | +--+|      |   +-++    |      | +-+ |      | |  ||      |  |  |
         * |     |      +-----+-----+      +-----+      +-+--++      +--+--+
         * +-----+
         */
        if ((r - l <= 1.0 && (int)r == (int)l) || (b - t <= 1.0 && (int)b == (int)t))
        {
            /* Inside */
            if ((int)l == (int)r || (int)t == (int)b)
            {
                uchar p[3];
                get_pixel (page, (int)l, (int)t, p);
                output[offset] = p[0];
                output[offset+1] = p[1];
                output[offset+2] = p[2];
                return;
            }

            /* Stradling horizontal edge */
            if (L > R)
            {
                uchar p[3];
                get_pixel (page, R, T-1, p);
                red   += p[0] * (r-l)*(T-t);
                green += p[1] * (r-l)*(T-t);
                blue  += p[2] * (r-l)*(T-t);
                for (var y = T; y < B; y++)
                {
                    get_pixel (page, R, y, p);
                    red   += p[0] * (r-l);
                    green += p[1] * (r-l);
                    blue  += p[2] * (r-l);
                }
                get_pixel (page, R, B, p);
                red   += p[0] * (r-l)*(b-B);
                green += p[1] * (r-l)*(b-B);
                blue  += p[2] * (r-l)*(b-B);
            }
            /* Stradling vertical edge */
            else
            {
                uchar p[3];
                get_pixel (page, L - 1, B, p);
                red   += p[0] * (b-t)*(L-l);
                green += p[1] * (b-t)*(L-l);
                blue  += p[2] * (b-t)*(L-l);
                for (var x = L; x < R; x++) {
                    get_pixel (page, x, B, p);
                    red   += p[0] * (b-t);
                    green += p[1] * (b-t);
                    blue  += p[2] * (b-t);
                }
                get_pixel (page, R, B, p);
                red   += p[0] * (b-t)*(r-R);
                green += p[1] * (b-t)*(r-R);
                blue  += p[2] * (b-t)*(r-R);
            }

            var scale = 1.0 / ((r - l) * (b - t));
            output[offset] = (uchar)(red * scale + 0.5);
            output[offset+1] = (uchar)(green * scale + 0.5);
            output[offset+2] = (uchar)(blue * scale + 0.5);
            return;
        }

        /* Add the middle pixels */
        for (var x = L; x < R; x++)
        {
            for (var y = T; y < B; y++)
            {
                uchar p[3];
                get_pixel (page, x, y, p);
                red   += p[0];
                green += p[1];
                blue  += p[2];
            }
        }

        /* Add the weighted top and bottom pixels */
        for (var x = L; x < R; x++)
        {
            if (t != T)
            {
                uchar p[3];
                get_pixel (page, x, T - 1, p);
                red   += p[0] * (T - t);
                green += p[1] * (T - t);
                blue  += p[2] * (T - t);
            }

            if (b != B)
            {
                uchar p[3];
                get_pixel (page, x, B, p);
                red   += p[0] * (b - B);
                green += p[1] * (b - B);
                blue  += p[2] * (b - B);
            }
        }

        /* Add the left and right pixels */
        for (var y = T; y < B; y++)
        {
            if (l != L)
            {
                uchar p[3];
                get_pixel (page, L - 1, y, p);
                red   += p[0] * (L - l);
                green += p[1] * (L - l);
                blue  += p[2] * (L - l);
            }

            if (r != R)
            {
                uchar p[3];
                get_pixel (page, R, y, p);
                red   += p[0] * (r - R);
                green += p[1] * (r - R);
                blue  += p[2] * (r - R);
            }
        }

        /* Add the corner pixels */
        if (l != L && t != T)
        {
            uchar p[3];
            get_pixel (page, L - 1, T - 1, p);
            red   += p[0] * (L - l)*(T - t);
            green += p[1] * (L - l)*(T - t);
            blue  += p[2] * (L - l)*(T - t);
        }
        if (r != R && t != T)
        {
            uchar p[3];
            get_pixel (page, R, T - 1, p);
            red   += p[0] * (r - R)*(T - t);
            green += p[1] * (r - R)*(T - t);
            blue  += p[2] * (r - R)*(T - t);
        }
        if (r != R && b != B)
        {
            uchar p[3];
            get_pixel (page, R, B, p);
            red   += p[0] * (r - R)*(b - B);
            green += p[1] * (r - R)*(b - B);
            blue  += p[2] * (r - R)*(b - B);
        }
        if (l != L && b != B)
        {
            uchar p[3];
            get_pixel (page, L - 1, B, p);
            red   += p[0] * (L - l)*(b - B);
            green += p[1] * (L - l)*(b - B);
            blue  += p[2] * (L - l)*(b - B);
        }

        /* Scale pixel values and clamp in range [0, 255] */
        var scale = 1.0 / ((r - l) * (b - t));
        output[offset] = (uchar)(red * scale + 0.5);
        output[offset+1] = (uchar)(green * scale + 0.5);
        output[offset+2] = (uchar)(blue * scale + 0.5);
    }

    private void update_preview (Page page, ref Gdk.Pixbuf? output_image, int output_width, int output_height,
                                 ScanDirection scan_direction, int old_scan_line, int scan_line)
    {
        var input_width = page.get_width ();
        var input_height = page.get_height ();

        /* Create new image if one does not exist or has changed size */
        int L, R, T, B;
        if (output_image == null ||
            output_image.get_width () != output_width ||
            output_image.get_height () != output_height)
        {
            output_image = new Gdk.Pixbuf (Gdk.Colorspace.RGB,
                                           false,
                                           8,
                                           output_width,
                                           output_height);

            /* Update entire image */
            L = 0;
            R = output_width - 1;
            T = 0;
            B = output_height - 1;
        }
        /* Otherwise only update changed area */
        else
        {
            switch (scan_direction)
            {
            case ScanDirection.TOP_TO_BOTTOM:
                L = 0;
                R = output_width - 1;
                T = (int)((double)old_scan_line * output_height / input_height);
                B = (int)((double)scan_line * output_height / input_height + 0.5);
                break;
            case ScanDirection.LEFT_TO_RIGHT:
                L = (int)((double)old_scan_line * output_width / input_width);
                R = (int)((double)scan_line * output_width / input_width + 0.5);
                T = 0;
                B = output_height - 1;
                break;
            case ScanDirection.BOTTOM_TO_TOP:
                L = 0;
                R = output_width - 1;
                T = (int)((double)(input_height - scan_line) * output_height / input_height);
                B = (int)((double)(input_height - old_scan_line) * output_height / input_height + 0.5);
                break;
            case ScanDirection.RIGHT_TO_LEFT:
                L = (int)((double)(input_width - scan_line) * output_width / input_width);
                R = (int)((double)(input_width - old_scan_line) * output_width / input_width + 0.5);
                T = 0;
                B = output_height - 1;
                break;
            default:
                L = R = B = T = 0;
                break;
            }
        }

        /* FIXME: There's an off by one error in there somewhere... */
        if (R >= output_width)
            R = output_width - 1;
        if (B >= output_height)
            B = output_height - 1;

        return_if_fail (L >= 0);
        return_if_fail (R < output_width);
        return_if_fail (T >= 0);
        return_if_fail (B < output_height);
        return_if_fail (output_image != null);

        unowned uchar[] output = output_image.get_pixels ();
        var output_rowstride = output_image.get_rowstride ();
        var output_n_channels = output_image.get_n_channels ();

        if (!page.has_data ())
        {
            for (var x = L; x <= R; x++)
                for (var y = T; y <= B; y++)
                {
                    var o = output_rowstride * y + x * output_n_channels;
                    output[o] = output[o+1] = output[o+2] = 0xFF;
                }
            return;
        }

        /* Update changed area */
        for (var x = L; x <= R; x++)
        {
            var l = (double)x * input_width / output_width;
            var r = (double)(x + 1) * input_width / output_width;

            for (var y = T; y <= B; y++)
            {
                var t = (double)y * input_height / output_height;
                var b = (double)(y + 1) * input_height / output_height;

                set_pixel (page,
                           l, r, t, b,
                           output, output_rowstride * y + x * output_n_channels);
            }
        }
    }

    private int get_preview_width ()
    {
        return width - border_width * 2;
    }

    private int get_preview_height ()
    {
        return height - border_width * 2;
    }

    private void update_page_view ()
    {
        if (!update_image)
            return;

        var old_scan_line = scan_line;
        var scan_line = page.get_scan_line ();

        /* Delete old image if scan direction changed */
        var left_steps = scan_direction - page.get_scan_direction ();
        if (left_steps != 0 && image != null)
            image = null;
        scan_direction = page.get_scan_direction ();

        update_preview (page,
                        ref image,
                        get_preview_width (),
                        get_preview_height (),
                        page.get_scan_direction (), old_scan_line, scan_line);

        update_image = false;
        this.scan_line = scan_line;
    }

    private int page_to_screen_x (int x)
    {
        return (int) ((double)x * get_preview_width () / page.get_width () + 0.5);
    }

    private int page_to_screen_y (int y)
    {
        return (int) ((double)y * get_preview_height () / page.get_height () + 0.5);
    }

    private int screen_to_page_x (int x)
    {
        return (int) ((double)x * page.get_width () / get_preview_width () + 0.5);
    }

    private int screen_to_page_y (int y)
    {
        return (int) ((double)y * page.get_height () / get_preview_height () + 0.5);
    }

    private CropLocation get_crop_location (int x, int y)
    {
        if (!page.has_crop ())
            return 0;

        int cx, cy, cw, ch;
        page.get_crop (out cx, out cy, out cw, out ch);
        var dx = page_to_screen_x (cx);
        var dy = page_to_screen_y (cy);
        var dw = page_to_screen_x (cw);
        var dh = page_to_screen_y (ch);
        var ix = x - dx;
        var iy = y - dy;

        if (ix < 0 || ix > dw || iy < 0 || iy > dh)
            return CropLocation.NONE;

        /* Can't resize named crops */
        var name = page.get_named_crop ();
        if (name != null)
            return CropLocation.MIDDLE;

        /* Adjust borders so can select */
        int crop_border = 20;
        if (dw < crop_border * 3)
            crop_border = dw / 3;
        if (dh < crop_border * 3)
            crop_border = dh / 3;

        /* Top left */
        if (ix < crop_border && iy < crop_border)
            return CropLocation.TOP_LEFT;
        /* Top right */
        if (ix > dw - crop_border && iy < crop_border)
            return CropLocation.TOP_RIGHT;
        /* Bottom left */
        if (ix < crop_border && iy > dh - crop_border)
            return CropLocation.BOTTOM_LEFT;
        /* Bottom right */
        if (ix > dw - crop_border && iy > dh - crop_border)
            return CropLocation.BOTTOM_RIGHT;

        /* Left */
        if (ix < crop_border)
            return CropLocation.LEFT;
        /* Right */
        if (ix > dw - crop_border)
            return CropLocation.RIGHT;
        /* Top */
        if (iy < crop_border)
            return CropLocation.TOP;
        /* Bottom */
        if (iy > dh - crop_border)
            return CropLocation.BOTTOM;

        /* In the middle */
        return CropLocation.MIDDLE;
    }

    public void button_press (int x, int y)
    {
        CropLocation location;

        /* See if selecting crop */
        location = get_crop_location (x, y);;
        if (location != CropLocation.NONE)
        {
            crop_location = location;
            selected_crop_px = x;
            selected_crop_py = y;
            page.get_crop (out selected_crop_x,
                           out selected_crop_y,
                           out selected_crop_w,
                           out selected_crop_h);
        }
    }

    public void motion (int x, int y)
    {
        var location = get_crop_location (x, y);
        Gdk.CursorType cursor;
        switch (location)
        {
        case CropLocation.MIDDLE:
            cursor = Gdk.CursorType.HAND1;
            break;
        case CropLocation.TOP:
            cursor = Gdk.CursorType.TOP_SIDE;
            break;
        case CropLocation.BOTTOM:
            cursor = Gdk.CursorType.BOTTOM_SIDE;
            break;
        case CropLocation.LEFT:
            cursor = Gdk.CursorType.LEFT_SIDE;
            break;
        case CropLocation.RIGHT:
            cursor = Gdk.CursorType.RIGHT_SIDE;
            break;
        case CropLocation.TOP_LEFT:
            cursor = Gdk.CursorType.TOP_LEFT_CORNER;
            break;
        case CropLocation.TOP_RIGHT:
            cursor = Gdk.CursorType.TOP_RIGHT_CORNER;
            break;
        case CropLocation.BOTTOM_LEFT:
            cursor = Gdk.CursorType.BOTTOM_LEFT_CORNER;
            break;
        case CropLocation.BOTTOM_RIGHT:
            cursor = Gdk.CursorType.BOTTOM_RIGHT_CORNER;
            break;
        default:
            cursor = Gdk.CursorType.ARROW;
            break;
        }

        if (crop_location == CropLocation.NONE)
        {
            this.cursor = cursor;
            return;
        }

        /* Move the crop */
        var pw = page.get_width ();
        var ph = page.get_height ();
        int cx, cy, cw, ch;
        page.get_crop (out cx, out cy, out cw, out ch);

        var dx = screen_to_page_x (x - (int) selected_crop_px);
        var dy = screen_to_page_y (y - (int) selected_crop_py);

        var new_x = selected_crop_x;
        var new_y = selected_crop_y;
        var new_w = selected_crop_w;
        var new_h = selected_crop_h;

        /* Limit motion to remain within page and minimum crop size */
        var min_size = screen_to_page_x (15);
        if (crop_location == CropLocation.TOP_LEFT ||
            crop_location == CropLocation.LEFT ||
            crop_location == CropLocation.BOTTOM_LEFT)
        {
            if (dx > new_w - min_size)
                dx = new_w - min_size;
            if (new_x + dx < 0)
                dx = -new_x;
        }
        if (crop_location == CropLocation.TOP_LEFT ||
            crop_location == CropLocation.TOP ||
            crop_location == CropLocation.TOP_RIGHT)
        {
            if (dy > new_h - min_size)
                dy = new_h - min_size;
            if (new_y + dy < 0)
                dy = -new_y;
        }

        if (crop_location == CropLocation.TOP_RIGHT ||
            crop_location == CropLocation.RIGHT ||
            crop_location == CropLocation.BOTTOM_RIGHT)
        {
            if (dx < min_size - new_w)
                dx = min_size - new_w;
            if (new_x + new_w + dx > pw)
                dx = pw - new_x - new_w;
        }
        if (crop_location == CropLocation.BOTTOM_LEFT ||
            crop_location == CropLocation.BOTTOM ||
            crop_location == CropLocation.BOTTOM_RIGHT)
        {
            if (dy < min_size - new_h)
                dy = min_size - new_h;
            if (new_y + new_h + dy > ph)
                dy = ph - new_y - new_h;
        }
        if (crop_location == CropLocation.MIDDLE)
        {
            if (new_x + dx + new_w > pw)
                dx = pw - new_x - new_w;
            if (new_x + dx < 0)
                dx = -new_x;
            if (new_y + dy + new_h > ph)
                dy = ph - new_y - new_h;
            if (new_y + dy  < 0)
                dy = -new_y;
        }

        /* Move crop */
        if (crop_location == CropLocation.MIDDLE)
        {
            new_x += dx;
            new_y += dy;
        }
        if (crop_location == CropLocation.TOP_LEFT ||
            crop_location == CropLocation.LEFT ||
            crop_location == CropLocation.BOTTOM_LEFT)
        {
            new_x += dx;
            new_w -= dx;
        }
        if (crop_location == CropLocation.TOP_LEFT ||
            crop_location == CropLocation.TOP ||
            crop_location == CropLocation.TOP_RIGHT)
        {
            new_y += dy;
            new_h -= dy;
        }

        if (crop_location == CropLocation.TOP_RIGHT ||
            crop_location == CropLocation.RIGHT ||
            crop_location == CropLocation.BOTTOM_RIGHT)
            new_w += dx;
        if (crop_location == CropLocation.BOTTOM_LEFT ||
            crop_location == CropLocation.BOTTOM ||
            crop_location == CropLocation.BOTTOM_RIGHT)
            new_h += dy;

        page.move_crop (new_x, new_y);

        /* If reshaped crop, must be a custom crop */
        if (new_w != cw || new_h != ch)
            page.set_custom_crop (new_w, new_h);
    }

    public void button_release (int x, int y)
    {
        /* Complete crop */
        crop_location = CropLocation.NONE;
        changed ();
    }

    public Gdk.CursorType get_cursor ()
    {
        return cursor;
    }

    private bool animation_cb ()
    {
        animate_segment = (animate_segment + 1) % animate_n_segments;
        changed ();
        return true;
    }

    private void update_animation ()
    {
        bool animate, is_animating;

        animate = page.is_scanning () && !page.has_data ();
        is_animating = animate_timeout != 0;
        if (animate == is_animating)
            return;

        if (animate)
        {
            animate_segment = 0;
            if (animate_timeout == 0)
                animate_timeout = Timeout.add (150, animation_cb);
        }
        else
        {
            if (animate_timeout != 0)
                Source.remove (animate_timeout);
            animate_timeout = 0;
        }
    }

    public void render (Cairo.Context context)
    {
        update_animation ();
        update_page_view ();

        var w = get_preview_width ();
        var h = get_preview_height ();

        context.set_line_width (1);
        context.translate (x_offset, y_offset);

        /* Draw page border */
        context.set_source_rgb (0, 0, 0);
        context.set_line_width (border_width);
        context.rectangle ((double)border_width / 2,
                           (double)border_width / 2,
                           width - border_width,
                           height - border_width);
        context.stroke ();

        /* Draw image */
        context.translate (border_width, border_width);
        Gdk.cairo_set_source_pixbuf (context, image, 0, 0);
        context.paint ();

        /* Draw throbber */
        if (page.is_scanning () && !page.has_data ())
        {
            double outer_radius;
            if (w > h)
                outer_radius = 0.15 * w;
            else
                outer_radius = 0.15 * h;
            var arc = Math.PI / animate_n_segments;

            /* Space circles */
            var x = outer_radius * Math.sin (arc);
            var y = outer_radius * (Math.cos (arc) - 1.0);
            var inner_radius = 0.6 * Math.sqrt (x*x + y*y);

            double offset = 0.0;
            for (var i = 0; i < animate_n_segments; i++, offset += arc * 2)
            {
                x = w / 2 + outer_radius * Math.sin (offset);
                y = h / 2 - outer_radius * Math.cos (offset);
                context.arc (x, y, inner_radius, 0, 2 * Math.PI);

                if (i == animate_segment)
                {
                    context.set_source_rgb (0.75, 0.75, 0.75);
                    context.fill_preserve ();
                }

                context.set_source_rgb (0.5, 0.5, 0.5);
                context.stroke ();
            }
        }

        /* Draw scan line */
        if (page.is_scanning () && page.get_scan_line () > 0)
        {
            var scan_line = page.get_scan_line ();

            double s;
            double x1, y1, x2, y2;
            switch (page.get_scan_direction ())
            {
            case ScanDirection.TOP_TO_BOTTOM:
                s = page_to_screen_y (scan_line);
                x1 = 0; y1 = s + 0.5;
                x2 = w; y2 = s + 0.5;
                break;
            case ScanDirection.BOTTOM_TO_TOP:
                s = page_to_screen_y (scan_line);
                x1 = 0; y1 = h - s + 0.5;
                x2 = w; y2 = h - s + 0.5;
                break;
            case ScanDirection.LEFT_TO_RIGHT:
                s = page_to_screen_x (scan_line);
                x1 = s + 0.5; y1 = 0;
                x2 = s + 0.5; y2 = h;
                break;
            case ScanDirection.RIGHT_TO_LEFT:
                s = page_to_screen_x (scan_line);
                x1 = w - s + 0.5; y1 = 0;
                x2 = w - s + 0.5; y2 = h;
                break;
            default:
                x1 = y1 = x2 = y2 = 0;
                break;
            }

            context.move_to (x1, y1);
            context.line_to (x2, y2);
            context.set_source_rgb (1.0, 0.0, 0.0);
            context.stroke ();
        }

        /* Draw crop */
        if (page.has_crop ())
        {
            int x, y, crop_width, crop_height;
            page.get_crop (out x, out y, out crop_width, out crop_height);

            var dx = page_to_screen_x (x);
            var dy = page_to_screen_y (y);
            var dw = page_to_screen_x (crop_width);
            var dh = page_to_screen_y (crop_height);

            /* Shade out cropped area */
            context.rectangle (0, 0, w, h);
            context.new_sub_path ();
            context.rectangle (dx, dy, dw, dh);
            context.set_fill_rule (Cairo.FillRule.EVEN_ODD);
            context.set_source_rgba (0.25, 0.25, 0.25, 0.2);
            context.fill ();

            /* Show new edge */
            context.rectangle (dx - 1.5, dy - 1.5, dw + 3, dh + 3);
            context.set_source_rgb (1.0, 1.0, 1.0);
            context.stroke ();
            context.rectangle (dx - 0.5, dy - 0.5, dw + 1, dh + 1);
            context.set_source_rgb (0.0, 0.0, 0.0);
            context.stroke ();
        }
    }

    public void set_width (int width)
    {
        // FIXME: Automatically update when get updated image
        var height = (int) ((double)width * page.get_height () / page.get_width ());
        if (this.width == width && this.height == height)
            return;

        this.width = width;
        this.height = height;

        /* Regenerate image */
        update_image = true;

        size_changed ();
        changed ();
    }

    public void set_height (int height)
    {
        // FIXME: Automatically update when get updated image
        var width = (int) ((double)height * page.get_width () / page.get_height ());
        if (this.width == width && this.height == height)
            return;

        this.width = width;
        this.height = height;

        /* Regenerate image */
        update_image = true;

        size_changed ();
        changed ();
    }

    public int get_width ()
    {
        return width;
    }

    public int get_height ()
    {
        return height;
    }

    private void page_pixels_changed_cb (Page p)
    {
        /* Regenerate image */
        update_image = true;
        changed ();
    }

    private void page_size_changed_cb (Page p)
    {
        /* Regenerate image */
        update_image = true;
        size_changed ();
        changed ();
    }

    private void page_overlay_changed_cb (Page p)
    {
        changed ();
    }

    private void scan_direction_changed_cb (Page p)
    {
        /* Regenerate image */
        update_image = true;
        size_changed ();
        changed ();
    }
}
