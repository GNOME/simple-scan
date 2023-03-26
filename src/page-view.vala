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

public class PageView : Object
{
    /* Page being rendered */
    public Page page { get; private set; }

    /* Image to render at current resolution */
    private PageViewTexture page_texture;

    /* Border around image */
    private bool selected_ = false;
    public bool selected
    {
        get { return selected_; }
        set
        {
            if ((this.selected && selected) || (!this.selected && !selected))
                return;
            this.selected = selected;
            changed ();
        }
    }

    private int ruler_width = 8;

    private int border_width = 2;

    /* True if image needs to be regenerated */
    private bool update_image = true;

    /* Dimensions of image to generate */
    private int width_;
    private int height_;

    /* Location to place this page */
    public int x_offset { get; set; }
    public int y_offset { get; set; }

    private CropLocation crop_location;
    private double selected_crop_px;
    private double selected_crop_py;
    private int selected_crop_x;
    private int selected_crop_y;
    private int selected_crop_w;
    private int selected_crop_h;

    /* Cursor over this page */
    public string cursor { get; private set; default = "arrow"; }

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
        
        page_texture = new PageViewTexture(page);
        page_texture.new_buffer.connect (new_buffer_cb);
    }

    ~PageView ()
    {
        page.pixels_changed.disconnect (page_pixels_changed_cb);
        page.size_changed.disconnect (page_size_changed_cb);
        page.crop_changed.disconnect (page_overlay_changed_cb);
        page.scan_line_changed.disconnect (page_overlay_changed_cb);
        page.scan_direction_changed.disconnect (scan_direction_changed_cb);

        page_texture.new_buffer.disconnect (new_buffer_cb);
    }
    
    private void new_buffer_cb()
    {
        changed ();
    }

    private int get_preview_width ()
    {
        return width_ - (border_width + ruler_width) * 2;
    }

    private int get_preview_height ()
    {
        return height_ - (border_width + ruler_width) * 2;
    }

    private int page_to_screen_x (int x)
    {
        return (int) ((double)x * get_preview_width () / page.width + 0.5);
    }

    private int page_to_screen_y (int y)
    {
        return (int) ((double)y * get_preview_height () / page.height + 0.5);
    }

    private int screen_to_page_x (int x)
    {
        return (int) ((double)x * page.width / get_preview_width () + 0.5);
    }

    private int screen_to_page_y (int y)
    {
        return (int) ((double)y * page.height / get_preview_height () + 0.5);
    }

    private CropLocation get_crop_location (int x, int y)
    {
        if (!page.has_crop)
            return CropLocation.NONE;

        var cx = page.crop_x;
        var cy = page.crop_y;
        var cw = page.crop_width;
        var ch = page.crop_height;
        var dx = page_to_screen_x (cx) + border_width + ruler_width;
        var dy = page_to_screen_y (cy) + border_width + ruler_width;
        var dw = page_to_screen_x (cw) + border_width + ruler_width;
        var dh = page_to_screen_y (ch) + border_width + ruler_width;
        var ix = x - dx;
        var iy = y - dy;

        if (ix < 0 || ix > dw || iy < 0 || iy > dh)
            return CropLocation.NONE;

        /* Can't resize named crops */
        var name = page.crop_name;
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
        /* See if selecting crop */
        var location = get_crop_location (x, y);
        if (location != CropLocation.NONE)
        {
            crop_location = location;
            selected_crop_px = x;
            selected_crop_py = y;
            selected_crop_x = page.crop_x;
            selected_crop_y = page.crop_y;
            selected_crop_w = page.crop_width;
            selected_crop_h = page.crop_height;
        }
    }

    public void motion (int x, int y)
    {
        var location = get_crop_location (x, y);

        string cursor;
        switch (location)
        {
        case CropLocation.MIDDLE:
            cursor = "hand1";
            break;
        case CropLocation.TOP:
            cursor = "top_side";
            break;
        case CropLocation.BOTTOM:
            cursor = "bottom_side";
            break;
        case CropLocation.LEFT:
            cursor = "left_side";
            break;
        case CropLocation.RIGHT:
            cursor = "right_side";
            break;
        case CropLocation.TOP_LEFT:
            cursor = "top_left_corner";
            break;
        case CropLocation.TOP_RIGHT:
            cursor = "top_right_corner";
            break;
        case CropLocation.BOTTOM_LEFT:
            cursor = "bottom_left_corner";
            break;
        case CropLocation.BOTTOM_RIGHT:
            cursor = "bottom_right_corner";
            break;
        default:
            cursor = "arrow";
            break;
        }

        if (crop_location == CropLocation.NONE)
        {
            this.cursor = cursor;
            return;
        }

        /* Move the crop */
        var pw = page.width;
        var ph = page.height;
        var cw = page.crop_width;
        var ch = page.crop_height;

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

    private bool animation_cb ()
    {
        animate_segment = (animate_segment + 1) % animate_n_segments;
        changed ();
        return true;
    }

    private void update_animation ()
    {
        bool animate, is_animating;

        animate = page.is_scanning && !page.has_data;
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

    /* It is necessary to ask the ruler color since it is themed with the GTK */
    /* theme foreground color, and this class doesn't have any GTK widget     */
    /* available to lookup the color. */
    public void render (Cairo.Context context, Gdk.RGBA ruler_color)
    {
        update_animation ();

        page_texture.request_resize (get_preview_width (), get_preview_height ());
        
        try {
            page_texture.queue_update ();
        }
        catch (Error e)
        {
            warning ("Failed to queue_update of the texture: %s", e.message);
            // Ask for another redraw
            changed ();
        }

        var w = get_preview_width ();
        var h = get_preview_height ();

        context.set_line_width (1);
        context.translate (x_offset, y_offset);

        /* Draw image */
        context.translate (border_width + ruler_width, border_width + ruler_width);

        if (page_texture.pixbuf != null)
        {
            float x_scale = (float) w / (float) page_texture.pixbuf.width;
            float y_scale = (float) h / (float) page_texture.pixbuf.height;
            
            context.save ();
            context.scale(x_scale, y_scale);

            //  context.rectangle (0, 0.0, w, h);
            Gdk.cairo_set_source_pixbuf (context, page_texture.pixbuf, 0, 0);
            context.paint ();
            context.restore ();
        }
        else
        {
            Gdk.cairo_set_source_rgba (context, {1.0f, 1.0f, 1.0f, 1.0f});
            context.rectangle (0, 0.0, w, h);
            context.fill ();
        }

        /* Draw page border */
        Gdk.cairo_set_source_rgba (context, ruler_color);
        context.set_line_width (border_width);

        context.rectangle (0,
                           0.0,
                           w,
                           h);
        context.stroke ();

        /* Draw horizontal ruler */
        context.set_line_width (1);
        var ruler_tick = 0;
        var line = 0.0;
        var big_ruler_tick = 5;

        while (ruler_tick <= page.width)
        {
            line = page_to_screen_x (ruler_tick) + 0.5;
            if (big_ruler_tick == 5)
            {
                context.move_to (line, 0);
                context.line_to (line, -ruler_width);
                context.move_to (line, h);
                context.line_to (line, h + ruler_width);
                big_ruler_tick = 0;
            }
            else
            {
                context.move_to (line, -2);
                context.line_to (line, -5);
                context.move_to (line, h + 2);
                context.line_to (line, h + 5);
            }
            ruler_tick = ruler_tick + page.dpi/5;
            big_ruler_tick = big_ruler_tick + 1;
        }
        context.stroke ();

        /* Draw vertical ruler */
        ruler_tick = 0;
        line = 0.0;
        big_ruler_tick = 5;
        while (ruler_tick <= page.height)
        {
            line = page_to_screen_y (ruler_tick) + 0.5;

            if (big_ruler_tick == 5)
            {
                context.move_to (0, line);
                context.line_to (-ruler_width, line);

                context.move_to (w, line);
                context.line_to (w + ruler_width, line);
                big_ruler_tick = 0;
            }
            else
            {
                context.move_to (-2, line);
                context.line_to (-5, line);

                context.move_to (w + 2, line);
                context.line_to (w + 5, line);
            }
            ruler_tick = ruler_tick + page.dpi/5;
            big_ruler_tick = big_ruler_tick + 1;
        }
        context.stroke ();

        /* Draw scan line */
        if (page.is_scanning && page.scan_line > 0)
        {
            var scan_line = page.scan_line;

            double s;
            double x1, y1, x2, y2;
            switch (page.scan_direction)
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
        if (page.has_crop)
        {
            var x = page.crop_x;
            var y = page.crop_y;
            var crop_width = page.crop_width;
            var crop_height = page.crop_height;

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
            context.set_source_rgb (1.0, 1.0, 1.0);
            context.move_to (-border_width, dy - 1.5);
            context.line_to (border_width + w, dy - 1.5);
            context.move_to (-border_width, dy + dh + 1.5);
            context.line_to (border_width + w, dy + dh + 1.5);
            context.stroke ();

            context.move_to (dx - 1.5, -border_width);
            context.line_to (dx - 1.5, border_width + h);
            context.move_to (dx + dw + 1.5, -border_width);
            context.line_to (dx + dw + 1.5, border_width + h);
            context.stroke ();

            context.rectangle (dx - 0.5, dy - 0.5, dw + 1, dh + 1);
            context.set_source_rgb (0.0, 0.0, 0.0);
            context.stroke ();
        }
    }

    public int width
    {
        get { return width_; }
        set
        {
            // FIXME: Automatically update when get updated image
            var h = (int) ((double) value * page.height / page.width);
            if (width_ == value && height_ == h)
                return;

            width_ = value;
            height_ = h;

            /* Regenerate image */
            update_image = true;

            size_changed ();
            changed ();
        }
    }

    public int height
    {
        get { return height_; }
        set
        {
            // FIXME: Automatically update when get updated image
            var w = (int) ((double) value * page.width / page.height);
            if (width_ == w && height_ == value)
                return;

            width_ = w;
            height_ = value;

            /* Regenerate image */
            update_image = true;

            size_changed ();
            changed ();
        }
    }

    private void page_pixels_changed_cb (Page p)
    {
        /* Regenerate image */
        update_image = true;
        page_texture.request_update ();
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
        page_texture.request_update ();
        size_changed ();
        changed ();
    }
}
