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

public class SimpleScan : Gtk.Application
{
    static bool show_version;
    static bool debug_enabled;
    static string? fix_pdf_filename = null;
    public static const OptionEntry[] options =
    {
        { "version", 'v', 0, OptionArg.NONE, ref show_version,
          /* Help string for command line --version flag */
          N_("Show release version"), null},
        { "debug", 'd', 0, OptionArg.NONE, ref debug_enabled,
          /* Help string for command line --debug flag */
          N_("Print debugging messages"), null},
        { "fix-pdf", 0, 0, OptionArg.STRING, ref fix_pdf_filename,
          N_("Fix PDF files generated with older versions of Simple Scan"), "FILENAME..."},
        { null }
    };
    private static Timer log_timer;
    private static FileStream? log_file;

    private ScanDevice? default_device = null;
    private bool have_devices = false;
    private GUdev.Client udev_client;
    private UserInterface ui;
    private Scanner scanner;
    private Book book;

    public SimpleScan (ScanDevice? device = null)
    {
        default_device = device;
    }

    public override void startup ()
    {
        base.startup ();

        ui = new UserInterface ();
        book = ui.book;
        ui.start_scan.connect (scan_cb);
        ui.stop_scan.connect (cancel_cb);
        ui.email.connect (email_cb);

        scanner = Scanner.get_instance ();
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

        if (default_device != null)
        {
            List<ScanDevice> device_list = null;

            device_list.append (default_device);
            ui.set_scan_devices (device_list);
            ui.selected_device = default_device.name;
        }
    }

    public override void activate ()
    {
        base.activate ();
        ui.start ();
        scanner.start ();
    }

    public override void shutdown ()
    {
        base.shutdown ();
        book = null;
        ui = null;
        udev_client = null;
        scanner.free ();
    }

    private void update_scan_devices_cb (Scanner scanner, List<ScanDevice> devices)
    {
        var devices_copy = devices.copy ();

        /* If the default device is not detected add it to the list */
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
        if (page != null && !page.has_data)
        {
            ui.selected_page = page;
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
            scan_direction = page.scan_direction;
            width = page.width;
            height = page.height;
            dpi = page.dpi;

            do_crop = page.has_crop;
            if (do_crop)
            {
                named_crop = page.crop_name;
                cx = page.crop_x;
                cy = page.crop_y;
                cw = page.crop_width;
                ch = page.crop_height;
            }
        }

        page = new Page (width, height, dpi, scan_direction);
        book.append_page (page);
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
        ui.selected_page = page;
        page.start ();

        return page;
    }

    private void scanner_new_page_cb (Scanner scanner)
    {
        append_page ();
    }

    private string? get_profile_for_device (string device_name)
    {
#if HAVE_COLORD
        var device_id = "sane:%s".printf (device_name);
        debug ("Getting color profile for device %s", device_name);

        var client = new Colord.Client ();
        try
        {
            client.connect_sync ();
        }
        catch (Error e)
        {
            debug ("Failed to connect to colord: %s", e.message);
            return null;
        }

        Colord.Device device;
        try
        {
            device = client.find_device_by_property_sync (Colord.DEVICE_PROPERTY_SERIAL, device_id);
        }
        catch (Error e)
        {
            debug ("Unable to find colord device %s: %s", device_name, e.message);
            return null;
        }

        try
        {
            device.connect_sync ();
        }
        catch (Error e)
        {
            debug ("Failed to get properties from the device %s: %s", device_name, e.message);
            return null;
        }

        var profile = device.get_default_profile ();
        if (profile == null)
        {
            debug ("No default color profile for device: %s", device_name);
            return null;
        }

        try
        {
            profile.connect_sync ();
        }
        catch (Error e)
        {
            debug ("Failed to get properties from the profile %s: %s", device_name, e.message);
            return null;
        }

        if (profile.filename == null)
        {
            debug ("No icc color profile for the device %s", device_name);
            return null;
        }

        debug ("Using color profile %s for device %s", profile.filename, device_name);
        return profile.filename;
#else
        return null;
#endif
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
        page.color_profile = get_profile_for_device (info.device);
    }

    private void scanner_line_cb (Scanner scanner, ScanLine line)
    {
        var page = book.get_page ((int) book.n_pages - 1);
        page.parse_scan_line (line);
    }

    private void scanner_page_done_cb (Scanner scanner)
    {
        var page = book.get_page ((int) book.n_pages - 1);
        page.finish ();
    }

    private void remove_empty_page ()
    {
        var page = book.get_page ((int) book.n_pages - 1);
        if (!page.has_data)
            book.delete_page (page);
    }

    private void scanner_document_done_cb (Scanner scanner)
    {
        remove_empty_page ();
    }

    private void scanner_failed_cb (Scanner scanner, int error_code, string error_string)
    {
        remove_empty_page ();
        if (error_code != Sane.Status.CANCELLED)
        {
            ui.show_error (/* Title of error dialog when scan failed */
                           _("Failed to scan"),
                           error_string,
                           have_devices);
        }
    }

    private void scanner_scanning_changed_cb (Scanner scanner)
    {
        ui.scanning = scanner.is_scanning ();
    }

    private void scan_cb (UserInterface ui, string? device, ScanOptions options)
    {
        debug ("Requesting scan at %d dpi from device '%s'", options.dpi, device);

        if (!scanner.is_scanning ())
            append_page ();

        /* Default filename to use when saving document (and extension will be added, e.g. .jpg) */
        string filename_prefix = _("Scanned Document");
        string extension;
        if (options.scan_mode == ScanMode.COLOR)
            extension = "jpg";
        else
            extension = "pdf";
        var filename = "%s.%s".printf (filename_prefix, extension);
        ui.default_file_name = filename;
        scanner.scan (device, options);
    }

    private void cancel_cb (UserInterface ui)
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

    private void email_cb (UserInterface ui, string profile, int quality)
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
                ui.show_progress_dialog ();
                try
                {
                    book.save ("pdf", quality, file);
                }
                catch (Error e)
                {
                    ui.hide_progress_dialog ();
                    warning ("Unable to save email file: %s", e.message);
                    return;
                }
                command_line += " --attach %s".printf (path);
            }
        }
        else
        {
            for (var i = 0; i < book.n_pages; i++)
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
                    book.get_page (i).save ("jpeg", quality, file);
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

    private static void log_cb (string? log_domain, LogLevelFlags log_level, string message)
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
        if (debug_enabled)
            stderr.printf ("[%+.2fs] %s %s\n", log_timer.elapsed (), prefix, message);
    }

    private void on_uevent (GUdev.Client client, string action, GUdev.Device device)
    {
        scanner.redetect ();
    }

    private static void fix_pdf (string filename) throws Error
    {
        uint8[] data;
        FileUtils.get_data (filename, out data);

        var fixed_file = FileStream.open (filename + ".fixed", "w");

        var offset = 0;
        var line_number = 0;
        var xref_offset = 0;
        var xref_line = -1;
        var startxref_line = -1;
        var fixed_size = -1;
        var line = new StringBuilder ();
        while (offset < data.length)
        {
            var end_offset = offset;
            line.assign ("");
            while (end_offset < data.length)
            {
                var c = data[end_offset];
                line.append_c ((char) c);
                end_offset++;
                if (c == '\n')
                    break;
            }

            if (line.str == "startxref\n")
                startxref_line = line_number;

            if (line.str == "xref\n")
                xref_line = line_number;

            /* Fix PDF header and binary comment */
            if (line_number < 2 && line.str.has_prefix ("%%"))
            {
                xref_offset--;
                fixed_file.printf ("%s", line.str.substring (1));
            }

            /* Fix xref subsection count */
            else if (line_number == xref_line + 1 && line.str.has_prefix ("1 "))
            {
                fixed_size = int.parse (line.str.substring (2)) + 1;
                fixed_file.printf ("0 %d\n", fixed_size);
                fixed_file.printf ("0000000000 65535 f \n");
            }

            /* Fix xref format */
            else if (line_number > xref_line && line.str.has_suffix (" 0000 n\n"))
                fixed_file.printf ("%010d 00000 n \n", int.parse (line.str) + xref_offset);

            /* Fix xref offset */
            else if (startxref_line > 0 && line_number == startxref_line + 1)
                fixed_file.printf ("%d\n".printf (int.parse (line.str) + xref_offset));

            else if (fixed_size > 0 && line.str.has_prefix ("/Size "))
                fixed_file.printf ("/Size %d\n".printf (fixed_size));

            /* Fix EOF marker */
            else if (line_number == startxref_line + 2 && line.str.has_prefix ("%%%%"))
                fixed_file.printf ("%s", line.str.substring (2));

            else
                for (var i = offset; i < end_offset; i++)
                    fixed_file.putc ((char) data[i]);

            line_number++;
            offset = end_offset;
        }

        if (FileUtils.rename (filename, filename + "~") >= 0)
            FileUtils.rename (filename + ".fixed", filename);
    }

    public static int main (string[] args)
    {
        Intl.setlocale (LocaleCategory.ALL, "");
        Intl.bindtextdomain (GETTEXT_PACKAGE, LOCALE_DIR);
        Intl.bind_textdomain_codeset (GETTEXT_PACKAGE, "UTF-8");
        Intl.textdomain (GETTEXT_PACKAGE);

        Gtk.init (ref args);

        var c = new OptionContext (/* Arguments and description for --help text */
                                   _("[DEVICE...] - Scanning utility"));
        c.add_main_entries (options, GETTEXT_PACKAGE);
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
            stderr.printf ("simple-scan %s\n", VERSION);
            return Posix.EXIT_SUCCESS;
        }
        if (fix_pdf_filename != null)
        {
            try
            {
                fix_pdf (fix_pdf_filename);
                for (var i = 1; i < args.length; i++)
                    fix_pdf (args[i]);
            }
            catch (Error e)
            {
                stderr.printf ("Error fixing PDF file: %s", e.message);
                return Posix.EXIT_FAILURE;
            }
            return Posix.EXIT_SUCCESS;
        }

        ScanDevice? device = null;
        if (args.length > 1)
        {
            device = new ScanDevice ();
            device.name = args[1];
            device.label = args[1];
        }

        /* Log to a file */
        log_timer = new Timer ();
        var path = Path.build_filename (Environment.get_user_cache_dir (), "simple-scan", null);
        DirUtils.create_with_parents (path, 0700);
        path = Path.build_filename (Environment.get_user_cache_dir (), "simple-scan", "simple-scan.log", null);
        log_file = FileStream.open (path, "w");
        Log.set_default_handler (log_cb);

        debug ("Starting Simple Scan %s, PID=%i", VERSION, Posix.getpid ());

        var app = new SimpleScan (device);
        return app.run ();
    }
}
