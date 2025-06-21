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
        { "scan_type", scan_type_action_cb, "s", "'single'"},
        { "document_hint", document_hint_action_cb, "s", "'text'"},
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
    
    private GLib.SimpleAction scan_type_action;
    private GLib.SimpleAction document_hint_action;

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
    private unowned Gtk.PopoverMenu page_menu;
    [GtkChild]
    private unowned Gtk.Stack stack;
    [GtkChild]
    private unowned Adw.StatusPage status_page;
    [GtkChild]
    private unowned Gtk.Label status_secondary_label;
    private ListStore device_model;
    [GtkChild]
    private unowned Gtk.Box device_buttons_box;
    [GtkChild]
    private unowned Gtk.DropDown device_drop_down;
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
    
    static string get_device_label (ScanDevice device) {
        return device.label;
    }

    public AppWindow ()
    {
        settings = new Settings ("org.gnome.SimpleScan");

        device_model = new ListStore (typeof (ScanDevice));
        device_drop_down.model = device_model;
        device_drop_down.expression = new Gtk.CClosureExpression (
            typeof (string),
            null,
            {},
            (Callback) get_device_label,
            null,
            null
        );

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
        var dialog = new Adw.AlertDialog (error_title,
                                          error_text);
        dialog.add_response ("close", _("_Close"));
        dialog.set_response_appearance ("close", Adw.ResponseAppearance.SUGGESTED);
        dialog.present (this);
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
            device_drop_down.sensitive = true;
        }
        else if (this.missing_driver != null)
        {
            status_page.set_title (/* Warning displayed when no drivers are installed but a compatible scanner is detected */
                                   _("Additional Software Needed"));
            /* Instructions to install driver software */
            status_secondary_label.set_markup (_("You need to <a href=\"install-firmware\">install driver software</a> for your scanner"));
            status_secondary_label.visible = true;
            device_buttons_box.visible = false;
        }
        else
        {
            /* Warning displayed when no scanners are detected */
            status_page.set_title (_("No Scanners Detected"));
            /* Hint to user on why there are no scanners detected */
            status_secondary_label.set_text (_("Please check your scanner is connected and powered on"));
            status_secondary_label.visible = true;
            device_buttons_box.visible = true;
            device_buttons_box.sensitive = true;
            device_drop_down.sensitive = false; // We would like to be refresh button to be active
        }
    }

    public void set_scan_devices (List<ScanDevice> devices, string? missing_driver = null)
    {
        have_devices = true;
        this.missing_driver = missing_driver;

        // Ignore selected events during this code, to prevent updating "selected-device"
        setting_devices = true;
        
        {
            /* 
            Technically this could be optimized, but:
            a) for the typical amount of scanners that would probably be overkill 
            b) we rescan only on user action so this is rarely called
            */
            device_model.remove_all ();

            /* Add new devices */
            foreach (var device in devices)
            {
                device_model.append (device);
            }

            /* Select the previously selected device or the first available device */
            var device_name = settings.get_string ("selected-device");
            
            uint position = 0;
            if (device_name != null && find_device_by_name (device_name, out position) != null)
                device_drop_down.selected = position;
            else
                device_drop_down.selected = 0;
        }

        setting_devices = false;

        update_scan_status ();
    }

    private async bool prompt_to_load_autosaved_book ()
    {
        var dialog = new Adw.AlertDialog ("",
                                          /* Contents of dialog that shows if autosaved book should be loaded. */
                                          _("An autosaved book exists. Do you want to open it?"));

        dialog.add_response ("no", _("_No"));
        dialog.add_response ("yes", _("_Yes"));
        
        dialog.set_response_appearance ("no", Adw.ResponseAppearance.DESTRUCTIVE);
        dialog.set_response_appearance ("yes", Adw.ResponseAppearance.SUGGESTED);

        dialog.set_default_response("yes");
        dialog.present (this);

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
        if (device_drop_down.selected != Gtk.INVALID_LIST_POSITION)
        {
            return ((ScanDevice) device_model.get_item (device_drop_down.selected)).name;
        }

        return null;
    }

    private string? get_selected_device_label ()
    {
        if (device_drop_down.selected != Gtk.INVALID_LIST_POSITION)
        {
            return ((ScanDevice) device_model.get_item (device_drop_down.selected)).label;
        }

        return null;
    }

    public void set_selected_device (string device)
    {
        user_selected_device = true;

        uint position;
        find_device_by_name (device, out position);

        if (position != Gtk.INVALID_LIST_POSITION)
            return;

        device_drop_down.selected = position;
    }

    private ScanDevice? find_device_by_name(string name, out uint position)
    {
        for (uint i = 0; i < device_model.get_n_items (); i++)
        {
            var item = (ScanDevice?) device_model.get_item (i);
            if (item.name == name) {
                position = i;
                return item;
            }
        }
        
        position = Gtk.INVALID_LIST_POSITION;
        return null;
    }

    private async string? choose_file_location ()
    {
        /* Get directory to save to */
        string? directory = null;
        directory = settings.get_string ("save-directory");

        if (directory == null || directory == "")
            directory = GLib.Filename.to_uri(Environment.get_user_special_dir (UserDirectory.DOCUMENTS));
        
        var save_dialog = new Gtk.FileDialog ();
        save_dialog.title = _("Save As…");
        save_dialog.modal = true;
        save_dialog.accept_label = _("_Save");

        // TODO(gtk4)
        //  save_dialog.local_only = false;

        var save_format = settings.get_string ("save-format");
        if (book_uri != null)
        {
            save_dialog.initial_file = GLib.File.new_for_uri (book_uri);
        }
        else
        {
            save_dialog.initial_folder = GLib.File.new_for_uri (directory);

            /* Default filename to use when saving document. */
            /* To that filename the extension will be added, eg. "Scanned Document.pdf" */
            save_dialog.initial_name = (_("Scanned Document") + "." + mime_type_to_extension (save_format));
        }
        
        var filters = new ListStore (typeof (Gtk.FileFilter));

        var pdf_filter = new Gtk.FileFilter ();
        pdf_filter.set_filter_name (_("PDF (multi-page document)"));
        pdf_filter.add_pattern ("*.pdf" );
        pdf_filter.add_mime_type ("application/pdf");
        filters.append (pdf_filter);
        
        var jpeg_filter = new Gtk.FileFilter ();
        jpeg_filter.set_filter_name (_("JPEG (compressed)"));
        jpeg_filter.add_pattern ("*.jpg" );
        jpeg_filter.add_pattern ("*.jpeg" );
        jpeg_filter.add_mime_type ("image/jpeg");
        filters.append (jpeg_filter);

        var png_filter = new Gtk.FileFilter ();
        png_filter.set_filter_name (_("PNG (lossless)"));
        png_filter.add_pattern ("*.png" );
        png_filter.add_mime_type ("image/png");
        filters.append (png_filter);

        var webp_filter = new Gtk.FileFilter ();
        webp_filter.set_filter_name (_("WebP (compressed)"));
        webp_filter.add_pattern ("*.webp" );
        webp_filter.add_mime_type ("image/webp");
        filters.append (webp_filter);

        var all_filter = new Gtk.FileFilter ();
        all_filter.set_filter_name (_("All Files"));
        all_filter.add_pattern ("*");
        filters.append (all_filter);
        
        save_dialog.filters = filters;
        
        switch (save_format)
        {
            case "application/pdf":
                save_dialog.default_filter = pdf_filter;
                break;
            case "image/jpeg":
                save_dialog.default_filter = jpeg_filter;
                break;
            case "image/png":
                save_dialog.default_filter = png_filter;
                break;
            case "image/webp":
                save_dialog.default_filter = webp_filter;
                break;
        }
        
        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
        box.visible = true;
        box.spacing = 10;
        box.set_halign (Gtk.Align.CENTER);

        while (true)
        {
            File? file = null;
            try {
                file = yield save_dialog.save (this, null);
            }
            catch (Error e) 
            {
                warning ("Failed to open save dialog: %s", e.message);
            }

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
                overwrite_check = yield check_overwrite (this, files);
            }

            if (overwrite_check)
            {
                var directory_uri = uri.substring (0, uri.last_index_of ("/") + 1);
                settings.set_string ("save-directory", directory_uri);
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

            var dialog = new Adw.AlertDialog (/* Contents of dialog that shows if saving would overwrite and existing file. %s is replaced with the name of the file. */
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
            
            dialog.present (parent);

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

        try
        {
            yield book.postprocess_async (
                mime_type, file, settings.get_boolean ("postproc-enabled"), settings.get_string ("postproc-script"),
                settings.get_string ("postproc-arguments"), settings.get_boolean ("postproc-keep-original"));
        }
        catch (Error e)
        {
            warning ("Error running postprocessing: %s", e.message);
            show_error_dialog (/* Title of error dialog when postprocessing failed */
                              _("Failed to run postprocessing"),
                              e.message);
        }

        book_needs_saving = false;
        book_uri = uri;
        return true;
    }

    private async bool prompt_to_save_async (string title, string discard_label)
    {
        if (!book_needs_saving || (book.n_pages == 0))
            return true;

        var dialog = new Adw.AlertDialog (title,
                                          _("If you don’t save, changes will be permanently lost."));

        dialog.add_response ("discard", discard_label);
        dialog.add_response ("cancel", _("_Cancel"));
        dialog.add_response ("save", _("_Save"));
        
        dialog.set_response_appearance ("discard", Adw.ResponseAppearance.DESTRUCTIVE);
        dialog.set_response_appearance ("save", Adw.ResponseAppearance.SUGGESTED);

        dialog.present (this);
        
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

        var page = book_view.selected_page;
        if (page == null)
        {
            warning ("Trying to set crop but no selected page");
            return;
        }

        if (btn.active)
        {
            // Avoid overwriting crop name if there is already different crop active
            if (!page.has_crop)
                set_crop ("custom");
        }
        else
        {
            set_crop (null);
        }
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

    private void scan_type_action_cb (SimpleAction action, Variant? value)
    {
        var type = value.get_string ();
       
        switch (type) {
            case "single":
                set_scan_type (ScanType.SINGLE);
                break;
            case "adf":
                set_scan_type (ScanType.ADF);
                break;
            case "batch":
                set_scan_type (ScanType.BATCH);
                break;
            default:
                return;
        }
    }

    private void document_hint_action_cb (SimpleAction action, Variant? value)
    {
        var hint = value.get_string ();
        set_document_hint(hint, true);
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
            scan_type_action.set_state ("single");
            scan_button_content.icon_name = "scanner-symbolic";
            scan_button.tooltip_text = _("Scan a Single Page");
            break;
        case ScanType.ADF:
            scan_type_action.set_state ("adf");
            scan_button_content.icon_name = "scan-type-adf-symbolic";
            scan_button.tooltip_text = _("Scan Multiple Pages");
            break;
        case ScanType.BATCH:
            scan_type_action.set_state ("batch");
            scan_button_content.icon_name = "scan-type-batch-symbolic";
            scan_button.tooltip_text = _("Scan Multiple Pages");
            break;
        }
    }

    private void set_document_hint (string document_hint, bool save = false)
    {
        this.document_hint = document_hint;

        document_hint_action.set_state (document_hint);

        if (save)
            settings.set_string ("document-type", document_hint);
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
    private void device_drop_down_changed_cb (Object widget, ParamSpec spec)
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
        preferences_dialog.present (this);
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

        var launcher = new Gtk.FileLauncher(file);
        launcher.launch.begin (this, null);
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

        if (crop_name == "none")
            crop_name = null;

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
        
        crop_actions.update_current_crop (crop_name);
        crop_button.active = page.has_crop;
    }
    
    public void crop_set_action_cb (SimpleAction action, Variant? value)
    {
        set_crop (value.get_string ());
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
                null, null);
            yield book.postprocess_async (mime_type, file, settings.get_boolean ("postproc-enabled"),
                settings.get_string ("postproc-script"), settings.get_string ("postproc-arguments"),
                settings.get_boolean ("postproc-keep-original"));
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
        var launcher = new Gtk.UriLauncher ("help:simple-scan");
        launcher.launch.begin (this, null);
    }

    private void help_cb ()
    {
        launch_help ();
    }

    private void show_about ()
    {
        string[] authors = { "Robert Ancell <robert.ancell@canonical.com>" };

        var about = new Adw.AboutDialog ()
        {
            developers = authors,
            translator_credits = _("translator-credits"),
            copyright = "Copyright © 2009-2018 Canonical Ltd.",
            license_type = Gtk.License.GPL_3_0,
            application_name = _("Document Scanner"),
            application_icon = "org.gnome.SimpleScan",
            version = VERSION,
            website = "https://gitlab.gnome.org/GNOME/simple-scan",
            issue_url = "https://gitlab.gnome.org/GNOME/simple-scan/-/issues/",
        };
        
        about.present (this);
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

        Gtk.Window.set_default_icon_name ("org.gnome.SimpleScan");

        var app = Application.get_default () as Gtk.Application;

        crop_actions = new CropActions (this);

        app.add_action_entries (action_entries, this);

        scan_type_action = (GLib.SimpleAction) app.lookup_action("scan_type");
        document_hint_action = (GLib.SimpleAction) app.lookup_action("document_hint");
        
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
        section.append (_("_Email…"), "app.email");
        section.append (_("Pri_nt…"), "app.print");
        section.append (C_("menu", "_Reorder Pages…"), "app.reorder");
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

    private GLib.SimpleAction crop_set;
    private GLib.SimpleAction crop_rotate;

    private GLib.ActionEntry[] crop_entries =
    {
        { "set", AppWindow.crop_set_action_cb, "s", "'none'" },
        { "rotate", AppWindow.crop_rotate_action_cb },
    };

    public CropActions (AppWindow window)
    {
        group = new GLib.SimpleActionGroup ();
        group.add_action_entries (crop_entries, window);
        
        crop_set = (GLib.SimpleAction) group.lookup_action ("set");
        crop_rotate = (GLib.SimpleAction) group.lookup_action ("rotate");

        window.insert_action_group ("crop", group);
    }

    public void update_current_crop (string? crop_name)
    {
        crop_rotate.set_enabled (crop_name != null);
        
        if (crop_name == null)
            crop_set.set_state ("none");
        else
            crop_set.set_state (crop_name);
    }
}
