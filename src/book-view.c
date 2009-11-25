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


struct BookViewPrivate
{
    Book *book;

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


void
book_view_set_book (BookView *view, Book *book)
{
    view->priv->book = book;
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
        Page *page = book_get_page (view->priv->book, i);
        gdouble h;

        page_set_scale (page, scale);

        h = page_get_display_height (page) + (2 * border);
        if (h > book_height)
            book_height = h;
        book_width += page_get_display_width (page) + (2 * border);
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
        Page *page = book_get_page (view->priv->book, i);
        gdouble y;

        y = y_offset;
        page_render (page, context, x_offset, y, scale, FALSE);
        x_offset += page_get_display_width (page) + (2 * border) + spacing;
    }
}

static void
book_view_class_init (BookViewClass *klass)
{
    g_type_class_add_private (klass, sizeof (BookViewPrivate));
}


static void
book_view_init (BookView *book)
{
    book->priv = G_TYPE_INSTANCE_GET_PRIVATE (book, BOOK_VIEW_TYPE, BookViewPrivate);
    book->priv->selected_page = -1;
}
