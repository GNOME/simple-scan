#ifndef _SCANNER_H_
#define _SCANNER_H_

#include <glib-object.h>

G_BEGIN_DECLS

#define SCANNER_TYPE                (scanner_get_type ())
#define SCANNER(obj)                (G_TYPE_CHECK_INSTANCE_CAST ((obj), SCANNER_TYPE, Scanner))
    

typedef struct
{
    gchar *name, *label;
} ScanDevice;

typedef struct
{
    gint width, height, depth;
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
    void (*image_done) (Scanner *scanner);
} ScannerClass;


Scanner *scanner_new ();

void scanner_scan (Scanner *scanner, const char *device, gint dpi);

void scanner_cancel (Scanner *scanner);

#endif /* _SCANNER_H_ */
