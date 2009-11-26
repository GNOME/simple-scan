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


typedef struct
{
    Page *page;
    gint width, height;
    GdkPixbuf *image;
    gboolean update_image;
} PageView;


struct BookViewPrivate
{
    Book *book;
    GHashTable *page_data;

    gint width, height;
    gint x_offset, y_offset;
    GtkAdjustment *zoom_adjustment;
    gdouble old_zoom;
    gint selected_page;
    
    GtkWidget *widget;
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


static void
page_updated (Page *page, BookView *view)
{
    PageView *page_view = g_hash_table_lookup (view->priv->page_data, page);
    page_view->update_image = TRUE;
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
page_added (Book *book, Page *page, BookView *view)
{
    g_hash_table_insert (view->priv->page_data, page, page_view_alloc (page));
    g_signal_connect (page, "updated", G_CALLBACK (page_updated), view);
    gtk_widget_queue_draw (view->priv->widget);
}


static void
page_removed (Book *book, Page *page, BookView *view)
{
    g_hash_table_remove (view->priv->page_data, page);
    gtk_widget_queue_draw (view->priv->widget);
}


void
book_view_set_book (BookView *view, Book *book)
{
    gint i, n_pages;

    view->priv->book = book;

    /* Load existing pages */
    n_pages = book_get_n_pages (view->priv->book);
    for (i = 0; i < n_pages; i++) {
        Page *page = book_get_page (book, i);
        page_added (book, page, view);
    }

    /* Watch for new pages */
    g_signal_connect (book, "page-added", G_CALLBACK (page_added), view);
    g_signal_connect (book, "page-removed", G_CALLBACK (page_removed), view);
}


static gboolean
configure_cb (GtkWidget *widget, GdkEventConfigure *event, BookView *view)
{
    view->priv->width = event->width;
    view->priv->height = event->height;
}


void
book_view_pan (BookView *view, gint x_offset, gint y_offset)
{
    view->priv->x_offset += x_offset;
    view->priv->y_offset += y_offset;
    gtk_widget_queue_draw (view->priv->widget);
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


static void
render_page (BookView *view, PageView *page, cairo_t *context,
             gdouble x, gdouble y, gdouble scale,
             gboolean selected)
{
    gint scan_line;

    /* Regenerate page pixbuf */
    update_page_view (page);

    cairo_save (context);

    /* Draw background */
    cairo_translate (context, x, y);
    cairo_translate (context, 1, 1);
    gdk_cairo_set_source_pixbuf (context, page->image, 0, 0);
    cairo_paint (context);
    cairo_translate (context, -1, -1);

    /* Draw page border */
    /* NOTE: Border width and height is rounded up so border is sharp.  Background may not
     * extend to border, should fill with white (?) before drawing scanned image or extend
     * edges slightly */
    if (selected)
        cairo_set_source_rgb (context, 1, 0, 0);
    else
        cairo_set_source_rgb (context, 0, 0, 0);
    cairo_set_line_width (context, 1);
    cairo_rectangle (context, 0.5, 0.5, gdk_pixbuf_get_width (page->image) + 1, gdk_pixbuf_get_height (page->image) + 1);
    cairo_stroke (context);

    /* Draw scan line */
    scan_line = page_get_scan_line (page->page);
    if (scan_line >= 0) {
        double w = gdk_pixbuf_get_width (page->image);
        double h = gdk_pixbuf_get_height (page->image);
        double s = scale * (double) scan_line;
        
        switch (page_get_orientation (page->page)) {
        case TOP_TO_BOTTOM:
            cairo_move_to (context, 0, s);
            cairo_line_to (context, w, s);
            break;
        case BOTTOM_TO_TOP:
            cairo_move_to (context, 0, h - s);
            cairo_line_to (context, w, h - s);
            break;
        case LEFT_TO_RIGHT:
            cairo_move_to (context, s, 0);
            cairo_line_to (context, s, h);
            break;
        case RIGHT_TO_LEFT:
            cairo_move_to (context, w - s, 0);
            cairo_line_to (context, w - s, h);
            break;
        }

        cairo_set_source_rgb (context, 1.0, 0.0, 0.0);
        cairo_stroke (context);
    }
    
    cairo_restore (context);
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

    page->width = width;
    page->height = height;
    page->update_image = TRUE;
}


static gboolean
expose_cb (GtkWidget *widget, GdkEventExpose *event, BookView *view)
{
    cairo_t *context;    
    gint i, n_pages;
    gdouble max_width = 0, max_height = 0;
    gdouble inner_width, inner_height;
    gdouble max_aspect, inner_aspect;
    gdouble border = 1, spacing = 12;
    gdouble book_width = 0, book_height = 0;
    gdouble x_offset = 0, y_offset = 0, scale;
    gdouble x_range = 0, y_range = 0;
    
    n_pages = book_get_n_pages (view->priv->book);
    if (n_pages == 0)
        return FALSE;

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
    
    if (view->priv->x_offset < -x_range)
        view->priv->x_offset = -x_range;
    if (view->priv->x_offset > 0)
        view->priv->x_offset = 0;
    if (view->priv->y_offset < -y_range)
        view->priv->y_offset = -y_range;
    if (view->priv->y_offset > 0)
        view->priv->y_offset = 0;
    
    //printf("x:0 < %f < %f y:0 < %f < %f\n", x_offset, x_range, y_offset, y_range);
    
    x_offset += view->priv->x_offset;
    y_offset += view->priv->y_offset;
    
    context = gdk_cairo_create (widget->window);

    /* Render each page */
    for (i = 0; i < n_pages; i++) {
        Page *p = book_get_page (view->priv->book, i);
        PageView *page = g_hash_table_lookup (view->priv->page_data, p);
        gdouble y;

        y = y_offset;
        render_page (view, page, context, x_offset, y, scale, FALSE);
        x_offset += page->width + (2 * border) + spacing;
    }

    cairo_destroy (context);

    return FALSE;
}

static void
book_view_class_init (BookViewClass *klass)
{
    g_type_class_add_private (klass, sizeof (BookViewPrivate));
}


static void
zoom_cb (GtkAdjustment *adjustment, BookView *view)
{
    gdouble zoom;
    
    zoom = gtk_adjustment_get_value (view->priv->zoom_adjustment);    
    view->priv->x_offset += (zoom - view->priv->old_zoom) * view->priv->width;
    view->priv->y_offset += (zoom - view->priv->old_zoom) * view->priv->height;
    view->priv->old_zoom = zoom;

    gtk_widget_queue_draw (view->priv->widget);
}


static void
book_view_init (BookView *view)
{
    view->priv = G_TYPE_INSTANCE_GET_PRIVATE (view, BOOK_VIEW_TYPE, BookViewPrivate);
    view->priv->page_data = g_hash_table_new_full (g_direct_hash, g_direct_equal,
                                                   NULL, (GDestroyNotify) page_view_free);
    view->priv->selected_page = -1;
    view->priv->zoom_adjustment = GTK_ADJUSTMENT (gtk_adjustment_new (0.0,
                                                                      0.0, 1.0,
                                                                      0.01,
                                                                      0.1,
                                                                      0));
    g_signal_connect (view->priv->zoom_adjustment, "value-changed", G_CALLBACK (zoom_cb), view);
}


static gboolean
button_cb (GtkWidget *widget, GdkEventButton *event, BookView *view)
{
    view->priv->mouse_x = event->x;
    view->priv->mouse_y = event->y;
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
    book_view_pan (view, event->x - view->priv->mouse_x, event->y - view->priv->mouse_y);
    view->priv->mouse_x = event->x;
    view->priv->mouse_y = event->y;
   
    return FALSE;
}


static gboolean
key_cb (GtkWidget *widget, GdkEventKey *event, BookView *view)
{
    switch (event->keyval) {
    /* Pan */
    case GDK_Left:
        book_view_pan (view, 5, 0);
        return TRUE;
    case GDK_Right:
        book_view_pan (view, -5, 0);
        return TRUE;
    case GDK_Up:
        book_view_pan (view, 0, 5);
        return TRUE;
    case GDK_Down:
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

    case GDK_Delete:
        return TRUE;

    default:
        return FALSE;
    }
}


void
book_view_set_widget (BookView *view, GtkWidget *widget)
{
    g_return_if_fail (view->priv->widget == NULL);
    view->priv->widget = widget;
    g_signal_connect (widget, "configure-event", G_CALLBACK (configure_cb), view);
    g_signal_connect (widget, "expose-event", G_CALLBACK (expose_cb), view);
    g_signal_connect (widget, "motion-notify-event", G_CALLBACK (motion_cb), view);
    g_signal_connect (widget, "key-press-event", G_CALLBACK (key_cb), view);
    g_signal_connect (widget, "button-press-event", G_CALLBACK (button_cb), view);
    g_signal_connect (widget, "scroll-event", G_CALLBACK (scroll_cb), view);
}
