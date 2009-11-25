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

#ifndef _SCANNER_H_
#define _SCANNER_H_

#include <glib-object.h>

G_BEGIN_DECLS

#define SCANNER_TYPE  (scanner_get_type ())
#define SCANNER(obj)  (G_TYPE_CHECK_INSTANCE_CAST ((obj), SCANNER_TYPE, Scanner))


typedef struct
{
    gchar *name, *label;
} ScanDevice;

typedef struct
{
    gint width, height, depth, dpi;
} ScanPageInfo;

typedef struct
{
    /* Line number */
    gint number;

    /* Width in pixels and format */
    gint width, depth;
    enum
    {
        LINE_GRAY,
        LINE_RGB,
        LINE_RED,
        LINE_GREEN,
        LINE_BLUE
    } format;
    
    /* Raw line data */
    guchar *data;
    gsize data_length;
} ScanLine;


typedef struct ScannerPrivate ScannerPrivate;

typedef struct
{
    GObject         parent_instance;
    ScannerPrivate *priv;
} Scanner;

typedef struct
{
    GObjectClass parent_class;

    void (*ready) (Scanner *scanner);
    void (*update_devices) (Scanner *scanner, GList *devices);
    void (*got_page_info) (Scanner *scanner, ScanPageInfo *info);
    void (*got_line) (Scanner *scanner, ScanLine *line);
    void (*scan_failed) (Scanner *scanner, GError *error);
    void (*image_done) (Scanner *scanner);
} ScannerClass;


Scanner *scanner_new ();

void scanner_start (Scanner *scanner);

void scanner_scan (Scanner *scanner, const char *device, const char *source,
                   gint dpi, const char *scan_mode, gint depth, gboolean multi_page);

void scanner_cancel (Scanner *scanner);

void scanner_free (Scanner *scanner);

#endif /* _SCANNER_H_ */
