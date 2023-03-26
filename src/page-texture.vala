/*
 * Copyright (C) 2009-2015 Canonical Ltd.
 * Author: Robert Ancell <robert.ancell@canonical.com>,
 *         Bartłomiej Maryńczak <marynczakbartlomiej@gmail.com>
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later
 * version. See http://www.gnu.org/copyleft/gpl.html the full text of the
 * license.
 */

private class PageToPixbuf : Object
{
    /* Image to render at current resolution */
    public Gdk.Pixbuf? pixbuf { get { return pixbuf_; } }
    private Gdk.Pixbuf? pixbuf_ = null;

    /* Direction of currently scanned image */
    private ScanDirection scan_direction;

    /* Next scan line to render */
    private int scan_line;

    /* Dimensions of image to generate */
    public int width;
    public int height;

    private static uchar get_sample (uchar[] pixels, int offset, int x, int depth, int sample)
    {
        // FIXME
        return 0xFF;
    }

    private static void get_pixel (Page page, int x, int y, uchar[] pixel)
    {
        switch (page.scan_direction)
        {
        case ScanDirection.TOP_TO_BOTTOM:
            break;
        case ScanDirection.BOTTOM_TO_TOP:
            x = page.scan_width - x - 1;
            y = page.scan_height - y - 1;
            break;
        case ScanDirection.LEFT_TO_RIGHT:
            var t = x;
            x = page.scan_width - y - 1;
            y = t;
            break;
        case ScanDirection.RIGHT_TO_LEFT:
            var t = x;
            x = y;
            y = page.scan_height - t - 1;
            break;
        }

        var depth = page.depth;
        var n_channels = page.n_channels;
        unowned uchar[] pixels = page.get_pixels ();
        var offset = page.rowstride * y;

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

    private static void set_pixel (Page page, double l, double r, double t, double b, uchar[] output, int offset)
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

    public static void update_preview (Page page, ref Gdk.Pixbuf? output_image, int output_width, int output_height,
                                 ScanDirection scan_direction, int old_scan_line, int scan_line)
    {
        var input_width = page.width;
        var input_height = page.height;

        /* Create new image if one does not exist or has changed size */
        int L, R, T, B;
        if (output_image == null ||
            output_image.width != output_width ||
            output_image.height != output_height)
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
        var output_rowstride = output_image.rowstride;
        var output_n_channels = output_image.n_channels;

        if (!page.has_data)
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

    public void update (Page page)
    {
        var old_scan_line = scan_line;
        scan_line = page.scan_line;

        /* Delete old image if scan direction changed */
        var left_steps = scan_direction - page.scan_direction;
        if (left_steps != 0 && pixbuf_ != null)
            pixbuf_ = null;
        scan_direction = page.scan_direction;

        update_preview (page,
                        ref pixbuf_,
                        width,
                        height,
                        page.scan_direction,
                        old_scan_line,
                        scan_line);
    }
}

/**
 * Just update texture contents
 */
private class TextureUpdateTask
{
    public Page page;
}

/**
 * Resize the texture
 */
private class TextureResizeTask: TextureUpdateTask
{
    public int width { get; private set; }
    public int height { get; private set; }
    
	public TextureResizeTask (int width, int height)
    {
        this.width = width;
        this.height = height;
	}
}

public class PageViewTexture : Object
{
    public Gdk.Pixbuf? pixbuf { get; private set; }
    public signal void new_buffer ();

    private int requested_width;
    private int requested_height;
    private TextureUpdateTask queued = null;

    private bool in_proggres;

    private ThreadPool<TextureUpdateTask> resize_pool;
    
    private Page page;
    
	public PageViewTexture (Page page)
    {
        this.page = page;

        try {
            resize_pool = new ThreadPool<TextureUpdateTask>.with_owned_data (thread_func, 1, false);
        }
        catch (ThreadError error)
        {
            // Pool is non-exclusive so this should never happen
        }
	}
    
    /**
     * Notify that data needs updating (eg. pixels changed during scanning process)
     */
    public void request_update ()
    {
        queued = new TextureUpdateTask ();
    }

    /**
     * Set size of the page, ignored if size did not change.
     */
    public void request_resize (int width, int height)
    {
        if (requested_width == width && requested_height == height)
        {
            return;
        }

        requested_width = width;
        requested_height = height;
        
        queued = new TextureResizeTask (requested_width, requested_height);
    }
    
    public void queue_update () throws ThreadError
    {
        if (in_proggres || queued == null)
        {
            return;
        }

        in_proggres = true;

        // We copy the page as it will be sent to resize thread
        queued.page = page.copy ();
        resize_pool.add (queued);

        queued = null;
    }

    private PageToPixbuf page_view = new PageToPixbuf ();
    private void thread_func(owned TextureUpdateTask task)
    {
        if (task is TextureResizeTask)
        {
            page_view.width = task.width;
            page_view.height = task.height;
        }

        page_view.update (task.page);
        
        Gdk.Pixbuf? new_pixbuf = null;
        if (page_view.pixbuf != null)
        {
            // We are sending this buffer back to main thread, therefore copy
            new_pixbuf = page_view.pixbuf.copy ();
        }


        Idle.add(() => {
            new_pixbuf_cb (new_pixbuf);
            return false;
        });
    }

    private void new_pixbuf_cb (Gdk.Pixbuf? pixbuf)
    {
        in_proggres = false;
        this.pixbuf = pixbuf;
        new_buffer ();
    }
}

public class PagePaintable: Gdk.Paintable, Object
{
    private Page page;
    private PageViewTexture page_texture;
    private Gdk.Texture? texture;
    
    public PagePaintable (Page page)
    {
        this.page = page;
        page.pixels_changed.connect (pixels_changed);
        page.size_changed.connect (pixels_changed);
        page.scan_direction_changed.connect (pixels_changed);

        page_texture = new PageViewTexture (page);
        page_texture.new_buffer.connect (texture_updated);

        pixels_changed ();
    }
    
    ~PagePaintable ()
    {
        page.pixels_changed.disconnect (pixels_changed);
        page.size_changed.disconnect (pixels_changed);
        page.scan_direction_changed.disconnect (pixels_changed);
        page_texture.new_buffer.disconnect (texture_updated);
    }
    
    private void pixels_changed ()
    {
        page_texture.request_update ();
        try {
            page_texture.queue_update ();
        }
        catch (Error e)
        {
            warning ("Failed to queue_update of the texture: %s", e.message);
            invalidate_contents ();
        }
    }

    private void texture_updated ()
    {
        if (page_texture.pixbuf != null)
            texture = Gdk.Texture.for_pixbuf(page_texture.pixbuf);
        else
            texture = null;

        invalidate_contents ();
    }

	public override double get_intrinsic_aspect_ratio ()
    {
        return (double) page.width / (double) page.height;
    }

    public void snapshot (Gdk.Snapshot gdk_snapshot, double width, double height) {
        var snapshot = (Gtk.Snapshot) gdk_snapshot;

        var rect = Graphene.Rect();
        rect.size.width = (float) width;
        rect.size.height = (float) height;

        page_texture.request_resize ((int) width, (int) height);

        try {
            page_texture.queue_update ();
        }
        catch (Error e)
        {
            warning ("Failed to queue_update of the texture: %s", e.message);
            // Ask for another redraw
            invalidate_contents ();
        }

        if (texture != null)
        {
            snapshot.append_texture(texture, rect);
        }
        else
        {
            snapshot.append_color ({1.0f, 1.0f, 1.0f, 1.0f}, rect);
        }
    }

}