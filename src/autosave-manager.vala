/*
 * Copyright (C) 2011 Timo Kluck
 * Author: Timo Kluck <tkluck@infty.nl>
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later
 * version. See http://www.gnu.org/copyleft/gpl.html the full text of the
 * license.
 */

/*
 * We store autosaves in a database named
 *    ~/.cache/simple-scan/autosaves/autosaves.db
 * It contains a single table of pages, each containing the process id (pid) of
 * the simple-scan instance that saved it, and a hash of the Book and Page
 * objects corresponding to it. The pixels are saved as a BLOB.
 * Additionally, the autosaves directory contains a number of tiff files that
 * the user can use for manual recovery.
 *
 * At startup, we check whether autosaves.db contains any records
 * with a pid that does not match a current pid for simple-scan. If so, we take
 * ownership by an UPDATE statement changing to our own pid. Then, we
 * recover the book. We're trying our best to avoid the possible race
 * condition if several instances of simple-scan are started simultaneously.
 *
 * At application exit, we delete the records corresponding to our own pid.
 *
 * Important notes:
 *  - We enforce that there is only one AutosaveManager instance in a given
 *    process by using a create function.
 *  - It should be possible to change the book object at runtime, although this
 *    is not used in the current implementation so it has not been tested.
 */

public class AutosaveManager
{
    private static string AUTOSAVE_DIR = Path.build_filename (Environment.get_user_cache_dir (), "simple-scan", "autosaves");
    private static string AUTOSAVE_NAME = "autosaves";
    private static string AUTOSAVE_EXT = ".db";
    private static string AUTOSAVE_FILENAME = Path.build_filename (AUTOSAVE_DIR, AUTOSAVE_NAME + AUTOSAVE_EXT);

    private static string PID = ((int)(Posix.getpid ())).to_string ();
    private static int number_of_instances = 0;

    private Sqlite.Database database_connection;
    private Book book_ = null;

    private uint update_timeout = 0;
    private HashTable<Page, bool> dirty_pages;

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
                for (var i = 0; i < book_.get_n_pages (); i++)
                {
                    var page = book_.get_page (i);
                    on_page_removed (page);
                }
                book_.page_added.disconnect (on_page_added);
                book_.page_removed.disconnect (on_page_removed);
                book_.reordered.disconnect (on_reordered);
                book_.cleared.disconnect (on_cleared);
            }
            book_ = value;
            book_.page_added.connect (on_page_added);
            book_.page_removed.connect (on_page_removed);
            book_.reordered.connect (on_reordered);
            book_.cleared.connect (on_cleared);
            for (var i = 0; i < book_.get_n_pages (); i++)
            {
                var page = book.get_page (i);
                on_page_added (page);
            }
        }
    }

    public static AutosaveManager? create (Book book)
    {
        /* compare autosave directories with pids of current instances of simple-scan
         * take ownership of one of the ones that are unowned by renaming to the
         * own pid. Then open the database and fill the book with the pages it
         * contains.
         */
        if (number_of_instances > 0)
            assert_not_reached ();

        var man = new AutosaveManager ();
        number_of_instances++;

        try
        {
            man.database_connection = open_database_connection ();
        }
        catch
        {
            warning ("Could not connect to the autosave database; no autosaves will be kept.");
            return null;
        }

        bool any_pages_recovered = false;
        try
        {
            // FIXME: this only works on linux. We can maybe use Gtk.Application and some session bus id instead?
            string current_pids;
            Process.spawn_command_line_sync ("pidof simple-scan | sed \"s/ /,/g\"", out current_pids);
            current_pids = current_pids.strip ();
            Sqlite.Statement stmt;
            string query = @"
                   SELECT process_id, book_hash, book_revision FROM pages
                   WHERE NOT process_id IN ($current_pids)
                   LIMIT 1
                ";

            var result = man.database_connection.prepare_v2 (query, -1, out stmt);
            if (result == Sqlite.OK)
            {
                while (stmt.step () == Sqlite.ROW)
                {
                    debug ("Found at least one autosave page, taking ownership");
                    var unowned_pid = stmt.column_int (0);
                    var book_hash = stmt.column_int (1);
                    var book_revision = stmt.column_int (2);
                    /* there's a possible race condition here when several instances
                     * try to take ownership of the same rows. What would happen is
                     * that this operations would affect no rows if another process
                     * has taken ownership in the mean time. In that case, recover_book
                     * does nothing, so there should be no problem.
                     */
                    query = @"
                        UPDATE pages
                           SET process_id = $PID
                         WHERE process_id = ?2
                           AND book_hash = ?3
                           AND book_revision = ?4";
                    Sqlite.Statement stmt2;
                    result = man.database_connection.prepare_v2 (query, -1, out stmt2);
                    if (result != Sqlite.OK)
                        warning (@"Error preparing statement: $query");

                    stmt2.bind_int64 (2, unowned_pid);
                    stmt2.bind_int64 (3, book_hash);
                    stmt2.bind_int64 (4, book_revision);
                    result = stmt2.step();
                    if (result == Sqlite.DONE)
                    {
                        any_pages_recovered = true;
                        man.recover_book (book);
                    }
                    else
                        warning ("Error %d while executing query", result);
                }
            }
            else
                warning ("Error %d while preparing statement", result);
        }
        catch (SpawnError e)
        {
            warning ("Could not obtain current process ids; not restoring any autosaves");
        }

        man.book = book;
        if (!any_pages_recovered)
        {
            for (var i = 0; i < book.get_n_pages (); i++)
            {
                var page = book.get_page (i);
                man.on_page_added (page);
            }
        }

        return man;
    }

    private AutosaveManager ()
    {
        dirty_pages = new HashTable<Page, bool> (direct_hash, direct_equal);
    }

    public void cleanup ()
    {
        debug ("Clean exit; deleting autosave records");

        if (update_timeout > 0)
            Source.remove (update_timeout);
        update_timeout = 0;

        string query = @"
        SELECT pixels_filename FROM pages
            WHERE process_id = $PID
        ";
        Sqlite.Statement stmt;
        var result = database_connection.prepare_v2 (query, -1, out stmt);
        if (result != Sqlite.OK)
            warning (@"Error $result while preparing query");
        while (stmt.step () != Sqlite.DONE)
        {
            string filename = stmt.column_text (0);
            var file = File.new_for_path (filename);
            try
            {
                file.delete (null);
            }
            catch (Error e)
            {
                warning("Failed to delete autosave file");
            }
        }

        warn_if_fail (database_connection.exec (@"
            DELETE FROM pages
                WHERE process_id = $PID
        ") == Sqlite.OK);
    }

    static Sqlite.Database open_database_connection () throws Error
    {
        var autosaves_dir = File.new_for_path (AUTOSAVE_DIR);
        try
        {
            autosaves_dir.make_directory_with_parents ();
        }
        catch
        { // the directory already exists
            // pass
        }
        Sqlite.Database connection;
        if (Sqlite.Database.open (AUTOSAVE_FILENAME, out connection) != Sqlite.OK)
            throw new IOError.FAILED ("Could not connect to autosave database");
        Sqlite.Statement stmt;
        var result = connection.prepare_v2 ("PRAGMA user_version", -1, out stmt);
        if (result != Sqlite.OK)
            warning ("Error %d while executing pragma query", result);
        while (stmt.step () != Sqlite.DONE)
        {
            var user_version = stmt.column_int (0);
            if (user_version < 1)
            {
                connection.exec("DROP TABLE pages");
                connection.exec("PRAGMA user_version = 1");
            }
        }
        string query = @"
            CREATE TABLE IF NOT EXISTS pages (
                id integer PRIMARY KEY,
                process_id integer,
                page_hash integer,
                book_hash integer,
                book_revision integer,
                page_number integer,
                dpi integer,
                width integer,
                height integer,
                depth integer,
                n_channels integer,
                rowstride integer,
                color_profile string,
                crop_x integer,
                crop_y integer,
                crop_width integer,
                crop_height integer,
                scan_direction integer,
                pixels_filename string
            )";
        result = connection.exec(query);
        if (result != Sqlite.OK)
            warning ("Error %d while executing query", result);
        return connection;
    }

    void on_page_added (Page page)
    {
        insert_page (page);
        // TODO: save a tiff file
        page.size_changed.connect (on_page_changed);
        page.scan_direction_changed.connect (on_page_changed);
        page.crop_changed.connect (on_page_changed);
        page.scan_finished.connect (on_page_changed);
        page.scan_finished.connect (on_pixels_changed);
        page.pixels_changed.connect (on_pixels_changed);
    }

    public void on_page_removed (Page page)
    {
        page.pixels_changed.disconnect (on_page_changed);
        page.size_changed.disconnect (on_page_changed);
        page.scan_direction_changed.disconnect (on_page_changed);
        page.crop_changed.disconnect (on_page_changed);
        page.scan_finished.disconnect (on_page_changed);
        page.pixels_changed.disconnect (on_pixels_changed);

        string query = @"
        SELECT pixels_filename FROM pages
            WHERE process_id = $PID
              AND page_hash = ?2
              AND book_hash = ?3
              AND book_revision = ?4
        ";
        Sqlite.Statement stmt;
        var result = database_connection.prepare_v2 (query, -1, out stmt);
        if (result != Sqlite.OK)
            warning (@"Error $result while preparing query");
        stmt.bind_int64 (2, direct_hash (page));
        stmt.bind_int64 (3, direct_hash (book));
        stmt.bind_int64 (4, cur_book_revision);
        while (stmt.step () != Sqlite.DONE)
        {
            string filename = stmt.column_text (0);
            var file = File.new_for_path (filename);
            try
            {
                file.delete (null);
            }
            catch (Error e)
            {
                warning ("Failed to delete autosave file");
            }
        }

        query = @"
        DELETE FROM pages
            WHERE process_id = $PID
              AND page_hash = ?2
              AND book_hash = ?3
              AND book_revision = ?4
        ";
        result = database_connection.prepare_v2 (query, -1, out stmt);
        if (result != Sqlite.OK)
            warning (@"Error $result while preparing query");
        stmt.bind_int64 (2, direct_hash (page));
        stmt.bind_int64 (3, direct_hash (book));
        stmt.bind_int64 (4, cur_book_revision);

        result = stmt.step();
        if (result != Sqlite.DONE)
            warning ("Error %d while executing query", result);
    }

    public void on_reordered ()
    {
        for (var i=0; i < book.get_n_pages (); i++)
        {
            var page = book.get_page (i);
            string query = @"
            UPDATE pages SET page_number = ?5
            WHERE process_id = $PID
              AND page_hash = ?2
              AND book_hash = ?3
              AND book_revision = ?4
            ";
            Sqlite.Statement stmt;
            var result = database_connection.prepare_v2 (query, -1, out stmt);
            if (result != Sqlite.OK)
                warning (@"Error $result while preparing query");

            stmt.bind_int64 (5, i);
            stmt.bind_int64 (2, direct_hash (page));
            stmt.bind_int64 (3, direct_hash (book));
            stmt.bind_int64 (4, cur_book_revision);

            result = stmt.step();
            if (result != Sqlite.DONE)
                warning ("Error %d while executing query", result);
        }
    }

    public void on_page_changed (Page page)
    {
        update_page (page);
    }

    public void on_pixels_changed (Page page)
    {
        if (!page.is_scanning)
            update_page_pixels (page);
    }

    public void on_needs_saving_changed (Book book)
    {
        for (var n = 0; n < book.get_n_pages (); n++)
        {
            var page = book.get_page (n);
            update_page (page);
        }
    }

    private int cur_book_revision = 0;

    public void on_cleared ()
    {
        cur_book_revision++;
    }

    private void insert_page (Page page)
    {
        debug ("Adding an autosave for a new page");
        string query = @"
            INSERT INTO pages
                (process_id,
                page_hash,
                book_hash,
                book_revision)
                VALUES
                ($PID,
                ?2,
                ?3,
                ?4)
        ";
        Sqlite.Statement stmt;
        var result = database_connection.prepare_v2 (query, -1, out stmt);
        if (result != Sqlite.OK)
            warning (@"Error $result while preparing query");

        stmt.bind_int64 (2, direct_hash (page));
        stmt.bind_int64 (3, direct_hash (book));
        stmt.bind_int64 (4, cur_book_revision);

        result = stmt.step();
        if (result != Sqlite.DONE)
            warning ("Error %d while executing query", result);

        update_page (page);
        update_page_pixels (page);
    }

    private void update_page (Page page)
    {
        dirty_pages.insert (page, true);
        if (update_timeout > 0)
            Source.remove (update_timeout);
        update_timeout = Timeout.add (100, () =>
        {
            var iter = HashTableIter<Page, bool> (dirty_pages);
            Page p;
            bool is_dirty;
            while (iter.next (out p, out is_dirty))
                real_update_page (p);

            dirty_pages.remove_all ();
            update_timeout = 0;

            return false;
        });
    }

    private void real_update_page (Page page)
    {
        debug ("Updating the autosave for a page");

        Sqlite.Statement stmt;
        string query = @"
            UPDATE pages
                SET
                page_number=$(book.get_page_index (page)),
                dpi=$(page.dpi),
                width=$(page.width),
                height=$(page.height),
                depth=$(page.depth),
                n_channels=$(page.n_channels),
                rowstride=$(page.rowstride),
                crop_x=$(page.crop_x),
                crop_y=$(page.crop_y),
                crop_width=$(page.crop_width),
                crop_height=$(page.crop_height),
                scan_direction=$((int)page.scan_direction),
                color_profile=?1
                WHERE process_id = $PID
                  AND page_hash = ?4
                  AND book_hash = ?5
                  AND book_revision = ?6
            ";

        var result = database_connection.prepare_v2 (query, -1, out stmt);
        if (result != Sqlite.OK)
        {
            warning ("Error %d while preparing statement", result);
            return;
        }

        stmt.bind_int64 (4, direct_hash (page));
        stmt.bind_int64 (5, direct_hash (book));
        stmt.bind_int64 (6, cur_book_revision);
        result = stmt.bind_text (1, page.color_profile ?? "");

        if (result != Sqlite.OK)
            warning ("Error %d while binding text", result);

        warn_if_fail (stmt.step () == Sqlite.DONE);
    }
    
    private void update_page_pixels (Page page)
    {
        debug ("Updating the pixels in the autosave for a page");

        string basename = @"$cur_book_revision-$(direct_hash (book))-$(direct_hash (page)).bin";
        string filename = Path.build_filename (AUTOSAVE_DIR, basename);
        var file = File.new_for_path (filename);
        try
        {
            file.replace_contents (page.get_pixels (), null, false, 0, null, null);
        }
        catch (Error e)
        {
            warning ("Error while saving autosave pixel data");
        }
        Sqlite.Statement stmt;
        string query = @"
            UPDATE pages
                SET
                pixels_filename=?1
                WHERE process_id = $PID
                  AND page_hash = ?2
                  AND book_hash = ?3
                  AND book_revision = ?4
            ";

        var result = database_connection.prepare_v2 (query, -1, out stmt);
        if (result != Sqlite.OK)
        {
            warning ("Error %d while preparing statement", result);
            return;
        }

        stmt.bind_int64 (2, direct_hash (page));
        stmt.bind_int64 (3, direct_hash (book));
        stmt.bind_int64 (4, cur_book_revision);

        result = stmt.bind_text (1, filename);
        if (result != Sqlite.OK)
            warning ("Error %d while binding string", result);

        warn_if_fail (stmt.step () == Sqlite.DONE);
    }

    private void recover_book (Book book)
    {
        Sqlite.Statement stmt;
        string query = @"
            SELECT process_id,
                page_hash,
                book_hash,
                book_revision,
                page_number,
                dpi,
                width,
                height,
                depth,
                n_channels,
                rowstride,
                color_profile,
                crop_x,
                crop_y,
                crop_width,
                crop_height,
                scan_direction,
                pixels_filename,
                id
            FROM pages
            WHERE process_id = $PID
              AND book_revision = (
                  SELECT MAX(book_revision) FROM pages WHERE process_id = $PID
              )
            ORDER BY page_number
        ";

        var result = database_connection.prepare_v2 (query, -1, out stmt);
        if (result != Sqlite.OK)
            warning ("Error %d while preparing statement", result);

        var first = true;
        while (Sqlite.ROW == stmt.step ())
        {
            debug ("Found a page that needs to be recovered");
            if (first)
            {
                book.clear ();
                first = false;
            }
            var dpi = stmt.column_int (5);
            var width = stmt.column_int (6);
            var height = stmt.column_int (7);
            var depth = stmt.column_int (8);
            var n_channels = stmt.column_int (9);
            var scan_direction = (ScanDirection)stmt.column_int (16);

            if (width <= 0 || height <= 0)
                continue;

            debug (@"Restoring a page of size $(width) x $(height)");
            var new_page = book.append_page (width, height, dpi, scan_direction);

            if (depth > 0 && n_channels > 0)
            {
                var info = new ScanPageInfo ();
                info.width = width;
                info.height = height;
                info.depth = depth;
                info.n_channels = n_channels;
                info.dpi = dpi;
                info.device = "";
                new_page.set_page_info (info);
            }

            new_page.color_profile = stmt.column_text (11);
            var crop_x = stmt.column_int (12);
            var crop_y = stmt.column_int (13);
            var crop_width = stmt.column_int (14);
            var crop_height = stmt.column_int (15);
            if (crop_width > 0 && crop_height > 0)
            {
                new_page.set_custom_crop (crop_width, crop_height);
                new_page.move_crop (crop_x, crop_y);
            }

            var file = File.new_for_path (stmt.column_text (17));
            uchar[] new_pixels;
            try
            {
                file.load_contents (null, out new_pixels, null);
            }
            catch (Error e)
            {
                warning ("Error while loading pixel data");
            }
            new_page.set_pixels (new_pixels);

            var id = stmt.column_int (18);
            debug ("Updating autosave to point to our new copy of the page");
            query = @"
                UPDATE pages
                   SET page_hash=?1,
                       book_hash=?2,
                       book_revision=?3
                WHERE id = $id
            ";

            Sqlite.Statement stmt2;
            var result2 = database_connection.prepare_v2 (query, -1, out stmt2);
            if (result2 != Sqlite.OK)
                warning (@"Error $result2 while preparing query");
            stmt2.bind_int64 (1, direct_hash (new_page));
            stmt2.bind_int64 (2, direct_hash (book));
            stmt2.bind_int64 (3, cur_book_revision);

            result2 = stmt2.step ();
            if (result2 != Sqlite.DONE)
                warning ("Error %d while executing query", result);
        }

        if (first)
            debug ("No pages found to recover");
    }
}
