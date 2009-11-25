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


struct PagePrivate
{
    /* Resolution of page */
    gint dpi;

    /* Number of rows in this page or -1 if currently unknown */
    gint rows;

    /* Scanned image data */
    GdkPixbuf *image;

    /* Last row scanned */
    gint scan_line;

    /* Rotation of scanned data */
    Orientation orientation;

    gint width, height;

    GdkPixbuf *display_image;
    gint display_width, display_height;
    gboolean display_image_changed;
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

    /* Variable height, try 50% of the width for now */
    if (rows < 0)
        h = width / 2;
    else
        h = rows;

    page->priv->rows = rows;
    page->priv->width = width;
    page->priv->height = h;
    page->priv->dpi = dpi;

    /* Fill with white */
    /* NOTE: Pixbuf only supports 8 bit RGB images */
    page->priv->image = gdk_pixbuf_new (GDK_COLORSPACE_RGB, FALSE,
                                        8,
                                        width,
                                        h);
    page->priv->display_image = g_object_ref (page->priv->image);
    memset (gdk_pixbuf_get_pixels (page->priv->image), 0xFF,
            gdk_pixbuf_get_height (page->priv->image) * gdk_pixbuf_get_rowstride (page->priv->image));
    
    /* Regenerate display image */
    page_set_scale (page, 1.0);
}


void
page_start (Page *page)
{
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


void
page_parse_scan_line (Page *page, ScanLine *line)
{
    guchar *pixels;
    gint i, j;

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
    page->priv->display_image_changed = TRUE;
}


void
page_finish (Page *page)
{
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

        page->priv->height = page->priv->scan_line; // FIXME: Doesn't take into account rotation
        page->priv->display_image_changed = TRUE;
    }
    page->priv->scan_line = -1;
}


Orientation
page_get_orientation (Page *page)
{
    return page->priv->orientation;
}


void
page_set_orientation (Page *page, Orientation orientation)
{
    if (page->priv->orientation == orientation)
        return;

    page->priv->orientation = orientation;
    
    if (orientation == TOP_TO_BOTTOM || orientation == LEFT_TO_RIGHT) {
        page->priv->width = gdk_pixbuf_get_width (page->priv->image);
        page->priv->height = gdk_pixbuf_get_height (page->priv->image);
    }
    else {
        page->priv->width = gdk_pixbuf_get_height (page->priv->image);
        page->priv->height = gdk_pixbuf_get_width (page->priv->image);
    }

    page->priv->display_image_changed = TRUE;
}


gint
page_get_dpi (Page *page)
{
    return page->priv->dpi;
}


gint
page_get_width (Page *page)
{
    return page->priv->width;
}


gint
page_get_height (Page *page)
{
    return page->priv->height;
}


GdkPixbuf *
page_get_image (Page *page)
{
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



static void
update_display_image (Page *page)
{
    GdkPixbuf *image;

    if (!page->priv->display_image_changed)
        return;

    g_object_unref (page->priv->display_image);
    image = page_get_image (page);
    page->priv->display_image = gdk_pixbuf_scale_simple (image, 
                                                         page->priv->display_width, page->priv->display_height,
                                                         GDK_INTERP_BILINEAR);
    g_object_unref (image);

    page->priv->display_image_changed = FALSE;
}


void
page_set_scale (Page *page, gdouble scale)
{
    gint width, height;

    width = (scale * page->priv->width + 0.5);
    height = (scale * page->priv->height + 0.5);

    if (page->priv->display_width == width &&
        page->priv->display_height == height)
        return;

    page->priv->display_width = width;
    page->priv->display_height = height;
    page->priv->display_image_changed = TRUE;
}


gint
page_get_display_width (Page *page)
{
    return page->priv->display_width;
}


gint
page_get_display_height (Page *page)
{
    return page->priv->display_height;
}


void
page_render (Page *page, cairo_t *context,
             gdouble x, gdouble y, gdouble scale,
             gboolean selected)
{
    update_display_image (page);

    cairo_save (context);

    /* Draw background */
    cairo_translate (context, x, y);
    cairo_translate (context, 1, 1);
    gdk_cairo_set_source_pixbuf (context, page->priv->display_image, 0, 0);
    cairo_paint (context);
    cairo_translate (context, -1, -1);

    /* Draw page border */
    /* NOTE: Border width and height is rounded up so border is sharp.  Background may not
     * extend to border, should fill with white (?) before drawing scanned image or extend
     * edges slightly */
    if (selected)
        cairo_set_source_rgb (context, 1, 0, 0);
    else
        cairo_set_source_rgb (context, 0, 0, 0);
    cairo_set_line_width (context, 1);
    cairo_rectangle (context, 0.5, 0.5, page->priv->display_width + 1, page->priv->display_height + 1);
    cairo_stroke (context);

    /* Draw scan line */
    if (page->priv->scan_line >= 0) {
        double h = scale * (double) page->priv->scan_line;

        cairo_set_source_rgb (context, 1.0, 0.0, 0.0);
        cairo_move_to (context, 0, h);
        cairo_line_to (context, page->priv->display_width, h);
        cairo_stroke (context);
    }
    
    cairo_restore (context);
}


static void
page_class_init (PageClass *klass)
{
    g_type_class_add_private (klass, sizeof (PagePrivate));
}


static void
page_init (Page *page)
{
    page->priv = G_TYPE_INSTANCE_GET_PRIVATE (page, PAGE_TYPE, PagePrivate);
    page->priv->scan_line = -1;
    page->priv->orientation = TOP_TO_BOTTOM;
}


static void
page_finalize (GObject *object)
{
    Page *page = PAGE (object);
    g_object_unref (page->priv->image);
    g_object_unref (page->priv->display_image);
    G_OBJECT_CLASS (page_parent_class)->finalize (object);
}
