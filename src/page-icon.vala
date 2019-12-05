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
    private string text;
    private double r;
    private double g;
    private double b;
    private const int MINIMUM_WIDTH = 20;

    public PageIcon (string text, double r = 1.0, double g = 1.0, double b = 1.0)
    {
        this.text = text;
        this.r = r;
        this.g = g;
        this.b = b;
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

        c.rectangle (0.5, 0.5, w - 1, h - 1);

        c.set_source_rgb (r, g, b);
        c.fill_preserve ();

        c.set_line_width (1.0);
        c.set_source_rgb (0.0, 0.0, 0.0);
        c.stroke ();

        Cairo.TextExtents extents;
        c.text_extents (text, out extents);
        c.translate ((w - extents.width) * 0.5 - 0.5, (h + extents.height) * 0.5 - 0.5);
        c.show_text (text);

        return true;
    }
}
