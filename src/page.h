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
#include <gio/gio.h>
#include <gdk-pixbuf/gdk-pixbuf.h>
#include "scanner.h"

G_BEGIN_DECLS

#define TYPE_PAGE  (page_get_type ())
#define PAGE(obj)  (G_TYPE_CHECK_INSTANCE_CAST ((obj), TYPE_PAGE, Page))
    
typedef enum
{
    TOP_TO_BOTTOM,
    LEFT_TO_RIGHT,
    BOTTOM_TO_TOP,
    RIGHT_TO_LEFT
} ScanDirection;


typedef struct PagePrivate PagePrivate;

typedef struct
{
    GObject      parent_instance;
    PagePrivate *priv;
} Page;

typedef struct
{
    GObjectClass parent_class;

    void (*pixels_changed) (Page *page);
    void (*size_changed) (Page *page);
    void (*scan_line_changed) (Page *page);
    void (*scan_direction_changed) (Page *page);
    void (*crop_changed) (Page *page);
} PageClass;


GType page_get_type (void);

Page *page_new (gint width, gint height, gint dpi, ScanDirection scan_direction);

void page_set_page_info (Page *page, ScanPageInfo *info);

gint page_get_dpi (Page *page);

gint page_get_width (Page *page);

gint page_get_height (Page *page);

gint page_get_depth (Page *page);

gint page_get_n_channels (Page *page);

gint page_get_rowstride (Page *page);

const guchar *page_get_pixels (Page *page);

guchar *page_get_pixel (Page *page, gint x, gint y);

gboolean page_is_landscape (Page *page);

gint page_get_scan_width (Page *page);

gint page_get_scan_height (Page *page);

void page_set_color_profile (Page *page, const gchar *color_profile);

const gchar *page_get_color_profile (Page *page);

void page_start (Page *page);

gboolean page_is_scanning (Page *page);

gboolean page_has_data (Page *page);

gboolean page_is_color (Page *page);

gint page_get_scan_line (Page *page);

void page_parse_scan_line (Page *page, ScanLine *line);

void page_finish (Page *page);

ScanDirection page_get_scan_direction (Page *page);

void page_rotate_left (Page *page);

void page_rotate_right (Page *page);

void page_set_no_crop (Page *page);

void page_set_custom_crop (Page *page, gint width, gint height);

void page_set_named_crop (Page *page, const gchar *name);

void page_move_crop (Page *page, gint x, gint y);

void page_rotate_crop (Page *page);

gboolean page_has_crop (Page *page);

void page_get_crop (Page *page, gint *x, gint *y, gint *width, gint *height);

gchar *page_get_named_crop (Page *page);

GdkPixbuf *page_get_image (Page *page, gboolean apply_crop);

gboolean page_save (Page *page, const gchar *type, GFile *file, GError **error);

#endif /* _PAGE_H_ */
