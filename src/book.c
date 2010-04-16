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

#include <string.h>
#include <math.h>
#include <gdk/gdk.h>
#include <gdk-pixbuf/gdk-pixbuf.h>
#include <cairo/cairo-pdf.h>
#include <cairo/cairo-ps.h>
#include <unistd.h> // TEMP: Needed for close() in get_temporary_filename()

#include "book.h"


enum {
    PAGE_ADDED,
    PAGE_REMOVED,
    CLEARED,
    LAST_SIGNAL
};
static guint signals[LAST_SIGNAL] = { 0, };

struct BookPrivate
{
    GList *pages;
};

G_DEFINE_TYPE (Book, book, G_TYPE_OBJECT);


Book *
book_new ()
{
    return g_object_new (BOOK_TYPE, NULL);
}


void
book_clear (Book *book)
{
    GList *iter;
    for (iter = book->priv->pages; iter; iter = iter->next) {
        Page *page = iter->data;
        g_object_unref (page);
    }
    g_list_free (book->priv->pages);
    book->priv->pages = NULL;
    g_signal_emit (book, signals[CLEARED], 0);
}


Page *
book_append_page (Book *book, gint width, gint height, gint dpi, Orientation orientation)
{
    Page *page;

    page = page_new ();
    page_setup (page, width, height, dpi, orientation);

    book->priv->pages = g_list_append (book->priv->pages, page);

    g_signal_emit (book, signals[PAGE_ADDED], 0, page);

    return page;
}


void
book_delete_page (Book *book, Page *page)
{
    g_signal_emit (book, signals[PAGE_REMOVED], 0, page);

    book->priv->pages = g_list_remove (book->priv->pages, page);
    g_object_unref (page);
}


gint
book_get_n_pages (Book *book)
{
    return g_list_length (book->priv->pages);    
}


Page *
book_get_page (Book *book, gint page_number)
{
    if (page_number < 0)
        page_number = g_list_length (book->priv->pages) + page_number;
    return g_list_nth_data (book->priv->pages, page_number);
}


static GFile *
make_indexed_file (const gchar *uri, gint i)
{
    gchar *basename, *suffix, *indexed_uri;
    GFile *file;

    if (i == 0)
        return g_file_new_for_uri (uri);

    basename = g_path_get_basename (uri);
    suffix = g_strrstr (basename, ".");

    if (suffix)
        indexed_uri = g_strdup_printf ("%.*s-%d%s", (int) (strlen (uri) - strlen (suffix)), uri, i, suffix);
    else
        indexed_uri = g_strdup_printf ("%s-%d", uri, i);
    g_free (basename);

    file = g_file_new_for_uri (indexed_uri);
    g_free (indexed_uri);

    return file;
}


static gboolean
book_save_multi_file (Book *book, const gchar *type, GFile *file, GError **error)
{
    GList *iter;
    gboolean result = TRUE;
    gint i;
    gchar *uri;

    uri = g_file_get_uri (file);
    for (iter = book->priv->pages, i = 0; iter && result; iter = iter->next, i++) {
        Page *page = iter->data;
        GFile *file;

        file = make_indexed_file (uri, i);
        result = page_save (page, type, file, error);
        g_object_unref (file);
    }
    g_free (uri);
   
    return result;
}


static void
save_ps_pdf_surface (cairo_surface_t *surface, GdkPixbuf *image, gdouble dpi)
{
    cairo_t *context;
    
    context = cairo_create (surface);

    cairo_scale (context, 72.0 / dpi, 72.0 / dpi);
    gdk_cairo_set_source_pixbuf (context, image, 0, 0);
    cairo_pattern_set_filter (cairo_get_source (context), CAIRO_FILTER_BEST);
    cairo_paint (context);

    cairo_destroy (context);
}


static cairo_status_t
write_cairo_data (GFileOutputStream *stream, unsigned char *data, unsigned int length)
{
    gboolean result;
    GError *error = NULL;

    result = g_output_stream_write_all (G_OUTPUT_STREAM (stream), data, length, NULL, NULL, &error);
    
    if (error) {
        g_warning ("Error writing data: %s", error->message);
        g_error_free (error);
    }

    return result ? CAIRO_STATUS_SUCCESS : CAIRO_STATUS_WRITE_ERROR;
}


static gboolean
book_save_ps (Book *book, GFile *file, GError **error)
{
    GFileOutputStream *stream;
    GList *iter;
    cairo_surface_t *surface;

    stream = g_file_replace (file, NULL, FALSE, G_FILE_CREATE_NONE, NULL, error);
    if (!stream)
        return FALSE;

    surface = cairo_ps_surface_create_for_stream ((cairo_write_func_t) write_cairo_data,
                                                  stream, 0, 0);

    for (iter = book->priv->pages; iter; iter = iter->next) {
        Page *page = iter->data;
        double width, height;
        GdkPixbuf *image;

        image = page_get_cropped_image (page);

        width = gdk_pixbuf_get_width (image) * 72.0 / page_get_dpi (page);
        height = gdk_pixbuf_get_height (image) * 72.0 / page_get_dpi (page);
        cairo_ps_surface_set_size (surface, width, height);
        save_ps_pdf_surface (surface, image, page_get_dpi (page));
        cairo_surface_show_page (surface);
        
        g_object_unref (image);
    }

    cairo_surface_destroy (surface);

    g_object_unref (stream);

    return TRUE;
}


// TEMP: Copied from simple-scan.c
static GFile *
get_temporary_file (const gchar *prefix, const gchar *extension)
{
    gint fd;
    GFile *file;
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
  
    file = g_file_new_for_path (path);
    g_free (path);

    return file;
}


static goffset
get_file_size (GFile *file)
{
    GFileInfo *info;
    goffset size = 0;
  
    info = g_file_query_info (file,
                              G_FILE_ATTRIBUTE_STANDARD_SIZE,
                              G_FILE_QUERY_INFO_NONE,
                              NULL,
                              NULL);
    if (info) {
        size = g_file_info_get_size (info);
        g_object_unref (info);
    }

    return size;
}


static gboolean
book_save_pdf_with_imagemagick (Book *book, GFile *file, GError **error)
{
    GList *iter;
    GString *command_line;
    gboolean result = TRUE;
    gint exit_status = 0;
    GFile *output_file = NULL;
    GList *link, *temporary_files = NULL;

    /* ImageMagick command to create a PDF */
    command_line = g_string_new ("convert -adjoin");

    /* Save each page to a file */
    for (iter = book->priv->pages; iter && result; iter = iter->next) {
        Page *page = iter->data;
        GFile *jpeg_file, *tiff_file;
        gchar *path;
        gint jpeg_size, tiff_size;

        jpeg_file = get_temporary_file ("simple-scan", "jpg");
        result = page_save (page, "jpeg", jpeg_file, error);
        jpeg_size = get_file_size (jpeg_file);
        temporary_files = g_list_append (temporary_files, jpeg_file);

        tiff_file = get_temporary_file ("simple-scan", "tiff");
        result = page_save (page, "tiff", tiff_file, error);
        tiff_size = get_file_size (tiff_file);
        temporary_files = g_list_append (temporary_files, tiff_file);

        /* Use the smallest file */
        if (jpeg_size < tiff_size)
            path = g_file_get_path (jpeg_file);
        else
            path = g_file_get_path (tiff_file);
        g_string_append_printf (command_line, " %s", path);
        g_free (path);
    }

    /* Use ImageMagick command to create a PDF */  
    if (result) {
        gchar *path, *stdout_text = NULL, *stderr_text = NULL;

        output_file = get_temporary_file ("simple-scan", "pdf");
        path = g_file_get_path (output_file);
        g_string_append_printf (command_line, " %s", path);
        g_free (path);

        result = g_spawn_command_line_sync (command_line->str, &stdout_text, &stderr_text, &exit_status, error);
        if (result && exit_status != 0) {
            g_warning ("ImageMagick returned error code %d, command line was: %s", exit_status, command_line->str);
            g_warning ("stdout: %s", stdout_text);
            g_warning ("stderr: %s", stderr_text);
            result = FALSE;
            g_set_error (error, BOOK_TYPE, 0, "ImageMagick returned error code %d, command line was: %s", exit_status, command_line->str);
        }
        g_free (stdout_text);
        g_free (stderr_text);
    }

    /* Move to target URI */
    if (result)
        result = g_file_move (output_file, file, G_FILE_COPY_OVERWRITE, NULL, NULL, NULL, error);
  
    /* Delete page files */
    for (link = temporary_files; link; link = link->next) {
        GFile *f = link->data;

        g_file_delete (f, NULL, NULL);
        g_object_unref (f);
    }
    g_list_free (temporary_files);

    if (output_file)
        g_object_unref (output_file);
    g_string_free (command_line, TRUE);

    return result;
}


static gboolean
book_save_pdf (Book *book, GFile *file, GError **error)
{
    GFileOutputStream *stream;
    GList *iter;
    cairo_surface_t *surface;
    gchar *imagemagick_executable;
  
    /* Use ImageMagick if it is available as then we can compress the images */
    imagemagick_executable = g_find_program_in_path ("convert");
    if (imagemagick_executable) {
        g_free (imagemagick_executable);
        return book_save_pdf_with_imagemagick (book, file, error);
    }

    stream = g_file_replace (file, NULL, FALSE, G_FILE_CREATE_NONE, NULL, error);
    if (!stream)
        return FALSE;

    surface = cairo_pdf_surface_create_for_stream ((cairo_write_func_t) write_cairo_data,
                                                   stream, 0, 0);

    for (iter = book->priv->pages; iter; iter = iter->next) {
        Page *page = iter->data;
        double width, height;
        GdkPixbuf *image;

        image = page_get_cropped_image (page);

        width = gdk_pixbuf_get_width (image) * 72.0 / page_get_dpi (page);
        height = gdk_pixbuf_get_height (image) * 72.0 / page_get_dpi (page);
        cairo_pdf_surface_set_size (surface, width, height);
        save_ps_pdf_surface (surface, image, page_get_dpi (page));
        cairo_surface_show_page (surface);
        
        g_object_unref (image);
    }

    cairo_surface_destroy (surface);

    g_object_unref (stream);

    return TRUE;
}


gboolean
book_save (Book *book, const gchar *type, GFile *file, GError **error)
{
    if (strcmp (type, "jpeg") == 0)
        return book_save_multi_file (book, "jpeg", file, error);
    else if (strcmp (type, "png") == 0)
        return book_save_multi_file (book, "png", file, error);
    else if (strcmp (type, "tiff") == 0)
        return book_save_multi_file (book, "tiff", file, error);    
    else if (strcmp (type, "ps") == 0)
        return book_save_ps (book, file, error);    
    else if (strcmp (type, "pdf") == 0)
        return book_save_pdf (book, file, error);
    else
        return FALSE;
}


static void
book_finalize (GObject *object)
{
    Book *book = BOOK (object);
    book_clear (book);
    G_OBJECT_CLASS (book_parent_class)->finalize (object);
}


static void
book_class_init (BookClass *klass)
{
    GObjectClass *object_class = G_OBJECT_CLASS (klass);

    object_class->finalize = book_finalize;

    signals[PAGE_ADDED] =
        g_signal_new ("page-added",
                      G_TYPE_FROM_CLASS (klass),
                      G_SIGNAL_RUN_LAST,
                      G_STRUCT_OFFSET (BookClass, page_added),
                      NULL, NULL,
                      g_cclosure_marshal_VOID__OBJECT,
                      G_TYPE_NONE, 1, page_get_type ());
    signals[PAGE_REMOVED] =
        g_signal_new ("page-removed",
                      G_TYPE_FROM_CLASS (klass),
                      G_SIGNAL_RUN_LAST,
                      G_STRUCT_OFFSET (BookClass, page_removed),
                      NULL, NULL,
                      g_cclosure_marshal_VOID__OBJECT,
                      G_TYPE_NONE, 1, page_get_type ());
    signals[CLEARED] =
        g_signal_new ("cleared",
                      G_TYPE_FROM_CLASS (klass),
                      G_SIGNAL_RUN_LAST,
                      G_STRUCT_OFFSET (BookClass, cleared),
                      NULL, NULL,
                      g_cclosure_marshal_VOID__VOID,
                      G_TYPE_NONE, 0);

    g_type_class_add_private (klass, sizeof (BookPrivate));
}


static void
book_init (Book *book)
{
    book->priv = G_TYPE_INSTANCE_GET_PRIVATE (book, BOOK_TYPE, BookPrivate);
}
