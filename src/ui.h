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

#ifndef _UI_H_
#define _UI_H_

#include <glib-object.h>

G_BEGIN_DECLS

#define SIMPLE_SCAN_TYPE  (ui_get_type ())
#define SIMPLE_SCAN(obj)  (G_TYPE_CHECK_INSTANCE_CAST ((obj), SIMPLE_SCAN_TYPE, SimpleScan))

typedef enum
{
    TOP_TO_BOTTOM,
    LEFT_TO_RIGHT,
    BOTTOM_TO_TOP,
    RIGHT_TO_LEFT
} Orientation;


typedef struct SimpleScanPrivate SimpleScanPrivate;

typedef struct
{
    GObject             parent_instance;
    SimpleScanPrivate  *priv;
} SimpleScan;

typedef struct
{
    GObjectClass parent_class;

    void (*render_preview) (SimpleScan *ui, cairo_t *context, double width, double height);
    void (*start_scan) (SimpleScan *ui, const gchar *device, const gchar *document_type);
    void (*stop_scan) (SimpleScan *ui);
    void (*save) (SimpleScan *ui, const gchar *format);
    void (*print) (SimpleScan *ui, cairo_t *context);
    void (*quit) (SimpleScan *ui);
} SimpleScanClass;


SimpleScan *ui_new ();

void ui_set_default_file_name (SimpleScan *ui, const gchar *default_file_name);

void ui_mark_devices_undetected (SimpleScan *ui);

void ui_add_scan_device (SimpleScan *ui, const gchar *device, const gchar *label);

void ui_set_selected_device (SimpleScan *ui, const gchar *device);

void ui_set_scanning (SimpleScan *ui, gboolean scanning);

void ui_set_have_scan (SimpleScan *ui, gboolean have_scan);

Orientation ui_get_orientation (SimpleScan *ui);

void ui_redraw_preview (SimpleScan *ui);

void ui_show_error (SimpleScan *ui, const gchar *error_title, const gchar *error_text);

void ui_start (SimpleScan *ui);

#endif /* _UI_H_ */
