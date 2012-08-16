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

public class UserInterface
{
    private const int DEFAULT_TEXT_DPI = 150;
    private const int DEFAULT_PHOTO_DPI = 300;

    private Settings settings;

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
    private ProgressBarDialog progress_dialog;
    private DragAndDropHandler dnd_handler = null;

    private bool have_error;
    private string error_title;
    private string error_text;
    private bool error_change_scanner_hint;

    private Book book;
    private string? book_uri = null;

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

    public signal void start_scan (string? device, ScanOptions options);
    public signal void stop_scan ();
    public signal void email (string profile);

    public UserInterface ()
    {
        book = new Book ();
        book.page_removed.connect (page_removed_cb);
        book.page_added.connect (page_added_cb);

        settings = new Settings ("org.gnome.SimpleScan");

        load ();
    }

    ~UserInterface ()
    {
        book.page_removed.disconnect (page_removed_cb);
        book.page_added.disconnect (page_added_cb);
    }

    private bool find_scan_device (string device, out Gtk.TreeIter iter)
    {
        bool have_iter = false;

        if (device_model.get_iter_first (out iter))
        {
            do
            {
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

        if (have_error)
        {
            type = Gtk.MessageType.ERROR;
            image_id = Gtk.Stock.DIALOG_ERROR;
            title = error_title;
            text = error_text;
            show_close_button = true;
            show_change_scanner_button = error_change_scanner_hint;
        }
        else if (device_model.iter_n_children (null) == 0)
        {
            type = Gtk.MessageType.WARNING;
            image_id = Gtk.Stock.DIALOG_WARNING;
            /* Warning displayed when no scanners are detected */
            title = _("No scanners detected");
            /* Hint to user on why there are no scanners detected */
            text = _("Please check your scanner is connected and powered on");
        }
        else
        {
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
            if (device_model.iter_nth_child (out iter, null, index))
            {
                int i = 0;
                do
                {
                    string name;
                    bool matched;

                    device_model.get (iter, 0, out name, -1);
                    matched = name == device.name;

                    if (matched)
                    {
                        n_delete = i;
                        break;
                    }
                    i++;
                } while (device_model.iter_next (ref iter));
            }

            /* If exists, remove elements up to this one */
            if (n_delete >= 0)
            {
                int i;

                /* Update label */
                device_model.set (iter, 1, device.label, -1);

                for (i = 0; i < n_delete; i++)
                {
                    device_model.iter_nth_child (out iter, null, index);
                    device_model.remove (iter);
                }
            }
            else
            {
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

        if (device_combo.get_active_iter (out iter))
        {
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
        directory = settings.get_string ("save-directory");

        if (directory == null || directory == "")
            directory = Environment.get_user_special_dir (UserDirectory.DOCUMENTS);

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
        filter.set_filter_name (/* Save dialog: Filter name to show only image files */
                                _("Image Files"));
        filter.add_pixbuf_formats ();
        filter.add_mime_type ("application/pdf");
        save_dialog.add_filter (filter);
        filter = new Gtk.FileFilter ();
        filter.set_filter_name (/* Save dialog: Filter name to show all files */
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

        if (file_type_store.get_iter_first (out iter))
        {
            do
            {
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

        settings.set_string ("save-directory", save_dialog.get_current_folder ());

        file_type_view.get_selection ().changed.disconnect (on_file_type_changed);
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

        show_progress_dialog ();
        try
        {
            book.save (format, file);
        }
        catch (Error e)
        {
            hide_progress_dialog ();
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

        switch (response)
        {
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

        if (scanning)
            stop_scan ();
        clear_document ();
    }

    private void set_document_hint (string document_hint)
    {
        this.document_hint = document_hint;

        if (document_hint == "text")
        {
            text_toolbar_menuitem.set_active (true);
            text_menu_menuitem.set_active (true);
        }
        else if (document_hint == "photo")
        {
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

    private void set_page_side (ScanType page_side)
    {
        Gtk.TreeIter iter;

        if (page_side_model.get_iter_first (out iter))
        {
            do
            {
                int s;
                page_side_model.get (iter, 0, out s, -1);
                if (s == page_side)
                {
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
             have_iter = paper_size_model.iter_next (ref iter))
        {
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

    private ScanType get_page_side ()
    {
        Gtk.TreeIter iter;
        int page_side = ScanType.ADF_BOTH;

        if (page_side_combo.get_active_iter (out iter))
            page_side_model.get (iter, 0, out page_side, -1);

        return (ScanType) page_side;
    }

    private bool get_paper_size (out int width, out int height)
    {
        Gtk.TreeIter iter;

        width = height = 0;
        if (paper_size_combo.get_active_iter (out iter))
        {
            paper_size_model.get (iter, 0, ref width, 1, ref height, -1);
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
            options.depth = 2;
        }
        else
        {
            options.scan_mode = ScanMode.COLOR;
            options.dpi = get_photo_dpi ();
            options.depth = 8;
        }
        get_paper_size (out options.paper_width, out options.paper_height);

        return options;
    }

    [CCode (cname = "G_MODULE_EXPORT scan_button_clicked_cb", instance_pos = -1)]
    public void scan_button_clicked_cb (Gtk.Widget widget)
    {
        var options = get_scan_options ();
        options.type = ScanType.SINGLE;
        start_scan (get_selected_device (), options);
    }

    [CCode (cname = "G_MODULE_EXPORT stop_scan_button_clicked_cb", instance_pos = -1)]
    public void stop_scan_button_clicked_cb (Gtk.Widget widget)
    {
        stop_scan ();
    }

    [CCode (cname = "G_MODULE_EXPORT continuous_scan_button_clicked_cb", instance_pos = -1)]
    public void continuous_scan_button_clicked_cb (Gtk.Widget widget)
    {
        if (scanning)
            stop_scan ();
        else
        {
            var options = get_scan_options ();
            options.type = get_page_side ();
            start_scan (get_selected_device (), options);
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
        var page = book_view.get_selected ();
        if (page == null)
        {
            page_move_left_menuitem.set_sensitive (false);
            page_move_right_menuitem.set_sensitive (false);
        }
        else
        {
            var index = book.get_page_index (page);
            page_move_left_menuitem.set_sensitive (index > 0);
            page_move_right_menuitem.set_sensitive (index < book.get_n_pages () - 1);
        }
    }

    private void page_selected_cb (BookView view, Page? page)
    {
        if (page == null)
            return;

        updating_page_menu = true;

        update_page_menu ();

        string? name = null;
        if (page.has_crop ())
        {
            // FIXME: Make more generic, move into page-size.c and reuse
            var crop_name = page.get_named_crop ();
            if (crop_name != null)
            {
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
        var page = book_view.get_selected ();
        if (page != null)
            page.rotate_left ();
    }

    [CCode (cname = "G_MODULE_EXPORT rotate_right_button_clicked_cb", instance_pos = -1)]
    public void rotate_right_button_clicked_cb (Gtk.Widget widget)
    {
        if (updating_page_menu)
            return;
        var page = book_view.get_selected ();
        if (page != null)
            page.rotate_right ();
    }

    private void set_crop (string? crop_name)
    {
        crop_rotate_menuitem.set_sensitive (crop_name != null);

        if (updating_page_menu)
            return;

        var page = book_view.get_selected ();
        if (page == null)
            return;

        if (crop_name == null)
        {
            page.set_no_crop ();
            return;
        }
        else if (crop_name == "custom")
        {
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
        if (page.is_landscape () != is_landscape)
        {
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
        print.set_n_pages ((int) book.get_n_pages ());
        print.draw_page.connect (draw_page);

        try
        {
            print.run (Gtk.PrintOperationAction.PRINT_DIALOG, window);
        }
        catch (Error e)
        {
            warning ("Error printing: %s", e.message);
        }

        print.draw_page.disconnect (draw_page);
    }

    [CCode (cname = "G_MODULE_EXPORT help_contents_menuitem_activate_cb", instance_pos = -1)]
    public void help_contents_menuitem_activate_cb (Gtk.Widget widget)
    {
        try
        {
            Gtk.show_uri (window.get_screen (), "help:simple-scan", Gtk.get_current_event_time ());
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

        if (device != null)
            settings.set_string ("selected-device", device);
        settings.set_string ("document-type", document_hint);
        settings.set_int ("text-dpi", get_text_dpi ());
        settings.set_int ("photo-dpi", get_photo_dpi ());
        settings.set_enum ("page-side", get_page_side ());
        settings.set_int ("paper-width", paper_width);
        settings.set_int ("paper-height", paper_height);
        settings.set_int ("window-width", window_width);
        settings.set_int ("window-height", window_height);
        settings.set_boolean ("window-is-maximized", window_is_maximized);
        settings.set_enum ("scan-direction", default_page_scan_direction);
        settings.set_int ("page-width", default_page_width);
        settings.set_int ("page-height", default_page_height);
        settings.set_int ("page-dpi", default_page_dpi);

        window.destroy ();

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
        if (!window_is_maximized)
        {
            window_width = event.width;
            window_height = event.height;
        }

        return false;
    }

    private void info_bar_response_cb (Gtk.InfoBar widget, int response_id)
    {
        if (response_id == 1)
        {
            device_combo.grab_focus ();
            preferences_dialog.present ();
        }
        else
        {
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
        page.size_changed.disconnect (page_size_changed_cb);
        page.scan_direction_changed.disconnect (page_scan_direction_changed_cb);

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

    private void needs_saving_cb (Book book)
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
        var filename = Path.build_filename (Config.UI_DIR, "simple-scan.ui", null);
        try
        {
            builder.add_from_file (filename);
        }
        catch (Error e)
        {
            critical ("Unable to load UI %s: %s\n", filename, e.message);
            show_error_dialog (/* Title of dialog when cannot load required files */
                               _("Files missing"),
                               /* Description in dialog when cannot load required files */
                               _("Please check your installation"));
            Posix.exit (Posix.EXIT_FAILURE);
        }
        builder.connect_signals (this);

        window = (Gtk.Window) builder.get_object ("simple_scan_window");
        var app = Application.get_default () as Gtk.Application;
        app.add_window (window);
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
        var hbox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
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

        var dpi = settings.get_int ("text-dpi");
        if (dpi <= 0)
            dpi = DEFAULT_TEXT_DPI;
        set_dpi_combo (text_dpi_combo, DEFAULT_TEXT_DPI, dpi);
        dpi = settings.get_int ("photo-dpi");
        if (dpi <= 0)
            dpi = DEFAULT_PHOTO_DPI;
        set_dpi_combo (photo_dpi_combo, DEFAULT_PHOTO_DPI, dpi);

        var renderer = new Gtk.CellRendererText ();
        device_combo.pack_start (renderer, true);
        device_combo.add_attribute (renderer, "text", 1);

        renderer = new Gtk.CellRendererText ();
        page_side_combo.pack_start (renderer, true);
        page_side_combo.add_attribute (renderer, "text", 1);
        set_page_side ((ScanType) settings.get_enum ("page-side"));

        renderer = new Gtk.CellRendererText ();
        paper_size_combo.pack_start (renderer, true);
        paper_size_combo.add_attribute (renderer, "text", 2);
        var paper_width = settings.get_int ("paper-width");
        var paper_height = settings.get_int ("paper-height");
        set_paper_size (paper_width, paper_height);

        var device = settings.get_string ("selected-device");
        if (device != null)
        {
            if (find_scan_device (device, out iter))
                device_combo.set_active_iter (iter);
        }

        var document_type = settings.get_string ("document-type");
        if (document_type != null)
            set_document_hint (document_type);

        book_view = new BookView (book);
        book_view.set_border_width (18);
        main_vbox.pack_end (book_view, true, true, 0);
        book_view.page_selected.connect (page_selected_cb);
        book_view.show_page.connect (show_page_cb);
        book_view.show_menu.connect (show_page_menu_cb);
        book_view.show ();

        /* Find default page details */
        default_page_scan_direction = (ScanDirection) settings.get_enum ("scan-direction");
        default_page_width = settings.get_int ("page-width");
        if (default_page_width <= 0)
            default_page_width = 595;
        default_page_height = settings.get_int ("page-height");
        if (default_page_height <= 0)
            default_page_height = 842;
        default_page_dpi = settings.get_int ("page-dpi");
        if (default_page_dpi <= 0)
            default_page_dpi = 72;

        /* Restore window size */
        window_width = settings.get_int ("window-width");
        if (window_width <= 0)
            window_width = 600;
        window_height = settings.get_int ("window-height");
        if (window_height <= 0)
            window_height = 400;
        debug ("Restoring window to %dx%d pixels", window_width, window_height);
        window.set_default_size (window_width, window_height);
        window_is_maximized = settings.get_boolean ("window-is-maximized");
        if (window_is_maximized)
        {
            debug ("Restoring window to maximized");
            window.maximize ();
        }

        if (book.get_n_pages () == 0)
            add_default_page ();
        book.set_needs_saving (false);
        book.needs_saving_changed.connect (needs_saving_cb);

        progress_dialog = new ProgressBarDialog (window, _("Saving document..."));
        book.saving.connect (book_saving_cb);

        dnd_handler = new DragAndDropHandler (book_view);
    }

    private void book_saving_cb (int page_number)
    {
        /* Prevent GUI from freezing */
        while (Gtk.events_pending ())
          Gtk.main_iteration ();

        var total = (int) book.get_n_pages ();
        var fraction = (page_number + 1.0) / total;
        var complete = fraction == 1.0;
        if (complete)
            Timeout.add(500, () => {
                progress_dialog.hide();
                return false;
            });
        var message = _("Saving page %d out of %d").printf (page_number + 1, total);

        progress_dialog.set_fraction (fraction);
        progress_dialog.set_message (message);
    }

    public void show_progress_dialog ()
    {
        progress_dialog.show ();
    }

    public void hide_progress_dialog ()
    {
        progress_dialog.hide ();
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

class ProgressBarDialog : Gtk.Window
{
    Gtk.ProgressBar bar;

    public ProgressBarDialog (Gtk.Window parent, string title)
    {
        bar = new Gtk.ProgressBar ();
        var hbox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 5);
        var vbox = new Gtk.Box (Gtk.Orientation.VERTICAL, 5);
        hbox.set_hexpand (true);

        bar.set_text ("");
        bar.set_show_text (true);
        bar.set_size_request (225, 25);
        set_size_request (250, 50);

        vbox.pack_start (bar, true, false, 0);
        hbox.pack_start (vbox, true, false, 0);
        add (hbox);
        set_title (title);

        set_transient_for (parent);
        set_position (Gtk.WindowPosition.CENTER_ON_PARENT);
        set_modal (true);
        set_resizable (false);

        hbox.show ();
        vbox.show ();
        bar.show ();
    }

    public void set_fraction (double percent)
    {
        bar.set_fraction (percent);
    }

    public void set_message (string message)
    {
        bar.set_text (message);
    }
}

class DragAndDropHandler
{
    private enum TargetType
    {
        IMAGE,
        URI
    }

    private BookView book_view;

    public DragAndDropHandler (BookView book_view)
    {
        this.book_view = book_view;
        var event_source = book_view.get_event_source ();

        set_targets (event_source);
        event_source.drag_data_get.connect (on_drag_data_get);
    }

    private void set_targets (Gtk.Widget event_source)
    {
        var table = new Gtk.TargetEntry [0];
        var targets = new Gtk.TargetList (table);
        targets.add_uri_targets (TargetType.URI);
        targets.add_image_targets (TargetType.IMAGE, true);

        Gtk.drag_source_set (event_source, Gdk.ModifierType.BUTTON1_MASK, table, Gdk.DragAction.COPY);
        Gtk.drag_source_set_target_list (event_source, targets);
    }

    private void on_drag_data_get (Gdk.DragContext context, Gtk.SelectionData selection, uint target_type, uint time)
    {
        var page = book_view.get_selected ();
        return_if_fail (page != null);

        switch (target_type)
        {
        case TargetType.IMAGE:
            var image = page.get_image (true);
            selection.set_pixbuf (image);

            debug ("Saving page to pixbuf");
            break;

        case TargetType.URI:
            var filetype = "png";
            var path = get_temporary_filename ("scanned-page", filetype);
            return_if_fail (path != null);

            var file = File.new_for_path (path);
            var uri = file.get_uri ();

            try
            {
                page.save (filetype, file);
                selection.set_uris ({ uri });
                debug ("Saving page to %s", uri);
            }
            catch (Error e)
            {
                warning ("Unable to save file using drag-drop %s", e.message);
            }
            break;

        default:
            warning ("Invalid DND target type %u", target_type);
            break;
        }
    }
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

