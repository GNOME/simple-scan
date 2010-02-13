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

#include <stdlib.h>
#include <string.h>
#include <glib/gi18n.h>
#include <gtk/gtk.h>
#include <gconf/gconf-client.h>
#include <math.h>

#include "ui.h"
#include "book-view.h"


enum {
    START_SCAN,
    STOP_SCAN,
    SAVE,
    EMAIL,
    QUIT,
    LAST_SIGNAL
};
static guint signals[LAST_SIGNAL] = { 0, };


struct SimpleScanPrivate
{
    GConfClient *client;
    
    GtkBuilder *builder;

    GtkWidget *window;
    GtkWidget *mode_combo;
    GtkTreeModel *mode_model;
    GtkWidget *preview_box, *preview_area, *preview_scroll;
    GtkWidget *page_delete_menuitem, *crop_rotate_menuitem;

    GtkWidget *authorize_dialog;
    GtkWidget *authorize_label;
    GtkWidget *username_entry, *password_entry;

    GtkWidget *preferences_dialog;
    GtkWidget *device_combo, *text_dpi_combo, *photo_dpi_combo;
    GtkTreeModel *device_model, *text_dpi_model, *photo_dpi_model;

    Book *book;
    BookView *book_view;
    gboolean updating_page_menu;
    gint default_page_width, default_page_height, default_page_dpi;
    Orientation default_page_orientation;
  
    gboolean have_device_list;

    gchar *default_file_name;
    gboolean scanning;

    gint window_width, window_height;
    gboolean window_is_maximized;
};

G_DEFINE_TYPE (SimpleScan, ui, G_TYPE_OBJECT);

static struct
{
   const gchar *key;
   Orientation orientation;
} orientation_keys[] = 
{
  { "top-to-bottom", TOP_TO_BOTTOM },
  { "bottom-to-top", BOTTOM_TO_TOP },
  { "left-to-right", LEFT_TO_RIGHT },
  { "right-to-left", RIGHT_TO_LEFT },
  { NULL, 0 }
};


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


void
ui_set_default_file_name (SimpleScan *ui, const gchar *default_file_name)
{
    g_free (ui->priv->default_file_name);
    ui->priv->default_file_name = g_strdup (default_file_name);
}


void
ui_authorize (SimpleScan *ui, const gchar *resource, gchar **username, gchar **password)
{
    GString *description;

    description = g_string_new ("");
    g_string_printf (description,
                     /* Label in authorization dialog.  '%s' is replaced with the name of the resource requesting authorization */
                     _("Username and password required to access '%s'"),
                     resource);

    gtk_entry_set_text (GTK_ENTRY (ui->priv->username_entry), *username ? *username : "");
    gtk_entry_set_text (GTK_ENTRY (ui->priv->password_entry), "");
    gtk_label_set_text (GTK_LABEL (ui->priv->authorize_label), description->str);
    g_string_free (description, TRUE);

    gtk_widget_show (ui->priv->authorize_dialog);
    gtk_dialog_run (GTK_DIALOG (ui->priv->authorize_dialog));
    gtk_widget_hide (ui->priv->authorize_dialog);

    *username = g_strdup (gtk_entry_get_text (GTK_ENTRY (ui->priv->username_entry)));
    *password = g_strdup (gtk_entry_get_text (GTK_ENTRY (ui->priv->password_entry)));
}

void
ui_set_scan_devices (SimpleScan *ui, GList *devices)
{
    GtkTreeIter iter;
    GList *i;
    gboolean have_iter;
    gboolean have_selection;

    if (!ui->priv->have_device_list) {
        ui->priv->have_device_list = TRUE;

        if (!devices) {
            ui_show_error (ui,
                           /* Warning displayed when no scanners are detected */
                           _("No scanners detected"),
                           /* Hint to user on why there are no scanners detected */
                           _("Please check your scanner is connected and powered on"),
                           FALSE);
        }
    }
  
    have_selection = gtk_combo_box_get_active (GTK_COMBO_BOX (ui->priv->device_combo)) >= 0;
  
    /* Remove disappeared devices */

    do {
        for (have_iter = gtk_tree_model_get_iter_first (ui->priv->device_model, &iter);
             have_iter;
             have_iter = gtk_tree_model_iter_next (ui->priv->device_model, &iter)) {
            gchar *name;

            gtk_tree_model_get (ui->priv->device_model, &iter, 0, &name, -1);
            for (i = devices; i; i = i->next)
                if (strcmp (name, ((ScanDevice *) i->data)->name) == 0)
                    break;
            g_free (name);

            /* Device was removed */
            if (i == NULL) {
                gtk_list_store_remove (GTK_LIST_STORE (ui->priv->device_model), &iter);
                break;
            }
        }
    } while (have_iter);

    /* Add new devices */
    for (i = devices; i; i = i->next) {
        ScanDevice *device = (ScanDevice *) i->data;

        if (!find_scan_device (ui, device->name, &iter)) {
            gtk_list_store_append (GTK_LIST_STORE (ui->priv->device_model), &iter);
            gtk_list_store_set (GTK_LIST_STORE (ui->priv->device_model), &iter, 0, device->name, 1, device->label, -1);

            /* Select this device if none selected */
            if (!have_selection) {
                gtk_combo_box_set_active_iter (GTK_COMBO_BOX (ui->priv->device_combo), &iter);
                have_selection = TRUE;
            }
        }
    }
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
add_default_page (SimpleScan *ui)
{
    if (book_get_n_pages (ui->priv->book) > 0)
        return;

    book_append_page (ui->priv->book,
                      ui->priv->default_page_width, ui->priv->default_page_height,
                      ui->priv->default_page_dpi,
                      ui->priv->default_page_orientation);
}


void new_button_clicked_cb (GtkWidget *widget, SimpleScan *ui);
G_MODULE_EXPORT
void
new_button_clicked_cb (GtkWidget *widget, SimpleScan *ui)
{
    book_clear (ui->priv->book);
    add_default_page (ui);
}


static void
set_document_hint (SimpleScan *ui, const gchar *document_hint)
{
    GtkTreeIter iter;

    if (gtk_tree_model_get_iter_first (ui->priv->mode_model, &iter)) {
        do {
            gchar *d;
            gboolean have_match;

            gtk_tree_model_get (ui->priv->mode_model, &iter, 0, &d, -1);
            have_match = strcmp (d, document_hint) == 0;
            g_free (d);

            if (have_match) {
                gtk_combo_box_set_active_iter (GTK_COMBO_BOX (ui->priv->mode_combo), &iter);                
                return;
            }
        } while (gtk_tree_model_iter_next (ui->priv->mode_model, &iter));
     }
}


static gint
get_text_dpi (SimpleScan *ui)
{
    GtkTreeIter iter;
    gint dpi = 200;

    if (gtk_combo_box_get_active_iter (GTK_COMBO_BOX (ui->priv->text_dpi_combo), &iter))
        gtk_tree_model_get (ui->priv->text_dpi_model, &iter, 0, &dpi, -1);
    
    return dpi;
}


static gint
get_photo_dpi (SimpleScan *ui)
{
    GtkTreeIter iter;
    gint dpi = 200;

    if (gtk_combo_box_get_active_iter (GTK_COMBO_BOX (ui->priv->photo_dpi_combo), &iter))
        gtk_tree_model_get (ui->priv->photo_dpi_model, &iter, 0, &dpi, -1);
    
    return dpi;
}


static gchar *
get_document_hint (SimpleScan *ui)
{
    GtkTreeIter iter;
    gchar *mode = NULL;

    if (gtk_combo_box_get_active_iter (GTK_COMBO_BOX (ui->priv->mode_combo), &iter))
        gtk_tree_model_get (ui->priv->mode_model, &iter, 0, &mode, -1);
    
    return mode;
}


void scan_button_clicked_cb (GtkWidget *widget, SimpleScan *ui);
G_MODULE_EXPORT
void
scan_button_clicked_cb (GtkWidget *widget, SimpleScan *ui)
{
    gchar *device, *mode;
    gint dpi;

    device = get_selected_device (ui);
    mode = get_document_hint (ui);
    if (strcmp (mode, "text") == 0) 
        dpi = get_text_dpi (ui);
    else
        dpi = get_photo_dpi (ui);
    g_signal_emit (G_OBJECT (ui), signals[START_SCAN], 0, device, dpi, mode, FALSE);
    g_free (device);
    g_free (mode);
}


void stop_scan_button_clicked_cb (GtkWidget *widget, SimpleScan *ui);
G_MODULE_EXPORT
void
stop_scan_button_clicked_cb (GtkWidget *widget, SimpleScan *ui)
{
    g_signal_emit (G_OBJECT (ui), signals[STOP_SCAN], 0);
}


void continuous_scan_button_clicked_cb (GtkWidget *widget, SimpleScan *ui);
G_MODULE_EXPORT
void
continuous_scan_button_clicked_cb (GtkWidget *widget, SimpleScan *ui)
{
    if (ui->priv->scanning) {
        g_signal_emit (G_OBJECT (ui), signals[STOP_SCAN], 0);
    } else {
        gchar *device, *mode;
        gint dpi;

        device = get_selected_device (ui);
        mode = get_document_hint (ui);
        if (strcmp (mode, "text") == 0) 
            dpi = get_text_dpi (ui);
        else
            dpi = get_photo_dpi (ui);
        g_signal_emit (G_OBJECT (ui), signals[START_SCAN], 0, device, dpi, mode, TRUE);
        g_free (device);
        g_free (mode);
    }
}


void preferences_button_clicked_cb (GtkWidget *widget, SimpleScan *ui);
G_MODULE_EXPORT
void
preferences_button_clicked_cb (GtkWidget *widget, SimpleScan *ui)
{
    gtk_window_present (GTK_WINDOW (ui->priv->preferences_dialog));
}


gboolean preferences_dialog_delete_event_cb (GtkWidget *widget, SimpleScan *ui);
G_MODULE_EXPORT
gboolean
preferences_dialog_delete_event_cb (GtkWidget *widget, SimpleScan *ui)
{
    return TRUE;
}


void preferences_dialog_response_cb (GtkWidget *widget, gint response_id, SimpleScan *ui);
G_MODULE_EXPORT
void
preferences_dialog_response_cb (GtkWidget *widget, gint response_id, SimpleScan *ui)
{
    gtk_widget_hide (ui->priv->preferences_dialog);
}


static void
page_selected_cb (BookView *view, Page *page, SimpleScan *ui)
{
    char *name = NULL;

    if (page == NULL)
        return;

    ui->priv->updating_page_menu = TRUE;
    
    if (page_has_crop (page)) {
        char *crop_name;

        // FIXME: Make more generic
        crop_name = page_get_named_crop (page);
        if (crop_name) {
            if (strcmp (crop_name, "A4") == 0)
                name = "a4_menuitem";
            else if (strcmp (crop_name, "A5") == 0)
                name = "a5_menuitem";
            else if (strcmp (crop_name, "A6") == 0)
                name = "a6_menuitem";
            else if (strcmp (crop_name, "letter") == 0)
                name = "letter_menuitem";
            else if (strcmp (crop_name, "legal") == 0)
                name = "legal_menuitem";
            else if (strcmp (crop_name, "4x6") == 0)
                name = "4x6_menuitem";
            g_free (crop_name);
        }
        else
            name = "custom_crop_menuitem";
    }
    else
        name = "no_crop_menuitem";

    gtk_check_menu_item_set_active (GTK_CHECK_MENU_ITEM (gtk_builder_get_object (ui->priv->builder, name)), TRUE);
    
    ui->priv->updating_page_menu = FALSE;
}


void rotate_left_button_clicked_cb (GtkWidget *widget, SimpleScan *ui);
G_MODULE_EXPORT
void
rotate_left_button_clicked_cb (GtkWidget *widget, SimpleScan *ui)
{
    Page *page;

    if (ui->priv->updating_page_menu)
        return;
    page = book_view_get_selected (ui->priv->book_view);
    page_rotate_left (page);
}


void rotate_right_button_clicked_cb (GtkWidget *widget, SimpleScan *ui);
G_MODULE_EXPORT
void
rotate_right_button_clicked_cb (GtkWidget *widget, SimpleScan *ui)
{
    Page *page;

    if (ui->priv->updating_page_menu)
        return;
    page = book_view_get_selected (ui->priv->book_view);
    page_rotate_right (page);
    ui->priv->default_page_orientation = page_get_orientation (page);
}


static void
set_crop (SimpleScan *ui, const gchar *crop_name)
{
    Page *page;
    
    gtk_widget_set_sensitive (ui->priv->crop_rotate_menuitem, crop_name != NULL);

    if (ui->priv->updating_page_menu)
        return;
    
    page = book_view_get_selected (ui->priv->book_view);
    if (!page)
        return;
    
    if (!crop_name) {
        page_set_no_crop (page);
        return;
    }

    if (strcmp (crop_name, "custom") == 0) {
        gint width, height, crop_width, crop_height;

        width = page_get_width (page);
        height = page_get_height (page);

        crop_width = (int) (width * 0.8 + 0.5);
        crop_height = (int) (height * 0.8 + 0.5);
        page_set_custom_crop (page, crop_width, crop_height);
        page_move_crop (page, (width - crop_width) / 2, (height - crop_height) / 2);

        return;
    }

    page_set_named_crop (page, crop_name);
}


void no_crop_menuitem_toggled_cb (GtkWidget *widget, SimpleScan *ui);
G_MODULE_EXPORT
void
no_crop_menuitem_toggled_cb (GtkWidget *widget, SimpleScan *ui)
{
    if (gtk_check_menu_item_get_active (GTK_CHECK_MENU_ITEM (widget)))
        set_crop (ui, NULL);
}


void custom_crop_menuitem_toggled_cb (GtkWidget *widget, SimpleScan *ui);
G_MODULE_EXPORT
void
custom_crop_menuitem_toggled_cb (GtkWidget *widget, SimpleScan *ui)
{
    if (gtk_check_menu_item_get_active (GTK_CHECK_MENU_ITEM (widget)))
        set_crop (ui, "custom");
}

void crop_toolbutton_clicked_cb (GtkWidget *widget, SimpleScan *ui);
G_MODULE_EXPORT
void
crop_toolbutton_clicked_cb (GtkWidget *widget, SimpleScan *ui)
{
    set_crop (ui, "custom");
}


void four_by_six_menuitem_toggled_cb (GtkWidget *widget, SimpleScan *ui);
G_MODULE_EXPORT
void
four_by_six_menuitem_toggled_cb (GtkWidget *widget, SimpleScan *ui)
{
    if (gtk_check_menu_item_get_active (GTK_CHECK_MENU_ITEM (widget)))
        set_crop (ui, "4x6");
}

                         
void legal_menuitem_toggled_cb (GtkWidget *widget, SimpleScan *ui);
G_MODULE_EXPORT
void
legal_menuitem_toggled_cb (GtkWidget *widget, SimpleScan *ui)
{
    if (gtk_check_menu_item_get_active (GTK_CHECK_MENU_ITEM (widget)))
        set_crop (ui, "legal");
}

                         
void letter_menuitem_toggled_cb (GtkWidget *widget, SimpleScan *ui);
G_MODULE_EXPORT
void
letter_menuitem_toggled_cb (GtkWidget *widget, SimpleScan *ui)
{
    if (gtk_check_menu_item_get_active (GTK_CHECK_MENU_ITEM (widget)))
        set_crop (ui, "letter");
}

                         
void a6_menuitem_toggled_cb (GtkWidget *widget, SimpleScan *ui);
G_MODULE_EXPORT
void
a6_menuitem_toggled_cb (GtkWidget *widget, SimpleScan *ui)
{
    if (gtk_check_menu_item_get_active (GTK_CHECK_MENU_ITEM (widget)))
        set_crop (ui, "A6");
}


void a5_menuitem_toggled_cb (GtkWidget *widget, SimpleScan *ui);
G_MODULE_EXPORT
void
a5_menuitem_toggled_cb (GtkWidget *widget, SimpleScan *ui)
{
    if (gtk_check_menu_item_get_active (GTK_CHECK_MENU_ITEM (widget)))
        set_crop (ui, "A5");
}

                         
void a4_menuitem_toggled_cb (GtkWidget *widget, SimpleScan *ui);
G_MODULE_EXPORT
void
a4_menuitem_toggled_cb (GtkWidget *widget, SimpleScan *ui)
{
    if (gtk_check_menu_item_get_active (GTK_CHECK_MENU_ITEM (widget)))
        set_crop (ui, "A4");
}


void crop_rotate_menuitem_activate_cb (GtkWidget *widget, SimpleScan *ui);
G_MODULE_EXPORT
void
crop_rotate_menuitem_activate_cb (GtkWidget *widget, SimpleScan *ui)
{
    Page *page;

    page = book_view_get_selected (ui->priv->book_view);
    if (!page)
        return;
    
    page_rotate_crop (page);
}


void page_delete_menuitem_activate_cb (GtkWidget *widget, SimpleScan *ui);
G_MODULE_EXPORT
void
page_delete_menuitem_activate_cb (GtkWidget *widget, SimpleScan *ui)
{
    book_delete_page (book_view_get_book (ui->priv->book_view),
                      book_view_get_selected (ui->priv->book_view));
}


static void
on_file_type_changed (GtkTreeSelection *selection, GtkWidget *dialog)
{
    GtkTreeModel *model;
    GtkTreeIter iter;
    gchar *path, *filename, *extension, *new_filename;

    if (!gtk_tree_selection_get_selected (selection, &model, &iter))
        return;

    gtk_tree_model_get (model, &iter, 1, &extension, -1);
    path = gtk_file_chooser_get_filename (GTK_FILE_CHOOSER (dialog));
    filename = g_path_get_basename (path);

    /* Replace extension */
    if (g_strrstr (filename, "."))
        new_filename = g_strdup_printf ("%.*s%s", (int)(g_strrstr (filename, ".") - filename), filename, extension);
    else
        new_filename = g_strdup_printf ("%s%s", filename, extension);
    gtk_file_chooser_set_current_name (GTK_FILE_CHOOSER (dialog), new_filename);

    g_free (path);
    g_free (filename);
    g_free (new_filename);
    g_free (extension);
}


void save_file_button_clicked_cb (GtkWidget *widget, SimpleScan *ui);
G_MODULE_EXPORT
void
save_file_button_clicked_cb (GtkWidget *widget, SimpleScan *ui)
{
    GtkWidget *dialog;
    gint response;
    GtkFileFilter *filter;
    GtkWidget *expander, *file_type_view;
    GtkListStore *file_type_store;
    GtkTreeIter iter;
    GtkTreeViewColumn *column;
    const gchar *extension;
    gint i;

    struct
    {
        gchar *label, *extension;
    } file_types[] =
    {
        /* Save dialog: Label for saving in PDF format */
        { _("PDF (multi-page document)"), ".pdf" },
        /* Save dialog: Label for saving in JPEG format */
        { _("JPEG (compressed)"), ".jpg" },
        /* Save dialog: Label for saving in PNG format */
        { _("PNG (lossless)"), ".png" },
        { NULL, NULL }
    };

    dialog = gtk_file_chooser_dialog_new (/* Save dialog: Dialog title */
                                          _("Save As..."),
                                          GTK_WINDOW (ui->priv->window),
                                          GTK_FILE_CHOOSER_ACTION_SAVE,
                                          GTK_STOCK_CANCEL, GTK_RESPONSE_CANCEL,
                                          GTK_STOCK_SAVE, GTK_RESPONSE_ACCEPT,
                                          NULL);
    gtk_file_chooser_set_do_overwrite_confirmation (GTK_FILE_CHOOSER (dialog), TRUE);
    gtk_file_chooser_set_local_only (GTK_FILE_CHOOSER (dialog), FALSE);
    gtk_file_chooser_set_current_name (GTK_FILE_CHOOSER (dialog), ui->priv->default_file_name);

    /* Filter to only show images by default */
    filter = gtk_file_filter_new ();
    gtk_file_filter_set_name (filter,
                              /* Save dialog: Filter name to show only image files */
                              _("Image Files"));
    gtk_file_filter_add_pixbuf_formats (filter);
    gtk_file_chooser_add_filter (GTK_FILE_CHOOSER (dialog), filter);
    filter = gtk_file_filter_new ();
    gtk_file_filter_set_name (filter,
                              /* Save dialog: Filter name to show all files */
                              _("All Files"));
    gtk_file_filter_add_pattern (filter, "*");
    gtk_file_chooser_add_filter (GTK_FILE_CHOOSER (dialog), filter);

    expander = gtk_expander_new_with_mnemonic (/* */
                                 _("Select File _Type"));
    gtk_expander_set_spacing (GTK_EXPANDER (expander), 5);
    gtk_file_chooser_set_extra_widget (GTK_FILE_CHOOSER (dialog), expander);
  
    extension = strstr (ui->priv->default_file_name, ".");
    if (!extension)
        extension = "";

    file_type_store = gtk_list_store_new (2, G_TYPE_STRING, G_TYPE_STRING);
    for (i = 0; file_types[i].label; i++) {
        gtk_list_store_append (file_type_store, &iter);
        gtk_list_store_set (file_type_store, &iter, 0, file_types[i].label, 1, file_types[i].extension, -1);
    }

    file_type_view = gtk_tree_view_new_with_model (GTK_TREE_MODEL (file_type_store));
    gtk_tree_view_set_headers_visible (GTK_TREE_VIEW (file_type_view), FALSE);
    gtk_tree_view_set_rules_hint (GTK_TREE_VIEW (file_type_view), TRUE);
    column = gtk_tree_view_column_new_with_attributes ("",
                                                       gtk_cell_renderer_text_new (),
                                                       "text", 0, NULL);
    gtk_tree_view_append_column (GTK_TREE_VIEW (file_type_view), column);
    gtk_container_add (GTK_CONTAINER (expander), file_type_view);

    if (gtk_tree_model_get_iter_first (GTK_TREE_MODEL (file_type_store), &iter)) {
        do {
            gchar *e;
            gtk_tree_model_get (GTK_TREE_MODEL (file_type_store), &iter, 1, &e, -1);
            if (strcmp (extension, e) == 0)
                gtk_tree_selection_select_iter (gtk_tree_view_get_selection (GTK_TREE_VIEW (file_type_view)), &iter);
            g_free (e);
        } while (gtk_tree_model_iter_next (GTK_TREE_MODEL (file_type_store), &iter));
    }
    g_signal_connect (gtk_tree_view_get_selection (GTK_TREE_VIEW (file_type_view)),
                      "changed",
                      G_CALLBACK (on_file_type_changed),
                      dialog);

    gtk_widget_show_all (expander);

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
           SimpleScan        *ui)
{
    cairo_t *context;
    Page *page;
    GdkPixbuf *image;
    gboolean is_landscape = FALSE;

    context = gtk_print_context_get_cairo_context (print_context);
   
    page = book_get_page (ui->priv->book, page_number);

    /* Rotate to same aspect */
    if (gtk_print_context_get_width (print_context) > gtk_print_context_get_height (print_context))
        is_landscape = TRUE;
    if (page_is_landscape (page) != is_landscape) {
        cairo_translate (context, gtk_print_context_get_width (print_context), 0);
        cairo_rotate (context, M_PI_2);
    }
   
    cairo_scale (context,
                 gtk_print_context_get_dpi_x (print_context) / page_get_dpi (page),
                 gtk_print_context_get_dpi_y (print_context) / page_get_dpi (page));

    image = page_get_cropped_image (page);
    gdk_cairo_set_source_pixbuf (context, image, 0, 0);
    cairo_paint (context);

    g_object_unref (image);
}


void email_button_clicked_cb (GtkWidget *widget, SimpleScan *ui);
G_MODULE_EXPORT
void
email_button_clicked_cb (GtkWidget *widget, SimpleScan *ui)
{
    g_signal_emit (G_OBJECT (ui), signals[EMAIL], 0);
}


void print_button_clicked_cb (GtkWidget *widget, SimpleScan *ui);
G_MODULE_EXPORT
void
print_button_clicked_cb (GtkWidget *widget, SimpleScan *ui)
{
    GtkPrintOperation *print;
    GtkPrintOperationResult result;
    GError *error = NULL;
   
    print = gtk_print_operation_new ();
    gtk_print_operation_set_n_pages (print, book_get_n_pages (ui->priv->book));
    g_signal_connect (print, "draw-page", G_CALLBACK (draw_page), ui);

    result = gtk_print_operation_run (print, GTK_PRINT_OPERATION_ACTION_PRINT_DIALOG,
                                      GTK_WINDOW (ui->priv->window), &error);

    g_object_unref (print);
}


void help_contents_menuitem_activate_cb (GtkWidget *widget, SimpleScan *ui);
G_MODULE_EXPORT
void
help_contents_menuitem_activate_cb (GtkWidget *widget, SimpleScan *ui)
{
    GdkScreen *screen;
    GError *error = NULL;

    screen = gtk_widget_get_screen (GTK_WIDGET (ui->priv->window));
    gtk_show_uri (screen, "ghelp:simple-scan", gtk_get_current_event_time (), &error);

    if (error != NULL)
    {
        GtkWidget *d;
        /* Error message displayed when unable to launch help browser */
        const char *message = _("Unable to open help file");

        d = gtk_message_dialog_new (GTK_WINDOW (ui->priv->window),
                                    GTK_DIALOG_MODAL | GTK_DIALOG_DESTROY_WITH_PARENT,
                                    GTK_MESSAGE_ERROR, GTK_BUTTONS_CLOSE,
                                    "%s", message);
        gtk_message_dialog_format_secondary_text (GTK_MESSAGE_DIALOG (d),
                                                  "%s", error->message);
        g_signal_connect (d, "response", G_CALLBACK (gtk_widget_destroy), NULL);
        gtk_window_present (GTK_WINDOW (d));

        g_error_free (error);
    }
}


void about_menuitem_activate_cb (GtkWidget *widget, SimpleScan *ui);
G_MODULE_EXPORT
void
about_menuitem_activate_cb (GtkWidget *widget, SimpleScan *ui)
{
    const gchar *authors[] = { "Robert Ancell <robert.ancell@canonical.com>", NULL };

    /* The license this software is under (GPL3+) */
    const char *license = _("This program is free software: you can redistribute it and/or modify\n"
                            "it under the terms of the GNU General Public License as published by\n"
                            "the Free Software Foundation, either version 3 of the License, or\n"
                            "(at your option) any later version.\n"
                            "\n"
                            "This program is distributed in the hope that it will be useful,\n"
                            "but WITHOUT ANY WARRANTY; without even the implied warranty of\n"
                            "MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the\n"
                            "GNU General Public License for more details.\n"
                            "\n"
                            "You should have received a copy of the GNU General Public License\n"
                            "along with this program.  If not, see <http://www.gnu.org/licenses/>.");

    /* Title of about dialog */
    const char *title = _("About Simple Scan");

    /* Description of program */
    const char *description = _("Simple document scanning tool");

    gtk_show_about_dialog (GTK_WINDOW (ui->priv->window),
                           "title", title,
                           "program-name", "Simple Scan",
                           "version", VERSION,
                           "comments", description,
                           "authors", authors,
                           "translator-credits", _("translator-credits"),
                           "website", "https://launchpad.net/simple-scan",
                           "copyright", "Copyright (C) 2009 Canonical Ltd.",
                           "license", license,
                           "wrap-license", TRUE,
                           NULL);
}


static void
quit (SimpleScan *ui)
{
    char *device, *document_type;
    gint i;

    device = get_selected_device (ui);
    if (device) {
        gconf_client_set_string(ui->priv->client, "/apps/simple-scan/selected_device", device, NULL);
        g_free (device);
    }

    document_type = get_document_hint (ui);
    gconf_client_set_string(ui->priv->client, "/apps/simple-scan/document_type", document_type, NULL);
    g_free (document_type);
    gconf_client_set_int (ui->priv->client, "/apps/simple-scan/text_dpi", get_text_dpi (ui), NULL);
    gconf_client_set_int (ui->priv->client, "/apps/simple-scan/photo_dpi", get_photo_dpi (ui), NULL);

    gconf_client_set_int(ui->priv->client, "/apps/simple-scan/window_width", ui->priv->window_width, NULL);
    gconf_client_set_int(ui->priv->client, "/apps/simple-scan/window_height", ui->priv->window_height, NULL);
    gconf_client_set_bool(ui->priv->client, "/apps/simple-scan/window_is_maximized", ui->priv->window_is_maximized, NULL);

    for (i = 0; orientation_keys[i].key != NULL && orientation_keys[i].orientation != ui->priv->default_page_orientation; i++);
    if (orientation_keys[i].key != NULL)
        gconf_client_set_string(ui->priv->client, "/apps/simple-scan/scan_direction", orientation_keys[i].key, NULL);
    gconf_client_set_int (ui->priv->client, "/apps/simple-scan/page_width", ui->priv->default_page_width, NULL);
    gconf_client_set_int (ui->priv->client, "/apps/simple-scan/page_height", ui->priv->default_page_height, NULL);
    gconf_client_set_int (ui->priv->client, "/apps/simple-scan/page_dpi", ui->priv->default_page_dpi, NULL);
   
    g_signal_emit (G_OBJECT (ui), signals[QUIT], 0);
}


void quit_menuitem_activate_cb (GtkWidget *widget, SimpleScan *ui);
G_MODULE_EXPORT
void
quit_menuitem_activate_cb (GtkWidget *widget, SimpleScan *ui)
{
    quit (ui);
}


gboolean simple_scan_window_configure_event_cb (GtkWidget *widget, GdkEventConfigure *event, SimpleScan *ui);
G_MODULE_EXPORT
gboolean
simple_scan_window_configure_event_cb (GtkWidget *widget, GdkEventConfigure *event, SimpleScan *ui)
{
    if (!ui->priv->window_is_maximized) {
        ui->priv->window_width = event->width;
        ui->priv->window_height = event->height;
    }

    return FALSE;
}


gboolean simple_scan_window_window_state_event_cb (GtkWidget *widget, GdkEventWindowState *event, SimpleScan *ui);
G_MODULE_EXPORT
gboolean
simple_scan_window_window_state_event_cb (GtkWidget *widget, GdkEventWindowState *event, SimpleScan *ui)
{
    if (event->changed_mask & GDK_WINDOW_STATE_MAXIMIZED)
        ui->priv->window_is_maximized = (event->new_window_state & GDK_WINDOW_STATE_MAXIMIZED) != 0;
    return FALSE;
}


gboolean window_delete_event_cb (GtkWidget *widget, GdkEvent *event, SimpleScan *ui);
G_MODULE_EXPORT
gboolean
window_delete_event_cb (GtkWidget *widget, GdkEvent *event, SimpleScan *ui)
{
    quit (ui);
    return TRUE;
}


static void
page_changed_cb (Page *page, SimpleScan *ui)
{
    ui->priv->default_page_width = page_get_scan_width (page);
    ui->priv->default_page_height = page_get_scan_height (page);
    ui->priv->default_page_dpi = page_get_dpi (page);
    ui->priv->default_page_orientation = page_get_orientation (page);
}


static void
page_added_cb (Book *book, Page *page, SimpleScan *ui)
{
    ui->priv->default_page_width = page_get_scan_width (page);
    ui->priv->default_page_height = page_get_scan_height (page);
    ui->priv->default_page_dpi = page_get_dpi (page);
    ui->priv->default_page_orientation = page_get_orientation (page);
    g_signal_connect (page, "image-changed", G_CALLBACK (page_changed_cb), ui);
}


static void
page_removed_cb (Book *book, Page *page, SimpleScan *ui)
{
    /* Ensure always one page */
    add_default_page (ui);
}


static void
set_dpi_combo (GtkWidget *combo, gint default_dpi, gint current_dpi)
{
    struct
    {
       gint dpi;
       const gchar *label;
    } scan_resolutions[] =
    {
      /* Preferences dialog: Label for minimum resolution in resolution list */
      { 75,  _("%d dpi (draft)") },
      /* Preferences dialog: Label for resolution value in resolution list (dpi = dots per inch) */
      { 150, _("%d dpi") },
      { 200, _("%d dpi") },
      { 400, _("%d dpi") },
      { 600, _("%d dpi") },
      { 800, _("%d dpi") },
      { 1000, _("%d dpi") },
      /* Preferences dialog: Label for maximum resolution in resolution list */      
      { 1200, _("%d dpi (high resolution)") },
      { -1, NULL }
    };
    GtkCellRenderer *renderer;
    GtkTreeModel *model;
    gint i;

    renderer = gtk_cell_renderer_text_new();
    gtk_cell_layout_pack_start (GTK_CELL_LAYOUT (combo), renderer, TRUE);
    gtk_cell_layout_add_attribute (GTK_CELL_LAYOUT (combo), renderer, "text", 1);

    model = gtk_combo_box_get_model (GTK_COMBO_BOX (combo));
    for (i = 0; scan_resolutions[i].dpi > 0; i++)
    {
        GtkTreeIter iter;
        gchar *label;
        gint dpi;

        dpi = scan_resolutions[i].dpi;

        if (dpi == default_dpi)
            label = g_strdup_printf (/* Preferences dialog: Label for default resolution in resolution list */
                                     _("%d dpi (default)"), dpi);
        else
            label = g_strdup_printf (scan_resolutions[i].label, dpi);

        gtk_list_store_append (GTK_LIST_STORE (model), &iter);
        gtk_list_store_set (GTK_LIST_STORE (model), &iter, 0, dpi, 1, label, -1);

        if (dpi == current_dpi)
            gtk_combo_box_set_active_iter (GTK_COMBO_BOX (combo), &iter);

        g_free (label);
    }
}


static void
ui_load (SimpleScan *ui)
{
    GtkBuilder *builder;
    GError *error = NULL;
    GtkCellRenderer *renderer;
    gchar *device, *document_type, *scan_direction;
    gint dpi;

    builder = ui->priv->builder = gtk_builder_new ();
    gtk_builder_add_from_file (builder, UI_DIR "simple-scan.ui", &error);
    if (error) {
        g_critical ("Unable to load UI: %s\n", error->message);
        ui_show_error (ui,
                       /* Title of dialog when cannot load required files */
                       _("Files missing"),
                       /* Description in dialog when cannot load required files */
                       _("Please check your installation"),
                       FALSE);
        exit (1);
    }
    gtk_builder_connect_signals (builder, ui);

    ui->priv->window = GTK_WIDGET (gtk_builder_get_object (builder, "simple_scan_window"));
    ui->priv->mode_combo = GTK_WIDGET (gtk_builder_get_object (builder, "mode_combo"));
    ui->priv->mode_model = gtk_combo_box_get_model (GTK_COMBO_BOX (ui->priv->mode_combo));
    ui->priv->preview_box = GTK_WIDGET (gtk_builder_get_object (builder, "preview_vbox"));
    ui->priv->preview_area = GTK_WIDGET (gtk_builder_get_object (builder, "preview_area"));
    ui->priv->preview_scroll = GTK_WIDGET (gtk_builder_get_object (builder, "preview_scrollbar"));
    ui->priv->page_delete_menuitem = GTK_WIDGET (gtk_builder_get_object (builder, "page_delete_menuitem"));
    ui->priv->crop_rotate_menuitem = GTK_WIDGET (gtk_builder_get_object (builder, "crop_rotate_menuitem"));

    renderer = gtk_cell_renderer_text_new();
    gtk_cell_layout_pack_start (GTK_CELL_LAYOUT (ui->priv->mode_combo), renderer, TRUE);
    gtk_cell_layout_add_attribute (GTK_CELL_LAYOUT (ui->priv->mode_combo), renderer, "text", 1);
    gtk_combo_box_set_active (GTK_COMBO_BOX (ui->priv->mode_combo), 0);

    ui->priv->authorize_dialog = GTK_WIDGET (gtk_builder_get_object (builder, "authorize_dialog"));
    ui->priv->authorize_label = GTK_WIDGET (gtk_builder_get_object (builder, "authorize_label"));
    ui->priv->username_entry = GTK_WIDGET (gtk_builder_get_object (builder, "username_entry"));
    ui->priv->password_entry = GTK_WIDGET (gtk_builder_get_object (builder, "password_entry"));
   
    ui->priv->preferences_dialog = GTK_WIDGET (gtk_builder_get_object (builder, "preferences_dialog"));
    ui->priv->device_combo = GTK_WIDGET (gtk_builder_get_object (builder, "device_combo"));
    ui->priv->device_model = gtk_combo_box_get_model (GTK_COMBO_BOX (ui->priv->device_combo));
    ui->priv->text_dpi_combo = GTK_WIDGET (gtk_builder_get_object (builder, "text_dpi_combo"));
    ui->priv->text_dpi_model = gtk_combo_box_get_model (GTK_COMBO_BOX (ui->priv->text_dpi_combo));
    ui->priv->photo_dpi_combo = GTK_WIDGET (gtk_builder_get_object (builder, "photo_dpi_combo"));
    ui->priv->photo_dpi_model = gtk_combo_box_get_model (GTK_COMBO_BOX (ui->priv->photo_dpi_combo));

    dpi = gconf_client_get_int (ui->priv->client, "/apps/simple-scan/text_dpi", NULL);
    if (dpi <= 0)
        dpi = 200;
    set_dpi_combo (ui->priv->text_dpi_combo, 200, dpi);
    dpi = gconf_client_get_int (ui->priv->client, "/apps/simple-scan/photo_dpi", NULL);
    if (dpi <= 0)
        dpi = 400;
    set_dpi_combo (ui->priv->photo_dpi_combo, 400, dpi);

    renderer = gtk_cell_renderer_text_new();
    gtk_cell_layout_pack_start (GTK_CELL_LAYOUT (ui->priv->device_combo), renderer, TRUE);
    gtk_cell_layout_add_attribute (GTK_CELL_LAYOUT (ui->priv->device_combo), renderer, "text", 1);

    device = gconf_client_get_string (ui->priv->client, "/apps/simple-scan/selected_device", NULL);
    if (device) {
        GtkTreeIter iter;
        if (find_scan_device (ui, device, &iter))
            gtk_combo_box_set_active_iter (GTK_COMBO_BOX (ui->priv->device_combo), &iter);
        g_free (device);
    }
    
    document_type = gconf_client_get_string (ui->priv->client, "/apps/simple-scan/document_type", NULL);
    if (document_type) {
        set_document_hint (ui, document_type);
        g_free (document_type);
    }

    ui->priv->book_view = book_view_new ();
    g_signal_connect (ui->priv->book_view, "page-selected", G_CALLBACK (page_selected_cb), ui);
    book_view_set_widgets (ui->priv->book_view,
                           ui->priv->preview_box,
                           ui->priv->preview_area,
                           ui->priv->preview_scroll,
                           GTK_WIDGET (gtk_builder_get_object (builder, "page_menu")));

    /* Find default page details */
    scan_direction = gconf_client_get_string(ui->priv->client, "/apps/simple-scan/scan_direction", NULL);
    ui->priv->default_page_orientation = TOP_TO_BOTTOM;
    if (scan_direction) {
        gint i;
        for (i = 0; orientation_keys[i].key != NULL && strcmp (orientation_keys[i].key, scan_direction) != 0; i++);
        if (orientation_keys[i].key != NULL)
            ui->priv->default_page_orientation = orientation_keys[i].orientation;
    }
    ui->priv->default_page_width = gconf_client_get_int (ui->priv->client, "/apps/simple-scan/page_width", NULL);
    if (ui->priv->default_page_width <= 0)
        ui->priv->default_page_width = 595;
    ui->priv->default_page_height = gconf_client_get_int (ui->priv->client, "/apps/simple-scan/page_height", NULL);
    if (ui->priv->default_page_height <= 0)
        ui->priv->default_page_height = 842;
    ui->priv->default_page_dpi = gconf_client_get_int (ui->priv->client, "/apps/simple-scan/page_dpi", NULL);
    if (ui->priv->default_page_dpi <= 0)
        ui->priv->default_page_dpi = 72;

    /* Restore window size */
    ui->priv->window_width = gconf_client_get_int (ui->priv->client, "/apps/simple-scan/window_width", NULL);
    if (ui->priv->window_width <= 0)
        ui->priv->window_width = 600;
    ui->priv->window_height = gconf_client_get_int (ui->priv->client, "/apps/simple-scan/window_height", NULL);
    if (ui->priv->window_height <= 0)
        ui->priv->window_height = 400;
    g_debug ("Restoring window to %dx%d pixels", ui->priv->window_width, ui->priv->window_height);
    gtk_window_set_default_size (GTK_WINDOW (ui->priv->window), ui->priv->window_width, ui->priv->window_height);
    ui->priv->window_is_maximized = gconf_client_get_bool (ui->priv->client, "/apps/simple-scan/window_is_maximized", NULL);
    if (ui->priv->window_is_maximized) {
        g_debug ("Restoring window to maximized");
        gtk_window_maximize (GTK_WINDOW (ui->priv->window));
    }

    add_default_page (ui);
    book_view_set_book (ui->priv->book_view, ui->priv->book);
}


SimpleScan *
ui_new ()
{
    return g_object_new (SIMPLE_SCAN_TYPE, NULL);
}


Book *
ui_get_book (SimpleScan *ui)
{
    return ui->priv->book;
}


void
ui_set_selected_page (SimpleScan *ui, Page *page)
{
    book_view_select_page (ui->priv->book_view, page);
}


Page *
ui_get_selected_page (SimpleScan *ui)
{
    return book_view_get_selected (ui->priv->book_view);
}


void
ui_set_scanning (SimpleScan *ui, gboolean scanning)
{
    ui->priv->scanning = scanning;
    gtk_widget_set_sensitive (ui->priv->page_delete_menuitem, !scanning);
}


void
ui_set_have_scan (SimpleScan *ui, gboolean have_scan)
{
    //FIXME: gtk_widget_set_sensitive (ui->priv->actions_box, have_scan);
}


void
ui_show_error (SimpleScan *ui, const gchar *error_title, const gchar *error_text, gboolean change_scanner_hint)
{
    GtkWidget *dialog;

    dialog = gtk_message_dialog_new (GTK_WINDOW (ui->priv->window),
                                     GTK_DIALOG_MODAL,
                                     GTK_MESSAGE_WARNING,
                                     GTK_BUTTONS_NONE,
                                     "%s", error_title);
    if (change_scanner_hint)
        gtk_dialog_add_button (GTK_DIALOG (dialog),
                               /* Button in error dialog to open prefereces dialog and change scanner */
                               _("Change _Scanner"),
                               1);
    gtk_dialog_add_button (GTK_DIALOG (dialog), GTK_STOCK_CLOSE, 0);
    gtk_message_dialog_format_secondary_text (GTK_MESSAGE_DIALOG (dialog),
                                              "%s", error_text);

    if (gtk_dialog_run (GTK_DIALOG (dialog)) == 1) {
        gtk_widget_grab_focus (ui->priv->device_combo);
        gtk_window_present (GTK_WINDOW (ui->priv->preferences_dialog));        
    }

    gtk_widget_destroy (dialog);
}


void
ui_start (SimpleScan *ui)
{
    gtk_widget_show (ui->priv->window);
}


/* Generated with glib-genmarshal */
static void
g_cclosure_user_marshal_VOID__STRING_INT_STRING_BOOLEAN (GClosure     *closure,
                                                         GValue       *return_value G_GNUC_UNUSED,
                                                         guint         n_param_values,
                                                         const GValue *param_values,
                                                         gpointer      invocation_hint G_GNUC_UNUSED,
                                                         gpointer      marshal_data)
{
  typedef void (*GMarshalFunc_VOID__STRING_INT_STRING_BOOLEAN) (gpointer       data1,
                                                                gconstpointer  arg_1,
                                                                gint           arg_2,
                                                                gconstpointer  arg_3,
                                                                gboolean       arg_4,
                                                                gpointer       data2);
  register GMarshalFunc_VOID__STRING_INT_STRING_BOOLEAN callback;
  register GCClosure *cc = (GCClosure*) closure;
  register gpointer data1, data2;

  g_return_if_fail (n_param_values == 5);

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
  callback = (GMarshalFunc_VOID__STRING_INT_STRING_BOOLEAN) (marshal_data ? marshal_data : cc->callback);

  callback (data1,
            g_value_get_string (param_values + 1),
            g_value_get_int (param_values + 2),
            g_value_get_string (param_values + 3),
            g_value_get_boolean (param_values + 4),
            data2);
}


static void
ui_class_init (SimpleScanClass *klass)
{
    signals[START_SCAN] =
        g_signal_new ("start-scan",
                      G_TYPE_FROM_CLASS (klass),
                      G_SIGNAL_RUN_LAST,
                      G_STRUCT_OFFSET (SimpleScanClass, start_scan),
                      NULL, NULL,
                      g_cclosure_user_marshal_VOID__STRING_INT_STRING_BOOLEAN,
                      G_TYPE_NONE, 4, G_TYPE_STRING, G_TYPE_INT, G_TYPE_STRING, G_TYPE_BOOLEAN);
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
    signals[EMAIL] =
        g_signal_new ("email",
                      G_TYPE_FROM_CLASS (klass),
                      G_SIGNAL_RUN_LAST,
                      G_STRUCT_OFFSET (SimpleScanClass, email),
                      NULL, NULL,
                      g_cclosure_marshal_VOID__VOID,
                      G_TYPE_NONE, 0);
    signals[QUIT] =
        g_signal_new ("quit",
                      G_TYPE_FROM_CLASS (klass),
                      G_SIGNAL_RUN_LAST,
                      G_STRUCT_OFFSET (SimpleScanClass, quit),
                      NULL, NULL,
                      g_cclosure_marshal_VOID__VOID,
                      G_TYPE_NONE, 0);

    g_type_class_add_private (klass, sizeof (SimpleScanPrivate));
}


static void
ui_init (SimpleScan *ui)
{
    ui->priv = G_TYPE_INSTANCE_GET_PRIVATE (ui, SIMPLE_SCAN_TYPE, SimpleScanPrivate);

    ui->priv->book = book_new ();
    g_signal_connect (ui->priv->book, "page-removed", G_CALLBACK (page_removed_cb), ui);
    g_signal_connect (ui->priv->book, "page-added", G_CALLBACK (page_added_cb), ui);
   
    ui->priv->client = gconf_client_get_default();
    gconf_client_add_dir(ui->priv->client, "/apps/simple-scan", GCONF_CLIENT_PRELOAD_NONE, NULL);

    ui->priv->default_file_name = g_strdup (_("Scanned Document.pdf"));
    ui->priv->scanning = FALSE;
    ui_load (ui);   
}
