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

#include "book-view.h"


typedef struct
{
    Page *page;
    gint width, height;
    GdkPixbuf *image;
    gboolean update_image;
} PageView;


enum {
    REDRAW,
    LAST_SIGNAL
};
static guint signals[LAST_SIGNAL] = { 0, };

struct BookViewPrivate
{
    Book *book;
    GHashTable *page_data;

    gint width, height;
    gint x_offset, y_offset;
    gdouble zoom;
    gint selected_page;
};

G_DEFINE_TYPE (BookView, book_view, G_TYPE_OBJECT);


BookView *
book_view_new ()
{
    return g_object_new (BOOK_VIEW_TYPE, NULL);
}


static void
page_updated (Page *page, BookView *view)
{
    PageView *page_view = g_hash_table_lookup (view->priv->page_data, page);
    page_view->update_image = TRUE;
}


static PageView *
page_view_alloc (Page *page)
{
    PageView *view;
    
    view = g_malloc0 (sizeof (PageView));
    view->page = page;
    view->update_image = TRUE;
    
    return view;
}


static void
page_view_free (PageView *view)
{
    if (view->image)
        g_object_unref (view->image);
    g_free (view);
}

static void
page_added (Book *book, Page *page, BookView *view)
{
    g_hash_table_insert (view->priv->page_data, page, page_view_alloc (page));
    g_signal_connect (page, "updated", G_CALLBACK (page_updated), view);
    g_signal_emit (view, signals[REDRAW], 0);
}


static void
page_removed (Book *book, Page *page, BookView *view)
{
    g_hash_table_remove (view->priv->page_data, page);
    g_signal_emit (view, signals[REDRAW], 0);
}


void
book_view_set_book (BookView *view, Book *book)
{
    gint i, n_pages;

    view->priv->book = book;

    /* Load existing pages */
    n_pages = book_get_n_pages (view->priv->book);
    for (i = 0; i < n_pages; i++) {
        Page *page = book_get_page (book, i);
        page_added (book, page, view);
    }

    /* Watch for new pages */
    g_signal_connect (book, "page-added", G_CALLBACK (page_added), view);
    g_signal_connect (book, "page-removed", G_CALLBACK (page_removed), view);
}


void
book_view_resize (BookView *view, gint width, gint height)
{
    view->priv->width = width;
    view->priv->height = height;
}


void
book_view_pan (BookView *view, gint x_offset, gint y_offset)
{
    view->priv->x_offset += x_offset;
    view->priv->y_offset += y_offset;
}


void
book_view_zoom (BookView *view, gdouble zoom)
{
    view->priv->zoom = zoom;    
}


static void
update_page_view (PageView *page)
{
    GdkPixbuf *image;

    if (!page->update_image)
        return;

    if (page->image)
        g_object_unref (page->image);
    image = page_get_image (page->page);
    page->image = gdk_pixbuf_scale_simple (image,
                                           page->width, page->height,
                                           GDK_INTERP_BILINEAR);
    g_object_unref (image);

    page->update_image = FALSE;
}


static void
render_page (BookView *view, PageView *page, cairo_t *context,
             gdouble x, gdouble y, gdouble scale,
             gboolean selected)
{
    gint scan_line;

    /* Regenerate page pixbuf */
    update_page_view (page);

    cairo_save (context);

    /* Draw background */
    cairo_translate (context, x, y);
    cairo_translate (context, 1, 1);
    gdk_cairo_set_source_pixbuf (context, page->image, 0, 0);
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
    cairo_rectangle (context, 0.5, 0.5, gdk_pixbuf_get_width (page->image) + 1, gdk_pixbuf_get_height (page->image) + 1);
    cairo_stroke (context);

    /* Draw scan line */
    scan_line = page_get_scan_line (page->page);
    if (scan_line >= 0) {
        double h = scale * (double) scan_line;

        cairo_set_source_rgb (context, 1.0, 0.0, 0.0);
        cairo_move_to (context, 0, h);
        cairo_line_to (context, gdk_pixbuf_get_width (page->image), h);
        cairo_stroke (context);
    }
    
    cairo_restore (context);
}


static void
page_set_scale (PageView *page, gdouble scale)
{
    gint width, height;

    width = (scale * page_get_width (page->page) + 0.5);
    height = (scale * page_get_height (page->page) + 0.5);

    if (page->width == width &&
        page->height == height)
        return;

    page->width = width;
    page->height = height;
    page->update_image = TRUE;
}


void
book_view_render (BookView *view, cairo_t *context)
{
    gint i, n_pages;
    gdouble max_width = 0, max_height = 0;
    gdouble inner_width, inner_height;
    gdouble max_aspect, inner_aspect;
    gdouble border = 1, spacing = 12;
    gdouble book_width = 0, book_height = 0;
    gdouble x_offset = 0, y_offset = 0, scale;
    gdouble x_range = 0, y_range = 0;

    n_pages = book_get_n_pages (view->priv->book);
    if (n_pages == 0)
        return;

    /* Get area required to fit all pages */
    for (i = 0; i < n_pages; i++) {
        Page *page = book_get_page (view->priv->book, i);
        if (page_get_width (page) > max_width)
            max_width = page_get_width (page);
        if (page_get_height (page) > max_height)
            max_height = page_get_height (page);
    }

    /* Make space for fixed size border */
    inner_width = view->priv->width - 2*border;
    inner_height = view->priv->height - 2*border;

    max_aspect = max_width / max_height;
    inner_aspect = inner_width / inner_height;
    
    /* Scale based on width... */
    if (max_aspect > inner_aspect) {
        scale = inner_width / max_width;
    }
    /* ...or height */
    else {
        scale = inner_height / max_height;
    }
    
    /* Don't scale past exact resolution */
    if (scale >= 1.0)
        scale = 1.0;
    else {
        scale += (1.0 - scale) * view->priv->zoom;
    }
    
    /* Get total dimensions of all pages */
    for (i = 0; i < n_pages; i++) {
        Page *p = book_get_page (view->priv->book, i);
        PageView *page = g_hash_table_lookup (view->priv->page_data, p);
        gdouble h;

        page_set_scale (page, scale);
        update_page_view (page);

        h = page->height + (2 * border);
        if (h > book_height)
            book_height = h;
        book_width += page->width + (2 * border);
        if (i != 0)
            book_width += spacing;
    }
    
    /* Offset so pages are in the middle */
    if (view->priv->width >= book_width) {
        x_offset = (int) ((view->priv->width - book_width) / 2);
        x_range = 0;
    }
    else {
        x_offset = 0;
        x_range = book_width - view->priv->width;
    }

    if (view->priv->height >= book_height) {
        y_offset = (int) ((view->priv->height - book_height) / 2);
        y_range = 0;
    } else {
        y_offset = 0;
        y_range = (int) (book_height - view->priv->height);
    }
    
    if (view->priv->x_offset < -x_range)
        view->priv->x_offset = -x_range;
    if (view->priv->x_offset > 0)
        view->priv->x_offset = 0;
    if (view->priv->y_offset < -y_range)
        view->priv->y_offset = -y_range;
    if (view->priv->y_offset > 0)
        view->priv->y_offset = 0;
    
    //printf("x:0 < %f < %f y:0 < %f < %f\n", x_offset, x_range, y_offset, y_range);
    
    x_offset += view->priv->x_offset;
    y_offset += view->priv->y_offset;
    
    /* Offset so the first page is centered */
    
    /* Can slide between center of first page and last page */

    /* Render each page */
    for (i = 0; i < n_pages; i++) {
        Page *p = book_get_page (view->priv->book, i);
        PageView *page = g_hash_table_lookup (view->priv->page_data, p);
        gdouble y;

        y = y_offset;
        render_page (view, page, context, x_offset, y, scale, FALSE);
        x_offset += page->width + (2 * border) + spacing;
    }
}

static void
book_view_class_init (BookViewClass *klass)
{
    signals[REDRAW] =
        g_signal_new ("redraw",
                      G_TYPE_FROM_CLASS (klass),
                      G_SIGNAL_RUN_LAST,
                      G_STRUCT_OFFSET (BookViewClass, redraw),
                      NULL, NULL,
                      g_cclosure_marshal_VOID__VOID,
                      G_TYPE_NONE, 0);

    g_type_class_add_private (klass, sizeof (BookViewPrivate));
}


static void
book_view_init (BookView *book)
{
    book->priv = G_TYPE_INSTANCE_GET_PRIVATE (book, BOOK_VIEW_TYPE, BookViewPrivate);
    book->priv->page_data = g_hash_table_new_full (g_direct_hash, g_direct_equal,
                                                   NULL, (GDestroyNotify) page_view_free);
    book->priv->selected_page = -1;
}
