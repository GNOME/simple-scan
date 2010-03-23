/*
 * Copyright (C) 2009 Canonical Ltd.
 * Author: Robert Ancell <robert.ancell@canonical.com>
 * 
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later
 * version. See http://www.gnu.org/copyleft/gpl.html the full text of the
 * license.
 */

#include <stdlib.h>
#include <stdio.h>
#include <glib/gi18n.h>
#include <gtk/gtk.h>
#include <unistd.h>
#include <gudev/gudev.h>
#include <dbus/dbus-glib.h>

#include <sane/sane.h> // For SANE_STATUS_CANCELLED

#include "ui.h"
#include "scanner.h"
#include "book.h"


static const char *default_device = NULL;

static GUdevClient *udev_client;

static SimpleScan *ui;

static Scanner *scanner;

static Book *book;

static GTimer *log_timer;

static FILE *log_file;

static gboolean debug = FALSE;


static void
update_scan_devices_cb (Scanner *scanner, GList *devices)
{
    ui_set_scan_devices (ui, devices);
}


static void
authorize_cb (Scanner *scanner, const gchar *resource)
{
    gchar *username = NULL, *password = NULL;
    ui_authorize (ui, resource, &username, &password);
    scanner_authorize (scanner, username, password);
    g_free (username);
    g_free (password);
}


static Page *
append_page ()
{
    Page *page;
    Orientation orientation = TOP_TO_BOTTOM;
    gboolean do_crop = FALSE;
    gchar *named_crop = NULL;
    gint width = 100, height = 100, dpi = 100, cx, cy, cw, ch;

    /* Use current page if not used */
    page = book_get_page (book, -1);
    if (page && !page_has_data (page)) {
        ui_set_selected_page (ui, page);
        page_start (page);
        return page;
    }
  
    /* Copy info from previous page */
    if (page) {
        orientation = page_get_orientation (page);
        width = page_get_width (page);
        height = page_get_height (page);
        dpi = page_get_dpi (page);

        do_crop = page_has_crop (page);
        if (do_crop) {
            named_crop = page_get_named_crop (page);
            page_get_crop (page, &cx, &cy, &cw, &ch);
        }
    }

    page = book_append_page (book, width, height, dpi, orientation);
    if (do_crop) {
        if (named_crop)  {
            page_set_named_crop (page, named_crop);
            g_free (named_crop);
        }
        else
            page_set_custom_crop (page, cw, ch);
        page_move_crop (page, cx, cy);
    }
    ui_set_selected_page (ui, page);
    page_start (page);
  
    return page;
}


static void
scanner_new_page_cb (Scanner *scanner)
{
    append_page ();
}


static gchar *
get_profile_for_device (const gchar *current_device)
{
    gboolean ret;
    DBusGConnection *connection;
    DBusGProxy *proxy;
    GError *error = NULL;
    GType custom_g_type_string_string;
    GPtrArray *profile_data_array = NULL;
    gchar *device_id = NULL;
    gchar *icc_profile = NULL;

    /* Connect to the color manager on the session bus */
    connection = dbus_g_bus_get (DBUS_BUS_SESSION, NULL);
    proxy = dbus_g_proxy_new_for_name (connection,
                                       "org.gnome.ColorManager",
                                       "/org/gnome/ColorManager",
                                       "org.gnome.ColorManager");

    /* Get color profile */
    device_id = g_strdup_printf ("sane:%s", current_device);
    custom_g_type_string_string = dbus_g_type_get_collection ("GPtrArray",
                                                              dbus_g_type_get_struct("GValueArray",
                                                                                     G_TYPE_STRING,
                                                                                     G_TYPE_STRING,
                                                                                     G_TYPE_INVALID));
    ret = dbus_g_proxy_call (proxy, "GetProfilesForDevice", &error,
                             G_TYPE_STRING, device_id,
                             G_TYPE_STRING, "",
                             G_TYPE_INVALID,
                             custom_g_type_string_string, &profile_data_array,
                             G_TYPE_INVALID);
    g_object_unref (proxy);
    g_free (device_id);
    if (!ret) {
        g_debug ("The request failed: %s", error->message);
        g_error_free (error);
        return NULL;
    }

    if (profile_data_array->len > 0) {
        GValueArray *gva;
        GValue *gv = NULL;

        /* Just use the preferred profile filename */
        gva = (GValueArray *) g_ptr_array_index (profile_data_array, 0);
        gv = g_value_array_get_nth (gva, 1);
        icc_profile = g_value_dup_string (gv);
        g_value_unset (gv);
    }
    else
        g_debug ("There are no ICC profiles for the device sane:%s", current_device);
    g_ptr_array_free (profile_data_array, TRUE);

    return icc_profile;
}


static void
scanner_page_info_cb (Scanner *scanner, ScanPageInfo *info)
{
    Page *page;

    g_debug ("Page is %d pixels wide, %d pixels high, %d bits per pixel",
             info->width, info->height, info->depth);

    /* Add a new page */
    page = append_page ();
    page_set_scan_area (page, info->width, info->height, info->dpi);

    /* Get ICC color profile */
    /* FIXME: The ICC profile could change */
    /* FIXME: Don't do a D-bus call for each page, cache color profiles */
    page_set_color_profile (page, get_profile_for_device (info->device));
}


static void
scanner_line_cb (Scanner *scanner, ScanLine *line)
{
    Page *page;

    page = book_get_page (book, book_get_n_pages (book) - 1);
    page_parse_scan_line (page, line);
}


static void
scanner_page_done_cb (Scanner *scanner)
{
    Page *page;
    page = book_get_page (book, book_get_n_pages (book) - 1);
    page_finish (page);
}


static void
remove_empty_page ()
{
    Page *page;

    page = book_get_page (book, book_get_n_pages (book) - 1);

    /* Remove a failed page */
    if (page_has_data (page))
        page_finish (page);
    else
        book_delete_page (book, page); 
}


static void
scanner_document_done_cb (Scanner *scanner)
{
    remove_empty_page ();
}


static void
scanner_failed_cb (Scanner *scanner, GError *error)
{
    remove_empty_page ();
    if (!g_error_matches (error, SCANNER_TYPE, SANE_STATUS_CANCELLED)) {
        ui_show_error (ui,
                       /* Title of error dialog when scan failed */
                       _("Failed to scan"),
                       error->message,
                       TRUE);
    }
}


static void
scanner_scanning_changed_cb (Scanner *scanner)
{
    ui_set_scanning (ui, scanner_is_scanning (scanner));
}


static void
scan_cb (SimpleScan *ui, const gchar *device, ScanOptions *options)
{
    /* Default filename to use when saving document (and extension will be added, e.g. .jpg) */
    const gchar *filename_prefix = _("Scanned Document");
    const gchar *extension;
    gchar *filename;

    if (options->scan_mode == SCAN_MODE_COLOR)
        extension = "jpg";
    else
        extension = "pdf";

    g_debug ("Requesting scan at %d dpi from device '%s'", options->dpi, device);

    if (!scanner_is_scanning (scanner))
        append_page ();

    filename = g_strdup_printf ("%s.%s", filename_prefix, extension);
    ui_set_default_file_name (ui, filename);
    g_free (filename);
    scanner_scan (scanner, device, options);
}


static void
cancel_cb (SimpleScan *ui)
{
    scanner_cancel (scanner);
}


static gboolean
save_book_by_extension (GFile *file, GError **error)
{
    gboolean result;
    gchar *uri, *uri_lower;

    uri = g_file_get_uri (file);
    uri_lower = g_utf8_strdown (uri, -1);
    if (g_str_has_suffix (uri_lower, ".pdf"))
        result = book_save (book, "pdf", file, error);
    else if (g_str_has_suffix (uri_lower, ".ps"))
        result = book_save (book, "ps", file, error);
    else if (g_str_has_suffix (uri_lower, ".png"))
        result = book_save (book, "png", file, error);
    else if (g_str_has_suffix (uri_lower, ".tif") || g_str_has_suffix (uri_lower, ".tiff"))
        result = book_save (book, "tiff", file, error);
    else
        result = book_save (book, "jpeg", file, error);

    g_free (uri);
    g_free (uri_lower);

    return result;
}


static void
save_cb (SimpleScan *ui, const gchar *uri)
{
    GError *error = NULL;
    GFile *file;

    g_debug ("Saving to '%s'", uri);

    file = g_file_new_for_uri (uri);
    if (!save_book_by_extension (file, &error)) {
        g_warning ("Error saving file: %s", error->message);
        ui_show_error (ui,
                       /* Title of error dialog when save failed */
                       _("Failed to save file"),
                       error->message,
               FALSE);
        g_error_free (error);
    }
    g_object_unref (file);
}


static gchar *
get_temporary_filename (const gchar *prefix, const gchar *extension)
{
    gint fd;
    gchar *filename, *path;
    GError *error = NULL;

    /* NOTE: I'm not sure if this is a 100% safe strategy to use g_file_open_tmp(), close and
     * use the filename but it appears to work in practise */

    filename = g_strdup_printf ("%s-XXXXXX.%s", prefix, extension);
    fd = g_file_open_tmp (filename, &path, &error);
    g_free (filename);
    if (fd < 0) {
        g_warning ("Error saving email attachment: %s", error->message);
        g_clear_error (&error);
        return NULL;
    }
    close (fd);

    return path;
}


static void
email_cb (SimpleScan *ui, const gchar *profile)
{
    gboolean saved = FALSE;
    GError *error = NULL;
    GString *command_line;
  
    command_line = g_string_new ("xdg-email");

    /* Save text files as PDFs */
    if (strcmp (profile, "text") == 0) {
        gchar *path;

        /* Open a temporary file */
        path = get_temporary_filename ("scanned-document", "pdf");
        if (path) {
            GFile *file;

            file = g_file_new_for_path (path);
            saved = book_save (book, "pdf", file, &error);
            g_string_append_printf (command_line, " --attach %s", path);
            g_free (path);
            g_object_unref (file);
        }
    }
    else {
        gint i;

        for (i = 0; i < book_get_n_pages (book); i++) {
            gchar *path;
            GFile *file;

            path = get_temporary_filename ("scanned-document", "jpg");
            if (!path) {
                saved = FALSE;
                break;
            }

            file = g_file_new_for_path (path);
            saved = page_save (book_get_page (book, i), "jpeg", file, &error);
            g_string_append_printf (command_line, " --attach %s", path);
            g_free (path);
            g_object_unref (file);
          
            if (!saved)
                break;
        }
    }

    if (saved) {
        g_debug ("Launchind email client: %s", command_line->str);
        g_spawn_command_line_async (command_line->str, &error);

        if (error) {
            g_warning ("Unable to start email: %s", error->message);
            g_clear_error (&error);
        }
    }
    else {
        g_warning ("Unable to save email file: %s", error->message);
        g_clear_error (&error);
    }

    g_string_free (command_line, TRUE);
}


static void
quit_cb (SimpleScan *ui)
{
    g_object_unref (book);
    g_object_unref (ui);
    g_object_unref (udev_client);
    scanner_free (scanner);
    gtk_main_quit ();
}


static void
version()
{
    /* NOTE: Is not translated so can be easily parsed */
    fprintf(stderr, "%1$s %2$s\n", SIMPLE_SCAN_BINARY, VERSION);
}


static void
usage(int show_gtk)
{
    fprintf(stderr,
            /* Description on how to use simple-scan displayed on command-line */
            _("Usage:\n"
              "  %s [DEVICE...] - Scanning utility"), SIMPLE_SCAN_BINARY);

    fprintf(stderr,
            "\n\n");

    fprintf(stderr,
            /* Description on how to use simple-scan displayed on command-line */    
            _("Help Options:\n"
              "  -d, --debug                     Print debugging messages\n"
              "  -v, --version                   Show release version\n"
              "  -h, --help                      Show help options\n"
              "  --help-all                      Show all help options\n"
              "  --help-gtk                      Show GTK+ options"));
    fprintf(stderr,
            "\n\n");

    if (show_gtk) {
        fprintf(stderr,
                /* Description on simple-scan command-line GTK+ options displayed on command-line */
                _("GTK+ Options:\n"
                  "  --class=CLASS                   Program class as used by the window manager\n"
                  "  --name=NAME                     Program name as used by the window manager\n"
                  "  --screen=SCREEN                 X screen to use\n"
                  "  --sync                          Make X calls synchronous\n"
                  "  --gtk-module=MODULES            Load additional GTK+ modules\n"
                  "  --g-fatal-warnings              Make all warnings fatal"));
        fprintf(stderr,
                "\n\n");
    }
}


static void
log_cb (const gchar *log_domain, GLogLevelFlags log_level,
        const gchar *message, gpointer data)
{
    /* Log everything to a file */
    if (log_file) {
        const gchar *prefix;

        switch (log_level & G_LOG_LEVEL_MASK) {
        case G_LOG_LEVEL_ERROR:
            prefix = "ERROR:";
            break;
        case G_LOG_LEVEL_CRITICAL:
            prefix = "CRITICAL:";
            break;
        case G_LOG_LEVEL_WARNING:
            prefix = "WARNING:";
            break;
        case G_LOG_LEVEL_MESSAGE:
            prefix = "MESSAGE:";
            break;
        case G_LOG_LEVEL_INFO:
            prefix = "INFO:";
            break;
        case G_LOG_LEVEL_DEBUG:
            prefix = "DEBUG:";
            break;
        default:
            prefix = "LOG:";
            break;
        }

        fprintf (log_file, "[%+.2fs] %s %s\n", g_timer_elapsed (log_timer, NULL), prefix, message);
    }

    /* Only show debug if requested */
    if (log_level & G_LOG_LEVEL_DEBUG) {
        if (debug)
            g_log_default_handler (log_domain, log_level, message, data);
    }
    else
        g_log_default_handler (log_domain, log_level, message, data);    
}


static void
get_options (int argc, char **argv)
{
    int i;

    for (i = 1; i < argc; i++) {
        char *arg = argv[i];

        if (strcmp (arg, "-d") == 0 ||
            strcmp (arg, "--debug") == 0) {
            debug = TRUE;
        }
        else if (strcmp (arg, "-v") == 0 ||
            strcmp (arg, "--version") == 0) {
            version ();
            exit (0);
        }
        else if (strcmp (arg, "-h") == 0 ||
                 strcmp (arg, "--help") == 0) {
            usage (FALSE);
            exit (0);
        }
        else if (strcmp (arg, "--help-all") == 0 ||
                 strcmp (arg, "--help-gtk") == 0) {
            usage (TRUE);
            exit (0);
        }
        else {
            if (default_device) {
                fprintf (stderr, "Unknown argument: '%s'\n", arg);
                exit (1);
            }
            default_device = arg;
        }
    }   
}


static void
on_uevent (GUdevClient *client, const gchar *action, GUdevDevice *device)
{
    scanner_redetect (scanner);
}


int
main (int argc, char **argv)
{
    const char *udev_subsystems[] = { "usb", NULL };
    gchar *path;

    g_thread_init (NULL);

    /* Log to a file */
    log_timer = g_timer_new ();
    path = g_build_filename (g_get_user_cache_dir (), "simple-scan", NULL);
    g_mkdir_with_parents (path, 0700);
    g_free (path);
    path = g_build_filename (g_get_user_cache_dir (), "simple-scan", "simple-scan.log", NULL);
    log_file = fopen (path, "w");
    g_free (path);
    g_log_set_default_handler (log_cb, NULL);

    bindtextdomain (GETTEXT_PACKAGE, LOCALE_DIR);
    bind_textdomain_codeset (GETTEXT_PACKAGE, "UTF-8");
    textdomain (GETTEXT_PACKAGE);
   
    gtk_init (&argc, &argv);

    get_options (argc, argv);
  
    g_debug ("Starting Simple Scan %s, PID=%i", VERSION, getpid ());
  
    ui = ui_new ();
    book = ui_get_book (ui);
    g_signal_connect (ui, "start-scan", G_CALLBACK (scan_cb), NULL);
    g_signal_connect (ui, "stop-scan", G_CALLBACK (cancel_cb), NULL);
    g_signal_connect (ui, "save", G_CALLBACK (save_cb), NULL);
    g_signal_connect (ui, "email", G_CALLBACK (email_cb), NULL);
    g_signal_connect (ui, "quit", G_CALLBACK (quit_cb), NULL);

    scanner = scanner_new ();
    g_signal_connect (G_OBJECT (scanner), "update-devices", G_CALLBACK (update_scan_devices_cb), NULL);
    g_signal_connect (G_OBJECT (scanner), "authorize", G_CALLBACK (authorize_cb), NULL);
    g_signal_connect (G_OBJECT (scanner), "expect-page", G_CALLBACK (scanner_new_page_cb), NULL);
    g_signal_connect (G_OBJECT (scanner), "got-page-info", G_CALLBACK (scanner_page_info_cb), NULL);
    g_signal_connect (G_OBJECT (scanner), "got-line", G_CALLBACK (scanner_line_cb), NULL);
    g_signal_connect (G_OBJECT (scanner), "page-done", G_CALLBACK (scanner_page_done_cb), NULL);
    g_signal_connect (G_OBJECT (scanner), "document-done", G_CALLBACK (scanner_document_done_cb), NULL);
    g_signal_connect (G_OBJECT (scanner), "scan-failed", G_CALLBACK (scanner_failed_cb), NULL);
    g_signal_connect (G_OBJECT (scanner), "scanning-changed", G_CALLBACK (scanner_scanning_changed_cb), NULL);

    udev_client = g_udev_client_new (udev_subsystems);
    g_signal_connect (udev_client, "uevent", G_CALLBACK (on_uevent), NULL);

    if (default_device)
        ui_set_selected_device (ui, default_device);

    ui_start (ui);
    scanner_start (scanner);

    gtk_main ();

    return 0;
}
