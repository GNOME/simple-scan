/*
 * Copyright (C) 2009-2017 Canonical Ltd.
 * Author: Robert Ancell <robert.ancell@canonical.com>,
 *         Eduard Gotwig <g@ox.io>
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later
 * version. See http://www.gnu.org/copyleft/gpl.html the full text of the
 * license.
 */

public class PageIcon : Gtk.DrawingArea
{
    private char side;
    private int position;
    private int angle;
    private const int MINIMUM_WIDTH = 20;

    public PageIcon (char side, int position, int angle)
    {
        this.side = side;
        this.position = position;
        this.angle = angle;
    }

    public override void get_preferred_width (out int minimum_width, out int natural_width)
    {
        minimum_width = natural_width = MINIMUM_WIDTH;
    }

    public override void get_preferred_height (out int minimum_height, out int natural_height)
    {
        minimum_height = natural_height = (int) Math.round (MINIMUM_WIDTH * Math.SQRT2);
    }

    public override void get_preferred_height_for_width (int width, out int minimum_height, out int natural_height)
    {
        minimum_height = natural_height = (int) (width * Math.SQRT2);
    }

    public override void get_preferred_width_for_height (int height, out int minimum_width, out int natural_width)
    {
        minimum_width = natural_width = (int) (height / Math.SQRT2);
    }

    public override bool draw (Cairo.Context c)
    {
        var w = get_allocated_width ();
        var h = get_allocated_height ();
        if (w * Math.SQRT2 > h)
            w = (int) Math.round (h / Math.SQRT2);
        else
            h = (int) Math.round (w * Math.SQRT2);

        c.translate ((get_allocated_width () - w) / 2, (get_allocated_height () - h) / 2);

        bool dark = Hdy.StyleManager.get_default ().dark;
        bool hc = Hdy.StyleManager.get_default ().high_contrast;

        if (dark && !hc)
            c.rectangle (1, 1, w - 2, h - 2);
        else
            c.rectangle (0, 0, w, h);

        Gdk.RGBA rgba = {};

        switch (side)
        {
        case 'F':
            /* Purple 2 */
            rgba.parse ("#c061cb");
            break;
        case 'B':
            /* Orange 3 */
            rgba.parse ("#ff7800");
            break;
        case 'U':
            /* green 4 */
            rgba.parse ("#5cc02e");
            break;
        case 'R':
            /* blue 4 */
            rgba.parse ("#0deee7");
            break;
        default:
            /* Yellow 3 to Red 2 */
            Gdk.RGBA start = {}, end = {};
            start.parse ("#f6d32d");
            end.parse ("#ed333b");

            double progress = position / 5.0;
            rgba.red   = start.red   + (end.red   - start.red)   * progress;
            rgba.green = start.green + (end.green - start.green) * progress;
            rgba.blue  = start.blue  + (end.blue  - start.blue)  * progress;
            break;
        }

        rgba.alpha = 0.3;

        Gdk.cairo_set_source_rgba (c, rgba);
        c.fill ();

        c.set_line_width (1.0);
        if (hc && dark)
            c.set_source_rgba (1, 1, 1, 0.5);
        else if (hc)
            c.set_source_rgba (0, 0, 0, 0.5);
        else
            c.set_source_rgba (0, 0, 0, 0.15);

        c.rectangle (0.5, 0.5, w - 1, h - 1);
        c.stroke ();

        if (dark)
            c.set_source_rgb (1, 1, 1);
        else
            c.set_source_rgb (0, 0, 0);

        var text = @"$(position + 1)";
        Cairo.TextExtents extents;

        var rad =  Math.PI / 180.0 * angle;
        c.text_extents (text, out extents);
        c.translate ((w - extents.width) * 0.5 - 0.5, extents.height + (h - extents.height) * 0.5 - 0.5);
        c.rotate(rad);
        //  only correct for 0 and 180 degree
        var tx = (1.0 - Math.sin(rad)) * extents.width / 2;
        var ty = (1.0 - Math.sin(rad)) * extents.height / 2;
        c.translate(-tx, +ty);
        c.show_text (text);

        return true;
    }
}
