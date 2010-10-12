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

#include <stdio.h>
#include <string.h>
#include <math.h>
#include <zlib.h>
#include <jpeglib.h>
#include <gdk/gdk.h>
#include <gdk-pixbuf/gdk-pixbuf.h>
#include <cairo/cairo-pdf.h>
#include <cairo/cairo-ps.h>

#include "book.h"

enum {
    PROP_0,
    PROP_NEEDS_SAVING
};

enum {
    PAGE_ADDED,
    PAGE_REMOVED,
    REORDERED,
    CLEARED,
    LAST_SIGNAL
};
static guint signals[LAST_SIGNAL] = { 0, };

struct BookPrivate
{
    GList *pages;
  
    gboolean needs_saving;
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


static void
page_changed_cb (Page *page, Book *book)
{
    book_set_needs_saving (book, TRUE);
}


Page *
book_append_page (Book *book, gint width, gint height, gint dpi, ScanDirection scan_direction)
{
    Page *page;

    page = page_new (width, height, dpi, scan_direction);
    g_signal_connect (page, "pixels-changed", G_CALLBACK (page_changed_cb), book);
    g_signal_connect (page, "crop-changed", G_CALLBACK (page_changed_cb), book);

    book->priv->pages = g_list_append (book->priv->pages, page);

    g_signal_emit (book, signals[PAGE_ADDED], 0, page);
  
    book_set_needs_saving (book, TRUE);

    return page;
}


void
book_move_page (Book *book, Page *page, gint location)
{
    book->priv->pages = g_list_remove (book->priv->pages, page);
    book->priv->pages = g_list_insert (book->priv->pages, page, location);

    g_signal_emit (book, signals[REORDERED], 0, page);

    book_set_needs_saving (book, TRUE);
}


void
book_delete_page (Book *book, Page *page)
{
    g_signal_handlers_disconnect_by_func (page, page_changed_cb, book);

    g_signal_emit (book, signals[PAGE_REMOVED], 0, page);

    book->priv->pages = g_list_remove (book->priv->pages, page);
    g_object_unref (page);

    book_set_needs_saving (book, TRUE);
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


gint
book_get_page_index (Book *book, Page *page)
{
     return g_list_index (book->priv->pages, page);
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

        image = page_get_image (page, TRUE);

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


typedef struct
{
    int offset;
    int n_objects;
    GList *object_offsets;
    GFileOutputStream *stream;
} PDFWriter;


static PDFWriter *
pdf_writer_new (GFileOutputStream *stream)
{
    PDFWriter *writer;
    writer = g_malloc0 (sizeof (PDFWriter));
    writer->stream = g_object_ref (stream);
    return writer;
}


static void
pdf_writer_free (PDFWriter *writer)
{
    g_object_unref (writer->stream);
    g_list_free (writer->object_offsets);
    g_free (writer);
}


static void
pdf_write (PDFWriter *writer, const unsigned char *data, size_t length)
{
    g_output_stream_write_all (G_OUTPUT_STREAM (writer->stream), data, length, NULL, NULL, NULL);
    writer->offset += length;
}


static void
pdf_printf (PDFWriter *writer, const char *format, ...)
{
    va_list args;
    gchar *string;

    va_start (args, format);
    string = g_strdup_vprintf (format, args);
    va_end (args);
    pdf_write (writer, (unsigned char *)string, strlen (string));

    g_free (string);
}


static int
pdf_start_object (PDFWriter *writer)
{
    writer->n_objects++;
    writer->object_offsets = g_list_append (writer->object_offsets, GINT_TO_POINTER (writer->offset));
    return writer->n_objects;
}


static guchar *
compress_zlib (guchar *data, size_t length, size_t *n_written)
{
    z_stream stream;
    guchar *out_data;

    out_data = g_malloc (sizeof (guchar) * length);

    stream.zalloc = Z_NULL;
    stream.zfree = Z_NULL;
    stream.opaque = Z_NULL;
    if (deflateInit (&stream, Z_BEST_COMPRESSION) != Z_OK)
        return NULL;

    stream.next_in = data;
    stream.avail_in = length;
    stream.next_out = out_data;
    stream.avail_out = length;
    while (stream.avail_in > 0) {
        if (deflate (&stream, Z_FINISH) == Z_STREAM_ERROR)
            break;
    }

    deflateEnd (&stream);

    if (stream.avail_in > 0) {
        g_free (out_data);
        return NULL;
    }

    *n_written = length - stream.avail_out;

    return out_data;
}


static void jpeg_init_cb (struct jpeg_compress_struct *info) {}
static boolean jpeg_empty_cb (struct jpeg_compress_struct *info) { return TRUE; }
static void jpeg_term_cb (struct jpeg_compress_struct *info) {}

static guchar *
compress_jpeg (GdkPixbuf *image, size_t *n_written)
{
    struct jpeg_compress_struct info;
    struct jpeg_error_mgr jerr;
    struct jpeg_destination_mgr dest_mgr;
    int r;
    guchar *pixels;
    guchar *data;
    size_t max_length;

    info.err = jpeg_std_error (&jerr);
    jpeg_create_compress (&info);

    pixels = gdk_pixbuf_get_pixels (image);
    info.image_width = gdk_pixbuf_get_width (image);
    info.image_height = gdk_pixbuf_get_height (image);
    info.input_components = 3;
    info.in_color_space = JCS_RGB; /* TODO: JCS_GRAYSCALE? */
    jpeg_set_defaults (&info);

    max_length = info.image_width * info.image_height * info.input_components;
    data = g_malloc (sizeof (guchar) * max_length);
    dest_mgr.next_output_byte = data;
    dest_mgr.free_in_buffer = max_length;
    dest_mgr.init_destination = jpeg_init_cb;
    dest_mgr.empty_output_buffer = jpeg_empty_cb;
    dest_mgr.term_destination = jpeg_term_cb;
    info.dest = &dest_mgr;

    jpeg_start_compress (&info, TRUE);
    for (r = 0; r < info.image_height; r++) {
        JSAMPROW row[1];
        row[0] = pixels + r * gdk_pixbuf_get_rowstride (image);
        jpeg_write_scanlines (&info, row, 1);
    }
    jpeg_finish_compress (&info);
    *n_written = max_length - dest_mgr.free_in_buffer;

    jpeg_destroy_compress (&info);

    return data;
}


static gboolean
book_save_pdf (Book *book, GFile *file, GError **error)
{
    GFileOutputStream *stream;
    PDFWriter *writer;
    int catalog_number, pages_number, info_number;
    int xref_offset;
    int i;

    stream = g_file_replace (file, NULL, FALSE, G_FILE_CREATE_NONE, NULL, error);
    if (!stream)
        return FALSE;

    writer = pdf_writer_new (stream);
    g_object_unref (stream);

    /* Header */
    pdf_printf (writer, "%%PDF-1.3\n");
  
    /* Catalog */
    catalog_number = pdf_start_object (writer);
    pdf_printf (writer, "%d 0 obj\n", catalog_number);
    pdf_printf (writer, "<<\n");
    pdf_printf (writer, "/Type /Catalog\n");
    pdf_printf (writer, "/Pages %d 0 R\n", catalog_number + 1);
    pdf_printf (writer, ">>\n");
    pdf_printf (writer, "endobj\n");

    /* Pages */
    pdf_printf (writer, "\n");
    pages_number = pdf_start_object (writer);
    pdf_printf (writer, "%d 0 obj\n", pages_number);
    pdf_printf (writer, "<<\n");
    pdf_printf (writer, "/Type /Pages\n");
    pdf_printf (writer, "/Kids [");
    for (i = 0; i < book_get_n_pages (book); i++) {
        pdf_printf (writer, " %d 0 R", pages_number + 1 + (i*3));
    }
    pdf_printf (writer, " ]\n");
    pdf_printf (writer, "/Count %d\n", book_get_n_pages (book));
    pdf_printf (writer, ">>\n");
    pdf_printf (writer, "endobj\n");

    for (i = 0; i < book_get_n_pages (book); i++) {
        int number, width, height, depth;
        size_t data_length, compressed_length;
        Page *page;
        GdkPixbuf *image;
        guchar *pixels, *data, *compressed_data;
        gchar *command, width_buffer[G_ASCII_DTOSTR_BUF_SIZE], height_buffer[G_ASCII_DTOSTR_BUF_SIZE];
        const gchar *color_space, *filter = NULL;
        float page_width, page_height;

        page = book_get_page (book, i);
        image = page_get_image (page, TRUE);
        width = gdk_pixbuf_get_width (image);
        height = gdk_pixbuf_get_height (image);
        pixels = gdk_pixbuf_get_pixels (image);
        page_width = width * 72. / page_get_dpi (page);
        page_height = height * 72. / page_get_dpi (page);

        if (page_is_color (page)) {
            int row;

            depth = 8;
            color_space = "DeviceRGB";
            data_length = height * width * 3 + 1;
            data = g_malloc (sizeof (guchar) * data_length);
            for (row = 0; row < height; row++) {
                int x;
                guchar *in_line, *out_line;

                in_line = pixels + row * gdk_pixbuf_get_rowstride (image);
                out_line = data + row * width * 3;
                for (x = 0; x < width; x++) {
                    guchar *in_p = in_line + x*3;
                    guchar *out_p = out_line + x*3;

                    out_p[0] = in_p[0];
                    out_p[1] = in_p[1];
                    out_p[2] = in_p[2];
                }
            }
        }
        else if (page_get_depth (page) == 2) {
            int row, shift_count = 6;
            guchar *write_ptr;

            depth = 2;
            color_space = "DeviceGray";
            data_length = height * ((width * 2 + 7) / 8);
            data = g_malloc (sizeof (guchar) * data_length);
            write_ptr = data;
            write_ptr[0] = 0;
            for (row = 0; row < height; row++) {
                int x;
                guchar *in_line;

                /* Pad to the next line */
                if (shift_count != 6) {
                    write_ptr++;
                    write_ptr[0] = 0;                   
                    shift_count = 6;
                }

                in_line = pixels + row * gdk_pixbuf_get_rowstride (image);
                for (x = 0; x < width; x++) {
                    guchar *in_p = in_line + x*3;
                    if (in_p[0] >= 192)
                        write_ptr[0] |= 3 << shift_count;
                    else if (in_p[0] >= 128)
                        write_ptr[0] |= 2 << shift_count;
                    else if (in_p[0] >= 64)
                        write_ptr[0] |= 1 << shift_count;
                    if (shift_count == 0) {
                        write_ptr++;
                        write_ptr[0] = 0;
                        shift_count = 6;
                    }
                    else
                        shift_count -= 2;
                }
            }
        }
        else if (page_get_depth (page) == 1) {
            int row, mask = 0x80;
            guchar *write_ptr;

            depth = 1;
            color_space = "DeviceGray";
            data_length = height * ((width + 7) / 8);
            data = g_malloc (sizeof (guchar) * data_length);
            write_ptr = data;
            write_ptr[0] = 0;
            for (row = 0; row < height; row++) {
                int x;
                guchar *in_line;

                /* Pad to the next line */
                if (mask != 0x80) {
                    write_ptr++;
                    write_ptr[0] = 0;
                    mask = 0x80;
                }

                in_line = pixels + row * gdk_pixbuf_get_rowstride (image);
                for (x = 0; x < width; x++) {
                    guchar *in_p = in_line + x*3;
                    if (in_p[0] != 0)
                        write_ptr[0] |= mask;
                    mask >>= 1;
                    if (mask == 0) {
                        write_ptr++;
                        write_ptr[0] = 0;
                        mask = 0x80;
                    }
                }
            }
        }
        else {
            int row;

            depth = 8;
            color_space = "DeviceGray";
            data_length = height * width + 1;
            data = g_malloc (sizeof (guchar) * data_length);
            for (row = 0; row < height; row++) {
                int x;
                guchar *in_line, *out_line;

                in_line = pixels + row * gdk_pixbuf_get_rowstride (image);
                out_line = data + row * width;
                for (x = 0; x < width; x++) {
                    guchar *in_p = in_line + x*3;
                    guchar *out_p = out_line + x;

                    out_p[0] = in_p[0];
                }
            }
        }

        /* Compress data */
        compressed_data = compress_zlib (data, data_length, &compressed_length);
        if (compressed_data) {
            /* Try if JPEG compression is better */
            if (depth > 1) {
                guchar *jpeg_data;
                size_t jpeg_length;

                jpeg_data = compress_jpeg (image, &jpeg_length);
                if (jpeg_length < compressed_length) {
                    filter = "DCTDecode";
                    g_free (data);
                    g_free (compressed_data);
                    data = jpeg_data;
                    data_length = jpeg_length;
                }
            }

            if (!filter) {
                filter = "FlateDecode";
                g_free (data);
                data = compressed_data;
                data_length = compressed_length;
            }
        }

        /* Page */
        pdf_printf (writer, "\n");
        number = pdf_start_object (writer);
        pdf_printf (writer, "%d 0 obj\n", number);
        pdf_printf (writer, "<<\n");
        pdf_printf (writer, "/Type /Page\n");
        pdf_printf (writer, "/Parent %d 0 R\n", pages_number);
        pdf_printf (writer, "/Resources << /XObject << /Im%d %d 0 R >> >>\n", i, number+1);
        pdf_printf (writer, "/MediaBox [ 0 0 %s %s ]\n",
                    g_ascii_formatd (width_buffer, sizeof (width_buffer), "%.2f", page_width),
                    g_ascii_formatd (height_buffer, sizeof (height_buffer), "%.2f", page_height));
        pdf_printf (writer, "/Contents %d 0 R\n", number+2);
        pdf_printf (writer, ">>\n");
        pdf_printf (writer, "endobj\n");

        /* Page image */
        pdf_printf (writer, "\n");
        number = pdf_start_object (writer);
        pdf_printf (writer, "%d 0 obj\n", number);
        pdf_printf (writer, "<<\n");
        pdf_printf (writer, "/Type /XObject\n");
        pdf_printf (writer, "/Subtype /Image\n");
        pdf_printf (writer, "/Width %d\n", width);
        pdf_printf (writer, "/Height %d\n", height);
        pdf_printf (writer, "/ColorSpace /%s\n", color_space);
        pdf_printf (writer, "/BitsPerComponent %d\n", depth);
        pdf_printf (writer, "/Length %d\n", data_length);
        if (filter)
          pdf_printf (writer, "/Filter /%s\n", filter);
        pdf_printf (writer, ">>\n");
        pdf_printf (writer, "stream\n");
        pdf_write (writer, data, data_length);
        g_free (data);
        pdf_printf (writer, "\n");
        pdf_printf (writer, "endstream\n");
        pdf_printf (writer, "endobj\n");      

        /* Page contents */
        command = g_strdup_printf ("q\n"
                                   "%s 0 0 %s 0 0 cm\n"
                                   "/Im%d Do\n"
                                   "Q",
                                   g_ascii_formatd (width_buffer, sizeof (width_buffer), "%f", page_width),
                                   g_ascii_formatd (height_buffer, sizeof (height_buffer), "%f", page_height),
                                   i);
        pdf_printf (writer, "\n");
        number = pdf_start_object (writer);
        pdf_printf (writer, "%d 0 obj\n", number);
        pdf_printf (writer, "<<\n");
        pdf_printf (writer, "/Length %d\n", strlen (command) + 1);
        pdf_printf (writer, ">>\n");
        pdf_printf (writer, "stream\n");
        pdf_write (writer, (unsigned char *)command, strlen (command));
        pdf_printf (writer, "\n");
        pdf_printf (writer, "endstream\n");
        pdf_printf (writer, "endobj\n");
        g_free (command);
                  
        g_object_unref (image);
    }
  
    /* Info */
    pdf_printf (writer, "\n");
    info_number = pdf_start_object (writer);
    pdf_printf (writer, "%d 0 obj\n", info_number);
    pdf_printf (writer, "<<\n");
    pdf_printf (writer, "/Creator (Simple Scan " VERSION ")\n");
    pdf_printf (writer, ">>\n");
    pdf_printf (writer, "endobj\n");

    /* Cross-reference table */
    xref_offset = writer->offset;
    pdf_printf (writer, "xref\n");
    pdf_printf (writer, "1 %d\n", writer->n_objects);
    GList *link;
    for (link = writer->object_offsets; link != NULL; link = link->next) {
        int offset = GPOINTER_TO_INT (link->data);
        pdf_printf (writer, "%010d 0000 n\n", offset);
    }

    /* Trailer */
    pdf_printf (writer, "trailer\n");
    pdf_printf (writer, "<<\n");
    pdf_printf (writer, "/Size %d\n", writer->n_objects);
    pdf_printf (writer, "/Info %d 0 R\n", info_number);
    pdf_printf (writer, "/Root %d 0 R\n", catalog_number);
    pdf_printf (writer, ">>\n");
    pdf_printf (writer, "startxref\n");
    pdf_printf (writer, "%d\n", xref_offset);
    pdf_printf (writer, "%%%%EOF\n");
  
    pdf_writer_free (writer);

    return TRUE;
}


gboolean
book_save (Book *book, const gchar *type, GFile *file, GError **error)
{
    gboolean result = FALSE;

    if (strcmp (type, "jpeg") == 0)
        result = book_save_multi_file (book, "jpeg", file, error);
    else if (strcmp (type, "png") == 0)
        result = book_save_multi_file (book, "png", file, error);
    else if (strcmp (type, "tiff") == 0)
        result = book_save_multi_file (book, "tiff", file, error);    
    else if (strcmp (type, "ps") == 0)
        result = book_save_ps (book, file, error);    
    else if (strcmp (type, "pdf") == 0)
        result = book_save_pdf (book, file, error);

    return result;
}


void
book_set_needs_saving (Book *book, gboolean needs_saving)
{
    gboolean needed_saving = book->priv->needs_saving;
    book->priv->needs_saving = needs_saving;
    if (needed_saving != needs_saving)
        g_object_notify (G_OBJECT (book), "needs-saving");
}


gboolean
book_get_needs_saving (Book *book)
{
    return book->priv->needs_saving;
}


static void
book_set_property (GObject      *object,
                   guint         prop_id,
                   const GValue *value,
                   GParamSpec   *pspec)
{
    Book *self;

    self = BOOK (object);

    switch (prop_id) {
    case PROP_NEEDS_SAVING:
        book_set_needs_saving (self, g_value_get_boolean (value));
        break;
    default:
        G_OBJECT_WARN_INVALID_PROPERTY_ID (object, prop_id, pspec);
        break;
    }
}


static void
book_get_property (GObject    *object,
                   guint       prop_id,
                   GValue     *value,
                   GParamSpec *pspec)
{
    Book *self;

    self = BOOK (object);

    switch (prop_id) {
    case PROP_NEEDS_SAVING:
        g_value_set_boolean (value, book_get_needs_saving (self));
        break;
    default:
        G_OBJECT_WARN_INVALID_PROPERTY_ID (object, prop_id, pspec);
        break;
    }
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

    object_class->get_property = book_get_property;
    object_class->set_property = book_set_property;
    object_class->finalize = book_finalize;

    g_object_class_install_property (object_class,
                                     PROP_NEEDS_SAVING,
                                     g_param_spec_boolean ("needs-saving",
                                                           "needs-saving",
                                                           "TRUE if this book needs saving",
                                                           FALSE,
                                                           G_PARAM_READWRITE));

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
    signals[REORDERED] =
        g_signal_new ("reordered",
                      G_TYPE_FROM_CLASS (klass),
                      G_SIGNAL_RUN_LAST,
                      G_STRUCT_OFFSET (BookClass, reordered),
                      NULL, NULL,
                      g_cclosure_marshal_VOID__VOID,
                      G_TYPE_NONE, 0);
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
