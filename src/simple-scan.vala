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

public class Application
{
    static bool show_version;
    static bool debug_enabled;
    public static const OptionEntry[] options =
    {
        { "version", 'v', 0, OptionArg.NONE, ref show_version,
          /* Help string for command line --version flag */
          N_("Show release version"), null},
        { "debug", 'd', 0, OptionArg.NONE, ref debug_enabled,
          /* Help string for command line --debug flag */
          N_("Print debugging messages"), null},
        { null }
    };
    private static Timer log_timer;
    private static FileStream? log_file;

#if 0
    private ScanDevice? default_device = null;
#endif
    private bool have_devices = false;
    private GUdev.Client udev_client;
    private SimpleScan ui;
    private Scanner scanner;
    private Book book;

    public Application (/*ScanDevice? device = null*/)
    {
#if 0
        default_device = device;
#endif

        ui = new SimpleScan ();
        book = ui.get_book ();
        ui.start_scan.connect (scan_cb);
        ui.stop_scan.connect (cancel_cb);
        ui.email.connect (email_cb);
        ui.quit.connect (quit_cb);

        scanner = new Scanner ();
        scanner.update_devices.connect (update_scan_devices_cb);
        scanner.request_authorization.connect (authorize_cb);
        scanner.expect_page.connect (scanner_new_page_cb);
        scanner.got_page_info.connect (scanner_page_info_cb);
        scanner.got_line.connect (scanner_line_cb);
        scanner.page_done.connect (scanner_page_done_cb);
        scanner.document_done.connect (scanner_document_done_cb);
        scanner.scan_failed.connect (scanner_failed_cb);
        scanner.scanning_changed.connect (scanner_scanning_changed_cb);

        string[]? subsystems = { "usb", null };
        udev_client = new GUdev.Client (subsystems);
        udev_client.uevent.connect (on_uevent);

#if 0
        if (default_device != null)
        {
            List<ScanDevice> device_list = null;

            device_list.append (default_device);
            ui.set_scan_devices (device_list);
            ui.set_selected_device (default_device.name);
        }
#endif        
    }
    
    public void start ()
    {
        ui.start ();
        scanner.start ();
    }

    private void update_scan_devices_cb (Scanner scanner, List<ScanDevice> devices)
    {
        var devices_copy = devices.copy ();

        /* If the default device is not detected add it to the list */
#if 0
        if (default_device != null)
        {
            var default_in_list = false;
            foreach (var device in devices_copy)
            {
                if (device.name == default_device.name)
                {
                    default_in_list = true;
                    break;
                }
            }

            if (!default_in_list)
                devices_copy.prepend (default_device);
        }
#endif

        have_devices = devices_copy.length () > 0;
        ui.set_scan_devices (devices_copy);
    }

    private void authorize_cb (Scanner scanner, string resource)
    {
        string username, password;
        ui.authorize (resource, out username, out password);
        scanner.authorize (username, password);
    }

    private Page append_page ()
    {
        /* Use current page if not used */
        var page = book.get_page (-1);
        if (page != null && !page.has_data ())
        {
            ui.set_selected_page (page);
            page.start ();
            return page;
        }

        /* Copy info from previous page */
        var scan_direction = ScanDirection.TOP_TO_BOTTOM;
        bool do_crop = false;
        string named_crop = null;
        var width = 100, height = 100, dpi = 100, cx = 0, cy = 0, cw = 0, ch = 0;
        if (page != null)
        {
            scan_direction = page.get_scan_direction ();
            width = page.get_width ();
            height = page.get_height ();
            dpi = page.get_dpi ();

            do_crop = page.has_crop ();
            if (do_crop)
            {
                named_crop = page.get_named_crop ();
                page.get_crop (out cx, out cy, out cw, out ch);
            }
        }

        page = book.append_page (width, height, dpi, scan_direction);
        if (do_crop)
        {
            if (named_crop != null)
            {
                page.set_named_crop (named_crop);
            }
            else
                page.set_custom_crop (cw, ch);
            page.move_crop (cx, cy);
        }
        ui.set_selected_page (page);
        page.start ();

        return page;
    }

    private void scanner_new_page_cb (Scanner scanner)
    {
        append_page ();
    }

    private string? get_profile_for_device (string current_device)
    {
#if 0    
        /* Connect to the color manager on the session bus */
        var connection = dbus_g_bus_get (DBUS_BUS_SESSION, null);
        var proxy = dbus_g_proxy_new_for_name (connection,
                                               "org.gnome.ColorManager",
                                               "/org/gnome/ColorManager",
                                               "org.gnome.ColorManager");

        /* Get color profile */
        var device_id = "sane:%s".printf (current_device);
        custom_g_type_string_string = dbus_g_type_get_collection ("GPtrArray",
                                                                  dbus_g_type_get_struct("GValueArray",
                                                                                         G_TYPE_STRING,
                                                                                         G_TYPE_STRING,
                                                                                         G_TYPE_INVALID));
        var ret = dbus_g_proxy_call (proxy, "GetProfilesForDevice", &error,
                                     G_TYPE_STRING, device_id,
                                     G_TYPE_STRING, "",
                                     G_TYPE_INVALID,
                                     custom_g_type_string_string, &profile_data_array,
                                     G_TYPE_INVALID);
        if (!ret)
        {
            debug ("The request failed: %s", error.message);
            g_error_free (error);
            return null;
        }

        if (profile_data_array.len > 0)
        {
            GValueArray *gva;
            GValue *gv = null;

            /* Just use the preferred profile filename */
            gva = (GValueArray *) g_ptr_array_index (profile_data_array, 0);
            gv = g_value_array_get_nth (gva, 1);
            icc_profile = g_value_dup_string (gv);
            g_value_unset (gv);
        }
        else
            debug ("There are no ICC profiles for the device sane:%s", current_device);
        g_ptr_array_free (profile_data_array, true);

        return icc_profile;
#endif
        return null;
    }

    private void scanner_page_info_cb (Scanner scanner, ScanPageInfo info)
    {
        debug ("Page is %d pixels wide, %d pixels high, %d bits per pixel",
               info.width, info.height, info.depth);

        /* Add a new page */
        var page = append_page ();
        page.set_page_info (info);

        /* Get ICC color profile */
        /* FIXME: The ICC profile could change */
        /* FIXME: Don't do a D-bus call for each page, cache color profiles */
        page.set_color_profile (get_profile_for_device (info.device));
    }

    private void scanner_line_cb (Scanner scanner, ScanLine line)
    {
        var page = book.get_page ((int) book.get_n_pages () - 1);
        page.parse_scan_line (line);
    }

    private void scanner_page_done_cb (Scanner scanner)
    {
        var page = book.get_page ((int) book.get_n_pages () - 1);
        page.finish ();
    }

    private void remove_empty_page ()
    {
        var page = book.get_page ((int) book.get_n_pages () - 1);

        /* Remove a failed page */
        if (page.has_data ())
            page.finish ();
        else
            book.delete_page (page);
    }

    private void scanner_document_done_cb (Scanner scanner)
    {
        remove_empty_page ();
    }

    private void scanner_failed_cb (Scanner scanner, Error error)
    {
        remove_empty_page ();
#if 0
        if (!error.matches (SCANNER_TYPE, SANE_STATUS_CANCELLED))
        {
            ui.show_error (/* Title of error dialog when scan failed */
                           _("Failed to scan"),
                           error.message,
                           have_devices);
        }
#endif
    }

    private void scanner_scanning_changed_cb (Scanner scanner)
    {
        ui.set_scanning (scanner.is_scanning ());
    }

    private void scan_cb (SimpleScan ui, string device, ScanOptions options)
    {
        string extension;
        if (options.scan_mode == ScanMode.COLOR)
            extension = "jpg";
        else
            extension = "pdf";

        debug ("Requesting scan at %d dpi from device '%s'", options.dpi, device);

        if (!scanner.is_scanning ())
            append_page ();

        /* Default filename to use when saving document (and extension will be added, e.g. .jpg) */
        string filename_prefix = _("Scanned Document");
        var filename = "%s.%s".printf (filename_prefix, extension);
        ui.set_default_file_name (filename);
        scanner.scan (device, options);
    }

    private void cancel_cb (SimpleScan ui)
    {
        scanner.cancel ();
    }

    private string? get_temporary_filename (string prefix, string extension)
    {
        /* NOTE: I'm not sure if this is a 100% safe strategy to use g_file_open_tmp(), close and
         * use the filename but it appears to work in practise */

        var filename = "%sXXXXXX.%s".printf (prefix, extension);
        string path;
        try
        {
            var fd = FileUtils.open_tmp (filename, out path);
            Posix.close (fd);
        }
        catch (Error e)
        {
            warning ("Error saving email attachment: %s", e.message);
            return null;
        }

        return path;
    }

    private void email_cb (SimpleScan ui, string profile)
    {
        var saved = false;
        var command_line = "xdg-email";

        /* Save text files as PDFs */
        if (profile == "text")
        {
            /* Open a temporary file */
            var path = get_temporary_filename ("scan", "pdf");
            if (path != null)
            {
                var file = File.new_for_path (path);
                try
                {
                    book.save ("pdf", file);
                }
                catch (Error e)
                {
                    warning ("Unable to save email file: %s", e.message);
                    return;
                }
                command_line += " --attach %s".printf (path);
            }
        }
        else
        {
            for (var i = 0; i < book.get_n_pages (); i++)
            {
                var path = get_temporary_filename ("scan", "jpg");
                if (path == null)
                {
                    saved = false;
                    break;
                }

                var file = File.new_for_path (path);
                try
                {
                    book.get_page (i).save ("jpeg", file);
                }
                catch (Error e)
                {
                    warning ("Unable to save email file: %s", e.message);
                    return;
                }
                command_line += " --attach %s".printf (path);

                if (!saved)
                    break;
            }
        }

        debug ("Launching email client: %s", command_line);
        try
        {
            Process.spawn_command_line_async (command_line);
        }
        catch (Error e)
        {
            warning ("Unable to start email: %s", e.message);
        }
    }

    private void quit_cb (SimpleScan ui)
    {
        book = null;
        ui = null;
        udev_client = null;
        scanner.free ();
        Gtk.main_quit ();
    }

    private static void log_cb (string? log_domain, LogLevelFlags log_level, string message)
    {
        /* Log everything to a file */
        if (log_file != null) 
        {
            string prefix;

            switch (log_level & LogLevelFlags.LEVEL_MASK)
            {
            case LogLevelFlags.LEVEL_ERROR:
                prefix = "ERROR:";
                break;
            case LogLevelFlags.LEVEL_CRITICAL:
                prefix = "CRITICAL:";
                break;
            case LogLevelFlags.LEVEL_WARNING:
                prefix = "WARNING:";
                break;
            case LogLevelFlags.LEVEL_MESSAGE:
                prefix = "MESSAGE:";
                break;
            case LogLevelFlags.LEVEL_INFO:
                prefix = "INFO:";
                break;
            case LogLevelFlags.LEVEL_DEBUG:
                prefix = "DEBUG:";
                break;
            default:
                prefix = "LOG:";
                break;
            }

            log_file.printf ("[%+.2fs] %s %s\n", log_timer.elapsed (), prefix, message);
        }

        /* Only show debug if requested */
        if ((log_level & LogLevelFlags.LEVEL_DEBUG) != 0)
        {
            if (debug_enabled)
                Log.default_handler (log_domain, log_level, message);
        }
        else
            Log.default_handler (log_domain, log_level, message);
    }

    private void on_uevent (GUdev.Client client, string action, GUdev.Device device)
    {
        scanner.redetect ();
    }

    public static int main (string[] args)
    {
        Intl.setlocale (LocaleCategory.ALL, "");
        Intl.bindtextdomain (Config.GETTEXT_PACKAGE, Config.LOCALE_DIR);
        Intl.bind_textdomain_codeset (Config.GETTEXT_PACKAGE, "UTF-8");
        Intl.textdomain (Config.GETTEXT_PACKAGE);

        Gtk.init (ref args);

        var c = new OptionContext (/* Arguments and description for --help text */
                                   _("[DEVICE...] - Scanning utility"));
        c.add_main_entries (options, Config.GETTEXT_PACKAGE);
        c.add_group (Gtk.get_option_group (true));
        try
        {
            c.parse (ref args);
        }
        catch (Error e)
        {
            stderr.printf ("%s\n", e.message);
            stderr.printf (/* Text printed out when an unknown command-line argument provided */
                           _("Run '%s --help' to see a full list of available command line options."), args[0]);
            stderr.printf ("\n");
            return Posix.EXIT_FAILURE;
        }
        if (show_version)
        {
            /* Note, not translated so can be easily parsed */
            stderr.printf ("simple-scan %s\n", Config.VERSION);
            return Posix.EXIT_SUCCESS;
        }

#if 0
        ScanDevice? device = null;
        if (args.length > 1)
        {
            device = new ScanDevice ();
            device.name = args[1];
            device.label = args[1];
        }
#endif

        /* Log to a file */
        log_timer = new Timer ();
        var path = Path.build_filename (Environment.get_user_cache_dir (), "simple-scan", null);
        DirUtils.create_with_parents (path, 0700);
        path = Path.build_filename (Environment.get_user_cache_dir (), "simple-scan", "simple-scan.log", null);
        log_file = FileStream.open (path, "w");
        Log.set_default_handler (log_cb);

        debug ("Starting Simple Scan %s, PID=%i", Config.VERSION, Posix.getpid ());

        Application app = new Application (/*device*/);
        app.start ();

        Gtk.main ();

        return Posix.EXIT_SUCCESS;
    }
}
