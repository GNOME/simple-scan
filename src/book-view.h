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

#include <gtk/gtk.h>
#include <cairo.h>
#include "book.h"

G_BEGIN_DECLS

#define BOOK_VIEW_TYPE  (book_view_get_type ())
#define BOOK_VIEW(obj)  (G_TYPE_CHECK_INSTANCE_CAST ((obj), BOOK_VIEW_TYPE, BookView))


typedef struct BookViewPrivate BookViewPrivate;

typedef struct
{
    GtkVBox parent_instance;
    BookViewPrivate *priv;
} BookView;

typedef struct
{
    GtkVBoxClass parent_class;

    void (*page_selected) (BookView *view, Page *page);
    void (*show_page) (BookView *view, Page *page);
    void (*show_menu) (BookView *view, Page *page);
} BookViewClass;


GType book_view_get_type (void);

BookView *book_view_new (Book *book);

void book_view_redraw (BookView *view);

Book *book_view_get_book (BookView *view);

void book_view_select_page (BookView *view, Page *page);

void book_view_select_next_page (BookView *view);

void book_view_select_prev_page (BookView *view);

Page *book_view_get_selected (BookView *view);

#endif /* _BOOK_VIEW_H_ */
