/*
 * Copyright (C) 2017 Stéphane Fillion
 * Authors: Stéphane Fillion <stphanef3724@gmail.com>
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later
 * version. See http://www.gnu.org/copyleft/gpl.html the full text of the
 * license.
 */

[DBus (name = "org.freedesktop.ScreenSaver")]
public interface FreedesktopScreensaver : Object
{
    public static FreedesktopScreensaver get_proxy () throws IOError
    {
        return Bus.get_proxy_sync (BusType.SESSION, "org.freedesktop.ScreenSaver", "/org/freedesktop/ScreenSaver");
    }

    [DBus (name = "Inhibit")]
    public abstract uint32 inhibit (string application_name, string reason_for_inhibit) throws Error;

    [DBus (name = "UnInhibit")]
    public abstract void uninhibit (uint32 cookie) throws Error;
}
