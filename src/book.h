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

#ifndef _BOOK_H_
#define _BOOK_H_

#include <glib-object.h>
#include <cairo.h>
#include "page.h"

G_BEGIN_DECLS

#define BOOK_TYPE  (book_get_type ())
#define BOOK(obj)  (G_TYPE_CHECK_INSTANCE_CAST ((obj), BOOK_TYPE, Book))


typedef struct BookPrivate BookPrivate;

typedef struct
{
    GObject      parent_instance;
    BookPrivate *priv;
} Book;

typedef struct
{
    GObjectClass parent_class;

    void (*page_added) (Book *book, Page *page);
    void (*page_removed) (Book *book, Page *page);
    void (*cleared) (Book *book);
} BookClass;


GType book_get_type (void);

Book *book_new (void);

void book_clear (Book *book);

Page *book_append_page (Book *book, gint width, gint height, gint dpi, Orientation orientation);

void book_delete_page (Book *book, Page *page);

gint book_get_n_pages (Book *book);

Page *book_get_page (Book *book, gint page_number);

gboolean book_save_jpeg (Book *book, GFileOutputStream *stream, GError **error);

gboolean book_save_png (Book *book, GFileOutputStream *stream, GError **error);

gboolean book_save_ps (Book *book, GFileOutputStream *stream, GError **error);

gboolean book_save_pdf (Book *book, GFileOutputStream *stream, GError **error);

#endif /* _BOOK_H_ */
