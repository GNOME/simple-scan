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

#include <math.h>

#include "page-view.h"

enum {
    CHANGED,
    LAST_SIGNAL
};
static guint signals[LAST_SIGNAL] = { 0, };

typedef enum
{
    CROP_NONE = 0,
    CROP_MIDDLE,
    CROP_TOP,
    CROP_BOTTOM,
    CROP_LEFT,
    CROP_RIGHT,
    CROP_TOP_LEFT,
    CROP_TOP_RIGHT,
    CROP_BOTTOM_LEFT,
    CROP_BOTTOM_RIGHT
} CropLocation;

struct PageViewPrivate
{
    /* Page being rendered */
    Page *page;

    /* Image to render at current resolution */
    GdkPixbuf *image;
  
    /* Border around image */
    gboolean selected;
    gint border_width;

    /* True if image needs to be regenerated */
    gboolean update_image;

    /* Dimensions of image to generate */
    gint width, height;

    /* Location to place this page */
    gint x, y;

    CropLocation crop_location;
    gdouble selected_crop_px, selected_crop_py;
    gint selected_crop_x, selected_crop_y;
    gint selected_crop_w, selected_crop_h;

    /* Cursor over this page */
    gint cursor;

    gint animate_n_segments, animate_segment;
    guint animate_timeout;
};

G_DEFINE_TYPE (PageView, page_view, G_TYPE_OBJECT);


PageView *
page_view_new (void)
{
    return g_object_new (PAGE_VIEW_TYPE, NULL);
}


Page *
page_view_get_page (PageView *view)
{
    g_return_val_if_fail (view != NULL, NULL);
    return view->priv->page;
}


void
page_view_set_selected (PageView *view, gboolean selected)
{
    g_return_if_fail (view != NULL);
    if ((view->priv->selected && selected) || (!view->priv->selected && !selected))
        return;
    view->priv->selected = selected;
    g_signal_emit (view, signals[CHANGED], 0);  
}


void
page_view_set_x_offset (PageView *view, gint offset)
{
    g_return_if_fail (view != NULL);
    view->priv->x = offset;
}


void
page_view_set_y_offset (PageView *view, gint offset)
{
    g_return_if_fail (view != NULL);
    view->priv->y = offset;
}


gint
page_view_get_x_offset (PageView *view)
{
    g_return_val_if_fail (view != NULL, 0);  
    return view->priv->x;  
}


gint
page_view_get_y_offset (PageView *view)
{
    g_return_val_if_fail (view != NULL, 0);
    return view->priv->y;
}


static void
update_page_view (PageView *view)
{
    GdkPixbuf *image;

    if (!view->priv->update_image)
        return;

    if (view->priv->image)
        g_object_unref (view->priv->image);
    image = page_get_image (view->priv->page);

    // FIXME: Only scale changed part onto existing image
    view->priv->image = gdk_pixbuf_scale_simple (image,
                                                 view->priv->width - view->priv->border_width * 2,
                                                 view->priv->height - view->priv->border_width * 2,
                                                 GDK_INTERP_BILINEAR);
    g_object_unref (image);

    view->priv->update_image = FALSE;
}


static gint
page_to_screen_x (PageView *view, gint x)
{
    return (double) x * gdk_pixbuf_get_width (view->priv->image) / page_get_width (view->priv->page) + 0.5;
}


static gint
page_to_screen_y (PageView *view, gint y)
{
    return (double) y * gdk_pixbuf_get_height (view->priv->image) / page_get_height (view->priv->page) + 0.5;    
}


static gint
screen_to_page_x (PageView *view, gint x)
{
    return (double) x * page_get_width (view->priv->page) / gdk_pixbuf_get_width (view->priv->image) + 0.5;
}


static gint
screen_to_page_y (PageView *view, gint y)
{
    return (double) y * page_get_height (view->priv->page) / gdk_pixbuf_get_height (view->priv->image) + 0.5;
}


static CropLocation
get_crop_location (PageView *view, gint x, gint y)
{
    gint cx, cy, cw, ch;
    gint dx, dy, dw, dh;
    gint ix, iy;
    gint crop_border = 20;
    gchar *name;

    if (!page_has_crop (view->priv->page))
        return 0;

    page_get_crop (view->priv->page, &cx, &cy, &cw, &ch);
    dx = page_to_screen_x (view, cx) + view->priv->x;
    dy = page_to_screen_y (view, cy) + view->priv->y;
    dw = page_to_screen_x (view, cw);
    dh = page_to_screen_y (view, ch);
    ix = x - dx;
    iy = y - dy;

    if (ix < 0 || ix > dw || iy < 0 || iy > dh)
        return CROP_NONE;

    /* Can't resize named crops */
    name = page_get_named_crop (view->priv->page);
    if (name != NULL) {
        g_free (name);
        return CROP_MIDDLE;
    }

    // FIXME: Adjust edges when small

    /* Top left */
    if (ix < crop_border && iy < crop_border)
        return CROP_TOP_LEFT;
    /* Top right */
    if (ix > dw - crop_border && iy < crop_border)
        return CROP_TOP_RIGHT;
    /* Bottom left */
    if (ix < crop_border && iy > dh - crop_border)
        return CROP_BOTTOM_LEFT;
    /* Bottom right */
    if (ix > dw - crop_border && iy > dh - crop_border)
        return CROP_BOTTOM_RIGHT;

    /* Left */
    if (ix < crop_border)
        return CROP_LEFT;
    /* Right */
    if (ix > dw - crop_border)
        return CROP_RIGHT;
    /* Top */
    if (iy < crop_border)
        return CROP_TOP;
    /* Bottom */
    if (iy > dh - crop_border)
        return CROP_BOTTOM;

    /* In the middle */
    return CROP_MIDDLE;
}


void
page_view_button_press (PageView *view, gint x, gint y)
{
    CropLocation location;

    g_return_if_fail (view != NULL);

    /* See if selecting crop */
    location = get_crop_location (view, x, y);;
    if (location != CROP_NONE) {
        view->priv->crop_location = location;
        view->priv->selected_crop_px = x;
        view->priv->selected_crop_py = y;
        page_get_crop (view->priv->page,
                       &view->priv->selected_crop_x,
                       &view->priv->selected_crop_y,
                       &view->priv->selected_crop_w,
                       &view->priv->selected_crop_h);
    }
}


void
page_view_motion (PageView *view, gint x, gint y)
{
    gint pw, ph;
    gint cx, cy, cw, ch, dx, dy;
    gint new_x, new_y, new_w, new_h;
    CropLocation location;
    gint cursor;

    g_return_if_fail (view != NULL);
  
    location = get_crop_location (view, x, y);
    switch (location) {
    case CROP_MIDDLE:
        cursor = GDK_HAND1;
        break;
    case CROP_TOP:
        cursor = GDK_TOP_SIDE;
        break;
    case CROP_BOTTOM:
        cursor = GDK_BOTTOM_SIDE;
        break;
    case CROP_LEFT:
        cursor = GDK_LEFT_SIDE;
        break;
    case CROP_RIGHT:
        cursor = GDK_RIGHT_SIDE;
        break;
    case CROP_TOP_LEFT:
        cursor = GDK_TOP_LEFT_CORNER;
        break;
    case CROP_TOP_RIGHT:
        cursor = GDK_TOP_RIGHT_CORNER;
        break;
    case CROP_BOTTOM_LEFT:
        cursor = GDK_BOTTOM_LEFT_CORNER;
        break;
    case CROP_BOTTOM_RIGHT:
        cursor = GDK_BOTTOM_RIGHT_CORNER;
        break;
    default:
        cursor = GDK_ARROW;
        break;
    }

    if (view->priv->crop_location == CROP_NONE) {
        view->priv->cursor = cursor;
        return;
    }

    /* Move the crop */  
    pw = page_get_width (view->priv->page);
    ph = page_get_height (view->priv->page);
    page_get_crop (view->priv->page, &cx, &cy, &cw, &ch);

    dx = screen_to_page_x (view, x - view->priv->selected_crop_px);
    dy = screen_to_page_y (view, y - view->priv->selected_crop_py);

    new_x = view->priv->selected_crop_x;
    new_y = view->priv->selected_crop_y;
    new_w = view->priv->selected_crop_w;
    new_h = view->priv->selected_crop_h;

    if (view->priv->crop_location == CROP_TOP_LEFT ||
        view->priv->crop_location == CROP_LEFT ||
        view->priv->crop_location == CROP_BOTTOM_LEFT) {
        if (dx > new_w + 1)
            dx = new_w + 1;
        if (new_x + dx < 0)
            dx = -new_x;
    }
    if (view->priv->crop_location == CROP_TOP_LEFT ||
        view->priv->crop_location == CROP_TOP ||
        view->priv->crop_location == CROP_TOP_RIGHT) {
        if (dy > new_h + 1)
            dy = new_h + 1;
        if (new_y + dy < 0)
            dy = -new_y;
    }
     
    if (view->priv->crop_location == CROP_TOP_RIGHT ||
        view->priv->crop_location == CROP_RIGHT ||
        view->priv->crop_location == CROP_BOTTOM_RIGHT) {
        if (new_w - dx < 1)
            dx = new_w - 1;
        if (new_x + new_w + dx > pw)
            dx = pw - new_x - new_w;
    }
    if (view->priv->crop_location == CROP_BOTTOM_LEFT ||
        view->priv->crop_location == CROP_BOTTOM ||
        view->priv->crop_location == CROP_BOTTOM_RIGHT) {
        if (new_h - dy < 1)
            dy = new_h - 1;
        if (new_y + new_h + dy > ph)
            dy = ph - new_y - new_h;
    }

    if (view->priv->crop_location == CROP_MIDDLE) {
        new_x += dx;
        new_y += dy;          
    }
    if (view->priv->crop_location == CROP_TOP_LEFT ||
        view->priv->crop_location == CROP_LEFT ||
        view->priv->crop_location == CROP_BOTTOM_LEFT) 
    {
        new_x += dx;
        new_w -= dx;
    }
    if (view->priv->crop_location == CROP_TOP_LEFT ||
        view->priv->crop_location == CROP_TOP ||
        view->priv->crop_location == CROP_TOP_RIGHT) {
        new_y += dy;
        new_h -= dy;
    }
 
    if (view->priv->crop_location == CROP_TOP_RIGHT ||
        view->priv->crop_location == CROP_RIGHT ||
        view->priv->crop_location == CROP_BOTTOM_RIGHT) {
        new_w += dx;
    }
    if (view->priv->crop_location == CROP_BOTTOM_LEFT ||
        view->priv->crop_location == CROP_BOTTOM ||
        view->priv->crop_location == CROP_BOTTOM_RIGHT) {
        new_h += dy;
    }

    if (new_w < 1)
        new_w = 1;
    if (new_h < 1)
        new_h = 1;

    if (new_x > pw - cw)
        new_x = pw - cw;
    if (new_x < 0)
        new_x = 0;
    if (new_y > ph - ch)
        new_y = ph - ch;
    if (new_y < 0)
        new_y = 0;

    page_move_crop (view->priv->page, new_x, new_y);
    if (new_w != cw || new_h != ch)
        page_set_custom_crop (view->priv->page, new_w, new_h);
}


void
page_view_button_release (PageView *view, gint x, gint y)
{
    g_return_if_fail (view != NULL);

    /* Complete crop */
    view->priv->crop_location = CROP_NONE;
    g_signal_emit (view, signals[CHANGED], 0);
}


gint
page_view_get_cursor (PageView *view)
{
    g_return_val_if_fail (view != NULL, 0);
    return view->priv->cursor;
}


static gboolean
animation_cb (PageView *view)
{
    view->priv->animate_segment = (view->priv->animate_segment + 1) % view->priv->animate_n_segments;
    g_signal_emit (view, signals[CHANGED], 0);
    return TRUE;
}


static void
update_animation (PageView *view)
{
    gboolean animate, is_animating;
  
    animate = page_get_scan_line (view->priv->page) == 0;
    is_animating = view->priv->animate_timeout != 0;
    if (animate == is_animating)
        return;
  
    if (animate) {
        view->priv->animate_segment = 0;
        if (view->priv->animate_timeout == 0)
            view->priv->animate_timeout = g_timeout_add (150, (GSourceFunc) animation_cb, view);
    }
    else
    {
        if (view->priv->animate_timeout != 0)
            g_source_remove (view->priv->animate_timeout);
        view->priv->animate_timeout = 0;
    }
}


void
page_view_render (PageView *view, cairo_t *context)
{
    gint scan_line;
    gint width, height;

    g_return_if_fail (view != NULL);
  
    update_animation (view);

    /* Regenerate page pixbuf */
    update_page_view (view);
    width = gdk_pixbuf_get_width (view->priv->image);
    height = gdk_pixbuf_get_height (view->priv->image);

    cairo_set_line_width (context, 1);
    cairo_translate (context, view->priv->x, view->priv->y);

    /* Draw page border */
    if (view->priv->selected)
        cairo_set_source_rgb (context, 1, 0, 0);
    else
        cairo_set_source_rgb (context, 0, 0, 0);
    cairo_set_line_width (context, view->priv->border_width);
    cairo_rectangle (context,
                     (double)view->priv->border_width / 2,
                     (double)view->priv->border_width / 2,
                     view->priv->width - view->priv->border_width,
                     view->priv->height - view->priv->border_width);
    cairo_stroke (context);

    /* Draw image */
    cairo_translate (context, view->priv->border_width, view->priv->border_width);
    gdk_cairo_set_source_pixbuf (context, view->priv->image, 0, 0);
    cairo_paint (context);

    /* Draw throbber */
    scan_line = page_get_scan_line (view->priv->page);
    if (scan_line == 0) {
        gdouble inner_radius, outer_radius, x, y, arc, offset = 0.0;
        gint i;

        if (width > height)
            outer_radius = 0.15 * width;
        else
            outer_radius = 0.15 * height;
        arc = M_PI / view->priv->animate_n_segments;

        /* Space circles */
        x = outer_radius * sin (arc);
        y = outer_radius * (cos (arc) - 1.0);
        inner_radius = 0.6 * sqrt (x*x + y*y);

        for (i = 0; i < view->priv->animate_n_segments; i++, offset += arc * 2) {
            x = width / 2 + outer_radius * sin (offset);
            y = height / 2 - outer_radius * cos (offset);
            cairo_arc (context, x, y, inner_radius, 0, 2 * M_PI);

            if (i == view->priv->animate_segment) {
                cairo_set_source_rgb (context, 0.75, 0.75, 0.75);
                cairo_fill_preserve (context);
            }

            cairo_set_source_rgb (context, 0.5, 0.5, 0.5);
            cairo_stroke (context);
        }
    }

    /* Draw scan line */
    if (scan_line > 0) {
        double s;
        double x1, y1, x2, y2;
        
        switch (page_get_orientation (view->priv->page)) {
        case TOP_TO_BOTTOM:
            s = page_to_screen_y (view, scan_line);
            x1 = 0; y1 = s + 0.5;
            x2 = width; y2 = s + 0.5;
            break;
        case BOTTOM_TO_TOP:
            s = page_to_screen_y (view, scan_line);
            x1 = 0; y1 = height - s + 0.5;
            x2 = width; y2 = height - s + 0.5;
            break;
        case LEFT_TO_RIGHT:
            s = page_to_screen_x (view, scan_line);
            x1 = s + 0.5; y1 = 0;
            x2 = s + 0.5; y2 = height;
            break;
        case RIGHT_TO_LEFT:
            s = page_to_screen_x (view, scan_line);
            x1 = width - s + 0.5; y1 = 0;
            x2 = width - s + 0.5; y2 = height;
            break;
        default:
            x1 = y1 = x2 = y2 = 0;
            break;
        }

        cairo_move_to (context, x1, y1);
        cairo_line_to (context, x2, y2);
        cairo_set_source_rgb (context, 1.0, 0.0, 0.0);
        cairo_stroke (context);
    }
    
    /* Draw crop */
    if (page_has_crop (view->priv->page)) {
        gint x, y, crop_width, crop_height;
        gdouble dx, dy, dw, dh;

        page_get_crop (view->priv->page, &x, &y, &crop_width, &crop_height);

        dx = page_to_screen_x (view, x);
        dy = page_to_screen_y (view, y);
        dw = page_to_screen_x (view, crop_width);
        dh = page_to_screen_y (view, crop_height);
        
        /* Shade out cropped area */
        cairo_rectangle (context,
                         0, 0,
                         width, height);
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
}


void
page_view_set_width (PageView *view, gint width)
{
    gint height;

    g_return_if_fail (view != NULL);

    // FIXME: Automatically update when get updated image
    height = (double)width * page_get_height (view->priv->page) / page_get_width (view->priv->page);
    view->priv->width = width;
    view->priv->height = height;
  
    /* Regenerate image */
    view->priv->update_image = TRUE;
    g_signal_emit (view, signals[CHANGED], 0);
}


void
page_view_set_height (PageView *view, gint height)
{
    gint width;

    g_return_if_fail (view != NULL);

    // FIXME: Automatically update when get updated image
    width = (double)height * page_get_width (view->priv->page) / page_get_height (view->priv->page);
    view->priv->width = width;
    view->priv->height = height;
  
    /* Regenerate image */
    view->priv->update_image = TRUE;
    g_signal_emit (view, signals[CHANGED], 0);
}


gint
page_view_get_width (PageView *view)
{
    g_return_val_if_fail (view != NULL, 0);
    return view->priv->width;
}


gint
page_view_get_height (PageView *view)
{
    g_return_val_if_fail (view != NULL, 0);
    return view->priv->height;
}


static void
page_image_changed_cb (Page *p, PageView *view)
{
    /* Regenerate image */
    view->priv->update_image = TRUE;
    g_signal_emit (view, signals[CHANGED], 0);
}


static void
page_overlay_changed_cb (Page *p, PageView *view)
{
    g_signal_emit (view, signals[CHANGED], 0);
}


void
page_view_set_page (PageView *view, Page *page)
{
    g_return_if_fail (view != NULL);
    g_return_if_fail (view->priv->page == NULL);

    view->priv->page = g_object_ref (page);
    g_signal_connect (view->priv->page, "image-changed", G_CALLBACK (page_image_changed_cb), view);
    g_signal_connect (view->priv->page, "orientation-changed", G_CALLBACK (page_image_changed_cb), view);
    g_signal_connect (view->priv->page, "crop-changed", G_CALLBACK (page_overlay_changed_cb), view);
}


static void
page_view_finalize (GObject *object)
{
    PageView *view = PAGE_VIEW (object);
    g_object_unref (view->priv->page);
    view->priv->page = NULL;
    if (view->priv->image)
        g_object_unref (view->priv->image);
    view->priv->image = NULL;
    G_OBJECT_CLASS (page_view_parent_class)->finalize (object);
}


static void
page_view_class_init (PageViewClass *klass)
{
    GObjectClass *object_class = G_OBJECT_CLASS (klass);

    object_class->finalize = page_view_finalize;

    signals[CHANGED] =
        g_signal_new ("changed",
                      G_TYPE_FROM_CLASS (klass),
                      G_SIGNAL_RUN_LAST,
                      G_STRUCT_OFFSET (PageViewClass, changed),
                      NULL, NULL,
                      g_cclosure_marshal_VOID__VOID,
                      G_TYPE_NONE, 0);

    g_type_class_add_private (klass, sizeof (PageViewPrivate));
}


static void
page_view_init (PageView *view)
{
    view->priv = G_TYPE_INSTANCE_GET_PRIVATE (view, PAGE_VIEW_TYPE, PageViewPrivate);
    view->priv->update_image = TRUE;
    view->priv->cursor = GDK_ARROW;
    view->priv->border_width = 1;
    view->priv->animate_n_segments = 7;
}
