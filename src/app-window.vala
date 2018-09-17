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

[GtkTemplate (ui = "/org/gnome/SimpleScan/app-window.ui")]
public class AppWindow : Gtk.ApplicationWindow
{
    private const GLib.ActionEntry[] action_entries =
    {
        { "new_document", new_document_activate_cb },
        { "reorder", reorder_document_activate_cb },
        { "save", save_document_activate_cb },
        { "email", email_document_activate_cb },
        { "print", print_document_activate_cb },
        { "preferences", preferences_activate_cb },
        { "help", help_contents_activate_cb },
        { "about", about_activate_cb },
        { "quit", quit_activate_cb }
    };

    private Settings settings;

    private PreferencesDialog preferences_dialog;

    [GtkChild]
    private Gtk.HeaderBar header_bar;
    [GtkChild]
    private Gtk.MenuBar menubar;
    [GtkChild]
    private Gtk.Toolbar toolbar;
    [GtkChild]
    private Gtk.Menu page_menu;
    [GtkChild]
    private Gtk.Stack stack;
    [GtkChild]
    private Gtk.Label status_primary_label;
    [GtkChild]
    private Gtk.Label status_secondary_label;
    [GtkChild]
    private Gtk.Box main_vbox;
    [GtkChild]
    private Gtk.RadioMenuItem custom_crop_menuitem;
    [GtkChild]
    private Gtk.RadioMenuItem a3_menuitem;
    [GtkChild]
    private Gtk.RadioMenuItem a4_menuitem;
    [GtkChild]
    private Gtk.RadioMenuItem a5_menuitem;
    [GtkChild]
    private Gtk.RadioMenuItem a6_menuitem;
    [GtkChild]
    private Gtk.RadioMenuItem letter_menuitem;
    [GtkChild]
    private Gtk.RadioMenuItem legal_menuitem;
    [GtkChild]
    private Gtk.RadioMenuItem four_by_six_menuitem;
    [GtkChild]
    private Gtk.RadioMenuItem no_crop_menuitem;
    [GtkChild]
    private Gtk.MenuItem page_move_left_menuitem;
    [GtkChild]
    private Gtk.MenuItem page_move_right_menuitem;
    [GtkChild]
    private Gtk.MenuItem page_delete_menuitem;
    [GtkChild]
    private Gtk.MenuItem crop_rotate_menuitem;
    [GtkChild]
    private Gtk.MenuItem save_menuitem;
    [GtkChild]
    private Gtk.MenuItem email_menuitem;
    [GtkChild]
    private Gtk.MenuItem print_menuitem;
    [GtkChild]
    private Gtk.MenuItem copy_to_clipboard_menuitem;
    [GtkChild]
    private Gtk.Button save_button;
    [GtkChild]
    private Gtk.ToolButton save_toolbutton;
    [GtkChild]
    private Gtk.MenuItem stop_scan_menuitem;
    [GtkChild]
    private Gtk.ToolButton stop_toolbutton;
    [GtkChild]
    private Gtk.Button stop_button;
    [GtkChild]
    private Gtk.Button scan_button;
    [GtkChild]
    private Gtk.ActionBar action_bar;
    private Gtk.ToggleButton crop_button;
    private Gtk.Button delete_button;

    [GtkChild]
    private Gtk.RadioMenuItem text_button_menuitem;
    [GtkChild]
    private Gtk.RadioMenuItem text_button_hb_menuitem;
    [GtkChild]
    private Gtk.RadioMenuItem text_menuitem;
    [GtkChild]
    private Gtk.RadioMenuItem photo_button_menuitem;
    [GtkChild]
    private Gtk.RadioMenuItem photo_button_hb_menuitem;
    [GtkChild]
    private Gtk.RadioMenuItem photo_menuitem;

    [GtkChild]
    private Gtk.MenuButton menu_button;

    private string? missing_driver = null;

    private Gtk.FileChooserDialog? save_dialog;

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
            page_delete_menuitem.sensitive = !value;
            delete_button.sensitive = !value;
            stop_scan_menuitem.sensitive = value;
            stop_toolbutton.sensitive = value;
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

    public string? selected_device
    {
        owned get { return preferences_dialog.get_selected_device (); }
        set { preferences_dialog.set_selected_device (value); }
    }

    public signal void start_scan (string? device, ScanOptions options);
    public signal void stop_scan ();

    public AppWindow ()
    {
        settings = new Settings ("org.gnome.SimpleScan");

        book = new Book ();
        book.page_added.connect (page_added_cb);
        book.reordered.connect (reordered_cb);
        book.page_removed.connect (page_removed_cb);
        book.changed.connect (book_changed_cb);

        load ();

        clear_document ();
        autosave_manager = new AutosaveManager ();
        autosave_manager.book = book;
        autosave_manager.load ();

        if (book.n_pages == 0)
            book_needs_saving = false;
        else
        {
            stack.set_visible_child_name ("document");
            book_view.selected_page = book.get_page (0);
            book_needs_saving = true;
            book_changed_cb (book);
        }
    }

    ~AppWindow ()
    {
        book.page_added.disconnect (page_added_cb);
        book.reordered.disconnect (reordered_cb);
        book.page_removed.disconnect (page_removed_cb);
    }

    public void show_error_dialog (string error_title, string error_text)
    {
        var dialog = new Gtk.MessageDialog (this,
                                            Gtk.DialogFlags.MODAL,
                                            Gtk.MessageType.WARNING,
                                            Gtk.ButtonsType.NONE,
                                            "%s", error_title);
        dialog.add_button (_("_Close"), 0);
        dialog.format_secondary_text ("%s", error_text);
        dialog.run ();
        dialog.destroy ();
    }

    public void authorize (string resource, out string username, out string password)
    {
        /* Label in authorization dialog.  “%s” is replaced with the name of the resource requesting authorization */
        var description = _("Username and password required to access “%s”").printf (resource);
        var authorize_dialog = new AuthorizeDialog (description);
        authorize_dialog.visible = true;
        authorize_dialog.transient_for = this;
        authorize_dialog.run ();
        authorize_dialog.destroy ();

        username = authorize_dialog.get_username ();
        password = authorize_dialog.get_password ();
    }

    public void set_scan_devices (List<ScanDevice> devices, string? missing_driver = null)
    {
        this.missing_driver = missing_driver;

        preferences_dialog.set_scan_devices (devices);

        if (devices != null)
        {
            status_primary_label.set_text (/* Label shown when detected a scanner */
                                           _("Ready to Scan"));
            status_secondary_label.set_text (preferences_dialog.get_selected_device_label ());
            status_secondary_label.visible = true;
        }
        else if (missing_driver != null)
        {
            status_primary_label.set_text (/* Warning displayed when no drivers are installed but a compatible scanner is detected */
                                           _("Additional software needed"));
            /* Instructions to install driver software */
            status_secondary_label.set_markup (_("You need to <a href=\"install-firmware\">install driver software</a> for your scanner."));
            status_secondary_label.visible = true;
        }
        else
        {
            /* Warning displayed when no scanners are detected */
            status_primary_label.set_text (_("No scanners detected"));
            /* Hint to user on why there are no scanners detected */
            status_secondary_label.set_text (_("Please check your scanner is connected and powered on"));
            status_secondary_label.visible = true;
        }
    }

    private string choose_file_location ()
    {
        /* Get directory to save to */
        string? directory = null;
        directory = settings.get_string ("save-directory");

        if (directory == null || directory == "")
            directory = Environment.get_user_special_dir (UserDirectory.DOCUMENTS);

        save_dialog = new Gtk.FileChooserDialog (/* Save dialog: Dialog title */
                                                 _("Save As…"),
                                                 this,
                                                 Gtk.FileChooserAction.SAVE,
                                                 _("_Cancel"), Gtk.ResponseType.CANCEL,
                                                 _("_Save"), Gtk.ResponseType.ACCEPT,
                                                 null);
        save_dialog.local_only = false;
        if (book_uri != null)
            save_dialog.set_uri (book_uri);
        else {
            save_dialog.set_current_folder (directory);
            /* Default filename to use when saving document */
            save_dialog.set_current_name (_("Scanned Document.pdf"));
        }

        /* Filter to only show images by default */
        var filter = new Gtk.FileFilter ();
        filter.set_filter_name (/* Save dialog: Filter name to show only supported image files */
                                _("Image Files"));
        filter.add_mime_type ("image/jpeg");
        filter.add_mime_type ("image/png");
#if HAVE_WEBP
        filter.add_mime_type ("image/webp");
#endif
        filter.add_mime_type ("application/pdf");
        save_dialog.add_filter (filter);
        filter = new Gtk.FileFilter ();
        filter.set_filter_name (/* Save dialog: Filter name to show all files */
                                _("All Files"));
        filter.add_pattern ("*");
        save_dialog.add_filter (filter);

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
#if HAVE_WEBP
        file_type_store.append (out iter);
        file_type_store.set (iter,
                             /* Save dialog: Label for sabing in WEBP format */
                             0, _("WebP (compressed)"),
                             1, ".webp",
                             -1);
#endif

        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
        box.visible = true;
        save_dialog.set_extra_widget (box);

        /* Label in save dialog beside combo box to choose file format (PDF, JPEG, PNG, WEBP) */
        var label = new Gtk.Label (_("File format:"));
        label.visible = true;
        box.pack_start (label, false, false, 0);

        var file_type_combo = new Gtk.ComboBox.with_model (file_type_store);
        file_type_combo.visible = true;
        var renderer = new Gtk.CellRendererText ();
        file_type_combo.pack_start (renderer, true);
        file_type_combo.add_attribute (renderer, "text", 0);
        box.pack_start (file_type_combo, false, true, 0);

        /* Label in save dialog beside compression slider */
        var quality_label = new Gtk.Label (_("Compression:"));
        box.pack_start (quality_label, false, false, 0);

        var quality_adjustment = new Gtk.Adjustment (75, 0, 100, 1, 10, 0);
        var quality_scale = new Gtk.Scale (Gtk.Orientation.HORIZONTAL, quality_adjustment);
        quality_scale.width_request = 200;
        quality_scale.draw_value = false;
        quality_scale.add_mark (0, Gtk.PositionType.BOTTOM, null);
        quality_scale.add_mark (75, Gtk.PositionType.BOTTOM, null);
        quality_scale.add_mark (90, Gtk.PositionType.BOTTOM, null);
        quality_scale.add_mark (100, Gtk.PositionType.BOTTOM, null);
        quality_adjustment.value = settings.get_int ("jpeg-quality");
        quality_adjustment.value_changed.connect (() => { settings.set_int ("jpeg-quality", (int) quality_adjustment.value); });
        box.pack_start (quality_scale, false, false, 0);

        file_type_combo.set_active (0);
        file_type_combo.changed.connect (() =>
        {
            var extension = "";
            Gtk.TreeIter i;
            if (file_type_combo.get_active_iter (out i))
                file_type_store.get (i, 1, out extension, -1);

            var path = save_dialog.get_filename ();
            var filename = Path.get_basename (path);

            /* Replace extension */
            var extension_index = filename.last_index_of_char ('.');
            if (extension_index >= 0)
                filename = filename.slice (0, extension_index);
            filename = filename + extension;
            save_dialog.set_current_name (filename);

            /* Quality not applicable to PNG */
            quality_scale.visible = quality_label.visible = (extension != ".png");
        });

        string? uri = null;
        while (true)
        {
            var response = save_dialog.run ();
            if (response != Gtk.ResponseType.ACCEPT)
                break;

            var extension = "";
            Gtk.TreeIter i;
            if (file_type_combo.get_active_iter (out i))
                file_type_store.get (i, 1, out extension, -1);

            var path = save_dialog.get_filename ();
            var filename = Path.get_basename (path);

            var extension_index = filename.last_index_of_char ('.');
            if (extension_index < 0)
                path += extension;

            uri = File.new_for_path (path).get_uri ();

            /* Check the file(s) don't already exist */
            var files = new List<File> ();
            var format = uri_to_format (uri);
#if HAVE_WEBP
            if (format == "jpeg" || format == "png" || format == "webp")
#else
            if (format == "jpeg" || format == "png")
#endif
            {
                for (var j = 0; j < book.n_pages; j++)
                    files.append (make_indexed_file (uri, j, book.n_pages));
            }
            else
                files.append (File.new_for_uri (uri));

            if (check_overwrite (save_dialog, files))
                break;
        }

        settings.set_string ("save-directory", save_dialog.get_current_folder ());

        save_dialog.destroy ();
        save_dialog = null;

        return uri;
    }

    private bool check_overwrite (Gtk.Window parent, List<File> files)
    {
        foreach (var file in files)
        {
            if (!file.query_exists ())
                continue;

            var dialog = new Gtk.MessageDialog (parent, Gtk.DialogFlags.MODAL | Gtk.DialogFlags.DESTROY_WITH_PARENT, Gtk.MessageType.QUESTION, Gtk.ButtonsType.NONE,
                                                /* Contents of dialog that shows if saving would overwrite and existing file. %s is replaced with the name of the file. */
                                                _("A file named “%s” already exists.  Do you want to replace it?"), file.get_basename ());
            dialog.add_button (_("_Cancel"), Gtk.ResponseType.CANCEL);
            dialog.add_button (/* Button in dialog that shows if saving would overwrite and existing file. Clicking the button allows simple-scan to overwrite the file. */
                               _("_Replace"), Gtk.ResponseType.ACCEPT);
            var response = dialog.run ();
            dialog.destroy ();

            if (response != Gtk.ResponseType.ACCEPT)
                return false;
        }

        return true;
    }

    private string uri_to_format (string uri)
    {
        var uri_lower = uri.down ();
        if (uri_lower.has_suffix (".pdf"))
            return "pdf";
        else if (uri_lower.has_suffix (".png"))
            return "png";
#if HAVE_WEBP
        else if (uri_lower.has_suffix (".webp"))
            return "webp";
#endif
        else
            return "jpeg";
    }

    private async bool save_document_async ()
    {
        var uri = choose_file_location ();
        if (uri == null)
            return false;

        var file = File.new_for_uri (uri);

        debug ("Saving to '%s'", uri);

        var format = uri_to_format (uri);

        var cancellable = new Cancellable ();
        var progress_bar =  new CancellableProgressBar (_("Saving"), cancellable);
        action_bar.pack_end (progress_bar);
        progress_bar.visible = true;
        try
        {
            yield book.save_async (format, settings.get_int ("jpeg-quality"), file, (fraction) =>
            {
                progress_bar.set_fraction (fraction);
            }, cancellable);
        }
        catch (Error e)
        {
            progress_bar.destroy ();
            warning ("Error saving file: %s", e.message);
            show_error_dialog (/* Title of error dialog when save failed */
                              _("Failed to save file"),
                               e.message);
            return false;
        }
        progress_bar.destroy_with_delay (500);

        book_needs_saving = false;
        book_uri = uri;
        return true;
    }

    private async bool prompt_to_save_async (string title, string discard_label)
    {
        if (!book_needs_saving)
            return true;

        var dialog = new Gtk.MessageDialog (this,
                                            Gtk.DialogFlags.MODAL,
                                            Gtk.MessageType.WARNING,
                                            Gtk.ButtonsType.NONE,
                                            "%s", title);
        dialog.format_secondary_text ("%s",
                                      /* Text in dialog warning when a document is about to be lost*/
                                      _("If you don’t save, changes will be permanently lost."));
        dialog.add_button (discard_label, Gtk.ResponseType.NO);
        dialog.add_button (_("_Cancel"), Gtk.ResponseType.CANCEL);
        dialog.add_button (_("_Save"), Gtk.ResponseType.YES);

        var response = dialog.run ();
        dialog.destroy ();

        switch (response)
        {
        case Gtk.ResponseType.YES:
            if (yield save_document_async ())
                return true;
            else
                return false;
        case Gtk.ResponseType.NO:
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
        save_menuitem.sensitive = false;
        email_menuitem.sensitive = false;
        print_menuitem.sensitive = false;
        save_button.sensitive = false;
        save_toolbutton.sensitive = false;
        copy_to_clipboard_menuitem.sensitive = false;
        status_primary_label.set_text (/* Label shown when detected a scanner */
                                       _("Ready to Scan"));
        stack.set_visible_child_name ("startup");
    }

    private void new_document ()
    {
        prompt_to_save_async.begin (/* Text in dialog warning when a document is about to be lost */
                                    _("Save current document?"),
                                    /* Button in dialog to create new document and discard unsaved document */
                                    _("Discard Changes"), (obj, res) =>
        {
            if (!prompt_to_save_async.end(res))
                return;

            if (scanning)
                stop_scan ();

            clear_document ();
        });
    }

    [GtkCallback]
    private bool status_label_activate_link_cb (Gtk.Label label, string uri)
    {
        if (uri == "install-firmware")
        {
            install_drivers ();
            return true;
        }

        return false;
    }

    [GtkCallback]
    private void new_button_clicked_cb (Gtk.Widget widget)
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
            text_button_menuitem.active = true;
            text_button_hb_menuitem.active = true;
            text_menuitem.active = true;
        }
        else if (document_hint == "photo")
        {
            photo_button_menuitem.active = true;
            photo_button_hb_menuitem.active = true;
            photo_menuitem.active = true;
        }

        if (save)
            settings.set_string ("document-type", document_hint);
    }

    [GtkCallback]
    private void text_menuitem_toggled_cb (Gtk.CheckMenuItem widget)
    {
        if (widget.active)
            set_document_hint ("text", true);
    }

    [GtkCallback]
    private void photo_menuitem_toggled_cb (Gtk.CheckMenuItem widget)
    {
        if (widget.active)
            set_document_hint ("photo", true);
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

        return options;
    }

    [GtkCallback]
    private void scan_button_clicked_cb (Gtk.Widget widget)
    {
        var options = make_scan_options ();
        options.type = ScanType.SINGLE;
        status_primary_label.set_text (/* Label shown when scan started */
                                       _("Contacting scanner…"));
        start_scan (selected_device, options);
    }

    [GtkCallback]
    private void stop_scan_button_clicked_cb (Gtk.Widget widget)
    {
        stop_scan ();
    }

    [GtkCallback]
    private void continuous_scan_button_clicked_cb (Gtk.Widget widget)
    {
        if (scanning)
            stop_scan ();
        else
        {
            var options = make_scan_options ();
            options.type = preferences_dialog.get_page_side ();
            start_scan (selected_device, options);
        }
    }

    [GtkCallback]
    private void batch_button_clicked_cb (Gtk.Widget widget)
    {
        var options = make_scan_options ();
        options.type = ScanType.BATCH;
        start_scan (selected_device, options);
    }

    [GtkCallback]
    private void preferences_button_clicked_cb (Gtk.Widget widget)
    {
        preferences_dialog.present ();
    }

    public void preferences_activate_cb ()
    {
        preferences_dialog.present ();
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

        var menuitem = no_crop_menuitem;
        if (page.has_crop)
        {
            var crop_name = page.crop_name;
            if (crop_name != null)
            {
                if (crop_name == "A3")
                    menuitem = a3_menuitem;
                else if (crop_name == "A4")
                    menuitem = a4_menuitem;
                else if (crop_name == "A5")
                    menuitem = a5_menuitem;
                else if (crop_name == "A6")
                    menuitem = a6_menuitem;
                else if (crop_name == "letter")
                    menuitem = letter_menuitem;
                else if (crop_name == "legal")
                    menuitem = legal_menuitem;
                else if (crop_name == "4x6")
                    menuitem = four_by_six_menuitem;
            }
            else
                menuitem = custom_crop_menuitem;
        }

        menuitem.active = true;
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

        try
        {
            Gtk.show_uri (screen, file.get_uri (), Gtk.get_current_event_time ());
        }
        catch (Error e)
        {
            show_error_dialog (/* Error message display when unable to preview image */
                               _("Unable to open image preview application"),
                               e.message);
        }
    }

    private void show_page_menu_cb (BookView view, Gdk.Event event)
    {
        page_menu.popup_at_pointer (event);
    }

    [GtkCallback]
    private void rotate_left_button_clicked_cb (Gtk.Widget widget)
    {
        if (updating_page_menu)
            return;
        var page = book_view.selected_page;
        if (page != null)
            page.rotate_left ();
    }

    [GtkCallback]
    private void rotate_right_button_clicked_cb (Gtk.Widget widget)
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

    [GtkCallback]
    private void no_crop_menuitem_toggled_cb (Gtk.CheckMenuItem widget)
    {
        if (widget.active)
            set_crop (null);
    }

    [GtkCallback]
    private void custom_crop_menuitem_toggled_cb (Gtk.CheckMenuItem widget)
    {
        if (widget.active)
            set_crop ("custom");
    }

    [GtkCallback]
    private void four_by_six_menuitem_toggled_cb (Gtk.CheckMenuItem widget)
    {
        if (widget.active)
            set_crop ("4x6");
    }

    [GtkCallback]
    private void legal_menuitem_toggled_cb (Gtk.CheckMenuItem widget)
    {
        if (widget.active)
            set_crop ("legal");
    }

    [GtkCallback]
    private void letter_menuitem_toggled_cb (Gtk.CheckMenuItem widget)
    {
        if (widget.active)
            set_crop ("letter");
    }

    [GtkCallback]
    private void a6_menuitem_toggled_cb (Gtk.CheckMenuItem widget)
    {
        if (widget.active)
            set_crop ("A6");
    }

    [GtkCallback]
    private void a5_menuitem_toggled_cb (Gtk.CheckMenuItem widget)
    {
        if (widget.active)
            set_crop ("A5");
    }

    [GtkCallback]
    private void a4_menuitem_toggled_cb (Gtk.CheckMenuItem widget)
    {
        if (widget.active)
            set_crop ("A4");
    }

    [GtkCallback]
    private void a3_menuitem_toggled_cb (Gtk.CheckMenuItem widget)
    {
        if (widget.active)
            set_crop ("A3");
    }

    [GtkCallback]
    private void crop_rotate_menuitem_activate_cb (Gtk.Widget widget)
    {
        var page = book_view.selected_page;
        if (page == null)
            return;
        page.rotate_crop ();
    }

    [GtkCallback]
    private void page_move_left_menuitem_activate_cb (Gtk.Widget widget)
    {
        var page = book_view.selected_page;
        var index = book.get_page_index (page);
        if (index > 0)
            book.move_page (page, index - 1);
    }

    [GtkCallback]
    private void page_move_right_menuitem_activate_cb (Gtk.Widget widget)
    {
        var page = book_view.selected_page;
        var index = book.get_page_index (page);
        if (index < book.n_pages - 1)
            book.move_page (page, book.get_page_index (page) + 1);
    }

    [GtkCallback]
    private void page_delete_menuitem_activate_cb (Gtk.Widget widget)
    {
        book_view.book.delete_page (book_view.selected_page);
    }

    private void reorder_document ()
    {
        var dialog = new Gtk.Window ();
        dialog.type_hint = Gdk.WindowTypeHint.DIALOG;
        dialog.modal = true;
        dialog.border_width = 12;
        /* Title of dialog to reorder pages */
        dialog.title = _("Reorder Pages");
        dialog.set_transient_for (this);
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

    public void reorder_document_activate_cb ()
    {
        reorder_document ();
    }

    [GtkCallback]
    private void reorder_menuitem_activate_cb (Gtk.Widget widget)
    {
        reorder_document ();
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
                var a = new Gtk.Label ("➤");
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

    [GtkCallback]
    private void save_file_button_clicked_cb (Gtk.Widget widget)
    {
        save_document_async.begin ();
    }

    public void save_document_activate_cb ()
    {
        save_document_async.begin ();
    }

    [GtkCallback]
    private void copy_to_clipboard_button_clicked_cb (Gtk.Widget widget)
    {
        var page = book_view.selected_page;
        if (page != null)
            page.copy_to_clipboard (this);
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

    [GtkCallback]
    private void email_button_clicked_cb (Gtk.Widget widget)
    {
        email_document_async.begin ();
    }

    public void email_document_activate_cb ()
    {
        email_document_async.begin ();
    }

    private async void email_document_async ()
    {
        try
        {
            var dir = DirUtils.make_tmp ("simple-scan-XXXXXX");
            var type = document_hint == "text" ? "pdf" : "jpeg";
            var file = File.new_for_path (Path.build_filename (dir, "scan." + type));
            yield book.save_async (type, settings.get_int ("jpeg-quality"), file, null, null);
            var command_line = "xdg-email";
            if (type == "pdf")
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

    [GtkCallback]
    private void print_button_clicked_cb (Gtk.Widget widget)
    {
        print_document ();
    }

    public void print_document_activate_cb ()
    {
        print_document ();
    }

    private void launch_help ()
    {
        try
        {
            Gtk.show_uri (screen, "help:simple-scan", Gtk.get_current_event_time ());
        }
        catch (Error e)
        {
            show_error_dialog (/* Error message displayed when unable to launch help browser */
                               _("Unable to open help file"),
                               e.message);
        }
    }

    [GtkCallback]
    private void help_contents_menuitem_activate_cb (Gtk.Widget widget)
    {
        launch_help ();
    }

    public void help_contents_activate_cb ()
    {
        launch_help ();
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

        Gtk.show_about_dialog (this,
                               "title", title,
                               "program-name", "Simple Scan",
                               "version", VERSION,
                               "comments", description,
                               "logo-icon-name", "scanner",
                               "authors", authors,
                               "translator-credits", _("translator-credits"),
                               "website", "https://gitlab.gnome.org/GNOME/simple-scan",
                               "copyright", "Copyright © 2009-2018 Canonical Ltd.",
                               "license", license,
                               "wrap-license", true,
                               null);
    }

    [GtkCallback]
    private void about_menuitem_activate_cb (Gtk.Widget widget)
    {
        show_about ();
    }

    public void about_activate_cb ()
    {
        show_about ();
    }

    private void on_quit ()
    {
        prompt_to_save_async.begin (/* Text in dialog warning when a document is about to be lost */
                                    _("Save document before quitting?"),
                                    /* Text in dialog warning when a document is about to be lost */
                                    _("Quit without Saving"), (obj, res) =>
        {
            if (!prompt_to_save_async.end(res))
                return;

            destroy ();

            if (save_state_timeout != 0)
                save_state (true);

            autosave_manager.cleanup ();
        });
    }

    [GtkCallback]
    private void quit_menuitem_activate_cb (Gtk.Widget widget)
    {
        on_quit ();
    }

    public void quit_activate_cb ()
    {
        on_quit ();
    }

    public override void size_allocate (Gtk.Allocation allocation)
    {
        base.size_allocate (allocation);

        if (!window_is_maximized && !window_is_fullscreen)
        {
            get_size (out window_width, out window_height);
            save_state ();
        }
    }

    private void install_drivers ()
    {
        var message = "", instructions = "";
        string[] packages_to_install = {};
        switch (missing_driver)
        {
        case "brscan":
        case "brscan2":
        case "brscan3":
        case "brscan4":
            /* Message to indicate a Brother scanner has been detected */
            message = _("You appear to have a Brother scanner.");
            /* Instructions on how to install Brother scanner drivers */
            instructions = _("Drivers for this are available on the <a href=\"http://support.brother.com\">Brother website</a>.");
            break;
        case "samsung":
            /* Message to indicate a Samsung scanner has been detected */
            message = _("You appear to have a Samsung scanner.");
            /* Instructions on how to install Samsung scanner drivers */
            instructions = _("Drivers for this are available on the <a href=\"http://samsung.com/support\">Samsung website</a>.");
            break;
        case "hpaio":
            /* Message to indicate a HP scanner has been detected */
            message = _("You appear to have an HP scanner.");
            packages_to_install = { "libsane-hpaio" };
            break;
        case "epkowa":
            /* Message to indicate an Epson scanner has been detected */
            message = _("You appear to have an Epson scanner.");
            /* Instructions on how to install Epson scanner drivers */
            instructions = _("Drivers for this are available on the <a href=\"http://support.epson.com\">Epson website</a>.");
            break;
        }
        var dialog = new Gtk.Dialog.with_buttons (/* Title of dialog giving instructions on how to install drivers */
                                                  _("Install drivers"), this, Gtk.DialogFlags.MODAL, _("_Close"), Gtk.ResponseType.CLOSE);
        dialog.get_content_area ().border_width = 12;
        dialog.get_content_area ().spacing = 6;

        var label = new Gtk.Label (message);
        label.visible = true;
        label.xalign = 0f;
        dialog.get_content_area ().pack_start (label, true, true, 0);

        var instructions_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
        instructions_box.visible = true;
        dialog.get_content_area ().pack_start (instructions_box, true, true, 0);

        var stack = new Gtk.Stack ();
        instructions_box.pack_start (stack, false, false, 0);

        var spinner = new Gtk.Spinner ();
        spinner.visible = true;
        stack.add (spinner);

        var status_label = new Gtk.Label ("");
        status_label.visible = true;
        stack.add (status_label);

        var instructions_label = new Gtk.Label (instructions);
        instructions_label.visible = true;
        instructions_label.xalign = 0f;
        instructions_label.use_markup = true;
        instructions_box.pack_start (instructions_label, false, false, 0);

        label = new Gtk.Label (/* Message in driver install dialog */
                               _("Once installed you will need to restart Simple Scan."));
        label.visible = true;
        label.xalign = 0f;
        dialog.get_content_area ().border_width = 12;
        dialog.get_content_area ().pack_start (label, true, true, 0);

        if (packages_to_install.length > 0)
        {
#if HAVE_PACKAGEKIT
            stack.visible = true;
            spinner.active = true;
            instructions_label.set_text (/* Label shown while installing drivers */
                                         _("Installing drivers…"));
            install_packages.begin (packages_to_install, () => {}, (object, result) =>
            {
                status_label.visible = true;
                spinner.active = false;
                status_label.set_text ("☒");
                stack.visible_child = status_label;
                /* Label shown once drivers successfully installed */
                var result_text = _("Drivers installed successfully!");
                try
                {
                    var results = install_packages.end (result);
                    if (results.get_error_code () == null)
                        status_label.set_text ("☑");
                    else
                    {
                        var e = results.get_error_code ();
                        /* Label shown if failed to install drivers */
                        result_text = _("Failed to install drivers (error code %d).").printf (e.code);
                    }
                }
                catch (Error e)
                {
                    /* Label shown if failed to install drivers */
                    result_text = _("Failed to install drivers.");
                    warning ("Failed to install drivers: %s", e.message);
                }
                instructions_label.set_text (result_text);
            });
#else
            instructions_label.set_text (/* Label shown to prompt user to install packages (when PackageKit not available) */
                                         ngettext ("You need to install the %s package.", "You need to install the %s packages.", packages_to_install.length).printf (string.joinv (", ", packages_to_install)));
#endif
        }

        dialog.run ();
        dialog.destroy ();
    }

#if HAVE_PACKAGEKIT
    private async Pk.Results? install_packages (string[] packages, Pk.ProgressCallback progress_callback) throws GLib.Error
    {
        var task = new Pk.Task ();
        Pk.Results results;
        results = yield task.resolve_async (Pk.Filter.NOT_INSTALLED, packages, null, progress_callback);
        if (results == null || results.get_error_code () != null)
            return results;

        var package_array = results.get_package_array ();
        var package_ids = new string[package_array.length + 1];
        package_ids[package_array.length] = null;
        for (var i = 0; i < package_array.length; i++)
            package_ids[i] = package_array.data[i].get_id ();

        return yield task.install_packages_async (package_ids, null, progress_callback);
    }
#endif

    public override bool window_state_event (Gdk.EventWindowState event)
    {
        var result = Gdk.EVENT_PROPAGATE;

        if (base.window_state_event != null)
            result = base.window_state_event (event);

        if ((event.changed_mask & Gdk.WindowState.MAXIMIZED) != 0)
        {
            window_is_maximized = (event.new_window_state & Gdk.WindowState.MAXIMIZED) != 0;
            save_state ();
        }
        if ((event.changed_mask & Gdk.WindowState.FULLSCREEN) != 0)
        {
            window_is_fullscreen = (event.new_window_state & Gdk.WindowState.FULLSCREEN) != 0;
            save_state ();
        }

        return result;
    }

    [GtkCallback]
    private bool window_delete_event_cb (Gtk.Widget widget, Gdk.EventAny event)
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
        save_menuitem.sensitive = true;
        email_menuitem.sensitive = true;
        print_menuitem.sensitive = true;
        save_button.sensitive = true;
        save_toolbutton.sensitive = true;
        book_needs_saving = true;
        copy_to_clipboard_menuitem.sensitive = true;
    }

    private void load ()
    {
        var use_header_bar = !is_traditional_desktop ();

        preferences_dialog = new PreferencesDialog (settings, use_header_bar);
        preferences_dialog.delete_event.connect (() => { return true; });
        preferences_dialog.response.connect (() => { preferences_dialog.visible = false; });

        Gtk.IconTheme.get_default ().append_search_path (ICON_DIR);

        Gtk.Window.set_default_icon_name ("scanner");

        var app = Application.get_default () as Gtk.Application;

        if (!use_header_bar)
        {
            set_titlebar (null);
            menubar.visible = true;
            toolbar.visible = true;
        }
        else
        {
            /* Set HeaderBar title here because Glade doesn't keep it translated */
            /* https://bugzilla.gnome.org/show_bug.cgi?id=782753 */
            /* Title of scan window */
            header_bar.title = _("Simple Scan");

            app.add_action_entries (action_entries, this);

            app.set_accels_for_action ("app.new_document", { "<Ctrl>N" });
            app.set_accels_for_action ("app.save", { "<Ctrl>S" });
            app.set_accels_for_action ("app.email", { "<Ctrl>E" });
            app.set_accels_for_action ("app.print", { "<Ctrl>P" });
            app.set_accels_for_action ("app.help", { "F1" });
            app.set_accels_for_action ("app.quit", { "<Ctrl>Q" });

            var gear_menu = new Menu ();
            var section = new Menu ();
            gear_menu.append_section (null, section);
            section.append (_("Email"), "app.email");
            section.append (_("Reorder Pages"), "app.reorder");
            section = new Menu ();
            gear_menu.append_section (null, section);
            section.append (_("Preferences"), "app.preferences");
            section.append (_("Keyboard Shortcuts"), "win.show-help-overlay");
            section.append (_("Help"), "app.help");
            section.append (_("About"), "app.about");
            menu_button.set_menu_model (gear_menu);
        }
        app.add_window (this);

        /* Populate ActionBar (not supported in Glade) */
        /* https://bugzilla.gnome.org/show_bug.cgi?id=769966 */
        var button = new Gtk.Button.with_label (/* Label on new document button */
                                               _("Start Again…"));
        button.visible = true;
        button.clicked.connect (new_button_clicked_cb);
        action_bar.pack_start (button);

        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10);
        box.visible = true;
        action_bar.set_center_widget (box);

        var rotate_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        rotate_box.get_style_context ().add_class (Gtk.STYLE_CLASS_LINKED);
        rotate_box.visible = true;
        box.pack_start (rotate_box, false, true, 0);

        button = new Gtk.Button.from_icon_name ("object-rotate-left-symbolic");
        button.visible = true;
        /* Tooltip for rotate left (counter-clockwise) button */
        button.tooltip_text = _("Rotate the page to the left (counter-clockwise)");
        button.clicked.connect (rotate_left_button_clicked_cb);
        rotate_box.pack_start (button, false, true, 0);

        button = new Gtk.Button.from_icon_name ("object-rotate-right-symbolic");
        button.visible = true;
        /* Tooltip for rotate right (clockwise) button */
        button.tooltip_text = _("Rotate the page to the right (clockwise)");
        button.clicked.connect (rotate_right_button_clicked_cb);
        rotate_box.pack_start (button, false, true, 0);

        crop_button = new Gtk.ToggleButton ();
        crop_button.visible = true;
        var image = new Gtk.Image.from_icon_name ("edit-cut-symbolic", Gtk.IconSize.BUTTON);
        image.visible = true;
        crop_button.add (image);
        /* Tooltip for crop button */
        crop_button.tooltip_text = _("Crop the selected page");
        crop_button.toggled.connect ((widget) =>
        {
            if (updating_page_menu)
                return;

            if (widget.active)
                custom_crop_menuitem.active = true;
            else
                no_crop_menuitem.active = true;
        });
        box.pack_start (crop_button, false, true, 0);

        delete_button = new Gtk.Button.from_icon_name ("user-trash-symbolic");
        delete_button.visible = true;
        /* Tooltip for delete button */
        delete_button.tooltip_text = _("Delete the selected page");
        delete_button.clicked.connect (() => { book_view.book.delete_page (book_view.selected_page); });
        box.pack_start (delete_button, false, true, 0);

        var document_type = settings.get_string ("document-type");
        if (document_type != null)
            set_document_hint (document_type);

        book_view = new BookView (book);
        book_view.border_width = 18;
        main_vbox.pack_start (book_view, true, true, 0);
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

    private bool is_desktop (string name)
    {
        var desktop_name_list = Environment.get_variable ("XDG_CURRENT_DESKTOP");
        if (desktop_name_list == null)
            return false;

        foreach (var n in desktop_name_list.split (":"))
            if (n == name)
                return true;

        return false;
    }

    private bool is_traditional_desktop ()
    {
        const string[] traditional_desktops = { "Unity", "XFCE", "MATE", "LXDE", "Cinnamon", "X-Cinnamon", "i3" };
        foreach (var name in traditional_desktops)
            if (is_desktop (name))
                return true;
        return false;
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
        window_is_fullscreen = state_get_boolean (f, "window", "is-fullscreen");
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
        try
        {
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
    }
}

private class CancellableProgressBar : Gtk.HBox
{
    private Gtk.ProgressBar bar;
    private Gtk.Button? button;

    public CancellableProgressBar (string? text, Cancellable? cancellable)
    {
        bar = new Gtk.ProgressBar ();
        bar.visible = true;
        bar.set_text (text);
        bar.set_show_text (true);
        pack_start (bar);

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
            pack_start (button);
        }
    }

    public void set_fraction (double fraction)
    {
        bar.set_fraction (fraction);
    }

    public void destroy_with_delay (uint delay)
    {
        button.set_sensitive (false);

        Timeout.add (delay, () =>
        {
            this.destroy ();
            return false;
        });
    }
}
