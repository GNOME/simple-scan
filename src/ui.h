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
#include "book.h"
#include "scanner.h"

G_BEGIN_DECLS

#define SIMPLE_SCAN_TYPE  (ui_get_type ())
#define SIMPLE_SCAN(obj)  (G_TYPE_CHECK_INSTANCE_CAST ((obj), SIMPLE_SCAN_TYPE, SimpleScan))


typedef struct SimpleScanPrivate SimpleScanPrivate;

typedef struct
{
    GObject             parent_instance;
    SimpleScanPrivate  *priv;
} SimpleScan;

typedef struct
{
    GObjectClass parent_class;

    void (*start_scan) (SimpleScan *ui, ScanOptions *options);
    void (*stop_scan) (SimpleScan *ui);
    void (*save) (SimpleScan *ui, const gchar *format);
    void (*email) (SimpleScan *ui, const gchar *profile);
    void (*quit) (SimpleScan *ui);
} SimpleScanClass;


GType ui_get_type (void);

SimpleScan *ui_new (void);

Book *ui_get_book (SimpleScan *ui);

void ui_set_selected_page (SimpleScan *ui, Page *page);

Page *ui_get_selected_page (SimpleScan *ui);

void ui_set_default_file_name (SimpleScan *ui, const gchar *default_file_name);

void ui_authorize (SimpleScan *ui, const gchar *resource, gchar **username, gchar **password);

void ui_set_scan_devices (SimpleScan *ui, GList *devices);

gchar *ui_get_selected_device (SimpleScan *ui);

void ui_set_selected_device (SimpleScan *ui, const gchar *device);

void ui_set_scanning (SimpleScan *ui, gboolean scanning);

void ui_show_error (SimpleScan *ui, const gchar *error_title, const gchar *error_text, gboolean change_scanner_hint);

void ui_start (SimpleScan *ui);

#endif /* _UI_H_ */
