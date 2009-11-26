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

#ifndef _BOOK_VIEW_H_
#define _BOOK_VIEW_H_

#include <glib-object.h>
#include <cairo.h>
#include "book.h"

G_BEGIN_DECLS

#define BOOK_VIEW_TYPE  (book_view_get_type ())
#define BOOK_VIEW(obj)  (G_TYPE_CHECK_INSTANCE_CAST ((obj), BOOK_VIEW_TYPE, BookView))


typedef struct BookViewPrivate BookViewPrivate;

typedef struct
{
    GObject          parent_instance;
    BookViewPrivate *priv;
} BookView;

typedef struct
{
    GObjectClass parent_class;

    void (*redraw) (BookView *view);
} BookViewClass;


BookView *book_view_new ();

// FIXME: Should be part of book_view_new
void book_view_set_book (BookView *view, Book *book);

void book_view_resize (BookView *view, gint width, gint height);

void book_view_pan (BookView *view, gint x_offset, gint y_offset);

void book_view_zoom (BookView *view, gdouble zoom);

void book_view_render (BookView *view, cairo_t *context);

#endif /* _BOOK_VIEW_H_ */
