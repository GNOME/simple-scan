/*
 * Copyright (C) 2009 Canonical Ltd.
 * Author: Robert Ancell <robert.ancell@canonical.com>
 * 
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later
 * version. See http://www.gnu.org/copyleft/gpl.html the full text of the
 * license.
 */

#include <gdk/gdkkeysyms.h>

#include "book-view.h"
#include "page-view.h"

// FIXME: When scrolling, copy existing render sideways?
// FIXME: Only render pages that change and only the part that changed

enum {
    PAGE_SELECTED,
    LAST_SIGNAL
};
static guint signals[LAST_SIGNAL] = { 0, };

struct BookViewPrivate
{
    /* Book being rendered */
    Book *book;
    GHashTable *page_data;
    
    /* True if the view needs to be laid out again */
    gboolean need_layout;

    /* Amount to offset view by (pixels) */
    gint x_offset;

    PageView *selected_page;
  
    /* Widget being rendered to */
    GtkWidget *widget;

    GtkWidget *box, *scroll;
    GtkAdjustment *adjustment;

    GtkWidget *page_menu;

    gint cursor;
};

G_DEFINE_TYPE (BookView, book_view, G_TYPE_OBJECT);


BookView *
book_view_new ()
{
    return g_object_new (BOOK_VIEW_TYPE, NULL);
}


static PageView *
get_nth_page (BookView *view, gint n)
{
    Page *page = book_get_page (view->priv->book, n);
    return g_hash_table_lookup (view->priv->page_data, page);
}


static PageView *
get_next_page (BookView *view)
{
    gint i;
    
    for (i = 0; ; i++) {
        Page *page;
        page = book_get_page (view->priv->book, i);
        if (!page)
            break;
        if (page == book_view_get_selected (view)) {
            page = book_get_page (view->priv->book, i + 1);
            if (page)
                return g_hash_table_lookup (view->priv->page_data, page);
        }
    }
    
    return view->priv->selected_page;
}


static PageView *
get_prev_page (BookView *view)
{
    gint i;
    PageView *prev_page = view->priv->selected_page;

    for (i = 0; ; i++) {
        Page *page;
        page = book_get_page (view->priv->book, i);
        if (!page)
            break;
        if (page == book_view_get_selected (view))
            return prev_page;
        prev_page = g_hash_table_lookup (view->priv->page_data, page);
    }

    return prev_page;
}


static void
page_view_changed_cb (PageView *page, BookView *view)
{
    // FIXME: Only layout if have changed dimensions
    // FIXME: Only redraw pages that need it
    view->priv->need_layout = TRUE;
    book_view_redraw (view);
}


static void
add_cb (Book *book, Page *page, BookView *view)
{
    PageView *page_view;
    page_view = page_view_new ();
    page_view_set_page (page_view, page);
    g_signal_connect (page_view, "changed", G_CALLBACK (page_view_changed_cb), view);
    g_hash_table_insert (view->priv->page_data, page, page_view);
    view->priv->need_layout = TRUE;
    book_view_redraw (view);
}


static void
update_page_focus (BookView *view)
{
    if (!view->priv->selected_page)
        return;

    if (!gtk_widget_has_focus (view->priv->widget))
        page_view_set_selected (view->priv->selected_page, FALSE);
    else
        page_view_set_selected (view->priv->selected_page, TRUE);
}


static void
select_page (BookView *view, PageView *page)
{
    Page *p = NULL;
  
    if (view->priv->selected_page == page)
        return;

    /* Deselect existing page */
    if (view->priv->selected_page)
        page_view_set_selected (view->priv->selected_page, FALSE);

    view->priv->selected_page = page;

    update_page_focus (view);

    /* Re-layout to make selected page visible */
    // FIXME: Shouldn't need a full layout */
    view->priv->need_layout = TRUE;
    book_view_redraw (view);

    if (page)
        p = page_view_get_page (page);
    g_signal_emit (view, signals[PAGE_SELECTED], 0, p);
}


static void
remove_cb (Book *book, Page *page, BookView *view)
{
    PageView *new_selection = view->priv->selected_page;

    /* Select previous page or next if removing the first page */
    if (page == book_view_get_selected (view)) {
        new_selection = get_prev_page (view);
        if (new_selection == view->priv->selected_page)
            new_selection = get_next_page (view);
        view->priv->selected_page = NULL;
    }

    g_hash_table_remove (view->priv->page_data, page);

    view->priv->need_layout = TRUE;
    book_view_redraw (view);
    
    select_page (view, new_selection);
}


static void
clear_cb (Book *book, BookView *view)
{
    g_hash_table_remove_all (view->priv->page_data);
    view->priv->selected_page = NULL;
    g_signal_emit (view, signals[PAGE_SELECTED], 0, NULL);
    view->priv->need_layout = TRUE;
    book_view_redraw (view);
}


void
book_view_set_book (BookView *view, Book *book)
{
    gint i, n_pages;

    g_return_if_fail (view != NULL);
    g_return_if_fail (book != NULL);

    view->priv->book = g_object_ref (book);

    /* Load existing pages */
    n_pages = book_get_n_pages (view->priv->book);
    for (i = 0; i < n_pages; i++) {
        Page *page = book_get_page (book, i);
        add_cb (book, page, view);
    }
    
    book_view_select_page (view, book_get_page (book, 0));

    /* Watch for new pages */
    g_signal_connect (book, "page-added", G_CALLBACK (add_cb), view);
    g_signal_connect (book, "page-removed", G_CALLBACK (remove_cb), view);
    g_signal_connect (book, "cleared", G_CALLBACK (clear_cb), view);
}


Book *
book_view_get_book (BookView *view)
{
    g_return_val_if_fail (view != NULL, NULL);

    return view->priv->book;
}


static gboolean
configure_cb (GtkWidget *widget, GdkEventConfigure *event, BookView *view)
{
    view->priv->need_layout = TRUE;
    return FALSE;
}


static void
layout_into (BookView *view, gint width, gint height, gint *book_width, gint *book_height)
{
    gint spacing = 12;
    gint max_width = 0, max_height = 0;
    gdouble aspect, max_aspect;
    gint x_offset = 0;
    gint i, n_pages;
    gint max_dpi = 0;

    n_pages = book_get_n_pages (view->priv->book);

    /* Get maximum page resolution */
    for (i = 0; i < n_pages; i++) {
        Page *page = book_get_page (view->priv->book, i);
        if (page_get_dpi (page) > max_dpi)
            max_dpi = page_get_dpi (page);
    }

    /* Get area required to fit all pages */
    for (i = 0; i < n_pages; i++) {
        Page *page = book_get_page (view->priv->book, i);
        gint w, h;

        w = page_get_width (page);
        h = page_get_height (page);

        /* Scale to the same DPI */
        w = (double)w * max_dpi / page_get_dpi (page) + 0.5;
        h = (double)h * max_dpi / page_get_dpi (page) + 0.5;

        if (w > max_width)
            max_width = w;
        if (h > max_height)
            max_height = h;
    }

    aspect = (double)width / height;
    max_aspect = (double)max_width / max_height;

    /* Get total dimensions of all pages */
    *book_width = 0;
    *book_height = 0;
    for (i = 0; i < n_pages; i++) {
        PageView *page = get_nth_page (view, i);
        gdouble h;

        // FIXME: Keep DPI
        // FIXME: Don't scale past max size
        /* Scale based on width... */
        if (max_aspect > aspect)
            page_view_set_width (page, width);
        /* ...or height */
        else
            page_view_set_height (page, height);

        h = page_view_get_height (page);
        if (h > *book_height)
            *book_height = h;
        *book_width += page_view_get_width (page);
        if (i != 0)
            *book_width += spacing;
    }

    for (i = 0; i < n_pages; i++) {
        PageView *page = get_nth_page (view, i);

        /* Layout pages left to right */
        page_view_set_x_offset (page, x_offset);
        x_offset += page_view_get_width (page) + spacing;

        /* Centre page vertically */
        page_view_set_y_offset (page, (*book_height - page_view_get_height (page)) / 2);
    }
}


static void
layout (BookView *view)
{
    gint width, height, book_width, book_height;

    if (!view->priv->need_layout)
        return;
  
    /* Try and fit without scrollbar */
    width = view->priv->widget->allocation.width;
    height = view->priv->box->allocation.height;
    layout_into (view, width, height, &book_width, &book_height);

    /* Relayout with scrollbar */
    if (book_width > view->priv->widget->allocation.width) {
        /* Re-layout leaving space for scrollbar */
        height = view->priv->widget->allocation.height;
        layout_into (view, width, height, &book_width, &book_height);

        /* Set scrollbar limits */
        gtk_adjustment_set_upper (view->priv->adjustment, book_width);
        gtk_adjustment_set_page_size (view->priv->adjustment, view->priv->widget->allocation.width);

        /* Ensure that selected page is visible */
        // FIXME: This is too agressive and overrides user control of the scrollbar
        if (view->priv->selected_page) {
            gint left_edge, right_edge;

            left_edge = page_view_get_x_offset (view->priv->selected_page);
            right_edge = page_view_get_x_offset (view->priv->selected_page) + page_view_get_width (view->priv->selected_page);

            if (left_edge - view->priv->x_offset < 0) {
                view->priv->x_offset = left_edge;
            }
            else if (right_edge - view->priv->x_offset > view->priv->widget->allocation.width) {
                view->priv->x_offset = right_edge - view->priv->widget->allocation.width;
            }
        }

        /* Make sure offset is still visible */
        if (view->priv->x_offset < 0)
            view->priv->x_offset = 0;
        if (view->priv->x_offset > book_width - view->priv->widget->allocation.width)
            view->priv->x_offset = book_width - view->priv->widget->allocation.width;

        gtk_adjustment_set_value (view->priv->adjustment, view->priv->x_offset);
        gtk_widget_show (view->priv->scroll);
    } else {
        view->priv->x_offset = (book_width - view->priv->widget->allocation.width) / 2;
        gtk_widget_hide (view->priv->scroll);
    }

    view->priv->need_layout = FALSE;
}


static gboolean
expose_cb (GtkWidget *widget, GdkEventExpose *event, BookView *view)
{
    gint i, n_pages;
    cairo_t *context;

    n_pages = book_get_n_pages (view->priv->book);
    if (n_pages == 0)
        return FALSE;

    layout (view);

    context = gdk_cairo_create (widget->window);

    /* Render each page */
    for (i = 0; i < n_pages; i++) {
        PageView *page = get_nth_page (view, i);
      
        /* Page not visible, off to the left */
        // FIXME: Not working
        //if (page_view_get_width (page) - view->priv->x_offset < event->area.x)
        //    continue;
      
        /* Page not visible, off to the right */
        //if (page_view_get_x_offset (page) > event->area.x + event->area.width)
        //    break;

        cairo_save (context);
        cairo_translate (context, -view->priv->x_offset, 0);
        page_view_render (page, context);
        cairo_restore (context);
    }

    cairo_destroy (context);

    return FALSE;
}


static PageView *
get_page_at (BookView *view, gint x, gint y, gint *x_, gint *y_)
{
    gint i, n_pages;

    n_pages = book_get_n_pages (view->priv->book);
    for (i = 0; i < n_pages; i++) {
        PageView *page;
        gint left, right, top, bottom;

        page = get_nth_page (view, i);
        left = page_view_get_x_offset (page);
        right = left + page_view_get_width (page);
        top = page_view_get_y_offset (page);
        bottom = top + page_view_get_height (page);
        if (x >= left && x <= right && y >= top && y <= bottom) 
        {
            *x_ = x - left;
            *y_ = y - top;
            return page;
        }
    }

    return NULL;
}


static gboolean
button_cb (GtkWidget *widget, GdkEventButton *event, BookView *view)
{
    gint x, y;

    layout (view);

    gtk_widget_grab_focus (view->priv->widget);

    select_page (view, get_page_at (view, event->x + view->priv->x_offset, event->y, &x, &y));
    if (!view->priv->selected_page)
        return FALSE;

    /* Modify page */
    if (event->button == 1) {
        if (event->type == GDK_BUTTON_PRESS)
            page_view_button_press (view->priv->selected_page, x, y);
        else
            page_view_button_release (view->priv->selected_page, x, y);
    }

    /* Show pop-up menu on right click */
    if (event->button == 3) {
        gtk_menu_popup (GTK_MENU (view->priv->page_menu), NULL, NULL, NULL, NULL,
                        event->button, event->time);
    }

    return FALSE;
}


static void
set_cursor (BookView *view, gint cursor)
{
    GdkCursor *c;
  
    if (view->priv->cursor == cursor)
        return;
    view->priv->cursor = cursor;

    c = gdk_cursor_new (cursor);
    gdk_window_set_cursor (gtk_widget_get_window (view->priv->widget), c);
    gdk_cursor_destroy (c);
}


static gboolean
motion_cb (GtkWidget *widget, GdkEventMotion *event, BookView *view)
{
    gint x, y;
    gint cursor = GDK_ARROW;
 
    /* Dragging */
    if (view->priv->selected_page && (event->state & GDK_BUTTON1_MASK) != 0) {
        x = event->x + view->priv->x_offset - page_view_get_x_offset (view->priv->selected_page);
        y = event->y - page_view_get_y_offset (view->priv->selected_page);
        page_view_motion (view->priv->selected_page, x, y);
        cursor = page_view_get_cursor (view->priv->selected_page);
    }
    else {
        PageView *over_page;
        over_page = get_page_at (view, event->x + view->priv->x_offset, event->y, &x, &y);
        if (over_page) {
            page_view_motion (over_page, x, y);
            cursor = page_view_get_cursor (over_page);
        }
    }

    set_cursor (view, cursor);

    return FALSE;
}


static gboolean
key_cb (GtkWidget *widget, GdkEventKey *event, BookView *view)
{
    switch (event->keyval) {
    case GDK_Home:
        book_view_select_page (view, book_get_page (view->priv->book, 0));
        return TRUE;
    case GDK_Left:
        select_page (view, get_prev_page (view));
        return TRUE;
    case GDK_Right:
        select_page (view, get_next_page (view));
        return TRUE;
    case GDK_End:
        book_view_select_page (view, book_get_page (view->priv->book, book_get_n_pages (view->priv->book) - 1));
        return TRUE;

    default:
        return FALSE;
    }
}


static gboolean
focus_cb (GtkWidget *widget, GdkEventFocus *event, BookView *view)
{
    update_page_focus (view);
    return FALSE;
}


static void
scroll_cb (GtkAdjustment *adjustment, BookView *view)
{
   view->priv->x_offset = (int) (gtk_adjustment_get_value (view->priv->adjustment) + 0.5);
   book_view_redraw (view);
}


void
book_view_set_widgets (BookView *view, GtkWidget *box, GtkWidget *area, GtkWidget *scroll, GtkWidget *page_menu)
{
    g_return_if_fail (view != NULL);
    g_return_if_fail (view->priv->widget == NULL);

    view->priv->widget = area;
    view->priv->box = box;
    view->priv->scroll = scroll;
    view->priv->adjustment = gtk_range_get_adjustment (GTK_RANGE (scroll));
    view->priv->page_menu = page_menu;

    g_signal_connect (area, "configure-event", G_CALLBACK (configure_cb), view);
    g_signal_connect (area, "expose-event", G_CALLBACK (expose_cb), view);
    g_signal_connect (area, "motion-notify-event", G_CALLBACK (motion_cb), view);
    g_signal_connect (area, "key-press-event", G_CALLBACK (key_cb), view);
    g_signal_connect (area, "button-press-event", G_CALLBACK (button_cb), view);
    g_signal_connect (area, "button-release-event", G_CALLBACK (button_cb), view);
    g_signal_connect_after (area, "focus-in-event", G_CALLBACK (focus_cb), view);
    g_signal_connect_after (area, "focus-out-event", G_CALLBACK (focus_cb), view);
    g_signal_connect (view->priv->adjustment, "value-changed", G_CALLBACK (scroll_cb), view);
}


void
book_view_redraw (BookView *view)
{
    g_return_if_fail (view != NULL);
    gtk_widget_queue_draw (view->priv->widget);  
}


void
book_view_select_page (BookView *view, Page *page)
{
    g_return_if_fail (view != NULL);

    if (book_view_get_selected (view) == page)
        return;

    if (page)
        select_page (view, g_hash_table_lookup (view->priv->page_data, page));
    else
        select_page (view, NULL);
}


void
book_view_select_next_page (BookView *view)
{
    g_return_if_fail (view != NULL);
    select_page (view, get_next_page (view));
}


void
book_view_select_prev_page (BookView *view)
{
    g_return_if_fail (view != NULL);
    select_page (view, get_prev_page (view));
}


Page *
book_view_get_selected (BookView *view)
{
    g_return_val_if_fail (view != NULL, NULL);

    if (view->priv->selected_page)
        return page_view_get_page (view->priv->selected_page);
    else
        return NULL;
}


static void
book_view_finalize (GObject *object)
{
    BookView *view = BOOK_VIEW (object);
    g_object_unref (view->priv->book);
    view->priv->book = NULL;
    g_hash_table_unref (view->priv->page_data);
    view->priv->page_data = NULL;
    G_OBJECT_CLASS (book_view_parent_class)->finalize (object);
}


static void
book_view_class_init (BookViewClass *klass)
{
    GObjectClass *object_class = G_OBJECT_CLASS (klass);

    object_class->finalize = book_view_finalize;

    signals[PAGE_SELECTED] =
        g_signal_new ("page-selected",
                      G_TYPE_FROM_CLASS (klass),
                      G_SIGNAL_RUN_LAST,
                      G_STRUCT_OFFSET (BookViewClass, page_selected),
                      NULL, NULL,
                      g_cclosure_marshal_VOID__POINTER,
                      G_TYPE_NONE, 1, G_TYPE_POINTER);

    g_type_class_add_private (klass, sizeof (BookViewPrivate));
}


static void
book_view_init (BookView *view)
{
    view->priv = G_TYPE_INSTANCE_GET_PRIVATE (view, BOOK_VIEW_TYPE, BookViewPrivate);
    view->priv->need_layout = TRUE;
    view->priv->page_data = g_hash_table_new_full (g_direct_hash, g_direct_equal,
                                                   NULL, (GDestroyNotify) g_object_unref);
    view->priv->cursor = GDK_ARROW;
}
