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

#define TYPE_SCAN_DEVICE  (scan_device_get_type ())
#define SCAN_DEVICE(obj)  (G_TYPE_CHECK_INSTANCE_CAST ((obj), TYPE_SCAN_DEVICE, ScanDevice))

#define TYPE_SCAN_OPTIONS  (scan_options_get_type ())
#define SCAN_OPTIONS(obj)  (G_TYPE_CHECK_INSTANCE_CAST ((obj), TYPE_SCAN_OPTIONS, ScanOptions))


typedef struct
{
    gchar *name, *label;
} ScanDevice;
typedef struct
{
    GObjectClass parent_class;
} ScanDeviceClass;

typedef struct
{
    /* Width, height in pixels */
    gint width, height;

    /* Bit depth */
    gint depth;

    /* Number of colour channels */
    gint n_channels;

    /* Resolution */
    gdouble dpi;

    /* The device this page came from */
    gchar *device;
} ScanPageInfo;

typedef struct
{
    /* Line number */
    gint number;
  
    /* Number of lines in this packet */
    gint n_lines;

    /* Width in pixels and format */
    gint width, depth;

    /* Channel for this line or -1 for all channels */
    gint channel;
    
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

typedef enum
{
    SCAN_SINGLE,
    SCAN_ADF_FRONT,
    SCAN_ADF_BACK,
    SCAN_ADF_BOTH
} ScanType;

typedef struct
{
    gint dpi;
    ScanMode scan_mode;
    gint depth;
    ScanType type;
    gint paper_width, paper_height;
} ScanOptions;
typedef struct
{
    GObjectClass parent_class;
} ScanOptionsClass;

typedef struct ScannerPrivate ScannerPrivate;

typedef struct
{
    GObject         parent_instance;
    ScannerPrivate *priv;
} Scanner;

typedef struct
{
    GObjectClass parent_class;

    void (*update_devices) (Scanner *scanner, GList *devices);
    void (*request_authorization) (Scanner *scanner, const gchar *resource);
    void (*expect_page) (Scanner *scanner);
    void (*got_page_info) (Scanner *scanner, ScanPageInfo *info);
    void (*got_line) (Scanner *scanner, ScanLine *line);
    void (*scan_failed) (Scanner *scanner, GError *error);
    void (*page_done) (Scanner *scanner);
    void (*document_done) (Scanner *scanner);
    void (*scanning_changed) (Scanner *scanner);
} ScannerClass;


GType scanner_get_type (void);

Scanner *scanner_new (void);

void scanner_start (Scanner *scanner);

void scanner_authorize (Scanner *scanner, const gchar *username, const gchar *password);

void scanner_redetect (Scanner *scanner);

gboolean scanner_is_scanning (Scanner *scanner);

void scanner_scan (Scanner *scanner, const char *device, ScanOptions *options);

void scanner_cancel (Scanner *scanner);

void scanner_free (Scanner *scanner);

ScanDevice *scan_device_new (void);
GType scan_device_get_type (void);
ScanOptions *scan_options_new (void);
GType scan_options_get_type (void);

#endif /* _SCANNER_H_ */
