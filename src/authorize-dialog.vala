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

[GtkTemplate (ui = "/org/gnome/SimpleScan/authorize-dialog.ui")]
private class AuthorizeDialog : Gtk.Dialog
{
    [GtkChild]
    private Gtk.Label authorize_label;
    [GtkChild]
    private Gtk.Entry username_entry;
    [GtkChild]
    private Gtk.Entry password_entry;

    public AuthorizeDialog (string title)
    {
        authorize_label.set_text (title);
    }

    public string get_username ()
    {
        return username_entry.text;
    }

    public string get_password ()
    {
        return password_entry.text;
    }
}
