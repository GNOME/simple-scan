/*
 * Copyright (C) 2009-2017 Canonical Ltd.
 * Author: Robert Ancell <robert.ancell@canonical.com>,
 *         Eduard Gotwig <g@ox.io>
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later
 * version. See http://www.gnu.org/copyleft/gpl.html the full text of the
 * license.
 */

[GtkTemplate (ui = "/org/gnome/SimpleScan/preferences-dialog.ui")]
private class PreferencesDialog : Gtk.Dialog
{
    private Settings settings;

    [GtkChild]
    private Gtk.ComboBox text_dpi_combo;
    [GtkChild]
    private Gtk.ComboBox photo_dpi_combo;
    [GtkChild]
    private Gtk.ComboBox paper_size_combo;
    [GtkChild]
    private Gtk.Scale brightness_scale;
    [GtkChild]
    private Gtk.Scale contrast_scale;
    [GtkChild]
    private Gtk.RadioButton page_delay_3s_button;
    [GtkChild]
    private Gtk.RadioButton page_delay_5s_button;
    [GtkChild]
    private Gtk.RadioButton page_delay_7s_button;
    [GtkChild]
    private Gtk.RadioButton page_delay_10s_button;
    [GtkChild]
    private Gtk.RadioButton page_delay_15s_button;
    [GtkChild]
    private Gtk.ListStore text_dpi_model;
    [GtkChild]
    private Gtk.ListStore photo_dpi_model;
    [GtkChild]
    private Gtk.RadioButton front_side_button;
    [GtkChild]
    private Gtk.RadioButton back_side_button;
    [GtkChild]
    private Gtk.RadioButton both_side_button;
    [GtkChild]
    private Gtk.ListStore paper_size_model;
    [GtkChild]
    private Gtk.Adjustment brightness_adjustment;
    [GtkChild]
    private Gtk.Adjustment contrast_adjustment;

    public PreferencesDialog (Settings settings)
    {
        Object (use_header_bar: 1);

        this.settings = settings;

        Gtk.TreeIter iter;
        paper_size_model.append (out iter);
        paper_size_model.set (iter, 0, 0, 1, 0, 2,
                              /* Combo box value for automatic paper size */
                              _("Automatic"), -1);
        paper_size_model.append (out iter);
        paper_size_model.set (iter, 0, 1050, 1, 1480, 2, "A6", -1);
        paper_size_model.append (out iter);
        paper_size_model.set (iter, 0, 1480, 1, 2100, 2, "A5", -1);
        paper_size_model.append (out iter);
        paper_size_model.set (iter, 0, 2100, 1, 2970, 2, "A4", -1);
        paper_size_model.append (out iter);
        paper_size_model.set (iter, 0, 2970, 1, 4200, 2, "A3", -1);
        paper_size_model.append (out iter);
        paper_size_model.set (iter, 0, 2159, 1, 2794, 2, "Letter", -1);
        paper_size_model.append (out iter);
        paper_size_model.set (iter, 0, 2159, 1, 3556, 2, "Legal", -1);
        paper_size_model.append (out iter);
        paper_size_model.set (iter, 0, 1016, 1, 1524, 2, "4×6", -1);

        var dpi = settings.get_int ("text-dpi");
        if (dpi <= 0)
            dpi = DEFAULT_TEXT_DPI;
        set_dpi_combo (text_dpi_combo, DEFAULT_TEXT_DPI, dpi);
        text_dpi_combo.changed.connect (() => { settings.set_int ("text-dpi", get_text_dpi ()); });
        dpi = settings.get_int ("photo-dpi");
        if (dpi <= 0)
            dpi = DEFAULT_PHOTO_DPI;
        set_dpi_combo (photo_dpi_combo, DEFAULT_PHOTO_DPI, dpi);
        photo_dpi_combo.changed.connect (() => { settings.set_int ("photo-dpi", get_photo_dpi ()); });

        set_page_side ((ScanType) settings.get_enum ("page-side"));
        front_side_button.toggled.connect ((button) => { if (button.active) settings.set_enum ("page-side", ScanType.ADF_FRONT); });
        back_side_button.toggled.connect ((button) => { if (button.active) settings.set_enum ("page-side", ScanType.ADF_BACK); });
        both_side_button.toggled.connect ((button) => { if (button.active) settings.set_enum ("page-side", ScanType.ADF_BOTH); });

        var renderer = new Gtk.CellRendererText ();
        paper_size_combo.pack_start (renderer, true);
        paper_size_combo.add_attribute (renderer, "text", 2);

        var lower = brightness_adjustment.lower;
        var darker_label = "<small>%s</small>".printf (_("Darker"));
        var upper = brightness_adjustment.upper;
        var lighter_label = "<small>%s</small>".printf (_("Lighter"));
        brightness_scale.add_mark (lower, Gtk.PositionType.BOTTOM, darker_label);
        brightness_scale.add_mark (0, Gtk.PositionType.BOTTOM, null);
        brightness_scale.add_mark (upper, Gtk.PositionType.BOTTOM, lighter_label);
        brightness_adjustment.value = settings.get_int ("brightness");
        brightness_adjustment.value_changed.connect (() => { settings.set_int ("brightness", get_brightness ()); });

        lower = contrast_adjustment.lower;
        var less_label = "<small>%s</small>".printf (_("Less"));
        upper = contrast_adjustment.upper;
        var more_label = "<small>%s</small>".printf (_("More"));
        contrast_scale.add_mark (lower, Gtk.PositionType.BOTTOM, less_label);
        contrast_scale.add_mark (0, Gtk.PositionType.BOTTOM, null);
        contrast_scale.add_mark (upper, Gtk.PositionType.BOTTOM, more_label);
        contrast_adjustment.value = settings.get_int ("contrast");
        contrast_adjustment.value_changed.connect (() => { settings.set_int ("contrast", get_contrast ()); });

        var paper_width = settings.get_int ("paper-width");
        var paper_height = settings.get_int ("paper-height");
        set_paper_size (paper_width, paper_height);
        paper_size_combo.changed.connect (() =>
        {
            int w, h;
            get_paper_size (out w, out h);
            settings.set_int ("paper-width", w);
            settings.set_int ("paper-height", h);
        });

        set_page_delay (settings.get_int ("page-delay"));
        page_delay_3s_button.toggled.connect ((button) => { if (button.active) settings.set_int ("page-delay", 3000); });
        page_delay_5s_button.toggled.connect ((button) => { if (button.active) settings.set_int ("page-delay", 5000); });
        page_delay_7s_button.toggled.connect ((button) => { if (button.active) settings.set_int ("page-delay", 7000); });
        page_delay_10s_button.toggled.connect ((button) => { if (button.active) settings.set_int ("page-delay", 10000); });
        page_delay_15s_button.toggled.connect ((button) => { if (button.active) settings.set_int ("page-delay", 15000); });
    }

    private void set_page_side (ScanType page_side)
    {
        switch (page_side)
        {
        case ScanType.ADF_FRONT:
            front_side_button.active = true;
            break;
        case ScanType.ADF_BACK:
            back_side_button.active = true;
            break;
        default:
        case ScanType.ADF_BOTH:
            both_side_button.active = true;
            break;
        }
    }

    public ScanType get_page_side ()
    {
        if (front_side_button.active)
            return ScanType.ADF_FRONT;
        else if (back_side_button.active)
            return ScanType.ADF_BACK;
        else
            return ScanType.ADF_BOTH;
    }

    public void set_paper_size (int width, int height)
    {
        Gtk.TreeIter iter;
        bool have_iter;

        for (have_iter = paper_size_model.get_iter_first (out iter);
             have_iter;
             have_iter = paper_size_model.iter_next (ref iter))
        {
            int w, h;
            paper_size_model.get (iter, 0, out w, 1, out h, -1);
            if (w == width && h == height)
               break;
        }

        if (!have_iter)
            have_iter = paper_size_model.get_iter_first (out iter);
        if (have_iter)
            paper_size_combo.set_active_iter (iter);
    }

    public int get_text_dpi ()
    {
        Gtk.TreeIter iter;
        int dpi = DEFAULT_TEXT_DPI;

        if (text_dpi_combo.get_active_iter (out iter))
            text_dpi_model.get (iter, 0, out dpi, -1);

        return dpi;
    }

    public int get_photo_dpi ()
    {
        Gtk.TreeIter iter;
        int dpi = DEFAULT_PHOTO_DPI;

        if (photo_dpi_combo.get_active_iter (out iter))
            photo_dpi_model.get (iter, 0, out dpi, -1);

        return dpi;
    }

    public bool get_paper_size (out int width, out int height)
    {
        Gtk.TreeIter iter;

        width = height = 0;
        if (paper_size_combo.get_active_iter (out iter))
        {
            paper_size_model.get (iter, 0, ref width, 1, ref height, -1);
            return true;
        }

        return false;
    }

    public int get_brightness ()
    {
        return (int) brightness_adjustment.value;
    }

    public void set_brightness (int brightness)
    {
        brightness_adjustment.value = brightness;
    }

    public int get_contrast ()
    {
        return (int) contrast_adjustment.value;
    }

    public void set_contrast (int contrast)
    {
        contrast_adjustment.value = contrast;
    }

    public int get_page_delay ()
    {
        if (page_delay_15s_button.active)
            return 15000;
        else if (page_delay_10s_button.active)
            return 10000;
        else if (page_delay_7s_button.active)
            return 7000;
        else if (page_delay_5s_button.active)
            return 5000;
        else
            return 3000;
    }

    public void set_page_delay (int page_delay)
    {
        if (page_delay >= 15000)
            page_delay_15s_button.active = true;
        else if (page_delay >= 10000)
            page_delay_10s_button.active = true;
        else if (page_delay >= 7000)
            page_delay_7s_button.active = true;
        else if (page_delay >= 5000)
            page_delay_5s_button.active = true;
        else
            page_delay_3s_button.active = true;
    }

    private void set_dpi_combo (Gtk.ComboBox combo, int default_dpi, int current_dpi)
    {
        var renderer = new Gtk.CellRendererText ();
        combo.pack_start (renderer, true);
        combo.add_attribute (renderer, "text", 1);

        var model = combo.model as Gtk.ListStore;
        int[] scan_resolutions = {75, 150, 300, 600, 1200, 2400};
        foreach (var dpi in scan_resolutions)
        {
            string label;
            if (dpi == default_dpi)
                /* Preferences dialog: Label for default resolution in resolution list */
                label = _("%d dpi (default)").printf (dpi);
            else if (dpi == 75)
                /* Preferences dialog: Label for minimum resolution in resolution list */
                label = _("%d dpi (draft)").printf (dpi);
            else if (dpi == 1200)
                /* Preferences dialog: Label for maximum resolution in resolution list */
                label = _("%d dpi (high resolution)").printf (dpi);
            else
                /* Preferences dialog: Label for resolution value in resolution list (dpi = dots per inch) */
                label = _("%d dpi").printf (dpi);

            Gtk.TreeIter iter;
            model.append (out iter);
            model.set (iter, 0, dpi, 1, label, -1);

            if (dpi == current_dpi)
                combo.set_active_iter (iter);
        }
    }
}
