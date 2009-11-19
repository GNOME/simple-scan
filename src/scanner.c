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

#include <string.h>
#include <sane/sane.h>
#include <sane/saneopts.h>
#include <glib/gi18n.h>

#include "scanner.h"


enum {
    READY,
    UPDATE_DEVICES,
    GOT_PAGE_INFO,
    GOT_LINE,
    SCAN_FAILED,
    IMAGE_DONE,
    LAST_SIGNAL
};
static guint signals[LAST_SIGNAL] = { 0, };

typedef struct
{
    Scanner *instance;
    guint sig;
    gpointer data;
} SignalInfo;

typedef enum
{
    STATE_IDLE = 0,
    STATE_GET_OPTION,
    STATE_START,
    STATE_GET_PARAMETERS,
    STATE_READ,
    STATE_CLOSE
} ScanState;

struct ScannerPrivate
{
    GAsyncQueue *scan_queue;
    gint dpi;
    gboolean running;
    GThread *thread;
};

G_DEFINE_TYPE (Scanner, scanner, G_TYPE_OBJECT);


static gboolean
send_signal (SignalInfo *info)
{
    g_signal_emit (info->instance, signals[info->sig], 0, info->data);
    
    switch (info->sig) {
    case UPDATE_DEVICES:
        {
            GList *iter, *devices = info->data;
            for (iter = devices; iter; iter = iter->next) {
                ScanDevice *device = iter->data;
                g_free (device->name);
                g_free (device->label);
                g_free (device);
            }
            g_list_free (devices);
        }
        break;
    case GOT_PAGE_INFO:
        {
            ScanPageInfo *page_info = info->data;
            g_free (page_info);
        }
        break;
    case GOT_LINE:
        {
            ScanLine *line = info->data;
            g_free(line->data);
            g_free(line);
        }
        break;
    case SCAN_FAILED:
        {
            GError *error = info->data;
            g_error_free (error);
        }
        break;
    default:
    case READY:
    case IMAGE_DONE:
    case LAST_SIGNAL:
        g_assert (info->data == NULL);
        break;
    }
    g_free (info);

    return FALSE;
}


/* Emit signals in main loop */
static void
emit_signal (Scanner *scanner, guint sig, gpointer data)
{
    SignalInfo *info;
    
    info = g_malloc(sizeof(SignalInfo));
    info->instance = scanner;
    info->sig = sig;
    info->data = data;
    g_idle_add ((GSourceFunc) send_signal, info);
}


static void
poll_for_devices (Scanner *scanner)
{
    const SANE_Device **device_list, **device_iter;
    SANE_Status status;
    GList *devices = NULL;

    status = sane_get_devices (&device_list, SANE_FALSE);
    if (status != SANE_STATUS_GOOD) {
        g_warning ("Unable to get SANE devices: Error %s", sane_strstatus(status));
        return;
    }

    for (device_iter = device_list; *device_iter; device_iter++) {
        const SANE_Device *device = *device_iter;
        ScanDevice *scan_device;
        GString *label;
        
        scan_device = g_malloc(sizeof(ScanDevice));

        scan_device->name = g_strdup (device->name);
        label = g_string_new ("");
        g_string_printf (label, "%s %s", device->vendor, device->model);
        scan_device->label = label->str;
        g_string_free (label, FALSE);

        devices = g_list_append (devices, scan_device);
    }

    emit_signal (scanner, UPDATE_DEVICES, devices);
}


static void
set_bool_option (SANE_Handle handle, const SANE_Option_Descriptor *option, SANE_Int option_index, SANE_Bool value)
{
    SANE_Bool v = value;
    g_return_if_fail (option->type == SANE_TYPE_BOOL);
    sane_control_option (handle, option_index, SANE_ACTION_SET_VALUE, &v, NULL);
}


static void
set_int_option (SANE_Handle handle, const SANE_Option_Descriptor *option, SANE_Int option_index, SANE_Int value)
{
    SANE_Int v = value;

    g_return_if_fail (option->type == SANE_TYPE_INT);

    if (option->constraint_type == SANE_CONSTRAINT_RANGE) {
        v *= option->constraint.range->quant;
        if (v < option->constraint.range->min)
            v = option->constraint.range->min;
        if (v > option->constraint.range->max)
            v = option->constraint.range->max;
    }
    sane_control_option (handle, option_index, SANE_ACTION_SET_VALUE, &v, NULL);
}


static void
set_fixed_option (SANE_Handle handle, const SANE_Option_Descriptor *option, SANE_Int option_index, SANE_Fixed value)
{
    SANE_Fixed v = value;

    g_return_if_fail (option->type == SANE_TYPE_FIXED);

    if (option->constraint_type == SANE_CONSTRAINT_RANGE) {
        v *= option->constraint.range->quant;
        if (v < option->constraint.range->min)
            v = option->constraint.range->min;
        if (v > option->constraint.range->max)
            v = option->constraint.range->max;
    }
    sane_control_option (handle, option_index, SANE_ACTION_SET_VALUE, &v, NULL);
}


static void
set_string_option (SANE_Handle handle, const SANE_Option_Descriptor *option, SANE_Int option_index, const char *value)
{
    char *string;
    gsize value_size, size;

    g_return_if_fail (option->type == SANE_TYPE_STRING);
    
    value_size = strlen (value) + 1;
    size = option->size > value_size ? option->size : value_size;
    string = g_malloc(sizeof(char) * size);
    strcpy (string, value);
    sane_control_option (handle, option_index, SANE_ACTION_SET_VALUE, string, NULL);
    g_free (string);
}


static void
log_option (SANE_Int index, const SANE_Option_Descriptor *option)
{
    GString *string;
    SANE_String_Const *string_iter;
    SANE_Word i;
    
    string = g_string_new ("");

    g_string_append_printf (string, "Option %d: name='%s', title='%s'",
                            index, option->name, option->title);

    switch (option->type) {
    case SANE_TYPE_BOOL:
        g_string_append (string, " type=bool");
        break;
    case SANE_TYPE_INT:
        g_string_append (string, " type=int");
        break;
    case SANE_TYPE_FIXED:
        g_string_append (string, " type=fixed");        
        break;
    case SANE_TYPE_STRING:
        g_string_append (string, " type=string");        
        break;
    case SANE_TYPE_BUTTON:
        g_string_append (string, " type=button");        
        break;
    case SANE_TYPE_GROUP:
        g_string_append (string, " type=group");
        break;
    default:
        g_string_append_printf (string, " type=%d", option->type);
        break;
    }

    switch (option->unit) {
    case SANE_UNIT_NONE:
        break;
    case SANE_UNIT_PIXEL:
        g_string_append (string, " unit=pixels");
        break;
    case SANE_UNIT_BIT:
        g_string_append (string, " unit=bits");
        break;
    case SANE_UNIT_MM:
        g_string_append (string, " unit=mm");
        break;
    case SANE_UNIT_DPI:
        g_string_append (string, " unit=dpi");
        break;
    case SANE_UNIT_PERCENT:
        g_string_append (string, " unit=percent");
        break;
    case SANE_UNIT_MICROSECOND:
        g_string_append (string, " unit=microseconds");
        break;
    default:
        g_string_append_printf (string, " unit=%d", option->unit);
        break;
    }

    switch (option->constraint_type) {
    case SANE_CONSTRAINT_RANGE:
        g_string_append_printf (string, " min=%d, max=%d, quant=%d",
                                option->constraint.range->min, option->constraint.range->max,
                                option->constraint.range->quant);
        break;
    case SANE_CONSTRAINT_WORD_LIST:
        g_string_append (string, " values=[");
        for (i = 0; i < option->constraint.word_list[0]; i++) {
            if (i != 0)
                g_string_append (string, ", ");
            g_string_append_printf (string, "%d", option->constraint.word_list[i+1]);
        }
        g_string_append (string, "]");
        break;
    case SANE_CONSTRAINT_STRING_LIST:
        g_string_append (string, " values=[");
        for (i = 0; option->constraint.string_list[i]; i++) {
            if (i != 0)
                g_string_append (string, ", ");
            g_string_append_printf (string, "\"%s\"", option->constraint.string_list[i]);
        }
        g_string_append (string, "]");
        break;
    default:
        break;
    }

    g_debug ("%s", string->str);
    g_string_free (string, TRUE);

    if (option->desc)
        g_debug ("  Description: %s", option->desc);
}


static gpointer
scan_thread (Scanner *scanner)
{
    gchar *device;
    SANE_Status status;
    SANE_Handle handle = NULL;
    SANE_Parameters parameters;
    const SANE_Option_Descriptor *option;
    SANE_Int option_index = 0;
    ScanState state = STATE_IDLE;
    SANE_Int bytes_remaining, line_count = 0, n_read;
    SANE_Byte *data;
    SANE_Int version_code;

    status = sane_init (&version_code, NULL);
    if (status != SANE_STATUS_GOOD) {
        g_warning ("Unable to initialize SANE backend: Error %s", sane_strstatus(status));
        return FALSE;
    }
    g_debug ("SANE version %d.%d.%d",
             SANE_VERSION_MAJOR(version_code),
             SANE_VERSION_MINOR(version_code),
             SANE_VERSION_BUILD(version_code));

    while (scanner->priv->running) {
        /* Get device to use */
        if (state == STATE_IDLE) {
            GTimeVal timeout = { 1, 0 };
            device = g_async_queue_timed_pop (scanner->priv->scan_queue, &timeout);
        } else if (state != STATE_CLOSE) {
            if (g_async_queue_length (scanner->priv->scan_queue) > 0)
                state = STATE_CLOSE;
        }
        
        /* Interrupted */
        if (!scanner->priv->running)
            break;
        
        switch (state) {
        case STATE_IDLE:
            if (device == NULL) {
                poll_for_devices (scanner);
            } else if (device[0] != '\0') {
                status = sane_open (device, &handle);
                if (status != SANE_STATUS_GOOD) {
                    g_warning ("Unable to get open device: %s", sane_strstatus (status));
                    emit_signal (scanner, SCAN_FAILED,
                                 g_error_new (SCANNER_TYPE, status,
                                              /* Error displayed when cannot connect to scanner */
                                              _("Unable to connect to scanner")));
                    state = STATE_CLOSE;
                }
                else {
                    state = STATE_GET_OPTION;
                    option_index = 0;
                }
            }
            break;

        case STATE_GET_OPTION:
            option = sane_get_option_descriptor (handle, option_index);
            if (!option) {
                state = STATE_START;
            } else {
                log_option (option_index, option);
                if (option->name) {
                    if (strcmp (option->name, SANE_NAME_SCAN_RESOLUTION) == 0) {
                        set_fixed_option (handle, option, option_index, scanner->priv->dpi);
                    }
                }
                option_index++;
            }
            break;
            
        case STATE_START:
            status = sane_start (handle);
            if (status != SANE_STATUS_GOOD) {
                g_warning ("Unable to start device: Error %s", sane_strstatus (status));
                emit_signal (scanner, SCAN_FAILED,
                             g_error_new (SCANNER_TYPE, status,
                                          /* Error display when unable to start scan */
                                          _("Unable to start scan")));
                state = STATE_CLOSE;
            } else {
                state = STATE_GET_PARAMETERS;
            }
            break;
            
        case STATE_GET_PARAMETERS:
            status = sane_get_parameters (handle, &parameters);
            if (status != SANE_STATUS_GOOD) {
                g_warning ("Unable to get device parameters: Error %s", sane_strstatus (status));
                emit_signal (scanner, SCAN_FAILED,
                             g_error_new (SCANNER_TYPE, status,
                                          /* Error displayed when communication with scanner broken */
                                          _("Error communicating with scanner")));
                state = STATE_CLOSE;
            } else {
                ScanPageInfo *info;
                
                info = g_malloc(sizeof(ScanPageInfo));
                info->width = parameters.pixels_per_line;
                info->height = parameters.lines;
                info->depth = parameters.depth;
                emit_signal (scanner, GOT_PAGE_INFO, info);
                bytes_remaining = parameters.bytes_per_line;
                data = g_malloc(sizeof(SANE_Byte) * bytes_remaining);
                line_count = 0;
                state = STATE_READ;
            }
            break;
            
        case STATE_READ:
            status = sane_read (handle, data, bytes_remaining, &n_read);
            if (status == SANE_STATUS_EOF &&
                parameters.lines == -1 &&
                bytes_remaining == parameters.bytes_per_line) {
                state = STATE_CLOSE;
            } else if (status != SANE_STATUS_GOOD) {
                g_warning ("Unable to read frame from device: Error %s", sane_strstatus (status));
                emit_signal (scanner, SCAN_FAILED,
                             g_error_new (SCANNER_TYPE, status,
                                          /* Error displayed when communication with scanner broken */
                                          _("Error communicating with scanner")));
                state = STATE_CLOSE;
            } else {
                bytes_remaining -= n_read;
                if (bytes_remaining == 0) {
                    ScanLine *line;

                    line = g_malloc(sizeof(ScanLine));
                    switch (parameters.format) {
                    case SANE_FRAME_GRAY:
                        line->format = LINE_GRAY;
                        break;
                    case SANE_FRAME_RGB:
                        line->format = LINE_RGB;
                        break;
                    case SANE_FRAME_RED:
                        line->format = LINE_RED;
                        break;
                    case SANE_FRAME_GREEN:
                        line->format = LINE_GREEN;
                        break;
                    case SANE_FRAME_BLUE:
                        line->format = LINE_BLUE;
                        break;
                    }
                    line->width = parameters.pixels_per_line;
                    line->depth = parameters.depth;
                    line->data = data;
                    line->data_length = parameters.bytes_per_line;
                    line->number = line_count;
                    emit_signal (scanner, GOT_LINE, line);

                    line_count++;
                    if (parameters.lines > 0 && line_count == parameters.lines) {
                        data = NULL;
                        state = STATE_CLOSE;
                    } else {
                        bytes_remaining = parameters.bytes_per_line;
                        data = g_malloc(sizeof(SANE_Byte) * bytes_remaining);
                    }
                }
            }
            break;
            
        case STATE_CLOSE:
            emit_signal (scanner, IMAGE_DONE, NULL);
            if (handle)
                sane_close (handle);
            handle = NULL;
            g_free (data);
            data = NULL;
            g_free (device);
            device = NULL;
            state = STATE_IDLE;
            emit_signal (scanner, READY, NULL);            
            break;
        }
    }
    
    return NULL;
}


Scanner *
scanner_new ()
{
    return g_object_new (SCANNER_TYPE, NULL);
}


void
scanner_start (Scanner *scanner)
{
    GError *error = NULL;
    scanner->priv->thread = g_thread_create ((GThreadFunc) scan_thread, scanner, TRUE, &error);
    if (error) {
        g_critical ("Unable to create thread: %s", error->message);
        g_error_free (error);
    }    
}


void
scanner_scan (Scanner *scanner, const char *device, gint dpi_)
{
    scanner->priv->dpi = dpi_;
    g_async_queue_push (scanner->priv->scan_queue, g_strdup (device));    
}


void
scanner_cancel (Scanner *scanner)
{
    g_async_queue_push (scanner->priv->scan_queue, "");
}


void scanner_free (Scanner *scanner)
{
    g_debug ("Stopping scan thread");
    scanner->priv->running = FALSE;
    g_async_queue_push (scanner->priv->scan_queue, "");
    if (scanner->priv->thread)
        g_thread_join (scanner->priv->thread);

    g_async_queue_unref (scanner->priv->scan_queue);
    g_object_unref (scanner);

    g_debug ("Closing SANE interface");
    sane_exit ();
    g_debug ("SANE interface closed");
}


static void
scanner_class_init (ScannerClass *klass)
{
    signals[READY] =
        g_signal_new ("ready",
                      G_TYPE_FROM_CLASS (klass),
                      G_SIGNAL_RUN_LAST,
                      G_STRUCT_OFFSET (ScannerClass, ready),
                      NULL, NULL,
                      g_cclosure_marshal_VOID__VOID,
                      G_TYPE_NONE, 0);
    signals[UPDATE_DEVICES] =
        g_signal_new ("update-devices",
                      G_TYPE_FROM_CLASS (klass),
                      G_SIGNAL_RUN_LAST,
                      G_STRUCT_OFFSET (ScannerClass, update_devices),
                      NULL, NULL,
                      g_cclosure_marshal_VOID__POINTER,
                      G_TYPE_NONE, 1, G_TYPE_POINTER);
    signals[GOT_PAGE_INFO] =
        g_signal_new ("got-page-info",
                      G_TYPE_FROM_CLASS (klass),
                      G_SIGNAL_RUN_LAST,
                      G_STRUCT_OFFSET (ScannerClass, got_page_info),
                      NULL, NULL,
                      g_cclosure_marshal_VOID__POINTER,
                      G_TYPE_NONE, 1, G_TYPE_POINTER);
    signals[GOT_LINE] =
        g_signal_new ("got-line",
                      G_TYPE_FROM_CLASS (klass),
                      G_SIGNAL_RUN_LAST,
                      G_STRUCT_OFFSET (ScannerClass, got_line),
                      NULL, NULL,
                      g_cclosure_marshal_VOID__POINTER,
                      G_TYPE_NONE, 1, G_TYPE_POINTER);
    signals[SCAN_FAILED] =
        g_signal_new ("scan-failed",
                      G_TYPE_FROM_CLASS (klass),
                      G_SIGNAL_RUN_LAST,
                      G_STRUCT_OFFSET (ScannerClass, scan_failed),
                      NULL, NULL,
                      g_cclosure_marshal_VOID__POINTER,
                      G_TYPE_NONE, 1, G_TYPE_POINTER);
    signals[IMAGE_DONE] =
        g_signal_new ("image-done",
                      G_TYPE_FROM_CLASS (klass),
                      G_SIGNAL_RUN_LAST,
                      G_STRUCT_OFFSET (ScannerClass, image_done),
                      NULL, NULL,
                      g_cclosure_marshal_VOID__VOID,
                      G_TYPE_NONE, 0);

    g_type_class_add_private (klass, sizeof (ScannerPrivate));
}


static void
scanner_init (Scanner *scanner)
{
    scanner->priv = G_TYPE_INSTANCE_GET_PRIVATE (scanner, SCANNER_TYPE, ScannerPrivate);
    scanner->priv->running = TRUE;
    scanner->priv->scan_queue = g_async_queue_new ();
}
