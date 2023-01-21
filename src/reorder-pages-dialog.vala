/*
 * Copyright (C) 2023 Bartłomiej Maryńczak
 * Author: Bartłomiej Maryńczak <marynczakbartlomiej@gmail.com>,
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later
 * version. See http://www.gnu.org/copyleft/gpl.html the full text of the
 * license.
 */

[GtkTemplate (ui = "/org/gnome/SimpleScan/ui/reorder-pages-item.ui")]
private class ReorderPagesItem : Gtk.Button
{
    [GtkChild]
    private unowned Gtk.Label title;
    [GtkChild]
    private unowned Gtk.Image before_image;
    [GtkChild]
    private unowned Gtk.Image after_image;

    public new string label
    {
        get { return title.label; }
        set { title.label = value; }
    }

    public string before
    {
        get { return before_image.get_icon_name (); }
        set { before_image.icon_name = value; }
    }

    public string after
    {
        get { return after_image.get_icon_name (); }
        set { after_image.icon_name = value; }
    }
}


[GtkTemplate (ui = "/org/gnome/SimpleScan/ui/reorder-pages-dialog.ui")]
private class ReorderPagesDialog : Gtk.Window
{
    [GtkChild]
    public unowned ReorderPagesItem combine_sides;
    [GtkChild]
    public unowned ReorderPagesItem combine_sides_rev;
    [GtkChild]
    public unowned ReorderPagesItem flip_odd;
    [GtkChild]
    public unowned ReorderPagesItem flip_even;
    [GtkChild]
    public unowned ReorderPagesItem reverse;
    
    public ReorderPagesDialog ()
    {
        add_binding_action (Gdk.Key.Escape, 0, "window.close", null);
    }
}
