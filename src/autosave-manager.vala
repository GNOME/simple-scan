/*
 * Copyright (C) 2011 Timo Kluck
 * Authors: Timo Kluck <tkluck@infty.nl>
 *          Robert Ancell <robert.ancell@canonical.com>
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later
 * version. See http://www.gnu.org/copyleft/gpl.html the full text of the
 * license.
 */

public class AutosaveManager
{
    private static string AUTOSAVE_DIR = Path.build_filename (Environment.get_user_cache_dir (), "simple-scan", "autosaves");
    private static string AUTOSAVE_FILENAME = "autosave.book";
    private static string AUTOSAVE_PATH = Path.build_filename (AUTOSAVE_DIR, AUTOSAVE_FILENAME);

    private uint update_timeout = 0;

    private HashTable<Page, string> page_filenames;

    private Book book_ = null;
    public Book book
    {
        get
        {
            return book_;
        }
        set
        {
            if (book_ != null)
            {
                for (var i = 0; i < book_.n_pages; i++)
                {
                    var page = book_.get_page (i);
                    on_page_removed (page);
                }
                book_.page_added.disconnect (on_page_added);
                book_.page_removed.disconnect (on_page_removed);
                book_.reordered.disconnect (on_changed);
                book_.cleared.disconnect (on_cleared);
            }
            book_ = value;
            book_.page_added.connect (on_page_added);
            book_.page_removed.connect (on_page_removed);
            book_.reordered.connect (on_changed);
            book_.cleared.connect (on_cleared);
            for (var i = 0; i < book_.n_pages; i++)
            {
                var page = book_.get_page (i);
                on_page_added (page);
            }
        }
    }

    public AutosaveManager ()
    {
        page_filenames = new HashTable<Page, string> (direct_hash, direct_equal);
    }

    public bool exists ()
    {
        var file = File.new_for_path (AUTOSAVE_PATH);
        return file.query_exists ();
    }

    public void load ()
    {
        debug ("Loading autosave information");

        book.clear ();
        page_filenames.remove_all ();

        var file = new KeyFile ();
        try
        {
            file.load_from_file (AUTOSAVE_PATH, KeyFileFlags.NONE);
        }
        catch (Error e)
        {
            if (!(e is FileError.NOENT))
                warning ("Could not load autosave information; not restoring any autosaves: %s", e.message);
            return;
        }
        var pages = get_value (file, "simple-scan", "pages");
        foreach (var page_name in pages.split (" "))
        {
            debug ("Loading automatically saved page %s", page_name);

            var scan_width = get_integer (file, page_name, "scan-width");
            var scan_height = get_integer (file, page_name, "scan-height");
            var rowstride = get_integer (file, page_name, "rowstride");
            var n_channels = get_integer (file, page_name, "n-channels");
            var depth = get_integer (file, page_name, "depth");
            var dpi = get_integer (file, page_name, "dpi");
            var scan_direction_name = get_value (file, page_name, "scan-direction");
            ScanDirection scan_direction = ScanDirection.TOP_TO_BOTTOM;
            switch (scan_direction_name)
            {
            case "TOP_TO_BOTTOM":
                scan_direction = ScanDirection.TOP_TO_BOTTOM;
                break;
            case "LEFT_TO_RIGHT":
                scan_direction = ScanDirection.LEFT_TO_RIGHT;
                break;
            case "BOTTOM_TO_TOP":
                scan_direction = ScanDirection.BOTTOM_TO_TOP;
                break;
            case "RIGHT_TO_LEFT":
                scan_direction = ScanDirection.RIGHT_TO_LEFT;
                break;
            }
            var color_profile = get_value (file, page_name, "color-profile");
            if (color_profile == "")
                color_profile = null;
            var pixels_filename = get_value (file, page_name, "pixels-filename");
            var has_crop = get_boolean (file, page_name, "has-crop");
            var crop_name = get_value (file, page_name, "crop-name");

            if (crop_name == "")
            {
                // If it has no crop name but has crop it probably means that it is a custom crop
                if (has_crop)
                    crop_name = "custom";
                else
                    crop_name = null;
            }

            var crop_x = get_integer (file, page_name, "crop-x");
            var crop_y = get_integer (file, page_name, "crop-y");
            var crop_width = get_integer (file, page_name, "crop-width");
            var crop_height = get_integer (file, page_name, "crop-height");

            uchar[]? pixels = null;
            if (pixels_filename != "")
            {
                var path = Path.build_filename (AUTOSAVE_DIR, pixels_filename);
                var f = File.new_for_path (path);
                try
                {
                    f.load_contents (null, out pixels, null);
                }
                catch (Error e)
                {
                    warning ("Failed to load pixel information");
                    continue;
                }
            }

            var page = new Page.from_data (scan_width,
                                           scan_height,
                                           rowstride,
                                           n_channels,
                                           depth,
                                           dpi,
                                           scan_direction,
                                           color_profile,
                                           pixels,
                                           has_crop,
                                           crop_name,
                                           crop_x,
                                           crop_y,
                                           crop_width,
                                           crop_height);
            page_filenames.insert (page, pixels_filename);
            book.append_page (page);
        }
    }

    private string get_value (KeyFile file, string group_name, string key, string default = "")
    {
        try
        {
            return file.get_value (group_name, key);
        }
        catch (Error e)
        {
            return default;
        }
    }

    private int get_integer (KeyFile file, string group_name, string key, int default = 0)
    {
        try
        {
            return file.get_integer (group_name, key);
        }
        catch (Error e)
        {
            return default;
        }
    }

    private bool get_boolean (KeyFile file, string group_name, string key, bool default = false)
    {
        try
        {
            return file.get_boolean (group_name, key);
        }
        catch (Error e)
        {
            return default;
        }
    }

    public void cleanup ()
    {
        debug ("Deleting autosave records");

        if (update_timeout > 0)
            Source.remove (update_timeout);
        update_timeout = 0;

        Dir dir;
        try
        {
            dir = Dir.open (AUTOSAVE_DIR);
        }
        catch (Error e)
        {
            warning ("Failed to delete autosaves: %s", e.message);
            return;
        }

        while (true)
        {
            var filename = dir.read_name ();
            if (filename == null)
                break;
            var path = Path.build_filename (AUTOSAVE_DIR, filename);
            FileUtils.unlink (path);
        }
    }

    public void on_page_added (Page page)
    {
        page.scan_finished.connect (on_scan_finished);
        page.crop_changed.connect (on_changed);
    }

    public void on_page_removed (Page page)
    {
        page.scan_finished.disconnect (on_scan_finished);
        page.crop_changed.disconnect (on_changed);

        var filename = page_filenames.lookup (page);
        if (filename != null)
            FileUtils.unlink (filename);
        page_filenames.remove (page);
    }

    public void on_scan_finished (Page page)
    {
        save_pixels (page);
        save (false);
    }

    public void on_changed ()
    {
        save ();
    }

    public void on_cleared ()
    {
        page_filenames.remove_all ();
        save ();
    }

    private void save (bool do_timeout = true)
    {
        if (update_timeout == 0 && do_timeout)
            debug ("Waiting to autosave...");

        /* Cancel existing timeout */
        if (update_timeout > 0)
            Source.remove (update_timeout);
        update_timeout = 0;

        if (do_timeout)
        {
            update_timeout = Timeout.add (100, () =>
            {
                real_save ();
                update_timeout = 0;
                return false;
            });
        }
        else
            real_save();
    }

    private void real_save ()
    {
        debug ("Autosaving book information");

        var file = new KeyFile ();
        var page_names = "";
        for (var i = 0; i < book.n_pages; i++)
        {
            var page = book.get_page (i);

            /* Skip empty pages */
            if (!page.has_data)
                continue;

            var page_name = "page-%d".printf (i);
            if (page_names != "")
                page_names += " ";
            page_names += page_name;

            debug ("Autosaving page %s", page_name);

            file.set_integer (page_name, "scan-width", page.scan_width);
            file.set_integer (page_name, "scan-height", page.scan_height);
            file.set_integer (page_name, "rowstride", page.rowstride);
            file.set_integer (page_name, "n-channels", page.n_channels);
            file.set_integer (page_name, "depth", page.depth);
            file.set_integer (page_name, "dpi", page.dpi);
            switch (page.scan_direction)
            {
            case ScanDirection.TOP_TO_BOTTOM:
                file.set_value (page_name, "scan-direction", "TOP_TO_BOTTOM");
                break;
            case ScanDirection.LEFT_TO_RIGHT:
                file.set_value (page_name, "scan-direction", "LEFT_TO_RIGHT");
                break;
            case ScanDirection.BOTTOM_TO_TOP:
                file.set_value (page_name, "scan-direction", "BOTTOM_TO_TOP");
                break;
            case ScanDirection.RIGHT_TO_LEFT:
                file.set_value (page_name, "scan-direction", "RIGHT_TO_LEFT");
                break;
            }
            file.set_value (page_name, "color-profile", page.color_profile ?? "");
            file.set_value (page_name, "pixels-filename", page_filenames.lookup (page) ?? "");
            file.set_boolean (page_name, "has-crop", page.has_crop);
            file.set_value (page_name, "crop-name", page.crop_name ?? "");
            file.set_integer (page_name, "crop-x", page.crop_x);
            file.set_integer (page_name, "crop-y", page.crop_y);
            file.set_integer (page_name, "crop-width", page.crop_width);
            file.set_integer (page_name, "crop-height", page.crop_height);
        }
        file.set_value ("simple-scan", "pages", page_names);

        try
        {
            DirUtils.create_with_parents (AUTOSAVE_DIR, 0700);
            FileUtils.set_contents (AUTOSAVE_PATH, file.to_data ());
        }
        catch (Error e)
        {
            warning ("Failed to write autosave: %s", e.message);
        }
    }

    private void save_pixels (Page page)
    {
        var filename = "%u.pixels".printf (direct_hash (page));
        var path = Path.build_filename (AUTOSAVE_DIR, filename);
        page_filenames.insert (page, filename);

        debug ("Autosaving page pixels to %s", path);

        var file = File.new_for_path (path);
        try
        {
            file.replace_contents (page.get_pixels (), null, false, FileCreateFlags.NONE, null);
        }
        catch (Error e)
        {
            warning ("Failed to autosave page contents: %s", e.message);
        }
    }
}
