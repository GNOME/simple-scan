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

[GtkTemplate (ui = "/org/gnome/SimpleScan/ui/preferences-dialog.ui")]
private class PreferencesDialog : Hdy.PreferencesWindow
{
    private Settings settings;

    [GtkChild]
    private unowned Gtk.ComboBox text_dpi_combo;
    [GtkChild]
    private unowned Gtk.ComboBox photo_dpi_combo;
    [GtkChild]
    private unowned Gtk.ComboBox paper_size_combo;
    [GtkChild]
    private unowned Gtk.Scale brightness_scale;
    [GtkChild]
    private unowned Gtk.Scale contrast_scale;
    [GtkChild]
    private unowned Gtk.RadioButton page_delay_0s_button;
    [GtkChild]
    private unowned Gtk.RadioButton page_delay_3s_button;
    [GtkChild]
    private unowned Gtk.RadioButton page_delay_6s_button;
    [GtkChild]
    private unowned Gtk.RadioButton page_delay_10s_button;
    [GtkChild]
    private unowned Gtk.RadioButton page_delay_15s_button;
    [GtkChild]
    private unowned Gtk.ListStore text_dpi_model;
    [GtkChild]
    private unowned Gtk.ListStore photo_dpi_model;
    [GtkChild]
    private unowned Gtk.RadioButton front_side_button;
    [GtkChild]
    private unowned Gtk.RadioButton back_side_button;
    [GtkChild]
    private unowned Gtk.RadioButton both_side_button;
    [GtkChild]
    private unowned Gtk.ListStore paper_size_model;
    [GtkChild]
    private unowned Gtk.Adjustment brightness_adjustment;
    [GtkChild]
    private unowned Gtk.Adjustment contrast_adjustment;
    [GtkChild]
    private unowned Gtk.Switch postproc_enable_switch;
    [GtkChild]
    private unowned Gtk.Entry postproc_script_entry;
    [GtkChild]
    private unowned Gtk.Entry postproc_args_entry;
    [GtkChild]
    private unowned Gtk.Switch postproc_keep_original_switch;

    public PreferencesDialog (Settings settings)
    {
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

        set_page_side ((ScanSide) settings.get_enum ("page-side"));
        front_side_button.toggled.connect ((button) => { if (button.active) settings.set_enum ("page-side", ScanSide.FRONT); });
        back_side_button.toggled.connect ((button) => { if (button.active) settings.set_enum ("page-side", ScanSide.BACK); });
        both_side_button.toggled.connect ((button) => { if (button.active) settings.set_enum ("page-side", ScanSide.BOTH); });

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
        page_delay_0s_button.toggled.connect ((button) => { if (button.active) settings.set_int ("page-delay", 0); });
        page_delay_3s_button.toggled.connect ((button) => { if (button.active) settings.set_int ("page-delay", 3000); });
        page_delay_6s_button.toggled.connect ((button) => { if (button.active) settings.set_int ("page-delay", 6000); });
        page_delay_10s_button.toggled.connect ((button) => { if (button.active) settings.set_int ("page-delay", 10000); });
        page_delay_15s_button.toggled.connect ((button) => { if (button.active) settings.set_int ("page-delay", 15000); });

        // Postprocessing settings
        var postproc_enabled = settings.get_boolean ("postproc-enabled");
        postproc_enable_switch.set_state(postproc_enabled);
        toggle_postproc_visibility (postproc_enabled);
        postproc_enable_switch.state_set.connect ((is_active) => {  toggle_postproc_visibility (is_active);
                                                                    settings.set_boolean("postproc-enabled", is_active);
                                                                    return true; });

        var postproc_script = settings.get_string("postproc-script");
        postproc_script_entry.set_text(postproc_script);
        postproc_script_entry.changed.connect (() => { settings.set_string("postproc-script", postproc_script_entry.get_text()); });

        var postproc_arguments = settings.get_string("postproc-arguments");
        postproc_args_entry.set_text(postproc_arguments);
        postproc_args_entry.changed.connect (() => { settings.set_string("postproc-arguments", postproc_args_entry.get_text()); });

        var postproc_keep_original = settings.get_boolean ("postproc-keep-original");
        postproc_keep_original_switch.set_state(postproc_keep_original);
        postproc_keep_original_switch.state_set.connect ((is_active) => {   settings.set_boolean("postproc-keep-original", is_active);
                                                                            return true; });
    }

    private void toggle_postproc_visibility(bool enabled) {
        postproc_script_entry.get_parent ().get_parent ().get_parent ().get_parent ().set_visible(enabled);
        postproc_args_entry.get_parent ().get_parent ().get_parent ().get_parent ().set_visible(enabled);
        postproc_keep_original_switch.get_parent ().get_parent ().get_parent ().get_parent ().set_visible(enabled);
    }

    private void set_page_side (ScanSide page_side)
    {
        switch (page_side)
        {
        case ScanSide.FRONT:
            front_side_button.active = true;
            break;
        case ScanSide.BACK:
            back_side_button.active = true;
            break;
        default:
        case ScanSide.BOTH:
            both_side_button.active = true;
            break;
        }
    }

    public ScanSide get_page_side ()
    {
        if (front_side_button.active)
            return ScanSide.FRONT;
        else if (back_side_button.active)
            return ScanSide.BACK;
        else
            return ScanSide.BOTH;
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
        else if (page_delay_6s_button.active)
            return 6000;
        else if (page_delay_3s_button.active)
            return 3000;
        else
            return 0;
    }

    public void set_page_delay (int page_delay)
    {
        if (page_delay >= 15000)
            page_delay_15s_button.active = true;
        else if (page_delay >= 10000)
            page_delay_10s_button.active = true;
        else if (page_delay >= 6000)
            page_delay_6s_button.active = true;
        else if (page_delay >= 3000)
            page_delay_3s_button.active = true;
        else
            page_delay_0s_button.active = true;
    }

    private void set_dpi_combo (Gtk.ComboBox combo, int default_dpi, int current_dpi)
    {
        var renderer = new Gtk.CellRendererText ();
        combo.pack_start (renderer, true);
        combo.add_attribute (renderer, "text", 1);

        var model = combo.model as Gtk.ListStore;
        int[] scan_resolutions = {75, 150, 200, 300, 600, 1200, 2400};
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
