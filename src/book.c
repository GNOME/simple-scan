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
    page_set_scan_area (page, width, height, dpi);
    page_set_orientation (page, orientation);

    book->priv->pages = g_list_append (book->priv->pages, page);

    g_signal_emit (book, signals[PAGE_ADDED], 0, page);

    return page;
}


void
book_delete_page (Book *book, Page *page)
{
    book->priv->pages = g_list_remove (book->priv->pages, page);
    g_signal_emit (book, signals[PAGE_REMOVED], 0, page);
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


static gboolean
write_pixbuf_data (const gchar *buf, gsize count, GError **error, GFileOutputStream *stream)
{
    return g_output_stream_write_all (G_OUTPUT_STREAM (stream), buf, count, NULL, NULL, error);
}


gboolean
book_save_jpeg (Book *book, GFileOutputStream *stream, GError **error)
{
    Page *page;
    GdkPixbuf *image;
    gboolean result;
    
    page = book_get_page (book, 0);
    image = page_get_cropped_image (page);
    result = gdk_pixbuf_save_to_callback (image,
                                          (GdkPixbufSaveFunc) write_pixbuf_data, stream,
                                          "jpeg", error,
                                          "quality", "90",
                                          NULL);
    g_object_unref (image);
    return result;
}


gboolean
book_save_png (Book *book, GFileOutputStream *stream, GError **error)
{
    Page *page;
    GdkPixbuf *image;
    gboolean result;

    page = book_get_page (book, 0);
    image = page_get_cropped_image (page);
    result = gdk_pixbuf_save_to_callback (image,
                                          (GdkPixbufSaveFunc) write_pixbuf_data, stream,
                                          "png", error,
                                          NULL);
    g_object_unref (image);
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


gboolean
book_save_ps (Book *book, GFileOutputStream *stream, GError **error)
{
    GList *iter;
    cairo_surface_t *surface;

    surface = cairo_ps_surface_create_for_stream ((cairo_write_func_t) write_cairo_data,
                                                  stream, 0, 0);

    // FIXME: rotate
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

    return TRUE;
}


gboolean
book_save_pdf (Book *book, GFileOutputStream *stream, GError **error)
{
    GList *iter;
    cairo_surface_t *surface;

    // FIXME: rotate

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

    return TRUE;
}


/* FIXME: Just book_render? */
void
book_print (Book *book, cairo_t *context)
{
    Page *page;
    GdkPixbuf *image;

    page = book_get_page (book, 0);
    image = page_get_cropped_image (page);

    gdk_cairo_set_source_pixbuf (context, image, 0, 0);
    cairo_pattern_set_filter (cairo_get_source (context), CAIRO_FILTER_BEST);
    cairo_paint (context);
    
    g_object_unref (image);
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
                      g_cclosure_marshal_VOID__POINTER,
                      G_TYPE_NONE, 1, G_TYPE_POINTER);
    signals[PAGE_REMOVED] =
        g_signal_new ("page-removed",
                      G_TYPE_FROM_CLASS (klass),
                      G_SIGNAL_RUN_LAST,
                      G_STRUCT_OFFSET (BookClass, page_removed),
                      NULL, NULL,
                      g_cclosure_marshal_VOID__POINTER,
                      G_TYPE_NONE, 1, G_TYPE_POINTER);
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
