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
#include <unistd.h> // TEMP: Needed for close() in get_temporary_filename()

#include "ui.h"
#include "book-view.h"


#define DEFAULT_TEXT_DPI 150
#define DEFAULT_PHOTO_DPI 300


enum {
    START_SCAN,
    STOP_SCAN,
    EMAIL,
    QUIT,
    LAST_SIGNAL
};
static guint signals[LAST_SIGNAL] = { 0, };


struct SimpleScanPrivate
{
    GConfClient *client;

    GtkBuilder *builder;

    GtkWidget *window, *main_vbox;
    GtkWidget *info_bar, *info_bar_image, *info_bar_label;
    GtkWidget *info_bar_close_button, *info_bar_change_scanner_button;
    GtkWidget *page_delete_menuitem, *crop_rotate_menuitem;
    GtkWidget *save_menuitem, *save_as_menuitem, *save_toolbutton;
    GtkWidget *stop_menuitem, *stop_toolbutton;

    GtkWidget *text_toolbar_menuitem, *text_menu_menuitem;
    GtkWidget *photo_toolbar_menuitem, *photo_menu_menuitem;

    GtkWidget *authorize_dialog;
    GtkWidget *authorize_label;
    GtkWidget *username_entry, *password_entry;

    GtkWidget *preferences_dialog;
    GtkWidget *device_combo, *text_dpi_combo, *photo_dpi_combo, *page_side_combo, *paper_size_combo;
    GtkTreeModel *device_model, *text_dpi_model, *photo_dpi_model, *page_side_model, *paper_size_model;
    gboolean setting_devices, user_selected_device;

    gboolean have_error;
    gchar *error_title, *error_text;
    gboolean error_change_scanner_hint;

    Book *book;
    gchar *book_uri;
  
    BookView *book_view;
    gboolean updating_page_menu;
    gint default_page_width, default_page_height, default_page_dpi;
    ScanDirection default_page_scan_direction;
  
    gchar *document_hint;

    gchar *default_file_name;
    gboolean scanning;

    gint window_width, window_height;
    gboolean window_is_maximized;
};

G_DEFINE_TYPE (SimpleScan, ui, G_TYPE_OBJECT);

static struct
{
   const gchar *key;
   ScanDirection scan_direction;
} scan_direction_keys[] = 
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


static void
show_error_dialog (SimpleScan *ui, const char *error_title, const char *error_text)
{
    GtkWidget *dialog;

    dialog = gtk_message_dialog_new (GTK_WINDOW (ui->priv->window),
                                     GTK_DIALOG_MODAL,
                                     GTK_MESSAGE_WARNING,
                                     GTK_BUTTONS_NONE,
                                     "%s", error_title);
    gtk_dialog_add_button (GTK_DIALOG (dialog), GTK_STOCK_CLOSE, 0);
    gtk_message_dialog_format_secondary_text (GTK_MESSAGE_DIALOG (dialog), "%s", error_text);
    gtk_widget_destroy (dialog);
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


void device_combo_changed_cb (GtkWidget *widget, SimpleScan *ui);
G_MODULE_EXPORT
void
device_combo_changed_cb (GtkWidget *widget, SimpleScan *ui)
{
    if (ui->priv->setting_devices)
        return;
    ui->priv->user_selected_device = TRUE;
}


static void
update_info_bar (SimpleScan *ui)
{
    GtkMessageType type;
    const gchar *title, *text, *image_id;
    gchar *message;
    gboolean show_close_button = FALSE;
    gboolean show_change_scanner_button = FALSE;
  
    if (ui->priv->have_error)  {
        type = GTK_MESSAGE_ERROR;
        image_id = GTK_STOCK_DIALOG_ERROR;
        title = ui->priv->error_title;
        text = ui->priv->error_text;
        show_close_button = TRUE;
        show_change_scanner_button = ui->priv->error_change_scanner_hint;
    }
    else if (gtk_tree_model_iter_n_children (ui->priv->device_model, NULL) == 0) {
        type = GTK_MESSAGE_WARNING;
        image_id = GTK_STOCK_DIALOG_WARNING;
        /* Warning displayed when no scanners are detected */
        title = _("No scanners detected");
        /* Hint to user on why there are no scanners detected */
        text = _("Please check your scanner is connected and powered on");
    }
    else {
        gtk_widget_hide (ui->priv->info_bar);
        return;
    }

    gtk_info_bar_set_message_type (GTK_INFO_BAR (ui->priv->info_bar), type);
    gtk_image_set_from_stock (GTK_IMAGE (ui->priv->info_bar_image), image_id, GTK_ICON_SIZE_DIALOG);
    message = g_strdup_printf ("<big><b>%s</b></big>\n\n%s", title, text);
    gtk_label_set_markup (GTK_LABEL (ui->priv->info_bar_label), message);
    g_free (message);
    gtk_widget_set_visible (ui->priv->info_bar_close_button, show_close_button);  
    gtk_widget_set_visible (ui->priv->info_bar_change_scanner_button, show_change_scanner_button);
    gtk_widget_show (ui->priv->info_bar);
}


void
ui_set_scan_devices (SimpleScan *ui, GList *devices)
{
    GList *d;
    gboolean have_selection = FALSE;
    gint index;
    GtkTreeIter iter;
  
    ui->priv->setting_devices = TRUE;
 
    /* If the user hasn't chosen a scanner choose the best available one */
    if (ui->priv->user_selected_device)
        have_selection = gtk_combo_box_get_active (GTK_COMBO_BOX (ui->priv->device_combo)) >= 0;

    /* Add new devices */
    index = 0;
    for (d = devices; d; d = d->next) {
        ScanDevice *device = (ScanDevice *) d->data;
        gint n_delete = -1;

        /* Find if already exists */
        if (gtk_tree_model_iter_nth_child (ui->priv->device_model, &iter, NULL, index)) {
            gint i = 0;
            do {
                gchar *name;
                gboolean matched;

                gtk_tree_model_get (ui->priv->device_model, &iter, 0, &name, -1);
                matched = strcmp (name, device->name) == 0;
                g_free (name);

                if (matched) {
                    n_delete = i;
                    break;
                }
                i++;
            } while (gtk_tree_model_iter_next (ui->priv->device_model, &iter));
        }
      
        /* If exists, remove elements up to this one */
        if (n_delete >= 0) {
            gint i;

            /* Update label */
            gtk_list_store_set (GTK_LIST_STORE (ui->priv->device_model), &iter, 1, device->label, -1);

            for (i = 0; i < n_delete; i++) {
                gtk_tree_model_iter_nth_child (ui->priv->device_model, &iter, NULL, index);
                gtk_list_store_remove (GTK_LIST_STORE (ui->priv->device_model), &iter);
            }
        }
        else {
            gtk_list_store_insert (GTK_LIST_STORE (ui->priv->device_model), &iter, index);
            gtk_list_store_set (GTK_LIST_STORE (ui->priv->device_model), &iter, 0, device->name, 1, device->label, -1);
        }
        index++;
    }

    /* Remove any remaining devices */
    while (gtk_tree_model_iter_nth_child (ui->priv->device_model, &iter, NULL, index))
        gtk_list_store_remove (GTK_LIST_STORE (ui->priv->device_model), &iter);

    /* Select the first available device */
    if (!have_selection && devices != NULL)
        gtk_combo_box_set_active (GTK_COMBO_BOX (ui->priv->device_combo), 0);

    ui->priv->setting_devices = FALSE;

    update_info_bar (ui);
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

    if (!find_scan_device (ui, device, &iter))
        return;

    gtk_combo_box_set_active_iter (GTK_COMBO_BOX (ui->priv->device_combo), &iter);
    ui->priv->user_selected_device = TRUE;
}


static void
add_default_page (SimpleScan *ui)
{
    Page *page;

    page = book_append_page (ui->priv->book,
                             ui->priv->default_page_width,
                             ui->priv->default_page_height,
                             ui->priv->default_page_dpi,
                             ui->priv->default_page_scan_direction);
    book_view_select_page (ui->priv->book_view, page);
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


static gchar *
choose_file_location (SimpleScan *ui)
{
    GtkWidget *dialog;
    gint response;
    GtkFileFilter *filter;
    GtkWidget *expander, *file_type_view;
    GtkListStore *file_type_store;
    GtkTreeIter iter;
    GtkTreeViewColumn *column;
    const gchar *extension;
    gchar *directory, *uri = NULL;
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

    /* Get directory to save to */
    directory = gconf_client_get_string (ui->priv->client, GCONF_DIR "/save_directory", NULL);
    if (!directory || directory[0] == '\0') {
        g_free (directory);
        directory = g_strdup (g_get_user_special_dir (G_USER_DIRECTORY_DOCUMENTS));
    }

    dialog = gtk_file_chooser_dialog_new (/* Save dialog: Dialog title */
                                          _("Save As..."),
                                          GTK_WINDOW (ui->priv->window),
                                          GTK_FILE_CHOOSER_ACTION_SAVE,
                                          GTK_STOCK_CANCEL, GTK_RESPONSE_CANCEL,
                                          GTK_STOCK_SAVE, GTK_RESPONSE_ACCEPT,
                                          NULL);
    gtk_file_chooser_set_do_overwrite_confirmation (GTK_FILE_CHOOSER (dialog), TRUE);
    gtk_file_chooser_set_local_only (GTK_FILE_CHOOSER (dialog), FALSE);
    gtk_file_chooser_set_current_folder (GTK_FILE_CHOOSER (dialog), directory);
    gtk_file_chooser_set_current_name (GTK_FILE_CHOOSER (dialog), ui->priv->default_file_name);
    g_free (directory);

    /* Filter to only show images by default */
    filter = gtk_file_filter_new ();
    gtk_file_filter_set_name (filter,
                              /* Save dialog: Filter name to show only image files */
                              _("Image Files"));
    gtk_file_filter_add_pixbuf_formats (filter);
    gtk_file_filter_add_mime_type (filter, "application/pdf");
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

    if (response == GTK_RESPONSE_ACCEPT)
        uri = gtk_file_chooser_get_uri (GTK_FILE_CHOOSER (dialog));

    gconf_client_set_string (ui->priv->client, GCONF_DIR "/save_directory",
                             gtk_file_chooser_get_current_folder (GTK_FILE_CHOOSER (dialog)),
                             NULL);

    gtk_widget_destroy (dialog);

    return uri;
}


static gboolean
save_document (SimpleScan *ui, gboolean force_choose_location)
{
    gboolean result;
    gchar *uri, *uri_lower;
    GError *error = NULL;
    GFile *file;
  
    if (ui->priv->book_uri && !force_choose_location)
        uri = g_strdup (ui->priv->book_uri);
    else
        uri = choose_file_location (ui);
    if (!uri)
        return FALSE;

    file = g_file_new_for_uri (uri);

    g_debug ("Saving to '%s'", uri);

    uri_lower = g_utf8_strdown (uri, -1);
    if (g_str_has_suffix (uri_lower, ".pdf"))
        result = book_save (ui->priv->book, "pdf", file, &error);
    else if (g_str_has_suffix (uri_lower, ".ps"))
        result = book_save (ui->priv->book, "ps", file, &error);
    else if (g_str_has_suffix (uri_lower, ".png"))
        result = book_save (ui->priv->book, "png", file, &error);
    else if (g_str_has_suffix (uri_lower, ".tif") || g_str_has_suffix (uri_lower, ".tiff"))
        result = book_save (ui->priv->book, "tiff", file, &error);
    else
        result = book_save (ui->priv->book, "jpeg", file, &error);

    g_free (uri_lower);

    if (result) {
        g_free (ui->priv->book_uri);
        ui->priv->book_uri = uri;
        book_set_needs_saving (ui->priv->book, FALSE);
    }
    else {
        g_free (uri);

        g_warning ("Error saving file: %s", error->message);
        ui_show_error (ui,
                       /* Title of error dialog when save failed */
                       _("Failed to save file"),
                       error->message,
                       FALSE);
        g_clear_error (&error);
    }

    g_object_unref (file);

    return result;
}


static gboolean
prompt_to_save (SimpleScan *ui, const gchar *title, const gchar *discard_label)
{
    GtkWidget *dialog;
    gint response;

    if (!book_get_needs_saving (ui->priv->book))
        return TRUE;

    dialog = gtk_message_dialog_new (GTK_WINDOW (ui->priv->window),
                                     GTK_DIALOG_MODAL,
                                     GTK_MESSAGE_WARNING,
                                     GTK_BUTTONS_NONE,
                                     "%s", title);
    gtk_message_dialog_format_secondary_text (GTK_MESSAGE_DIALOG (dialog), "%s",
                                              /* Text in dialog warning when a document is about to be lost*/
                                              _("If you don't save, changes will be permanently lost."));
    gtk_dialog_add_button (GTK_DIALOG (dialog), discard_label, GTK_RESPONSE_NO);
    gtk_dialog_add_button (GTK_DIALOG (dialog), GTK_STOCK_CANCEL, GTK_RESPONSE_CANCEL);
    gtk_dialog_add_button (GTK_DIALOG (dialog), GTK_STOCK_SAVE, GTK_RESPONSE_YES);

    response = gtk_dialog_run (GTK_DIALOG (dialog));
    gtk_widget_destroy (dialog);
  
    switch (response) {
    case GTK_RESPONSE_YES:
        if (save_document (ui, FALSE))
            return TRUE;
        else
            return FALSE;
    case GTK_RESPONSE_CANCEL:
        return FALSE;
    case GTK_RESPONSE_NO:      
    default:
        return TRUE;
    }
}


static void
clear_document (SimpleScan *ui)
{
    book_clear (ui->priv->book);
    add_default_page (ui);
    g_free (ui->priv->book_uri);
    ui->priv->book_uri = NULL;
    book_set_needs_saving (ui->priv->book, FALSE);
    gtk_widget_set_sensitive (ui->priv->save_as_menuitem, FALSE);
}


void new_button_clicked_cb (GtkWidget *widget, SimpleScan *ui);
G_MODULE_EXPORT
void
new_button_clicked_cb (GtkWidget *widget, SimpleScan *ui)
{
    if (!prompt_to_save (ui,
                         /* Text in dialog warning when a document is about to be lost */
                         _("Save current document?"),
                         /* Button in dialog to create new document and discard unsaved document */
                         _("Discard Changes")))
        return;

    clear_document (ui);
}


static void
set_document_hint (SimpleScan *ui, const gchar *document_hint)
{
    g_free (ui->priv->document_hint);
    ui->priv->document_hint = g_strdup (document_hint);

    if (strcmp (document_hint, "text") == 0) {
        gtk_check_menu_item_set_active (GTK_CHECK_MENU_ITEM (ui->priv->text_toolbar_menuitem), TRUE);
        gtk_check_menu_item_set_active (GTK_CHECK_MENU_ITEM (ui->priv->text_menu_menuitem), TRUE);
    }
    else if (strcmp (document_hint, "photo") == 0) {
        gtk_check_menu_item_set_active (GTK_CHECK_MENU_ITEM (ui->priv->photo_toolbar_menuitem), TRUE);
        gtk_check_menu_item_set_active (GTK_CHECK_MENU_ITEM (ui->priv->photo_menu_menuitem), TRUE);
    }
}


void text_menuitem_toggled_cb (GtkWidget *widget, SimpleScan *ui);
G_MODULE_EXPORT
void
text_menuitem_toggled_cb (GtkWidget *widget, SimpleScan *ui)
{
    if (gtk_check_menu_item_get_active (GTK_CHECK_MENU_ITEM (widget)))
        set_document_hint (ui, "text");
}


void photo_menuitem_toggled_cb (GtkWidget *widget, SimpleScan *ui);
G_MODULE_EXPORT
void
photo_menuitem_toggled_cb (GtkWidget *widget, SimpleScan *ui)
{
    if (gtk_check_menu_item_get_active (GTK_CHECK_MENU_ITEM (widget)))
        set_document_hint (ui, "photo");
}


static void
set_page_side (SimpleScan *ui, const gchar *document_hint)
{
    GtkTreeIter iter;

    if (gtk_tree_model_get_iter_first (ui->priv->page_side_model, &iter)) {
        do {
            gchar *d;
            gboolean have_match;

            gtk_tree_model_get (ui->priv->page_side_model, &iter, 0, &d, -1);
            have_match = strcmp (d, document_hint) == 0;
            g_free (d);

            if (have_match) {
                gtk_combo_box_set_active_iter (GTK_COMBO_BOX (ui->priv->page_side_combo), &iter);                
                return;
            }
        } while (gtk_tree_model_iter_next (ui->priv->page_side_model, &iter));
     }
}


static void
set_paper_size (SimpleScan *ui, gint width, gint height)
{
    GtkTreeIter iter;
    gboolean have_iter;
  
    for (have_iter = gtk_tree_model_get_iter_first (ui->priv->paper_size_model, &iter);
         have_iter;
         have_iter = gtk_tree_model_iter_next (ui->priv->paper_size_model, &iter)) {
        gint w, h;

        gtk_tree_model_get (ui->priv->paper_size_model, &iter, 0, &w, 1, &h, -1);
        if (w == width && h == height)
            break;
    }
  
    if (!have_iter)
        have_iter = gtk_tree_model_get_iter_first (ui->priv->paper_size_model, &iter);
    if (have_iter)
        gtk_combo_box_set_active_iter (GTK_COMBO_BOX (ui->priv->paper_size_combo), &iter);
}


static gint
get_text_dpi (SimpleScan *ui)
{
    GtkTreeIter iter;
    gint dpi = DEFAULT_TEXT_DPI;

    if (gtk_combo_box_get_active_iter (GTK_COMBO_BOX (ui->priv->text_dpi_combo), &iter))
        gtk_tree_model_get (ui->priv->text_dpi_model, &iter, 0, &dpi, -1);
    
    return dpi;
}


static gint
get_photo_dpi (SimpleScan *ui)
{
    GtkTreeIter iter;
    gint dpi = DEFAULT_PHOTO_DPI;

    if (gtk_combo_box_get_active_iter (GTK_COMBO_BOX (ui->priv->photo_dpi_combo), &iter))
        gtk_tree_model_get (ui->priv->photo_dpi_model, &iter, 0, &dpi, -1);
    
    return dpi;
}


static gchar *
get_page_side (SimpleScan *ui)
{
    GtkTreeIter iter;
    gchar *mode = NULL;

    if (gtk_combo_box_get_active_iter (GTK_COMBO_BOX (ui->priv->page_side_combo), &iter))
        gtk_tree_model_get (ui->priv->page_side_model, &iter, 0, &mode, -1);
    
    return mode;
}


static gboolean
get_paper_size (SimpleScan *ui, gint *width, gint *height)
{
    GtkTreeIter iter;

    if (gtk_combo_box_get_active_iter (GTK_COMBO_BOX (ui->priv->paper_size_combo), &iter)) {
        gtk_tree_model_get (ui->priv->paper_size_model, &iter, 0, width, 1, height, -1);
        return TRUE;
    }
  
    return FALSE;
}


static ScanOptions *
get_scan_options (SimpleScan *ui)
{
    struct {
        const gchar *name;
        ScanMode mode;
    } profiles[] =
    {
        { "text",  SCAN_MODE_LINEART },
        { "photo", SCAN_MODE_COLOR   },
        { NULL,    SCAN_MODE_COLOR   }
    };
    gint i;
    ScanOptions *options;

    /* Find this profile */
    // FIXME: Move this into scan-profile.c
    for (i = 0; profiles[i].name && strcmp (profiles[i].name, ui->priv->document_hint) != 0; i++);
  
    options = g_malloc0 (sizeof (ScanOptions));
    options->scan_mode = profiles[i].mode;
    options->depth = 8;
    if (options->scan_mode == SCAN_MODE_COLOR)
        options->dpi = get_photo_dpi (ui);
    else
        options->dpi = get_text_dpi (ui);
    get_paper_size (ui, &options->paper_width, &options->paper_height);
  
    return options;
}


void scan_button_clicked_cb (GtkWidget *widget, SimpleScan *ui);
G_MODULE_EXPORT
void
scan_button_clicked_cb (GtkWidget *widget, SimpleScan *ui)
{
    gchar *device;
    ScanOptions *options;

    device = get_selected_device (ui);

    options = get_scan_options (ui);
    options->type = SCAN_SINGLE;
    g_signal_emit (G_OBJECT (ui), signals[START_SCAN], 0, device, options);
    g_free (device);
    g_free (options);
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
        gchar *device, *side;
        ScanOptions *options;

        device = get_selected_device (ui);
        options = get_scan_options (ui);
        side = get_page_side (ui);
        if (strcmp (side, "front") == 0)
            options->type = SCAN_ADF_FRONT;
        else if (strcmp (side, "back") == 0)
            options->type = SCAN_ADF_BACK;
        else
            options->type = SCAN_ADF_BOTH;

        g_signal_emit (G_OBJECT (ui), signals[START_SCAN], 0, device, options);
        g_free (device);
        g_free (side);
        g_free (options);
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
      
        // FIXME: Make more generic, move into page-size.c and reuse
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
    gtk_toggle_tool_button_set_active (GTK_TOGGLE_TOOL_BUTTON (gtk_builder_get_object (ui->priv->builder, "crop_toolbutton")), page_has_crop (page));

    ui->priv->updating_page_menu = FALSE;
}


// FIXME: Duplicated from simple-scan.c
static gchar *
get_temporary_filename (const gchar *prefix, const gchar *extension)
{
    gint fd;
    gchar *filename, *path;
    GError *error = NULL;

    /* NOTE: I'm not sure if this is a 100% safe strategy to use g_file_open_tmp(), close and
     * use the filename but it appears to work in practise */

    filename = g_strdup_printf ("%s-XXXXXX.%s", prefix, extension);
    fd = g_file_open_tmp (filename, &path, &error);
    g_free (filename);
    if (fd < 0) {
        g_warning ("Error saving page for viewing: %s", error->message);
        g_clear_error (&error);
        return NULL;
    }
    close (fd);

    return path;
}


static void
show_page_cb (BookView *view, Page *page, SimpleScan *ui)
{
    gchar *path;
    GFile *file;
    GdkScreen *screen;
    GError *error = NULL;
  
    path = get_temporary_filename ("scanned-page", "tiff");
    if (!path)
        return;
    file = g_file_new_for_path (path);
    g_free (path);

    screen = gtk_widget_get_screen (GTK_WIDGET (ui->priv->window));

    if (page_save (page, "tiff", file, &error)) {
        gchar *uri = g_file_get_uri (file);
        gtk_show_uri (screen, uri, gtk_get_current_event_time (), &error);
        g_free (uri);
    }

    g_object_unref (file);

    if (error) {
        show_error_dialog (ui,
                           /* Error message display when unable to preview image */
                           _("Unable to open image preview application"),
                           error->message);
        g_clear_error (&error);
    }
}


static void
show_page_menu_cb (BookView *view, SimpleScan *ui)
{
    gtk_menu_popup (GTK_MENU (gtk_builder_get_object (ui->priv->builder, "page_menu")), NULL, NULL, NULL, NULL,
                    3, gtk_get_current_event_time());
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

void crop_toolbutton_toggled_cb (GtkWidget *widget, SimpleScan *ui);
G_MODULE_EXPORT
void
crop_toolbutton_toggled_cb (GtkWidget *widget, SimpleScan *ui)
{
    if (ui->priv->updating_page_menu)
        return;
  
    if (gtk_toggle_tool_button_get_active (GTK_TOGGLE_TOOL_BUTTON (widget)))
        gtk_check_menu_item_set_active (GTK_CHECK_MENU_ITEM (gtk_builder_get_object (ui->priv->builder, "custom_crop_menuitem")), TRUE);
    else
        gtk_check_menu_item_set_active (GTK_CHECK_MENU_ITEM (gtk_builder_get_object (ui->priv->builder, "no_crop_menuitem")), TRUE);
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


void save_file_button_clicked_cb (GtkWidget *widget, SimpleScan *ui);
G_MODULE_EXPORT
void
save_file_button_clicked_cb (GtkWidget *widget, SimpleScan *ui)
{
    save_document (ui, FALSE);
}


void save_as_file_button_clicked_cb (GtkWidget *widget, SimpleScan *ui);
G_MODULE_EXPORT
void
save_as_file_button_clicked_cb (GtkWidget *widget, SimpleScan *ui)
{
    save_document (ui, TRUE);
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

    image = page_get_image (page, TRUE);
    gdk_cairo_set_source_pixbuf (context, image, 0, 0);
    cairo_paint (context);

    g_object_unref (image);
}


void email_button_clicked_cb (GtkWidget *widget, SimpleScan *ui);
G_MODULE_EXPORT
void
email_button_clicked_cb (GtkWidget *widget, SimpleScan *ui)
{
    g_signal_emit (G_OBJECT (ui), signals[EMAIL], 0, ui->priv->document_hint);
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

    if (error)
    {
        show_error_dialog (ui,
                           /* Error message displayed when unable to launch help browser */
                           _("Unable to open help file"),
                           error->message);
        g_clear_error (&error);
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
                           "logo-icon-name", "scanner",
                           "authors", authors,
                           "translator-credits", _("translator-credits"),
                           "website", "https://launchpad.net/simple-scan",
                           "copyright", "Copyright © 2009 Canonical Ltd.",
                           "license", license,
                           "wrap-license", TRUE,
                           NULL);
}


static gboolean
quit (SimpleScan *ui)
{
    char *device;
    gint paper_width = 0, paper_height = 0;
    gint i;

    if (!prompt_to_save (ui,
                         /* Text in dialog warning when a document is about to be lost */
                         _("Save document before quitting?"),
                         /* Button in dialog to quit and discard unsaved document */
                         _("Quit without Saving")))
        return FALSE;

    device = get_selected_device (ui);
    if (device) {
        gconf_client_set_string(ui->priv->client, GCONF_DIR "/selected_device", device, NULL);
        g_free (device);
    }

    gconf_client_set_string (ui->priv->client, GCONF_DIR "/document_type", ui->priv->document_hint, NULL);
    gconf_client_set_int (ui->priv->client, GCONF_DIR "/text_dpi", get_text_dpi (ui), NULL);
    gconf_client_set_int (ui->priv->client, GCONF_DIR "/photo_dpi", get_photo_dpi (ui), NULL);
    gconf_client_set_string (ui->priv->client, GCONF_DIR "/page_side", get_page_side (ui), NULL);
    get_paper_size (ui, &paper_width, &paper_height);
    gconf_client_set_int (ui->priv->client, GCONF_DIR "/paper_width", paper_width, NULL);
    gconf_client_set_int (ui->priv->client, GCONF_DIR "/paper_height", paper_height, NULL);

    gconf_client_set_int(ui->priv->client, GCONF_DIR "/window_width", ui->priv->window_width, NULL);
    gconf_client_set_int(ui->priv->client, GCONF_DIR "/window_height", ui->priv->window_height, NULL);
    gconf_client_set_bool(ui->priv->client, GCONF_DIR "/window_is_maximized", ui->priv->window_is_maximized, NULL);

    for (i = 0; scan_direction_keys[i].key != NULL && scan_direction_keys[i].scan_direction != ui->priv->default_page_scan_direction; i++);
    if (scan_direction_keys[i].key != NULL)
        gconf_client_set_string(ui->priv->client, GCONF_DIR "/scan_direction", scan_direction_keys[i].key, NULL);
    gconf_client_set_int (ui->priv->client, GCONF_DIR "/page_width", ui->priv->default_page_width, NULL);
    gconf_client_set_int (ui->priv->client, GCONF_DIR "/page_height", ui->priv->default_page_height, NULL);
    gconf_client_set_int (ui->priv->client, GCONF_DIR "/page_dpi", ui->priv->default_page_dpi, NULL);
   
    g_signal_emit (G_OBJECT (ui), signals[QUIT], 0);

    return TRUE;
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


static void
info_bar_response_cb (GtkWidget *widget, gint response_id, SimpleScan *ui)
{
    if (response_id == 1) {
        gtk_widget_grab_focus (ui->priv->device_combo);
        gtk_window_present (GTK_WINDOW (ui->priv->preferences_dialog));
    }
    else {
        ui->priv->have_error = FALSE;
        g_free (ui->priv->error_title);
        ui->priv->error_title = NULL;
        g_free (ui->priv->error_text);
        ui->priv->error_text = NULL;
        update_info_bar (ui);      
    }
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
    return !quit (ui);
}


static void
page_size_changed_cb (Page *page, SimpleScan *ui)
{
    ui->priv->default_page_width = page_get_width (page);
    ui->priv->default_page_height = page_get_height (page);
    ui->priv->default_page_dpi = page_get_dpi (page);
}


static void
page_scan_direction_changed_cb (Page *page, SimpleScan *ui)
{
    ui->priv->default_page_scan_direction = page_get_scan_direction (page);
}


static void
page_added_cb (Book *book, Page *page, SimpleScan *ui)
{
    ui->priv->default_page_width = page_get_width (page);
    ui->priv->default_page_height = page_get_height (page);
    ui->priv->default_page_dpi = page_get_dpi (page);
    ui->priv->default_page_scan_direction = page_get_scan_direction (page);
    g_signal_connect (page, "size-changed", G_CALLBACK (page_size_changed_cb), ui);
    g_signal_connect (page, "scan-direction-changed", G_CALLBACK (page_scan_direction_changed_cb), ui);
}


static void
page_removed_cb (Book *book, Page *page, SimpleScan *ui)
{
    /* If this is the last page add a new blank one */
    if (book_get_n_pages (ui->priv->book) == 1)
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
      { 300, _("%d dpi") },
      { 600, _("%d dpi") },
      /* Preferences dialog: Label for maximum resolution in resolution list */      
      { 1200, _("%d dpi (high resolution)") },
      { 2400, _("%d dpi") },
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
needs_saving_cb (Book *book, GParamSpec *param, SimpleScan *ui)
{
    gtk_widget_set_sensitive (ui->priv->save_menuitem, book_get_needs_saving (book));
    gtk_widget_set_sensitive (ui->priv->save_toolbutton, book_get_needs_saving (book));
    if (book_get_needs_saving (book))
        gtk_widget_set_sensitive (ui->priv->save_as_menuitem, TRUE);
}


static void
ui_load (SimpleScan *ui)
{
    GtkBuilder *builder;
    GError *error = NULL;
    GtkWidget *hbox;
    GtkCellRenderer *renderer;
    gchar *device, *document_type, *scan_direction, *page_side;
    gint dpi, paper_width, paper_height;

    gtk_icon_theme_append_search_path (gtk_icon_theme_get_default (), ICON_DIR);

    gtk_window_set_default_icon_name ("scanner");

    builder = ui->priv->builder = gtk_builder_new ();
    gtk_builder_add_from_file (builder, UI_DIR "simple-scan.ui", &error);
    if (error) {
        g_critical ("Unable to load UI: %s\n", error->message);
        show_error_dialog (ui,
                           /* Title of dialog when cannot load required files */
                           _("Files missing"),
                           /* Description in dialog when cannot load required files */
                           _("Please check your installation"));
        exit (1);
    }
    gtk_builder_connect_signals (builder, ui);

    ui->priv->window = GTK_WIDGET (gtk_builder_get_object (builder, "simple_scan_window"));
    ui->priv->main_vbox = GTK_WIDGET (gtk_builder_get_object (builder, "main_vbox"));
    ui->priv->page_delete_menuitem = GTK_WIDGET (gtk_builder_get_object (builder, "page_delete_menuitem"));
    ui->priv->crop_rotate_menuitem = GTK_WIDGET (gtk_builder_get_object (builder, "crop_rotate_menuitem"));
    ui->priv->save_menuitem = GTK_WIDGET (gtk_builder_get_object (builder, "save_menuitem"));
    ui->priv->save_as_menuitem = GTK_WIDGET (gtk_builder_get_object (builder, "save_as_menuitem"));
    ui->priv->save_toolbutton = GTK_WIDGET (gtk_builder_get_object (builder, "save_toolbutton"));
    ui->priv->stop_menuitem = GTK_WIDGET (gtk_builder_get_object (builder, "stop_scan_menuitem"));
    ui->priv->stop_toolbutton = GTK_WIDGET (gtk_builder_get_object (builder, "stop_toolbutton"));

    ui->priv->text_toolbar_menuitem = GTK_WIDGET (gtk_builder_get_object (builder, "text_toolbutton_menuitem"));
    ui->priv->text_menu_menuitem = GTK_WIDGET (gtk_builder_get_object (builder, "text_menuitem"));
    ui->priv->photo_toolbar_menuitem = GTK_WIDGET (gtk_builder_get_object (builder, "photo_toolbutton_menuitem"));
    ui->priv->photo_menu_menuitem = GTK_WIDGET (gtk_builder_get_object (builder, "photo_menuitem"));

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
    ui->priv->page_side_combo = GTK_WIDGET (gtk_builder_get_object (builder, "page_side_combo"));
    ui->priv->page_side_model = gtk_combo_box_get_model (GTK_COMBO_BOX (ui->priv->page_side_combo));
    ui->priv->paper_size_combo = GTK_WIDGET (gtk_builder_get_object (builder, "paper_size_combo"));
    ui->priv->paper_size_model = gtk_combo_box_get_model (GTK_COMBO_BOX (ui->priv->paper_size_combo));

    /* Add InfoBar (not supported in Glade) */
    ui->priv->info_bar = gtk_info_bar_new ();
    g_signal_connect (ui->priv->info_bar, "response", G_CALLBACK (info_bar_response_cb), ui);  
    gtk_box_pack_start (GTK_BOX(ui->priv->main_vbox), ui->priv->info_bar, FALSE, TRUE, 0);
    hbox = gtk_hbox_new (FALSE, 12);
    gtk_container_add (GTK_CONTAINER (gtk_info_bar_get_content_area (GTK_INFO_BAR (ui->priv->info_bar))), hbox);
    gtk_widget_show (hbox);

    ui->priv->info_bar_image = gtk_image_new_from_stock (GTK_STOCK_DIALOG_WARNING, GTK_ICON_SIZE_DIALOG);
    gtk_box_pack_start (GTK_BOX(hbox), ui->priv->info_bar_image, FALSE, TRUE, 0);
    gtk_widget_show (ui->priv->info_bar_image);

    ui->priv->info_bar_label = gtk_label_new (NULL);
    gtk_misc_set_alignment (GTK_MISC (ui->priv->info_bar_label), 0.0, 0.5);
    gtk_box_pack_start (GTK_BOX(hbox), ui->priv->info_bar_label, TRUE, TRUE, 0);
    gtk_widget_show (ui->priv->info_bar_label);

    ui->priv->info_bar_close_button = gtk_info_bar_add_button (GTK_INFO_BAR (ui->priv->info_bar), GTK_STOCK_CLOSE, GTK_RESPONSE_CLOSE);
    ui->priv->info_bar_change_scanner_button = gtk_info_bar_add_button (GTK_INFO_BAR (ui->priv->info_bar),
                                                                        /* Button in error infobar to open preferences dialog and change scanner */
                                                                        _("Change _Scanner"), 1);

    GtkTreeIter iter;
    gtk_list_store_append (GTK_LIST_STORE (ui->priv->paper_size_model), &iter);
    gtk_list_store_set (GTK_LIST_STORE (ui->priv->paper_size_model), &iter, 0, 0, 1, 0, 2,
                        /* Combo box value for automatic paper size */
                        _("Automatic"), -1);
    gtk_list_store_append (GTK_LIST_STORE (ui->priv->paper_size_model), &iter);
    gtk_list_store_set (GTK_LIST_STORE (ui->priv->paper_size_model), &iter, 0, 1050, 1, 1480, 2, "A6", -1);
    gtk_list_store_append (GTK_LIST_STORE (ui->priv->paper_size_model), &iter);
    gtk_list_store_set (GTK_LIST_STORE (ui->priv->paper_size_model), &iter, 0, 1480, 1, 2100, 2, "A5", -1);
    gtk_list_store_append (GTK_LIST_STORE (ui->priv->paper_size_model), &iter);
    gtk_list_store_set (GTK_LIST_STORE (ui->priv->paper_size_model), &iter, 0, 2100, 1, 2970, 2, "A4", -1);
    gtk_list_store_append (GTK_LIST_STORE (ui->priv->paper_size_model), &iter);
    gtk_list_store_set (GTK_LIST_STORE (ui->priv->paper_size_model), &iter, 0, 2159, 1, 2794, 2, "Letter", -1);
    gtk_list_store_append (GTK_LIST_STORE (ui->priv->paper_size_model), &iter);
    gtk_list_store_set (GTK_LIST_STORE (ui->priv->paper_size_model), &iter, 0, 2159, 1, 3556, 2, "Legal", -1);
    gtk_list_store_append (GTK_LIST_STORE (ui->priv->paper_size_model), &iter);
    gtk_list_store_set (GTK_LIST_STORE (ui->priv->paper_size_model), &iter, 0, 1016, 1, 1524, 2, "4×6", -1);

    dpi = gconf_client_get_int (ui->priv->client, GCONF_DIR "/text_dpi", NULL);
    if (dpi <= 0)
        dpi = DEFAULT_TEXT_DPI;
    set_dpi_combo (ui->priv->text_dpi_combo, DEFAULT_TEXT_DPI, dpi);
    dpi = gconf_client_get_int (ui->priv->client, GCONF_DIR "/photo_dpi", NULL);
    if (dpi <= 0)
        dpi = DEFAULT_PHOTO_DPI;
    set_dpi_combo (ui->priv->photo_dpi_combo, DEFAULT_PHOTO_DPI, dpi);

    renderer = gtk_cell_renderer_text_new();
    gtk_cell_layout_pack_start (GTK_CELL_LAYOUT (ui->priv->device_combo), renderer, TRUE);
    gtk_cell_layout_add_attribute (GTK_CELL_LAYOUT (ui->priv->device_combo), renderer, "text", 1);

    renderer = gtk_cell_renderer_text_new();
    gtk_cell_layout_pack_start (GTK_CELL_LAYOUT (ui->priv->page_side_combo), renderer, TRUE);
    gtk_cell_layout_add_attribute (GTK_CELL_LAYOUT (ui->priv->page_side_combo), renderer, "text", 1);
    page_side = gconf_client_get_string (ui->priv->client, GCONF_DIR "/page_side", NULL);
    if (page_side) {
        set_page_side (ui, page_side);
        g_free (page_side);
    }

    renderer = gtk_cell_renderer_text_new();
    gtk_cell_layout_pack_start (GTK_CELL_LAYOUT (ui->priv->paper_size_combo), renderer, TRUE);
    gtk_cell_layout_add_attribute (GTK_CELL_LAYOUT (ui->priv->paper_size_combo), renderer, "text", 2);
    paper_width = gconf_client_get_int (ui->priv->client, GCONF_DIR "/paper_width", NULL);
    paper_height = gconf_client_get_int (ui->priv->client, GCONF_DIR "/paper_height", NULL);
    set_paper_size (ui, paper_width, paper_height);

    device = gconf_client_get_string (ui->priv->client, GCONF_DIR "/selected_device", NULL);
    if (device) {
        GtkTreeIter iter;
        if (find_scan_device (ui, device, &iter))
            gtk_combo_box_set_active_iter (GTK_COMBO_BOX (ui->priv->device_combo), &iter);
        g_free (device);
    }

    document_type = gconf_client_get_string (ui->priv->client, GCONF_DIR "/document_type", NULL);
    if (document_type) {
        set_document_hint (ui, document_type);
        g_free (document_type);
    }

    ui->priv->book_view = book_view_new (ui->priv->book);
    gtk_container_set_border_width (GTK_CONTAINER (ui->priv->book_view), 18);
    gtk_box_pack_end (GTK_BOX (ui->priv->main_vbox), GTK_WIDGET (ui->priv->book_view), TRUE, TRUE, 0);
    g_signal_connect (ui->priv->book_view, "page-selected", G_CALLBACK (page_selected_cb), ui);
    g_signal_connect (ui->priv->book_view, "show-page", G_CALLBACK (show_page_cb), ui);
    g_signal_connect (ui->priv->book_view, "show-menu", G_CALLBACK (show_page_menu_cb), ui);
    gtk_widget_show (GTK_WIDGET (ui->priv->book_view));

    /* Find default page details */
    scan_direction = gconf_client_get_string(ui->priv->client, GCONF_DIR "/scan_direction", NULL);
    ui->priv->default_page_scan_direction = TOP_TO_BOTTOM;
    if (scan_direction) {
        gint i;
        for (i = 0; scan_direction_keys[i].key != NULL && strcmp (scan_direction_keys[i].key, scan_direction) != 0; i++);
        if (scan_direction_keys[i].key != NULL)
            ui->priv->default_page_scan_direction = scan_direction_keys[i].scan_direction;
        g_free (scan_direction);
    }
    ui->priv->default_page_width = gconf_client_get_int (ui->priv->client, GCONF_DIR "/page_width", NULL);
    if (ui->priv->default_page_width <= 0)
        ui->priv->default_page_width = 595;
    ui->priv->default_page_height = gconf_client_get_int (ui->priv->client, GCONF_DIR "/page_height", NULL);
    if (ui->priv->default_page_height <= 0)
        ui->priv->default_page_height = 842;
    ui->priv->default_page_dpi = gconf_client_get_int (ui->priv->client, GCONF_DIR "/page_dpi", NULL);
    if (ui->priv->default_page_dpi <= 0)
        ui->priv->default_page_dpi = 72;

    /* Restore window size */
    ui->priv->window_width = gconf_client_get_int (ui->priv->client, GCONF_DIR "/window_width", NULL);
    if (ui->priv->window_width <= 0)
        ui->priv->window_width = 600;
    ui->priv->window_height = gconf_client_get_int (ui->priv->client, GCONF_DIR "/window_height", NULL);
    if (ui->priv->window_height <= 0)
        ui->priv->window_height = 400;
    g_debug ("Restoring window to %dx%d pixels", ui->priv->window_width, ui->priv->window_height);
    gtk_window_set_default_size (GTK_WINDOW (ui->priv->window), ui->priv->window_width, ui->priv->window_height);
    ui->priv->window_is_maximized = gconf_client_get_bool (ui->priv->client, GCONF_DIR "/window_is_maximized", NULL);
    if (ui->priv->window_is_maximized) {
        g_debug ("Restoring window to maximized");
        gtk_window_maximize (GTK_WINDOW (ui->priv->window));
    }

    if (book_get_n_pages (ui->priv->book) == 0)
        add_default_page (ui);
    book_set_needs_saving (ui->priv->book, FALSE);
    g_signal_connect (ui->priv->book, "notify::needs-saving", G_CALLBACK (needs_saving_cb), ui);
}


SimpleScan *
ui_new ()
{
    return g_object_new (SIMPLE_SCAN_TYPE, NULL);
}


Book *
ui_get_book (SimpleScan *ui)
{
    return g_object_ref (ui->priv->book);
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
    gtk_widget_set_sensitive (ui->priv->stop_menuitem, scanning);
    gtk_widget_set_sensitive (ui->priv->stop_toolbutton, scanning);
}


void
ui_show_error (SimpleScan *ui, const gchar *error_title, const gchar *error_text, gboolean change_scanner_hint)
{
    ui->priv->have_error = TRUE;
    g_free (ui->priv->error_title);
    ui->priv->error_title = g_strdup (error_title);
    g_free (ui->priv->error_text);
    ui->priv->error_text = g_strdup (error_text);
    ui->priv->error_change_scanner_hint = change_scanner_hint;
    update_info_bar (ui);
}


void
ui_start (SimpleScan *ui)
{
    gtk_widget_show (ui->priv->window);
}


/* Generated with glib-genmarshal */
static void
g_cclosure_user_marshal_VOID__STRING_POINTER (GClosure     *closure,
                                              GValue       *return_value G_GNUC_UNUSED,
                                              guint         n_param_values,
                                              const GValue *param_values,
                                              gpointer      invocation_hint G_GNUC_UNUSED,
                                              gpointer      marshal_data)
{
  typedef void (*GMarshalFunc_VOID__STRING_POINTER) (gpointer       data1,
                                                     gconstpointer  arg_1,
                                                     gconstpointer  arg_2,
                                                     gpointer       data2);
  register GMarshalFunc_VOID__STRING_POINTER callback;
  register GCClosure *cc = (GCClosure*) closure;
  register gpointer data1, data2;

  g_return_if_fail (n_param_values == 3);

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
  callback = (GMarshalFunc_VOID__STRING_POINTER) (marshal_data ? marshal_data : cc->callback);

  callback (data1,
            g_value_get_string (param_values + 1),
            g_value_get_pointer (param_values + 2),
            data2);
}


static void
ui_finalize (GObject *object)
{
    SimpleScan *ui = SIMPLE_SCAN (object);

    g_object_unref (ui->priv->client);
    ui->priv->client = NULL;
    g_object_unref (ui->priv->builder);
    ui->priv->builder = NULL;
    g_object_unref (ui->priv->book);
    ui->priv->book = NULL;
    gtk_widget_destroy (GTK_WIDGET (ui->priv->book_view));
    ui->priv->book_view = NULL;

    G_OBJECT_CLASS (ui_parent_class)->finalize (object);
}


static void
ui_class_init (SimpleScanClass *klass)
{
    GObjectClass *object_class = G_OBJECT_CLASS (klass);

    object_class->finalize = ui_finalize;

    signals[START_SCAN] =
        g_signal_new ("start-scan",
                      G_TYPE_FROM_CLASS (klass),
                      G_SIGNAL_RUN_LAST,
                      G_STRUCT_OFFSET (SimpleScanClass, start_scan),
                      NULL, NULL,
                      g_cclosure_user_marshal_VOID__STRING_POINTER,
                      G_TYPE_NONE, 2, G_TYPE_STRING, G_TYPE_POINTER);
    signals[STOP_SCAN] =
        g_signal_new ("stop-scan",
                      G_TYPE_FROM_CLASS (klass),
                      G_SIGNAL_RUN_LAST,
                      G_STRUCT_OFFSET (SimpleScanClass, stop_scan),
                      NULL, NULL,
                      g_cclosure_marshal_VOID__VOID,
                      G_TYPE_NONE, 0);
    signals[EMAIL] =
        g_signal_new ("email",
                      G_TYPE_FROM_CLASS (klass),
                      G_SIGNAL_RUN_LAST,
                      G_STRUCT_OFFSET (SimpleScanClass, email),
                      NULL, NULL,
                      g_cclosure_marshal_VOID__STRING,
                      G_TYPE_NONE, 1, G_TYPE_STRING);
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
    gconf_client_add_dir(ui->priv->client, GCONF_DIR, GCONF_CLIENT_PRELOAD_NONE, NULL);

    ui->priv->document_hint = g_strdup ("photo");
    ui->priv->default_file_name = g_strdup (_("Scanned Document.pdf"));
    ui->priv->scanning = FALSE;
    ui_load (ui);
}
