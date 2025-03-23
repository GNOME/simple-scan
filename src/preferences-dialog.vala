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

private class DpiItem: Object
{
    public int dpi;
    public string label;
    
    public DpiItem(int dpi, string label)
    {
        this.dpi = dpi;
        this.label = label;
    }
}

private class PaperSizeItem: Object
{
    public string label;
    public int width;
    public int height;
    
    public PaperSizeItem(string label, int width, int height)
    {
        this.label = label;
        this.width = width;
        this.height = height;
    }
}

[GtkTemplate (ui = "/org/gnome/SimpleScan/ui/preferences-dialog.ui")]
private class PreferencesDialog : Adw.PreferencesDialog
{
    private Settings settings;

    [GtkChild]
    private unowned Adw.ComboRow text_dpi_row;
    [GtkChild]
    private unowned Adw.ComboRow photo_dpi_row;
    [GtkChild]
    private unowned Adw.ComboRow paper_size_row;
    [GtkChild]
    private unowned Gtk.Scale brightness_scale;
    [GtkChild]
    private unowned Gtk.Scale contrast_scale;
    [GtkChild]
    private unowned Gtk.Scale compression_scale;
    [GtkChild]
    private unowned Gtk.ToggleButton page_delay_0s_button;
    [GtkChild]
    private unowned Gtk.ToggleButton page_delay_3s_button;
    [GtkChild]
    private unowned Gtk.ToggleButton page_delay_6s_button;
    [GtkChild]
    private unowned Gtk.ToggleButton page_delay_10s_button;
    [GtkChild]
    private unowned Gtk.ToggleButton page_delay_15s_button;
    private ListStore text_dpi_model;
    private ListStore photo_dpi_model;
    [GtkChild]
    private unowned Gtk.ToggleButton front_side_button;
    [GtkChild]
    private unowned Gtk.ToggleButton back_side_button;
    [GtkChild]
    private unowned Gtk.ToggleButton both_side_button;
    private ListStore paper_size_model;
    [GtkChild]
    private unowned Gtk.Adjustment brightness_adjustment;
    [GtkChild]
    private unowned Gtk.Adjustment contrast_adjustment;
    [GtkChild]
    private unowned Gtk.Adjustment compression_adjustment;
    [GtkChild]
    private unowned Gtk.Switch postproc_enable_switch;
    [GtkChild]
    private unowned Gtk.Entry postproc_script_entry;
    [GtkChild]
    private unowned Gtk.Entry postproc_args_entry;
    [GtkChild]
    private unowned Gtk.Switch postproc_keep_original_switch;

    static string get_dpi_label (DpiItem device) {
        return device.label;
    }

    static string get_page_size_label (PaperSizeItem size) {
        return size.label;
    }

    public PreferencesDialog (Settings settings)
    {
        this.settings = settings;

        paper_size_row.expression = new Gtk.CClosureExpression (
            typeof (string),
            null,
            {},
            (Callback) get_page_size_label,
            null,
            null
        );

        paper_size_model = new ListStore (typeof (PaperSizeItem));
        /* Combo box value for automatic paper size */
        paper_size_model.append (new PaperSizeItem (_("Automatic"), 0, 0));
        paper_size_model.append (new PaperSizeItem ("A6", 1050, 1480));
        paper_size_model.append (new PaperSizeItem ("A5", 1480, 2100));
        paper_size_model.append (new PaperSizeItem ("A4", 2100, 2970));
        paper_size_model.append (new PaperSizeItem ("A3", 2970, 4200));
        paper_size_model.append (new PaperSizeItem ("Letter", 2159, 2794));
        paper_size_model.append (new PaperSizeItem ("Legal", 2159, 3556));
        paper_size_model.append (new PaperSizeItem ("4×6", 1016, 1524));
        paper_size_row.model = paper_size_model;

        text_dpi_row.expression = new Gtk.CClosureExpression (
            typeof (string),
            null,
            {},
            (Callback) get_dpi_label,
            null,
            null
        );
        text_dpi_model = new ListStore (typeof (DpiItem));
        text_dpi_row.model = text_dpi_model;

        photo_dpi_row.expression = new Gtk.CClosureExpression (
            typeof (string),
            null,
            {},
            (Callback) get_dpi_label,
            null,
            null
        );
        photo_dpi_model = new ListStore (typeof (DpiItem));
        photo_dpi_row.model = photo_dpi_model;

        var dpi = settings.get_int ("text-dpi");
        if (dpi <= 0)
            dpi = DEFAULT_TEXT_DPI;
        set_dpi_combo (text_dpi_row, DEFAULT_TEXT_DPI, dpi);
        text_dpi_row.notify["selected"].connect (() => { settings.set_int ("text-dpi", get_text_dpi ()); });
        dpi = settings.get_int ("photo-dpi");
        if (dpi <= 0)
            dpi = DEFAULT_PHOTO_DPI;
        set_dpi_combo (photo_dpi_row, DEFAULT_PHOTO_DPI, dpi);
        photo_dpi_row.notify["selected"].connect (() => { settings.set_int ("photo-dpi", get_photo_dpi ()); });

        set_page_side ((ScanSide) settings.get_enum ("page-side"));
        front_side_button.toggled.connect ((button) => { if (button.active) settings.set_enum ("page-side", ScanSide.FRONT); });
        back_side_button.toggled.connect ((button) => { if (button.active) settings.set_enum ("page-side", ScanSide.BACK); });
        both_side_button.toggled.connect ((button) => { if (button.active) settings.set_enum ("page-side", ScanSide.BOTH); });

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
        
        var minimum_size_label = "<small>%s</small>".printf (_("Minimum size"));
        compression_scale.add_mark (compression_adjustment.lower, Gtk.PositionType.BOTTOM, minimum_size_label);
        compression_scale.add_mark (75, Gtk.PositionType.BOTTOM, null);
        compression_scale.add_mark (90, Gtk.PositionType.BOTTOM, null);
        var full_detail_label = "<small>%s</small>".printf (_("Full detail"));
        compression_scale.add_mark (compression_adjustment.upper, Gtk.PositionType.BOTTOM, full_detail_label);
        compression_adjustment.value = settings.get_int ("jpeg-quality");
        compression_adjustment.value_changed.connect (() => { settings.set_int ("jpeg-quality", (int) compression_adjustment.value); });

        var paper_width = settings.get_int ("paper-width");
        var paper_height = settings.get_int ("paper-height");
        set_paper_size (paper_width, paper_height);
        paper_size_row.notify["selected"].connect (() =>
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
        for (uint i = 0; i < paper_size_model.n_items; i++)
        {
            var item = paper_size_model.get_item (i) as PaperSizeItem;
            if (item.width == width && item.height == height)
            {
                paper_size_row.selected = i;
                break;
            }
        }
    }

    public int get_text_dpi ()
    {
        if (text_dpi_row.selected != Gtk.INVALID_LIST_POSITION)
        {
            var item = text_dpi_model.get_item (text_dpi_row.selected) as DpiItem;
            return item.dpi;
        }

        return DEFAULT_TEXT_DPI;
    }

    public int get_photo_dpi ()
    {
        if (photo_dpi_row.selected != Gtk.INVALID_LIST_POSITION)
        {
            var item = photo_dpi_model.get_item (photo_dpi_row.selected) as DpiItem;
            return item.dpi;
        }

        return DEFAULT_PHOTO_DPI;
    }

    public bool get_paper_size (out int width, out int height)
    {
        width = height = 0;
        if (paper_size_row.selected != Gtk.INVALID_LIST_POSITION)
        {
            var item = paper_size_model.get_item (paper_size_row.selected) as PaperSizeItem;
            width = item.width;
            height = item.height;
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

    private void set_dpi_combo (Adw.ComboRow combo, int default_dpi, int current_dpi)
    {
        var model = combo.model as ListStore;
        int[] scan_resolutions = {75, 150, 200, 300, 600, 1200, 2400};
        
        for (var i = 0; i < scan_resolutions.length; i++)
        {
            var dpi = scan_resolutions[i];

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
            
            model.append (new DpiItem (dpi, label));

            if (dpi == current_dpi)
                combo.selected = i;

        }
    }
}
