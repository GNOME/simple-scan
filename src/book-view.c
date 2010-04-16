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
    PROP_0,
    PROP_BOOK
};

enum {
    PAGE_SELECTED,
    SHOW_PAGE,
    SHOW_MENU,
    LAST_SIGNAL
};
static guint signals[LAST_SIGNAL] = { 0, };

struct BookViewPrivate
{
    /* Book being rendered */
    Book *book;
    GHashTable *page_data;
    
    /* True if the view needs to be laid out again */
    gboolean need_layout, laying_out, show_selected_page;

    /* Currently selected page */
    PageView *selected_page;
  
    /* Widget being rendered to */
    GtkWidget *drawing_area;

    /* Horizontal scrollbar */
    GtkWidget *scroll;
    GtkAdjustment *adjustment;

    gint cursor;
};

G_DEFINE_TYPE (BookView, book_view, GTK_TYPE_VBOX);


BookView *
book_view_new (Book *book)
{
    return g_object_new (BOOK_VIEW_TYPE, "book", book, NULL);
}


static PageView *
get_nth_page (BookView *view, gint n)
{
    Page *page = book_get_page (view->priv->book, n);
    return g_hash_table_lookup (view->priv->page_data, page);
}


static PageView *
get_next_page (BookView *view, PageView *page)
{
    gint i;
    
    for (i = 0; ; i++) {
        Page *p;
        p = book_get_page (view->priv->book, i);
        if (!p)
            break;
        if (p == page_view_get_page (page)) {
            p = book_get_page (view->priv->book, i + 1);
            if (p)
                return g_hash_table_lookup (view->priv->page_data, p);
        }
    }
    
    return page;
}


static PageView *
get_prev_page (BookView *view, PageView *page)
{
    gint i;
    PageView *prev_page = page;

    for (i = 0; ; i++) {
        Page *p;
        p = book_get_page (view->priv->book, i);
        if (!p)
            break;
        if (p == page_view_get_page (page))
            return prev_page;
        prev_page = g_hash_table_lookup (view->priv->page_data, p);
    }

    return page;
}


static void
page_view_changed_cb (PageView *page, BookView *view)
{
    book_view_redraw (view);
}


static void
page_view_size_changed_cb (PageView *page, BookView *view)
{
    view->priv->need_layout = TRUE;
    book_view_redraw (view);
}


static void
add_cb (Book *book, Page *page, BookView *view)
{
    PageView *page_view;
    page_view = page_view_new (page);
    g_signal_connect (page_view, "changed", G_CALLBACK (page_view_changed_cb), view);
    g_signal_connect (page_view, "size-changed", G_CALLBACK (page_view_size_changed_cb), view);  
    g_hash_table_insert (view->priv->page_data, page, page_view);
    view->priv->need_layout = TRUE;
    book_view_redraw (view);
}


static void
set_selected_page (BookView *view, PageView *page)
{
    /* Deselect existing page if changed */
    if (view->priv->selected_page && page != view->priv->selected_page)
        page_view_set_selected (view->priv->selected_page, FALSE);  

    view->priv->selected_page = page;
    if (!view->priv->selected_page)
        return;

    /* Select new page if widget has focus */
    if (!gtk_widget_has_focus (view->priv->drawing_area))
        page_view_set_selected (view->priv->selected_page, FALSE);
    else
        page_view_set_selected (view->priv->selected_page, TRUE);
}


static void
set_x_offset (BookView *view, gint offset)
{
    gtk_adjustment_set_value (view->priv->adjustment, offset);
}


static gint
get_x_offset (BookView *view)
{
    return (gint) gtk_adjustment_get_value (view->priv->adjustment);
}


static void
show_page (BookView *view, PageView *page)
{
    gint left_edge, right_edge;
    GtkAllocation allocation;

    if (!page || !gtk_widget_get_visible (view->priv->scroll))
        return;

    gtk_widget_get_allocation(view->priv->drawing_area, &allocation);
    left_edge = page_view_get_x_offset (page);
    right_edge = page_view_get_x_offset (page) + page_view_get_width (page);

    if (left_edge - get_x_offset (view) < 0)
        set_x_offset(view, left_edge);
    else if (right_edge - get_x_offset (view) > allocation.width)
        set_x_offset(view, right_edge - allocation.width);
}


static void
select_page (BookView *view, PageView *page)
{
    Page *p = NULL;
  
    if (view->priv->selected_page == page)
        return;

    set_selected_page (view, page);

    if (view->priv->need_layout)
        view->priv->show_selected_page = TRUE;
    else
        show_page (view, page);

    if (page)
        p = page_view_get_page (page);
    g_signal_emit (view, signals[PAGE_SELECTED], 0, p);
}


static void
remove_cb (Book *book, Page *page, BookView *view)
{
    PageView *new_selection = view->priv->selected_page;

    /* Select previous page or next if removing the selected page */
    if (page == book_view_get_selected (view)) {
        new_selection = get_prev_page (view, view->priv->selected_page);
        if (new_selection == view->priv->selected_page)
            new_selection = get_next_page (view, view->priv->selected_page);
        view->priv->selected_page = NULL;
    }

    g_hash_table_remove (view->priv->page_data, page);

    select_page (view, new_selection);

    view->priv->need_layout = TRUE;
    book_view_redraw (view);
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
        Page *p = page_view_get_page (page);
        gint h;

        /* NOTE: Using double to avoid overflow for large images */
        if (max_aspect > aspect) {
            /* Set width scaled on DPI and maximum width */
            gint w = (double)page_get_width (p) * max_dpi * width / (page_get_dpi (p) * max_width);
            page_view_set_width (page, w);
        }
        else {
            /* Set height scaled on DPI and maximum height */
            gint h = (double)page_get_height (p) * max_dpi * height / (page_get_dpi (p) * max_height);
            page_view_set_height (page, h);
        }

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
        page_view_set_y_offset (page, (height - page_view_get_height (page)) / 2);
    }
}


static void
layout (BookView *view)
{
    gint width, height, book_width, book_height;
    gboolean right_aligned = TRUE;
    GtkAllocation allocation, box_allocation;

    if (!view->priv->need_layout)
        return;

    view->priv->laying_out = TRUE;

    gtk_widget_get_allocation(view->priv->drawing_area, &allocation);
    gtk_widget_get_allocation(GTK_WIDGET(view), &box_allocation);

    /* If scroll is right aligned then keep that after layout */
    if (gtk_adjustment_get_value (view->priv->adjustment) < gtk_adjustment_get_upper (view->priv->adjustment) - gtk_adjustment_get_page_size (view->priv->adjustment))
        right_aligned = FALSE;

    /* Try and fit without scrollbar */
    width = allocation.width;
    height = box_allocation.height - gtk_container_get_border_width (GTK_CONTAINER (view)) * 2;
    layout_into (view, width, height, &book_width, &book_height);

    /* Relayout with scrollbar */
    if (book_width > allocation.width) {
        gint max_offset;
      
        /* Re-layout leaving space for scrollbar */
        height = allocation.height;
        layout_into (view, width, height, &book_width, &book_height);

        /* Set scrollbar limits */
        gtk_adjustment_set_lower (view->priv->adjustment, 0);
        gtk_adjustment_set_upper (view->priv->adjustment, book_width);
        gtk_adjustment_set_page_size (view->priv->adjustment, allocation.width);

        /* Keep right-aligned */
        max_offset = book_width - allocation.width;
        if (right_aligned || get_x_offset (view) > max_offset)
            set_x_offset(view, max_offset);

        gtk_widget_show (view->priv->scroll);
    } else {
        gint offset;
        gtk_widget_hide (view->priv->scroll);
        offset = (book_width - allocation.width) / 2;
        gtk_adjustment_set_lower (view->priv->adjustment, offset);
        gtk_adjustment_set_upper (view->priv->adjustment, offset);
        gtk_adjustment_set_page_size (view->priv->adjustment, 0);
        set_x_offset(view, offset);
    }
  
    if (view->priv->show_selected_page)
       show_page (view, view->priv->selected_page);

    view->priv->need_layout = FALSE;
    view->priv->show_selected_page = FALSE;
    view->priv->laying_out = FALSE;
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

    context = gdk_cairo_create (gtk_widget_get_window(widget));

    /* Render each page */
    for (i = 0; i < n_pages; i++) {
        PageView *page = get_nth_page (view, i);
        gint left_edge, right_edge;
      
        left_edge = page_view_get_x_offset (page) - get_x_offset (view);
        right_edge = page_view_get_x_offset (page) + page_view_get_width (page) - get_x_offset (view);
      
        /* Page not visible, don't render */
        if (right_edge < event->area.x || left_edge > event->area.x + event->area.width)
            continue;

        cairo_save (context);
        cairo_translate (context, -get_x_offset (view), 0);
        page_view_render (page, context);
        cairo_restore (context);

        if (page_view_get_selected (page))
            gtk_paint_focus (gtk_widget_get_style (view->priv->drawing_area),
                             gtk_widget_get_window (view->priv->drawing_area),
                             GTK_STATE_SELECTED,
                             &event->area,
                             NULL,
                             NULL,
                             page_view_get_x_offset (page) - get_x_offset (view),
                             page_view_get_y_offset (page),
                             page_view_get_width (page),
                             page_view_get_height (page));
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

    gtk_widget_grab_focus (view->priv->drawing_area);

    if (event->type == GDK_BUTTON_PRESS)
        select_page (view, get_page_at (view, event->x + get_x_offset (view), event->y, &x, &y));

    if (!view->priv->selected_page)
        return FALSE;

    /* Modify page */
    if (event->button == 1) {
        if (event->type == GDK_BUTTON_PRESS)
            page_view_button_press (view->priv->selected_page, x, y);
        else if (event->type == GDK_BUTTON_RELEASE)
            page_view_button_release (view->priv->selected_page, x, y);
        else if (event->type == GDK_2BUTTON_PRESS)
            g_signal_emit (view, signals[SHOW_PAGE], 0, book_view_get_selected (view));
    }

    /* Show pop-up menu on right click */
    if (event->button == 3)
        g_signal_emit (view, signals[SHOW_MENU], 0);

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
    gdk_window_set_cursor (gtk_widget_get_window (view->priv->drawing_area), c);
    gdk_cursor_destroy (c);
}


static gboolean
motion_cb (GtkWidget *widget, GdkEventMotion *event, BookView *view)
{
    gint x, y;
    gint cursor = GDK_ARROW;
 
    /* Dragging */
    if (view->priv->selected_page && (event->state & GDK_BUTTON1_MASK) != 0) {
        x = event->x + get_x_offset (view) - page_view_get_x_offset (view->priv->selected_page);
        y = event->y - page_view_get_y_offset (view->priv->selected_page);
        page_view_motion (view->priv->selected_page, x, y);
        cursor = page_view_get_cursor (view->priv->selected_page);
    }
    else {
        PageView *over_page;
        over_page = get_page_at (view, event->x + get_x_offset (view), event->y, &x, &y);
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
        select_page (view, get_prev_page (view, view->priv->selected_page));
        return TRUE;
    case GDK_Right:
        select_page (view, get_next_page (view, view->priv->selected_page));
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
    set_selected_page (view, view->priv->selected_page);
    return FALSE;
}


static void
scroll_cb (GtkAdjustment *adjustment, BookView *view)
{
   if (!view->priv->laying_out)
       book_view_redraw (view);
}


void
book_view_redraw (BookView *view)
{
    g_return_if_fail (view != NULL);
    gtk_widget_queue_draw (view->priv->drawing_area);  
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
    select_page (view, get_next_page (view, view->priv->selected_page));
}


void
book_view_select_prev_page (BookView *view)
{
    g_return_if_fail (view != NULL);
    select_page (view, get_prev_page (view, view->priv->selected_page));
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
book_view_set_property(GObject      *object,
                       guint         prop_id,
                       const GValue *value,
                       GParamSpec   *pspec)
{
    BookView *self;
    gint i, n_pages;

    self = BOOK_VIEW (object);

    switch (prop_id) {
    case PROP_BOOK:
        self->priv->book = g_object_ref (g_value_get_object (value));

        /* Load existing pages */
        n_pages = book_get_n_pages (self->priv->book);
        for (i = 0; i < n_pages; i++) {
            Page *page = book_get_page (self->priv->book, i);
            add_cb (self->priv->book, page, self);
        }

        book_view_select_page (self, book_get_page (self->priv->book, 0));

        /* Watch for new pages */
        g_signal_connect (self->priv->book, "page-added", G_CALLBACK (add_cb), self);
        g_signal_connect (self->priv->book, "page-removed", G_CALLBACK (remove_cb), self);
        g_signal_connect (self->priv->book, "cleared", G_CALLBACK (clear_cb), self);
        break;
    default:
        G_OBJECT_WARN_INVALID_PROPERTY_ID (object, prop_id, pspec);
        break;
    }
}


static void
book_view_get_property(GObject    *object,
                       guint       prop_id,
                       GValue     *value,
                       GParamSpec *pspec)
{
    BookView *self;

    self = BOOK_VIEW (object);

    switch (prop_id) {
    case PROP_BOOK:
        g_value_set_object (value, self->priv->book);
        break;
    default:
        G_OBJECT_WARN_INVALID_PROPERTY_ID (object, prop_id, pspec);
        break;
    }
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
    object_class->set_property = book_view_set_property;
    object_class->get_property = book_view_get_property;

    signals[PAGE_SELECTED] =
        g_signal_new ("page-selected",
                      G_TYPE_FROM_CLASS (klass),
                      G_SIGNAL_RUN_LAST,
                      G_STRUCT_OFFSET (BookViewClass, page_selected),
                      NULL, NULL,
                      g_cclosure_marshal_VOID__OBJECT,
                      G_TYPE_NONE, 1, page_get_type());
    signals[SHOW_PAGE] =
        g_signal_new ("show-page",
                      G_TYPE_FROM_CLASS (klass),
                      G_SIGNAL_RUN_LAST,
                      G_STRUCT_OFFSET (BookViewClass, show_page),
                      NULL, NULL,
                      g_cclosure_marshal_VOID__OBJECT,
                      G_TYPE_NONE, 1, page_get_type());
    signals[SHOW_MENU] =
        g_signal_new ("show-menu",
                      G_TYPE_FROM_CLASS (klass),
                      G_SIGNAL_RUN_LAST,
                      G_STRUCT_OFFSET (BookViewClass, show_page),
                      NULL, NULL,
                      g_cclosure_marshal_VOID__VOID,
                      G_TYPE_NONE, 0);

    g_object_class_install_property(object_class,
                                    PROP_BOOK,
                                    g_param_spec_object("book",
                                                        "book",
                                                        "Book being shown",
                                                        book_get_type(),
                                                        G_PARAM_READWRITE | G_PARAM_CONSTRUCT_ONLY));

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
  
    view->priv->drawing_area = gtk_drawing_area_new ();
    gtk_widget_set_size_request (view->priv->drawing_area, 200, 100);
    gtk_widget_set_can_focus (view->priv->drawing_area, TRUE);
    gtk_widget_set_events (view->priv->drawing_area, GDK_POINTER_MOTION_MASK | GDK_BUTTON_PRESS_MASK | GDK_BUTTON_RELEASE_MASK | GDK_FOCUS_CHANGE_MASK | GDK_STRUCTURE_MASK | GDK_SCROLL_MASK);
    gtk_box_pack_start (GTK_BOX (view), view->priv->drawing_area, TRUE, TRUE, 0);

    view->priv->scroll = gtk_hscrollbar_new (NULL);
    view->priv->adjustment = gtk_range_get_adjustment (GTK_RANGE (view->priv->scroll));
    gtk_box_pack_start (GTK_BOX (view), view->priv->scroll, FALSE, TRUE, 0);

    g_signal_connect (view->priv->drawing_area, "configure-event", G_CALLBACK (configure_cb), view);
    g_signal_connect (view->priv->drawing_area, "expose-event", G_CALLBACK (expose_cb), view);
    g_signal_connect (view->priv->drawing_area, "motion-notify-event", G_CALLBACK (motion_cb), view);
    g_signal_connect (view->priv->drawing_area, "key-press-event", G_CALLBACK (key_cb), view);
    g_signal_connect (view->priv->drawing_area, "button-press-event", G_CALLBACK (button_cb), view);
    g_signal_connect (view->priv->drawing_area, "button-release-event", G_CALLBACK (button_cb), view);
    g_signal_connect_after (view->priv->drawing_area, "focus-in-event", G_CALLBACK (focus_cb), view);
    g_signal_connect_after (view->priv->drawing_area, "focus-out-event", G_CALLBACK (focus_cb), view);
    g_signal_connect (view->priv->adjustment, "value-changed", G_CALLBACK (scroll_cb), view);

    gtk_widget_show (view->priv->drawing_area);
}
