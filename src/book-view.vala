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

// FIXME: When scrolling, copy existing render sideways?
// FIXME: Only render pages that change and only the part that changed

public class BookView : Gtk.VBox
{
    /* Book being rendered */
    private Book book;
    private HashTable<Page, PageView> page_data;

    /* True if the view needs to be laid out again */
    private bool need_layout;
    private bool laying_out;
    private bool show_selected_page;

    /* Currently selected page */
    private PageView? selected_page = null;

    /* Widget being rendered to */
    private Gtk.Widget drawing_area;

    /* Horizontal scrollbar */
    private Gtk.Scrollbar scroll;
    private Gtk.Adjustment adjustment;

    private Gdk.CursorType cursor;

    public signal void page_selected (Page? page);
    public signal void show_page (Page page);
    public signal void show_menu ();

    public BookView (Book book)
    {
        this.book = book;

        /* Load existing pages */
        for (var i = 0; i < book.get_n_pages (); i++)
        {
            Page page = book.get_page (i);
            add_cb (book, page);
        }

        select_page (book.get_page (0));

        /* Watch for new pages */
        book.page_added.connect (add_cb);
        book.page_removed.connect (remove_cb);
        book.reordered.connect (reorder_cb);
        book.cleared.connect (clear_cb);

        need_layout = true;
        page_data = new HashTable<Page, PageView> (direct_hash, direct_equal);
        cursor = Gdk.CursorType.ARROW;

        drawing_area = new Gtk.DrawingArea ();
        drawing_area.set_size_request (200, 100);
        drawing_area.set_can_focus (true);
        drawing_area.set_events (Gdk.EventMask.POINTER_MOTION_MASK | Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.BUTTON_RELEASE_MASK | Gdk.EventMask.FOCUS_CHANGE_MASK | Gdk.EventMask.STRUCTURE_MASK | Gdk.EventMask.SCROLL_MASK);
        pack_start (drawing_area, true, true, 0);

        scroll = new Gtk.Scrollbar (Gtk.Orientation.HORIZONTAL, null);
        adjustment = scroll.get_adjustment ();
        pack_start (scroll, false, true, 0);

        drawing_area.configure_event.connect (configure_cb);
        drawing_area.draw.connect (draw_cb);
        drawing_area.motion_notify_event.connect (motion_cb);
        drawing_area.key_press_event.connect (key_cb);
        drawing_area.button_press_event.connect (button_cb);
        drawing_area.button_release_event.connect (button_cb);
        drawing_area.focus_in_event.connect_after (focus_cb);
        drawing_area.focus_out_event.connect_after (focus_cb);
        adjustment.value_changed.connect (scroll_cb);

        drawing_area.show ();
    }

    ~BookView ()
    {
        book.page_added.disconnect (add_cb);
        book.page_removed.disconnect (remove_cb);
        book.reordered.disconnect (reorder_cb);
        book.cleared.disconnect (clear_cb);
        drawing_area.configure_event.disconnect (configure_cb);
        drawing_area.draw.disconnect (draw_cb);
        drawing_area.motion_notify_event.disconnect (motion_cb);
        drawing_area.key_press_event.disconnect (key_cb);
        drawing_area.button_press_event.disconnect (button_cb);
        drawing_area.button_release_event.disconnect (button_cb);
        drawing_area.focus_in_event.disconnect (focus_cb);
        drawing_area.focus_out_event.disconnect (focus_cb);
        adjustment.value_changed.disconnect (scroll_cb);
    }

    private PageView get_nth_page (int n)
    {
        Page page = book.get_page (n);
        return page_data.lookup (page);
    }

    private PageView get_next_page (PageView page)
    {
        for (var i = 0; ; i++)
        {
            var p = book.get_page (i);
            if (p == null)
                break;
            if (p == page.get_page ())
            {
                p = book.get_page (i + 1);
                if (p != null)
                    return page_data.lookup (p);
            }
        }

        return page;
    }

    private PageView get_prev_page (PageView page)
    {
        var prev_page = page;
        for (var i = 0; ; i++)
        {
            var p = book.get_page (i);
            if (p == null)
                break;
            if (p == page.get_page ())
                return prev_page;
            prev_page = page_data.lookup (p);
        }

        return page;
    }

    private void page_view_changed_cb (PageView page)
    {
        redraw ();
    }

    private void page_view_size_changed_cb (PageView page)
    {
        need_layout = true;
        redraw ();
    }

    private void add_cb (Book book, Page page)
    {
        var page_view = new PageView (page);
        page_view.changed.connect (page_view_changed_cb);
        page_view.size_changed.connect (page_view_size_changed_cb);
        page_data.insert (page, page_view);
        need_layout = true;
        redraw ();
    }

    private void set_selected_page (PageView? page)
    {
        /* Deselect existing page if changed */
        if (selected_page != null && page != selected_page)
            selected_page.set_selected (false);

        selected_page = page;
        if (selected_page == null)
            return;

        /* Select new page if widget has focus */
        if (!drawing_area.has_focus)
            selected_page.set_selected (false);
        else
            selected_page.set_selected (true);
    }

    private void set_x_offset (int offset)
    {
        adjustment.set_value (offset);
    }

    private int get_x_offset ()
    {
        return (int) adjustment.get_value ();
    }

    private void show_page_view (PageView? page)
    {
        if (page == null || !scroll.get_visible ())
            return;

        Gtk.Allocation allocation;
        drawing_area.get_allocation (out allocation);
        var left_edge = page.get_x_offset ();
        var right_edge = page.get_x_offset () + page.get_width ();

        if (left_edge - get_x_offset () < 0)
            set_x_offset (left_edge);
        else if (right_edge - get_x_offset () > allocation.width)
            set_x_offset (right_edge - allocation.width);
    }

    private void select_page_view (PageView? page)
    {
        Page? p = null;

        if (selected_page == page)
            return;

        set_selected_page (page);

        if (need_layout)
            show_selected_page = true;
        else
            show_page_view (page);

        if (page != null)
            p = page.get_page ();
        page_selected (p);
    }

    private void remove_cb (Book book, Page page)
    {
        PageView new_selection = selected_page;

        /* Select previous page or next if removing the selected page */
        if (page == get_selected ())
        {
            new_selection = get_prev_page (selected_page);
            if (new_selection == selected_page)
                new_selection = get_next_page (selected_page);
            selected_page = null;
        }

        var page_view = page_data.lookup (page);
        page_view.changed.disconnect (page_view_changed_cb);
        page_view.size_changed.disconnect (page_view_size_changed_cb);
        page_data.remove (page);

        select_page_view (new_selection);

        need_layout = true;
        redraw ();
    }

    private void reorder_cb (Book book)
    {
        need_layout = true;
        redraw ();
    }

    private void clear_cb (Book book)
    {
        page_data.remove_all ();
        selected_page = null;
        page_selected (null);
        need_layout = true;
        redraw ();
    }

    public Book get_book ()
    {
        return book;
    }

    private bool configure_cb (Gtk.Widget widget, Gdk.EventConfigure event)
    {
        need_layout = true;
        return false;
    }

    private void layout_into (int width, int height, out int book_width, out int book_height)
    {
        /* Get maximum page resolution */
        int max_dpi = 0;
        for (var i = 0; i < book.get_n_pages (); i++)
        {
            var page = book.get_page (i);
            if (page.get_dpi () > max_dpi)
                max_dpi = page.get_dpi ();
        }

        /* Get area required to fit all pages */
        int max_width = 0, max_height = 0;
        for (var i = 0; i < book.get_n_pages (); i++)
        {
            var page = book.get_page (i);
            var w = page.get_width ();
            var h = page.get_height ();

            /* Scale to the same DPI */
            w = (int) ((double)w * max_dpi / page.get_dpi () + 0.5);
            h = (int) ((double)h * max_dpi / page.get_dpi () + 0.5);

            if (w > max_width)
                max_width = w;
            if (h > max_height)
                max_height = h;
        }

        var aspect = (double)width / height;
        var max_aspect = (double)max_width / max_height;

        /* Get total dimensions of all pages */
        int spacing = 12;
        book_width = 0;
        book_height = 0;
        for (var i = 0; i < book.get_n_pages (); i++)
        {
            var page = get_nth_page (i);
            var p = page.get_page ();

            /* NOTE: Using double to avoid overflow for large images */
            if (max_aspect > aspect)
            {
                /* Set width scaled on DPI and maximum width */
                int w = (int) ((double)p.get_width () * max_dpi * width / (p.get_dpi () * max_width));
                page.set_width (w);
            }
            else
            {
                /* Set height scaled on DPI and maximum height */
                int h = (int) ((double)p.get_height () * max_dpi * height / (p.get_dpi () * max_height));
                page.set_height (h);
            }

            var h = page.get_height ();
            if (h > book_height)
                book_height = h;
            book_width += page.get_width ();
            if (i != 0)
                book_width += spacing;
        }

        int x_offset = 0;
        for (var i = 0; i < book.get_n_pages (); i++)
        {
            var page = get_nth_page (i);

            /* Layout pages left to right */
            page.set_x_offset (x_offset);
            x_offset += page.get_width () + spacing;

            /* Centre page vertically */
            page.set_y_offset ((height - page.get_height ()) / 2);
        }
    }

    private void layout ()
    {
        if (!need_layout)
            return;

        laying_out = true;

        Gtk.Allocation allocation;
        drawing_area.get_allocation(out allocation);
        Gtk.Allocation box_allocation;
        get_allocation(out box_allocation);

        /* If scroll is right aligned then keep that after layout */
        bool right_aligned = true;
        if (adjustment.get_value () < adjustment.get_upper () - adjustment.get_page_size ())
            right_aligned = false;

        /* Try and fit without scrollbar */
        var width = (int) allocation.width;
        var height = (int) (box_allocation.height - get_border_width () * 2);
        int book_width, book_height;
        layout_into (width, height, out book_width, out book_height);

        /* Relayout with scrollbar */
        if (book_width > allocation.width)
        {
            /* Re-layout leaving space for scrollbar */
            height = allocation.height;
            layout_into (width, height, out book_width, out book_height);

            /* Set scrollbar limits */
            adjustment.set_lower (0);
            adjustment.set_upper (book_width);
            adjustment.set_page_size (allocation.width);

            /* Keep right-aligned */
            var max_offset = book_width - allocation.width;
            if (right_aligned || get_x_offset () > max_offset)
                set_x_offset(max_offset);

            scroll.show ();
        }
        else
        {
            scroll.hide ();
            var offset = (book_width - allocation.width) / 2;
            adjustment.set_lower (offset);
            adjustment.set_upper (offset);
            adjustment.set_page_size (0);
            set_x_offset (offset);
        }

        if (show_selected_page)
           show_page_view (selected_page);

        need_layout = false;
        show_selected_page = false;
        laying_out = false;
    }

    private bool draw_cb (Gtk.Widget widget, Cairo.Context context)
    {
        if (book.get_n_pages () == 0)
            return false;

        layout ();

        double left, top, right, bottom;
        context.clip_extents (out left, out top, out right, out bottom);

        /* Render each page */
        for (var i = 0; i < book.get_n_pages (); i++)
        {
            var page = get_nth_page (i);
            var left_edge = page.get_x_offset () - get_x_offset ();
            var right_edge = page.get_x_offset () + page.get_width () - get_x_offset ();

            /* Page not visible, don't render */
            if (right_edge < left || left_edge > right)
                continue;

            context.save ();
            context.translate (-get_x_offset (), 0);
            page.render (context);
            context.restore ();

            if (page.get_selected ())
                drawing_area.get_style_context ().render_focus (context,
                                                                page.get_x_offset () - get_x_offset (),
                                                                page.get_y_offset (),
                                                                page.get_width (),
                                                                page.get_height ());
        }

        return false;
    }

    private PageView? get_page_at (int x, int y, out int x_, out int y_)
    {
        x_ = y_ = 0;
        for (var i = 0; i < book.get_n_pages (); i++)
        {
            var page = get_nth_page (i);
            var left = page.get_x_offset ();
            var right = left + page.get_width ();
            var top = page.get_y_offset ();
            var bottom = top + page.get_height ();
            if (x >= left && x <= right && y >= top && y <= bottom)
            {
                x_ = x - left;
                y_ = y - top;
                return page;
            }
        }

        return null;
    }

    private bool button_cb (Gtk.Widget widget, Gdk.EventButton event)
    {
        layout ();

        drawing_area.grab_focus ();

        int x = 0, y = 0;
        if (event.type == Gdk.EventType.BUTTON_PRESS)
            select_page_view (get_page_at ((int) (event.x + get_x_offset ()), (int) event.y, out x, out y));

        if (selected_page == null)
            return false;

        /* Modify page */
        if (event.button == 1)
        {
            if (event.type == Gdk.EventType.BUTTON_PRESS)
                selected_page.button_press (x, y);
            else if (event.type == Gdk.EventType.BUTTON_RELEASE)
                selected_page.button_release (x, y);
            else if (event.type == Gdk.EventType.2BUTTON_PRESS)
                show_page (get_selected ());
        }

        /* Show pop-up menu on right click */
        if (event.button == 3)
            show_menu ();

        return false;
    }

    private void set_cursor (Gdk.CursorType cursor)
    {
        Gdk.Cursor c;

        if (this.cursor == cursor)
            return;
        this.cursor = cursor;

        c = new Gdk.Cursor (cursor);
        drawing_area.get_window ().set_cursor (c);
    }

    private bool motion_cb (Gtk.Widget widget, Gdk.EventMotion event)
    {
        Gdk.CursorType cursor = Gdk.CursorType.ARROW;

        /* Dragging */
        if (selected_page != null && (event.state & Gdk.ModifierType.BUTTON1_MASK) != 0)
        {
            var x = (int) (event.x + get_x_offset () - selected_page.get_x_offset ());
            var y = (int) (event.y - selected_page.get_y_offset ());
            selected_page.motion (x, y);
            cursor = selected_page.get_cursor ();
        }
        else
        {
            int x, y;
            var over_page = get_page_at ((int) (event.x + get_x_offset ()), (int) event.y, out x, out y);
            if (over_page != null)
            {
                over_page.motion (x, y);
                cursor = over_page.get_cursor ();
            }
        }

        set_cursor (cursor);

        return false;
    }

    private bool key_cb (Gtk.Widget widget, Gdk.EventKey event)
    {
        switch (event.keyval)
        {
        case 0xff50: /* FIXME: GDK_Home */
            select_page (book.get_page (0));
            return true;
        case 0xff51: /* FIXME: GDK_Left */
            select_page_view (get_prev_page (selected_page));
            return true;
        case 0xff53: /* FIXME: GDK_Right */
            select_page_view (get_next_page (selected_page));
            return true;
        case 0xFF57: /* FIXME: GDK_End */
            select_page (book.get_page ((int) book.get_n_pages () - 1));
            return true;

        default:
            return false;
        }
    }

    private bool focus_cb (Gtk.Widget widget, Gdk.EventFocus event)
    {
        set_selected_page (selected_page);
        return false;
    }

    private void scroll_cb (Gtk.Adjustment adjustment)
    {
       if (!laying_out)
           redraw ();
    }

    public void redraw ()
    {
        drawing_area.queue_draw ();
    }

    public void select_page (Page? page)
    {
        if (get_selected () == page)
            return;

        if (page != null)
            select_page_view (page_data.lookup (page));
        else
            select_page_view (null);
    }

    public void select_next_page ()
    {
        select_page_view (get_next_page (selected_page));
    }

    public void select_prev_page ()
    {
        select_page_view (get_prev_page (selected_page));
    }

    public Page? get_selected ()
    {
        if (selected_page != null)
            return selected_page.get_page ();
        else
            return null;
    }
}
