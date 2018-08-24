/*
 * Copyright (C) 2018 Canonical Ltd.
 * Author: Robert Ancell <robert.ancell@canonical.com>
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later
 * version. See http://www.gnu.org/copyleft/gpl.html the full text of the
 * license.
 */

public class ThumbnailView : Gtk.DrawingArea
{
    /* Page being rendered */
    private Page page_ = null;
    public Page page {
        get {
            return page_;
        }
        set {
            if (page_ != null) {
                page_.pixels_changed.disconnect (page_changed_cb);
                page_.size_changed.disconnect (page_changed_cb);
                page_.scan_line_changed.disconnect (page_changed_cb);
                page_.scan_direction_changed.disconnect (page_changed_cb);
            }
            page_ = value;
            page_.pixels_changed.connect (page_changed_cb);
            page_.size_changed.connect (page_changed_cb);
            page_.scan_line_changed.connect (page_changed_cb);
            page_.scan_direction_changed.connect (page_changed_cb);
        }
    }

    /* Border around image */
    private bool selected_ = false;
    public bool selected
    {
        get { return selected_; }
        set
        {
            if (selected_ == value)
                return;
            selected_ = value;
            queue_draw ();
        }
    }

    private int selected_border_width = 4;
    private int unselected_border_width = 1;

    public signal void clicked ();

    public ThumbnailView ()
    {
        add_events (Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.BUTTON_RELEASE_MASK);
    }

    private void get_page_size (out int width, out int height)
    {
        var w = get_allocated_width () - selected_border_width * 2;
        var h = get_allocated_height () - selected_border_width * 2;

        /* Fit page inside available space */
        if (w * page.height > h * page.width)
            w = h * page.width / page.height;
        else
            h = w * page.height / page.width;

        width = w;
        height = h;
    }

    public override void get_preferred_height_for_width (int width, out int minimum_height, out int natural_height)
    {
        if (page == null) {
            minimum_height = natural_height = 1 + selected_border_width * 2;
            return;
        }
        minimum_height = 1 + selected_border_width * 2;
        natural_height = int.max (width - selected_border_width * 2, 0) * page.height / page.width + selected_border_width * 2;
    }

    public override Gtk.SizeRequestMode get_request_mode ()
    {
        return Gtk.SizeRequestMode.HEIGHT_FOR_WIDTH;
    }

    public override bool draw (Cairo.Context context)
    {
        int w, h;
        get_page_size (out w, out h);

        var x_offset = (get_allocated_width () - w - selected_border_width * 2) / 2;
        var y_offset = (get_allocated_height () - h - selected_border_width * 2) / 2;

        /* Draw page border */
        context.set_source_rgba (0.0, 0.0, 0.0, 0.25);
        var border_delta = selected_border_width - unselected_border_width;
        if (selected)
        {
            context.arc (x_offset + selected_border_width, y_offset + selected_border_width,
                         selected_border_width, -Math.PI, -Math.PI / 2);
            context.arc (x_offset + w + selected_border_width, y_offset + selected_border_width,
                         selected_border_width, -Math.PI / 2, 0);
            context.arc (x_offset + w + selected_border_width, y_offset + h + selected_border_width,
                         selected_border_width, 0, Math.PI / 2);
            context.arc (x_offset + selected_border_width, y_offset + h + selected_border_width,
                         selected_border_width, Math.PI / 2, Math.PI);
            context.close_path ();
        }
        else
            context.rectangle (x_offset + border_delta, y_offset + border_delta,
                               w + unselected_border_width * 2,
                               h + unselected_border_width * 2);
        context.set_line_width (selected_border_width);
        context.fill ();

        /* Draw page data */
        var image = page.get_image (); // FIXME: Cache and mipmap
        context.translate (x_offset + selected_border_width, y_offset + selected_border_width);
        context.scale ((double) w / image.width, (double) h / image.height);
        Gdk.cairo_set_source_pixbuf (context, image, 0, 0);
        context.paint ();

        return true;
    }

    public override bool button_release_event (Gdk.EventButton event)
    {
        if (event.button == 1) {
            clicked ();
            return true;
        }

        return false;
    }

    private void page_changed_cb (Page p)
    {
        queue_draw ();
    }
}
