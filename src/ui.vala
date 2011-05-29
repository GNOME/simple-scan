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

public class SimpleScan
{
    private const int DEFAULT_TEXT_DPI = 150;
    private const int DEFAULT_PHOTO_DPI = 300;

    private GConf.Client client;

    private Gtk.Builder builder;

    private Gtk.Window window;
    private Gtk.VBox main_vbox;
    private Gtk.InfoBar info_bar;
    private Gtk.Image info_bar_image;
    private Gtk.Label info_bar_label;
    private Gtk.Button info_bar_close_button;
    private Gtk.Button info_bar_change_scanner_button;
    private Gtk.MenuItem page_move_left_menuitem;
    private Gtk.MenuItem page_move_right_menuitem;
    private Gtk.MenuItem page_delete_menuitem;
    private Gtk.MenuItem crop_rotate_menuitem;
    private Gtk.MenuItem save_menuitem;
    private Gtk.MenuItem save_as_menuitem;
    private Gtk.ToolButton save_toolbutton;
    private Gtk.MenuItem stop_menuitem;
    private Gtk.ToolButton stop_toolbutton;

    private Gtk.RadioMenuItem text_toolbar_menuitem;
    private Gtk.RadioMenuItem text_menu_menuitem;
    private Gtk.RadioMenuItem photo_toolbar_menuitem;
    private Gtk.RadioMenuItem photo_menu_menuitem;

    private Gtk.Dialog authorize_dialog;
    private Gtk.Label authorize_label;
    private Gtk.Entry username_entry;
    private Gtk.Entry password_entry;

    private Gtk.Dialog preferences_dialog;
    private Gtk.ComboBox device_combo;
    private Gtk.ComboBox text_dpi_combo;
    private Gtk.ComboBox photo_dpi_combo;
    private Gtk.ComboBox page_side_combo;
    private Gtk.ComboBox paper_size_combo;
    private Gtk.ListStore device_model;
    private Gtk.ListStore text_dpi_model;
    private Gtk.ListStore photo_dpi_model;
    private Gtk.ListStore page_side_model;
    private Gtk.ListStore paper_size_model;
    private bool setting_devices;
    private bool user_selected_device;

    private Gtk.FileChooserDialog? save_dialog;

    private bool have_error;
    private string error_title;
    private string error_text;
    private bool error_change_scanner_hint;

    private Book book;
    private string? book_uri;

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
    
    public signal void start_scan (string device, ScanOptions options);
    public signal void stop_scan ();
    public signal void email (string profile);
    public signal void quit ();

    public SimpleScan ()
    {
        book = new Book ();
        book.page_removed.connect (page_removed_cb);
        book.page_added.connect (page_added_cb);

        client = GConf.Client.get_default ();
        try
        {
            client.add_dir (Config.GCONF_DIR, GConf.ClientPreloadType.NONE);
        }
        catch (Error e)
        {
            warning ("Unable to preload GConf dir: %s", e.message);
        }

        load ();
    }

    private bool find_scan_device (string device, out Gtk.TreeIter iter)
    {
        bool have_iter = false;

        if (device_model.get_iter_first (out iter)) {
            do {
                string d;
                device_model.get (iter, 0, out d, -1);
                if (d == device)
                    have_iter = true;
            } while (!have_iter && device_model.iter_next (ref iter));
        }

        return have_iter;
    }

    private void show_error_dialog (string error_title, string error_text)
    {
        var dialog = new Gtk.MessageDialog (window,
                                            Gtk.DialogFlags.MODAL,
                                            Gtk.MessageType.WARNING,
                                            Gtk.ButtonsType.NONE,
                                            "%s", error_title);
        dialog.add_button (Gtk.Stock.CLOSE, 0);
        dialog.format_secondary_text ("%s", error_text);
        dialog.destroy ();
    }

    public void set_default_file_name (string default_file_name)
    {
        this.default_file_name = default_file_name;
    }

    public void authorize (string resource, out string username, out string password)
    {
        /* Label in authorization dialog.  '%s' is replaced with the name of the resource requesting authorization */
        var description = _("Username and password required to access '%s'").printf (resource);

        username_entry.set_text ("");
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
        bool show_close_button = false;
        bool show_change_scanner_button = false;

        if (have_error)  {
            type = Gtk.MessageType.ERROR;
            image_id = Gtk.Stock.DIALOG_ERROR;
            title = error_title;
            text = error_text;
            show_close_button = true;
            show_change_scanner_button = error_change_scanner_hint;
        }
        else if (device_model.iter_n_children (null) == 0) {
            type = Gtk.MessageType.WARNING;
            image_id = Gtk.Stock.DIALOG_WARNING;
            /* Warning displayed when no scanners are detected */
            title = _("No scanners detected");
            /* Hint to user on why there are no scanners detected */
            text = _("Please check your scanner is connected and powered on");
        }
        else {
            info_bar.hide ();
            return;
        }

        info_bar.set_message_type (type);
        info_bar_image.set_from_stock (image_id, Gtk.IconSize.DIALOG);
        var message = "<big><b>%s</b></big>\n\n%s".printf (title, text);
        info_bar_label.set_markup (message);
        info_bar_close_button.set_visible (show_close_button);
        info_bar_change_scanner_button.set_visible (show_change_scanner_button);
        info_bar.show ();
    }

    public void set_scan_devices (List<ScanDevice> devices)
    {
        bool have_selection = false;
        int index;
        Gtk.TreeIter iter;

        setting_devices = true;

        /* If the user hasn't chosen a scanner choose the best available one */
        if (user_selected_device)
            have_selection = device_combo.get_active () >= 0;

        /* Add new devices */
        index = 0;
        foreach (var device in devices)
        {
            int n_delete = -1;

            /* Find if already exists */
            if (device_model.iter_nth_child (out iter, null, index)) {
                int i = 0;
                do {
                    string name;
                    bool matched;

                    device_model.get (iter, 0, out name, -1);
                    matched = name == device.name;

                    if (matched) {
                        n_delete = i;
                        break;
                    }
                    i++;
                } while (device_model.iter_next (ref iter));
            }

            /* If exists, remove elements up to this one */
            if (n_delete >= 0) {
                int i;

                /* Update label */
                device_model.set (iter, 1, device.label, -1);

                for (i = 0; i < n_delete; i++) {
                    device_model.iter_nth_child (out iter, null, index);
                    device_model.remove (iter);
                }
            }
            else {
                device_model.insert (out iter, index);
                device_model.set (iter, 0, device.name, 1, device.label, -1);
            }
            index++;
        }

        /* Remove any remaining devices */
        while (device_model.iter_nth_child (out iter, null, index))
            device_model.remove (iter);

        /* Select the first available device */
        if (!have_selection && devices != null)
            device_combo.set_active (0);

        setting_devices = false;

        update_info_bar ();
    }

    private string? get_selected_device ()
    {
        Gtk.TreeIter iter;

        if (device_combo.get_active_iter (out iter)) {
            string device;
            device_model.get (iter, 0, out device, -1);
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

    private void on_file_type_changed (Gtk.TreeSelection selection)
    {
        Gtk.TreeModel model;
        Gtk.TreeIter iter;
        if (!selection.get_selected (out model, out iter))
            return;

        string extension;
        model.get (iter, 1, out extension, -1);
        var path = save_dialog.get_filename ();
        var filename = Path.get_basename (path);

        /* Replace extension */
        var extension_index = filename.last_index_of_char ('.');
        if (extension_index >= 0)
            filename = filename.slice (0, extension_index);
        filename = filename + extension;
        save_dialog.set_current_name (filename);
    }

    private string choose_file_location ()
    {
        /* Get directory to save to */
        string? directory = null;
        try
        {
            directory = client.get_string (Config.GCONF_DIR + "/save_directory");
        }
        catch (Error e)
        {
            warning ("Error reading configuration: %s", e.message);
        }
            
        if (directory == null || directory == "") {
            directory = Environment.get_user_special_dir (UserDirectory.DOCUMENTS);
        }

        save_dialog = new Gtk.FileChooserDialog (/* Save dialog: Dialog title */
                                                 _("Save As..."),
                                                 window,
                                                 Gtk.FileChooserAction.SAVE,
                                                 Gtk.Stock.CANCEL, Gtk.ResponseType.CANCEL,
                                                 Gtk.Stock.SAVE, Gtk.ResponseType.ACCEPT,
                                                 null);
        save_dialog.set_do_overwrite_confirmation (true);
        save_dialog.set_local_only (false);
        save_dialog.set_current_folder (directory);
        save_dialog.set_current_name (default_file_name);

        /* Filter to only show images by default */
        var filter = new Gtk.FileFilter ();
        filter.set_name (/* Save dialog: Filter name to show only image files */
                         _("Image Files"));
        filter.add_pixbuf_formats ();
        filter.add_mime_type ("application/pdf");
        save_dialog.add_filter (filter);
        filter = new Gtk.FileFilter ();
        filter.set_name (/* Save dialog: Filter name to show all files */
                         _("All Files"));
        filter.add_pattern ("*");
        save_dialog.add_filter (filter);

        var expander = new Gtk.Expander.with_mnemonic (/* */
                                                       _("Select File _Type"));
        expander.set_spacing (5);
        save_dialog.set_extra_widget (expander);

        string extension = "";
        var index = default_file_name.last_index_of_char ('.');
        if (index >= 0)
            extension = default_file_name.slice (0, index);

        var file_type_store = new Gtk.ListStore (2, typeof (string), typeof (string));
        Gtk.TreeIter iter;
        file_type_store.append (out iter);
        file_type_store.set (iter,
                             /* Save dialog: Label for saving in PDF format */
                             0, _("PDF (multi-page document)"),
                             1, ".pdf",
                             -1);
        file_type_store.append (out iter);
        file_type_store.set (iter,
                             /* Save dialog: Label for saving in JPEG format */
                             0, _("JPEG (compressed)"),
                             1, ".jpg",
                             -1);
        file_type_store.append (out iter);
        file_type_store.set (iter,
                             /* Save dialog: Label for saving in PNG format */
                             0, _("PNG (lossless)"),
                             1, ".png",
                             -1);

        var file_type_view = new Gtk.TreeView.with_model (file_type_store);
        file_type_view.set_headers_visible (false);
        file_type_view.set_rules_hint (true);
        var column = new Gtk.TreeViewColumn.with_attributes ("",
                                                             new Gtk.CellRendererText (),
                                                             "text", 0, null);
        file_type_view.append_column (column);
        expander.add (file_type_view);

        if (file_type_store.get_iter_first (out iter)) {
            do {
                string e;
                file_type_store.get (iter, 1, out e, -1);
                if (extension == e)
                    file_type_view.get_selection ().select_iter (iter);
            } while (file_type_store.iter_next (ref iter));
        }
        file_type_view.get_selection ().changed.connect (on_file_type_changed);

        expander.show_all ();

        var response = save_dialog.run ();

        string? uri = null;
        if (response == Gtk.ResponseType.ACCEPT)
            uri = save_dialog.get_uri ();

        try
        {
            client.set_string (Config.GCONF_DIR + "/save_directory", save_dialog.get_current_folder ());
        }
        catch (Error e)
        {
            warning ("Error writing configuration: %s", e.message);
        }

        save_dialog.destroy ();
        save_dialog = null;

        return uri;
    }

    private bool save_document (bool force_choose_location)
    {
        string? uri;
        if (book_uri != null && !force_choose_location)
            uri = book_uri;
        else
            uri = choose_file_location ();
        if (uri == null)
            return false;

        var file = File.new_for_uri (uri);

        debug ("Saving to '%s'", uri);

        var uri_lower = uri.down ();
        string format = "jpeg";
        if (uri_lower.has_suffix (".pdf"))
            format = "pdf";
        else if (uri_lower.has_suffix (".ps"))
            format = "ps";
        else if (uri_lower.has_suffix (".png"))
            format = "png";
        else if (uri_lower.has_suffix (".tif") || uri_lower.has_suffix (".tiff"))
            format = "tiff";

        try
        {
            book.save (format, file);
        }
        catch (Error e)
        {
            warning ("Error saving file: %s", e.message);
            show_error (/* Title of error dialog when save failed */
                        _("Failed to save file"),
                        e.message,
                        false);
            return false;
        }

        book_uri = uri;
        book.set_needs_saving (false);
        return true;
    }

    private bool prompt_to_save (string title, string discard_label)
    {
        if (!book.get_needs_saving ())
            return true;

        var dialog = new Gtk.MessageDialog (window,
                                            Gtk.DialogFlags.MODAL,
                                            Gtk.MessageType.WARNING,
                                            Gtk.ButtonsType.NONE,
                                            "%s", title);
        dialog.format_secondary_text ("%s",
                                      /* Text in dialog warning when a document is about to be lost*/
                                      _("If you don't save, changes will be permanently lost."));
        dialog.add_button (discard_label, Gtk.ResponseType.NO);
        dialog.add_button (Gtk.Stock.CANCEL, Gtk.ResponseType.CANCEL);
        dialog.add_button (Gtk.Stock.SAVE, Gtk.ResponseType.YES);

        var response = dialog.run ();
        dialog.destroy ();

        switch (response) {
        case Gtk.ResponseType.YES:
            if (save_document (false))
                return true;
            else
                return false;
        case Gtk.ResponseType.CANCEL:
            return false;
        case Gtk.ResponseType.NO:
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
        save_as_menuitem.set_sensitive (false);
    }

    [CCode (cname = "G_MODULE_EXPORT new_button_clicked_cb", instance_pos = -1)]
    public void new_button_clicked_cb (Gtk.Widget widget)
    {
        if (!prompt_to_save (/* Text in dialog warning when a document is about to be lost */
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
            text_toolbar_menuitem.set_active (true);
            text_menu_menuitem.set_active (true);
        }
        else if (document_hint == "photo") {
            photo_toolbar_menuitem.set_active (true);
            photo_menu_menuitem.set_active (true);
        }
    }

    [CCode (cname = "G_MODULE_EXPORT text_menuitem_toggled_cb", instance_pos = -1)]
    public void text_menuitem_toggled_cb (Gtk.CheckMenuItem widget)
    {
        if (widget.get_active ())
            set_document_hint ("text");
    }

    [CCode (cname = "G_MODULE_EXPORT photo_menuitem_toggled_cb", instance_pos = -1)]
    public void photo_menuitem_toggled_cb (Gtk.CheckMenuItem widget)
    {
        if (widget.get_active ())
            set_document_hint ("photo");
    }

    private void set_page_side (string document_hint)
    {
        Gtk.TreeIter iter;

        if (page_side_model.get_iter_first (out iter)) {
            do {
                string d;
                page_side_model.get (iter, 0, out d, -1);
                var have_match = d == document_hint;

                if (have_match) {
                    page_side_combo.set_active_iter (iter);
                    return;
                }
            } while (page_side_model.iter_next (ref iter));
         }
    }

    private void set_paper_size (int width, int height)
    {
        Gtk.TreeIter iter;
        bool have_iter;

        for (have_iter = paper_size_model.get_iter_first (out iter);
             have_iter;
             have_iter = paper_size_model.iter_next (ref iter)) {
            int w, h;
            paper_size_model.get (iter, 0, out w, 1, out h, -1);
            if (w == width && h == height)
                break;
        }

        if (!have_iter)
            have_iter = paper_size_model.get_iter_first (out iter);
        if (have_iter)
            paper_size_combo.set_active_iter (iter);
    }

    private int get_text_dpi ()
    {
        Gtk.TreeIter iter;
        int dpi = DEFAULT_TEXT_DPI;

        if (text_dpi_combo.get_active_iter (out iter))
            text_dpi_model.get (iter, 0, out dpi, -1);

        return dpi;
    }

    private int get_photo_dpi ()
    {
        Gtk.TreeIter iter;
        int dpi = DEFAULT_PHOTO_DPI;

        if (photo_dpi_combo.get_active_iter (out iter))
            photo_dpi_model.get (iter, 0, out dpi, -1);

        return dpi;
    }

    private string get_page_side ()
    {
        Gtk.TreeIter iter;
        string mode = null;

        if (page_side_combo.get_active_iter (out iter))
            page_side_model.get (iter, 0, out mode, -1);

        return mode;
    }

    private bool get_paper_size (out int width, out int height)
    {
        Gtk.TreeIter iter;

        if (paper_size_combo.get_active_iter (out iter)) {
            paper_size_model.get (iter, 0, width, 1, height, -1);
            return true;
        }

        return false;
    }

    private ScanOptions get_scan_options ()
    {
        var options = new ScanOptions ();
        if (document_hint == "text")
        {
            options.scan_mode = ScanMode.GRAY;
            options.dpi = get_text_dpi ();
        }
        else
        {
            options.scan_mode = ScanMode.COLOR;
            options.dpi = get_photo_dpi ();
        }
        options.depth = 8;
        get_paper_size (out options.paper_width, out options.paper_height);

        return options;
    }

    [CCode (cname = "G_MODULE_EXPORT scan_button_clicked_cb", instance_pos = -1)]
    public void scan_button_clicked_cb (Gtk.Widget widget)
    {
        string device;
        ScanOptions options;

        device = get_selected_device ();

        options = get_scan_options ();
        options.type = ScanType.SINGLE;
        start_scan (device, options);
    }

    [CCode (cname = "G_MODULE_EXPORT stop_scan_button_clicked_cb", instance_pos = -1)]
    public void stop_scan_button_clicked_cb (Gtk.Widget widget)
    {
        stop_scan ();
    }

    [CCode (cname = "G_MODULE_EXPORT continuous_scan_button_clicked_cb", instance_pos = -1)]
    public void continuous_scan_button_clicked_cb (Gtk.Widget widget)
    {
        if (scanning) {
            stop_scan ();
        } else {
            string device, side;
            ScanOptions options;

            device = get_selected_device ();
            options = get_scan_options ();
            side = get_page_side ();
            if (side == "front")
                options.type = ScanType.ADF_FRONT;
            else if (side == "back")
                options.type = ScanType.ADF_BACK;
            else
                options.type = ScanType.ADF_BOTH;

            start_scan (device, options);
        }
    }

    [CCode (cname = "G_MODULE_EXPORT preferences_button_clicked_cb", instance_pos = -1)]
    public void preferences_button_clicked_cb (Gtk.Widget widget)
    {
        preferences_dialog.present ();
    }

    [CCode (cname = "G_MODULE_EXPORT preferences_dialog_delete_event_cb", instance_pos = -1)]
    public bool preferences_dialog_delete_event_cb (Gtk.Widget widget)
    {
        return true;
    }

    [CCode (cname = "G_MODULE_EXPORT preferences_dialog_response_cb", instance_pos = -1)]
    public void preferences_dialog_response_cb (Gtk.Widget widget, int response_id)
    {
        preferences_dialog.hide ();
    }

    private void update_page_menu ()
    {
        var index = book.get_page_index (book_view.get_selected ());
        page_move_left_menuitem.set_sensitive (index > 0);
        page_move_right_menuitem.set_sensitive (index < book.get_n_pages () - 1);
    }

    private void page_selected_cb (BookView view, Page? page)
    {
        if (page == null)
            return;

        updating_page_menu = true;

        update_page_menu ();

        string name = null;
        if (page.has_crop ()) {
            // FIXME: Make more generic, move into page-size.c and reuse
            var crop_name = page.get_named_crop ();
            if (crop_name != null) {
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

        var menuitem = (Gtk.RadioMenuItem) builder.get_object (name);
        menuitem.set_active (true);
        var toolbutton = (Gtk.ToggleToolButton) builder.get_object ("crop_toolbutton");
        toolbutton.set_active (page.has_crop ());

        updating_page_menu = false;
    }

    // FIXME: Duplicated from simple-scan.vala
    private string? get_temporary_filename (string prefix, string extension)
    {
        /* NOTE: I'm not sure if this is a 100% safe strategy to use g_file_open_tmp(), close and
         * use the filename but it appears to work in practise */

        var filename = "%sXXXXXX.%s".printf (prefix, extension);
        string path;
        try
        {
            var fd = FileUtils.open_tmp (filename, out path);
            Posix.close (fd);
        }
        catch (Error e)
        {
            warning ("Error saving email attachment: %s", e.message);
            return null;
        }

        return path;
    }

    private void show_page_cb (BookView view, Page page)
    {
        var path = get_temporary_filename ("scanned-page", "tiff");
        if (path == null)
            return;
        var file = File.new_for_path (path);

        try
        {
            page.save ("tiff", file);
        }
        catch (Error e)
        {
            show_error_dialog (/* Error message display when unable to save image for preview */
                               _("Unable to save image for preview"),
                               e.message);
            return;
        }
        
        try
        {
            Gtk.show_uri (window.get_screen (), file.get_uri (), Gtk.get_current_event_time ());
        }
        catch (Error e)
        {
            show_error_dialog (/* Error message display when unable to preview image */
                               _("Unable to open image preview application"),
                               e.message);
        }
    }

    private void show_page_menu_cb (BookView view)
    {
        var menu = (Gtk.Menu) builder.get_object ("page_menu");
        menu.popup (null, null, null, 3, Gtk.get_current_event_time());
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
        crop_rotate_menuitem.set_sensitive (crop_name != null);

        if (updating_page_menu)
            return;

        var page = book_view.get_selected ();
        if (page == null)
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
    public void no_crop_menuitem_toggled_cb (Gtk.CheckMenuItem widget)
    {
        if (widget.get_active ())
            set_crop (null);
    }

    [CCode (cname = "G_MODULE_EXPORT custom_crop_menuitem_toggled_cb", instance_pos = -1)]
    public void custom_crop_menuitem_toggled_cb (Gtk.CheckMenuItem widget)
    {
        if (widget.get_active ())
            set_crop ("custom");
    }

    [CCode (cname = "G_MODULE_EXPORT crop_toolbutton_toggled_cb", instance_pos = -1)]
    public void crop_toolbutton_toggled_cb (Gtk.ToggleToolButton widget)
    {
        if (updating_page_menu)
            return;

        Gtk.RadioMenuItem menuitem;
        if (widget.get_active ())
            menuitem = (Gtk.RadioMenuItem) builder.get_object ("custom_crop_menuitem");
        else
            menuitem = (Gtk.RadioMenuItem) builder.get_object ("no_crop_menuitem");
        menuitem.set_active (true);
    }

    [CCode (cname = "G_MODULE_EXPORT four_by_six_menuitem_toggled_cb", instance_pos = -1)]
    public void four_by_six_menuitem_toggled_cb (Gtk.CheckMenuItem widget)
    {
        if (widget.get_active ())
            set_crop ("4x6");
    }

    [CCode (cname = "G_MODULE_EXPORT legal_menuitem_toggled_cb", instance_pos = -1)]
    public void legal_menuitem_toggled_cb (Gtk.CheckMenuItem widget)
    {
        if (widget.get_active ())
            set_crop ("legal");
    }

    [CCode (cname = "G_MODULE_EXPORT letter_menuitem_toggled_cb", instance_pos = -1)]
    public void letter_menuitem_toggled_cb (Gtk.CheckMenuItem widget)
    {
        if (widget.get_active ())
            set_crop ("letter");
    }

    [CCode (cname = "G_MODULE_EXPORT a6_menuitem_toggled_cb", instance_pos = -1)]
    public void a6_menuitem_toggled_cb (Gtk.CheckMenuItem widget)
    {
        if (widget.get_active ())
            set_crop ("A6");
    }

    [CCode (cname = "G_MODULE_EXPORT a5_menuitem_toggled_cb", instance_pos = -1)]
    public void a5_menuitem_toggled_cb (Gtk.CheckMenuItem widget)
    {
        if (widget.get_active ())
            set_crop ("A5");
    }

    [CCode (cname = "G_MODULE_EXPORT a4_menuitem_toggled_cb", instance_pos = -1)]
    public void a4_menuitem_toggled_cb (Gtk.CheckMenuItem widget)
    {
        if (widget.get_active ())
            set_crop ("A4");
    }

    [CCode (cname = "G_MODULE_EXPORT crop_rotate_menuitem_activate_cb", instance_pos = -1)]
    public void crop_rotate_menuitem_activate_cb (Gtk.Widget widget)
    {
        var page = book_view.get_selected ();
        if (page == null)
            return;
        page.rotate_crop ();
    }

    [CCode (cname = "G_MODULE_EXPORT page_move_left_menuitem_activate_cb", instance_pos = -1)]
    public void page_move_left_menuitem_activate_cb (Gtk.Widget widget)
    {
        var page = book_view.get_selected ();
        var index = book.get_page_index (page);
        if (index > 0)
            book.move_page (page, index - 1);

        update_page_menu ();
    }

    [CCode (cname = "G_MODULE_EXPORT page_move_right_menuitem_activate_cb", instance_pos = -1)]
    public void page_move_right_menuitem_activate_cb (Gtk.Widget widget)
    {
        var page = book_view.get_selected ();
        var index = book.get_page_index (page);
        if (index < book.get_n_pages () - 1)
            book.move_page (page, book.get_page_index (page) + 1);

        update_page_menu ();
    }

    [CCode (cname = "G_MODULE_EXPORT page_delete_menuitem_activate_cb", instance_pos = -1)]
    public void page_delete_menuitem_activate_cb (Gtk.Widget widget)
    {
        book_view.get_book ().delete_page (book_view.get_selected ());
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
                            int                page_number)
    {
        var context = print_context.get_cairo_context ();
        var page = book.get_page (page_number);

        /* Rotate to same aspect */
        bool is_landscape = false;
        if (print_context.get_width () > print_context.get_height ())
            is_landscape = true;
        if (page.is_landscape () != is_landscape) {
            context.translate (print_context.get_width (), 0);
            context.rotate (Math.PI_2);
        }

        context.scale (print_context.get_dpi_x () / page.get_dpi (),
                       print_context.get_dpi_y () / page.get_dpi ());

        var image = page.get_image (true);
        Gdk.cairo_set_source_pixbuf (context, image, 0, 0);
        context.paint ();
    }

    [CCode (cname = "G_MODULE_EXPORT email_button_clicked_cb", instance_pos = -1)]
    public void email_button_clicked_cb (Gtk.Widget widget)
    {
        email (document_hint);
    }

    [CCode (cname = "G_MODULE_EXPORT print_button_clicked_cb", instance_pos = -1)]
    public void print_button_clicked_cb (Gtk.Widget widget)
    {
        var print = new Gtk.PrintOperation ();
        print.set_n_pages (book.get_n_pages ());
        print.draw_page.connect (draw_page);

        try
        {
            print.run (Gtk.PrintOperationAction.PRINT_DIALOG, window);
        }
        catch (Error e)
        {
            warning ("Error printing: %s", e.message);
        }
    }

    [CCode (cname = "G_MODULE_EXPORT help_contents_menuitem_activate_cb", instance_pos = -1)]
    public void help_contents_menuitem_activate_cb (Gtk.Widget widget)
    {
        try
        {
            Gtk.show_uri (window.get_screen (), "ghelp:simple-scan", Gtk.get_current_event_time ());
        }
        catch (Error e)
        {
            show_error_dialog (/* Error message displayed when unable to launch help browser */
                               _("Unable to open help file"),
                               e.message);
        }
    }

    [CCode (cname = "G_MODULE_EXPORT about_menuitem_activate_cb", instance_pos = -1)]
    public void about_menuitem_activate_cb (Gtk.Widget widget)
    {
        string[] authors = { "Robert Ancell <robert.ancell@canonical.com>" };

        /* The license this software is under (GPL3+) */
        string license = _("This program is free software: you can redistribute it and/or modify\nit under the terms of the GNU General Public License as published by\nthe Free Software Foundation, either version 3 of the License, or\n(at your option) any later version.\n\nThis program is distributed in the hope that it will be useful,\nbut WITHOUT ANY WARRANTY; without even the implied warranty of\nMERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the\nGNU General Public License for more details.\n\nYou should have received a copy of the GNU General Public License\nalong with this program.  If not, see <http://www.gnu.org/licenses/>.");

        /* Title of about dialog */
        string title = _("About Simple Scan");

        /* Description of program */
        string description = _("Simple document scanning tool");

        Gtk.show_about_dialog (window,
                               "title", title,
                               "program-name", "Simple Scan",
                               "version", Config.VERSION,
                               "comments", description,
                               "logo-icon-name", "scanner",
                               "authors", authors,
                               "translator-credits", _("translator-credits"),
                               "website", "https://launchpad.net/simple-scan",
                               "copyright", "Copyright © 2009-2011 Canonical Ltd.",
                               "license", license,
                               "wrap-license", true,
                               null);
    }

    private bool on_quit ()
    {
        if (!prompt_to_save (/* Text in dialog warning when a document is about to be lost */
                             _("Save document before quitting?"),
                             /* Button in dialog to quit and discard unsaved document */
                             _("Quit without Saving")))
            return false;

        var device = get_selected_device ();
        int paper_width = 0, paper_height = 0;
        get_paper_size (out paper_width, out paper_height);

        try
        {
            if (device != null)
                client.set_string (Config.GCONF_DIR + "/selected_device", device);
            client.set_string (Config.GCONF_DIR + "/document_type", document_hint);
            client.set_int (Config.GCONF_DIR + "/text_dpi", get_text_dpi ());
            client.set_int (Config.GCONF_DIR + "/photo_dpi", get_photo_dpi ());
            client.set_string (Config.GCONF_DIR + "/page_side", get_page_side ());
            client.set_int (Config.GCONF_DIR + "/paper_width", paper_width);
            client.set_int (Config.GCONF_DIR + "/paper_height", paper_height);
            client.set_int (Config.GCONF_DIR + "/window_width", window_width);
            client.set_int (Config.GCONF_DIR + "/window_height", window_height);
            client.set_bool (Config.GCONF_DIR + "/window_is_maximized", window_is_maximized);
            switch (default_page_scan_direction)
            {
            case ScanDirection.TOP_TO_BOTTOM:
                client.set_string (Config.GCONF_DIR + "/scan_direction", "top-to-bottom");
                break;
            case ScanDirection.BOTTOM_TO_TOP:
                client.set_string (Config.GCONF_DIR + "/scan_direction", "bottom-to-top");
                break;
            case ScanDirection.LEFT_TO_RIGHT:
                client.set_string (Config.GCONF_DIR + "/scan_direction", "left-to-right");
                break;
            case ScanDirection.RIGHT_TO_LEFT:
                client.set_string (Config.GCONF_DIR + "/scan_direction", "right-to-left");
                break;
            }
            client.set_int (Config.GCONF_DIR + "/page_width", default_page_width);
            client.set_int (Config.GCONF_DIR + "/page_height", default_page_height);
            client.set_int (Config.GCONF_DIR + "/page_dpi", default_page_dpi);
        }
        catch (Error e)
        {
            warning ("Error writing configuration: %s", e.message);
        }

        quit ();

        return true;
    }

    [CCode (cname = "G_MODULE_EXPORT quit_menuitem_activate_cb", instance_pos = -1)]
    public void quit_menuitem_activate_cb (Gtk.Widget widget)
    {
        on_quit ();
    }

    [CCode (cname = "G_MODULE_EXPORT simple_scan_window_configure_event_cb", instance_pos = -1)]
    public bool simple_scan_window_configure_event_cb (Gtk.Widget widget, Gdk.EventConfigure event)
    {
        if (!window_is_maximized) {
            window_width = event.width;
            window_height = event.height;
        }

        return false;
    }

    private void info_bar_response_cb (Gtk.InfoBar widget, int response_id)
    {
        if (response_id == 1) {
            device_combo.grab_focus ();
            preferences_dialog.present ();
        }
        else {
            have_error = false;
            error_title = null;
            error_text = null;
            update_info_bar ();
        }
    }

    [CCode (cname = "G_MODULE_EXPORT simple_scan_window_window_state_event_cb", instance_pos = -1)]
    public bool simple_scan_window_window_state_event_cb (Gtk.Widget widget, Gdk.EventWindowState event)
    {
        if ((event.changed_mask & Gdk.WindowState.MAXIMIZED) != 0)
            window_is_maximized = (event.new_window_state & Gdk.WindowState.MAXIMIZED) != 0;
        return false;
    }

    [CCode (cname = "G_MODULE_EXPORT window_delete_event_cb", instance_pos = -1)]
    public bool window_delete_event_cb (Gtk.Widget widget, Gdk.Event event)
    {
        return !on_quit ();
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
        page.size_changed.connect (page_size_changed_cb);
        page.scan_direction_changed.connect (page_scan_direction_changed_cb);

        update_page_menu ();
    }

    private void page_removed_cb (Book book, Page page)
    {
        /* If this is the last page add a new blank one */
        if (book.get_n_pages () == 1)
            add_default_page ();

        update_page_menu ();
    }

    private void set_dpi_combo (Gtk.ComboBox combo, int default_dpi, int current_dpi)
    {
        var renderer = new Gtk.CellRendererText ();
        combo.pack_start (renderer, true);
        combo.add_attribute (renderer, "text", 1);

        var model = (Gtk.ListStore) combo.get_model ();
        int[] scan_resolutions = {75, 150, 300, 600, 1200, 2400};
        foreach (var dpi in scan_resolutions)
        {
            string label;
            if (dpi == default_dpi)
                /* Preferences dialog: Label for default resolution in resolution list */
                label = _("%d dpi (default)").printf (dpi);
            else if (dpi == 75)
                /* Preferences dialog: Label for minimum resolution in resolution list */
                label = _("%d dpi (draft)").printf (dpi);
            else if (dpi == 1200)
                /* Preferences dialog: Label for maximum resolution in resolution list */
                label = _("%d dpi (high resolution)").printf (dpi);
            else
                /* Preferences dialog: Label for resolution value in resolution list (dpi = dots per inch) */
                label = _("%d dpi").printf (dpi);

            Gtk.TreeIter iter;
            model.append (out iter);
            model.set (iter, 0, dpi, 1, label, -1);

            if (dpi == current_dpi)
                combo.set_active_iter (iter);
        }
    }

    private void needs_saving_cb (ParamSpec pspec)
    {
        save_menuitem.set_sensitive (book.get_needs_saving ());
        save_toolbutton.set_sensitive (book.get_needs_saving ());
        if (book.get_needs_saving ())
            save_as_menuitem.set_sensitive (true);
    }

    private void load ()
    {
        Gtk.IconTheme.get_default ().append_search_path (Config.ICON_DIR);

        Gtk.Window.set_default_icon_name ("scanner");

        builder = new Gtk.Builder ();
        try
        {
            builder.add_from_file (Config.UI_DIR + "simple-scan.ui");
        }
        catch (Error e)
        {
            critical ("Unable to load UI: %s\n", e.message);
            show_error_dialog (/* Title of dialog when cannot load required files */
                               _("Files missing"),
                               /* Description in dialog when cannot load required files */
                               _("Please check your installation"));
            Posix.exit (Posix.EXIT_FAILURE);
        }
        builder.connect_signals (this);

        window = (Gtk.Window) builder.get_object ("simple_scan_window");
        main_vbox = (Gtk.VBox) builder.get_object ("main_vbox");
        page_move_left_menuitem = (Gtk.MenuItem) builder.get_object ("page_move_left_menuitem");
        page_move_right_menuitem = (Gtk.MenuItem) builder.get_object ("page_move_right_menuitem");
        page_delete_menuitem = (Gtk.MenuItem) builder.get_object ("page_delete_menuitem");
        crop_rotate_menuitem = (Gtk.MenuItem) builder.get_object ("crop_rotate_menuitem");
        save_menuitem = (Gtk.MenuItem) builder.get_object ("save_menuitem");
        save_as_menuitem = (Gtk.MenuItem) builder.get_object ("save_as_menuitem");
        save_toolbutton = (Gtk.ToolButton) builder.get_object ("save_toolbutton");
        stop_menuitem = (Gtk.MenuItem) builder.get_object ("stop_scan_menuitem");
        stop_toolbutton = (Gtk.ToolButton) builder.get_object ("stop_toolbutton");

        text_toolbar_menuitem = (Gtk.RadioMenuItem) builder.get_object ("text_toolbutton_menuitem");
        text_menu_menuitem = (Gtk.RadioMenuItem) builder.get_object ("text_menuitem");
        photo_toolbar_menuitem = (Gtk.RadioMenuItem) builder.get_object ("photo_toolbutton_menuitem");
        photo_menu_menuitem = (Gtk.RadioMenuItem) builder.get_object ("photo_menuitem");

        authorize_dialog = (Gtk.Dialog) builder.get_object ("authorize_dialog");
        authorize_label = (Gtk.Label) builder.get_object ("authorize_label");
        username_entry = (Gtk.Entry) builder.get_object ("username_entry");
        password_entry = (Gtk.Entry) builder.get_object ("password_entry");

        preferences_dialog = (Gtk.Dialog) builder.get_object ("preferences_dialog");
        device_combo = (Gtk.ComboBox) builder.get_object ("device_combo");
        device_model = (Gtk.ListStore) device_combo.get_model ();
        text_dpi_combo = (Gtk.ComboBox) builder.get_object ("text_dpi_combo");
        text_dpi_model = (Gtk.ListStore) text_dpi_combo.get_model ();
        photo_dpi_combo = (Gtk.ComboBox) builder.get_object ("photo_dpi_combo");
        photo_dpi_model = (Gtk.ListStore) photo_dpi_combo.get_model ();
        page_side_combo = (Gtk.ComboBox) builder.get_object ("page_side_combo");
        page_side_model = (Gtk.ListStore) page_side_combo.get_model ();
        paper_size_combo = (Gtk.ComboBox) builder.get_object ("paper_size_combo");
        paper_size_model = (Gtk.ListStore) paper_size_combo.get_model ();

        /* Add InfoBar (not supported in Glade) */
        info_bar = new Gtk.InfoBar ();
        info_bar.response.connect (info_bar_response_cb);
        main_vbox.pack_start (info_bar, false, true, 0);
        var hbox = new Gtk.HBox (false, 12);
        var content_area = (Gtk.Container) info_bar.get_content_area ();
        content_area.add (hbox);
        hbox.show ();

        info_bar_image = new Gtk.Image.from_stock (Gtk.Stock.DIALOG_WARNING, Gtk.IconSize.DIALOG);
        hbox.pack_start (info_bar_image, false, true, 0);
        info_bar_image.show ();

        info_bar_label = new Gtk.Label (null);
        info_bar_label.set_alignment (0.0f, 0.5f);
        hbox.pack_start (info_bar_label, true, true, 0);
        info_bar_label.show ();

        info_bar_close_button = (Gtk.Button) info_bar.add_button (Gtk.Stock.CLOSE, Gtk.ResponseType.CLOSE);
        info_bar_change_scanner_button = (Gtk.Button) info_bar.add_button (/* Button in error infobar to open preferences dialog and change scanner */
                                                                           _("Change _Scanner"), 1);

        Gtk.TreeIter iter;
        paper_size_model.append (out iter);
        paper_size_model.set (iter, 0, 0, 1, 0, 2,
                            /* Combo box value for automatic paper size */
                            _("Automatic"), -1);
        paper_size_model.append (out iter);
        paper_size_model.set (iter, 0, 1050, 1, 1480, 2, "A6", -1);
        paper_size_model.append (out iter);
        paper_size_model.set (iter, 0, 1480, 1, 2100, 2, "A5", -1);
        paper_size_model.append (out iter);
        paper_size_model.set (iter, 0, 2100, 1, 2970, 2, "A4", -1);
        paper_size_model.append (out iter);
        paper_size_model.set (iter, 0, 2159, 1, 2794, 2, "Letter", -1);
        paper_size_model.append (out iter);
        paper_size_model.set (iter, 0, 2159, 1, 3556, 2, "Legal", -1);
        paper_size_model.append (out iter);
        paper_size_model.set (iter, 0, 1016, 1, 1524, 2, "4×6", -1);

        var dpi = client.get_int (Config.GCONF_DIR + "/text_dpi");
        if (dpi <= 0)
            dpi = DEFAULT_TEXT_DPI;
        set_dpi_combo (text_dpi_combo, DEFAULT_TEXT_DPI, dpi);
        dpi = client.get_int (Config.GCONF_DIR + "/photo_dpi");
        if (dpi <= 0)
            dpi = DEFAULT_PHOTO_DPI;
        set_dpi_combo (photo_dpi_combo, DEFAULT_PHOTO_DPI, dpi);

        var renderer = new Gtk.CellRendererText ();
        device_combo.pack_start (renderer, true);
        device_combo.add_attribute (renderer, "text", 1);

        renderer = new Gtk.CellRendererText ();
        page_side_combo.pack_start (renderer, true);
        page_side_combo.add_attribute (renderer, "text", 1);
        var page_side = client.get_string (Config.GCONF_DIR + "/page_side");
        if (page_side != null) {
            set_page_side (page_side);
        }

        renderer = new Gtk.CellRendererText ();
        paper_size_combo.pack_start (renderer, true);
        paper_size_combo.add_attribute (renderer, "text", 2);
        var paper_width = client.get_int (Config.GCONF_DIR + "/paper_width");
        var paper_height = client.get_int (Config.GCONF_DIR + "/paper_height");
        set_paper_size (paper_width, paper_height);

        var device = client.get_string (Config.GCONF_DIR + "/selected_device");
        if (device != null) {
            if (find_scan_device (device, out iter))
                device_combo.set_active_iter (iter);
        }

        var document_type = client.get_string (Config.GCONF_DIR + "/document_type");
        if (document_type != null) {
            set_document_hint (document_type);
        }

        book_view = new BookView (book);
        book_view.set_border_width (18);
        main_vbox.pack_end (book_view, true, true, 0);
        book_view.page_selected.connect (page_selected_cb);
        book_view.show_page.connect (show_page_cb);
        book_view.show_menu.connect (show_page_menu_cb);
        book_view.show ();

        /* Find default page details */
        var scan_direction = client.get_string (Config.GCONF_DIR + "/scan_direction");
        default_page_scan_direction = ScanDirection.TOP_TO_BOTTOM;
        if (scan_direction != null) {
            switch (scan_direction)
            {
            case "top-to-bottom":
                default_page_scan_direction = ScanDirection.TOP_TO_BOTTOM;
                break;
            case "bottom-to-top":
                default_page_scan_direction = ScanDirection.BOTTOM_TO_TOP;
                break;
            case "left-to-right":
                default_page_scan_direction = ScanDirection.LEFT_TO_RIGHT;
                break;
            case "right-to-left":
                default_page_scan_direction = ScanDirection.RIGHT_TO_LEFT;
                break;
            }
        }
        default_page_width = client.get_int (Config.GCONF_DIR + "/page_width");
        if (default_page_width <= 0)
            default_page_width = 595;
        default_page_height = client.get_int (Config.GCONF_DIR + "/page_height");
        if (default_page_height <= 0)
            default_page_height = 842;
        default_page_dpi = client.get_int (Config.GCONF_DIR + "/page_dpi");
        if (default_page_dpi <= 0)
            default_page_dpi = 72;

        /* Restore window size */
        window_width = client.get_int (Config.GCONF_DIR + "/window_width");
        if (window_width <= 0)
            window_width = 600;
        window_height = client.get_int (Config.GCONF_DIR + "/window_height");
        if (window_height <= 0)
            window_height = 400;
        debug ("Restoring window to %dx%d pixels", window_width, window_height);
        window.set_default_size (window_width, window_height);
        window_is_maximized = client.get_bool (Config.GCONF_DIR + "/window_is_maximized");
        if (window_is_maximized) {
            debug ("Restoring window to maximized");
            window.maximize ();
        }

        if (book.get_n_pages () == 0)
            add_default_page ();
        book.set_needs_saving (false);
        book.notify["needs-saving"].connect (needs_saving_cb);
    }

    public Book get_book ()
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
        this.scanning = scanning;
        page_delete_menuitem.set_sensitive (!scanning);
        stop_menuitem.set_sensitive (scanning);
        stop_toolbutton.set_sensitive (scanning);
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
