/*
 * Copyright (C) 2009-2011 Canonical Ltd.
 * Author: Robert Ancell <robert.ancell@canonical.com>,
 *         Eduard Gotwig <g@ox.io>
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

    private const GLib.ActionEntry[] action_entries =
    {
        { "new_document", new_document_activate_cb },
        { "save", save_document_activate_cb },
        { "save_as", save_as_document_activate_cb },
        { "email", email_document_activate_cb },
        { "print", print_document_activate_cb },
        { "preferences", preferences_activate_cb },
        { "help", help_contents_activate_cb },
        { "about", about_activate_cb },
        { "quit", quit_activate_cb }
    };

    private Settings settings;

    private Gtk.Builder builder;

    private Gtk.ApplicationWindow window;
    private GLib.MenuModel app_menu;
    private Gtk.Box main_vbox;
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
    private Gtk.MenuItem copy_to_clipboard_menuitem;
    private Gtk.Button save_button;
    private Gtk.ToolButton save_toolbutton;
    private Gtk.MenuItem stop_menuitem;
    private Gtk.ToolButton stop_toolbutton;
    private Gtk.Button stop_button;
    private Gtk.Button scan_button;

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
    private Gtk.Scale brightness_scale;
    private Gtk.Scale contrast_scale;
    private Gtk.Scale quality_scale;
    private Gtk.ListStore device_model;
    private Gtk.ListStore text_dpi_model;
    private Gtk.ListStore photo_dpi_model;
    private Gtk.ListStore page_side_model;
    private Gtk.ListStore paper_size_model;
    private Gtk.Adjustment brightness_adjustment;
    private Gtk.Adjustment contrast_adjustment;
    private Gtk.Adjustment quality_adjustment;
    private bool setting_devices;
    private bool user_selected_device;

    private Gtk.FileChooserDialog? save_dialog;
    private ProgressBarDialog progress_dialog;

    private bool have_error;
    private string error_title;
    private string error_text;
    private bool error_change_scanner_hint;

    public Book book { get; private set; }
    private string? book_uri = null;

    public Page selected_page
    {
        get
        {
            return book_view.selected_page;
        }
        set
        {
            book_view.selected_page = value;
        }
    }

    private AutosaveManager autosave_manager;

    private BookView book_view;
    private bool updating_page_menu;
    private int default_page_width;
    private int default_page_height;
    private int default_page_dpi;
    private ScanDirection default_page_scan_direction;

    private string document_hint = "photo";

    public string default_file_name { get; set; default = _("Scanned Document.pdf"); }
    private bool scanning_ = false;
    public bool scanning
    {
        get { return scanning_; }
        set
        {
            scanning_ = value;
            page_delete_menuitem.sensitive = !value;
            stop_menuitem.sensitive = value;
            stop_toolbutton.sensitive = value;
            scan_button.visible = !value;
            stop_button.visible = value;
        }
    }

    private int window_width;
    private int window_height;
    private bool window_is_maximized;

    private uint save_state_timeout;

    public int brightness
    {
        get { return (int) brightness_adjustment.value; }
        set { brightness_adjustment.value = value; }
    }

    public int contrast
    {
        get { return (int) contrast_adjustment.value; }
        set { contrast_adjustment.value = value; }
    }

    public int quality
    {
        get { return (int) quality_adjustment.value; }
        set { quality_adjustment.value = value; }
    }

    public string? selected_device
    {
        owned get
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

        set
        {
            Gtk.TreeIter iter;
            if (!find_scan_device (value, out iter))
                return;

            device_combo.set_active_iter (iter);
            user_selected_device = true;
        }
    }

    public signal void start_scan (string? device, ScanOptions options);
    public signal void stop_scan ();
    public signal void email (string profile, int quality);

    public UserInterface ()
    {
        settings = new Settings ("org.gnome.SimpleScan");

        book = new Book ();
        book.page_added.connect (page_added_cb);
        book.reordered.connect (reordered_cb);
        book.page_removed.connect (page_removed_cb);

        load ();

        autosave_manager = new AutosaveManager ();
        autosave_manager.book = book;
        autosave_manager.load ();

        if (book.n_pages == 0)
        {
            add_default_page ();
            book.needs_saving = false;
        }
        else
            book_view.selected_page = book.get_page (0);
        book.needs_saving_changed.connect (needs_saving_cb);
    }

    ~UserInterface ()
    {
        book.page_added.disconnect (page_added_cb);
        book.reordered.disconnect (reordered_cb);
        book.page_removed.disconnect (page_removed_cb);
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
        dialog.add_button (_("_Close"), 0);
        dialog.format_secondary_text ("%s", error_text);
        dialog.destroy ();
    }

    public void authorize (string resource, out string username, out string password)
    {
        /* Label in authorization dialog.  '%s' is replaced with the name of the resource requesting authorization */
        var description = _("Username and password required to access '%s'").printf (resource);

        username_entry.text = "";
        password_entry.text = "";
        authorize_label.set_text (description);

        authorize_dialog.visible = true;
        authorize_dialog.run ();
        authorize_dialog.visible = false;

        username = username_entry.text;
        password = password_entry.text;
    }

    [CCode (cname = "G_MODULE_EXPORT device_combo_changed_cb", instance_pos = -1)]
    public void device_combo_changed_cb (Gtk.Widget widget)
    {
        if (setting_devices)
            return;
        user_selected_device = true;
        if (selected_device != null)
            settings.set_string ("selected-device", selected_device);
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
            image_id = "dialog-error";
            title = error_title;
            text = error_text;
            show_close_button = true;
            show_change_scanner_button = error_change_scanner_hint;
        }
        else if (device_model.iter_n_children (null) == 0)
        {
            type = Gtk.MessageType.WARNING;
            image_id = "dialog-warning";
            /* Warning displayed when no scanners are detected */
            title = _("No scanners detected");
            /* Hint to user on why there are no scanners detected */
            text = _("Please check your scanner is connected and powered on");
        }
        else
        {
            info_bar.visible = false;
            return;
        }

        info_bar.message_type = type;
        info_bar_image.set_from_icon_name (image_id, Gtk.IconSize.DIALOG);
        var message = "<big><b>%s</b></big>\n\n%s".printf (title, text);
        info_bar_label.set_markup (message);
        info_bar_close_button.visible = show_close_button;
        info_bar_change_scanner_button.visible = show_change_scanner_button;
        info_bar.visible = true;
    }

    public void set_scan_devices (List<ScanDevice> devices)
    {
        bool have_selection = false;
        int index;
        Gtk.TreeIter iter;

        setting_devices = true;

        /* If the user hasn't chosen a scanner choose the best available one */
        if (user_selected_device)
            have_selection = device_combo.active >= 0;

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

    private void add_default_page ()
    {
        var page = new Page (default_page_width,
                             default_page_height,
                             default_page_dpi,
                             default_page_scan_direction);
        book.append_page (page);
        book_view.selected_page = page;
    }

    private void on_file_type_changed (Gtk.TreeSelection selection)
    {
        var extension = get_selected_extension (selection);
        var path = save_dialog.get_filename ();
        var filename = Path.get_basename (path);

        /* Replace extension */
        var extension_index = filename.last_index_of_char ('.');
        if (extension_index >= 0)
            filename = filename.slice (0, extension_index);
        filename = filename + extension;
        save_dialog.set_current_name (filename);
    }

    private string get_selected_extension (Gtk.TreeSelection selection)
    {
        Gtk.TreeModel model;
        Gtk.TreeIter iter;
        string extension = "";

        if (selection.get_selected (out model, out iter))
            model.get (iter, 1, out extension, -1);
        return extension;
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
                                                 _("_Cancel"), Gtk.ResponseType.CANCEL,
                                                 _("_Save"), Gtk.ResponseType.ACCEPT,
                                                 null);
        save_dialog.do_overwrite_confirmation = true;
        save_dialog.local_only = false;
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
        expander.spacing = 5;
        save_dialog.set_extra_widget (expander);

        string default_extension = "";
        var index = default_file_name.last_index_of_char ('.');
        if (index >= 0)
            default_extension = default_file_name.substring (index);

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
        file_type_view.headers_visible = false;
        file_type_view.rules_hint = true;
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
                if (default_extension == e)
                    file_type_view.get_selection ().select_iter (iter);
            } while (file_type_store.iter_next (ref iter));
        }
        file_type_view.get_selection ().changed.connect (on_file_type_changed);

        expander.show_all ();

        var response = save_dialog.run ();

        string? uri = null;
        if (response == Gtk.ResponseType.ACCEPT)
        {
            var selection = file_type_view.get_selection ();
            var extension = get_selected_extension (selection);

            var path = save_dialog.get_filename ();
            var filename = Path.get_basename (path);
            
            var extension_index = filename.last_index_of_char ('.');
            if (extension_index < 0)
                path += extension;

            uri = File.new_for_path (path).get_uri ();
        }

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
            book.save (format, quality, file);
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
        book.needs_saving = false;
        return true;
    }

    private bool prompt_to_save (string title, string discard_label)
    {
        if (!book.needs_saving)
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
        dialog.add_button (_("_Cancel"), Gtk.ResponseType.CANCEL);
        dialog.add_button (_("_Save"), Gtk.ResponseType.YES);

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
        book.needs_saving = false;
        save_as_menuitem.sensitive = false;
        copy_to_clipboard_menuitem.sensitive = false;
    }

    private void new_document ()
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

    [CCode (cname = "G_MODULE_EXPORT new_button_clicked_cb", instance_pos = -1)]
    public void new_button_clicked_cb (Gtk.Widget widget)
    {
        new_document();
    }

    public void new_document_activate_cb ()
    {
        new_document();
    }

    private void set_document_hint (string document_hint, bool save = false)
    {
        this.document_hint = document_hint;

        if (document_hint == "text")
        {
            text_toolbar_menuitem.active = true;
            text_menu_menuitem.active = true;
        }
        else if (document_hint == "photo")
        {
            photo_toolbar_menuitem.active = true;
            photo_menu_menuitem.active = true;
        }

        if (save)
            settings.set_string ("document-type", document_hint);
    }

    [CCode (cname = "G_MODULE_EXPORT text_menuitem_toggled_cb", instance_pos = -1)]
    public void text_menuitem_toggled_cb (Gtk.CheckMenuItem widget)
    {
        if (widget.active)
            set_document_hint ("text", true);
    }

    [CCode (cname = "G_MODULE_EXPORT photo_menuitem_toggled_cb", instance_pos = -1)]
    public void photo_menuitem_toggled_cb (Gtk.CheckMenuItem widget)
    {
        if (widget.active)
        {
            set_document_hint ("photo", true);
        }
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

    private ScanOptions make_scan_options ()
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
        options.brightness = brightness;
        options.contrast = contrast;

        return options;
    }

    [CCode (cname = "G_MODULE_EXPORT scan_button_clicked_cb", instance_pos = -1)]
    public void scan_button_clicked_cb (Gtk.Widget widget)
    {
        var options = make_scan_options ();
        options.type = ScanType.SINGLE;
        start_scan (selected_device, options);
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
            var options = make_scan_options ();
            options.type = get_page_side ();
            start_scan (selected_device, options);
        }
    }

    [CCode (cname = "G_MODULE_EXPORT preferences_button_clicked_cb", instance_pos = -1)]
    public void preferences_button_clicked_cb (Gtk.Widget widget)
    {
        preferences_dialog.present ();
    }

    public void preferences_activate_cb ()
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
        preferences_dialog.visible = false;
    }

    private void update_page_menu ()
    {
        var page = book_view.selected_page;
        if (page == null)
        {
            page_move_left_menuitem.sensitive = false;
            page_move_right_menuitem.sensitive = false;
        }
        else
        {
            var index = book.get_page_index (page);
            page_move_left_menuitem.sensitive = index > 0;
            page_move_right_menuitem.sensitive = index < book.n_pages - 1;
        }
    }

    private void page_selected_cb (BookView view, Page? page)
    {
        if (page == null)
            return;

        updating_page_menu = true;

        update_page_menu ();

        var name = "no_crop_menuitem";
        if (page.has_crop)
        {
            // FIXME: Make more generic, move into page-size.c and reuse
            var crop_name = page.crop_name;
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

        var menuitem = builder.get_object (name) as Gtk.RadioMenuItem;
        menuitem.active = true;
        var crop_button = builder.get_object ("crop_button") as Gtk.ToggleButton;
        crop_button.active = page.has_crop;

        var crop_toolbutton = builder.get_object ("crop_toolbutton") as Gtk.ToggleToolButton;
        crop_toolbutton.active = page.has_crop;
        
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
            page.save ("tiff", quality, file);
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
            Gtk.show_uri (window.screen, file.get_uri (), Gtk.get_current_event_time ());
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
        var menu = builder.get_object ("page_menu") as Gtk.Menu;
        menu.popup (null, null, null, 3, Gtk.get_current_event_time ());
    }

    [CCode (cname = "G_MODULE_EXPORT rotate_left_button_clicked_cb", instance_pos = -1)]
    public void rotate_left_button_clicked_cb (Gtk.Widget widget)
    {
        if (updating_page_menu)
            return;
        var page = book_view.selected_page;
        if (page != null)
            page.rotate_left ();
    }

    [CCode (cname = "G_MODULE_EXPORT rotate_right_button_clicked_cb", instance_pos = -1)]
    public void rotate_right_button_clicked_cb (Gtk.Widget widget)
    {
        if (updating_page_menu)
            return;
        var page = book_view.selected_page;
        if (page != null)
            page.rotate_right ();
    }

    private void set_crop (string? crop_name)
    {
        crop_rotate_menuitem.sensitive = crop_name != null;

        if (updating_page_menu)
            return;

        var page = book_view.selected_page;
        if (page == null)
        {
            warning ("Trying to set crop but no selected page");
            return;
        }

        if (crop_name == null)
            page.set_no_crop ();
        else if (crop_name == "custom")
        {
            var width = page.width;
            var height = page.height;
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
        if (widget.active)
            set_crop (null);
    }

    [CCode (cname = "G_MODULE_EXPORT custom_crop_menuitem_toggled_cb", instance_pos = -1)]
    public void custom_crop_menuitem_toggled_cb (Gtk.CheckMenuItem widget)
    {
        if (widget.active)
            set_crop ("custom");
    }

    [CCode (cname = "G_MODULE_EXPORT crop_button_toggled_cb", instance_pos = -1)]
    public void crop_button_toggled_cb (Gtk.ToggleButton widget)
    {
        if (updating_page_menu)
            return;

        Gtk.RadioMenuItem menuitem;
        if (widget.active)
            menuitem = builder.get_object ("custom_crop_menuitem") as Gtk.RadioMenuItem;
        else
            menuitem = builder.get_object ("no_crop_menuitem") as Gtk.RadioMenuItem;
        menuitem.active = true;
    }
    
    [CCode (cname = "G_MODULE_EXPORT crop_toolbutton_toggled_cb", instance_pos = -1)]
    public void crop_toolbutton_toggled_cb (Gtk.ToggleToolButton widget)
    {
        if (updating_page_menu)
            return;

        Gtk.RadioMenuItem menuitem;
        if (widget.active)
            menuitem = builder.get_object ("custom_crop_menuitem") as Gtk.RadioMenuItem;
        else
            menuitem = builder.get_object ("no_crop_menuitem") as Gtk.RadioMenuItem;
        menuitem.active = true;
    }

    [CCode (cname = "G_MODULE_EXPORT four_by_six_menuitem_toggled_cb", instance_pos = -1)]
    public void four_by_six_menuitem_toggled_cb (Gtk.CheckMenuItem widget)
    {
        if (widget.active)
            set_crop ("4x6");
    }

    [CCode (cname = "G_MODULE_EXPORT legal_menuitem_toggled_cb", instance_pos = -1)]
    public void legal_menuitem_toggled_cb (Gtk.CheckMenuItem widget)
    {
        if (widget.active)
            set_crop ("legal");
    }

    [CCode (cname = "G_MODULE_EXPORT letter_menuitem_toggled_cb", instance_pos = -1)]
    public void letter_menuitem_toggled_cb (Gtk.CheckMenuItem widget)
    {
        if (widget.active)
            set_crop ("letter");
    }

    [CCode (cname = "G_MODULE_EXPORT a6_menuitem_toggled_cb", instance_pos = -1)]
    public void a6_menuitem_toggled_cb (Gtk.CheckMenuItem widget)
    {
        if (widget.active)
            set_crop ("A6");
    }

    [CCode (cname = "G_MODULE_EXPORT a5_menuitem_toggled_cb", instance_pos = -1)]
    public void a5_menuitem_toggled_cb (Gtk.CheckMenuItem widget)
    {
        if (widget.active)
            set_crop ("A5");
    }

    [CCode (cname = "G_MODULE_EXPORT a4_menuitem_toggled_cb", instance_pos = -1)]
    public void a4_menuitem_toggled_cb (Gtk.CheckMenuItem widget)
    {
        if (widget.active)
            set_crop ("A4");
    }

    [CCode (cname = "G_MODULE_EXPORT crop_rotate_menuitem_activate_cb", instance_pos = -1)]
    public void crop_rotate_menuitem_activate_cb (Gtk.Widget widget)
    {
        var page = book_view.selected_page;
        if (page == null)
            return;
        page.rotate_crop ();
    }

    [CCode (cname = "G_MODULE_EXPORT page_move_left_menuitem_activate_cb", instance_pos = -1)]
    public void page_move_left_menuitem_activate_cb (Gtk.Widget widget)
    {
        var page = book_view.selected_page;
        var index = book.get_page_index (page);
        if (index > 0)
            book.move_page (page, index - 1);
    }

    [CCode (cname = "G_MODULE_EXPORT page_move_right_menuitem_activate_cb", instance_pos = -1)]
    public void page_move_right_menuitem_activate_cb (Gtk.Widget widget)
    {
        var page = book_view.selected_page;
        var index = book.get_page_index (page);
        if (index < book.n_pages - 1)
            book.move_page (page, book.get_page_index (page) + 1);
    }

    [CCode (cname = "G_MODULE_EXPORT page_delete_menuitem_activate_cb", instance_pos = -1)]
    public void page_delete_menuitem_activate_cb (Gtk.Widget widget)
    {
        book_view.book.delete_page (book_view.selected_page);
    }

    [CCode (cname = "G_MODULE_EXPORT reorder_menuitem_activate_cb", instance_pos = -1)]
    public void reorder_menuitem_activate_cb (Gtk.Widget widget)
    {
        var dialog = new Gtk.Window ();
        dialog.type_hint = Gdk.WindowTypeHint.DIALOG;
        dialog.modal = true;
        dialog.border_width = 12;
        /* Title of dialog to reorder pages */
        dialog.title = _("Reorder Pages");
        dialog.set_transient_for (window);
        dialog.key_press_event.connect ((e) =>
        {
            if (e.state == 0 && e.keyval == Gdk.Key.Escape)
            {
                dialog.destroy ();
                return true;
            }

            return false;
        });
        dialog.visible = true;

        var g = new Gtk.Grid ();
        g.row_homogeneous = true;
        g.row_spacing = 6;
        g.column_homogeneous = true;
        g.column_spacing = 6;
        g.visible = true;
        dialog.add (g);

        /* Label on button for combining sides in reordering dialog */
        var b = make_reorder_button (_("Combine sides"), "F1F2F3B1B2B3-F1B1F2B2F3B3");
        b.clicked.connect (() =>
        {
            book.combine_sides ();
            dialog.destroy ();
        });
        b.visible = true;
        g.attach (b, 0, 0, 1, 1);

        /* Label on button for combining sides in reverse order in reordering dialog */
        b = make_reorder_button (_("Combine sides (reverse)"), "F1F2F3B3B2B1-F1B1F2B2F3B3");
        b.clicked.connect (() =>
        {
            book.combine_sides_reverse ();
            dialog.destroy ();
        });
        b.visible = true;
        g.attach (b, 1, 0, 1, 1);

        /* Label on button for reversing in reordering dialog */
        b = make_reorder_button (_("Reverse"), "C1C2C3C4C5C6-C6C5C4C3C2C1");
        b.clicked.connect (() =>
        {
            book.reverse ();           
            dialog.destroy ();
        });
        b.visible = true;
        g.attach (b, 0, 2, 1, 1);

        /* Label on button for cancelling page reordering dialog */
        b = make_reorder_button (_("Keep unchanged"), "C1C2C3C4C5C6-C1C2C3C4C5C6");
        b.clicked.connect (() =>
        {
            dialog.destroy ();
        });
        b.visible = true;
        g.attach (b, 1, 2, 1, 1);

        dialog.present ();
    }

    private Gtk.Button make_reorder_button (string text, string items)
    {
        var b = new Gtk.Button ();
        
        var vbox = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
        vbox.visible = true;
        b.add (vbox);

        var label = new Gtk.Label (text);
        label.visible = true;
        vbox.pack_start (label, true, true, 0);

        var rb = make_reorder_box (items);
        rb.visible = true;
        vbox.pack_start (rb, true, true, 0);

        return b;
    }

    private Gtk.Box make_reorder_box (string items)
    {
        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
        box.visible = true;

        Gtk.Box? page_box = null;
        for (var i = 0; items[i] != '\0'; i++)
        {
            if (items[i] == '-')
            {
                var a = new Gtk.Arrow (Gtk.ArrowType.RIGHT, Gtk.ShadowType.NONE);
                a.visible = true;
                box.pack_start (a, false, false, 0);
                page_box = null;
                continue;
            }

            /* First character describes side */
            var side = items[i];
            i++;
            if (items[i] == '\0')
                break;

            if (page_box == null)
            {
                page_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 3);
                page_box.visible = true;
                box.pack_start (page_box, false, false, 0);
            }

            /* Get colours for each page (from Tango palette) */
            var r = 1.0;
            var g = 1.0;
            var b = 1.0;
            switch (side)
            {
            case 'F':
                /* Plum */
                r = 0x75 / 255.0;
                g = 0x50 / 255.0;
                b = 0x7B / 255.0;
                break;
            case 'B':
                /* Orange */
                r = 0xF5 / 255.0;
                g = 0x79 / 255.0;
                b = 0.0;
                break;
            case 'C':
                /* Butter to Scarlet Red */
                var p = (items[i] - '1') / 5.0;
                r = (0xED / 255.0) * (1 - p) + 0xCC * p;
                g = (0xD4 / 255.0) * (1 - p);
                b = 0;
                break;
            }

            /* Mix with white to look more paper like */
            r = r + (1.0 - r) * 0.7;
            g = g + (1.0 - g) * 0.7;
            b = b + (1.0 - b) * 0.7;

            var icon = new PageIcon ("%c".printf (items[i]), r, g, b);
            icon.visible = true;
            page_box.pack_start (icon, false, false, 0);
        }

        return box;
    }

    [CCode (cname = "G_MODULE_EXPORT save_file_button_clicked_cb", instance_pos = -1)]
    public void save_file_button_clicked_cb (Gtk.Widget widget)
    {
        save_document (false);
    }

    public void save_document_activate_cb ()
    {
        save_document (false);
    }

    [CCode (cname = "G_MODULE_EXPORT copy_to_clipboard_button_clicked_cb", instance_pos = -1)]
    public void copy_to_clipboard_button_clicked_cb (Gtk.Widget widget)
    {
        var page = book_view.selected_page;
        if (page != null)
            page.copy_to_clipboard (window);
    }

    [CCode (cname = "G_MODULE_EXPORT save_as_file_button_clicked_cb", instance_pos = -1)]
    public void save_as_file_button_clicked_cb (Gtk.Widget widget)
    {
        save_document (true);
    }

    public void save_as_document_activate_cb ()
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
        if (page.is_landscape != is_landscape)
        {
            context.translate (print_context.get_width (), 0);
            context.rotate (Math.PI_2);
        }

        context.scale (print_context.get_dpi_x () / page.dpi,
                       print_context.get_dpi_y () / page.dpi);

        var image = page.get_image (true);
        Gdk.cairo_set_source_pixbuf (context, image, 0, 0);
        context.paint ();
    }

    [CCode (cname = "G_MODULE_EXPORT email_button_clicked_cb", instance_pos = -1)]
    public void email_button_clicked_cb (Gtk.Widget widget)
    {
        email (document_hint, quality);
    }

    public void email_document_activate_cb ()
    {
        email (document_hint, quality);
    }
    
    private void print_document ()
    {
        var print = new Gtk.PrintOperation ();
        print.n_pages = (int) book.n_pages;
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

    [CCode (cname = "G_MODULE_EXPORT print_button_clicked_cb", instance_pos = -1)]
    public void print_button_clicked_cb (Gtk.Widget widget)
    {
        print_document ();
    }

    public void print_document_activate_cb ()
    {
        print_document ();
    }

    private void show_help ()
    {
        try
        {
            Gtk.show_uri (window.screen, "help:simple-scan", Gtk.get_current_event_time ());
        }
        catch (Error e)
        {
            show_error_dialog (/* Error message displayed when unable to launch help browser */
                               _("Unable to open help file"),
                               e.message);
        }
    }

    [CCode (cname = "G_MODULE_EXPORT help_contents_menuitem_activate_cb", instance_pos = -1)]
    public void help_contents_menuitem_activate_cb (Gtk.Widget widget)
    {
        show_help ();
    }

    public void help_contents_activate_cb ()
    {
        show_help ();
    }

    private void show_about ()
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
                               "version", VERSION,
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

    [CCode (cname = "G_MODULE_EXPORT about_menuitem_activate_cb", instance_pos = -1)]
    public void about_menuitem_activate_cb (Gtk.Widget widget)
    {
        show_about ();
    }

    public void about_activate_cb ()
    {
        show_about ();
    }

    private bool on_quit ()
    {
        if (!prompt_to_save (/* Text in dialog warning when a document is about to be lost */
                             _("Save document before quitting?"),
                             /* Button in dialog to quit and discard unsaved document */
                             _("Quit without Saving")))
            return false;

        window.destroy ();

        if (save_state_timeout != 0)
            save_state (true);

        autosave_manager.cleanup ();

        return true;
    }

    [CCode (cname = "G_MODULE_EXPORT quit_menuitem_activate_cb", instance_pos = -1)]
    public void quit_menuitem_activate_cb (Gtk.Widget widget)
    {
        on_quit ();
    }

    public void quit_activate_cb ()
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
            save_state ();
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
        {
            window_is_maximized = (event.new_window_state & Gdk.WindowState.MAXIMIZED) != 0;
            save_state ();
        }
        return false;
    }

    [CCode (cname = "G_MODULE_EXPORT window_delete_event_cb", instance_pos = -1)]
    public bool window_delete_event_cb (Gtk.Widget widget, Gdk.Event event)
    {
        return !on_quit ();
    }

    private void page_size_changed_cb (Page page)
    {
        default_page_width = page.width;
        default_page_height = page.height;
        default_page_dpi = page.dpi;
        save_state ();
    }

    private void page_scan_direction_changed_cb (Page page)
    {
        default_page_scan_direction = page.scan_direction;
        save_state ();
    }

    private void page_added_cb (Book book, Page page)
    {
        page_size_changed_cb (page);
        default_page_scan_direction = page.scan_direction;
        page.size_changed.connect (page_size_changed_cb);
        page.scan_direction_changed.connect (page_scan_direction_changed_cb);

        update_page_menu ();
    }

    private void reordered_cb (Book book)
    {
        update_page_menu ();
    }

    private void page_removed_cb (Book book, Page page)
    {
        page.size_changed.disconnect (page_size_changed_cb);
        page.scan_direction_changed.disconnect (page_scan_direction_changed_cb);

        /* If this is the last page add a new blank one */
        if (book.n_pages == 1)
            add_default_page ();

        update_page_menu ();
    }

    private void set_dpi_combo (Gtk.ComboBox combo, int default_dpi, int current_dpi)
    {
        var renderer = new Gtk.CellRendererText ();
        combo.pack_start (renderer, true);
        combo.add_attribute (renderer, "text", 1);

        var model = combo.model as Gtk.ListStore;
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
        save_menuitem.sensitive = book.needs_saving;
        save_button.sensitive = book.needs_saving;
        save_toolbutton.sensitive = book.needs_saving;
        if (book.needs_saving)
            save_as_menuitem.sensitive = true;
        copy_to_clipboard_menuitem.sensitive = true;
    }

    private bool has_app_menu (Gtk.Application app)
    {
        /* We have three cases:
         * - GNOME 3: show-app-menu true, show-menubar false -> use the app menu
         * - Unity, OSX: show-app-menu and show-menubar true -> use the normal menu
         * - Other WM, Windows: show-app-menu and show-menubar false -> use the normal menu
         */
        var gtk_settings = Gtk.Settings.get_default ();

        bool show_app_menu = false;
        bool show_menubar = true;
        gtk_settings.get ("gtk-shell-shows-app-menu", &show_app_menu, "gtk-shell-shows-menubar", &show_menubar, null);

        return show_app_menu && !show_menubar;
    }

    private void load ()
    {
        Gtk.IconTheme.get_default ().append_search_path (ICON_DIR);

        Gtk.Window.set_default_icon_name ("scanner");

        var app = Application.get_default () as Gtk.Application;

        builder = new Gtk.Builder ();
        try
        {
            builder.add_from_resource ("/org/gnome/SimpleScan/simple-scan.ui");
        if (has_app_menu (app))
        {
            builder.add_from_resource ("/org/gnome/SimpleScan/simple-scan-menu.ui");
        }

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

 window = builder.get_object ("simple_scan_window") as Gtk.ApplicationWindow;
        if (has_app_menu (app))
        {
            app_menu = builder.get_object ("appmenu") as GLib.MenuModel;
            app.add_action_entries (action_entries, this);
            app.app_menu = app_menu;
        }
        else
        {
            window.set_titlebar (null);
            var menubar = builder.get_object ("menubar") as Gtk.MenuBar;
            menubar.visible = true;
            var toolbar = builder.get_object ("toolbar") as Gtk.Toolbar;
            toolbar.visible = true;
        }
        app.add_window (window);
        main_vbox = builder.get_object ("main_vbox") as Gtk.Box;
        page_move_left_menuitem = builder.get_object ("page_move_left_menuitem") as Gtk.MenuItem;
        page_move_right_menuitem = builder.get_object ("page_move_right_menuitem") as Gtk.MenuItem;
        page_delete_menuitem = builder.get_object ("page_delete_menuitem") as Gtk.MenuItem;
        crop_rotate_menuitem = builder.get_object ("crop_rotate_menuitem") as Gtk.MenuItem;
        save_menuitem = builder.get_object ("save_menuitem") as Gtk.MenuItem;
        save_as_menuitem = builder.get_object ("save_as_menuitem") as Gtk.MenuItem;
        copy_to_clipboard_menuitem = builder.get_object ("copy_to_clipboard_menuitem") as Gtk.MenuItem;
        save_button = builder.get_object ("save_button") as Gtk.Button;
        save_toolbutton = builder.get_object ("save_toolbutton") as Gtk.ToolButton;
        stop_menuitem = builder.get_object ("stop_scan_menuitem") as Gtk.MenuItem;
        stop_button = builder.get_object ("stop_button") as Gtk.Button;
        stop_toolbutton = builder.get_object ("stop_toolbutton") as Gtk.ToolButton;
        scan_button = builder.get_object ("scan_button") as Gtk.Button;

        text_toolbar_menuitem = builder.get_object ("text_toolbutton_menuitem") as Gtk.RadioMenuItem;
        text_menu_menuitem = builder.get_object ("text_menuitem") as Gtk.RadioMenuItem;
        photo_toolbar_menuitem = builder.get_object ("photo_toolbutton_menuitem") as Gtk.RadioMenuItem;
        photo_menu_menuitem = builder.get_object ("photo_menuitem") as Gtk.RadioMenuItem;

        authorize_dialog = builder.get_object ("authorize_dialog") as Gtk.Dialog;
        authorize_label = builder.get_object ("authorize_label") as Gtk.Label;
        username_entry = builder.get_object ("username_entry") as Gtk.Entry;
        password_entry = builder.get_object ("password_entry") as Gtk.Entry;

        preferences_dialog = builder.get_object ("preferences_dialog") as Gtk.Dialog;
        device_combo = builder.get_object ("device_combo") as Gtk.ComboBox;
        device_model = device_combo.model as Gtk.ListStore;
        text_dpi_combo = builder.get_object ("text_dpi_combo") as Gtk.ComboBox;
        text_dpi_model = text_dpi_combo.model as Gtk.ListStore;
        photo_dpi_combo = builder.get_object ("photo_dpi_combo") as Gtk.ComboBox;
        photo_dpi_model = photo_dpi_combo.model as Gtk.ListStore;
        page_side_combo = builder.get_object ("page_side_combo") as Gtk.ComboBox;
        page_side_model = page_side_combo.model as Gtk.ListStore;
        paper_size_combo = builder.get_object ("paper_size_combo") as Gtk.ComboBox;
        paper_size_model = paper_size_combo.model as Gtk.ListStore;
        brightness_scale = builder.get_object ("brightness_scale") as Gtk.Scale;
        brightness_adjustment = brightness_scale.adjustment as Gtk.Adjustment;
        contrast_scale = builder.get_object ("contrast_scale") as Gtk.Scale;
        contrast_adjustment = contrast_scale.adjustment as Gtk.Adjustment;
        quality_scale = builder.get_object ("quality_scale") as Gtk.Scale;
        quality_adjustment = quality_scale.adjustment as Gtk.Adjustment;

        /* Add InfoBar (not supported in Glade) */
        info_bar = new Gtk.InfoBar ();
        info_bar.response.connect (info_bar_response_cb);
        main_vbox.pack_start (info_bar, false, true, 0);
        var hbox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
        var content_area = info_bar.get_content_area () as Gtk.Container;
        content_area.add (hbox);
        hbox.visible = true;

        info_bar_image = new Gtk.Image.from_icon_name ("dialog-warning", Gtk.IconSize.DIALOG);
        hbox.pack_start (info_bar_image, false, true, 0);
        info_bar_image.visible = true;

        info_bar_label = new Gtk.Label (null);
        info_bar_label.set_alignment (0.0f, 0.5f);
        hbox.pack_start (info_bar_label, true, true, 0);
        info_bar_label.visible = true;

        info_bar_close_button = info_bar.add_button (_("_Close"), Gtk.ResponseType.CLOSE) as Gtk.Button;
        info_bar_change_scanner_button = info_bar.add_button (/* Button in error infobar to open preferences dialog and change scanner */
                                                              _("Change _Scanner"), 1) as Gtk.Button;

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
        text_dpi_combo.changed.connect (() => { settings.set_int ("text-dpi", get_text_dpi ()); });
        dpi = settings.get_int ("photo-dpi");
        if (dpi <= 0)
            dpi = DEFAULT_PHOTO_DPI;
        set_dpi_combo (photo_dpi_combo, DEFAULT_PHOTO_DPI, dpi);
        photo_dpi_combo.changed.connect (() => { settings.set_int ("photo-dpi", get_photo_dpi ()); });

        var renderer = new Gtk.CellRendererText ();
        device_combo.pack_start (renderer, true);
        device_combo.add_attribute (renderer, "text", 1);

        renderer = new Gtk.CellRendererText ();
        page_side_combo.pack_start (renderer, true);
        page_side_combo.add_attribute (renderer, "text", 1);
        set_page_side ((ScanType) settings.get_enum ("page-side"));
        page_side_combo.changed.connect (() => { settings.set_enum ("page-side", get_page_side ()); });

        renderer = new Gtk.CellRendererText ();
        paper_size_combo.pack_start (renderer, true);
        paper_size_combo.add_attribute (renderer, "text", 2);
        var paper_width = settings.get_int ("paper-width");
        var paper_height = settings.get_int ("paper-height");
        set_paper_size (paper_width, paper_height);
        paper_size_combo.changed.connect (() =>
        {
            int w, h;
            get_paper_size (out w, out h);
            settings.set_int ("paper-width", w);
            settings.set_int ("paper-height", h);
        });

        var lower = brightness_adjustment.lower;
        var darker_label = "<small>%s</small>".printf (_("Darker"));
        var upper = brightness_adjustment.upper;
        var lighter_label = "<small>%s</small>".printf (_("Lighter"));
        brightness_scale.add_mark (lower, Gtk.PositionType.BOTTOM, darker_label);
        brightness_scale.add_mark (0, Gtk.PositionType.BOTTOM, null);
        brightness_scale.add_mark (upper, Gtk.PositionType.BOTTOM, lighter_label);
        brightness = settings.get_int ("brightness");
        brightness_adjustment.value_changed.connect (() => { settings.set_int ("brightness", brightness); });

        lower = contrast_adjustment.lower;
        var less_label = "<small>%s</small>".printf (_("Less"));
        upper = contrast_adjustment.upper;
        var more_label = "<small>%s</small>".printf (_("More"));
        contrast_scale.add_mark (lower, Gtk.PositionType.BOTTOM, less_label);
        contrast_scale.add_mark (0, Gtk.PositionType.BOTTOM, null);
        contrast_scale.add_mark (upper, Gtk.PositionType.BOTTOM, more_label);
        contrast = settings.get_int ("contrast");
        contrast_adjustment.value_changed.connect (() => { settings.set_int ("contrast", contrast); });

        lower = quality_adjustment.lower;
        var minimum_label = "<small>%s</small>".printf (_("Minimum"));
        upper = quality_adjustment.upper;
        var maximum_label = "<small>%s</small>".printf (_("Maximum"));
        quality_scale.add_mark (lower, Gtk.PositionType.BOTTOM, minimum_label);
        quality_scale.add_mark (75, Gtk.PositionType.BOTTOM, null);
        quality_scale.add_mark (upper, Gtk.PositionType.BOTTOM, maximum_label);
        quality = settings.get_int ("jpeg-quality");
        quality_adjustment.value_changed.connect (() => { settings.set_int ("jpeg-quality", quality); });

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
        book_view.border_width = 18;
        main_vbox.pack_end (book_view, true, true, 0);
        book_view.page_selected.connect (page_selected_cb);
        book_view.show_page.connect (show_page_cb);
        book_view.show_menu.connect (show_page_menu_cb);
        book_view.visible = true;

        /* Load previous state */
        load_state ();

        /* Restore window size */
        debug ("Restoring window to %dx%d pixels", window_width, window_height);
        window.set_default_size (window_width, window_height);
        if (window_is_maximized)
        {
            debug ("Restoring window to maximized");
            window.maximize ();
        }

        progress_dialog = new ProgressBarDialog (window, _("Saving document..."));
        book.saving.connect (book_saving_cb);
    }
    
    private string state_filename
    {
        owned get { return Path.build_filename (Environment.get_user_cache_dir (), "simple-scan", "state"); }
    }

    private void load_state ()
    {
        debug ("Loading state from %s", state_filename);

        var f = new KeyFile ();
        try
        {
            f.load_from_file (state_filename, KeyFileFlags.NONE);
        }
        catch (Error e)
        {
            if (!(e is FileError.NOENT))
                warning ("Failed to load state: %s", e.message);
        }
        window_width = state_get_integer (f, "window", "width", 600);
        if (window_width <= 0)
            window_width = 600;
        window_height = state_get_integer (f, "window", "height", 400);
        if (window_height <= 0)
            window_height = 400;
        window_is_maximized = state_get_boolean (f, "window", "is-maximized");
        default_page_width = state_get_integer (f, "last-page", "width", 595);
        default_page_height = state_get_integer (f, "last-page", "height", 842);
        default_page_dpi = state_get_integer (f, "last-page", "dpi", 72);
        switch (state_get_string (f, "last-page", "scan-direction", "top-to-bottom"))
        {
        default:
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

    private int state_get_integer (KeyFile f, string group_name, string key, int default = 0)
    {
        try
        {
            return f.get_integer (group_name, key);
        }
        catch
        {
            return default;
        }
    }

    private bool state_get_boolean (KeyFile f, string group_name, string key, bool default = false)
    {
        try
        {
            return f.get_boolean (group_name, key);
        }
        catch
        {
            return default;
        }
    }

    private string state_get_string (KeyFile f, string group_name, string key, string default = "")
    {
        try
        {
            return f.get_string (group_name, key);
        }
        catch
        {
            return default;
        }
    }

    private void save_state (bool force = false)
    {
        if (!force)
        {
            if (save_state_timeout != 0)
                Source.remove (save_state_timeout);
            save_state_timeout = Timeout.add (100, () =>
            {
                save_state (true);
                save_state_timeout = 0;
                return false;
            });
            return;
        }

        debug ("Saving state to %s", state_filename);

        var f = new KeyFile ();
        f.set_integer ("window", "width", window_width);
        f.set_integer ("window", "height", window_height);
        f.set_boolean ("window", "is-maximized", window_is_maximized);
        f.set_integer ("last-page", "width", default_page_width);
        f.set_integer ("last-page", "height", default_page_height);
        f.set_integer ("last-page", "dpi", default_page_dpi);
        switch (default_page_scan_direction)
        {
        case ScanDirection.TOP_TO_BOTTOM:
            f.set_value ("last-page", "scan-direction", "top-to-bottom");
            break;
        case ScanDirection.BOTTOM_TO_TOP:
            f.set_value ("last-page", "scan-direction", "bottom-to-top");
            break;
        case ScanDirection.LEFT_TO_RIGHT:
            f.set_value ("last-page", "scan-direction", "left-to-right");
            break;
        case ScanDirection.RIGHT_TO_LEFT:
            f.set_value ("last-page", "scan-direction", "right-to-left");
            break;
        }
        try
        {
            FileUtils.set_contents (state_filename, f.to_data ());
        }
        catch (Error e)
        {
            warning ("Failed to write state: %s", e.message);
        }
    }

    private void book_saving_cb (int page_number)
    {
        /* Prevent GUI from freezing */
        while (Gtk.events_pending ())
          Gtk.main_iteration ();

        var total = (int) book.n_pages;
        var fraction = (page_number + 1.0) / total;
        var complete = fraction == 1.0;
        if (complete)
            Timeout.add (500, () => {
                progress_dialog.visible = false;
                return false;
            });
        var message = _("Saving page %d out of %d").printf (page_number + 1, total);

        progress_dialog.fraction = fraction;
        progress_dialog.message = message;
    }

    public void show_progress_dialog ()
    {
        progress_dialog.visible = true;
    }

    public void hide_progress_dialog ()
    {
        progress_dialog.visible = false;
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
        window.visible = true;
    }
}

private class ProgressBarDialog : Gtk.Window
{
    private Gtk.ProgressBar bar;
    
    public double fraction
    {
        get { return bar.fraction; }
        set { bar.fraction = value; }
    }

    public string message
    {
        get { return bar.text; }
        set { bar.text = value; }
    }

    public ProgressBarDialog (Gtk.ApplicationWindow parent, string title)
    {
        bar = new Gtk.ProgressBar ();
        var hbox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 5);
        var vbox = new Gtk.Box (Gtk.Orientation.VERTICAL, 5);
        hbox.hexpand = true;

        bar.text = "";
        bar.show_text = true;
        bar.set_size_request (225, 25);
        set_size_request (250, 50);

        vbox.pack_start (bar, true, false, 0);
        hbox.pack_start (vbox, true, false, 0);
        add (hbox);
        this.title = title;

        transient_for = parent;
        set_position (Gtk.WindowPosition.CENTER_ON_PARENT);
        modal = true;
        resizable = false;

        hbox.visible = true;
        vbox.visible = true;
        bar.visible = true;
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

private class PageIcon : Gtk.DrawingArea
{
    private string text;
    private double r;
    private double g;
    private double b;
    private const int MINIMUM_WIDTH = 20;

    public PageIcon (string text, double r = 1.0, double g = 1.0, double b = 1.0)
    {
        this.text = text;
        this.r = r;
        this.g = g;
        this.b = b;
    }

    public override void get_preferred_width (out int minimum_width, out int natural_width)
    {
        minimum_width = natural_width = MINIMUM_WIDTH;
    }

    public override void get_preferred_height (out int minimum_height, out int natural_height)
    {
        minimum_height = natural_height = (int) Math.round (MINIMUM_WIDTH * Math.SQRT2);
    }

    public override void get_preferred_height_for_width (int width, out int minimum_height, out int natural_height)
    {
        minimum_height = natural_height = (int) (width * Math.SQRT2);
    }

    public override void get_preferred_width_for_height (int height, out int minimum_width, out int natural_width)
    {
        minimum_width = natural_width = (int) (height / Math.SQRT2);
    }

    public override bool draw (Cairo.Context c)
    {
        var w = get_allocated_width ();
        var h = get_allocated_height ();
        if (w * Math.SQRT2 > h)
            w = (int) Math.round (h / Math.SQRT2);
        else
            h = (int) Math.round (w * Math.SQRT2);

        c.translate ((get_allocated_width () - w) / 2, (get_allocated_height () - h) / 2);

        c.rectangle (0.5, 0.5, w - 1, h - 1);

        c.set_source_rgb (r, g, b);
        c.fill_preserve ();

        c.set_line_width (1.0);
        c.set_source_rgb (0.0, 0.0, 0.0);
        c.stroke ();

        Cairo.TextExtents extents;
        c.text_extents (text, out extents);
        c.translate ((w - extents.width) * 0.5 - 0.5, (h + extents.height) * 0.5 - 0.5);
        c.show_text (text);

        return true;
    }
}
