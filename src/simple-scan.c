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

#include <sane/sane.h> // For SANE_STATUS_CANCELLED

#include "ui.h"
#include "scanner.h"
#include "book.h"


static const char *default_device = NULL;

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
        width = page_get_scan_width (page);
        height = page_get_scan_height (page);
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
scanner_page_info_cb (Scanner *scanner, ScanPageInfo *info)
{
    Page *page;

    g_debug ("Page is %d pixels wide, %d pixels high, %d bits per pixel",
             info->width, info->height, info->depth);

    /* Add a new page */
    page = append_page (FALSE);
    page_set_scan_area (page, info->width, info->height, info->dpi);
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
scanner_document_done_cb (Scanner *scanner)
{
    ui_set_scanning (ui, FALSE);
    ui_set_have_scan (ui, TRUE);
}


static void
scanner_failed_cb (Scanner *scanner, GError *error)
{
    Page *page;

    page = book_get_page (book, book_get_n_pages (book) - 1);

    /* Remove a failed page */
    if (page_has_data (page))
        page_finish (page);
    else
        book_delete_page (book, page); 

    if (!g_error_matches (error, SCANNER_TYPE, SANE_STATUS_CANCELLED)) {
        ui_show_error (ui,
                       /* Title of error dialog when scan failed */
                       _("Failed to scan"),
                       error->message,
                       TRUE);
    }
        
    ui_set_scanning (ui, FALSE);
    ui_set_have_scan (ui, TRUE);
}


static void
scan_cb (SimpleScan *ui, const gchar *device, gint dpi, const gchar *profile_name, gboolean continuous)
{
    /* Default filename to use when saving document (and extension will be added, e.g. .jpg) */
    const gchar *filename_prefix = _("Scanned Document");
    struct {
        const gchar *name;
        ScanMode mode;
        const gchar *extension;
    } profiles[] = 
    {
        { "text",  SCAN_MODE_LINEART, "pdf" },
        { "photo", SCAN_MODE_COLOR,   "jpg" },
        { NULL,    SCAN_MODE_COLOR,   "jpg" }
    };
    gchar *filename;
    gint i;

    g_debug ("Requesting scan of type %s at %d dpi from device '%s'", profile_name, dpi, device);

    /* Find this profile */
    for (i = 0; profiles[i].name && strcmp (profiles[i].name, profile_name) != 0; i++);

    if (!scanner_is_scanning (scanner))
        append_page ();

    ui_set_have_scan (ui, FALSE);
    ui_set_scanning (ui, TRUE);

    filename = g_strdup_printf ("%s.%s", filename_prefix, profiles[i].extension);
    ui_set_default_file_name (ui, filename);
    g_free (filename);
    scanner_scan (scanner, device, dpi, profiles[i].mode, 8, continuous);
}


static void
cancel_cb (SimpleScan *ui)
{
    scanner_cancel (scanner);
}


static gboolean
save_book (const gchar *uri, GError **error)
{
    gboolean result;
    gchar *uri_lower;

    uri_lower = g_utf8_strdown (uri, -1);
    if (g_str_has_suffix (uri_lower, ".pdf"))
        result = book_save_pdf (book, uri, error);
    else if (g_str_has_suffix (uri_lower, ".ps"))
        result = book_save_ps (book, uri, error);
    else if (g_str_has_suffix (uri_lower, ".png"))
        result = book_save_png (book, uri, error);
    else
        result = book_save_jpeg (book, uri, error);

    g_free (uri_lower);

    return result;
}


static void
save_cb (SimpleScan *ui, const gchar *uri)
{
    GError *error = NULL;

    g_debug ("Saving to '%s'", uri);

    if (!save_book (uri, &error)) {
        g_warning ("Error saving file: %s", error->message);
        ui_show_error (ui,
                       /* Title of error dialog when save failed */
                       _("Failed to save file"),
                       error->message,
		       FALSE);
        g_error_free (error);
    }
}


static void
email_cb (SimpleScan *ui)
{
    gint i;
    gchar *dir, *path = NULL, *uri = NULL;

    // TODO: Delete old files on startup

    /* Save in the temporary dir */
    dir = g_build_filename (g_get_user_cache_dir (), "simple-scan", "email", NULL);
    g_mkdir_with_parents (dir, 0700);

    for (i = 0; ; i++) {
        GString *filename;
        GError *error = NULL;

        filename = g_string_new ("");
        g_string_printf (filename, "scan-%d-%d.pdf", getpid (), i);

        g_free (path);
        path = g_build_filename (dir, filename->str, NULL);
        g_string_free (filename, TRUE);

        g_free (uri);
        uri = g_filename_to_uri (path, NULL, NULL);

        if (book_save_pdf (book, uri, &error)) {
            GString *command_line;

            command_line = g_string_new ("");
            g_string_printf (command_line, "xdg-email --attach %s", path);
            g_debug ("Launchind email client: %s", command_line->str);
            g_spawn_command_line_async (command_line->str, &error);

            if (error) {
                g_warning ("Unable to start email: %s", error->message);
                g_clear_error (&error);
            }
            g_string_free (command_line, TRUE);
	    break;
        }
        else {
            if (!g_error_matches (error, G_IO_ERROR, G_IO_ERROR_EXISTS)) {
                g_warning ("Unable to save email PDF: %s", error->message);
                g_clear_error (&error);
                break;
            }
        }
    }

    g_free (path);
    g_free (uri);   
    g_free (dir);
}


static void
quit_cb (SimpleScan *ui)
{
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
    GUdevClient *udev_client;
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
    g_signal_connect (G_OBJECT (scanner), "got-page-info", G_CALLBACK (scanner_page_info_cb), NULL);
    g_signal_connect (G_OBJECT (scanner), "got-line", G_CALLBACK (scanner_line_cb), NULL);
    g_signal_connect (G_OBJECT (scanner), "page-done", G_CALLBACK (scanner_page_done_cb), NULL);
    g_signal_connect (G_OBJECT (scanner), "document-done", G_CALLBACK (scanner_document_done_cb), NULL);
    g_signal_connect (G_OBJECT (scanner), "scan-failed", G_CALLBACK (scanner_failed_cb), NULL);

    udev_client = g_udev_client_new (udev_subsystems);
    g_signal_connect (udev_client, "uevent", G_CALLBACK (on_uevent), NULL);

    if (default_device)
        ui_set_selected_device (ui, default_device);

    ui_start (ui);
    scanner_start (scanner);

    gtk_main ();

    return 0;
}
