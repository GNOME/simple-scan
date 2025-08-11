/*
 * Copyright (C) 2009-2015 Canonical Ltd.
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

public class BookView : Gtk.Box
{
    /* Book being rendered */
    public Book book { get; private set; }
    private HashTable<Page, PageView> page_data;

    /* True if the view needs to be laid out again */
    private bool need_layout;
    private bool laying_out;
    private bool show_selected_page;
    
    /* Currently selected page */
    private PageView? selected_page_view = null;
    public Page? selected_page
    {
        get
        {
            if (selected_page_view != null)
                return selected_page_view.page;
            else
                return null;
        }
        set
        {
            if (selected_page == value)
                return;

            if (value != null)
                select_page_view (page_data.lookup (value));
            else
                select_page_view (null);
        }
    }

    /* Widget being rendered to */
    private Gtk.ScrolledWindow scrolled_window;
    private Gtk.DrawingArea drawing_area;

    private new string cursor;

    private Gtk.EventControllerMotion motion_controller;
    private Gtk.EventControllerScroll cursor_scroll_controller;
    private Gtk.EventControllerKey key_controller;
    private Gtk.GestureClick primary_click_gesture;
    private Gtk.GestureClick secondary_click_gesture;
    private Gtk.EventControllerFocus focus_controller;


    public signal void page_selected (Page? page);
    public signal void show_page (Page page);
    public signal void show_menu (Gtk.Widget from, double x, double y);

    public int x_offset { get; set; }

    public BookView (Book book)
    {
        GLib.Object (orientation: Gtk.Orientation.VERTICAL);
        this.book = book;

        /* Load existing pages */
        for (var i = 0; i < book.n_pages; i++)
        {
            Page page = book.get_page (i);
            add_cb (book, page);
        }

        selected_page = book.get_page (0);

        /* Watch for new pages */
        book.page_added.connect (add_cb);
        book.page_removed.connect (remove_cb);
        book.reordered.connect (reorder_cb);
        book.cleared.connect (clear_cb);

        need_layout = true;
        page_data = new HashTable<Page, PageView> (direct_hash, direct_equal);
        cursor = "arrow";

        drawing_area = new Gtk.DrawingArea ();
        drawing_area.set_size_request (200, 100);
        drawing_area.can_focus = true;
        drawing_area.focusable = true;
        drawing_area.vexpand = true;
        drawing_area.set_draw_func(draw_cb);

        // Use GtkScrolledWindow for automatic scrollbar management
        scrolled_window = new Gtk.ScrolledWindow();
        scrolled_window.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.NEVER); // Horizontal only
        scrolled_window.set_child(drawing_area);
        scrolled_window.hexpand = true;
        scrolled_window.vexpand = true;

        append(scrolled_window);

        drawing_area.resize.connect (drawing_area_resize_cb);

        motion_controller = new Gtk.EventControllerMotion ();
        motion_controller.motion.connect (motion_cb);
        drawing_area.add_controller(motion_controller);

        cursor_scroll_controller = new Gtk.EventControllerScroll (
            Gtk.EventControllerScrollFlags.BOTH_AXES
                | Gtk.EventControllerScrollFlags.DISCRETE
        );
        cursor_scroll_controller.scroll.connect (cursor_scroll_cb);
        drawing_area.add_controller(cursor_scroll_controller);

        key_controller = new Gtk.EventControllerKey ();
        key_controller.key_pressed.connect (key_cb);
        drawing_area.add_controller(key_controller);

        primary_click_gesture = new Gtk.GestureClick (); 
        primary_click_gesture.button = Gdk.BUTTON_PRIMARY;
        primary_click_gesture.pressed.connect (primary_pressed_cb);
        primary_click_gesture.released.connect (primary_released_cb);
        drawing_area.add_controller(primary_click_gesture);

        secondary_click_gesture = new Gtk.GestureClick (); 
        secondary_click_gesture.button = Gdk.BUTTON_SECONDARY;
        secondary_click_gesture.pressed.connect (secondary_pressed_cb);
        secondary_click_gesture.released.connect (secondary_released_cb);
        drawing_area.add_controller(secondary_click_gesture);

        focus_controller = new Gtk.EventControllerFocus ();
        focus_controller.enter.connect_after (focus_cb);
        focus_controller.leave.connect_after (focus_cb);
        drawing_area.add_controller(focus_controller);

        drawing_area.visible = true;
    }

    ~BookView ()
    {
        book.page_added.disconnect (add_cb);
        book.page_removed.disconnect (remove_cb);
        book.reordered.disconnect (reorder_cb);
        book.cleared.disconnect (clear_cb);
        drawing_area.resize.disconnect (drawing_area_resize_cb);
        motion_controller.motion.disconnect (motion_cb);
        cursor_scroll_controller.scroll.disconnect (cursor_scroll_cb);
        key_controller.key_pressed.disconnect (key_cb);
        primary_click_gesture.pressed.disconnect (primary_pressed_cb);
        primary_click_gesture.released.disconnect (primary_released_cb);
        secondary_click_gesture.pressed.disconnect (secondary_pressed_cb);
        secondary_click_gesture.released.disconnect (secondary_released_cb);
        focus_controller.enter.disconnect (focus_cb);
        focus_controller.leave.disconnect (focus_cb);
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
            if (p == page.page)
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
            if (p == page.page)
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

    private void set_selected_page_view (PageView? page)
    {
        /* Deselect existing page if changed */
        if (selected_page_view != null && page != selected_page_view)
            selected_page_view.selected = true;

        selected_page_view = page;
        redraw();
        if (selected_page_view == null)
            return;

        /* Select new page if widget has focus */
        if (!drawing_area.has_focus)
            selected_page_view.selected = false;
        else
            selected_page_view.selected = true;
    }

    private void show_page_view (PageView? page)
    {
        if (page == null)
            return;

        int allocation_width = drawing_area.get_allocated_width();
        var left_edge = page.x_offset;
        var right_edge = page.x_offset + page.width;

        if (left_edge - x_offset < 0)
            x_offset = left_edge;
        else if (right_edge - x_offset > allocation_width)
            x_offset = right_edge - allocation_width;
    }

    private void select_page_view (PageView? page)
    {
        Page? p = null;

        if (selected_page_view == page)
            return;

        set_selected_page_view (page);

        if (need_layout)
            show_selected_page = true;
        else
            show_page_view (page);

        if (page != null)
            p = page.page;
        page_selected (p);
    }

    private void remove_cb (Book book, Page page)
    {
        PageView new_selection = selected_page_view;

        /* Select previous page or next if removing the selected page */
        if (page == selected_page)
        {
            new_selection = get_prev_page (selected_page_view);
            if (new_selection == selected_page_view)
                new_selection = get_next_page (selected_page_view);
            selected_page_view = null;
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
        selected_page_view = null;
        page_selected (null);
        need_layout = true;
        redraw ();
    }

    public void drawing_area_resize_cb ()
    {
        need_layout = true;
        layout ();
    }

    private void layout_into (int width, int height, out int book_width, out int book_height)
    {
        var pages = new List<PageView> ();
        for (var i = 0; i < book.n_pages; i++)
            pages.append (get_nth_page (i));

        /* Get maximum page resolution */
        int max_dpi = 0;
        foreach (var page in pages)
        {
            var p = page.page;
            if (p.dpi > max_dpi)
                max_dpi = p.dpi;
        }

        /* Get area required to fit all pages */
        int max_width = 0, max_height = 0;
        foreach (var page in pages)
        {
            var p = page.page;
            var w = p.width;
            var h = p.height;

            /* Scale to the same DPI */
            w = (int) ((double)w * max_dpi / p.dpi + 0.5);
            h = (int) ((double)h * max_dpi / p.dpi + 0.5);

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
        foreach (var page in pages)
        {
            var p = page.page;

            /* NOTE: Using double to avoid overflow for large images */
            if (max_aspect > aspect)
            {
                /* Set width scaled on DPI and maximum width */
                int w = (int) ((double)p.width * max_dpi * width / (p.dpi * max_width));
                page.width = w;
            }
            else
            {
                /* Set height scaled on DPI and maximum height */
                int h = (int) ((double)p.height * max_dpi * height / (p.dpi * max_height));
                page.height = h;
            }

            var h = page.height;
            if (h > book_height)
                book_height = h;
            book_width += page.width + spacing;
        }
        if (pages != null)
            book_width -= spacing;

        int x_offset_local = 0;
        foreach (var page in pages)
        {
            /* Layout pages left to right */
            page.x_offset = x_offset_local;
            x_offset_local += page.width + spacing;

            /* Centre page vertically */
            page.y_offset = (height - page.height) / 2;
        }
    }

    private void layout ()
    {
        if (!need_layout)
            return;

        laying_out = true;

        int width = drawing_area.get_allocated_width();
        int height = this.get_allocated_height();

        int book_width, book_height;
        layout_into (width, height, out book_width, out book_height);

        drawing_area.set_size_request(book_width, -1);
        if (show_selected_page)
            show_page_view (selected_page_view);

        need_layout = false;
        show_selected_page = false;
        laying_out = false;
    }

    public void draw_cb (Gtk.DrawingArea drawing_area, Cairo.Context context, int width, int height)
    {
        layout ();

        double left, top, right, bottom;
        context.clip_extents (out left, out top, out right, out bottom);

        var pages = new List<PageView> ();
        for (var i = 0; i < book.n_pages; i++)
            pages.append (get_nth_page (i));

        var ruler_color = get_style_context ().get_color ();
        Gdk.RGBA ruler_color_selected = {};
        ruler_color_selected.parse("#3584e4");  /* Gnome Blue 3 */

        /* Render each page */
        foreach (var page in pages)
        {
            var left_edge = page.x_offset - x_offset;
            var right_edge = page.x_offset + page.width - x_offset;

            /* Page not visible, don't render */
            if (right_edge < left || left_edge > right)
                continue;

            context.save ();
            context.translate (-x_offset, 0);
            page.render (context, page == selected_page_view ? ruler_color_selected : ruler_color);
            context.restore ();

            if (page.selected)
                drawing_area.get_style_context ().render_focus (context,
                                                                page.x_offset - x_offset,
                                                                page.y_offset,
                                                                page.width,
                                                                page.height);
        }
    }

    private PageView? get_page_at (int x, int y, out int x_, out int y_)
    {
        x_ = y_ = 0;
        for (var i = 0; i < book.n_pages; i++)
        {
            var page = get_nth_page (i);
            var left = page.x_offset;
            var right = left + page.width;
            var top = page.y_offset;
            var bottom = top + page.height;
            if (x >= left && x <= right && y >= top && y <= bottom)
            {
                x_ = x - left;
                y_ = y - top;
                return page;
            }
        }

        return null;
    }

    private void primary_pressed_cb (Gtk.GestureClick controler, int n_press, double x, double y)
    {
        button_cb(controler, Gdk.BUTTON_PRIMARY, true, n_press, x, y);
    }

    private void primary_released_cb (Gtk.GestureClick controler, int n_press, double x, double y)
    {
        button_cb(controler, Gdk.BUTTON_PRIMARY, false, n_press, x, y);
    }

    private void secondary_pressed_cb (Gtk.GestureClick controler, int n_press, double x, double y)
    {
        button_cb(controler, Gdk.BUTTON_SECONDARY, true, n_press, x, y);
    }

    private void secondary_released_cb (Gtk.GestureClick controler, int n_press, double x, double y)
    {
        button_cb(controler, Gdk.BUTTON_SECONDARY, false, n_press, x, y);
    }

    private void button_cb (Gtk.GestureClick controler, int button, bool press, int n_press, double dx, double dy)
    {
        layout ();

        drawing_area.grab_focus ();

        int x = 0, y = 0;
        if (press)
            select_page_view (get_page_at ((int) ((int) dx + x_offset), (int) dy, out x, out y));

        if (selected_page_view == null)
            return;

        /* Modify page */
        if (button == Gdk.BUTTON_PRIMARY)
        {
            if (press)
                selected_page_view.button_press (x, y);
            else if (press && n_press == 2)
                show_page (selected_page);
            else if (!press)
                selected_page_view.button_release (x, y);
        }

        /* Show pop-up menu on right click */
        if (button == Gdk.BUTTON_SECONDARY)
            show_menu (drawing_area, dx, dy);
    }

    private new void set_cursor (string cursor)
    {
        if (this.cursor == cursor)
            return;
        this.cursor = cursor;

        Gdk.Cursor c = new Gdk.Cursor.from_name (cursor, null);
        drawing_area.set_cursor (c);
    }

    private void motion_cb (Gtk.EventControllerMotion controler, double dx, double dy)
    {
        string cursor = "arrow";
        
        int event_x = (int) dx;
        int event_y = (int) dy;
        
        var event_state = controler.get_current_event_state();

        /* Dragging */
        if (selected_page_view != null && (event_state & Gdk.ModifierType.BUTTON1_MASK) != 0)
        {
            var x = (int) (event_x + x_offset - selected_page_view.x_offset);
            var y = (int) (event_y - selected_page_view.y_offset);
            selected_page_view.motion (x, y);
            cursor = selected_page_view.cursor;
        }
        else
        {
            int x, y;
            var over_page = get_page_at ((int) (event_x + x_offset), (int) event_y, out x, out y);
            if (over_page != null)
            {
                over_page.motion (x, y);
                cursor = over_page.cursor;
            }
        }

        set_cursor (cursor);
    }

    private bool key_cb (Gtk.EventControllerKey controler, uint keyval, uint keycode, Gdk.ModifierType state)
    {
        switch (keyval)
        {
        case Gdk.Key.Home:
            selected_page = book.get_page (0);
            return true;
        case Gdk.Key.Left:
            select_page_view (get_prev_page (selected_page_view));
            return true;
        case Gdk.Key.Right:
            select_page_view (get_next_page (selected_page_view));
            return true;
        case Gdk.Key.End:
            selected_page = book.get_page ((int) book.n_pages - 1);
            return true;

        default:
            return false;
        }
    }

    private void focus_cb (Gtk.EventControllerFocus controler)
    {
        set_selected_page_view (selected_page_view);
    }

    private bool cursor_scroll_cb (Gtk.EventControllerScroll controller, double dx, double dy)
    {
        if (dx == 0 && dy == 0) {
            return false;
        }
        else if (dy >= 0 && dx >= 0) {
            // Down and/or right
            select_next_page();
        }
        else if (dy <= 0 && dx <= 0) {
            // Up and/or left
            select_prev_page();
        }
        return true;
    }

    public void redraw ()
    {
        drawing_area.queue_draw ();
    }

    public void select_next_page ()
    {
        select_page_view (get_next_page (selected_page_view));
    }

    public void select_prev_page ()
    {
        select_page_view (get_prev_page (selected_page_view));
    }
}
