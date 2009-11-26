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

#ifndef _PAGE_H_
#define _PAGE_H_

#include <glib-object.h>
#include <gdk-pixbuf/gdk-pixbuf.h>
#include "scanner.h"

G_BEGIN_DECLS

#define PAGE_TYPE  (page_get_type ())
#define PAGE(obj)  (G_TYPE_CHECK_INSTANCE_CAST ((obj), PAGE_TYPE, Page))
    
typedef enum
{
    TOP_TO_BOTTOM,
    LEFT_TO_RIGHT,
    BOTTOM_TO_TOP,
    RIGHT_TO_LEFT
} Orientation;


typedef struct PagePrivate PagePrivate;

typedef struct
{
    GObject      parent_instance;
    PagePrivate *priv;
} Page;

typedef struct
{
    GObjectClass parent_class;

    void (*updated) (Page *page);
} PageClass;


Page *page_new ();

// FIXME: Should be part of page_new
void page_set_scan_area (Page *page, gint width, gint rows, gint dpi);

gint page_get_width (Page *page);

gint page_get_height (Page *page);

void page_start (Page *page);

gint page_get_scan_line (Page *page);

void page_parse_scan_line (Page *page, ScanLine *line);

void page_finish (Page *page);

Orientation page_get_orientation (Page *page);

void page_set_orientation (Page *page, Orientation orientation);

gint page_get_width (Page *page);

gint page_get_height (Page *page);

GdkPixbuf *page_get_image (Page *page);

#endif /* _PAGE_H_ */
