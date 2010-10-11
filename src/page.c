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
    PIXELS_CHANGED,
    SIZE_CHANGED,
    SCAN_LINE_CHANGED,
    SCAN_DIRECTION_CHANGED,
    CROP_CHANGED,
    LAST_SIGNAL
};
static guint signals[LAST_SIGNAL] = { 0, };

struct PagePrivate
{
    /* Resolution of page */
    gint dpi;

    /* Number of rows in this page or -1 if currently unknown */
    gint expected_rows;

    /* Bit depth */
    gint depth;

    /* Color profile */
    gchar *color_profile;

    /* Scanned image data */
    gint width, n_rows, rowstride, n_channels;
    guchar *pixels;

    /* Page is getting data */
    gboolean scanning;

    /* TRUE if have some page data */
    gboolean has_data;

    /* Expected next scan row */
    gint scan_line;

    /* Rotation of scanned data */
    ScanDirection scan_direction;

    /* Crop */
    gboolean has_crop;
    gchar *crop_name;
    gint crop_x, crop_y, crop_width, crop_height;
};

G_DEFINE_TYPE (Page, page, G_TYPE_OBJECT);


Page *
page_new (gint width, gint height, gint dpi, ScanDirection scan_direction)
{
    Page *page;
  
    page = g_object_new (PAGE_TYPE, NULL);
    if (scan_direction == TOP_TO_BOTTOM || scan_direction == BOTTOM_TO_TOP) {
        page->priv->width = width;
        page->priv->n_rows = height;
    }
    else {
        page->priv->width = height;
        page->priv->n_rows = width;
    }
    page->priv->dpi = dpi;
    page->priv->scan_direction = scan_direction;

    return page;
}


void
page_set_page_info (Page *page, ScanPageInfo *info)
{
    g_return_if_fail (page != NULL);

    page->priv->expected_rows = info->height;
    page->priv->dpi = info->dpi;

    /* Create a white page */
    page->priv->width = info->width;
    page->priv->n_rows = info->height;
    /* Variable height, try 50% of the width for now */
    if (page->priv->n_rows < 0)
        page->priv->n_rows = page->priv->width / 2;
    page->priv->depth = info->depth;
    page->priv->n_channels = info->n_channels;
    page->priv->rowstride = (page->priv->width * page->priv->depth * page->priv->n_channels + 7) / 8;
    page->priv->pixels = g_realloc (page->priv->pixels, page->priv->n_rows * page->priv->rowstride);
    g_return_if_fail (page->priv->pixels != NULL);

    /* Fill with white */
    if (page->priv->depth == 1)
        memset (page->priv->pixels, 0x00, page->priv->n_rows * page->priv->rowstride);
    else
        memset (page->priv->pixels, 0xFF, page->priv->n_rows * page->priv->rowstride);

    g_signal_emit (page, signals[SIZE_CHANGED], 0);
    g_signal_emit (page, signals[PIXELS_CHANGED], 0);
}


void
page_start (Page *page)
{
    g_return_if_fail (page != NULL);

    page->priv->scanning = TRUE;
    g_signal_emit (page, signals[SCAN_LINE_CHANGED], 0);
}


gboolean
page_is_scanning (Page *page)
{
    g_return_val_if_fail (page != NULL, FALSE);
  
    return page->priv->scanning;
}


gboolean
page_has_data (Page *page)
{
    g_return_val_if_fail (page != NULL, FALSE);
    return page->priv->has_data;
}


gboolean
page_is_color (Page *page)
{
    g_return_val_if_fail (page != NULL, FALSE);
    return page->priv->n_channels > 1;
}


gint
page_get_scan_line (Page *page)
{
    g_return_val_if_fail (page != NULL, -1);
    return page->priv->scan_line;
}


static void
parse_line (Page *page, ScanLine *line, gint n, gboolean *size_changed)
{
    gint line_number;

    line_number = line->number + n;

    /* Extend image if necessary */
    while (line_number >= page_get_scan_height (page)) {
        gint rows;

        /* Extend image */
        rows = page->priv->n_rows;
        page->priv->n_rows = rows + page->priv->width / 2;
        g_debug("Extending image from %d lines to %d lines", rows, page->priv->n_rows);
        page->priv->pixels = g_realloc (page->priv->pixels, page->priv->n_rows * page->priv->rowstride);

        *size_changed = TRUE;
    }

    /* Copy in new row */
    memcpy (page->priv->pixels + line_number * page->priv->rowstride, line->data + n * line->data_length, line->data_length);

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
    g_signal_emit (page, signals[PIXELS_CHANGED], 0);
}


void
page_finish (Page *page)
{
    gboolean size_changed = FALSE;

    g_return_if_fail (page != NULL);

    /* Trim page */
    if (page->priv->expected_rows < 0 &&
        page->priv->scan_line != page_get_scan_height (page)) {
        gint rows;

        rows = page->priv->n_rows;
        page->priv->n_rows = page->priv->scan_line;
        page->priv->pixels = g_realloc (page->priv->pixels, page->priv->n_rows * page->priv->rowstride);
        g_debug("Trimming page from %d lines to %d lines", rows, page->priv->n_rows);

        size_changed = TRUE;
    }
    page->priv->scanning = FALSE;

    if (size_changed)
        g_signal_emit (page, signals[SIZE_CHANGED], 0);
    g_signal_emit (page, signals[SCAN_LINE_CHANGED], 0);
}


ScanDirection
page_get_scan_direction (Page *page)
{
    g_return_val_if_fail (page != NULL, TOP_TO_BOTTOM);

    return page->priv->scan_direction;
}


static void
page_set_scan_direction (Page *page, ScanDirection scan_direction)
{
    gint left_steps, t;
    gboolean size_changed = FALSE;
    gint width, height;

    g_return_if_fail (page != NULL);

    if (page->priv->scan_direction == scan_direction)
        return;

    /* Work out how many times it has been rotated to the left */
    left_steps = scan_direction - page->priv->scan_direction;
    if (left_steps < 0)
        left_steps += 4;
    if (left_steps != 2)
        size_changed = TRUE;
  
    width = page_get_width (page);
    height = page_get_height (page);

    /* Rotate crop */
    if (page->priv->has_crop) {
        switch (left_steps) {
        /* 90 degrees counter-clockwise */
        case 1:
            t = page->priv->crop_x;
            page->priv->crop_x = page->priv->crop_y;
            page->priv->crop_y = width - (t + page->priv->crop_width);
            t = page->priv->crop_width;
            page->priv->crop_width = page->priv->crop_height;
            page->priv->crop_height = t;
            break;
        /* 180 degrees */
        case 2:
            page->priv->crop_x = width - (page->priv->crop_x + page->priv->crop_width);
            page->priv->crop_y = width - (page->priv->crop_y + page->priv->crop_height);
            break;
        /* 90 degrees clockwise */
        case 3:
            t = page->priv->crop_y;
            page->priv->crop_y = page->priv->crop_x;
            page->priv->crop_x = height - (t + page->priv->crop_height);
            t = page->priv->crop_width;
            page->priv->crop_width = page->priv->crop_height;
            page->priv->crop_height = t;
            break;
        }
    }

    page->priv->scan_direction = scan_direction;
    if (size_changed)
        g_signal_emit (page, signals[SIZE_CHANGED], 0);
    g_signal_emit (page, signals[SCAN_DIRECTION_CHANGED], 0);
    if (page->priv->has_crop)
        g_signal_emit (page, signals[CROP_CHANGED], 0);
}


void
page_rotate_left (Page *page)
{
    ScanDirection scan_direction;

    g_return_if_fail (page != NULL);

    scan_direction = page_get_scan_direction (page);
    if (scan_direction == RIGHT_TO_LEFT)
        scan_direction = TOP_TO_BOTTOM;
    else
        scan_direction++;
    page_set_scan_direction (page, scan_direction);
}


void
page_rotate_right (Page *page)
{
    ScanDirection scan_direction;

    scan_direction = page_get_scan_direction (page);
    if (scan_direction == TOP_TO_BOTTOM)
        scan_direction = RIGHT_TO_LEFT;
    else
        scan_direction--;
    page_set_scan_direction (page, scan_direction);
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

    if (page->priv->scan_direction == TOP_TO_BOTTOM || page->priv->scan_direction == BOTTOM_TO_TOP)
        return page->priv->width;
    else
        return page->priv->n_rows;
}


gint
page_get_height (Page *page)
{
    g_return_val_if_fail (page != NULL, 0);

    if (page->priv->scan_direction == TOP_TO_BOTTOM || page->priv->scan_direction == BOTTOM_TO_TOP)
        return page->priv->n_rows;
    else
        return page->priv->width;
}


gint
page_get_depth (Page *page)
{
    g_return_val_if_fail (page != NULL, 0);
    return page->priv->depth;
}


gint page_get_n_channels (Page *page)
{
    g_return_val_if_fail (page != NULL, 0);
    return page->priv->n_channels;
}


gint page_get_rowstride (Page *page)
{
    g_return_val_if_fail (page != NULL, 0);
    return page->priv->rowstride;
}


gint
page_get_scan_width (Page *page)
{
    g_return_val_if_fail (page != NULL, 0);

    return page->priv->width;
}


gint
page_get_scan_height (Page *page)
{
    g_return_val_if_fail (page != NULL, 0);

    return page->priv->n_rows;
}


void page_set_color_profile (Page *page, const gchar *color_profile)
{
     g_free (page->priv->color_profile);
     page->priv->color_profile = g_strdup (color_profile);
}


const gchar *page_get_color_profile (Page *page)
{
     return page->priv->color_profile;
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


const guchar *
page_get_pixels (Page *page)
{
    g_return_val_if_fail (page != NULL, NULL);
    return page->priv->pixels;
}


// FIXME: Copied from page-view, should be shared code
static guchar
get_sample (const guchar *line, gint x, gint depth, gint n_channels, gint channel)
{
    // FIXME
    return 0xFF;
}


// FIXME: Copied from page-view, should be shared code
static void
get_pixel (Page *page, gint x, gint y, guchar *pixel)
{
    gint t, depth, n_channels;
    const guchar *p, *line;

    switch (page_get_scan_direction (page))
    {
    case TOP_TO_BOTTOM:
        break;
    case BOTTOM_TO_TOP:
        x = page_get_scan_width (page) - x - 1;
        y = page_get_scan_height (page) - y - 1;
        break;
    case LEFT_TO_RIGHT:
        t = x;
        x = page_get_scan_width (page) - y - 1;
        y = t;
        break;
    case RIGHT_TO_LEFT:
        t = x;
        x = y;
        y = page_get_scan_height (page) - t - 1;
        break;
    }

    depth = page_get_depth (page);
    n_channels = page_get_n_channels (page);
    line = page_get_pixels (page) + page_get_rowstride (page) * y;

    /* Optimise for 8 bit images */
    if (depth == 8 && n_channels == 3) {
        p = line + x * n_channels;
        pixel[0] = p[0];
        pixel[1] = p[1];
        pixel[2] = p[2];
        return;
    }
    else if (depth == 8 && n_channels == 1) {
        p = line + x;
        pixel[0] = pixel[1] = pixel[2] = p[0];
        return;
    }

    /* Optimise for bitmaps */
    else if (depth == 1 && n_channels == 1) {
        p = line + (x / 8);
        pixel[0] = pixel[1] = pixel[2] = p[0] & (0x80 >> (x % 8)) ? 0x00 : 0xFF;
        return;
    }

    /* Optimise for 2 bit images */
    else if (depth == 2 && n_channels == 1) {
        gint sample;
        gint block_shift[4] = { 6, 4, 2, 0 };

        p = line + (x / 4);
        sample = (p[0] >> block_shift[x % 4]) & 0x3;
        sample = sample * 255 / 3;

        pixel[0] = pixel[1] = pixel[2] = sample;
        return;
    }

    /* Use slow method */
    pixel[0] = get_sample (line, x, depth, n_channels, 0);
    pixel[0] = get_sample (line, x, depth, n_channels, 1);
    pixel[0] = get_sample (line, x, depth, n_channels, 2);
}


GdkPixbuf *
page_get_image (Page *page, gboolean apply_crop)
{
    GdkPixbuf *image;
    gint x, y, l, r, t, b;

    if (apply_crop && page->priv->has_crop) {
        l = page->priv->crop_x;
        r = l + page->priv->crop_width;
        t = page->priv->crop_y;
        b = l + page->priv->crop_height;
      
        if (l < 0)
            l = 0;
        if (r > page_get_width (page))
            r = page_get_width (page);
        if (t < 0)
            t = 0;
        if (b > page_get_height (page))
            b = page_get_height (page);
    }
    else {
        l = 0;
        r = page_get_width (page);
        t = 0;
        b = page_get_height (page);
    }

    image = gdk_pixbuf_new (GDK_COLORSPACE_RGB, FALSE, 8, r - l, b - t);

    for (y = t; y < b; y++) {
        guchar *line = gdk_pixbuf_get_pixels (image) + gdk_pixbuf_get_rowstride (image) * (y - t);
        for (x = l; x < r; x++) {
            guchar *pixel;

            pixel = line + (x - l) * 3;
            get_pixel (page, x, y, pixel);
        }
    }

    return image;
}


static gboolean
write_pixbuf_data (const gchar *buf, gsize count, GError **error, GFileOutputStream *stream)
{
    return g_output_stream_write_all (G_OUTPUT_STREAM (stream), buf, count, NULL, NULL, error);
}


static gchar *
get_icc_data_encoded (const gchar *icc_profile_filename)
{
    gchar *contents = NULL;
    gchar *contents_encode = NULL;
    gsize length;
    gboolean ret;
    GError *error = NULL;

    /* Get binary data */
    ret = g_file_get_contents (icc_profile_filename, &contents, &length, &error);
    if (!ret) {
        g_warning ("failed to get icc profile data: %s", error->message);
        g_error_free (error);
    }
    else {
        /* Encode into base64 */
        contents_encode = g_base64_encode ((const guchar *) contents, length);
    }
  
    g_free (contents);
    return contents_encode;
}


gboolean
page_save (Page *page, const gchar *type, GFile *file, GError **error)
{
    GFileOutputStream *stream;
    GdkPixbuf *image;
    gboolean result = FALSE;
    gchar *icc_profile_data = NULL;

    stream = g_file_replace (file, NULL, FALSE, G_FILE_CREATE_NONE, NULL, error);
    if (!stream)
        return FALSE;

    image = page_get_image (page, TRUE);

    if (page->priv->color_profile != NULL)
        icc_profile_data = get_icc_data_encoded (page->priv->color_profile);

    if (strcmp (type, "jpeg") == 0) {
        /* ICC profile is awaiting review in gtk2+ bugzilla */
        gchar *keys[] = { "quality", /* "icc-profile", */ NULL };
        gchar *values[] = { "90", /* icc_profile_data, */ NULL };
        result = gdk_pixbuf_save_to_callbackv (image,
                                               (GdkPixbufSaveFunc) write_pixbuf_data, stream,
                                               "jpeg", keys, values, error);
    }
    else if (strcmp (type, "png") == 0) {
        gchar *keys[] = { "icc-profile", NULL };
        gchar *values[] = { icc_profile_data, NULL };
        if (icc_profile_data == NULL)
            keys[0] = NULL;
        result = gdk_pixbuf_save_to_callbackv (image,
                                               (GdkPixbufSaveFunc) write_pixbuf_data, stream,
                                               "png", keys, values, error);
    }
    else if (strcmp (type, "tiff") == 0) {
        gchar *keys[] = { "compression", "icc-profile", NULL };
        gchar *values[] = { "8" /* Deflate compression */, icc_profile_data, NULL };
        if (icc_profile_data == NULL)
            keys[1] = NULL;
        result = gdk_pixbuf_save_to_callbackv (image,
                                               (GdkPixbufSaveFunc) write_pixbuf_data, stream,
                                               "tiff", keys, values, error);
    }
    else
        result = FALSE; // FIXME: Set GError

    g_free (icc_profile_data);
    g_object_unref (image);
    g_object_unref (stream);

    return result;
}


static void
page_finalize (GObject *object)
{
    Page *page = PAGE (object);
    g_free (page->priv->pixels);
    G_OBJECT_CLASS (page_parent_class)->finalize (object);
}


static void
page_class_init (PageClass *klass)
{
    GObjectClass *object_class = G_OBJECT_CLASS (klass);

    object_class->finalize = page_finalize;

    signals[PIXELS_CHANGED] =
        g_signal_new ("pixels-changed",
                      G_TYPE_FROM_CLASS (klass),
                      G_SIGNAL_RUN_LAST,
                      G_STRUCT_OFFSET (PageClass, pixels_changed),
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
    signals[SCAN_DIRECTION_CHANGED] =
        g_signal_new ("scan-direction-changed",
                      G_TYPE_FROM_CLASS (klass),
                      G_SIGNAL_RUN_LAST,
                      G_STRUCT_OFFSET (PageClass, scan_direction_changed),
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
    page->priv->scan_direction = TOP_TO_BOTTOM;
}
