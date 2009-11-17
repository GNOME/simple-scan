#include <string.h>
#include <gtk/gtk.h>
#include <gconf/gconf-client.h>

#include "ui.h"


enum {
    RENDER_PREVIEW,
    START_SCAN,
    STOP_SCAN,
    SAVE,
    PRINT,
    LAST_SIGNAL
};
static guint signals[LAST_SIGNAL] = { 0, };


struct SimpleScanPrivate
{
    GConfClient *client;

    GtkWidget *window;
    GtkWidget *scan_label;
    GtkWidget *actions_box;
    GtkWidget *device_combo, *mode_combo;
    GtkTreeModel *device_model;
    GtkWidget *preview_area;

    gboolean scanning;
    Orientation orientation;
};

G_DEFINE_TYPE (SimpleScan, ui, G_TYPE_OBJECT);


static gboolean
find_scan_device (SimpleScan *ui, const char *device, GtkTreeIter *iter)
{
    gboolean have_iter = FALSE;

    if (gtk_tree_model_get_iter_first (ui->priv->device_model, iter)) {
        do {
            gchar *d;
            gtk_tree_model_get (ui->priv->device_model, iter, 0, &d, -1);
            if (strcmp (d, device) == 0)
                have_iter = TRUE;
            g_free (d);
        } while (!have_iter && gtk_tree_model_iter_next (ui->priv->device_model, iter));
    }
    
    return have_iter;
}


static gchar *
get_selected_device (SimpleScan *ui)
{
    GtkTreeIter iter;

    if (gtk_combo_box_get_active_iter (GTK_COMBO_BOX (ui->priv->device_combo), &iter)) {
        gchar *device;
        gtk_tree_model_get (ui->priv->device_model, &iter, 0, &device, -1);
        return device;
    }

    return NULL;
}


void
ui_mark_devices_undetected (SimpleScan *ui)
{
    GtkTreeIter iter;
    
    if (gtk_tree_model_get_iter_first (ui->priv->device_model, &iter)) {
        do {
            gtk_list_store_set (GTK_LIST_STORE (ui->priv->device_model), &iter, 2, FALSE, -1);
        } while (gtk_tree_model_iter_next (ui->priv->device_model, &iter));
    }
}


void
ui_add_scan_device (SimpleScan *ui, const gchar *device, const gchar *label)
{
    GtkTreeIter iter;
    
    if (!find_scan_device (ui, device, &iter)) {
        gtk_list_store_append (GTK_LIST_STORE (ui->priv->device_model), &iter);
        gtk_list_store_set (GTK_LIST_STORE (ui->priv->device_model), &iter, 0, device, -1);
    }

    gtk_list_store_set (GTK_LIST_STORE (ui->priv->device_model), &iter, 1, label, 2, TRUE, -1);
    
    /* Select this device if none selected */
    if (gtk_combo_box_get_active (GTK_COMBO_BOX (ui->priv->device_combo)) == -1)
        gtk_combo_box_set_active_iter (GTK_COMBO_BOX (ui->priv->device_combo), &iter);
}


void
ui_set_selected_device (SimpleScan *ui, const gchar *device)
{
    GtkTreeIter iter;

    /* If doesn't exist add with label set to device name */
    if (!find_scan_device (ui, device, &iter)) {
        gtk_list_store_append (GTK_LIST_STORE (ui->priv->device_model), &iter);
        gtk_list_store_set (GTK_LIST_STORE (ui->priv->device_model), &iter, 0, device, 1, device, 2, FALSE, -1);
    }

    gtk_combo_box_set_active_iter (GTK_COMBO_BOX (ui->priv->device_combo), &iter);
}


static void
get_document_hint (SimpleScan *ui)
{
    GtkTreeIter iter;

    if (gtk_combo_box_get_active_iter (GTK_COMBO_BOX (ui->priv->mode_combo), &iter)) {
        GtkTreeModel *model;
        gchar *mode;

        model = gtk_combo_box_get_model (GTK_COMBO_BOX (ui->priv->mode_combo));
        gtk_tree_model_get (model, &iter, 0, &mode, -1);
        g_free (mode);
    }
}


G_MODULE_EXPORT
gboolean
preview_area_expose_event_cb (GtkWidget *widget, GdkEventExpose *event, SimpleScan *ui)
{
    cairo_t *context;
    double width, height;
    
    context = gdk_cairo_create (widget->window);
    
    width = widget->allocation.width;
    height = widget->allocation.height;
    g_signal_emit (G_OBJECT (ui), signals[RENDER_PREVIEW], 0, context, width, height);

    cairo_destroy (context);

    return FALSE;
}


G_MODULE_EXPORT
void
scan_button_clicked_cb (GtkWidget *widget, SimpleScan *ui)
{
    if (ui->priv->scanning) {
        g_signal_emit (G_OBJECT (ui), signals[STOP_SCAN], 0);
    } else {
        gchar *device;
        device = get_selected_device (ui);
        if (device) {
            g_signal_emit (G_OBJECT (ui), signals[START_SCAN], 0, device);
            g_free (device);
        }
    }
}


G_MODULE_EXPORT
void
rotate_button_clicked_cb (GtkWidget *widget, SimpleScan *ui)
{
    ui->priv->orientation++;
    if (ui->priv->orientation > RIGHT_TO_LEFT)
        ui->priv->orientation = TOP_TO_BOTTOM;
    ui_redraw_preview (ui);
}


G_MODULE_EXPORT
void
save_file_button_clicked_cb (GtkWidget *widget, SimpleScan *ui)
{
    GtkWidget *dialog;
    gint response;

    dialog = gtk_file_chooser_dialog_new ("Save As...", GTK_WINDOW (ui->priv->window),
                                          GTK_FILE_CHOOSER_ACTION_SAVE,
                                          GTK_STOCK_CANCEL, GTK_RESPONSE_CANCEL,
                                          GTK_STOCK_SAVE, GTK_RESPONSE_ACCEPT,
                                          NULL);
    gtk_file_chooser_set_do_overwrite_confirmation (GTK_FILE_CHOOSER (dialog), TRUE);
    gtk_file_chooser_set_local_only (GTK_FILE_CHOOSER (dialog), FALSE);
    gtk_file_chooser_set_current_name (GTK_FILE_CHOOSER (dialog), "Scanned Document.pdf");
    
    response = gtk_dialog_run (GTK_DIALOG (dialog));
    if (response == GTK_RESPONSE_ACCEPT) {
        gchar *uri;
        
        uri = gtk_file_chooser_get_uri (GTK_FILE_CHOOSER (dialog));
        g_signal_emit (G_OBJECT (ui), signals[SAVE], 0, uri);

        g_free (uri);
    }
    gtk_widget_destroy (dialog);
}


static void
draw_page (GtkPrintOperation *operation,
           GtkPrintContext   *print_context,
           gint               page_number,
           SimpleScan                *ui)
{
    cairo_t *context;

    context = gtk_print_context_get_cairo_context (print_context);

    g_signal_emit (G_OBJECT (ui), signals[PRINT], 0, context);

    //For some reason can't destroy until job complete
    //cairo_destroy (context);
}


G_MODULE_EXPORT
void
print_button_clicked_cb (GtkWidget *widget, SimpleScan *ui)
{
    GtkPrintOperation *print;
    GtkPrintOperationResult result;
    GError *error = NULL;
    
    print = gtk_print_operation_new ();
    gtk_print_operation_set_n_pages (print, 1);
    gtk_print_operation_set_use_full_page (print, TRUE);
    // FIXME: Auto portrait, landscape
    g_signal_connect (print, "draw-page", G_CALLBACK (draw_page), ui);

    result = gtk_print_operation_run (print, GTK_PRINT_OPERATION_ACTION_PRINT_DIALOG,
                                      GTK_WINDOW (ui->priv->window), &error);

    g_object_unref (print);
}


static void
load_device_cache (SimpleScan *ui)
{
    gchar *filename;
    GKeyFile *key_file;
    gboolean result;
    GError *error = NULL;
    
    filename = g_build_filename (g_get_user_cache_dir (), "simple-scan", "device_cache", NULL);
    
    key_file = g_key_file_new ();
    result = g_key_file_load_from_file (key_file, filename, G_KEY_FILE_NONE, &error);
    if (error) {
        g_warning ("Error loading device cache file: %s", error->message);
        g_error_free (error);
        error = NULL;
    }
    if (result) {
        gchar **groups, **group_iter;

        groups = g_key_file_get_groups (key_file, NULL);
        for (group_iter = groups; *group_iter; group_iter++) {
            gchar *label, *device;

            label = *group_iter;
            device = g_key_file_get_value (key_file, label, "device", &error);
            if (error) {
                g_warning ("Error getting device name for label '%s': %s", label, error->message);
                g_error_free (error);
                error = NULL;
            }
            
            if (device)
                ui_add_scan_device (ui, device, label);

            g_free (device);
        }

        g_strfreev (groups);
    }

    g_free (filename);
    g_key_file_free (key_file);
}


static void
save_device_cache (SimpleScan *ui)
{
    GtkTreeModel *model;
    GtkTreeIter iter;

    g_debug ("Saving device cache");

    model = ui->priv->device_model;
    if (gtk_tree_model_get_iter_first (model, &iter)) {
        GKeyFile *key_file;
        gchar *data;
        gsize data_length;
        GError *error = NULL;

        key_file = g_key_file_new ();
        do {
            gchar *name, *label;
            gboolean detected;
            
            gtk_tree_model_get (model, &iter, 0, &name, 1, &label, 2, &detected, -1);
            
            if (detected) {
                g_debug ("Storing device '%s' in cache", name);
                g_key_file_set_value (key_file, label, "device", name);
            }

            g_free (name);
            g_free (label);
        } while (gtk_tree_model_iter_next (model, &iter));
        
        data = g_key_file_to_data (key_file, &data_length, &error);
        if (data) {
            gchar *dir, *filename;
            GFile *file;
            GFileOutputStream *stream;
            GError *error = NULL;

            dir = g_build_filename (g_get_user_cache_dir (), "simple-scan", NULL);
            g_mkdir_with_parents (dir, 0700);
            filename = g_build_filename (dir, "device_cache", NULL);

            file = g_file_new_for_path (filename);
            stream = g_file_replace (file, NULL, FALSE, G_FILE_CREATE_NONE, NULL, &error);
            if (error) {
                g_warning ("Error writing device cache: %s", error->message);
                g_error_free (error);
                error = NULL;
            }
            if (stream) {
                g_output_stream_write_all (G_OUTPUT_STREAM (stream), data, data_length, NULL, NULL, &error);
                if (error) {
                    g_warning ("Error writing device cache: %s", error->message);
                    g_error_free (error);
                    error = NULL;
                }
                g_output_stream_close (G_OUTPUT_STREAM (stream), NULL, NULL);
            }
            g_free (data);

            g_free (filename);
            g_free (dir);        
        }

        g_key_file_free (key_file);
    }
}


G_MODULE_EXPORT
gboolean
window_delete_event_cb (GtkWidget *widget, GdkEvent *event, SimpleScan *ui)
{
    char *device;
    save_device_cache (ui);
    device = get_selected_device (ui);
    if (device) {
        gconf_client_set_string(ui->priv->client, "/apps/simple-scan/selected_device", device, NULL);
        g_free (device);
    }
    gtk_main_quit ();
    return TRUE;
}


static gboolean
ui_load (SimpleScan *ui)
{
    GtkBuilder *builder;
    GError *error = NULL;
    GtkCellRenderer *renderer;
    GtkTreeIter iter;
    gchar *device;

    builder = gtk_builder_new ();
    gtk_builder_add_from_file (builder, UI_DIR "simple-scan.ui", &error);
    if (error) {
        g_critical ("Unable to load UI: %s\n", error->message);
        return FALSE;
    }
    gtk_builder_connect_signals (builder, ui);

    ui->priv->window = GTK_WIDGET (gtk_builder_get_object (builder, "simple_scan_window"));
    ui->priv->scan_label = GTK_WIDGET (gtk_builder_get_object (builder, "scan_label"));
    ui->priv->actions_box = GTK_WIDGET (gtk_builder_get_object (builder, "actions_box"));
    ui->priv->device_combo = GTK_WIDGET (gtk_builder_get_object (builder, "device_combo"));
    ui->priv->device_model = gtk_combo_box_get_model (GTK_COMBO_BOX (ui->priv->device_combo));
    ui->priv->mode_combo = GTK_WIDGET (gtk_builder_get_object (builder, "mode_combo"));
    ui->priv->preview_area = GTK_WIDGET (gtk_builder_get_object (builder, "preview_area"));

    renderer = gtk_cell_renderer_text_new();
    gtk_cell_layout_pack_start (GTK_CELL_LAYOUT (ui->priv->device_combo), renderer, TRUE);
    gtk_cell_layout_add_attribute (GTK_CELL_LAYOUT (ui->priv->device_combo), renderer, "text", 1);

    renderer = gtk_cell_renderer_text_new();
    gtk_cell_layout_pack_start (GTK_CELL_LAYOUT (ui->priv->mode_combo), renderer, TRUE);
    gtk_cell_layout_add_attribute (GTK_CELL_LAYOUT (ui->priv->mode_combo), renderer, "text", 1);
    gtk_combo_box_set_active (GTK_COMBO_BOX (ui->priv->mode_combo), 0);

    /* Load previously detected scanners and select the last used one */
    load_device_cache (ui);
    device = gconf_client_get_string(ui->priv->client, "/apps/simple-scan/selected_device", NULL);
    if (device && find_scan_device (ui, device, &iter)) {
        gtk_combo_box_set_active_iter (GTK_COMBO_BOX (ui->priv->device_combo), &iter);
    }

    return TRUE;
}


SimpleScan *
ui_new ()
{
    return g_object_new (SIMPLE_SCAN_TYPE, NULL);
}


void
ui_set_scanning (SimpleScan *ui, gboolean scanning)
{
    ui->priv->scanning = scanning;
    if (ui->priv->scanning)
        gtk_label_set_label (GTK_LABEL (ui->priv->scan_label), "_Cancel");
    else
        gtk_label_set_label (GTK_LABEL (ui->priv->scan_label), "_Scan");
}


void
ui_set_have_scan (SimpleScan *ui, gboolean have_scan)
{
    gtk_widget_set_sensitive (ui->priv->actions_box, have_scan);
}


Orientation ui_get_orientation (SimpleScan *ui)
{
    return ui->priv->orientation;
}


void
ui_redraw_preview (SimpleScan *ui)
{
    gtk_widget_queue_draw (ui->priv->preview_area);    
}


void
ui_show_error (SimpleScan *ui, const gchar *error_title, const gchar *error_text)
{
    GtkWidget *dialog;

    dialog = gtk_message_dialog_new (GTK_WINDOW (ui->priv->window),
                                     GTK_DIALOG_MODAL,
                                     GTK_MESSAGE_WARNING,
                                     GTK_BUTTONS_CLOSE,
                                     "%s", error_title);
    gtk_message_dialog_format_secondary_text (GTK_MESSAGE_DIALOG (dialog),
                                              "%s", error_text);

    gtk_dialog_run (GTK_DIALOG (dialog));
    gtk_widget_destroy (dialog);
}


void
ui_start (SimpleScan *ui)
{
    if (gtk_tree_model_iter_n_children (ui->priv->device_model, NULL) == 0)
        ui_show_error (ui, "No scanners detected", "Please check your scanner is connected and powered on");
}

static void
g_cclosure_user_marshal_VOID__POINTER_DOUBLE_DOUBLE (GClosure     *closure,
                                                     GValue       *return_value G_GNUC_UNUSED,
                                                     guint         n_param_values,
                                                     const GValue *param_values,
                                                     gpointer      invocation_hint G_GNUC_UNUSED,
                                                     gpointer      marshal_data)
{
    typedef void (*GMarshalFunc_VOID__POINTER_DOUBLE_DOUBLE) (gpointer     data1,
                                                              gpointer     arg_1,
                                                              gdouble      arg_2,
                                                              gdouble      arg_3,
                                                              gpointer     data2);
    register GMarshalFunc_VOID__POINTER_DOUBLE_DOUBLE callback;
    register GCClosure *cc = (GCClosure*) closure;
    register gpointer data1, data2;
    
    g_return_if_fail (n_param_values == 4);
    
    if (G_CCLOSURE_SWAP_DATA (closure))
    {
        data1 = closure->data;
        data2 = g_value_peek_pointer (param_values + 0);
    }
    else
    {
        data1 = g_value_peek_pointer (param_values + 0);
        data2 = closure->data;
    }
    callback = (GMarshalFunc_VOID__POINTER_DOUBLE_DOUBLE) (marshal_data ? marshal_data : cc->callback);
    
    callback (data1,
              g_value_get_pointer (param_values + 1),
              g_value_get_double (param_values + 2),
              g_value_get_double (param_values + 3),
              data2);
}


static void
ui_class_init (SimpleScanClass *klass)
{
    signals[RENDER_PREVIEW] =
        g_signal_new ("render-preview",
                      G_TYPE_FROM_CLASS (klass),
                      G_SIGNAL_RUN_LAST,
                      G_STRUCT_OFFSET (SimpleScanClass, render_preview),
                      NULL, NULL,
                      g_cclosure_user_marshal_VOID__POINTER_DOUBLE_DOUBLE,
                      G_TYPE_NONE, 3, G_TYPE_POINTER, G_TYPE_DOUBLE, G_TYPE_DOUBLE);
    signals[START_SCAN] =
        g_signal_new ("start-scan",
                      G_TYPE_FROM_CLASS (klass),
                      G_SIGNAL_RUN_LAST,
                      G_STRUCT_OFFSET (SimpleScanClass, start_scan),
                      NULL, NULL,
                      g_cclosure_marshal_VOID__INT,
                      G_TYPE_NONE, 1, G_TYPE_INT);
    signals[STOP_SCAN] =
        g_signal_new ("stop-scan",
                      G_TYPE_FROM_CLASS (klass),
                      G_SIGNAL_RUN_LAST,
                      G_STRUCT_OFFSET (SimpleScanClass, stop_scan),
                      NULL, NULL,
                      g_cclosure_marshal_VOID__VOID,
                      G_TYPE_NONE, 0);
    signals[SAVE] =
        g_signal_new ("save",
                      G_TYPE_FROM_CLASS (klass),
                      G_SIGNAL_RUN_LAST,
                      G_STRUCT_OFFSET (SimpleScanClass, save),
                      NULL, NULL,
                      g_cclosure_marshal_VOID__POINTER,
                      G_TYPE_NONE, 1, G_TYPE_POINTER);
    signals[PRINT] =
        g_signal_new ("print",
                      G_TYPE_FROM_CLASS (klass),
                      G_SIGNAL_RUN_LAST,
                      G_STRUCT_OFFSET (SimpleScanClass, print),
                      NULL, NULL,
                      g_cclosure_marshal_VOID__POINTER,
                      G_TYPE_NONE, 1, G_TYPE_POINTER);

    g_type_class_add_private (klass, sizeof (SimpleScanPrivate));
}


static void
ui_init (SimpleScan *ui)
{
    ui->priv = G_TYPE_INSTANCE_GET_PRIVATE (ui, SIMPLE_SCAN_TYPE, SimpleScanPrivate);

    ui->priv->client = gconf_client_get_default();
    gconf_client_add_dir(ui->priv->client, "/apps/simple-scan", GCONF_CLIENT_PRELOAD_NONE, NULL);
    
    ui->priv->scanning = FALSE;
    ui->priv->orientation = TOP_TO_BOTTOM;

    ui_load (ui);
}
