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

typedef enum
{
    SCAN_MODE_DEFAULT,    
    SCAN_MODE_COLOR,
    SCAN_MODE_GRAY,
    SCAN_MODE_LINEART
} ScanMode;


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
    void (*authorize) (Scanner *scanner, const gchar *resource);
    void (*got_page_info) (Scanner *scanner, ScanPageInfo *info);
    void (*got_line) (Scanner *scanner, ScanLine *line);
    void (*scan_failed) (Scanner *scanner, GError *error);
    void (*image_done) (Scanner *scanner);
} ScannerClass;


GType scanner_get_type (void);

Scanner *scanner_new (void);

void scanner_start (Scanner *scanner);

void scanner_authorize (Scanner *scanner, const gchar *username, const gchar *password);

void scanner_scan (Scanner *scanner, const char *device,
                   gint dpi, ScanMode scan_mode, gint depth, gboolean multi_page);

void scanner_cancel (Scanner *scanner);

void scanner_free (Scanner *scanner);

#endif /* _SCANNER_H_ */
