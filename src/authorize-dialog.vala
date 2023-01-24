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

[GtkTemplate (ui = "/org/gnome/SimpleScan/ui/authorize-dialog.ui")]
private class AuthorizeDialog : Gtk.Window
{
    [GtkChild]
    private unowned Adw.PreferencesGroup preferences_group;
    [GtkChild]
    private unowned Adw.EntryRow username_entry;
    [GtkChild]
    private unowned Adw.PasswordEntryRow password_entry;

    public signal void authorized (AuthorizeDialogResponse res);

    public AuthorizeDialog (Gtk.Window parent, string title)
    {
        preferences_group.set_title (title);
        set_transient_for (parent);
    }

    public string get_username ()
    {
        return username_entry.text;
    }

    public string get_password ()
    {
        return password_entry.text;
    }

    [GtkCallback]
    private void authorize_button_cb ()
    {
        authorized (AuthorizeDialogResponse.new_authorized (get_username (), get_password ()));
    }

    [GtkCallback]
    private void cancel_button_cb ()
    {
        authorized (AuthorizeDialogResponse.new_canceled ());
    }
    
    public async AuthorizeDialogResponse open()
    {
        SourceFunc callback = open.callback;
        
        AuthorizeDialogResponse response = {};

        authorized.connect ((res) =>
        {
            response = res;
            callback ();
        });

        present ();
        yield;
        close ();

        return response;
    }
}

public struct AuthorizeDialogResponse
{
    public string username;
    public string password;
    public bool success;
    
    public static AuthorizeDialogResponse new_canceled ()
    {
        return AuthorizeDialogResponse ()
        {
            success = false,
        };
    }

    public static AuthorizeDialogResponse new_authorized (string username, string password)
    {
        return AuthorizeDialogResponse ()
        {
            username = username,
            password = password,
            success = true,
        };
    }
}
