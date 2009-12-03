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


enum {
    PAGE_SELECTED,
    LAST_SIGNAL
};
static guint signals[LAST_SIGNAL] = { 0, };

typedef struct
{
    /* Page being rendered */
    Page *page;
    
    /* Image to render at current resolution */
    GdkPixbuf *image;

    /* True if image needs to be regenerated */
    gboolean update_image;
    
    gdouble scale;

    /* Dimensions of image to generate */
    gint width, height;
    
    /* Border around image */
    gint border;
    
    /* Location to place this page */
    gint x, y;
} PageView;


struct BookViewPrivate
{
    /* Book being rendered */
    Book *book;
    GHashTable *page_data;
    
    /* True if the view needs to be laid out again */
    gboolean need_layout;

    /* Dimensions of area to render into (pixels) */
    // FIXME: Can use widget->allocation.width?
    gint width, height;

    /* Amount to offset view by (pixels) */
    gint x_offset, y_offset;

    GtkAdjustment *zoom_adjustment;
    gdouble old_zoom;

    Page *selected_page;
    
    /* The page the crop is being moved on or NULL */
    PageView *selected_crop;
    gdouble selected_crop_px, selected_crop_py;
    gint selected_crop_x, selected_crop_y;

    /* Widget being rendered to */
    GtkWidget *widget;

    GtkWidget *page_menu;

    /* Last location of mouse */
    gdouble mouse_x, mouse_y;
};

G_DEFINE_TYPE (BookView, book_view, G_TYPE_OBJECT);


BookView *
book_view_new ()
{
    return g_object_new (BOOK_VIEW_TYPE, NULL);
}


GtkAdjustment *
book_view_get_zoom_adjustment (BookView *view)
{
    return view->priv->zoom_adjustment;
}


static Page *
get_next_page (BookView *view)
{
    gint i;
    
    for (i = 0; ; i++) {
        Page *page;
        page = book_get_page (view->priv->book, i);
        if (!page)
            break;
        if (page == view->priv->selected_page) {
            page = book_get_page (view->priv->book, i + 1);
            if (page)
                return page;
        }
    }
    
    return view->priv->selected_page;
}


static Page *
get_prev_page (BookView *view)
{
    gint i;
    Page *prev_page = view->priv->selected_page;

    for (i = 0; ; i++) {
        Page *page;
        page = book_get_page (view->priv->book, i);
        if (!page)
            break;
        if (page == view->priv->selected_page)
            return prev_page;
        prev_page = page;
    }
    
    return prev_page;
}


static void
page_set_scale (PageView *page, gdouble scale)
{
    gint width, height;

    width = (scale * page_get_width (page->page) + 0.5);
    height = (scale * page_get_height (page->page) + 0.5);

    if (page->width == width &&
        page->height == height)
        return;

    page->scale = scale;
    page->width = width;
    page->height = height;
    page->update_image = TRUE;
}


static void
update_cb (Page *p, BookView *view)
{
    PageView *page = g_hash_table_lookup (view->priv->page_data, p);
    page_set_scale (page, page->scale);
    page->update_image = TRUE;
    view->priv->need_layout = TRUE; // Only for rotation/resize
    gtk_widget_queue_draw (view->priv->widget);
}


static void
crop_update_cb (Page *p, BookView *view)
{
    gtk_widget_queue_draw (view->priv->widget);
}


static PageView *
page_view_alloc (Page *page)
{
    PageView *view;
    
    view = g_malloc0 (sizeof (PageView));
    view->page = page;
    view->update_image = TRUE;
    
    return view;
}


static void
page_view_free (PageView *view)
{
    if (view->image)
        g_object_unref (view->image);
    g_free (view);
}

static void
add_cb (Book *book, Page *page, BookView *view)
{
    g_hash_table_insert (view->priv->page_data, page, page_view_alloc (page));
    g_signal_connect (page, "image-changed", G_CALLBACK (update_cb), view);
    g_signal_connect (page, "orientation-changed", G_CALLBACK (update_cb), view);
    g_signal_connect (page, "crop-changed", G_CALLBACK (crop_update_cb), view);
    view->priv->need_layout = TRUE;
    gtk_widget_queue_draw (view->priv->widget);
}


static void
remove_cb (Book *book, Page *page, BookView *view)
{
    Page *new_selection = view->priv->selected_page;

    /* Select previous page or next if removing the first page */
    if (page == view->priv->selected_page) {
        new_selection = get_prev_page (view);
        if (new_selection == view->priv->selected_page)
            new_selection = get_next_page (view);
    }

    g_hash_table_remove (view->priv->page_data, page);
    view->priv->need_layout = TRUE;
    gtk_widget_queue_draw (view->priv->widget);
    
    book_view_select_page (view, new_selection);
}


static void
clear_cb (Book *book, BookView *view)
{
    g_hash_table_remove_all (view->priv->page_data);
    view->priv->need_layout = TRUE;
    gtk_widget_queue_draw (view->priv->widget);
    book_view_select_page (view, NULL);
}


void
book_view_set_book (BookView *view, Book *book)
{
    gint i, n_pages;

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


Book *book_view_get_book (BookView *view)
{
    return view->priv->book;
}


static gboolean
configure_cb (GtkWidget *widget, GdkEventConfigure *event, BookView *view)
{
    view->priv->width = event->width;
    view->priv->height = event->height;
    view->priv->need_layout = TRUE;
    return FALSE;
}


static void
set_cursor (BookView *view, gint cursor)
{
    gdk_window_set_cursor (gtk_widget_get_window (view->priv->widget),
                           gdk_cursor_new (cursor));
}


void
book_view_pan (BookView *view, gint x_offset, gint y_offset)
{
    view->priv->x_offset += x_offset;
    view->priv->y_offset += y_offset;
    view->priv->need_layout = TRUE;
    gtk_widget_queue_draw (view->priv->widget);

    set_cursor (view, GDK_HAND1);
}


void
book_view_set_zoom (BookView *view, gdouble zoom)
{
    gtk_adjustment_set_value (view->priv->zoom_adjustment, zoom);
}


static void
update_page_view (PageView *page)
{
    GdkPixbuf *image;

    if (!page->update_image)
        return;

    if (page->image)
        g_object_unref (page->image);
    image = page_get_image (page->page);
    
    page->image = gdk_pixbuf_scale_simple (image,
                                           page->width, page->height,
                                           GDK_INTERP_BILINEAR);
    g_object_unref (image);

    page->update_image = FALSE;
}



static gint
page_to_screen_x (PageView *page, gint x)
{
    return (double) x * page->width / page_get_width (page->page) + 0.5;
}


static gint
page_to_screen_y (PageView *page, gint y)
{
    return (double) y * page->height / page_get_height (page->page) + 0.5;    
}


static gint
screen_to_page_x (PageView *page, gint x)
{
    return (double) x * page_get_width (page->page) / page->width + 0.5;
}


static gint
screen_to_page_y (PageView *page, gint y)
{
    return (double) y * page_get_height (page->page) / page->height  + 0.5;    
}


static void
render_page (BookView *view, PageView *page, cairo_t *context)
{
    gint scan_line;

    /* Regenerate page pixbuf */
    update_page_view (page);

    cairo_save (context);
    cairo_set_line_width (context, 1);

    /* Draw background */
    cairo_translate (context, view->priv->x_offset + page->x, view->priv->y_offset + page->y);
    cairo_translate (context, 1, 1);
    gdk_cairo_set_source_pixbuf (context, page->image, 0, 0);
    cairo_paint (context);

    /* Draw scan line */
    scan_line = page_get_scan_line (page->page);
    if (scan_line >= 0) {
        double s;
        double x1, y1, x2, y2;
        
        switch (page_get_orientation (page->page)) {
        case TOP_TO_BOTTOM:
            s = page_to_screen_y (page, scan_line);
            x1 = 0; y1 = s + 0.5;
            x2 = page->width; y2 = s + 0.5;
            break;
        case BOTTOM_TO_TOP:
            s = page_to_screen_y (page, scan_line);
            x1 = 0; y1 = page->height - s + 0.5;
            x2 = page->width; y2 = page->height - s + 0.5;
            break;
        case LEFT_TO_RIGHT:
            s = page_to_screen_x (page, scan_line);
            x1 = s + 0.5; y1 = 0;
            x2 = s + 0.5; y2 = page->height;
            break;
        case RIGHT_TO_LEFT:
            s = page_to_screen_x (page, scan_line);
            x1 = page->width - s + 0.5; y1 = 0;
            x2 = page->width - s + 0.5; y2 = page->height;
            break;
        }

        cairo_move_to (context, x1, y1);
        cairo_line_to (context, x2, y2);
        cairo_set_source_rgb (context, 1.0, 0.0, 0.0);
        cairo_stroke (context);
    }
    
    /* Draw crop */
    if (page_has_crop (page->page)) {
        gint x, y, width, height;
        gdouble dx, dy, dw, dh;

        page_get_crop (page->page, &x, &y, &width, &height);

        dx = page_to_screen_x (page, x);
        dy = page_to_screen_y (page, y);
        dw = page_to_screen_x (page, width);
        dh = page_to_screen_y (page, height);
        
        /* Shade out cropped area */
        cairo_rectangle (context, 0, 0, page->width, page->height);
        cairo_new_sub_path (context);
        cairo_rectangle (context, dx, dy, dw, dh);
        cairo_set_fill_rule (context, CAIRO_FILL_RULE_EVEN_ODD);
        cairo_set_source_rgba (context, 0.5, 0.5, 0.5, 0.5);
        cairo_fill (context);
        
        /* Show new edge */
        cairo_rectangle (context, dx - 0.5, dy - 0.5, dw + 1, dh + 1);
        cairo_set_source_rgb (context, 0.5, 0.5, 0.5);
        cairo_stroke (context);
    }

    /* Draw page border */
    /* NOTE: Border width and height is rounded up so border is sharp.  Background may not
     * extend to border, should fill with white (?) before drawing scanned image or extend
     * edges slightly */
    if (page->page == view->priv->selected_page) {
        if (gtk_widget_has_focus (view->priv->widget))
            cairo_set_source_rgb (context, 1, 0, 0);
        else if (book_get_n_pages (view->priv->book) > 1)
            cairo_set_source_rgb (context, 0.75, 0, 0);
        else
            cairo_set_source_rgb (context, 0, 0, 0);            
    }
    else
        cairo_set_source_rgb (context, 0, 0, 0);
    cairo_rectangle (context, -0.5, -0.5, gdk_pixbuf_get_width (page->image) + 1, gdk_pixbuf_get_height (page->image) + 1);
    cairo_stroke (context);
    
    cairo_restore (context);
}


static void
layout (BookView *view)
{
    gint i, n_pages;
    gdouble max_width = 0, max_height = 0;
    gdouble inner_width, inner_height;
    gdouble max_aspect, inner_aspect;
    gdouble border = 1, spacing = 12;
    gdouble book_width = 0, book_height = 0;
    gdouble x_offset = 0, y_offset = 0, scale;
    gdouble x_range = 0, y_range = 0;

    if (!view->priv->need_layout)
        return;
    
    n_pages = book_get_n_pages (view->priv->book);

    /* Get area required to fit all pages */
    for (i = 0; i < n_pages; i++) {
        Page *page = book_get_page (view->priv->book, i);
        if (page_get_width (page) > max_width)
            max_width = page_get_width (page);
        if (page_get_height (page) > max_height)
            max_height = page_get_height (page);
    }
    
    /* Make space for fixed size border */
    inner_width = view->priv->width - 2*border;
    inner_height = view->priv->height - 2*border;
    
    /* Make space to see adjacent pages */
    // FIXME: If selected first or last only need half amount
    if (n_pages > 1)
        inner_width -= spacing * 4;

    max_aspect = max_width / max_height;
    inner_aspect = inner_width / inner_height;
    
    /* Scale based on width... */
    if (max_aspect > inner_aspect) {
        scale = inner_width / max_width;
    }
    /* ...or height */
    else {
        scale = inner_height / max_height;
    }
    
    /* Don't scale past exact resolution */
    if (scale >= 1.0)
        scale = 1.0;
    else {
        scale += (1.0 - scale) * gtk_adjustment_get_value (view->priv->zoom_adjustment);
    }
    
    /* Get total dimensions of all pages */
    for (i = 0; i < n_pages; i++) {
        Page *p = book_get_page (view->priv->book, i);
        PageView *page = g_hash_table_lookup (view->priv->page_data, p);
        gdouble h;

        page_set_scale (page, scale);
        update_page_view (page);

        h = page->height + (2 * border);
        if (h > book_height)
            book_height = h;
        book_width += page->width + (2 * border);
        if (i != 0)
            book_width += spacing;
    }
    
    /* Offset so pages are in the middle */
    if (view->priv->width >= book_width) {
        x_offset = (int) ((view->priv->width - book_width) / 2);
        x_range = 0;
    }
    else {
        x_offset = 0;
        x_range = book_width - view->priv->width;
    }

    if (view->priv->height >= book_height) {
        y_offset = (int) ((view->priv->height - book_height) / 2);
        y_range = 0;
    } else {
        y_offset = 0;
        y_range = (int) (book_height - view->priv->height);
    }
    
    /* Clamp offsets */
    if (view->priv->x_offset < -x_range)
        view->priv->x_offset = -x_range;
    if (view->priv->x_offset > 0)
        view->priv->x_offset = 0;
    if (view->priv->y_offset < -y_range)
        view->priv->y_offset = -y_range;
    if (view->priv->y_offset > 0)
        view->priv->y_offset = 0;
    
    for (i = 0; i < n_pages; i++) {
        Page *p = book_get_page (view->priv->book, i);
        PageView *page = g_hash_table_lookup (view->priv->page_data, p);

        page->border = border;
        page->x = x_offset;
        x_offset += page->width + (2 * page->border) + spacing;
        page->y = y_offset + (book_height - page->height) / 2 - page->border;
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
    
    /* Make sure the selected page is visible */
    if (view->priv->selected_page) {
        PageView *page;
        gint left_edge, right_edge;

        page = g_hash_table_lookup (view->priv->page_data, view->priv->selected_page);

        /* Left and right edges of the page */
        left_edge = page->x;
        right_edge = left_edge + page->border + page->width + page->border;

        /* Make sure can see adjacent pages */
        // FIXME: Hardcoded spacing 24

        if (right_edge + view->priv->x_offset > view->priv->width)
            view->priv->x_offset = view->priv->width - right_edge - 24;
        else if (left_edge + view->priv->x_offset < 0)
            view->priv->x_offset = -left_edge + 24;
    }

    context = gdk_cairo_create (widget->window);

    /* Render each page */
    for (i = 0; i < n_pages; i++) {
        Page *p = book_get_page (view->priv->book, i);
        PageView *page = g_hash_table_lookup (view->priv->page_data, p);
        render_page (view, page, context);
    }

    cairo_destroy (context);

    return FALSE;
}


static void
zoom_cb (GtkAdjustment *adjustment, BookView *view)
{
    gdouble zoom;
    
    zoom = gtk_adjustment_get_value (view->priv->zoom_adjustment);    
    view->priv->x_offset += (zoom - view->priv->old_zoom) * view->priv->width;
    view->priv->y_offset += (zoom - view->priv->old_zoom) * view->priv->height;
    view->priv->old_zoom = zoom;
    
    view->priv->need_layout = TRUE;

    gtk_widget_queue_draw (view->priv->widget);
}


static gboolean
is_inside_crop (PageView *page, gint x, gint y)
{
    gint cx, cy, cw, ch;
    gint dx, dy, dw, dh;

    if (!page_has_crop (page->page))
        return FALSE;

    page_get_crop (page->page, &cx, &cy, &cw, &ch);
    dx = page_to_screen_x (page, cx) + page->x;
    dy = page_to_screen_y (page, cy) + page->y;
    dw = page_to_screen_x (page, cw);
    dh = page_to_screen_y (page, ch);
    return (x >= dx && x <= dx + dw) && (y >= dy && y <= dy + dh);
}


static gboolean
button_cb (GtkWidget *widget, GdkEventButton *event, BookView *view)
{
    gint i, n_pages;
    gboolean on_page = FALSE;
    
    if (event->type == GDK_BUTTON_RELEASE) {
        view->priv->selected_crop = NULL;
        return FALSE;
    }

    view->priv->mouse_x = event->x;
    view->priv->mouse_y = event->y;
    
    layout (view);
    
    /* Select the page clicked on */
    n_pages = book_get_n_pages (view->priv->book);
    for (i = 0; i < n_pages; i++) {
        Page *p = book_get_page (view->priv->book, i);
        PageView *page = g_hash_table_lookup (view->priv->page_data, p);
        gint x, y, left, right, top, bottom;
        
        update_page_view (page);
        x = event->x - view->priv->x_offset;
        y = event->y - view->priv->y_offset;
        left = page->x;
        right = page->x + page->width;
        top = page->y;
        bottom = page->y + page->height;
        if (x >= left && x <= right && y >= top && y <= bottom) {
            book_view_select_page (view, page->page);
            on_page = TRUE;

            /* See if selecting crop */
            if (is_inside_crop (page, x, y)) {
                view->priv->selected_crop = page;
                view->priv->selected_crop_px = event->x;
                view->priv->selected_crop_py = event->y;
                page_get_crop (page->page,
                               &view->priv->selected_crop_x,
                               &view->priv->selected_crop_y,
                               NULL, NULL);
            }

            break;
        }
    }
    
    gtk_widget_grab_focus (view->priv->widget);

    /* Show pop-up menu */
    if (on_page && event->button == 3) {
        gtk_menu_popup (GTK_MENU (view->priv->page_menu), NULL, NULL, NULL, NULL,
                        event->button, event->time);
    }

    return FALSE;
}


static gboolean
scroll_cb (GtkWidget *widget, GdkEventScroll *event, BookView *view)
{
    if (event->direction == GDK_SCROLL_UP)
        book_view_set_zoom (view, gtk_adjustment_get_value (view->priv->zoom_adjustment) + 0.1);
    else if (event->direction == GDK_SCROLL_DOWN)
        book_view_set_zoom (view, gtk_adjustment_get_value (view->priv->zoom_adjustment) - 0.1);
    return FALSE;
}


static gboolean
motion_cb (GtkWidget *widget, GdkEventMotion *event, BookView *view)
{
    gint x, y;
    gint sx, sy;
    gint i, n_pages;
    gboolean over_crop = FALSE;

    sx = event->x - view->priv->mouse_x;
    sy = event->y - view->priv->mouse_y;
    view->priv->mouse_x = event->x;
    view->priv->mouse_y = event->y;

    /* Location of cursor in book */
    x = event->x - view->priv->x_offset;
    y = event->y - view->priv->y_offset;
    
    /* Check if inside crop */
    n_pages = book_get_n_pages (view->priv->book);
    for (i = 0; i < n_pages; i++) {
        Page *p = book_get_page (view->priv->book, i);
        PageView *page = g_hash_table_lookup (view->priv->page_data, p);

        if (is_inside_crop (page, x, y)) {
            over_crop = TRUE;
            continue;
        }
    }

    /* Move the crop */
    if (view->priv->selected_crop && event->state & GDK_BUTTON1_MASK) {
        gint pw, ph;
        gint cx, cy, cw, ch;
        gint new_x, new_y;
        
        pw = page_get_width (view->priv->selected_crop->page);
        ph = page_get_height (view->priv->selected_crop->page);
        page_get_crop (view->priv->selected_crop->page, &cx, &cy, &cw, &ch);
        new_x = view->priv->selected_crop_x + screen_to_page_x (view->priv->selected_crop, event->x - view->priv->selected_crop_px);
        new_y = view->priv->selected_crop_y + screen_to_page_y (view->priv->selected_crop, event->y - view->priv->selected_crop_py);
        if (new_x < 0)
            new_x = 0;
        if (new_x > pw - cw)
            new_x = pw - cw;
        if (new_y < 0)
            new_y = 0;
        if (new_y > ph - ch)
            new_y = ph - ch;        

        page_move_crop (view->priv->selected_crop->page, new_x, new_y);
    }
    
    // FIXME: Do this in the rendering loop (what if disable/change crop without rotating) */
    if (view->priv->selected_crop || over_crop)
        set_cursor (view, GDK_HAND1);
    else
        set_cursor (view, GDK_ARROW);
   
    return FALSE;
}


static gboolean
key_cb (GtkWidget *widget, GdkEventKey *event, BookView *view)
{
    switch (event->keyval) {
    /* Pan */
    case GDK_Left:
        if (event->state & GDK_CONTROL_MASK)
            book_view_pan (view, 5, 0);
        else
            book_view_select_page (view, get_prev_page (view));
        return TRUE;
    case GDK_Right:
        if (event->state & GDK_CONTROL_MASK)
            book_view_pan (view, -5, 0);
        else
            book_view_select_page (view, get_next_page (view));
        return TRUE;
    case GDK_Up:
        if (event->state & GDK_CONTROL_MASK)
            book_view_pan (view, 0, 5);
        return TRUE;
    case GDK_Down:
        if (event->state & GDK_CONTROL_MASK)
            book_view_pan (view, 0, -5);
        return TRUE;

    /* Zoom */
    case GDK_plus:
    case GDK_equal:
        book_view_set_zoom (view, gtk_adjustment_get_value (view->priv->zoom_adjustment) + 0.1);
        return TRUE;
    case GDK_minus:
        book_view_set_zoom (view, gtk_adjustment_get_value (view->priv->zoom_adjustment) - 0.1);        
        return TRUE;

    default:
        return FALSE;
    }
}


static gboolean
focus_cb (GtkWidget *widget, GdkEventFocus *event, BookView *view)
{
    gtk_widget_queue_draw (view->priv->widget);
    return FALSE;
}


void
book_view_set_widget (BookView *view, GtkWidget *widget, GtkWidget *page_menu)
{
    g_return_if_fail (view->priv->widget == NULL);
    view->priv->widget = widget;
    g_signal_connect (widget, "configure-event", G_CALLBACK (configure_cb), view);
    g_signal_connect (widget, "expose-event", G_CALLBACK (expose_cb), view);
    g_signal_connect (widget, "motion-notify-event", G_CALLBACK (motion_cb), view);
    g_signal_connect (widget, "key-press-event", G_CALLBACK (key_cb), view);
    g_signal_connect (widget, "button-press-event", G_CALLBACK (button_cb), view);
    g_signal_connect (widget, "button-release-event", G_CALLBACK (button_cb), view);
    g_signal_connect (widget, "scroll-event", G_CALLBACK (scroll_cb), view);
    g_signal_connect (widget, "focus-in-event", G_CALLBACK (focus_cb), view);
    g_signal_connect (widget, "focus-out-event", G_CALLBACK (focus_cb), view);
    view->priv->page_menu = page_menu;
}


void
book_view_select_page (BookView *view, Page *page)
{
    if (view->priv->selected_page == page)
        return;

    view->priv->selected_page = page;

    /* Make selected page visible */

    gtk_widget_queue_draw (view->priv->widget);    
    g_signal_emit (view, signals[PAGE_SELECTED], 0, view->priv->selected_page);
}


void
book_view_select_next_page (BookView *view)
{
    book_view_select_page (view, get_next_page (view));
}


void
book_view_select_prev_page (BookView *view)
{
    book_view_select_page (view, get_prev_page (view));
}


Page *
book_view_get_selected (BookView *view)
{
    return view->priv->selected_page;
}


static void
book_view_class_init (BookViewClass *klass)
{
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
                                                   NULL, (GDestroyNotify) page_view_free);
    view->priv->zoom_adjustment = GTK_ADJUSTMENT (gtk_adjustment_new (0.0,
                                                                      0.0, 1.0,
                                                                      0.01,
                                                                      0.1,
                                                                      0));
    g_signal_connect (view->priv->zoom_adjustment, "value-changed", G_CALLBACK (zoom_cb), view);
}
