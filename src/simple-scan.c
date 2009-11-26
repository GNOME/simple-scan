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

#include "ui.h"
#include "scanner.h"
#include "book.h"
#include "book-view.h"


static const char *default_device = NULL;

static SimpleScan *ui;

static Scanner *scanner;

static Book *book;

static BookView *book_view;

static gboolean scanning = FALSE;

static gboolean clear_pages = FALSE;

static gboolean first_autodetect = TRUE;

static Orientation default_orientation = TOP_TO_BOTTOM;

static int page_count = 0;


static void
scanner_ready_cb (Scanner *scanner)
{
    scanning = FALSE;
    ui_set_scanning (ui, FALSE);
}


static void
update_scan_devices_cb (Scanner *scanner, GList *devices)
{
    GList *dev_iter;
    gboolean first;

    if (first_autodetect) {
        first_autodetect = FALSE;

        if (!devices) {
            gchar *selected;

            selected = ui_get_selected_device (ui);
            if (!selected)
                ui_show_error (ui,
                               /* Warning displayed when no scanners are detected */
                               _("No scanners detected"),
                               /* Hint to user on why there are no scanners detected */
                               _("Please check your scanner is connected and powered on"));
            g_free (selected);
        }
    }

    /* Mark existing values as undetected */
    ui_mark_devices_undetected (ui);

    /* Add/update detected devices */
    for (dev_iter = devices; dev_iter; dev_iter = dev_iter->next) {
        ScanDevice *device = dev_iter->data;       
        ui_add_scan_device (ui, device->name, device->label);
    }
}


static void
scanner_page_info_cb (Scanner *scanner, ScanPageInfo *info)
{
    Page *page;
    gint height;

    g_debug ("Page is %d pixels wide, %d pixels high, %d bits per pixel",
             info->width, info->height, info->depth);
    
    if (clear_pages) {
        page_count = 0;
        book_clear (book);
        clear_pages = FALSE;
    }

    page = book_append_page (book, info->width, info->height, info->dpi, default_orientation);
    page_start (page);

    page_count++;
}


static void
scanner_line_cb (Scanner *scanner, ScanLine *line)
{
    Page *page;

    page = book_get_page (book, page_count - 1);
    page_parse_scan_line (page, line);
}


static void
scanner_image_done_cb (Scanner *scanner)
{
    Page *page;
    
    page = book_get_page (book, page_count - 1);
    page_finish (page);
    ui_set_have_scan (ui, TRUE);
}


static void
scanner_failed_cb (Scanner *scanner, GError *error)
{
    ui_show_error (ui,
                   /* Title of error dialog when scan failed */
                   _("Failed to scan"),
                   error->message);
}


static void
redraw_cb (BookView *view)
{
    ui_redraw_preview (ui);  
}


static void
scan_cb (SimpleScan *ui, const gchar *device, const gchar *document_type)
{
    PageMode page_mode;
    gint dpi;

    g_debug ("Requesting scan of type %s from device '%s'", document_type, device);

    scanning = TRUE;
    ui_set_have_scan (ui, FALSE);
    ui_set_scanning (ui, TRUE);
    
    // FIXME: Translate
    if (strcmp (document_type, "photo") == 0) {
        ui_set_default_file_name (ui,
                                  /* Default name for JPEG documents */
                                  _("Scanned Document.jpeg"));
        dpi = 400;
    }
    else if (strcmp (document_type, "document") == 0) {
        ui_set_default_file_name (ui,
                                  /* Default name for PDF documents */
                                  _("Scanned Document.pdf"));
        dpi = 200;
    }
    else if (strcmp (document_type, "raw") == 0) {
        ui_set_default_file_name (ui,
                                  /* Default name for PNG documents */
                                  _("Scanned Document.png"));
        dpi = 400;
    }
    /* Draft or unknown */
    else
    {
        ui_set_default_file_name (ui, _("Scanned Document.jpeg"));
        dpi = 75;
    }

    page_mode = ui_get_page_mode (ui);

    /* Start again if not using multiple scans */
    if (page_mode != PAGE_MULTIPLE)
        clear_pages = TRUE;

    //scanner_scan (scanner, device, NULL, dpi, NULL, 8, page_mode == PAGE_AUTOMATIC);
    //scanner_scan (scanner, device, "Flatbed", 50, "Color", 8, page_mode == PAGE_AUTOMATIC);
    scanner_scan (scanner, device, "Automatic Document Feeder", 200, "Color", 8, page_mode == PAGE_AUTOMATIC);
}


static void
cancel_cb (SimpleScan *ui)
{
    scanner_cancel (scanner);
}


static void
rotate_left_cb (SimpleScan *ui)
{
    Page *page;
    gint t;
    Orientation orientation;

    page = book_get_page (book, page_count - 1);
    orientation = page_get_orientation (page);
    if (orientation == RIGHT_TO_LEFT)
        orientation = TOP_TO_BOTTOM;
    else
        orientation++;
    page_set_orientation (page, orientation);
    default_orientation = orientation;
}


static void
rotate_right_cb (SimpleScan *ui)
{
    Page *page;
    gint t;
    Orientation orientation;

    page = book_get_page (book, page_count - 1);
    orientation = page_get_orientation (page);
    if (orientation == TOP_TO_BOTTOM)
        orientation = RIGHT_TO_LEFT;
    else
        orientation--;
    page_set_orientation (page, orientation);
    default_orientation = orientation;
}


static void
save_cb (SimpleScan *ui, gchar *uri)
{
    GFile *file;
    GError *error = NULL;
    GFileOutputStream *stream;

    file = g_file_new_for_uri (uri);

    stream = g_file_replace (file, NULL, FALSE, G_FILE_CREATE_NONE, NULL, &error);
    if (!stream) {
        g_warning ("Error saving file: %s", error->message);
        g_error_free (error);
    }
    else {
        gboolean result;
        gchar *uri_lower;

        uri_lower = g_utf8_strdown (uri, -1);
        if (g_str_has_suffix (uri_lower, ".pdf"))
            result = book_save_pdf (book, stream, &error);
        else if (g_str_has_suffix (uri_lower, ".ps"))
            result = book_save_ps (book, stream, &error);
        else if (g_str_has_suffix (uri_lower, ".png"))
            result = book_save_png (book, stream, &error);
        else
            result = book_save_jpeg (book, stream, &error);

        g_free (uri_lower);           

        if (error) {
            g_warning ("Error saving file: %s", error->message);
            ui_show_error (ui,
                           /* Title of error dialog when save failed */
                           _("Failed to save file"),
                           error->message);
            g_error_free (error);
        }

        g_output_stream_close (G_OUTPUT_STREAM (stream), NULL, NULL);
    }
}


static void
print_cb (SimpleScan *ui, cairo_t *context)
{
    book_print (book, context);
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
get_options (int argc, char **argv)
{
    int i;

    for (i = 1; i < argc; i++) {
        char *arg = argv[i];

        if (strcmp (arg, "-v") == 0 ||
            strcmp (arg, "--version") == 0) {
            version ();
            exit (0);
        }
        else if (strcmp (arg, "-h") == 0 ||
                 strcmp (arg, "--help") == 0) {
            usage (FALSE);
            exit (0);
        }
        else if (strcmp (arg, "--help-all") == 0) {
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


int
main(int argc, char **argv)
{
    g_thread_init (NULL);
    gtk_init (&argc, &argv);
    
    get_options (argc, argv);

    book = book_new ();
    /* Start with A4 white image at 72dpi */
    /* TODO: Should be like the last scanned image for the selected scanner */
    book_append_page (book, 595, 842, 72, default_orientation);
    page_count++;
    book_append_page (book, 595, 842, 72, default_orientation);
    page_count++;
    book_append_page (book, 595, 842, 72, default_orientation);
    page_count++;

    ui = ui_new ();
    g_signal_connect (ui, "start-scan", G_CALLBACK (scan_cb), NULL);
    g_signal_connect (ui, "stop-scan", G_CALLBACK (cancel_cb), NULL);
    g_signal_connect (ui, "rotate-left", G_CALLBACK (rotate_left_cb), NULL);
    g_signal_connect (ui, "rotate-right", G_CALLBACK (rotate_right_cb), NULL);
    g_signal_connect (ui, "save", G_CALLBACK (save_cb), NULL);
    g_signal_connect (ui, "print", G_CALLBACK (print_cb), NULL);
    g_signal_connect (ui, "quit", G_CALLBACK (quit_cb), NULL);

    book_view = book_view_new ();
    book_view_set_widget (book_view, ui_get_preview_widget (ui)); // FIXME
    book_view_set_book (book_view, book);
    
    ui_set_zoom_adjustment (ui, book_view_get_zoom_adjustment (book_view));
    
    scanner = scanner_new ();
    g_signal_connect (G_OBJECT (scanner), "ready", G_CALLBACK (scanner_ready_cb), NULL);
    g_signal_connect (G_OBJECT (scanner), "update-devices", G_CALLBACK (update_scan_devices_cb), NULL);
    g_signal_connect (G_OBJECT (scanner), "got-page-info", G_CALLBACK (scanner_page_info_cb), NULL);
    g_signal_connect (G_OBJECT (scanner), "got-line", G_CALLBACK (scanner_line_cb), NULL);
    g_signal_connect (G_OBJECT (scanner), "image-done", G_CALLBACK (scanner_image_done_cb), NULL);
    g_signal_connect (G_OBJECT (scanner), "scan-failed", G_CALLBACK (scanner_failed_cb), NULL);

    if (default_device)
        ui_set_selected_device (ui, default_device);

    ui_start (ui);
    scanner_start (scanner);

    gtk_main ();

    return 0;
}
