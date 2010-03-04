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

#ifndef _PAGE_VIEW_H_
#define _PAGE_VIEW_H_

#include <glib-object.h>
#include <gtk/gtk.h>
#include <cairo.h>
#include "page.h"

G_BEGIN_DECLS

#define PAGE_VIEW_TYPE  (page_view_get_type ())
#define PAGE_VIEW(obj)  (G_TYPE_CHECK_INSTANCE_CAST ((obj), PAGE_VIEW_TYPE, PageView))


typedef struct PageViewPrivate PageViewPrivate;

typedef struct
{
    GObject          parent_instance;
    PageViewPrivate *priv;
} PageView;

typedef struct
{
    GObjectClass parent_class;

    void (*changed) (PageView *view);
    void (*size_changed) (PageView *view);
} PageViewClass;


GType page_view_get_type (void);

PageView *page_view_new (void);

//FIXME 
void page_view_set_page (PageView *view, Page *page);

Page *page_view_get_page (PageView *view);

void page_view_set_selected (PageView *view, gboolean selected);

void page_view_set_x_offset (PageView *view, gint offset);

void page_view_set_y_offset (PageView *view, gint offset);

gint page_view_get_x_offset (PageView *view);

gint page_view_get_y_offset (PageView *view);

void page_view_set_width (PageView *view, gint width);

void page_view_set_height (PageView *view, gint height);

gint page_view_get_width (PageView *view);

gint page_view_get_height (PageView *view);

void page_view_button_press (PageView *view, gint x, gint y);

void page_view_motion (PageView *view, gint x, gint y);

void page_view_button_release (PageView *view, gint x, gint y);

gint page_view_get_cursor (PageView *view);

void page_view_render (PageView *view, cairo_t *context);

#endif /* _PAGE_VIEW_H_ */
