/*
 * Copyright (C) 2009-2015 Canonical Ltd.
 * Author: Robert Ancell <robert.ancell@canonical.com>,
 *         Eduard Gotwig <g@ox.io>
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later
 * version. See http://www.gnu.org/copyleft/gpl.html the full text of the
 * license.
 */

private const int DEFAULT_TEXT_DPI = 150;
private const int DEFAULT_PHOTO_DPI = 300;

[GtkTemplate (ui = "/org/gnome/SimpleScan/ui/app-window.ui")]
public class AppWindow : Adw.ApplicationWindow
{
    private const GLib.ActionEntry[] action_entries =
    {
        { "new_document", new_document_cb },
        { "scan_single", scan_single_cb },
        { "scan_adf", scan_adf_cb },
        { "scan_batch", scan_batch_cb },
        { "scan_stop", scan_stop_cb },
        { "rotate_left", rotate_left_cb },
        { "rotate_right", rotate_right_cb },
        { "move_left", move_left_cb },
        { "move_right", move_right_cb },
        { "copy_page", copy_page_cb },
        { "delete_page", delete_page_cb },
        { "reorder", reorder_document_cb },
        { "save", save_document_cb },
        { "email", email_document_cb },
        { "print", print_document_cb },
        { "preferences", preferences_cb },
        { "help", help_cb },
        { "about", about_cb },
        { "quit", quit_cb }
    };
    
    private GLib.SimpleAction delete_page_action;
    private GLib.SimpleAction page_move_left_action;
    private GLib.SimpleAction page_move_right_action;
    private GLib.SimpleAction copy_to_clipboard_action;
    
    private CropActions crop_actions;

    private Settings settings;
    private ScanType scan_type = ScanType.SINGLE;

    private PreferencesDialog preferences_dialog;

    private bool setting_devices;
    private bool user_selected_device;

    [GtkChild]
    private unowned Gtk.Popover scan_options_popover;
    [GtkChild]
    private unowned Gtk.PopoverMenu page_menu;
    [GtkChild]
    private unowned Gtk.Stack stack;
    [GtkChild]
    private unowned Adw.StatusPage status_page;
    [GtkChild]
    private unowned Gtk.Label status_secondary_label;
    [GtkChild]
    private unowned Gtk.ListStore device_model;
    [GtkChild]
    private unowned Gtk.Box device_buttons_box;
    [GtkChild]
    private unowned Gtk.ComboBox device_combo;
    [GtkChild]
    private unowned Gtk.Box main_vbox;
    [GtkChild]
    private unowned Gtk.Button save_button;
    [GtkChild]
    private unowned Gtk.Button stop_button;
    [GtkChild]
    private unowned Gtk.Button scan_button;
    [GtkChild]
    private unowned Gtk.ActionBar action_bar;
    [GtkChild]
    private unowned Gtk.ToggleButton crop_button;

    [GtkChild]
    private unowned Adw.ButtonContent scan_button_content;
    [GtkChild]
    private unowned Gtk.ToggleButton scan_single_radio;
    [GtkChild]
    private unowned Gtk.ToggleButton scan_adf_radio;
    [GtkChild]
    private unowned Gtk.ToggleButton scan_batch_radio;
    [GtkChild]
    private unowned Gtk.ToggleButton text_radio;
    [GtkChild]
    private unowned Gtk.ToggleButton photo_radio;

    [GtkChild]
    private unowned Gtk.MenuButton menu_button;

    private bool have_devices = false;
    private string? missing_driver = null;

    public Book book { get; private set; }
    private bool book_needs_saving;
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

    private string document_hint = "photo";

    private bool scanning_ = false;
    public bool scanning
    {
        get { return scanning_; }
        set
        {
            scanning_ = value;
            stack.set_visible_child_name ("document");
            
            delete_page_action.set_enabled (!value);
            scan_button.visible = !value;
            stop_button.visible = value;
        }
    }

    private int window_width;
    private int window_height;
    private bool window_is_maximized;
    private bool window_is_fullscreen;

    private uint save_state_timeout;

    public int brightness
    {
        get { return preferences_dialog.get_brightness (); }
        set { preferences_dialog.set_brightness (value); }
    }

    public int contrast
    {
        get { return preferences_dialog.get_contrast (); }
        set { preferences_dialog.set_contrast (value); }
    }

    public int page_delay
    {
        get { return preferences_dialog.get_page_delay (); }
        set { preferences_dialog.set_page_delay (value); }
    }

    public signal void start_scan (string? device, ScanOptions options);
    public signal void stop_scan ();
    public signal void redetect ();

    public AppWindow ()
    {
        settings = new Settings ("org.gnome.SimpleScan");

        var renderer = new Gtk.CellRendererText ();
        renderer.set_property ("xalign", 0.5);
        device_combo.pack_start (renderer, true);
        device_combo.add_attribute (renderer, "text", 1);

        book = new Book ();
        book.page_added.connect (page_added_cb);
        book.reordered.connect (reordered_cb);
        book.page_removed.connect (page_removed_cb);
        book.changed.connect (book_changed_cb);
        
        load ();

        clear_document ();
    }

    ~AppWindow ()
    {
        book.page_added.disconnect (page_added_cb);
        book.reordered.disconnect (reordered_cb);
        book.page_removed.disconnect (page_removed_cb);
    }

    public void show_error_dialog (string error_title, string error_text)
    {
        var dialog = new Adw.MessageDialog (this,
                                            error_title,
                                            error_text);
        dialog.add_response ("close", _("_Close"));
        dialog.set_response_appearance ("close", Adw.ResponseAppearance.SUGGESTED);
        dialog.show ();
    }

    public async AuthorizeDialogResponse authorize (string resource)
    {
        /* Label in authorization dialog.  “%s” is replaced with the name of the resource requesting authorization */
        var description = _("Username and password required to access “%s”").printf (resource);
        var authorize_dialog = new AuthorizeDialog (this, description);
        authorize_dialog.transient_for = this;

        return yield authorize_dialog.open ();
    }

    private void update_scan_status ()
    {
        scan_button.sensitive = false;
        if (!have_devices)
        {
            status_page.set_title (/* Label shown when searching for scanners */
                                   _("Searching for Scanners…"));
            status_secondary_label.visible = false;
            device_buttons_box.visible = false;
        }
        else if (get_selected_device () != null)
        {
            scan_button.sensitive = true;
            status_page.set_title (/* Label shown when detected a scanner */
                                   _("Ready to Scan"));
            status_secondary_label.set_text (get_selected_device_label ());
            status_secondary_label.visible = false;
            device_buttons_box.visible = true;
            device_buttons_box.sensitive = true;
            device_combo.sensitive = true;
        }
        else if (this.missing_driver != null)
        {
            status_page.set_title (/* Warning displayed when no drivers are installed but a compatible scanner is detected */
                                   _("Additional Software Needed"));
            /* Instructions to install driver software */
            status_secondary_label.set_markup (_("You need to <a href=\"install-firmware\">install driver software</a> for your scanner."));
            status_secondary_label.visible = true;
            device_buttons_box.visible = false;
        }
        else
        {
            /* Warning displayed when no scanners are detected */
            status_page.set_title (_("No Scanners Detected"));
            /* Hint to user on why there are no scanners detected */
            status_secondary_label.set_text (_("Please check your scanner is connected and powered on."));
            status_secondary_label.visible = true;
            device_buttons_box.visible = true;
            device_buttons_box.sensitive = true;
            device_combo.sensitive = false; // We would like to be refresh button to be active
        }
    }

    public void set_scan_devices (List<ScanDevice> devices, string? missing_driver = null)
    {
        have_devices = true;
        this.missing_driver = missing_driver;

        setting_devices = true;

        /* If the user hasn't chosen a scanner choose the best available one */
        var have_selection = false;
        if (user_selected_device)
            have_selection = device_combo.active >= 0;

        /* Add new devices */
        int index = 0;
        Gtk.TreeIter iter;
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
#if VALA_0_36
                    device_model.remove (ref iter);
#else
                    device_model.remove (iter);
#endif
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
#if VALA_0_36
            device_model.remove (ref iter);
#else
            device_model.remove (iter);
#endif

        /* Select the previously selected device or the first available device */
        if (!have_selection)
        {
            var device = settings.get_string ("selected-device");
            if (device != null && find_scan_device (device, out iter))
                device_combo.set_active_iter (iter);
            else
                device_combo.set_active (0);
        }

        setting_devices = false;

        update_scan_status ();
    }

    private async bool prompt_to_load_autosaved_book ()
    {
        var dialog = new Adw.MessageDialog (this,
                                            "",
                                            /* Contents of dialog that shows if autosaved book should be loaded. */
                                            _("An autosaved book exists. Do you want to open it?"));

        dialog.add_response ("no", _("_No"));
        dialog.add_response ("yes", _("_Yes"));
        
        dialog.set_response_appearance ("no", Adw.ResponseAppearance.DESTRUCTIVE);
        dialog.set_response_appearance ("yes", Adw.ResponseAppearance.SUGGESTED);

        dialog.set_default_response("yes");
        dialog.show ();

        string response = "yes";

        SourceFunc callback = prompt_to_load_autosaved_book.callback;
        dialog.response.connect((res) => {
            response = res;
            callback();
        });
        
        yield;
        
        return response == "yes";
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

    private string? get_selected_device_label ()
    {
        Gtk.TreeIter iter;

        if (device_combo.get_active_iter (out iter))
        {
            string label;
            device_model.get (iter, 1, out label, -1);
            return label;
        }

        return null;
    }

    public void set_selected_device (string device)
    {
        user_selected_device = true;

        Gtk.TreeIter iter;
        if (!find_scan_device (device, out iter))
            return;

        device_combo.set_active_iter (iter);
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

    private async string? choose_file_location ()
    {
        /* Get directory to save to */
        string? directory = null;
        directory = settings.get_string ("save-directory");

        if (directory == null || directory == "")
            directory = GLib.Filename.to_uri(Environment.get_user_special_dir (UserDirectory.DOCUMENTS));

        var save_dialog = new Gtk.FileChooserNative (/* Save dialog: Dialog title */
                                                     _("Save As…"),
                                                     this,
                                                     Gtk.FileChooserAction.SAVE,
                                                     _("_Save"),
                                                     _("_Cancel"));
        
        save_dialog.set_modal(true);
        // TODO(gtk4)
        //  save_dialog.local_only = false;

        var save_format = settings.get_string ("save-format");
        if (book_uri != null)
        {
            var file = GLib.File.new_for_uri (book_uri);
            
            try
            {
                save_dialog.set_file (file);
            }
            catch (Error e)
            {
                warning ("Error file chooser set_file: %s", e.message);
            }
        }
        else
        {
            var file = GLib.File.new_for_uri (directory);

            try
            {
                save_dialog.set_current_folder (file);
            }
            catch (Error e)
            {
                warning ("Error file chooser set_current_folder: %s", e.message);
            }

            /* Default filename to use when saving document. */
            /* To that filename the extension will be added, eg. "Scanned Document.pdf" */
            save_dialog.set_current_name (_("Scanned Document") + "." + mime_type_to_extension (save_format));
        }

        var pdf_filter = new Gtk.FileFilter ();
        pdf_filter.set_filter_name (_("PDF (multi-page document)"));
        pdf_filter.add_pattern ("*.pdf" );
        pdf_filter.add_mime_type ("application/pdf");
        save_dialog.add_filter (pdf_filter);
        
        var jpeg_filter = new Gtk.FileFilter ();
        jpeg_filter.set_filter_name (_("JPEG (compressed)"));
        jpeg_filter.add_pattern ("*.jpg" );
        jpeg_filter.add_pattern ("*.jpeg" );
        jpeg_filter.add_mime_type ("image/jpeg");
        save_dialog.add_filter (jpeg_filter);

        var png_filter = new Gtk.FileFilter ();
        png_filter.set_filter_name (_("PNG (lossless)"));
        png_filter.add_pattern ("*.png" );
        png_filter.add_mime_type ("image/png");
        save_dialog.add_filter (png_filter);

        var webp_filter = new Gtk.FileFilter ();
        webp_filter.set_filter_name (_("WebP (compressed)"));
        webp_filter.add_pattern ("*.webp" );
        webp_filter.add_mime_type ("image/webp");
        save_dialog.add_filter (webp_filter);

        var all_filter = new Gtk.FileFilter ();
        all_filter.set_filter_name (_("All Files"));
        all_filter.add_pattern ("*");
        save_dialog.add_filter (all_filter);
        
        switch (save_format)
        {
            case "application/pdf":
                save_dialog.set_filter (pdf_filter);
                break;
            case "image/jpeg":
                save_dialog.set_filter (jpeg_filter);
                break;
            case "image/png":
                save_dialog.set_filter (png_filter);
                break;
            case "image/webp":
                save_dialog.set_filter (webp_filter);
                break;
        }
        
        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
        box.visible = true;
        box.spacing = 10;
        box.set_halign (Gtk.Align.CENTER);

        while (true)
        {
            save_dialog.show ();
            
            var response = Gtk.ResponseType.NONE;
            SourceFunc callback = choose_file_location.callback;

            save_dialog.response.connect ((res) => {
                response = (Gtk.ResponseType) res;
                callback ();
            });
            
            yield;

            if (response != Gtk.ResponseType.ACCEPT)
            {
                save_dialog.destroy ();
                return null;
            }

            var file = save_dialog.get_file ();
            
            if (file == null)
            {
                return null;
            }

            var uri = file.get_uri ();

            var extension = uri_extension(uri);

            var mime_type = extension_to_mime_type(extension);
            mime_type = mime_type != null ? mime_type : "application/pdf";

            settings.set_string ("save-format", mime_type);

            if (extension == null)
                uri += "." + mime_type_to_extension (mime_type);

            /* Check the file(s) don't already exist */
            var files = new List<File> ();
            if (mime_type == "image/jpeg" || mime_type == "image/png" || mime_type == "image/webp")
            {
                for (var j = 0; j < book.n_pages; j++)
                    files.append (make_indexed_file (uri, j, book.n_pages));
            }
            else
                files.append (File.new_for_uri (uri));
                
            var overwrite_check = true;
            
            // We assume that GTK or system file dialog asked about overwrite already so we reask only if there is more than one file or we changed the name
            // Ideally in flatpack era we should not modify file name after save dialog is done 
            // but for the sake of keeping old functionality in tact we leave it as it 
            if (files.length () > 1 || file.get_uri () != uri)
            {
                overwrite_check = yield check_overwrite (save_dialog.transient_for, files);
            }

            if (overwrite_check)
            {
                var directory_uri = uri.substring (0, uri.last_index_of ("/") + 1);
                settings.set_string ("save-directory", directory_uri);
                save_dialog.destroy ();
                return uri;
            }
        }
    }

    private async bool check_overwrite (Gtk.Window parent, List<File> files)
    {
        foreach (var file in files)
        {
            if (!file.query_exists ())
                continue;

            var title = _("A file named “%s” already exists.  Do you want to replace it?").printf(file.get_basename ());

            var dialog = new Adw.MessageDialog (parent,
                                                /* Contents of dialog that shows if saving would overwrite and existing file. %s is replaced with the name of the file. */
                                                title,
                                                null);

            dialog.add_response ("cancel", _("_Cancel"));
            dialog.add_response ("replace", _("_Replace"));
            
            dialog.set_response_appearance ("replace", Adw.ResponseAppearance.DESTRUCTIVE);

            SourceFunc callback = check_overwrite.callback;
            string response = "cancel";

            dialog.response.connect ((res) => {
                response = res;
                callback ();
            });
            
            dialog.show ();

            yield;

            if (response != "replace")
                return false;
        }

        return true;
    }

    private string? mime_type_to_extension (string mime_type)
    {
        if (mime_type == "application/pdf")
            return "pdf";
        else if (mime_type == "image/jpeg")
            return "jpg";
        else if (mime_type == "image/png")
            return "png";
        else if (mime_type == "image/webp")
            return "webp";
        else
            return null;
    }

    private string? extension_to_mime_type (string extension)
    {
        var extension_lower = extension.down ();
        if (extension_lower == "pdf")
            return "application/pdf";
        else if (extension_lower == "jpg" || extension_lower == "jpeg")
            return "image/jpeg";
        else if (extension_lower == "png")
            return "image/png";
        else if (extension_lower == "webp")
            return "image/webp";
        else
            return null;
    }

    private string? uri_extension (string uri)
    {
        var extension_index = uri.last_index_of_char ('.');
        if (extension_index < 0)
            return null;

        return uri.substring (extension_index + 1);
    }

    private string uri_to_mime_type (string uri)
    {
        var extension = uri_extension(uri);
        if (extension == null)
            return "image/jpeg";

        var mime_type = extension_to_mime_type (extension);
        if (mime_type == null)
            return "image/jpeg";

        return mime_type;
    }

    private async bool save_document_async ()
    {
        var uri = yield choose_file_location ();
        if (uri == null)
            return false;

        var file = File.new_for_uri (uri);

        debug ("Saving to '%s'", uri);

        var mime_type = uri_to_mime_type (uri);

        var cancellable = new Cancellable ();
        var progress_bar =  new CancellableProgressBar (_("Saving"), cancellable);
        action_bar.pack_end (progress_bar);
        progress_bar.visible = true;
        save_button.sensitive = false;
        try
        {
            yield book.save_async (mime_type, settings.get_int ("jpeg-quality"), file,
                settings.get_boolean ("postproc-enabled"), settings.get_string ("postproc-script"),
                settings.get_string ("postproc-arguments"), settings.get_boolean ("postproc-keep-original"),
                (fraction) =>
            {
                progress_bar.set_fraction (fraction);
            }, cancellable);
        }
        catch (Error e)
        {
            save_button.sensitive = true;
            progress_bar.destroy ();
            warning ("Error saving file: %s", e.message);
            show_error_dialog (/* Title of error dialog when save failed */
                              _("Failed to save file"),
                               e.message);
            return false;
        }
        save_button.sensitive = true;
        progress_bar.remove_with_delay (500, action_bar);

        book_needs_saving = false;
        book_uri = uri;
        return true;
    }

    private async bool prompt_to_save_async (string title, string discard_label)
    {
        if (!book_needs_saving || (book.n_pages == 0))
            return true;

        var dialog = new Adw.MessageDialog (this,
                                            title,
                                            _("If you don’t save, changes will be permanently lost."));

        dialog.add_response ("discard", discard_label);
        dialog.add_response ("cancel", _("_Cancel"));
        dialog.add_response ("save", _("_Save"));
        
        dialog.set_response_appearance ("discard", Adw.ResponseAppearance.DESTRUCTIVE);
        dialog.set_response_appearance ("save", Adw.ResponseAppearance.SUGGESTED);

        dialog.show ();
        
        string response = "cancel";
        SourceFunc callback = prompt_to_save_async.callback;
        dialog.response.connect((res) => {
            response = res;
            callback ();
        });

        yield;

        switch (response)
        {
        case "save":
            if (yield save_document_async ())
                return true;
            else
                return false;
        case "discard":
            return true;
        default:
            return false;
        }
    }

    private void clear_document ()
    {
        book.clear ();
        book_needs_saving = false;
        book_uri = null;
        save_button.sensitive = false;
        copy_to_clipboard_action.set_enabled (false);
        update_scan_status ();
        stack.set_visible_child_name ("startup");
    }

    private void new_document ()
    {
        prompt_to_save_async.begin (/* Text in dialog warning when a document is about to be lost */
                                    _("Save current document?"),
                                    /* Button in dialog to create new document and discard unsaved document */
                                    _("_Discard Changes"), (obj, res) =>
        {
            if (!prompt_to_save_async.end(res))
                return;

            if (scanning)
                stop_scan ();

            clear_document ();
            autosave_manager.cleanup ();
        });
    }

    [GtkCallback]
    private bool status_label_activate_link_cb (Gtk.Label label, string uri)
    {
        if (uri == "install-firmware")
        {
            var dialog = new DriversDialog (this, missing_driver);
            dialog.open.begin (() => {});
            return true;
        }

        return false;
    }

    [GtkCallback]
    private void new_document_cb ()
    {
        new_document ();
    }

    [GtkCallback]
    private void crop_toggle_cb (Gtk.ToggleButton btn)
    {
        if (updating_page_menu)
            return;

        if (btn.active)
            set_crop ("custom");
        else
            set_crop (null);
    }

    [GtkCallback]
    private void redetect_button_clicked_cb (Gtk.Button button)
    {
        have_devices = false;
        update_scan_status ();
        redetect ();
    }

    private void scan (ScanOptions options)
    {
        status_page.set_title (/* Label shown when scan started */
                               _("Contacting Scanner…"));
        device_buttons_box.visible = true;
        device_buttons_box.sensitive = false;
        start_scan (get_selected_device (), options);
    }

    private void scan_single_cb ()
    {
        var options = make_scan_options ();
        options.type = ScanType.SINGLE;
        scan (options);
    }

    private void scan_adf_cb ()
    {
        var options = make_scan_options ();
        options.type = ScanType.ADF;
        scan (options);
    }

    private void scan_batch_cb ()
    {
        var options = make_scan_options ();
        options.type = ScanType.BATCH;
        scan (options);
    }

    private void scan_stop_cb ()
    {
        stop_scan ();
    }

    private void rotate_left_cb ()
    {
        if (updating_page_menu)
            return;
        var page = book_view.selected_page;
        if (page != null)
            page.rotate_left ();
    }

    private void rotate_right_cb ()
    {
        if (updating_page_menu)
            return;
        var page = book_view.selected_page;
        if (page != null)
            page.rotate_right ();
    }

    private void move_left_cb ()
    {
        var page = book_view.selected_page;
        var index = book.get_page_index (page);
        if (index > 0)
            book.move_page (page, index - 1);
    }

    private void move_right_cb ()
    {
        var page = book_view.selected_page;
        var index = book.get_page_index (page);
        if (index < book.n_pages - 1)
            book.move_page (page, book.get_page_index (page) + 1);
    }

    private void copy_page_cb ()
    {
        var page = book_view.selected_page;
        if (page != null)
            page.copy_to_clipboard (this);
    }

    private void delete_page_cb ()
    {
        book_view.book.delete_page (book_view.selected_page);
    }

    private void set_scan_type (ScanType scan_type)
    {
        this.scan_type = scan_type;

        switch (scan_type)
        {
        case ScanType.SINGLE:
            scan_single_radio.active = true;
            scan_button_content.icon_name = "scanner-symbolic";
            scan_button.tooltip_text = _("Scan a single page from the scanner");
            break;
        case ScanType.ADF:
            scan_adf_radio.active = true;
            scan_button_content.icon_name = "scan-type-adf-symbolic";
            scan_button.tooltip_text = _("Scan multiple pages from the scanner");
            break;
        case ScanType.BATCH:
            scan_batch_radio.active = true;
            scan_button_content.icon_name = "scan-type-batch-symbolic";
            scan_button.tooltip_text = _("Scan multiple pages from the scanner");
            break;
        }
    }

    [GtkCallback]
    private void scan_single_radio_toggled_cb (Gtk.ToggleButton button)
    {
        if (button.active)
            set_scan_type (ScanType.SINGLE);
    }

    [GtkCallback]
    private void scan_adf_radio_toggled_cb (Gtk.ToggleButton button)
    {
        if (button.active)
            set_scan_type (ScanType.ADF);
    }

    [GtkCallback]
    private void scan_batch_radio_toggled_cb (Gtk.ToggleButton button)
    {
        if (button.active)
            set_scan_type (ScanType.BATCH);
    }

    private void set_document_hint (string document_hint, bool save = false)
    {
        this.document_hint = document_hint;

        if (document_hint == "text")
        {
            text_radio.active = true;
        }
        else if (document_hint == "photo")
        {
            photo_radio.active = true;
        }

        if (save)
            settings.set_string ("document-type", document_hint);
    }

    [GtkCallback]
    private void text_radio_toggled_cb (Gtk.ToggleButton button)
    {
        if (button.active)
            set_document_hint ("text", true);
    }

    [GtkCallback]
    private void photo_radio_toggled_cb (Gtk.ToggleButton button)
    {
        if (button.active)
            set_document_hint ("photo", true);
    }

    [GtkCallback]
    private void preferences_button_clicked_cb (Gtk.Button button)
    {
        scan_options_popover.popdown ();
        preferences_cb ();
    }

    private ScanOptions make_scan_options ()
    {
        var options = new ScanOptions ();
        if (document_hint == "text")
        {
            options.scan_mode = ScanMode.GRAY;
            options.dpi = preferences_dialog.get_text_dpi ();
            options.depth = 2;
        }
        else
        {
            options.scan_mode = ScanMode.COLOR;
            options.dpi = preferences_dialog.get_photo_dpi ();
            options.depth = 8;
        }
        preferences_dialog.get_paper_size (out options.paper_width, out options.paper_height);
        options.brightness = brightness;
        options.contrast = contrast;
        options.page_delay = page_delay;
        options.side = preferences_dialog.get_page_side ();

        return options;
    }

    [GtkCallback]
    private void device_combo_changed_cb (Gtk.Widget widget)
    {
        if (setting_devices)
            return;
        user_selected_device = true;
        if (get_selected_device () != null)
            settings.set_string ("selected-device", get_selected_device ());
    }

    [GtkCallback]
    private void scan_button_clicked_cb (Gtk.Widget widget)
    {
        scan_button.visible = false;
        stop_button.visible = true;
        var options = make_scan_options ();
        options.type = scan_type;
        scan (options);
    }

    [GtkCallback]
    private void stop_scan_button_clicked_cb (Gtk.Widget widget)
    {
        scan_button.visible = true;
        stop_button.visible = false;
        stop_scan ();
    }

    private void preferences_cb ()
    {
        preferences_dialog.present ();
    }

    private void update_page_menu ()
    {
        var page = book_view.selected_page;
        if (page == null)
        {
            page_move_left_action.set_enabled (false);
            page_move_right_action.set_enabled (false);
        }
        else
        {
            var index = book.get_page_index (page);
            page_move_left_action.set_enabled (index > 0);
            page_move_right_action.set_enabled (index < book.n_pages - 1);
        }
    }

    private void page_selected_cb (BookView view, Page? page)
    {
        if (page == null)
            return;

        updating_page_menu = true;

        update_page_menu ();
        
        crop_actions.update_current_crop (page.crop_name);
        crop_button.active = page.has_crop;

        updating_page_menu = false;
    }

    private void show_page_cb (BookView view, Page page)
    {
        File file;
        try
        {
            var dir = DirUtils.make_tmp ("simple-scan-XXXXXX");
            file = File.new_for_path (Path.build_filename (dir, "scan.png"));
            page.save_png (file);
        }
        catch (Error e)
        {
            show_error_dialog (/* Error message display when unable to save image for preview */
                               _("Unable to save image for preview"),
                               e.message);
            return;
        }

        Gtk.show_uri (this, file.get_uri (), Gdk.CURRENT_TIME);
    }

    private void show_page_menu_cb (BookView view, Gtk.Widget from, double x, double y)
    {
        double tx, ty;
        from.translate_coordinates(this, x, y, out tx, out ty);

        Gdk.Rectangle rect = { x: (int) tx, y: (int) ty, w: 1, h: 1 };

        page_menu.set_pointing_to (rect);
        page_menu.popup ();
    }

    private void set_crop (string? crop_name)
    {
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
        
        crop_actions.update_current_crop (page.crop_name);
        crop_button.active = page.has_crop;
    }

    public void crop_none_action_cb ()
    {
        set_crop (null);
    }

    public void crop_custom_action_cb ()
    {
        set_crop ("custom");
    }

    public void crop_four_by_six_action_cb ()
    {
        set_crop ("4x6");
    }

    public void crop_legal_action_cb ()
    {
        set_crop ("legal");
    }

    public void crop_letter_action_cb ()
    {
        set_crop ("letter");
    }

    public void crop_a6_action_cb ()
    {
        set_crop ("A6");
    }

    public void crop_a5_action_cb ()
    {
        set_crop ("A5");
    }

    public void crop_a4_action_cb ()
    {
        set_crop ("A4");
    }

    public void crop_a3_action_cb ()
    {
        set_crop ("A3");
    }

    public void crop_rotate_action_cb ()
    {
        var page = book_view.selected_page;
        if (page == null)
            return;
        page.rotate_crop ();
    }

    private void reorder_document_cb ()
    {
        var dialog = new ReorderPagesDialog ();
        dialog.set_transient_for (this);
        
        /* Button for combining sides in reordering dialog */
        dialog.combine_sides.clicked.connect (() =>
        {
            book.combine_sides ();
            dialog.close ();
        });

        /* Button for combining sides in reverse order in reordering dialog */
        dialog.combine_sides_rev.clicked.connect (() =>
        {
            book.combine_sides_reverse ();
            dialog.close ();
        });

        /* Button for reversing in reordering dialog */
        dialog.reverse.clicked.connect (() =>
        {
            book.reverse ();
            dialog.close ();
        });

        /* Button for keeping the ordering, but flip every second upside down */
        dialog.flip_odd.clicked.connect (() =>
        {
            book.flip_every_second(FlipEverySecond.Odd);
            dialog.close ();
        });

        /* Button for keeping the ordering, but flip every second upside down */
        dialog.flip_even.clicked.connect (() =>
        {
            dialog.close ();
            book.flip_every_second(FlipEverySecond.Even);
        });

        dialog.present ();
    }

    public void save_document_cb ()
    {
        save_document_async.begin ();
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

    private void email_document_cb ()
    {
        email_document_async.begin ();
    }

    private async void email_document_async ()
    {
        try
        {
            var dir = DirUtils.make_tmp ("simple-scan-XXXXXX");
            string mime_type, filename;
            if (document_hint == "text")
            {
                mime_type = "application/pdf";
                filename = "scan.pdf";
            }
            else
            {
                mime_type = "image/jpeg";
                filename = "scan.jpg";
            }
            var file = File.new_for_path (Path.build_filename (dir, filename));
            yield book.save_async (mime_type, settings.get_int ("jpeg-quality"), file,
                settings.get_boolean ("postproc-enabled"), settings.get_string ("postproc-script"),
                settings.get_string ("postproc-arguments"), settings.get_boolean ("postproc-keep-original"),
                null, null);
            var command_line = "xdg-email";
            if (mime_type == "application/pdf")
                command_line += " --attach %s".printf (file.get_path ());
            else
            {
                for (var i = 0; i < book.n_pages; i++) {
                    var indexed_file = make_indexed_file (file.get_uri (), i, book.n_pages);
                    command_line += " --attach %s".printf (indexed_file.get_path ());
                }
            }
            Process.spawn_command_line_async (command_line);
        }
        catch (Error e)
        {
            warning ("Unable to email document: %s", e.message);
        }
    }

    private void print_document ()
    {
        var print = new Gtk.PrintOperation ();
        print.n_pages = (int) book.n_pages;
        print.draw_page.connect (draw_page);

        try
        {
            print.run (Gtk.PrintOperationAction.PRINT_DIALOG, this);
        }
        catch (Error e)
        {
            warning ("Error printing: %s", e.message);
        }

        print.draw_page.disconnect (draw_page);
    }

    private void print_document_cb ()
    {
        print_document ();
    }

    private void launch_help ()
    {
        Gtk.show_uri (this, "help:simple-scan", Gdk.CURRENT_TIME);
    }

    private void help_cb ()
    {
        launch_help ();
    }

    private void show_about ()
    {
        string[] authors = { "Robert Ancell <robert.ancell@canonical.com>" };

        var about = new Adw.AboutWindow ()
        {
            transient_for = this,
            developers = authors,
            translator_credits = _("translator-credits"),
            copyright = "Copyright © 2009-2018 Canonical Ltd.",
            license_type = Gtk.License.GPL_3_0,
            application_name = _("Document Scanner"),
            application_icon = "org.gnome.SimpleScan",
            version = VERSION,
            website = "https://gitlab.gnome.org/GNOME/simple-scan",
            issue_url = "https://gitlab.gnome.org/GNOME/baobab/-/issues/new",
        };
        
        about.present ();
    }

    private void about_cb ()
    {
        show_about ();
    }

    private void on_quit ()
    {
        prompt_to_save_async.begin (/* Text in dialog warning when a document is about to be lost */
                                    _("Save document before quitting?"),
                                    /* Text in dialog warning when a document is about to be lost */
                                    _("_Quit without Saving"), (obj, res) =>
        {
            if (!prompt_to_save_async.end(res))
                return;

            destroy ();

            if (save_state_timeout != 0)
                save_state (true);

            autosave_manager.cleanup ();
        });
    }

    private void quit_cb ()
    {
        on_quit ();
    }

    public override void size_allocate (int width, int height, int baseline)
    {
        base.size_allocate (width, height, baseline);

        if (!window_is_maximized && !window_is_fullscreen)
        {
            window_width = this.get_width();
            window_height = this.get_height();
            save_state ();
        }
    }

    public override void unmap ()
    {
        window_is_maximized = is_maximized ();
        window_is_fullscreen = is_fullscreen ();
        save_state ();
        
        base.unmap ();
    }

    [GtkCallback]
    private bool window_close_request_cb (Gtk.Window window)
    {
        on_quit ();
        return true; /* Let us quit on our own terms */
    }

    private void page_added_cb (Book book, Page page)
    {
        update_page_menu ();
    }

    private void reordered_cb (Book book)
    {
        update_page_menu ();
    }

    private void page_removed_cb (Book book, Page page)
    {
        update_page_menu ();
    }

    private void book_changed_cb (Book book)
    {
        save_button.sensitive = true;
        book_needs_saving = true;
        copy_to_clipboard_action.set_enabled (true);
    }

    private void load ()
    {
        preferences_dialog = new PreferencesDialog (settings);
        preferences_dialog.close_request.connect (() => {
            preferences_dialog.visible = false;
            return true;
        });
        preferences_dialog.transient_for = this;
        preferences_dialog.modal = true;

        Gtk.Window.set_default_icon_name ("org.gnome.SimpleScan");

        var app = Application.get_default () as Gtk.Application;

        crop_actions = new CropActions (this);

        app.add_action_entries (action_entries, this);
        
        delete_page_action = (GLib.SimpleAction) app.lookup_action("delete_page");
        page_move_left_action = (GLib.SimpleAction) app.lookup_action("move_left");
        page_move_right_action = (GLib.SimpleAction) app.lookup_action("move_right");
        copy_to_clipboard_action = (GLib.SimpleAction) app.lookup_action("copy_page");

        app.set_accels_for_action ("app.new_document", { "<Ctrl>N" });
        app.set_accels_for_action ("app.scan_single", { "<Ctrl>1" });
        app.set_accels_for_action ("app.scan_adf", { "<Ctrl>F" });
        app.set_accels_for_action ("app.scan_batch", { "<Ctrl>M" });
        app.set_accels_for_action ("app.scan_stop", { "Escape" });
        app.set_accels_for_action ("app.rotate_left", { "bracketleft" });
        app.set_accels_for_action ("app.rotate_right", { "bracketright" });
        app.set_accels_for_action ("app.move_left", { "less" });
        app.set_accels_for_action ("app.move_right", { "greater" });
        app.set_accels_for_action ("app.copy_page", { "<Ctrl>C" });
        app.set_accels_for_action ("app.delete_page", { "Delete" });
        app.set_accels_for_action ("app.save", { "<Ctrl>S" });
        app.set_accels_for_action ("app.email", { "<Ctrl>E" });
        app.set_accels_for_action ("app.print", { "<Ctrl>P" });
        app.set_accels_for_action ("app.help", { "F1" });
        app.set_accels_for_action ("app.quit", { "<Ctrl>Q" });
        app.set_accels_for_action ("app.preferences", { "<Ctrl>comma" });
        app.set_accels_for_action ("win.show-help-overlay", { "<Ctrl>question" });

        var gear_menu = new Menu ();
        var section = new Menu ();
        gear_menu.append_section (null, section);
        section.append (_("_Email"), "app.email");
        section.append (_("Pri_nt"), "app.print");
        section.append (C_("menu", "_Reorder Pages"), "app.reorder");
        section = new Menu ();
        gear_menu.append_section (null, section);
        section.append (_("_Preferences"), "app.preferences");
        section.append (_("_Keyboard Shortcuts"), "win.show-help-overlay");
        section.append (_("_Help"), "app.help");
        section.append (_("_About Document Scanner"), "app.about");
        menu_button.set_menu_model (gear_menu);

        app.add_window (this);

        var document_type = settings.get_string ("document-type");
        if (document_type != null)
            set_document_hint (document_type);

        book_view = new BookView (book);
        book_view.vexpand = true;

        main_vbox.prepend (book_view);

        book_view.page_selected.connect (page_selected_cb);
        book_view.show_page.connect (show_page_cb);
        book_view.show_menu.connect (show_page_menu_cb);
        book_view.visible = true;

        preferences_dialog.transient_for = this;

        /* Load previous state */
        load_state ();

        /* Restore window size */
        debug ("Restoring window to %dx%d pixels", window_width, window_height);
        set_default_size (window_width, window_height);
        if (window_is_maximized)
        {
            debug ("Restoring window to maximized");
            maximize ();
        }
        if (window_is_fullscreen)
        {
            debug ("Restoring window to fullscreen");
            fullscreen ();
        }
    }

    private string state_filename
    {
        owned get { return Path.build_filename (Environment.get_user_config_dir (), "simple-scan", "state"); }
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
        window_is_fullscreen = state_get_boolean (f, "window", "is-fullscreen");
        scan_type = Scanner.type_from_string(state_get_string (f, "scanner", "scan-type"));
        set_scan_type (scan_type);
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

    private static string STATE_DIR = Path.build_filename (Environment.get_user_config_dir (), "simple-scan", null);
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
        f.set_boolean ("window", "is-fullscreen", window_is_fullscreen);
        f.set_string ("scanner", "scan-type", Scanner.type_to_string(scan_type));
        try
        {
            DirUtils.create_with_parents (STATE_DIR, 0700);
            FileUtils.set_contents (state_filename, f.to_data ());
        }
        catch (Error e)
        {
            warning ("Failed to write state: %s", e.message);
        }
    }

    public void start ()
    {
        visible = true;
        autosave_manager = new AutosaveManager ();
        autosave_manager.book = book;
        
        if (autosave_manager.exists ())
        {
            prompt_to_load_autosaved_book.begin ((obj, res) => {
                bool restore = prompt_to_load_autosaved_book.end (res);
                
                if (restore) 
                {
                    autosave_manager.load ();
                }

                if (book.n_pages == 0)
                    book_needs_saving = false;
                else
                {
                    stack.set_visible_child_name ("document");
                    book_view.selected_page = book.get_page (0);
                    book_needs_saving = true;
                    book_changed_cb (book);
                }
            });
        }
    }
}

private class CancellableProgressBar : Gtk.Box
{
    private Gtk.ProgressBar bar;
    private Gtk.Button? button;

    public CancellableProgressBar (string? text, Cancellable? cancellable)
    {
        this.orientation = Gtk.Orientation.HORIZONTAL;

        bar = new Gtk.ProgressBar ();
        bar.visible = true;
        bar.set_text (text);
        bar.set_show_text (true);
        prepend (bar);

        if (cancellable != null)
        {
            button = new Gtk.Button.with_label (/* Text of button for cancelling save */
                                                _("Cancel"));
            button.visible = true;
            button.clicked.connect (() =>
            {
                set_visible (false);
                cancellable.cancel ();
            });
            prepend (button);
        }
    }

    public void set_fraction (double fraction)
    {
        bar.set_fraction (fraction);
    }

    public void remove_with_delay (uint delay, Gtk.ActionBar parent)
    {
        button.set_sensitive (false);

        Timeout.add (delay, () =>
        {
            parent.remove (this);
            return false;
        });
    }
}

private class CropActions
{
    private GLib.SimpleActionGroup group;

    private GLib.SimpleAction none;
    private GLib.SimpleAction a4;
    private GLib.SimpleAction a5;
    private GLib.SimpleAction a6;
    private GLib.SimpleAction letter;
    private GLib.SimpleAction legal;
    private GLib.SimpleAction four_by_six;
    private GLib.SimpleAction a3;
    private GLib.SimpleAction custom;
    private GLib.SimpleAction rotate;

    private GLib.ActionEntry[] crop_entries =
    {
        { "none", AppWindow.crop_none_action_cb },
        { "a4", AppWindow.crop_a4_action_cb },
        { "a5", AppWindow.crop_a5_action_cb },
        { "a6", AppWindow.crop_a6_action_cb },
        { "letter", AppWindow.crop_letter_action_cb },
        { "legal", AppWindow.crop_legal_action_cb },
        { "four_by_six", AppWindow.crop_four_by_six_action_cb },
        { "a3", AppWindow.crop_a3_action_cb },
        { "custom", AppWindow.crop_custom_action_cb },
        { "rotate", AppWindow.crop_rotate_action_cb },
    };

    public CropActions (AppWindow window)
    {
        group = new GLib.SimpleActionGroup ();
        group.add_action_entries (crop_entries, window);
        
        none = (GLib.SimpleAction) group.lookup_action ("none");
        a4 = (GLib.SimpleAction) group.lookup_action ("a4");
        a5 = (GLib.SimpleAction) group.lookup_action ("a5");
        a6 = (GLib.SimpleAction) group.lookup_action ("a6");
        letter = (GLib.SimpleAction) group.lookup_action ("letter");
        legal = (GLib.SimpleAction) group.lookup_action ("legal");
        four_by_six = (GLib.SimpleAction) group.lookup_action ("four_by_six");
        a3 = (GLib.SimpleAction) group.lookup_action ("a3");
        custom = (GLib.SimpleAction) group.lookup_action ("custom");
        rotate = (GLib.SimpleAction) group.lookup_action ("rotate");

        window.insert_action_group ("crop", group);
    }

    public void update_current_crop (string? crop_name)
    {
        rotate.set_enabled (crop_name != null);

        if (crop_name == null)
        {
            crop_name = "none";
        }

        none.set_enabled (true);
        a4.set_enabled (true);
        a5.set_enabled (true);
        a6.set_enabled (true);
        letter.set_enabled (true);
        legal.set_enabled (true);
        four_by_six.set_enabled (true);
        a3.set_enabled (true);
        custom.set_enabled (true);
        
        GLib.SimpleAction active_action = none;

        switch (crop_name)
        {
        case "A3":
            active_action = a3;
            break;
        case "A4":
            active_action = a4;
            break;
        case "A5":
            active_action = a5;
            break;
        case "A6":
            active_action = a6;
            break;
        case "letter":
            active_action = letter;
            break;
        case "legal":
            active_action = legal;
            break;
        case "4x6":
            active_action = four_by_six;
            break;
        case "custom":
            active_action = custom;
            break;
        default:
            active_action = none;
            break;
        }
        
        active_action.set_enabled (false);
    }
}