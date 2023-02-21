/*
 * Copyright (C) 2023 Bartłomiej Maryńczak
 * Author: Bartłomiej Maryńczak <marynczakbartlomiej@gmail.com>,
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later
 * version. See http://www.gnu.org/copyleft/gpl.html the full text of the
 * license.
 */

[GtkTemplate (ui = "/org/gnome/SimpleScan/ui/drivers-dialog.ui")]
private class DriversDialog : Gtk.Window
{
    [GtkChild]
    private unowned Gtk.Revealer header_revealer;

    [GtkChild]
    private unowned Gtk.Label main_label;
    [GtkChild]
    private unowned Gtk.Label main_sublabel;
    
    [GtkChild]
    private unowned Gtk.Revealer progress_revealer;
    [GtkChild]
    private unowned Gtk.ProgressBar progress_bar;

    [GtkChild]
    private unowned Gtk.Label result_label;
    [GtkChild]
    private unowned Gtk.Label result_sublabel;
    [GtkChild]
    private unowned Gtk.Image result_icon;

    [GtkChild]
    private unowned Gtk.Stack stack;
    
    private uint pulse_timer;
    private string? missing_driver;

    public DriversDialog (Gtk.Window parent, string? missing_driver)
    {
        this.missing_driver = missing_driver;
        set_transient_for (parent);
    }
    
    ~DriversDialog () {
        pulse_stop ();
    }
    
    private void pulse_start ()
    {
        pulse_stop ();
        pulse_timer = GLib.Timeout.add(100, () => {
            progress_bar.pulse ();
            return Source.CONTINUE;
        });
    }

    private void pulse_stop ()
    {
        Source.remove (pulse_timer);
    }
    
    public async void open ()
    {
        var message = "", instructions = "";
        string[] packages_to_install = {};
        switch (missing_driver)
        {
        case "brscan":
        case "brscan2":
        case "brscan3":
        case "brscan4":
            /* Message to indicate a Brother scanner has been detected */
            message = _("You appear to have a Brother scanner.");
            /* Instructions on how to install Brother scanner drivers */
            instructions = _("Drivers for this are available on the <a href=\"http://support.brother.com\">Brother website</a>.");
            break;
        case "pixma":
            /* Message to indicate a Canon Pixma scanner has been detected */
            message = _("You appear to have a Canon scanner, which is supported by the <a href=\"http://www.sane-project.org/man/sane-pixma.5.html\">Pixma SANE backend</a>.");
            /* Instructions on how to resolve issue with SANE scanner drivers */
            instructions = _("Please check if your <a href=\"http://www.sane-project.org/sane-supported-devices.html\">scanner is supported by SANE</a>, otherwise report the issue to the <a href=\"https://alioth-lists.debian.net/cgi-bin/mailman/listinfo/sane-devel\">SANE mailing list</a>.");
            break;
        case "samsung":
            /* Message to indicate a Samsung scanner has been detected */
            message = _("You appear to have a Samsung scanner.");
            /* Instructions on how to install Samsung scanner drivers.
               Because HP acquired Samsung's global printing business in 2017, the support is made on HP site. */
            instructions = _("Drivers for this are available on the <a href=\"https://support.hp.com\">HP website</a> (HP acquired Samsung's printing business).");
            break;
        case "hpaio":
        case "smfp":
            /* Message to indicate a HP scanner has been detected */
            message = _("You appear to have an HP scanner.");
            if (missing_driver == "hpaio")
                packages_to_install = { "libsane-hpaio" };
            else
                /* Instructions on how to install HP scanner drivers.
                   smfp is rebranded and slightly modified Samsung devices,
                   for example: HP Laser MFP 135a is rebranded Samsung Xpress SL-M2070.
                   It require custom drivers, not available in hpaio package */
                instructions = _("Drivers for this are available on the <a href=\"https://support.hp.com\">HP website</a>.");
            break;
        case "epkowa":
            /* Message to indicate an Epson scanner has been detected */
            message = _("You appear to have an Epson scanner.");
            /* Instructions on how to install Epson scanner drivers */
            instructions = _("Drivers for this are available on the <a href=\"http://support.epson.com\">Epson website</a>.");
            break;
        case "lexmark_nscan":
            /* Message to indicate a Lexmark scanner has been detected */
            message = _("You appear to have a Lexmark scanner.");
            /* Instructions on how to install Lexmark scanner drivers */
            instructions = _("Drivers for this are available on the <a href=\"http://support.lexmark.com\">Lexmark website</a>.");
            break;
        }

        main_label.label = message;
        main_sublabel.label = instructions;

        if (packages_to_install.length > 0)
        {
#if HAVE_PACKAGEKIT
            this.progress_revealer.reveal_child = true;
            pulse_start();

            main_sublabel.set_text (/* Label shown while installing drivers */
                                         _("Installing drivers…"));

            present ();

            /* Label shown once drivers successfully installed */
            var result_text = _("Drivers installed successfully!");
            var success = true;
            try
            {
                var results = yield install_packages(packages_to_install, () => {});

                if (results.get_error_code () != null)
                {
                    var e = results.get_error_code ();
                    /* Label shown if failed to install drivers */
                    result_text = _("Failed to install drivers (error code %d).").printf (e.code);
                    success = false;
                }
            }
            catch (Error e)
            {
                /* Label shown if failed to install drivers */
                result_text = _("Failed to install drivers.");
                success = false;
                warning ("Failed to install drivers: %s", e.message);
            }

            result_label.label = result_text;

            if (success)
            {
                result_sublabel.label = _("Once installed you will need to restart this app.");
                result_icon.icon_name = "emblem-ok-symbolic";
            }
            else
            {
                result_sublabel.visible = false;
                result_icon.icon_name = "emblem-important-symbolic";
            }
                
            stack.set_visible_child_name ("result");
            header_revealer.reveal_child = false;
            progress_revealer.reveal_child = false;
            pulse_stop ();
#else
            main_sublabel.set_text (/* Label shown to prompt user to install packages (when PackageKit not available) */
                                         ngettext ("You need to install the %s package.", "You need to install the %s packages.", packages_to_install.length).printf (string.joinv (", ", packages_to_install)));
            present ();
#endif
        }
    }

#if HAVE_PACKAGEKIT
    private async Pk.Results? install_packages (string[] packages, Pk.ProgressCallback progress_callback) throws GLib.Error
    {
        var task = new Pk.Task ();
        Pk.Results results;
        results = yield task.resolve_async (Pk.Filter.NOT_INSTALLED, packages, null, progress_callback);
        if (results == null || results.get_error_code () != null)
            return results;

        var package_array = results.get_package_array ();
        var package_ids = new string[package_array.length + 1];
        package_ids[package_array.length] = null;
        for (var i = 0; i < package_array.length; i++)
            package_ids[i] = package_array.data[i].get_id ();

        return yield task.install_packages_async (package_ids, null, progress_callback);
    }
#endif
}
