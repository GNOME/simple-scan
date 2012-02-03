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
    private Book _book = null;

    public Book book
    {
        get
        {
            return _book;
        }
        set
        {
            if (_book != null)
            {
                for (var i = 0; i < _book.get_n_pages (); i++)
                {
                    var page = _book.get_page (i);
                    on_page_removed (page);
                }
                _book.page_added.disconnect (on_page_added);
                _book.page_removed.disconnect (on_page_removed);
                _book.reordered.disconnect (on_reordered);
                _book.cleared.disconnect (on_cleared);
            }
            _book = value;
            _book.page_added.connect (on_page_added);
            _book.page_removed.connect (on_page_removed);
            _book.reordered.connect (on_reordered);
            _book.cleared.connect (on_cleared);
        }
    }

    public static AutosaveManager? create (ref Book book)
    {
        /* compare autosave directories with pids of current instances of simple-scan
         * take ownership of one of the ones that are unowned by renaming to the
         * own pid. Then open the database and fill the book with the pages it
         * contains.
         */
        if (number_of_instances > 0)
        {
            assert_not_reached ();
        }

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

        try
        {
            // FIXME: this only works on linux
            string current_pids;
            Process.spawn_command_line_sync ("pidof simple-scan | sed \"s/ /,/g\"", out current_pids);
            current_pids = current_pids.strip ();
            Sqlite.Statement stmt;
            if(Sqlite.OK == man.database_connection.prepare_v2 (@"
                   SELECT process_id, book_hash, book_revision FROM pages
                   WHERE NOT process_id IN ($current_pids)
                   LIMIT 1
                ", -1, out stmt))
            {
                while (Sqlite.ROW == stmt.step ())
                {
                    var unowned_pid = stmt.column_int (0);
                    var book_hash = stmt.column_int (1);
                    var book_revision = stmt.column_int (2);
                    /* there's a possible race condition here when several instances
                     * try to take ownership of the same rows. What would happen is
                     * that this operations would affect no rows if another process
                     * has taken ownership in the mean time. In that case, recover_book
                     * does nothing, so there should be no problem.
                     */            
                    if (Sqlite.OK == man.database_connection.exec (@"
                        UPDATE pages
                           SET process_id = $PID
                         WHERE process_id = $unowned_pid
                           AND book_hash = $book_hash
                           AND book_revision = $book_revision"))
                    {
                        man.recover_book (ref book);
                    }
                    else
                    {
                        warn_if_reached ();
                    }
                }
            }
            else
            {
                warn_if_reached ();
            }
        }
        catch (SpawnError e)
        {
            warning ("Could not obtain current process ids; not restoring any autosaves");
        }

        man.book = book;
        /* FIXME: we would like to connect to a scan_fished signal on a page,
         * but it does not exist. Updating the database every time a scanline
         * has changed is much to slow. We choose to update the database every
         * now and then, instead.
         * FIXME: this takes a reference on man, so it will never be destroyed.
         */
        GLib.Timeout.add_seconds (3, man.on_update_all_pages);

        return man;
    }

    private AutosaveManager ()
    {
    }

    public void cleanup () {
        // delete autosave records
        warn_if_fail (Sqlite.OK == database_connection.exec (@"
            DELETE FROM pages
                WHERE process_id = $PID
        "));
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
        if (Sqlite.OK != Sqlite.Database.open (AUTOSAVE_FILENAME, out connection))
        {
            throw new IOError.FAILED ("Could not connect to autosave database");
        }
        warn_if_fail (Sqlite.OK == connection.exec (@"
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
                pixels binary
            )"));
        return connection;
    }

    void on_page_added (Page page)
    {
        insert_page (page);
        // TODO: save a tiff file
        page.size_changed.connect (on_page_changed);
        page.scan_line_changed.connect (on_page_changed);
        page.scan_direction_changed.connect (on_page_changed);
        page.crop_changed.connect (on_page_changed);
    }
    
    public void on_page_removed (Page page)
    {
        page.pixels_changed.disconnect (on_page_changed);
        page.size_changed.disconnect (on_page_changed);
        page.scan_line_changed.disconnect (on_page_changed);
        page.scan_direction_changed.disconnect (on_page_changed);
        page.crop_changed.disconnect (on_page_changed);

        warn_if_fail (Sqlite.OK == database_connection.exec (@"
            DELETE FROM pages
                WHERE process_id = $PID
                  AND page_hash = $(direct_hash (page))
                  AND book_hash = $(direct_hash (book))
                  AND book_revision = $cur_book_revision
            "));
    }
    
    public void on_reordered ()
    {
        for (var i=0; i < book.get_n_pages (); i++)
        {
            var page = book.get_page (i);
            warn_if_fail (Sqlite.OK == database_connection.exec (@"
                UPDATE pages SET page_number = $i
                WHERE process_id = $PID
                  AND page_hash = $(direct_hash (page))
                  AND book_hash = $(direct_hash (book))
                  AND book_revision = $cur_book_revision
                "));
        }    
    }

    public void on_page_changed (Page page)
    {
        /* we don't update the database as it is to slow to do so each time
         * a scan line is received.
         */
        //update_page (page);
    }

    public void on_needs_saving_changed (Book book)
    {
        for (int n = 0; n < book.get_n_pages (); n++)
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
        warn_if_fail (Sqlite.OK == database_connection.exec (@"
            INSERT INTO pages
                (process_id,
                page_hash,
                book_hash,
                book_revision)
                VALUES
                ($PID,
                $(direct_hash (page)),
                $(direct_hash (book)),
                $cur_book_revision)
        "));
        update_page (page);     
    }

    private bool on_update_all_pages ()
    {
        for (int n = 0; n < book.get_n_pages (); n++)
        {
            var page = book.get_page (n);
            update_page (page);
        }
        return true;
    }

    private void update_page (Page page)
    {
        int crop_x;
        int crop_y;
        int crop_width;
        int crop_height;
        page.get_crop (out crop_x, out crop_y, out crop_width, out crop_height);
        Sqlite.Statement stmt;
        return_if_fail (Sqlite.OK == database_connection.prepare_v2 (@"
            UPDATE pages
                SET
                page_number=$(book.get_page_index (page)),
                dpi=$(page.get_dpi ()),
                width=$(page.get_width ()),
                height=$(page.get_height ()),
                depth=$(page.get_depth ()),
                n_channels=$(page.get_n_channels ()),
                rowstride=$(page.get_rowstride ()),
                crop_x=$crop_x,
                crop_y=$crop_y,
                crop_width=$crop_width,
                crop_height=$crop_height,
                scan_direction=$((int)page.get_scan_direction ()),
                color_profile=?1,
                pixels=?2
                WHERE process_id = $PID
                  AND page_hash = $(direct_hash (page))
                  AND book_hash = $(direct_hash (book))
                  AND book_revision = $cur_book_revision
            ", -1, out stmt));
        warn_if_fail (Sqlite.OK == stmt.bind_text (1, page.get_color_profile () ?? ""));
        if (page.get_pixels () != null)
        {
            // (-1) is the special value SQLITE_TRANSIENT
            warn_if_fail (Sqlite.OK == stmt.bind_blob (2, page.get_pixels (), page.get_pixels ().length, (DestroyNotify)(-1)));
        }
        else
        {
            warn_if_fail (Sqlite.OK == stmt.bind_null (2));
        }

        warn_if_fail (Sqlite.DONE == stmt.step ());
    }

    private void recover_book (ref Book book)
    {
        Sqlite.Statement stmt;
        return_if_fail (Sqlite.OK == database_connection.prepare_v2 (@"
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
                pixels,
                id
            FROM pages
            WHERE process_id = $PID
              AND book_revision = (
                  SELECT MAX(book_revision) WHERE process_id = $PID
              )
            ORDER BY page_number
        ", -1, out stmt));
        bool first = true;
        while (Sqlite.ROW == stmt.step ())
        {
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
            {
                continue;
            }
            
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

            new_page.set_color_profile (stmt.column_text (11));
            var crop_x = stmt.column_int (12);
            var crop_y = stmt.column_int (13);
            var crop_width = stmt.column_int (14);
            var crop_height = stmt.column_int (15);
            if (crop_width > 0 && crop_height > 0) 
            {
                new_page.set_custom_crop (crop_width, crop_height);
                new_page.move_crop (crop_x, crop_y);
            }

            uchar[] new_pixels = new uchar[stmt.column_bytes (17)];
            Memory.copy (new_pixels, stmt.column_blob (17), stmt.column_bytes (17));
            new_page.set_pixels (new_pixels);

            var id = stmt.column_int (18);
            warn_if_fail (Sqlite.OK == database_connection.exec (@"
                UPDATE pages
                   SET page_hash=$(direct_hash (new_page)),
                       book_hash=$(direct_hash (book)),
                       book_revision=$cur_book_revision
                WHERE id = $id
            "));
        }
    }
}
