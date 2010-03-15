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
#include "page.h"


enum {
    IMAGE_CHANGED,
    SIZE_CHANGED,
    SCAN_LINE_CHANGED,
    ORIENTATION_CHANGED,
    CROP_CHANGED,
    LAST_SIGNAL
};
static guint signals[LAST_SIGNAL] = { 0, };

struct PagePrivate
{
    /* Resolution of page */
    gint dpi;

    /* Number of rows in this page or -1 if currently unknown */
    gint rows;

    /* Scanned image data */
    GdkPixbuf *image;
  
    /* Page is getting data */
    gboolean scanning;
  
    /* TRUE if have some page data */
    gboolean has_data;

    /* Expected next scan row */
    gint scan_line;

    /* Rotation of scanned data */
    Orientation orientation;
    
    /* Crop */
    gboolean has_crop;
    gchar *crop_name;
    gint crop_x, crop_y, crop_width, crop_height;
};

G_DEFINE_TYPE (Page, page, G_TYPE_OBJECT);


Page *
page_new ()
{
    return g_object_new (PAGE_TYPE, NULL);
}


void
page_set_scan_area (Page *page, gint width, gint rows, gint dpi)
{
    gint height;

    g_return_if_fail (page != NULL);

    /* Variable height, try 50% of the width for now */
    if (rows < 0)
        height = width / 2;
    else
        height = rows;

    /* Rotate page */
    if (page->priv->orientation == LEFT_TO_RIGHT || page->priv->orientation == RIGHT_TO_LEFT) {
        gint t;
        t = width;
        width = height;
        height = t;
    }

    page->priv->rows = rows;
    page->priv->dpi = dpi;

    /* Create a white page */
    /* NOTE: Pixbuf only supports 8 bit RGB images */
    page->priv->image = gdk_pixbuf_new (GDK_COLORSPACE_RGB, FALSE,
                                        8,
                                        width,
                                        height);
    gdk_pixbuf_fill (page->priv->image, 0xFFFFFFFF);
    g_signal_emit (page, signals[SIZE_CHANGED], 0);
    g_signal_emit (page, signals[IMAGE_CHANGED], 0);
}


void
page_start (Page *page)
{
    g_return_if_fail (page != NULL);

    page->priv->scanning = TRUE;
    g_signal_emit (page, signals[SCAN_LINE_CHANGED], 0);
}


gboolean page_is_scanning (Page *page)
{
    g_return_val_if_fail (page != NULL, FALSE);
  
    return page->priv->scanning;
}


static gint
get_sample (guchar *data, gint depth, gint index)
{
    gint i, offset, value, n_bits;

    /* Optimise if using 8 bit samples */
    if (depth == 8)
        return data[index];

    /* Bit offset for this sample */
    offset = depth * index;

    /* Get the remaining bits in the octet this sample starts in */
    i = offset / 8;
    n_bits = 8 - offset % 8;
    value = data[i] & (0xFF >> (8 - n_bits));
    
    /* Add additional octets until get enough bits */
    while (n_bits < depth) {
        value = value << 8 | data[i++];
        n_bits += 8;
    }

    /* Trim remaining bits off */
    if (n_bits > depth)
        value >>= n_bits - depth;

    return value;
}


gboolean page_has_data (Page *page)
{
    g_return_val_if_fail (page != NULL, FALSE);
    return page->priv->has_data;
}


gint page_get_scan_line (Page *page)
{
    g_return_val_if_fail (page != NULL, -1);
    return page->priv->scan_line;
}


static void
set_pixel (ScanLine *line, gint n, gint x, guchar *pixel)
{
    gint sample;
    guchar *data;
  
    data = line->data + line->data_length * n;

    switch (line->format) {
    case LINE_RGB:
        pixel[0] = get_sample (data, line->depth, x*3) * 0xFF / ((1 << line->depth) - 1);
        pixel[1] = get_sample (data, line->depth, x*3+1) * 0xFF / ((1 << line->depth) - 1);
        pixel[2] = get_sample (data, line->depth, x*3+2) * 0xFF / ((1 << line->depth) - 1);
        break;
    case LINE_GRAY:
        /* Bitmap, 0 = white, 1 = black */
        sample = get_sample (data, line->depth, x) * 0xFF / ((1 << line->depth) - 1);
        if (line->depth == 1)
            sample = sample ? 0x00 : 0xFF;

        pixel[0] = pixel[1] = pixel[2] = sample;
        break;
    case LINE_RED:
        pixel[0] = get_sample (data, line->depth, x) * 0xFF / ((1 << line->depth) - 1);
        break;
    case LINE_GREEN:
        pixel[1] = get_sample (data, line->depth, x) * 0xFF / ((1 << line->depth) - 1);
        break;
    case LINE_BLUE:
        pixel[2] = get_sample (data, line->depth, x) * 0xFF / ((1 << line->depth) - 1);
        break;
    }
}


static void
parse_line (Page *page, ScanLine *line, gint n, gboolean *size_changed)
{
    guchar *pixels;
    gint line_number;
    gint i, x = 0, y = 0, x_step = 0, y_step = 0;
    gint rowstride, n_channels;

    line_number = line->number + n;

    /* Extend image if necessary */
    while (line_number >= page_get_scan_height (page)) {
        GdkPixbuf *image;
        gint height, width, new_width, new_height;

        /* Extend image */
        new_width = width = gdk_pixbuf_get_width (page->priv->image);
        new_height = height = gdk_pixbuf_get_height (page->priv->image);
        if (page->priv->orientation == TOP_TO_BOTTOM || page->priv->orientation == BOTTOM_TO_TOP) {
            new_height = height + width / 2;
            g_debug("Extending image height from %d pixels to %d pixels", height, new_height);
        }
        else {
            new_width = width + height / 2;
            g_debug("Extending image width from %d pixels to %d pixels", width, new_width);
        }
        image = gdk_pixbuf_new (GDK_COLORSPACE_RGB, FALSE,
                                8, new_width, new_height);

        /* Copy old data */
        gdk_pixbuf_fill (image, 0xFFFFFFFF);
        if (page->priv->orientation == TOP_TO_BOTTOM || page->priv->orientation == LEFT_TO_RIGHT)
            gdk_pixbuf_copy_area (page->priv->image, 0, 0, width, height,
                                  image, 0, 0);
        else
            gdk_pixbuf_copy_area (page->priv->image, 0, 0, width, height,
                                  image, new_width - width, new_height - height);

        g_object_unref (page->priv->image);
        page->priv->image = image;

        *size_changed = TRUE;
    }
  
    switch (page->priv->orientation) {
    case TOP_TO_BOTTOM:
        x = 0;
        y = line_number;
        x_step = 1;
        y_step = 0;
        break;
    case BOTTOM_TO_TOP:
        x = page_get_width (page) - 1;
        y = page_get_height (page) - line_number - 1;
        x_step = -1;
        y_step = 0;
        break;
    case LEFT_TO_RIGHT:
        x = line_number;
        y = page_get_height (page) - 1;
        x_step = 0;
        y_step = -1;
        break;
    case RIGHT_TO_LEFT:
        x = page_get_width (page) - line_number - 1;
        y = 0;
        x_step = 0;
        y_step = 1;
        break;
    }
    pixels = gdk_pixbuf_get_pixels (page->priv->image);
    rowstride = gdk_pixbuf_get_rowstride (page->priv->image);
    n_channels = gdk_pixbuf_get_n_channels (page->priv->image);
    for (i = 0; i < line->width; i++) {
        guchar *pixel;

        pixel = pixels + y * rowstride + x * n_channels;
        set_pixel (line, n, i, pixel);
        x += x_step;
        y += y_step;
    }

    page->priv->scan_line = line_number;
}


void
page_parse_scan_line (Page *page, ScanLine *line)
{
    gint i;
    gboolean size_changed = FALSE;

    g_return_if_fail (page != NULL);

    for (i = 0; i < line->n_lines; i++)
        parse_line (page, line, i, &size_changed);

    page->priv->has_data = TRUE;

    if (size_changed)
        g_signal_emit (page, signals[SIZE_CHANGED], 0);
    g_signal_emit (page, signals[SCAN_LINE_CHANGED], 0);
    g_signal_emit (page, signals[IMAGE_CHANGED], 0);
}


void
page_finish (Page *page)
{
    gboolean size_changed = FALSE;

    g_return_if_fail (page != NULL);

    /* Trim page */
    if (page->priv->rows < 0 &&
        page->priv->scan_line != gdk_pixbuf_get_height (page->priv->image)) {
        GdkPixbuf *image;
        gint width, height, new_width, new_height;

        new_width = width = gdk_pixbuf_get_width (page->priv->image);
        new_height = height = gdk_pixbuf_get_height (page->priv->image);
        if (page->priv->orientation == TOP_TO_BOTTOM || page->priv->orientation == BOTTOM_TO_TOP) {
            new_height = page->priv->scan_line;
            g_debug("Trimming image height from %d pixels to %d pixels", height, new_height);
        }
        else {
            new_width = page->priv->scan_line;
            g_debug("Trimming image width from %d pixels to %d pixels", width, new_width);          
        }
        image = gdk_pixbuf_new (GDK_COLORSPACE_RGB, FALSE,
                                8,
                                new_width, new_height);

        /* Copy old data */
        if (page->priv->orientation == TOP_TO_BOTTOM || page->priv->orientation == LEFT_TO_RIGHT)
            gdk_pixbuf_copy_area (page->priv->image, 0, 0, width, height,
                                  image, 0, 0);
        else
            gdk_pixbuf_copy_area (page->priv->image, width - new_width, height - new_height, width, height,
                                  image, 0, 0);

        g_object_unref (page->priv->image);
        page->priv->image = image;
        size_changed = TRUE;
    }
    page->priv->scanning = FALSE;

    if (size_changed)
        g_signal_emit (page, signals[SIZE_CHANGED], 0);
    g_signal_emit (page, signals[SCAN_LINE_CHANGED], 0);
}


Orientation
page_get_orientation (Page *page)
{
    g_return_val_if_fail (page != NULL, TOP_TO_BOTTOM);

    return page->priv->orientation;
}


void
page_set_orientation (Page *page, Orientation orientation)
{
    gint left_steps, t;
    GdkPixbuf *image;
    gboolean size_changed = FALSE;

    g_return_if_fail (page != NULL);

    if (page->priv->orientation == orientation)
        return;

    /* Work out how many times it has been rotated to the left */
    left_steps = orientation - page->priv->orientation;
    if (left_steps < 0)
        left_steps += 4;
  
    /* Rotate image */
    if (left_steps == 1)
        image = gdk_pixbuf_rotate_simple (page->priv->image, GDK_PIXBUF_ROTATE_COUNTERCLOCKWISE);
    else if (left_steps == 2)
        image = gdk_pixbuf_rotate_simple (page->priv->image, GDK_PIXBUF_ROTATE_UPSIDEDOWN);
    else if (left_steps == 3)
        image = gdk_pixbuf_rotate_simple (page->priv->image, GDK_PIXBUF_ROTATE_CLOCKWISE);
    else
        image = gdk_pixbuf_rotate_simple (page->priv->image, GDK_PIXBUF_ROTATE_NONE);
    gdk_pixbuf_unref (page->priv->image);
    page->priv->image = image;
    if (left_steps != 2)
        size_changed = TRUE;

    /* Rotate crop */
    if (page->priv->has_crop) {
        switch (left_steps) {
        /* 90 degrees counter-clockwise */
        case 1:
            t = page->priv->crop_x;
            page->priv->crop_x = page->priv->crop_y;
            page->priv->crop_y = page_get_width (page) - (t + page->priv->crop_width);
            t = page->priv->crop_width;
            page->priv->crop_width = page->priv->crop_height;
            page->priv->crop_height = t;
            break;
        /* 180 degrees */
        case 2:
            page->priv->crop_x = page_get_width (page) - (page->priv->crop_x + page->priv->crop_width);
            page->priv->crop_y = page_get_width (page) - (page->priv->crop_y + page->priv->crop_height);
            break;
        /* 90 degrees clockwise */
        case 3:
            t = page->priv->crop_y;
            page->priv->crop_y = page->priv->crop_x;
            page->priv->crop_x = page_get_height (page) - (t + page->priv->crop_height);
            t = page->priv->crop_width;
            page->priv->crop_width = page->priv->crop_height;
            page->priv->crop_height = t;
            break;
        }
    }

    page->priv->orientation = orientation;
    if (size_changed)
        g_signal_emit (page, signals[SIZE_CHANGED], 0);  
    g_signal_emit (page, signals[IMAGE_CHANGED], 0);
    g_signal_emit (page, signals[ORIENTATION_CHANGED], 0);
    g_signal_emit (page, signals[CROP_CHANGED], 0);
}


void
page_rotate_left (Page *page)
{
    Orientation orientation;

    g_return_if_fail (page != NULL);

    orientation = page_get_orientation (page);
    if (orientation == RIGHT_TO_LEFT)
        orientation = TOP_TO_BOTTOM;
    else
        orientation++;
    page_set_orientation (page, orientation);
}


void
page_rotate_right (Page *page)
{
    Orientation orientation;

    orientation = page_get_orientation (page);
    if (orientation == TOP_TO_BOTTOM)
        orientation = RIGHT_TO_LEFT;
    else
        orientation--;
    page_set_orientation (page, orientation);
}


gint
page_get_dpi (Page *page)
{
    g_return_val_if_fail (page != NULL, 0);

    return page->priv->dpi;
}


gboolean
page_is_landscape (Page *page)
{
   return page_get_width (page) > page_get_height (page);
}


gint
page_get_width (Page *page)
{
    g_return_val_if_fail (page != NULL, 0);
    return gdk_pixbuf_get_width (page->priv->image);
}


gint
page_get_height (Page *page)
{
    g_return_val_if_fail (page != NULL, 0);
    return gdk_pixbuf_get_height (page->priv->image);
}


gint
page_get_scan_width (Page *page)
{
    g_return_val_if_fail (page != NULL, 0);

    if (page->priv->orientation == TOP_TO_BOTTOM || page->priv->orientation == BOTTOM_TO_TOP)
        return gdk_pixbuf_get_width (page->priv->image);
    else
        return gdk_pixbuf_get_height (page->priv->image);
}


gint
page_get_scan_height (Page *page)
{
    g_return_val_if_fail (page != NULL, 0);

    if (page->priv->orientation == TOP_TO_BOTTOM || page->priv->orientation == BOTTOM_TO_TOP)
        return gdk_pixbuf_get_height (page->priv->image);
    else
        return gdk_pixbuf_get_width (page->priv->image);  

}


void
page_set_no_crop (Page *page)
{
    g_return_if_fail (page != NULL);

    if (!page->priv->has_crop)
        return;
    page->priv->has_crop = FALSE;
    g_signal_emit (page, signals[CROP_CHANGED], 0);
}


void
page_set_custom_crop (Page *page, gint width, gint height)
{
    //gint pw, ph;

    g_return_if_fail (page != NULL);
    g_return_if_fail (width >= 1);
    g_return_if_fail (height >= 1);
    
    if (!page->priv->crop_name &&
        page->priv->has_crop &&
        page->priv->crop_width == width &&
        page->priv->crop_height == height)
        return;
    g_free (page->priv->crop_name);
    page->priv->crop_name = NULL;
    page->priv->has_crop = TRUE;

    page->priv->crop_width = width;
    page->priv->crop_height = height;

    /*pw = page_get_width (page);
    ph = page_get_height (page);
    if (page->priv->crop_width < pw)
        page->priv->crop_x = (pw - page->priv->crop_width) / 2;
    else
        page->priv->crop_x = 0;
    if (page->priv->crop_height < ph)
        page->priv->crop_y = (ph - page->priv->crop_height) / 2;
    else
        page->priv->crop_y = 0;*/
    
    g_signal_emit (page, signals[CROP_CHANGED], 0);
}


void
page_set_named_crop (Page *page, const gchar *name)
{
    struct {
        const gchar *name;
        /* Width and height in inches */
        gdouble width, height;
    } named_crops[] =
    {
        {"A4", 8.3, 11.7},
        {"A5", 5.8, 8.3},
        {"A6", 4.1, 5.8},
        {"letter", 8.5, 11},
        {"legal", 8.5, 14},
        {"4x6", 4, 6},
        {NULL, 0, 0}
    };
    gint i;
    gint pw, ph;
    double width, height;

    g_return_if_fail (page != NULL);
    
    for (i = 0; named_crops[i].name && strcmp (name, named_crops[i].name) != 0; i++);
    width = named_crops[i].width;
    height = named_crops[i].height;

    if (!named_crops[i].name) {
        g_warning ("Unknown paper size '%s'", name);
        return;
    }

    g_free (page->priv->crop_name);
    page->priv->crop_name = g_strdup (name);
    page->priv->has_crop = TRUE;
    
    pw = page_get_width (page);
    ph = page_get_height (page);
   
    /* Rotate to match original aspect */
    if (pw > ph) {
        double t;
        t = width;
        width = height;
        height = t;
    }

    /* Custom crop, make slightly smaller than original */
    page->priv->crop_width = (int) (width * page->priv->dpi + 0.5);
    page->priv->crop_height = (int) (height * page->priv->dpi + 0.5);
        
    if (page->priv->crop_width < pw)
        page->priv->crop_x = (pw - page->priv->crop_width) / 2;
    else
        page->priv->crop_x = 0;
    if (page->priv->crop_height < ph)
        page->priv->crop_y = (ph - page->priv->crop_height) / 2;
    else
        page->priv->crop_y = 0;
    g_signal_emit (page, signals[CROP_CHANGED], 0);
}


void
page_move_crop (Page *page, gint x, gint y)
{
    g_return_if_fail (x >= 0);
    g_return_if_fail (y >= 0);
    g_return_if_fail (x < page_get_width (page));
    g_return_if_fail (y < page_get_height (page));

    page->priv->crop_x = x;
    page->priv->crop_y = y;
    g_signal_emit (page, signals[CROP_CHANGED], 0);    
}


void
page_rotate_crop (Page *page)
{
    gint t;
    
    g_return_if_fail (page != NULL);
  
    if (!page->priv->has_crop)
        return;

    t = page->priv->crop_width;
    page->priv->crop_width = page->priv->crop_height;
    page->priv->crop_height = t;
  
    /* Clip custom crops */
    if (!page->priv->crop_name) {
        gint w, h;

        w = page_get_width (page);
        h = page_get_height (page);
        
        if (page->priv->crop_x + page->priv->crop_width > w)
            page->priv->crop_x = w - page->priv->crop_width;
        if (page->priv->crop_x < 0) {
            page->priv->crop_x = 0;
            page->priv->crop_width = w;
        }
        if (page->priv->crop_y + page->priv->crop_height > h)
            page->priv->crop_y = h - page->priv->crop_height;
        if (page->priv->crop_y < 0) {
            page->priv->crop_y = 0;
            page->priv->crop_height = h;
        }
    }

    g_signal_emit (page, signals[CROP_CHANGED], 0);
}


gboolean
page_has_crop (Page *page)
{
    g_return_val_if_fail (page != NULL, FALSE);
    return page->priv->has_crop;
}


void
page_get_crop (Page *page, gint *x, gint *y, gint *width, gint *height)
{
    g_return_if_fail (page != NULL);

    if (x)
        *x = page->priv->crop_x;
    if (y)
        *y = page->priv->crop_y;
    if (width)
        *width = page->priv->crop_width;
    if (height)
        *height = page->priv->crop_height;
}


gchar *
page_get_named_crop (Page *page)
{
    g_return_val_if_fail (page != NULL, NULL);

    if (page->priv->crop_name)
        return g_strdup (page->priv->crop_name);
    else
        return NULL;
}


GdkPixbuf *
page_get_image (Page *page)
{
    g_return_val_if_fail (page != NULL, NULL);
    return gdk_pixbuf_copy (page->priv->image);
}


GdkPixbuf *
page_get_cropped_image (Page *page)
{
    GdkPixbuf *image, *cropped_image, *i;
    gint x, y, w, h, pw, ph;

    g_return_val_if_fail (page != NULL, NULL);
    
    image = page_get_image (page);
    
    if (!page->priv->has_crop)
        return image;
    
    x = page->priv->crop_x;
    y = page->priv->crop_y;
    w = page->priv->crop_width;
    h = page->priv->crop_height;
    pw = gdk_pixbuf_get_width (image);
    ph = gdk_pixbuf_get_height (image);
    
    /* Trim crop */
    if (x + w >= pw)
        w = pw - x;
    if (y + h >= ph)
        h = ph - y;
    
    cropped_image = gdk_pixbuf_new_subpixbuf (image, x, y, w, h);
    g_object_unref (image);
    
    i = gdk_pixbuf_copy (cropped_image);
    g_object_unref (cropped_image);

    return i;
}


static GFileOutputStream *
open_file (const gchar *uri, GError **error)
{
    GFile *file;
    GFileOutputStream *stream; 

    file = g_file_new_for_uri (uri);
    stream = g_file_replace (file, NULL, FALSE, G_FILE_CREATE_NONE, NULL, error);
    g_object_unref (file);
    return stream;
}


static gboolean
write_pixbuf_data (const gchar *buf, gsize count, GError **error, GFileOutputStream *stream)
{
    return g_output_stream_write_all (G_OUTPUT_STREAM (stream), buf, count, NULL, NULL, error);
}


gboolean
page_save_jpeg (Page *page, const gchar *uri, GError **error)
{
    GdkPixbuf *image;
    GFileOutputStream *stream;
    gboolean result;
  
    stream = open_file (uri, error);
    if (!stream)
        return FALSE;

    image = page_get_cropped_image (page);
    result = gdk_pixbuf_save_to_callback (image,
                                          (GdkPixbufSaveFunc) write_pixbuf_data, stream,
                                          "jpeg", error,
                                          "quality", "90",
                                          NULL);
    g_object_unref (image);
    g_object_unref (stream);

    return result;
}


gboolean
page_save_png (Page *page, const gchar *uri, GError **error)
{
    GdkPixbuf *image;
    GFileOutputStream *stream;
    gboolean result;
  
    stream = open_file (uri, error);
    if (!stream)
        return FALSE;

    image = page_get_cropped_image (page);
    result = gdk_pixbuf_save_to_callback (image,
                                          (GdkPixbufSaveFunc) write_pixbuf_data, stream,
                                          "png", error,
                                          NULL);
    g_object_unref (image);
    g_object_unref (stream);

    return result;
}


gboolean
page_save_tiff (Page *page, const gchar *uri, GError **error)
{
    GdkPixbuf *image;
    GFileOutputStream *stream;
    gboolean result;
  
    stream = open_file (uri, error);
    if (!stream)
        return FALSE;

    image = page_get_cropped_image (page);
    result = gdk_pixbuf_save_to_callback (image,
                                          (GdkPixbufSaveFunc) write_pixbuf_data, stream,
                                          "tiff", error,
                                          "compression", "8", /* Deflate compression */
                                          NULL);
    g_object_unref (image);
    g_object_unref (stream);

    return result;
}


static void
page_finalize (GObject *object)
{
    Page *page = PAGE (object);
    g_object_unref (page->priv->image);
    page->priv->image = NULL;
    G_OBJECT_CLASS (page_parent_class)->finalize (object);
}


static void
page_class_init (PageClass *klass)
{
    GObjectClass *object_class = G_OBJECT_CLASS (klass);

    object_class->finalize = page_finalize;

    signals[IMAGE_CHANGED] =
        g_signal_new ("image-changed",
                      G_TYPE_FROM_CLASS (klass),
                      G_SIGNAL_RUN_LAST,
                      G_STRUCT_OFFSET (PageClass, image_changed),
                      NULL, NULL,
                      g_cclosure_marshal_VOID__VOID,
                      G_TYPE_NONE, 0);
    signals[SIZE_CHANGED] =
        g_signal_new ("size-changed",
                      G_TYPE_FROM_CLASS (klass),
                      G_SIGNAL_RUN_LAST,
                      G_STRUCT_OFFSET (PageClass, size_changed),
                      NULL, NULL,
                      g_cclosure_marshal_VOID__VOID,
                      G_TYPE_NONE, 0);
    signals[SCAN_LINE_CHANGED] =
        g_signal_new ("scan-line-changed",
                      G_TYPE_FROM_CLASS (klass),
                      G_SIGNAL_RUN_LAST,
                      G_STRUCT_OFFSET (PageClass, scan_line_changed),
                      NULL, NULL,
                      g_cclosure_marshal_VOID__VOID,
                      G_TYPE_NONE, 0);
    signals[ORIENTATION_CHANGED] =
        g_signal_new ("orientation-changed",
                      G_TYPE_FROM_CLASS (klass),
                      G_SIGNAL_RUN_LAST,
                      G_STRUCT_OFFSET (PageClass, orientation_changed),
                      NULL, NULL,
                      g_cclosure_marshal_VOID__VOID,
                      G_TYPE_NONE, 0);
    signals[CROP_CHANGED] =
        g_signal_new ("crop-changed",
                      G_TYPE_FROM_CLASS (klass),
                      G_SIGNAL_RUN_LAST,
                      G_STRUCT_OFFSET (PageClass, crop_changed),
                      NULL, NULL,
                      g_cclosure_marshal_VOID__VOID,
                      G_TYPE_NONE, 0);

    g_type_class_add_private (klass, sizeof (PagePrivate));
}


static void
page_init (Page *page)
{
    page->priv = G_TYPE_INSTANCE_GET_PRIVATE (page, PAGE_TYPE, PagePrivate);
    page->priv->orientation = TOP_TO_BOTTOM;
}
