#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <gtk/gtk.h>
#include <cairo/cairo-pdf.h>
#include <math.h>

#include "config.h"
#include "ui.h"
#include "scanner.h"

#define DEFAULT_DPI 75 // FIXME


static const char *default_device = NULL;

static SimpleScan *ui;

static Scanner *scanner;

static GdkPixbuf *raw_image = NULL;

static gboolean scan_complete = FALSE;

static int current_line;


static void
update_scan_devices_cb (Scanner *scanner, GList *devices)
{
    GList *dev_iter;

    /* Mark existing values as undetected */
    ui_mark_devices_undetected (ui);

    /* Add/update detected devices */
    for (dev_iter = devices; dev_iter; dev_iter = dev_iter->next) {
        ScanDevice *device = dev_iter->data;
        
        ui_add_scan_device (ui, device->name, device->label);
        g_free (device->name);
        g_free (device->label);
        g_free (device);
    }
    g_list_free (devices);
}


static void
scanner_page_info_cb (Scanner *scanner, ScanPageInfo *info)
{
    gint height;

    g_debug ("Page is %d pixels wide, %d pixels high, %d bits per pixel",
             info->width, info->height, info->depth);

    /* Variable heigh, try 50% of the width for now */
    if (info->height < 0)
        height = info->width / 2;
    else
        height = info->height;

    raw_image = gdk_pixbuf_new (GDK_COLORSPACE_RGB, FALSE,
                                info->depth,
                                info->width,
                                height);
    g_free (info);

    current_line = 0;
    scan_complete = FALSE;
}


static int
get_sample (guchar *data, int depth, int index)
{
    int i, offset, value, n_bits;

    /* Optimise if using 8 bit samples */
    if (depth == 8)
        return data[index];

    /* Bit offset for this sample */
    offset = depth * index;

    /* Get the remaining bits in the octet this sample starts in */
    i = offset / 8;
    n_bits = 8 - offset % 8;
    value = data[i] & (0xFF >> (8 - n_bits));
    
    /* Add additional octets until get enough bits */
    while (n_bits < depth) {
        value = value << 8 | data[i++];
        n_bits += 8;
    }

    /* Trim remaining bits off */
    if (n_bits > depth)
        value >>= n_bits - depth;
    
    return value;
}


static void
scanner_line_cb (Scanner *scanner, ScanLine *line)
{
    guchar *pixels;
    gint i, j;
    
    /* Extend image if necessary */
    while (line->number >= gdk_pixbuf_get_height (raw_image)) {
        GdkPixbuf *image;
        gint height, width, new_height;

        width = gdk_pixbuf_get_width (raw_image);        
        height = gdk_pixbuf_get_height (raw_image);
        new_height = height + width / 2;
        g_debug("Resizing image height from %d pixels to %d pixels", height, new_height);

        image = gdk_pixbuf_new (GDK_COLORSPACE_RGB, FALSE,
                                gdk_pixbuf_get_bits_per_sample (raw_image),
                                width, new_height);
        memcpy (gdk_pixbuf_get_pixels (image),
                gdk_pixbuf_get_pixels (raw_image),
                height * gdk_pixbuf_get_rowstride (raw_image));
        g_object_unref (raw_image);
        raw_image = image;
    }

    pixels = gdk_pixbuf_get_pixels (raw_image) + line->number * gdk_pixbuf_get_rowstride (raw_image);
    switch (line->format) {
    case LINE_RGB:
        memcpy (pixels, line->data, line->data_length);
        break;
    case LINE_GRAY:
        for (i = 0; i < line->width; i++) {
            pixels[j] = get_sample (line->data, line->depth, i);
            pixels[j+1] = get_sample (line->data, line->depth, i);
            pixels[j+2] = get_sample (line->data, line->depth, i);
            j += 3;
        }
        break;
    case LINE_RED:
        for (i = 0; i < line->width; i++) {
            pixels[j] = get_sample (line->data, line->depth, i);
            j += 3;
        }
        break;
    case LINE_GREEN:
        for (i = 0; i < line->width; i++) {
            pixels[j+1] = get_sample (line->data, line->depth, i);
            j += 3;
        }
        break;
    case LINE_BLUE:
        for (i = 0; i < line->width; i++) {
            pixels[j+2] = get_sample (line->data, line->depth, i);
            j += 3;
        }
        break;
    }

    current_line = line->number + 1;

    g_free(line->data);
    g_free(line);

    ui_redraw_preview (ui);
}


static void
scanner_image_done_cb (Scanner *scanner)
{
    /* Trim image */
    if (raw_image && current_line != gdk_pixbuf_get_height (raw_image)) {
        GdkPixbuf *image;

        gint height, width, new_height;

        width = gdk_pixbuf_get_width (raw_image);        
        height = gdk_pixbuf_get_height (raw_image);
        new_height = current_line;
        g_debug("Trimming image height from %d pixels to %d pixels", height, new_height);

        image = gdk_pixbuf_new (GDK_COLORSPACE_RGB, FALSE,
                                gdk_pixbuf_get_bits_per_sample (raw_image),
                                width, new_height);
        memcpy (gdk_pixbuf_get_pixels (image),
                gdk_pixbuf_get_pixels (raw_image),
                new_height * gdk_pixbuf_get_rowstride (raw_image));
        g_object_unref (raw_image);
        raw_image = image;
    }

    scan_complete = TRUE;
    ui_redraw_preview (ui);
    ui_set_have_scan (ui, raw_image != NULL);
}


static void
scanner_ready_cb (Scanner *scanner)
{
    ui_set_scanning (ui, FALSE);
}


static void
render_scan (cairo_t *context, GdkPixbuf *image, Orientation orientation, double canvas_width, double canvas_height, gboolean show_scan_line)
{
    double orig_img_width, orig_img_height, img_width, img_height;
    double source_aspect, canvas_aspect;
    double x_offset = 0.0, y_offset = 0.0, scale = 1.0, rotation = 0.0;

    orig_img_width = img_width = gdk_pixbuf_get_width (image);
    orig_img_height = img_height = gdk_pixbuf_get_height (image);

    switch (orientation) {
    case TOP_TO_BOTTOM:
        rotation = 0.0;
        break;
    case BOTTOM_TO_TOP:
        rotation = M_PI;
        break;
    case LEFT_TO_RIGHT:
        img_width = orig_img_height;
        img_height = orig_img_width;
        rotation = -M_PI_2;
        break;
    case RIGHT_TO_LEFT:
        img_width = orig_img_height;
        img_height = orig_img_width;
        rotation = M_PI_2;
        break;
    }

    /* Scale if cannot fit into canvas */
    if (img_width > canvas_width || img_height > canvas_height) {
        canvas_aspect = canvas_width / canvas_height;
        source_aspect = img_width / img_height;

        /* Scale to canvas height */
        if (canvas_aspect > source_aspect) {
            scale = canvas_height / img_height;
            x_offset = (int) (canvas_width - (img_width * scale)) / 2;
        }
        /* Otherwise scale to canvas width */
        else {
            scale = canvas_width / img_width;
            y_offset = (int) (canvas_height - (img_height * scale)) / 2;
        }
    }
    
    /* Render the image */
    cairo_save (context);

    cairo_translate (context, x_offset, y_offset);
    cairo_scale (context, scale, scale);
    cairo_translate (context, img_width / 2, img_height / 2);
    cairo_rotate (context, rotation);
    cairo_translate (context, -orig_img_width / 2, -orig_img_height / 2);

    gdk_cairo_set_source_pixbuf (context, image, 0, 0);
    cairo_pattern_set_filter (cairo_get_source (context), CAIRO_FILTER_BEST);
    cairo_paint (context);

    cairo_restore (context);

    /* Show scan line */
    if (show_scan_line && !scan_complete) {
        double h = scale * (double)(current_line * orig_img_height) / (double)img_height;
        
        switch (orientation) {
        case TOP_TO_BOTTOM:
            cairo_translate (context, x_offset, y_offset);
            break;
        case BOTTOM_TO_TOP:
            cairo_translate (context, canvas_width - x_offset, canvas_height - y_offset);
            break;
        case LEFT_TO_RIGHT:
            cairo_translate (context, x_offset, canvas_height - y_offset);
            break;
        case RIGHT_TO_LEFT:
            cairo_translate (context, canvas_width - x_offset, y_offset);
            break;
        }
        cairo_rotate (context, rotation);

        cairo_set_source_rgb (context, 1.0, 0.0, 0.0);
        cairo_move_to (context, 0, h);
        cairo_line_to (context, scale * orig_img_width, h);
        cairo_stroke (context);
    }
}


static void
render_cb (SimpleScan *ui, cairo_t *context, double width, double height)
{
    if (raw_image) {
        render_scan (context, raw_image, ui_get_orientation (ui),
                     width, height, TRUE);
    }
    else {
        cairo_set_source_rgb (context, 0.0, 0.0, 0.0);
        cairo_rectangle (context, 0, 0, width, height);
        cairo_fill (context);
    }
}


static void
scan_cb (SimpleScan *ui, const gchar *device)
{
    g_debug ("Requesting scan from device '%s'", device);
    ui_set_have_scan (ui, FALSE);
    ui_set_scanning (ui, TRUE);
    scanner_scan (scanner, device, DEFAULT_DPI);
}


static void
cancel_cb (SimpleScan *ui)
{
    scanner_cancel (scanner);
}


static gboolean
write_pixbuf_data (const gchar *buf, gsize count, GError **error, GFileOutputStream *stream)
{
    return g_output_stream_write_all (G_OUTPUT_STREAM (stream), buf, count, NULL, NULL, error);
}


static gboolean
save_jpeg (GdkPixbuf *image, GFileOutputStream *stream, GError **error)
{
    return gdk_pixbuf_save_to_callback (image,
                                        (GdkPixbufSaveFunc) write_pixbuf_data, stream,
                                        "jpeg", error,
                                        "quality", "90",
                                        NULL);
}


static gboolean
save_png (GdkPixbuf *image, GFileOutputStream *stream, GError **error)
{
    return gdk_pixbuf_save_to_callback (image,
                                        (GdkPixbufSaveFunc) write_pixbuf_data, stream,
                                        "png", error,
                                        NULL);
}

    
static cairo_status_t
write_pdf_data (GFileOutputStream *stream, unsigned char *data, unsigned int length)
{
    gboolean result;
    GError *error = NULL;

    result = g_output_stream_write_all (G_OUTPUT_STREAM (stream), data, length, NULL, NULL, &error);
    
    if (error) {
        g_warning ("Error writing PDF data: %s", error->message);
        g_error_free (error);
    }

    return result ? CAIRO_STATUS_SUCCESS : CAIRO_STATUS_WRITE_ERROR;
}
   

static gboolean
save_pdf (GdkPixbuf *image, GFileOutputStream *stream, GError **error)
{
    cairo_surface_t *surface;
    cairo_t *context;
    double width, height;
    
    width = gdk_pixbuf_get_width (image) * 72.0 / DEFAULT_DPI;
    height = gdk_pixbuf_get_height (image) * 72.0 / DEFAULT_DPI;

    surface = cairo_pdf_surface_create_for_stream ((cairo_write_func_t) write_pdf_data,
                                                   stream,
                                                   width, height);
    
    context = cairo_create (surface);

    cairo_scale (context, 72.0 / DEFAULT_DPI, 72.0 / DEFAULT_DPI);
    gdk_cairo_set_source_pixbuf (context, image, 0, 0);
    cairo_pattern_set_filter (cairo_get_source (context), CAIRO_FILTER_BEST);
    cairo_paint (context);

    cairo_destroy (context);
    cairo_surface_destroy (surface);
    
    return TRUE;
}


static GdkPixbuf *get_rotated_image (Orientation orientation)
{
    switch (orientation) {
    default:
    case TOP_TO_BOTTOM:
        return gdk_pixbuf_ref (raw_image);
    case BOTTOM_TO_TOP:
        return gdk_pixbuf_rotate_simple (raw_image, GDK_PIXBUF_ROTATE_UPSIDEDOWN);
    case LEFT_TO_RIGHT:
        return gdk_pixbuf_rotate_simple (raw_image, GDK_PIXBUF_ROTATE_COUNTERCLOCKWISE);
    case RIGHT_TO_LEFT:
        return gdk_pixbuf_rotate_simple (raw_image, GDK_PIXBUF_ROTATE_CLOCKWISE);
    }   
}


static void
save_cb (SimpleScan *ui, gchar *uri)
{
    GFile *file;
    GError *error = NULL;
    GFileOutputStream *stream;

    file = g_file_new_for_uri (uri);

    stream = g_file_replace (file, NULL, FALSE, G_FILE_CREATE_NONE, NULL, &error);
    if (!stream) {
        g_warning ("Error saving file: %s", error->message);
        g_error_free (error);
    }
    else {
        gboolean result;
        gchar *uri_lower;
        GdkPixbuf *image;

        image = get_rotated_image (ui_get_orientation (ui));

        uri_lower = g_utf8_strdown (uri, -1);
        if (g_str_has_suffix (uri_lower, ".pdf"))
            result = save_pdf (image, stream, &error);
        else if (g_str_has_suffix (uri_lower, ".png"))
            result = save_png (image, stream, &error);
        else
            result = save_jpeg (image, stream, &error);

        g_free (uri_lower);           
        g_object_unref (image);

        if (error) {
            g_warning ("Error saving file: %s", error->message);
            g_error_free (error);
        }

        g_output_stream_close (G_OUTPUT_STREAM (stream), NULL, NULL);
    }
}


static void
print_cb (SimpleScan *ui, cairo_t *context)
{
    GdkPixbuf *image;

    image = get_rotated_image (ui_get_orientation (ui));

    gdk_cairo_set_source_pixbuf (context, image, 0, 0);
    cairo_pattern_set_filter (cairo_get_source (context), CAIRO_FILTER_BEST);
    cairo_paint (context);

    g_object_unref (image);
}


static void
version()
{
    /* NOTE: Is not translated so can be easily parsed */
    fprintf(stderr, "%1$s %2$s\n", SIMPLE_SCAN_BINARY, VERSION);
}


static void
usage(int show_gtk)
{
    fprintf(stderr,
            "Usage:\n"
            "  %s [DEVICE...] - Scanning utility", SIMPLE_SCAN_BINARY);

    fprintf(stderr,
            "\n\n");

    fprintf(stderr,
            "Help Options:\n"
            "  -v, --version                   Show release version\n"
            "  -h, --help                      Show help options\n"
            "  --help-all                      Show all help options\n"
            "  --help-gtk                      Show GTK+ options");
    fprintf(stderr,
            "\n\n");

    if (show_gtk) {
        fprintf(stderr,
                "GTK+ Options:\n"
                "  --class=CLASS                   Program class as used by the window manager\n"
                "  --name=NAME                     Program name as used by the window manager\n"
                "  --screen=SCREEN                 X screen to use\n"
                "  --sync                          Make X calls synchronous\n"
                "  --gtk-module=MODULES            Load additional GTK+ modules\n"
                "  --g-fatal-warnings              Make all warnings fatal");
        fprintf(stderr,
                "\n\n");
    }

    //fprintf(stderr,
    //        "Application Options:\n"
    //        "  -u, --unittest                  Perform unittests\n");
    //fprintf(stderr,
    //        "\n\n");
}


static void
get_options (int argc, char **argv)
{
    int i;

    for (i = 1; i < argc; i++) {
        char *arg = argv[i];

        if (strcmp (arg, "-v") == 0 ||
            strcmp (arg, "--version") == 0) {
            version ();
            exit (0);
        }
        else if (strcmp (arg, "-h") == 0 ||
                 strcmp (arg, "--help") == 0) {
            usage (FALSE);
            exit (0);
        }
        else if (strcmp (arg, "--help-all") == 0) {
            usage (TRUE);
            exit (0);
        }
        else {
            if (default_device) {
                fprintf (stderr, "Unknown argument: '%s'\n", arg);
                exit (1);
            }
            default_device = arg;
        }
    }
}


int
main(int argc, char **argv)
{
    g_thread_init (NULL);
    gtk_init (&argc, &argv);
    
    get_options (argc, argv);

    scanner = scanner_new ();
    g_signal_connect (G_OBJECT (scanner), "ready", G_CALLBACK (scanner_ready_cb), NULL);
    g_signal_connect (G_OBJECT (scanner), "update-devices", G_CALLBACK (update_scan_devices_cb), NULL);
    g_signal_connect (G_OBJECT (scanner), "got-page-info", G_CALLBACK (scanner_page_info_cb), NULL);
    g_signal_connect (G_OBJECT (scanner), "got-line", G_CALLBACK (scanner_line_cb), NULL);
    g_signal_connect (G_OBJECT (scanner), "image-done", G_CALLBACK (scanner_image_done_cb), NULL);

    ui = ui_new ();
    g_signal_connect (ui, "render-preview", G_CALLBACK (render_cb), NULL);
    g_signal_connect (ui, "start-scan", G_CALLBACK (scan_cb), NULL);
    g_signal_connect (ui, "stop-scan", G_CALLBACK (cancel_cb), NULL);
    g_signal_connect (ui, "save", G_CALLBACK (save_cb), NULL);
    g_signal_connect (ui, "print", G_CALLBACK (print_cb), NULL);

    if (default_device)
        ui_set_selected_device (ui, default_device);

    gtk_main ();

    return 0;
}
