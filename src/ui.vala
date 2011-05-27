/*
 * Copyright (C) 2009-2011 Canonical Ltd.
 * Author: Robert Ancell <robert.ancell@canonical.com>
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later
 * version. See http://www.gnu.org/copyleft/gpl.html the full text of the
 * license.
 */

#if 0
define DEFAULT_TEXT_DPI 150
define DEFAULT_PHOTO_DPI 300

static struct
{
   string key;
   ScanDirection scan_direction;
} scan_direction_keys[] =
{
  { "top-to-bottom", TOP_TO_BOTTOM },
  { "bottom-to-top", BOTTOM_TO_TOP },
  { "left-to-right", LEFT_TO_RIGHT },
  { "right-to-left", RIGHT_TO_LEFT },
  { NULL, 0 }
};
#endif

public class SimpleScan
{
    private GConfClient client;

    private Gtk.Builder builder;

    private Gtk.Widget window;
    private Gtk.Widget main_vbox;
    private Gtk.Widget info_bar;
    private Gtk.Widget info_bar_image;
    private Gtk.Widget info_bar_label;
    private Gtk.Widget info_bar_close_button;
    private Gtk.Widget info_bar_change_scanner_button;
    private Gtk.Widget page_move_left_menuitem;
    private Gtk.Widget page_move_right_menuitem;
    private Gtk.Widget page_delete_menuitem;
    private Gtk.Widget crop_rotate_menuitem;
    private Gtk.Widget save_menuitem;
    private Gtk.Widget save_as_menuitem;
    private Gtk.Widget save_toolbutton;
    private Gtk.Widget stop_menuitem;
    private Gtk.Widget stop_toolbutton;

    private Gtk.Widget text_toolbar_menuitem;
    private Gtk.Widget text_menu_menuitem;
    private Gtk.Widget photo_toolbar_menuitem;
    private Gtk.Widget photo_menu_menuitem;

    private Gtk.Widget authorize_dialog;
    private Gtk.Widget authorize_label;
    private Gtk.Widget username_entry;
    private Gtk.Widget password_entry;

    private Gtk.Widget preferences_dialog;
    private Gtk.Widget device_combo;
    private Gtk.Widget text_dpi_combo;
    private Gtk.Widget photo_dpi_combo;
    private Gtk.Widget page_side_combo;
    private Gtk.Widget paper_size_combo;
    private Gtk.TreeModel device_model;
    private Gtk.TreeModel text_dpi_model;
    private Gtk.TreeModel photo_dpi_model;
    private Gtk.TreeModel page_side_model;
    private Gtk.TreeModel paper_size_model;
    private bool setting_devices;
    private bool user_selected_device;

    private bool have_error;
    private string error_title;
    private string error_text;
    private bool error_change_scanner_hint;

    private Book book;
    private string book_uri;

    private BookView book_view;
    private bool updating_page_menu;
    private int default_page_width;
    private int default_page_height;
    private int default_page_dpi;
    private ScanDirection default_page_scan_direction;

    private string document_hint = "photo";

    private string default_file_name = _("Scanned Document.pdf");
    private bool scanning = false;

    private int window_width;
    private int window_height;
    private bool window_is_maximized;

    public SimpleScan ()
    {
        book = new Book ();
        book.page_removed.connect (page_removed_cb);
        book.page_added.connect (page_added_cb);

        client = gconf_client_get_default ();
        client.add_dir (GCONF_DIR, GCONF_CLIENT_PRELOAD_NONE, null);

        load ();
    }

    private bool find_scan_device (string device, Gtk.TreeIter iter)
    {
        bool have_iter = false;

        if (gtk_tree_model_get_iter_first (device_model, iter)) {
            do {
                string d;
                gtk_tree_model_get (device_model, iter, 0, &d, -1);
                if (d == device)
                    have_iter = true;
            } while (!have_iter && gtk_tree_model_iter_next (device_model, iter));
        }

        return have_iter;
    }

    private void show_error_dialog (string error_title, string error_text)
    {
        Gtk.Widget dialog;

        dialog = gtk_message_dialog_new (GTK_WINDOW (window),
                                         GTK_DIALOG_MODAL,
                                         GTK_MESSAGE_WARNING,
                                         GTK_BUTTONS_NONE,
                                         "%s", error_title);
        gtk_dialog_add_button (GTK_DIALOG (dialog), GTK_STOCK_CLOSE, 0);
        gtk_message_dialog_format_secondary_text (GTK_MESSAGE_DIALOG (dialog), "%s", error_text);
        gtk_widget_destroy (dialog);
    }

    public void set_default_file_name (string default_file_name)
    {
        this.default_file_name = default_file_name;
    }

    public void authorize (string resource, out string username, out string password)
    {
        /* Label in authorization dialog.  '%s' is replaced with the name of the resource requesting authorization */
        var description = _("Username and password required to access '%s'").printf (resource);

        username_entry.set_text (*username ? *username : "");
        password_entry.set_text ("");
        authorize_label.set_text (description);

        authorize_dialog.show ();
        authorize_dialog.run ();
        authorize_dialog.hide ();

        username = username_entry.get_text ();
        password = password_entry.get_text ();
    }

    [CCode (cname = "G_MODULE_EXPORT device_combo_changed_cb", instance_pos = -1)]
    public void device_combo_changed_cb (Gtk.Widget widget)
    {
        if (setting_devices)
            return;
        user_selected_device = true;
    }

    private void update_info_bar ()
    {
        Gtk.MessageType type;
        string title, text, image_id;
        string message;
        bool show_close_button = false;
        bool show_change_scanner_button = false;

        if (have_error)  {
            type = GTK_MESSAGE_ERROR;
            image_id = GTK_STOCK_DIALOG_ERROR;
            title = error_title;
            text = error_text;
            show_close_button = true;
            show_change_scanner_button = error_change_scanner_hint;
        }
        else if (gtk_tree_model_iter_n_children (device_model, null) == 0) {
            type = GTK_MESSAGE_WARNING;
            image_id = GTK_STOCK_DIALOG_WARNING;
            /* Warning displayed when no scanners are detected */
            title = _("No scanners detected");
            /* Hint to user on why there are no scanners detected */
            text = _("Please check your scanner is connected and powered on");
        }
        else {
            gtk_widget_hide (info_bar);
            return;
        }

        gtk_info_bar_set_message_type (GTK_INFO_BAR (info_bar), type);
        gtk_image_set_from_stock (GTK_IMAGE (info_bar_image), image_id, GTK_ICON_SIZE_DIALOG);
        message = "<big><b>%s</b></big>\n\n%s".printf (title, text);
        gtk_label_set_markup (GTK_LABEL (info_bar_label), message);
        gtk_widget_set_visible (info_bar_close_button, show_close_button);
        gtk_widget_set_visible (info_bar_change_scanner_button, show_change_scanner_button);
        gtk_widget_show (info_bar);
    }

    public void set_scan_devices (List<ScanDevice> devices)
    {
        bool have_selection = false;
        int index;
        Gtk.TreeIter iter;

        setting_devices = true;

        /* If the user hasn't chosen a scanner choose the best available one */
        if (user_selected_device)
            have_selection = gtk_combo_box_get_active (GTK_COMBO_BOX (device_combo)) >= 0;

        /* Add new devices */
        index = 0;
        foreach (var device in devices)
        {
            int n_delete = -1;

            /* Find if already exists */
            if (gtk_tree_model_iter_nth_child (device_model, &iter, null, index)) {
                int i = 0;
                do {
                    string name;
                    bool matched;

                    gtk_tree_model_get (device_model, &iter, 0, &name, -1);
                    matched = name == device->name;

                    if (matched) {
                        n_delete = i;
                        break;
                    }
                    i++;
                } while (gtk_tree_model_iter_next (device_model, &iter));
            }

            /* If exists, remove elements up to this one */
            if (n_delete >= 0) {
                int i;

                /* Update label */
                gtk_list_store_set (GTK_LIST_STORE (device_model), &iter, 1, device->label, -1);

                for (i = 0; i < n_delete; i++) {
                    gtk_tree_model_iter_nth_child (device_model, &iter, null, index);
                    gtk_list_store_remove (GTK_LIST_STORE (device_model), &iter);
                }
            }
            else {
                gtk_list_store_insert (GTK_LIST_STORE (device_model), &iter, index);
                gtk_list_store_set (GTK_LIST_STORE (device_model), &iter, 0, device->name, 1, device->label, -1);
            }
            index++;
        }

        /* Remove any remaining devices */
        while (gtk_tree_model_iter_nth_child (device_model, &iter, null, index))
            gtk_list_store_remove (GTK_LIST_STORE (device_model), &iter);

        /* Select the first available device */
        if (!have_selection && devices != null)
            gtk_combo_box_set_active (GTK_COMBO_BOX (device_combo), 0);

        setting_devices = false;

        update_info_bar ();
    }

    private string get_selected_device ()
    {
        Gtk.TreeIter iter;

        if (gtk_combo_box_get_active_iter (GTK_COMBO_BOX (device_combo), &iter)) {
            string device;
            gtk_tree_model_get (device_model, &iter, 0, &device, -1);
            return device;
        }

        return null;
    }

    public void set_selected_device (string device)
    {
        Gtk.TreeIter iter;

        if (!find_scan_device (device, out iter))
            return;

        device_combo.set_active_iter (iter);
        user_selected_device = true;
    }

    private void add_default_page ()
    {
        var page = book.append_page (default_page_width,
                                     default_page_height,
                                     default_page_dpi,
                                     default_page_scan_direction);
        book_view.select_page (page);
    }

    private void on_file_type_changed (Gtk.TreeSelection selection, Gtk.Widget dialog)
    {
        Gtk.TreeModel model;
        Gtk.TreeIter iter;
        string path, filename, extension, new_filename;

        if (!gtk_tree_selection_get_selected (selection, &model, &iter))
            return;

        gtk_tree_model_get (model, &iter, 1, &extension, -1);
        path = gtk_file_chooser_get_filename (GTK_FILE_CHOOSER (dialog));
        filename = g_path_get_basename (path);

        /* Replace extension */
        if (g_strrstr (filename, "."))
            new_filename = "%.*s%s".printf ((int)(g_strrstr (filename, ".") - filename), filename, extension);
        else
            new_filename = "%s%s".printf (filename, extension);
        gtk_file_chooser_set_current_name (GTK_FILE_CHOOSER (dialog), new_filename);

    }

    private string choose_file_location ()
    {
        Gtk.Widget dialog;
        int response;
        Gtk.FileFilter filter;
        Gtk.Widget expander, file_type_view;
        Gtk.ListStore file_type_store;
        Gtk.TreeIter iter;
        Gtk.TreeViewColumn column;
        string extension;
        string directory, uri = null;
        int i;

        /* Get directory to save to */
        directory = gconf_client_get_string (client, GCONF_DIR + "/save_directory", null);
        if (!directory || directory[0] == '\0') {
            directory = Environment.get_user_special_dir (G_USER_DIRECTORY_DOCUMENTS);
        }

        dialog = gtk_file_chooser_dialog_new (/* Save dialog: Dialog title */
                                              _("Save As..."),
                                              GTK_WINDOW (window),
                                              GTK_FILE_CHOOSER_ACTION_SAVE,
                                              GTK_STOCK_CANCEL, GTK_RESPONSE_CANCEL,
                                              GTK_STOCK_SAVE, GTK_RESPONSE_ACCEPT,
                                              null);
        gtk_file_chooser_set_do_overwrite_confirmation (GTK_FILE_CHOOSER (dialog), true);
        gtk_file_chooser_set_local_only (GTK_FILE_CHOOSER (dialog), false);
        gtk_file_chooser_set_current_folder (GTK_FILE_CHOOSER (dialog), directory);
        gtk_file_chooser_set_current_name (GTK_FILE_CHOOSER (dialog), default_file_name);

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

        extension = strstr (default_file_name, ".");
        if (!extension)
            extension = "";

        file_type_store = gtk_list_store_new (2, G_TYPE_STRING, G_TYPE_STRING);
        gtk_list_store_append (file_type_store, &iter);
        gtk_list_store_set (file_type_store, &iter,
                            /* Save dialog: Label for saving in PDF format */
                            0, _("PDF (multi-page document)"),
                            1, ".pdf",
                            -1);
        gtk_list_store_append (file_type_store, &iter);
        gtk_list_store_set (file_type_store, &iter,
                            /* Save dialog: Label for saving in JPEG format */
                            0, _("JPEG (compressed)"),
                            1, ".jpg",
                            -1);
        gtk_list_store_append (file_type_store, &iter);
        gtk_list_store_set (file_type_store, &iter,
                            /* Save dialog: Label for saving in PNG format */
                            0, _("PNG (lossless)"),
                            1, ".png",
                            -1);

        file_type_view = gtk_tree_view_new_with_model (GTK_TREE_MODEL (file_type_store));
        gtk_tree_view_set_headers_visible (GTK_TREE_VIEW (file_type_view), false);
        gtk_tree_view_set_rules_hint (GTK_TREE_VIEW (file_type_view), true);
        column = gtk_tree_view_column_new_with_attributes ("",
                                                           gtk_cell_renderer_text_new (),
                                                           "text", 0, null);
        gtk_tree_view_append_column (GTK_TREE_VIEW (file_type_view), column);
        gtk_container_add (GTK_CONTAINER (expander), file_type_view);

        if (gtk_tree_model_get_iter_first (GTK_TREE_MODEL (file_type_store), &iter)) {
            do {
                string e;
                gtk_tree_model_get (GTK_TREE_MODEL (file_type_store), &iter, 1, &e, -1);
                if (extension == e)
                    gtk_tree_selection_select_iter (gtk_tree_view_get_selection (GTK_TREE_VIEW (file_type_view)), &iter);
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

        gconf_client_set_string (client, GCONF_DIR + "/save_directory",
                                 gtk_file_chooser_get_current_folder (GTK_FILE_CHOOSER (dialog)),
                                 null);

        gtk_widget_destroy (dialog);

        return uri;
    }

    private bool save_document (bool force_choose_location)
    {
        bool result;
        string uri, uri_lower;
        GError error = null;
        GFile file;

        if (book_uri && !force_choose_location)
            uri = book_uri;
        else
            uri = choose_file_location ();
        if (!uri)
            return false;

        file = g_file_new_for_uri (uri);

        g_debug ("Saving to '%s'", uri);

        uri_lower = g_utf8_strdown (uri, -1);
        if (g_str_has_suffix (uri_lower, ".pdf"))
            result = book.save ("pdf", file, &error);
        else if (g_str_has_suffix (uri_lower, ".ps"))
            result = book.save ("ps", file, &error);
        else if (g_str_has_suffix (uri_lower, ".png"))
            result = book.save ("png", file, &error);
        else if (g_str_has_suffix (uri_lower, ".tif") || g_str_has_suffix (uri_lower, ".tiff"))
            result = book.save ("tiff", file, &error);
        else
            result = book.save ("jpeg", file, &error);

        if (result) {
            book_uri = uri;
            book.set_needs_saving (false);
        }
        else {
            g_warning ("Error saving file: %s", error->message);
            show_error (ui,
                           /* Title of error dialog when save failed */
                           _("Failed to save file"),
                           error->message,
                           false);
            g_clear_error (&error);
        }

        g_object_unref (file);

        return result;
    }

    private bool prompt_to_save (string title, string discard_label)
    {
        Gtk.Widget dialog;
        int response;

        if (!book.get_needs_saving ())
            return true;

        dialog = gtk_message_dialog_new (GTK_WINDOW (window),
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
            if (save_document (false))
                return true;
            else
                return false;
        case GTK_RESPONSE_CANCEL:
            return false;
        case GTK_RESPONSE_NO:
        default:
            return true;
        }
    }

    private void clear_document ()
    {
        book.clear ();
        add_default_page ();
        book_uri = null;
        book.set_needs_saving (false);
        gtk_widget_set_sensitive (save_as_menuitem, false);
    }

    [CCode (cname = "G_MODULE_EXPORT new_button_clicked_cb", instance_pos = -1)]
    public void new_button_clicked_cb (Gtk.Widget widget)
    {
        if (!prompt_to_save (ui,
                             /* Text in dialog warning when a document is about to be lost */
                             _("Save current document?"),
                             /* Button in dialog to create new document and discard unsaved document */
                             _("Discard Changes")))
            return;

        clear_document ();
    }

    private void set_document_hint (string document_hint)
    {
        this.document_hint = document_hint;

        if (document_hint == "text") {
            gtk_check_menu_item_set_active (GTK_CHECK_MENU_ITEM (text_toolbar_menuitem), true);
            gtk_check_menu_item_set_active (GTK_CHECK_MENU_ITEM (text_menu_menuitem), true);
        }
        else if (document_hint == "photo") {
            gtk_check_menu_item_set_active (GTK_CHECK_MENU_ITEM (photo_toolbar_menuitem), true);
            gtk_check_menu_item_set_active (GTK_CHECK_MENU_ITEM (photo_menu_menuitem), true);
        }
    }

    [CCode (cname = "G_MODULE_EXPORT text_menuitem_toggled_cb", instance_pos = -1)]
    public void text_menuitem_toggled_cb (Gtk.Widget widget)
    {
        if (gtk_check_menu_item_get_active (GTK_CHECK_MENU_ITEM (widget)))
            set_document_hint ("text");
    }

    [CCode (cname = "G_MODULE_EXPORT photo_menuitem_toggled_cb", instance_pos = -1)]
    public void photo_menuitem_toggled_cb (Gtk.Widget widget)
    {
        if (gtk_check_menu_item_get_active (GTK_CHECK_MENU_ITEM (widget)))
            set_document_hint ("photo");
    }

    private void set_page_side (string document_hint)
    {
        Gtk.TreeIter iter;

        if (gtk_tree_model_get_iter_first (page_side_model, &iter)) {
            do {
                string d;
                bool have_match;

                gtk_tree_model_get (page_side_model, &iter, 0, &d, -1);
                have_match = d == document_hint;

                if (have_match) {
                    gtk_combo_box_set_active_iter (GTK_COMBO_BOX (page_side_combo), &iter);
                    return;
                }
            } while (gtk_tree_model_iter_next (page_side_model, &iter));
         }
    }

    private void set_paper_size (int width, int height)
    {
        Gtk.TreeIter iter;
        bool have_iter;

        for (have_iter = gtk_tree_model_get_iter_first (paper_size_model, &iter);
             have_iter;
             have_iter = gtk_tree_model_iter_next (paper_size_model, &iter)) {
            int w, h;

            gtk_tree_model_get (paper_size_model, &iter, 0, &w, 1, &h, -1);
            if (w == width && h == height)
                break;
        }

        if (!have_iter)
            have_iter = gtk_tree_model_get_iter_first (paper_size_model, &iter);
        if (have_iter)
            gtk_combo_box_set_active_iter (GTK_COMBO_BOX (paper_size_combo), &iter);
    }

    private int get_text_dpi ()
    {
        Gtk.TreeIter iter;
        int dpi = DEFAULT_TEXT_DPI;

        if (gtk_combo_box_get_active_iter (GTK_COMBO_BOX (text_dpi_combo), &iter))
            gtk_tree_model_get (text_dpi_model, &iter, 0, &dpi, -1);

        return dpi;
    }

    private int get_photo_dpi ()
    {
        Gtk.TreeIter iter;
        int dpi = DEFAULT_PHOTO_DPI;

        if (gtk_combo_box_get_active_iter (GTK_COMBO_BOX (photo_dpi_combo), &iter))
            gtk_tree_model_get (photo_dpi_model, &iter, 0, &dpi, -1);

        return dpi;
    }

    private string get_page_side ()
    {
        Gtk.TreeIter iter;
        string mode = null;

        if (gtk_combo_box_get_active_iter (GTK_COMBO_BOX (page_side_combo), &iter))
            gtk_tree_model_get (page_side_model, &iter, 0, &mode, -1);

        return mode;
    }

    private bool get_paper_size (out int width, out int height)
    {
        Gtk.TreeIter iter;

        if (gtk_combo_box_get_active_iter (GTK_COMBO_BOX (paper_size_combo), &iter)) {
            gtk_tree_model_get (paper_size_model, &iter, 0, width, 1, height, -1);
            return true;
        }

        return false;
    }

    private ScanOptions get_scan_options ()
    {
        struct {
            string name;
            ScanMode mode;
            int depth;
        } profiles[] =
        {
            { "text",  SCAN_MODE_GRAY,  2 },
            { "photo", SCAN_MODE_COLOR, 8 },
            { null,    SCAN_MODE_COLOR, 8 }
        };
        int i;
        ScanOptions options;

        /* Find this profile */
        // FIXME: Move this into scan-profile.c
        for (i = 0; profiles[i].name && profiles[i].name != document_hint; i++);

        options = g_malloc0 (sizeof (ScanOptions));
        options->scan_mode = profiles[i].mode;
        options->depth = profiles[i].depth;
        if (options->scan_mode == SCAN_MODE_COLOR)
            options->dpi = get_photo_dpi ();
        else
            options->dpi = get_text_dpi ();
        get_paper_size (&options->paper_width, &options->paper_height);

        return options;
    }

    [CCode (cname = "G_MODULE_EXPORT scan_button_clicked_cb", instance_pos = -1)]
    public void scan_button_clicked_cb (Gtk.Widget widget)
    {
        string device;
        ScanOptions options;

        device = get_selected_device ();

        options = get_scan_options ();
        options->type = SCAN_SINGLE;
        g_signal_emit (G_OBJECT (ui), signals[START_SCAN], 0, device, options);
    }

    [CCode (cname = "G_MODULE_EXPORT stop_scan_button_clicked_cb", instance_pos = -1)]
    public void stop_scan_button_clicked_cb (Gtk.Widget widget)
    {
        g_signal_emit (G_OBJECT (ui), signals[STOP_SCAN], 0);
    }

    [CCode (cname = "G_MODULE_EXPORT continuous_scan_button_clicked_cb", instance_pos = -1)]
    public void continuous_scan_button_clicked_cb (Gtk.Widget widget)
    {
        if (scanning) {
            g_signal_emit (G_OBJECT (ui), signals[STOP_SCAN], 0);
        } else {
            string device, side;
            ScanOptions options;

            device = get_selected_device ();
            options = get_scan_options ();
            side = get_page_side ();
            if (side == "front")
                options->type = SCAN_ADF_FRONT;
            else if (side == "back")
                options->type = SCAN_ADF_BACK;
            else
                options->type = SCAN_ADF_BOTH;

            g_signal_emit (G_OBJECT (ui), signals[START_SCAN], 0, device, options);
        }
    }

    [CCode (cname = "G_MODULE_EXPORT preferences_button_clicked_cb", instance_pos = -1)]
    public void preferences_button_clicked_cb (Gtk.Widget widget)
    {
        gtk_window_present (GTK_WINDOW (preferences_dialog));
    }

    [CCode (cname = "G_MODULE_EXPORT preferences_dialog_delete_event_cb", instance_pos = -1)]
    public bool preferences_dialog_delete_event_cb (Gtk.Widget widget)
    {
        return true;
    }

    [CCode (cname = "G_MODULE_EXPORT preferences_dialog_response_cb", instance_pos = -1)]
    public void preferences_dialog_response_cb (Gtk.Widget widget, int response_id)
    {
        gtk_widget_hide (preferences_dialog);
    }

    private void update_page_menu ()
    {
        var book = book_view.get_book ();
        var index = book.get_page_index (book_view.get_selected ());
        gtk_widget_set_sensitive (page_move_left_menuitem, index > 0);
        gtk_widget_set_sensitive (page_move_right_menuitem, index < book.get_n_pages () - 1);
    }

    private void page_selected_cb (BookView view, Page page)
    {
        string name = null;

        if (page == null)
            return;

        updating_page_menu = true;

        update_page_menu ();

        if (page_has_crop (page)) {
            string crop_name;

            // FIXME: Make more generic, move into page-size.c and reuse
            crop_name = page_get_named_crop (page);
            if (crop_name) {
                if (crop_name == "A4")
                    name = "a4_menuitem";
                else if (crop_name == "A5")
                    name = "a5_menuitem";
                else if (crop_name == "A6")
                    name = "a6_menuitem";
                else if (crop_name == "letter")
                    name = "letter_menuitem";
                else if (crop_name == "legal")
                    name = "legal_menuitem";
                else if (crop_name == "4x6")
                    name = "4x6_menuitem";
            }
            else
                name = "custom_crop_menuitem";
        }
        else
            name = "no_crop_menuitem";

        gtk_check_menu_item_set_active (GTK_CHECK_MENU_ITEM (gtk_builder_get_object (builder, name)), true);
        gtk_toggle_tool_button_set_active (GTK_TOGGLE_TOOL_BUTTON (gtk_builder_get_object (builder, "crop_toolbutton")), page_has_crop (page));

        updating_page_menu = false;
    }

    // FIXME: Duplicated from simple-scan.c
    private string get_temporary_filename (string prefix, string extension)
    {
        int fd;
        string filename, path;
        GError error = null;

        /* NOTE: I'm not sure if this is a 100% safe strategy to use g_file_open_tmp(), close and
         * use the filename but it appears to work in practise */

        filename = "%s-XXXXXX.%s".printf (prefix, extension);
        fd = g_file_open_tmp (filename, &path, &error);
        if (fd < 0) {
            g_warning ("Error saving page for viewing: %s", error->message);
            g_clear_error (&error);
            return null;
        }
        close (fd);

        return path;
    }

    private void show_page_cb (BookView view, Page page)
    {
        string path;
        GFile file;
        GdkScreen screen;
        GError error = null;

        path = get_temporary_filename ("scanned-page", "tiff");
        if (!path)
            return;
        file = g_file_new_for_path (path);

        screen = gtk_widget_get_screen (GTK_WIDGET (window));

        if (page_save (page, "tiff", file, &error)) {
            string uri = g_file_get_uri (file);
            gtk_show_uri (screen, uri, gtk_get_current_event_time (), &error);
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

    private void show_page_menu_cb (BookView view)
    {
        gtk_menu_popup (GTK_MENU (gtk_builder_get_object (builder, "page_menu")), null, null, null, null,
                        3, gtk_get_current_event_time());
    }

    [CCode (cname = "G_MODULE_EXPORT rotate_left_button_clicked_cb", instance_pos = -1)]
    public void rotate_left_button_clicked_cb (Gtk.Widget widget)
    {
        if (updating_page_menu)
            return;
        book_view.get_selected ().rotate_left ();
    }

    [CCode (cname = "G_MODULE_EXPORT rotate_right_button_clicked_cb", instance_pos = -1)]
    public void rotate_right_button_clicked_cb (Gtk.Widget widget)
    {
        if (updating_page_menu)
            return;
        book_view.get_selected ().rotate_right ();
    }

    private void set_crop (string? crop_name)
    {
        gtk_widget_set_sensitive (crop_rotate_menuitem, crop_name != null);

        if (updating_page_menu)
            return;

        var page = book_view.get_selected ();
        if (!page)
            return;

        if (crop_name == null) {
            page.set_no_crop ();
            return;
        }
        else if (crop_name == "custom") {
            var width = page.get_width ();
            var height = page.get_height ();
            var crop_width = (int) (width * 0.8 + 0.5);
            var crop_height = (int) (height * 0.8 + 0.5);
            page.set_custom_crop (crop_width, crop_height);
            page.move_crop ((width - crop_width) / 2, (height - crop_height) / 2);
        }
        else
            page.set_named_crop (crop_name);
    }

    [CCode (cname = "G_MODULE_EXPORT no_crop_menuitem_toggled_cb", instance_pos = -1)]
    public void no_crop_menuitem_toggled_cb (Gtk.Widget widget)
    {
        if (gtk_check_menu_item_get_active (GTK_CHECK_MENU_ITEM (widget)))
            set_crop (null);
    }

    [CCode (cname = "G_MODULE_EXPORT custom_crop_menuitem_toggled_cb", instance_pos = -1)]
    public void custom_crop_menuitem_toggled_cb (Gtk.Widget widget)
    {
        if (gtk_check_menu_item_get_active (GTK_CHECK_MENU_ITEM (widget)))
            set_crop ("custom");
    }
    [CCode (cname = "G_MODULE_EXPORT crop_toolbutton_toggled_cb", instance_pos = -1)]
    public void crop_toolbutton_toggled_cb (Gtk.Widget widget)
    {
        if (updating_page_menu)
            return;

        if (gtk_toggle_tool_button_get_active (GTK_TOGGLE_TOOL_BUTTON (widget)))
            gtk_check_menu_item_set_active (GTK_CHECK_MENU_ITEM (gtk_builder_get_object (builder, "custom_crop_menuitem")), true);
        else
            gtk_check_menu_item_set_active (GTK_CHECK_MENU_ITEM (gtk_builder_get_object (builder, "no_crop_menuitem")), true);
    }

    [CCode (cname = "G_MODULE_EXPORT four_by_six_menuitem_toggled_cb", instance_pos = -1)]
    public void four_by_six_menuitem_toggled_cb (Gtk.Widget widget)
    {
        if (gtk_check_menu_item_get_active (GTK_CHECK_MENU_ITEM (widget)))
            set_crop ("4x6");
    }

    [CCode (cname = "G_MODULE_EXPORT legal_menuitem_toggled_cb", instance_pos = -1)]
    public void legal_menuitem_toggled_cb (Gtk.Widget widget)
    {
        if (gtk_check_menu_item_get_active (GTK_CHECK_MENU_ITEM (widget)))
            set_crop ("legal");
    }

    [CCode (cname = "G_MODULE_EXPORT letter_menuitem_toggled_cb", instance_pos = -1)]
    public void letter_menuitem_toggled_cb (Gtk.Widget widget)
    {
        if (gtk_check_menu_item_get_active (GTK_CHECK_MENU_ITEM (widget)))
            set_crop ("letter");
    }

    [CCode (cname = "G_MODULE_EXPORT a6_menuitem_toggled_cb", instance_pos = -1)]
    public void a6_menuitem_toggled_cb (Gtk.Widget widget)
    {
        if (gtk_check_menu_item_get_active (GTK_CHECK_MENU_ITEM (widget)))
            set_crop ("A6");
    }

    [CCode (cname = "G_MODULE_EXPORT a5_menuitem_toggled_cb", instance_pos = -1)]
    public void a5_menuitem_toggled_cb (Gtk.Widget widget)
    {
        if (gtk_check_menu_item_get_active (GTK_CHECK_MENU_ITEM (widget)))
            set_crop ("A5");
    }

    [CCode (cname = "G_MODULE_EXPORT a4_menuitem_toggled_cb", instance_pos = -1)]
    public void a4_menuitem_toggled_cb (Gtk.Widget widget)
    {
        if (gtk_check_menu_item_get_active (GTK_CHECK_MENU_ITEM (widget)))
            set_crop ("A4");
    }

    [CCode (cname = "G_MODULE_EXPORT crop_rotate_menuitem_activate_cb", instance_pos = -1)]
    public void crop_rotate_menuitem_activate_cb (Gtk.Widget widget)
    {
        Page page;

        page = book_view_get_selected (book_view);
        if (!page)
            return;

        page_rotate_crop (page);
    }

    [CCode (cname = "G_MODULE_EXPORT page_move_left_menuitem_activate_cb", instance_pos = -1)]
    public void page_move_left_menuitem_activate_cb (Gtk.Widget widget)
    {
        var book = book_view.get_book ();
        var page = book_view.get_selected ();
        var index = book.get_page_index (page);
        if (index > 0)
            book.move_page (page, index - 1);

        update_page_menu ();
    }

    [CCode (cname = "G_MODULE_EXPORT page_move_right_menuitem_activate_cb", instance_pos = -1)]
    public void page_move_right_menuitem_activate_cb (Gtk.Widget widget)
    {
        var book = book_view.get_book ();
        var page = book_view.get_selected ();
        var index = book.get_page_index (page);
        if (index < book.get_n_pages () - 1)
            book.move_page (page, book.get_page_index (page) + 1);

        update_page_menu ();
    }

    [CCode (cname = "G_MODULE_EXPORT page_delete_menuitem_activate_cb", instance_pos = -1)]
    public void page_delete_menuitem_activate_cb (Gtk.Widget widget)
    {
        book_delete_page (book_view_get_book (book_view),
                          book_view_get_selected (book_view));
    }

    [CCode (cname = "G_MODULE_EXPORT save_file_button_clicked_cb", instance_pos = -1)]
    public void save_file_button_clicked_cb (Gtk.Widget widget)
    {
        save_document (false);
    }

    [CCode (cname = "G_MODULE_EXPORT save_as_file_button_clicked_cb", instance_pos = -1)]
    public void save_as_file_button_clicked_cb (Gtk.Widget widget)
    {
        save_document (true);
    }

    private void draw_page (Gtk.PrintOperation operation,
                            Gtk.PrintContext   print_context,
                            int               page_number,
                            SimpleScan        ui)
    {
        cairo_t context;
        Page page;
        GdkPixbuf image;
        bool is_landscape = false;

        context = gtk_print_context_get_cairo_context (print_context);

        page = book.get_page (page_number);

        /* Rotate to same aspect */
        if (gtk_print_context_get_width (print_context) > gtk_print_context_get_height (print_context))
            is_landscape = true;
        if (page_is_landscape (page) != is_landscape) {
            cairo_translate (context, gtk_print_context_get_width (print_context), 0);
            cairo_rotate (context, M_PI_2);
        }

        cairo_scale (context,
                     gtk_print_context_get_dpi_x (print_context) / page.get_dpi (),
                     gtk_print_context_get_dpi_y (print_context) / page.get_dpi ());

        image = page_get_image (page, true);
        gdk_cairo_set_source_pixbuf (context, image, 0, 0);
        cairo_paint (context);

        g_object_unref (image);
    }

    [CCode (cname = "G_MODULE_EXPORT email_button_clicked_cb", instance_pos = -1)]
    public void email_button_clicked_cb (Gtk.Widget widget)
    {
        g_signal_emit (G_OBJECT (ui), signals[EMAIL], 0, document_hint);
    }

    [CCode (cname = "G_MODULE_EXPORT print_button_clicked_cb", instance_pos = -1)]
    public void print_button_clicked_cb (Gtk.Widget widget)
    {
        Gtk.PrintOperation print;
        Gtk.PrintOperationResult result;
        GError error = null;

        print = gtk_print_operation_new ();
        gtk_print_operation_set_n_pages (print, book.get_n_pages ());
        g_signal_connect (print, "draw-page", G_CALLBACK (draw_page), ui);

        result = gtk_print_operation_run (print, GTK_PRINT_OPERATION_ACTION_PRINT_DIALOG,
                                          GTK_WINDOW (window), &error);

        g_object_unref (print);
    }

    [CCode (cname = "G_MODULE_EXPORT help_contents_menuitem_activate_cb", instance_pos = -1)]
    public void help_contents_menuitem_activate_cb (Gtk.Widget widget)
    {
        GdkScreen screen;
        GError error = null;

        screen = gtk_widget_get_screen (GTK_WIDGET (window));
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

    [CCode (cname = "G_MODULE_EXPORT about_menuitem_activate_cb", instance_pos = -1)]
    public void about_menuitem_activate_cb (Gtk.Widget widget)
    {
        string authors[] = { "Robert Ancell <robert.ancell@canonical.com>", null };

        /* The license this software is under (GPL3+) */
        string license = _("This program is free software: you can redistribute it and/or modify\nit under the terms of the GNU General Public License as published by\nthe Free Software Foundation, either version 3 of the License, or\n(at your option) any later version.\n\nThis program is distributed in the hope that it will be useful,\nbut WITHOUT ANY WARRANTY; without even the implied warranty of\nMERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the\nGNU General Public License for more details.\n\nYou should have received a copy of the GNU General Public License\nalong with this program.  If not, see <http://www.gnu.org/licenses/>.");

        /* Title of about dialog */
        string title = _("About Simple Scan");

        /* Description of program */
        string description = _("Simple document scanning tool");

        gtk_show_about_dialog (GTK_WINDOW (window),
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
                               "wrap-license", true,
                               null);
    }

    private bool quit ()
    {
        string device;
        int paper_width = 0, paper_height = 0;
        int i;

        if (!prompt_to_save (ui,
                             /* Text in dialog warning when a document is about to be lost */
                             _("Save document before quitting?"),
                             /* Button in dialog to quit and discard unsaved document */
                             _("Quit without Saving")))
            return false;

        device = get_selected_device ();
        if (device) {
            gconf_client_set_string(client, GCONF_DIR + "/selected_device", device, null);
        }

        gconf_client_set_string (client, GCONF_DIR + "/document_type", document_hint, null);
        gconf_client_set_int (client, GCONF_DIR + "/text_dpi", get_text_dpi (), null);
        gconf_client_set_int (client, GCONF_DIR + "/photo_dpi", get_photo_dpi (), null);
        gconf_client_set_string (client, GCONF_DIR + "/page_side", get_page_side (), null);
        get_paper_size (&paper_width, &paper_height);
        gconf_client_set_int (client, GCONF_DIR + "/paper_width", paper_width, null);
        gconf_client_set_int (client, GCONF_DIR + "/paper_height", paper_height, null);

        gconf_client_set_int(client, GCONF_DIR + "/window_width", window_width, null);
        gconf_client_set_int(client, GCONF_DIR + "/window_height", window_height, null);
        gconf_client_set_bool(client, GCONF_DIR + "/window_is_maximized", window_is_maximized, null);

        for (i = 0; scan_direction_keys[i].key != null && scan_direction_keys[i].scan_direction != default_page_scan_direction; i++);
        if (scan_direction_keys[i].key != null)
            gconf_client_set_string(client, GCONF_DIR + "/scan_direction", scan_direction_keys[i].key, null);
        gconf_client_set_int (client, GCONF_DIR + "/page_width", default_page_width, null);
        gconf_client_set_int (client, GCONF_DIR + "/page_height", default_page_height, null);
        gconf_client_set_int (client, GCONF_DIR + "/page_dpi", default_page_dpi, null);

        g_signal_emit (G_OBJECT (ui), signals[QUIT], 0);

        return true;
    }

    [CCode (cname = "G_MODULE_EXPORT quit_menuitem_activate_cb", instance_pos = -1)]
    public void quit_menuitem_activate_cb (Gtk.Widget widget)
    {
        quit ();
    }

    [CCode (cname = "G_MODULE_EXPORT simple_scan_window_configure_event_cb", instance_pos = -1)]
    public bool simple_scan_window_configure_event_cb (Gtk.Widget widget, GdkEventConfigure event)
    {
        if (!window_is_maximized) {
            window_width = event->width;
            window_height = event->height;
        }

        return false;
    }

    private void info_bar_response_cb (Gtk.Widget widget, int response_id)
    {
        if (response_id == 1) {
            gtk_widget_grab_focus (device_combo);
            gtk_window_present (GTK_WINDOW (preferences_dialog));
        }
        else {
            have_error = false;
            error_title = null;
            error_text = null;
            update_info_bar ();
        }
    }

    [CCode (cname = "G_MODULE_EXPORT simple_scan_window_window_state_event_cb", instance_pos = -1)]
    public bool simple_scan_window_window_state_event_cb (Gtk.Widget widget, GdkEventWindowState event)
    {
        if (event->changed_mask & GDK_WINDOW_STATE_MAXIMIZED)
            window_is_maximized = (event->new_window_state & GDK_WINDOW_STATE_MAXIMIZED) != 0;
        return false;
    }

    [CCode (cname = "G_MODULE_EXPORT window_delete_event_cb", instance_pos = -1)]
    public bool window_delete_event_cb (Gtk.Widget widget, GdkEvent event)
    {
        return !quit ();
    }

    private void page_size_changed_cb (Page page)
    {
        default_page_width = page.get_width ();
        default_page_height = page.get_height ();
        default_page_dpi = page.get_dpi ();
    }

    private void page_scan_direction_changed_cb (Page page)
    {
        default_page_scan_direction = page.get_scan_direction ();
    }

    private void page_added_cb (Book book, Page page)
    {
        default_page_width = page.get_width ();
        default_page_height = page.get_height ();
        default_page_dpi = page.get_dpi ();
        default_page_scan_direction = page.get_scan_direction ();
        g_signal_connect (page, "size-changed", G_CALLBACK (page_size_changed_cb), ui);
        g_signal_connect (page, "scan-direction-changed", G_CALLBACK (page_scan_direction_changed_cb), ui);

        update_page_menu ();
    }

    private void page_removed_cb (Book book, Page page)
    {
        /* If this is the last page add a new blank one */
        if (book.get_n_pages () == 1)
            add_default_page ();

        update_page_menu ();
    }

    private void set_dpi_combo (Gtk.Widget combo, int default_dpi, int current_dpi)
    {
        struct
        {
           int dpi;
           string label;
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
          { -1, null }
        };
        Gtk.CellRenderer renderer;
        Gtk.TreeModel model;
        int i;

        renderer = gtk_cell_renderer_text_new();
        gtk_cell_layout_pack_start (GTK_CELL_LAYOUT (combo), renderer, true);
        gtk_cell_layout_add_attribute (GTK_CELL_LAYOUT (combo), renderer, "text", 1);

        model = gtk_combo_box_get_model (GTK_COMBO_BOX (combo));
        for (i = 0; scan_resolutions[i].dpi > 0; i++)
        {
            Gtk.TreeIter iter;
            string label;
            int dpi;

            dpi = scan_resolutions[i].dpi;

            if (dpi == default_dpi)
                label = /* Preferences dialog: Label for default resolution in resolution list */
                        _("%d dpi (default)").printf (dpi);
            else
                label = scan_resolutions[i].label.printf (dpi);

            gtk_list_store_append (GTK_LIST_STORE (model), &iter);
            gtk_list_store_set (GTK_LIST_STORE (model), &iter, 0, dpi, 1, label, -1);

            if (dpi == current_dpi)
                gtk_combo_box_set_active_iter (GTK_COMBO_BOX (combo), &iter);
        }
    }

    private void needs_saving_cb (Book book, GParamSpec param)
    {
        gtk_widget_set_sensitive (save_menuitem, book.get_needs_saving ());
        gtk_widget_set_sensitive (save_toolbutton, book.get_needs_saving ());
        if (book.get_needs_saving ())
            gtk_widget_set_sensitive (save_as_menuitem, true);
    }

    private void load ()
    {
        Gtk.Builder builder;
        GError error = null;
        Gtk.Widget hbox;
        Gtk.CellRenderer renderer;
        string device, document_type, scan_direction, page_side;
        int dpi, paper_width, paper_height;

        gtk_icon_theme_append_search_path (gtk_icon_theme_get_default (), ICON_DIR);

        gtk_window_set_default_icon_name ("scanner");

        builder = builder = gtk_builder_new ();
        gtk_builder_add_from_file (builder, UI_DIR + "simple-scan.ui", &error);
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

        window = GTK_WIDGET (gtk_builder_get_object (builder, "simple_scan_window"));
        main_vbox = GTK_WIDGET (gtk_builder_get_object (builder, "main_vbox"));
        page_move_left_menuitem = GTK_WIDGET (gtk_builder_get_object (builder, "page_move_left_menuitem"));
        page_move_right_menuitem = GTK_WIDGET (gtk_builder_get_object (builder, "page_move_right_menuitem"));
        page_delete_menuitem = GTK_WIDGET (gtk_builder_get_object (builder, "page_delete_menuitem"));
        crop_rotate_menuitem = GTK_WIDGET (gtk_builder_get_object (builder, "crop_rotate_menuitem"));
        save_menuitem = GTK_WIDGET (gtk_builder_get_object (builder, "save_menuitem"));
        save_as_menuitem = GTK_WIDGET (gtk_builder_get_object (builder, "save_as_menuitem"));
        save_toolbutton = GTK_WIDGET (gtk_builder_get_object (builder, "save_toolbutton"));
        stop_menuitem = GTK_WIDGET (gtk_builder_get_object (builder, "stop_scan_menuitem"));
        stop_toolbutton = GTK_WIDGET (gtk_builder_get_object (builder, "stop_toolbutton"));

        text_toolbar_menuitem = GTK_WIDGET (gtk_builder_get_object (builder, "text_toolbutton_menuitem"));
        text_menu_menuitem = GTK_WIDGET (gtk_builder_get_object (builder, "text_menuitem"));
        photo_toolbar_menuitem = GTK_WIDGET (gtk_builder_get_object (builder, "photo_toolbutton_menuitem"));
        photo_menu_menuitem = GTK_WIDGET (gtk_builder_get_object (builder, "photo_menuitem"));

        authorize_dialog = GTK_WIDGET (gtk_builder_get_object (builder, "authorize_dialog"));
        authorize_label = GTK_WIDGET (gtk_builder_get_object (builder, "authorize_label"));
        username_entry = GTK_WIDGET (gtk_builder_get_object (builder, "username_entry"));
        password_entry = GTK_WIDGET (gtk_builder_get_object (builder, "password_entry"));

        preferences_dialog = GTK_WIDGET (gtk_builder_get_object (builder, "preferences_dialog"));
        device_combo = GTK_WIDGET (gtk_builder_get_object (builder, "device_combo"));
        device_model = gtk_combo_box_get_model (GTK_COMBO_BOX (device_combo));
        text_dpi_combo = GTK_WIDGET (gtk_builder_get_object (builder, "text_dpi_combo"));
        text_dpi_model = gtk_combo_box_get_model (GTK_COMBO_BOX (text_dpi_combo));
        photo_dpi_combo = GTK_WIDGET (gtk_builder_get_object (builder, "photo_dpi_combo"));
        photo_dpi_model = gtk_combo_box_get_model (GTK_COMBO_BOX (photo_dpi_combo));
        page_side_combo = GTK_WIDGET (gtk_builder_get_object (builder, "page_side_combo"));
        page_side_model = gtk_combo_box_get_model (GTK_COMBO_BOX (page_side_combo));
        paper_size_combo = GTK_WIDGET (gtk_builder_get_object (builder, "paper_size_combo"));
        paper_size_model = gtk_combo_box_get_model (GTK_COMBO_BOX (paper_size_combo));

        /* Add InfoBar (not supported in Glade) */
        info_bar = gtk_info_bar_new ();
        g_signal_connect (info_bar, "response", G_CALLBACK (info_bar_response_cb), ui);
        gtk_box_pack_start (GTK_BOX(main_vbox), info_bar, false, true, 0);
        hbox = gtk_hbox_new (false, 12);
        gtk_container_add (GTK_CONTAINER (gtk_info_bar_get_content_area (GTK_INFO_BAR (info_bar))), hbox);
        gtk_widget_show (hbox);

        info_bar_image = gtk_image_new_from_stock (GTK_STOCK_DIALOG_WARNING, GTK_ICON_SIZE_DIALOG);
        gtk_box_pack_start (GTK_BOX(hbox), info_bar_image, false, true, 0);
        gtk_widget_show (info_bar_image);

        info_bar_label = gtk_label_new (null);
        gtk_misc_set_alignment (GTK_MISC (info_bar_label), 0.0, 0.5);
        gtk_box_pack_start (GTK_BOX(hbox), info_bar_label, true, true, 0);
        gtk_widget_show (info_bar_label);

        info_bar_close_button = gtk_info_bar_add_button (GTK_INFO_BAR (info_bar), GTK_STOCK_CLOSE, GTK_RESPONSE_CLOSE);
        info_bar_change_scanner_button = gtk_info_bar_add_button (GTK_INFO_BAR (info_bar),
                                                                            /* Button in error infobar to open preferences dialog and change scanner */
                                                                            _("Change _Scanner"), 1);

        Gtk.TreeIter iter;
        gtk_list_store_append (GTK_LIST_STORE (paper_size_model), &iter);
        gtk_list_store_set (GTK_LIST_STORE (paper_size_model), &iter, 0, 0, 1, 0, 2,
                            /* Combo box value for automatic paper size */
                            _("Automatic"), -1);
        gtk_list_store_append (GTK_LIST_STORE (paper_size_model), &iter);
        gtk_list_store_set (GTK_LIST_STORE (paper_size_model), &iter, 0, 1050, 1, 1480, 2, "A6", -1);
        gtk_list_store_append (GTK_LIST_STORE (paper_size_model), &iter);
        gtk_list_store_set (GTK_LIST_STORE (paper_size_model), &iter, 0, 1480, 1, 2100, 2, "A5", -1);
        gtk_list_store_append (GTK_LIST_STORE (paper_size_model), &iter);
        gtk_list_store_set (GTK_LIST_STORE (paper_size_model), &iter, 0, 2100, 1, 2970, 2, "A4", -1);
        gtk_list_store_append (GTK_LIST_STORE (paper_size_model), &iter);
        gtk_list_store_set (GTK_LIST_STORE (paper_size_model), &iter, 0, 2159, 1, 2794, 2, "Letter", -1);
        gtk_list_store_append (GTK_LIST_STORE (paper_size_model), &iter);
        gtk_list_store_set (GTK_LIST_STORE (paper_size_model), &iter, 0, 2159, 1, 3556, 2, "Legal", -1);
        gtk_list_store_append (GTK_LIST_STORE (paper_size_model), &iter);
        gtk_list_store_set (GTK_LIST_STORE (paper_size_model), &iter, 0, 1016, 1, 1524, 2, "4×6", -1);

        dpi = gconf_client_get_int (client, GCONF_DIR + "/text_dpi", null);
        if (dpi <= 0)
            dpi = DEFAULT_TEXT_DPI;
        set_dpi_combo (text_dpi_combo, DEFAULT_TEXT_DPI, dpi);
        dpi = gconf_client_get_int (client, GCONF_DIR + "/photo_dpi", null);
        if (dpi <= 0)
            dpi = DEFAULT_PHOTO_DPI;
        set_dpi_combo (photo_dpi_combo, DEFAULT_PHOTO_DPI, dpi);

        renderer = gtk_cell_renderer_text_new();
        gtk_cell_layout_pack_start (GTK_CELL_LAYOUT (device_combo), renderer, true);
        gtk_cell_layout_add_attribute (GTK_CELL_LAYOUT (device_combo), renderer, "text", 1);

        renderer = gtk_cell_renderer_text_new();
        gtk_cell_layout_pack_start (GTK_CELL_LAYOUT (page_side_combo), renderer, true);
        gtk_cell_layout_add_attribute (GTK_CELL_LAYOUT (page_side_combo), renderer, "text", 1);
        page_side = gconf_client_get_string (client, GCONF_DIR + "/page_side", null);
        if (page_side) {
            set_page_side (page_side);
        }

        renderer = gtk_cell_renderer_text_new();
        gtk_cell_layout_pack_start (GTK_CELL_LAYOUT (paper_size_combo), renderer, true);
        gtk_cell_layout_add_attribute (GTK_CELL_LAYOUT (paper_size_combo), renderer, "text", 2);
        paper_width = gconf_client_get_int (client, GCONF_DIR + "/paper_width", null);
        paper_height = gconf_client_get_int (client, GCONF_DIR + "/paper_height", null);
        set_paper_size (paper_width, paper_height);

        device = gconf_client_get_string (client, GCONF_DIR + "/selected_device", null);
        if (device) {
            Gtk.TreeIter iter;
            if (find_scan_device (device, &iter))
                gtk_combo_box_set_active_iter (GTK_COMBO_BOX (device_combo), &iter);
        }

        document_type = gconf_client_get_string (client, GCONF_DIR + "/document_type", null);
        if (document_type) {
            set_document_hint (document_type);
        }

        book_view = new BookView ();
        gtk_container_set_border_width (GTK_CONTAINER (book_view), 18);
        gtk_box_pack_end (GTK_BOX (main_vbox), GTK_WIDGET (book_view), true, true, 0);
        g_signal_connect (book_view, "page-selected", G_CALLBACK (page_selected_cb), ui);
        g_signal_connect (book_view, "show-page", G_CALLBACK (show_page_cb), ui);
        g_signal_connect (book_view, "show-menu", G_CALLBACK (show_page_menu_cb), ui);
        gtk_widget_show (GTK_WIDGET (book_view));

        /* Find default page details */
        scan_direction = gconf_client_get_string(client, GCONF_DIR + "/scan_direction", null);
        default_page_scan_direction = TOP_TO_BOTTOM;
        if (scan_direction) {
            int i;
            for (i = 0; scan_direction_keys[i].key != null && scan_direction_keys[i].key != scan_direction; i++);
            if (scan_direction_keys[i].key != null)
                default_page_scan_direction = scan_direction_keys[i].scan_direction;
        }
        default_page_width = gconf_client_get_int (client, GCONF_DIR + "/page_width", null);
        if (default_page_width <= 0)
            default_page_width = 595;
        default_page_height = gconf_client_get_int (client, GCONF_DIR + "/page_height", null);
        if (default_page_height <= 0)
            default_page_height = 842;
        default_page_dpi = gconf_client_get_int (client, GCONF_DIR + "/page_dpi", null);
        if (default_page_dpi <= 0)
            default_page_dpi = 72;

        /* Restore window size */
        window_width = gconf_client_get_int (client, GCONF_DIR + "/window_width", null);
        if (window_width <= 0)
            window_width = 600;
        window_height = gconf_client_get_int (client, GCONF_DIR + "/window_height", null);
        if (window_height <= 0)
            window_height = 400;
        g_debug ("Restoring window to %dx%d pixels", window_width, window_height);
        gtk_window_set_default_size (GTK_WINDOW (window), window_width, window_height);
        window_is_maximized = gconf_client_get_bool (client, GCONF_DIR + "/window_is_maximized", null);
        if (window_is_maximized) {
            g_debug ("Restoring window to maximized");
            gtk_window_maximize (GTK_WINDOW (window));
        }

        if (book.get_n_pages () == 0)
            add_default_page ();
        book.set_needs_saving (false);
        g_signal_connect (book, "notify::needs-saving", G_CALLBACK (needs_saving_cb), ui);
    }

    Book get_book ()
    {
        return book;
    }

    public void set_selected_page (Page page)
    {
        book_view.select_page (page);
    }

    public Page get_selected_page ()
    {
        return book_view.get_selected ();
    }

    public void set_scanning (bool scanning)
    {
        scanning = scanning;
        gtk_widget_set_sensitive (page_delete_menuitem, !scanning);
        gtk_widget_set_sensitive (stop_menuitem, scanning);
        gtk_widget_set_sensitive (stop_toolbutton, scanning);
    }

    public void show_error (string error_title, string error_text, bool change_scanner_hint)
    {
        have_error = true;
        this.error_title = error_title;
        this.error_text = error_text;
        error_change_scanner_hint = change_scanner_hint;
        update_info_bar ();
    }

    public void start ()
    {
        window.show ();
    }
}
