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


void page_set_scan_area (Page *page, gint width, gint rows, gint dpi)
{
    gint h;

    g_return_if_fail (page != NULL);

    /* Variable height, try 50% of the width for now */
    if (rows < 0)
        h = width / 2;
    else
        h = rows;

    page->priv->rows = rows;
    page->priv->dpi = dpi;

    /* Create a white page */
    /* NOTE: Pixbuf only supports 8 bit RGB images */
    page->priv->image = gdk_pixbuf_new (GDK_COLORSPACE_RGB, FALSE,
                                        8,
                                        width,
                                        h);
    memset (gdk_pixbuf_get_pixels (page->priv->image), 0xFF,
            gdk_pixbuf_get_height (page->priv->image) * gdk_pixbuf_get_rowstride (page->priv->image));
}


void
page_start (Page *page)
{
    g_return_if_fail (page != NULL);

    page->priv->scan_line = 0;
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


gint page_get_scan_line (Page *page)
{
    g_return_val_if_fail (page != NULL, -1);

    return page->priv->scan_line;
}


void
page_parse_scan_line (Page *page, ScanLine *line)
{
    guchar *pixels;
    gint i, j;

    g_return_if_fail (page != NULL);

    /* Extend image if necessary */
    while (line->number >= gdk_pixbuf_get_height (page->priv->image)) {
        GdkPixbuf *image;
        gint height, width, new_height;

        width = gdk_pixbuf_get_width (page->priv->image);
        height = gdk_pixbuf_get_height (page->priv->image);
        new_height = height + width / 2;
        g_debug("Resizing image height from %d pixels to %d pixels", height, new_height);

        image = gdk_pixbuf_new (GDK_COLORSPACE_RGB, FALSE,
                                8, width, new_height);
        memset (gdk_pixbuf_get_pixels (image), 0xFF,
                gdk_pixbuf_get_height (image) * gdk_pixbuf_get_rowstride (image));
        memcpy (gdk_pixbuf_get_pixels (image),
                gdk_pixbuf_get_pixels (page->priv->image),
                height * gdk_pixbuf_get_rowstride (image));

        g_object_unref (page->priv->image);
        page->priv->image = image;
    }

    pixels = gdk_pixbuf_get_pixels (page->priv->image) + line->number * gdk_pixbuf_get_rowstride (page->priv->image);
    switch (line->format) {
    case LINE_RGB:
        if (line->depth == 8) {
            memcpy (pixels, line->data, line->data_length);
        } else {
            for (i = 0, j = 0; i < line->width; i++) {
                pixels[j] = get_sample (line->data, line->depth, j) * 0xFF / (1 << (line->depth - 1));
                pixels[j+1] = get_sample (line->data, line->depth, j+1) * 0xFF / (1 << (line->depth - 1));
                pixels[j+2] = get_sample (line->data, line->depth, j+2) * 0xFF / (1 << (line->depth - 1));
                j += 3;
            }
        }
        break;
    case LINE_GRAY:
        for (i = 0, j = 0; i < line->width; i++) {
            gint sample;

            /* Bitmap, 0 = white, 1 = black */
            sample = get_sample (line->data, line->depth, i) * 0xFF / (1 << (line->depth - 1));
            if (line->depth == 1)
                sample = sample ? 0x00 : 0xFF;

            pixels[j] = pixels[j+1] = pixels[j+2] = sample;
            j += 3;
        }
        break;
    case LINE_RED:
        for (i = 0, j = 0; i < line->width; i++) {
            pixels[j] = get_sample (line->data, line->depth, i) * 0xFF / (1 << (line->depth - 1));
            j += 3;
        }
        break;
    case LINE_GREEN:
        for (i = 0, j = 0; i < line->width; i++) {
            pixels[j+1] = get_sample (line->data, line->depth, i) * 0xFF / (1 << (line->depth - 1));
            j += 3;
        }
        break;
    case LINE_BLUE:
        for (i = 0, j = 0; i < line->width; i++) {
            pixels[j+2] = get_sample (line->data, line->depth, i) * 0xFF / (1 << (line->depth - 1));
            j += 3;
        }
        break;
    }
    
    page->priv->scan_line = line->number;
    g_signal_emit (page, signals[IMAGE_CHANGED], 0);
}


void
page_finish (Page *page)
{
    g_return_if_fail (page != NULL);

    /* Trim page */
    if (page->priv->rows < 0 &&
        page->priv->scan_line != gdk_pixbuf_get_height (page->priv->image)) {
        GdkPixbuf *image;
        gint height, width;

        width = gdk_pixbuf_get_width (page->priv->image);
        height = gdk_pixbuf_get_height (page->priv->image);
        g_debug("Trimming image height from %d pixels to %d pixels", height, page->priv->scan_line);
    
        image = gdk_pixbuf_new (GDK_COLORSPACE_RGB, FALSE,
                                8,
                                width, page->priv->scan_line);
        memcpy (gdk_pixbuf_get_pixels (image),
                gdk_pixbuf_get_pixels (page->priv->image),
                page->priv->scan_line * gdk_pixbuf_get_rowstride (page->priv->image));

        g_object_unref (page->priv->image);
        page->priv->image = image;
    }
    page->priv->scan_line = -1;

    g_signal_emit (page, signals[IMAGE_CHANGED], 0);
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
    g_return_if_fail (page != NULL);

    if (page->priv->orientation == orientation)
        return;

    page->priv->orientation = orientation;
    g_signal_emit (page, signals[ORIENTATION_CHANGED], 0);
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

    if (page->priv->orientation == TOP_TO_BOTTOM || page->priv->orientation == BOTTOM_TO_TOP)
        return gdk_pixbuf_get_width (page->priv->image);
    else
        return gdk_pixbuf_get_height (page->priv->image);
}


gint
page_get_height (Page *page)
{
    g_return_val_if_fail (page != NULL, 0);

    if (page->priv->orientation == TOP_TO_BOTTOM || page->priv->orientation == BOTTOM_TO_TOP)
        return gdk_pixbuf_get_height (page->priv->image);
    else
        return gdk_pixbuf_get_width (page->priv->image);
}


gint
page_get_scan_width (Page *page)
{
    g_return_val_if_fail (page != NULL, 0);

    return gdk_pixbuf_get_width (page->priv->image);
}


gint
page_get_scan_height (Page *page)
{
    g_return_val_if_fail (page != NULL, 0);

    return gdk_pixbuf_get_height (page->priv->image);
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

    t = page->priv->crop_width;
    page->priv->crop_width = page->priv->crop_height;
    page->priv->crop_height = t;
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

    switch (page->priv->orientation) {
    default:
    case TOP_TO_BOTTOM:
        return gdk_pixbuf_copy (page->priv->image);
    case BOTTOM_TO_TOP:
        return gdk_pixbuf_rotate_simple (page->priv->image, GDK_PIXBUF_ROTATE_UPSIDEDOWN);
    case LEFT_TO_RIGHT:
        return gdk_pixbuf_rotate_simple (page->priv->image, GDK_PIXBUF_ROTATE_COUNTERCLOCKWISE);
    case RIGHT_TO_LEFT:
        return gdk_pixbuf_rotate_simple (page->priv->image, GDK_PIXBUF_ROTATE_CLOCKWISE);
    }
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


static void
page_finalize (GObject *object)
{
    Page *page = PAGE (object);
    g_object_unref (page->priv->image);
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
    page->priv->scan_line = -1;
    page->priv->orientation = TOP_TO_BOTTOM;
}
