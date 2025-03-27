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

public class SimpleScan : Adw.Application
{
    static bool show_version;
    static bool debug_enabled;
    static string? fix_pdf_filename = null;
    const OptionEntry[] options =
    {
        { "version", 'v', 0, OptionArg.NONE, ref show_version,
          /* Help string for command line --version flag */
          N_("Show release version"), null},
        { "debug", 'd', 0, OptionArg.NONE, ref debug_enabled,
          /* Help string for command line --debug flag */
          N_("Print debugging messages"), null},
        { "fix-pdf", 0, 0, OptionArg.STRING, ref fix_pdf_filename,
          N_("Fix PDF files generated with older versions of this app"), "FILENAME…"},
        { null }
    };
    private static Timer log_timer;
    private static FileStream? log_file;

    private ScanDevice? default_device = null;
    private bool have_devices = false;
    private GUsb.Context usb_context;
    private AppWindow app;
    private Scanner scanner;
    private Book book;
    private Page scanned_page;

    public SimpleScan (ScanDevice? device = null)
    {
        Object (
            /* The inhibit () method use this */
            application_id: "org.gnome.SimpleScan",
            /* Icon resources will be looked up starting from here */
            resource_base_path: "/org/gnome/SimpleScan"
        );
        register_session = true;

        default_device = device;
    }

    public override void startup ()
    {
        base.startup ();

        app = new AppWindow ();
        book = app.book;
        app.start_scan.connect (scan_cb);
        app.stop_scan.connect (cancel_cb);
        app.redetect.connect (redetect_cb);

        scanner = Scanner.get_instance ();
        scanner.update_devices.connect (update_scan_devices_cb);
        scanner.request_authorization.connect (authorize_cb);
        scanner.expect_page.connect (scanner_new_page_cb);
        scanner.got_page_info.connect (scanner_page_info_cb);
        scanner.got_line.connect (scanner_line_cb);
        scanner.page_done.connect (scanner_page_done_cb);
        scanner.document_done.connect (scanner_document_done_cb);
        scanner.scan_failed.connect (scanner_failed_cb);
        scanner.scanning_changed.connect (scanner_scanning_changed_cb);

        try
        {
            usb_context = new GUsb.Context ();
            usb_context.device_added.connect (() => { scanner.redetect (); });
            usb_context.device_removed.connect (() => { scanner.redetect (); });
        }
        catch (Error e)
        {
            warning ("Failed to create USB context: %s\n", e.message);
        }

        if (default_device != null)
        {
            List<ScanDevice> device_list = null;

            device_list.append (default_device);
            app.set_scan_devices (device_list);
            app.set_selected_device (default_device.name);
        }

        app.start ();
        scanner.start ();
    }

    public override void activate ()
    {
        base.activate ();
        app.present ();
    }

    public override void shutdown ()
    {
        base.shutdown ();
        book = null;
        app = null;
        usb_context = null;
        scanner.free ();
    }

    private void update_scan_devices_cb (Scanner scanner, List<ScanDevice> devices)
    {
        var devices_copy = devices.copy_deep ((CopyFunc) Object.ref);

        /* If the default device is not detected add it to the list */
        if (default_device != null)
        {
            var default_in_list = false;
            foreach (var device in devices_copy)
            {
                if (device.name == default_device.name)
                {
                    default_in_list = true;
                    break;
                }
            }

            if (!default_in_list)
                devices_copy.prepend (default_device);
        }

        have_devices = devices_copy.length () > 0;

        /* If SANE doesn't see anything, see if we recognise any of the USB devices */
        string? missing_driver = null;
        if (!have_devices)
            missing_driver = suggest_driver ();

        app.set_scan_devices (devices_copy, missing_driver);
    }

    /* Taken from /usr/local/Brother/sane/Brsane.ini from brscan driver */
    private const uint32 brscan_devices[] = { 0x04f90110, 0x04f90111, 0x04f90112, 0x04f9011d, 0x04f9011e, 0x04f9011f, 0x04f9012b, 0x04f90124, 0x04f90153, 0x04f90125, 0x04f90113, 0x04f90114, 0x04f90115, 0x04f90116, 0x04f90119, 0x04f9011a, 0x04f9011b, 0x04f9011c, 0x04f9012e, 0x04f9012f, 0x04f90130, 0x04f90128, 0x04f90127, 0x04f90142, 0x04f90143, 0x04f90140, 0x04f90141, 0x04f9014e, 0x04f9014f, 0x04f90150, 0x04f90151, 0x04f9010e, 0x04f9013a, 0x04f90120, 0x04f9010f, 0x04f90121, 0x04f90122, 0x04f90132, 0x04f9013d, 0x04f9013c, 0x04f90136, 0x04f90135, 0x04f9013e, 0x04f9013f, 0x04f90144, 0x04f90146, 0x04f90148, 0x04f9014a, 0x04f9014b, 0x04f9014c, 0x04f90157, 0x04f90158, 0x04f9015d, 0x04f9015e, 0x04f9015f, 0x04f90160 };

    /* Taken from /usr/local/Brother/sane/models2/*.ini from brscan2 driver */
    private const uint32 brscan2_devices[] = { 0x04f901c9, 0x04f901ca, 0x04f901cb, 0x04f901cc, 0x04f901ec, 0x04f901e4, 0x04f901e3, 0x04f901e2, 0x04f901e1, 0x04f901e0, 0x04f901df, 0x04f901de, 0x04f901dd, 0x04f901dc, 0x04f901db, 0x04f901da, 0x04f901d9, 0x04f901d8, 0x04f901d7, 0x04f901d6, 0x04f901d5, 0x04f901d4, 0x04f901d3, 0x04f901d2, 0x04f901d1, 0x04f901d0, 0x04f901cf, 0x04f901ce, 0x04f9020d, 0x04f9020c, 0x04f9020a };

    /* Taken from /usr/local/Brother/sane/models3/*.ini from brscan3 driver */
    private const uint32 brscan3_devices[] = { 0x04f90222, 0x04f90223, 0x04f90224, 0x04f90225, 0x04f90229, 0x04f9022a, 0x04f9022c, 0x04f90228, 0x04f90236, 0x04f90227, 0x04f9022b, 0x04f9022d, 0x04f9022e, 0x04f9022f, 0x04f90230, 0x04f9021b, 0x04f9021a, 0x04f90219, 0x04f9023f, 0x04f90216, 0x04f9021d, 0x04f9021c, 0x04f90220, 0x04f9021e, 0x04f9023e, 0x04f90235, 0x04f9023a, 0x04f901c9, 0x04f901ca, 0x04f901cb, 0x04f901cc, 0x04f901ec, 0x04f9020d, 0x04f9020c, 0x04f90257, 0x04f9025d, 0x04f90254, 0x04f9025b, 0x04f9026b, 0x04f90258, 0x04f9025e, 0x04f90256, 0x04f90240, 0x04f9025f, 0x04f90260, 0x04f90261, 0x04f90278, 0x04f9026f, 0x04f9026e, 0x04f9026d, 0x04f90234, 0x04f90239, 0x04f90253, 0x04f90255, 0x04f90259, 0x04f9025a, 0x04f9025c, 0x04f90276 };

    /* Taken from /opt/brother/scanner/brscan4/models4/*.ini from brscan4 driver */
    private const uint32 brscan4_devices[] = {
      0x04f90314, /* MFC-L9550CDW */
      0x04f90313, /* MFC-L8850CDW */
      0x04f90312, /* MFC-L8650CDW */
      0x04f90311, /* MFC-L8600CDW */
      0x04f90310, /* DCP-L8450CDW */
      0x04f9030f, /* DCP-L8400CDN */
      0x04f90366, /* MFC-J5520DW */
      0x04f90365, /* MFC-J4520DW */
      0x04f90364, /* MFC-J5625DW */
      0x04f90350, /* MFC-J5620CDW */
      0x04f9034f, /* MFC-J5820DN */
      0x04f9034e, /* MFC-J5720CDW */
      0x04f9034b, /* MFC-J4720N */
      0x04f90349, /* DCP-J4220N */
      0x04f90347, /* MFC-J5720DW */
      0x04f90346, /* MFC-J5620DW */
      0x04f90343, /* MFC-J5320DW */
      0x04f90342, /* MFC-J4625DW */
      0x04f90341, /* MFC-J2720 */
      0x04f90340, /* MFC-J4620DW */
      0x04f9033d, /* MFC-J4420DW */
      0x04f9033c, /* MFC-J2320 */
      0x04f9033a, /* MFC-J4320DW */
      0x04f90339, /* DCP-J4120DW */
      0x04f90392, /* MFC-L2705DW */
      0x04f90373, /* MFC-L2700D */
      0x04f9036e, /* MFC-7889DW */
      0x04f9036d, /* MFC-7880DN */
      0x04f9036c, /* MFC-7480D */
      0x04f9036b, /* MFC-7380 */
      0x04f9036a, /* DCP-7189DW */
      0x04f90369, /* DCP-7180DN */
      0x04f90368, /* DCP-7080 */
      0x04f90367, /* DCP-7080D */
      0x04f90338, /* MFC-L2720DN */
      0x04f90337, /* MFC-L2720DW */
      0x04f90335, /* FAX-L2700DN */
      0x04f90331, /* MFC-L2700DW */
      0x04f90330, /* HL-L2380DW */
      0x04f90329, /* DCP-L2560DW */
      0x04f90328, /* DCP-L2540DW */
      0x04f90326, /* DCP-L2540DN */
      0x04f90324, /* DCP-L2520D */
      0x04f90322, /* DCP-L2520DW */
      0x04f90321, /* DCP-L2500D */
      0x04f90320, /* MFC-L2740DW */
      0x04f90372, /* MFC-9342CDW */
      0x04f90371, /* MFC-9332CDW */
      0x04f90370, /* MFC-9142CDN */
      0x04f9036f, /* DCP-9022CDW */
      0x04f90361, /* MFC-1919NW */
      0x04f90360, /* DCP-1618W */
      0x04f9035e, /* MFC-1910NW */
      0x04f9035d, /* MFC-1910W */
      0x04f9035c, /* DCP-1610NW */
      0x04f9035b, /* DCP-1610W */
      0x04f90379, /* DCP-1619 */
      0x04f90378, /* DCP-1608 */
      0x04f90376, /* DCP-1600 */
      0x04f9037a, /* MFC-1906 */
      0x04f9037b, /* MFC-1908 */
      0x04f90377, /* MFC-1900 */
      0x04f9037f, /* ADS-2600We */
      0x04f9037e, /* ADS-2500We */
      0x04f9037d, /* ADS-2100e */
      0x04f9037c, /* ADS-2000e */
      0x04f9035a, /* MFC-J897DN */
      0x04f90359, /* MFC-J827DN */
      0x04f90358, /* MFC-J987DN */
      0x04f90357, /* MFC-J727D */
      0x04f90356, /* MFC-J877N */
      0x04f90355, /* DCP-J957N */
      0x04f90354, /* DCP-J757N */
      0x04f90353, /* DCP-J557N */
      0x04f90351, /* DCP-J137N */
      0x04f90390, /* MFC-J5920DW */
      0x04f903b3, /* MFC-J6925DW */
      0x04f90396, /* MFC-T800W */
      0x04f90395, /* DCP-T700W */
      0x04f90394, /* DCP-T500W */
      0x04f90393, /* DCP-T300 */
      0x04f90380, /* DCP-J562DW */
      0x04f90381, /* DCP-J562N */
      0x04f903bd, /* DCP-J762N */
      0x04f90383, /* DCP-J962N */
      0x04f90397, /* DCP-J963N */
      0x04f90386, /* MFC-J460DW */
      0x04f90384, /* MFC-J480DW */
      0x04f90385, /* MFC-J485DW */
      0x04f90388, /* MFC-J680DW */
      0x04f90389, /* MFC-J880DW */
      0x04f9038b, /* MFC-J880N */
      0x04f9038a, /* MFC-J885DW */
      0x04f9038c, /* MFC-J730DN */
      0x04f9038e, /* MFC-J830DN */
      0x04f9038f, /* MFC-J900DN */
      0x04f9038d, /* MFC-J990DN */
      0x04f903bc, /* MFC-L2700DN */
      0x04f903bb, /* MFC-L2680W */
      0x04f903b6, /* MFC-J6990CDW */
      0x04f903b5, /* MFC-J6973CDW */
      0x04f903b4, /* MFC-J6573CDW */
      0x04f9034a, /* DCP-J4225N */
      0x04f9034c, /* MFC-J4725N */
      0x04f903c5, /* MFC-9335CDW */
      0x04f903c1, /* HL-3180CDW */
      0x04f903c0, /* DCP-9015CDW */
      0x04f903bf, /* DCP-9017CDW */
      0x04f903c7, /* MFC-L5702DW */
      0x04f903c6, /* MFC-L5700DW */
      0x04f903b2, /* MFC-L5755DW */
      0x04f903b1, /* MFC-L6902DW */
      0x04f903b0, /* MFC-L6900DW */
      0x04f903af, /* MFC-L6800DW */
      0x04f903ae, /* MFC-L6750DW */
      0x04f903ad, /* MFC-L6702DW */
      0x04f903ac, /* MFC-L6700DW */
      0x04f903ab, /* MFC-L5902DW */
      0x04f903aa, /* MFC-L5900DW */
      0x04f903a9, /* MFC-L5850DW */
      0x04f903a8, /* MFC-L5802DW */
      0x04f903a7, /* MFC-L5800DW */
      0x04f903a6, /* MFC-8540DN */
      0x04f903a5, /* MFC-L5750DW */
      0x04f903a3, /* MFC-8535DN */
      0x04f903a2, /* MFC-8530DN */
      0x04f903a0, /* MFC-L5700DN */
      0x04f9039f, /* DCP-L6600DW */
      0x04f9039e, /* DCP-L5652DN */
      0x04f9039d, /* DCP-L5650DN */
      0x04f9039c, /* DCP-L5602DN */
      0x04f9039b, /* DCP-L5600DN */
      0x04f9039a, /* DCP-L5502DN */
      0x04f90399, /* DCP-L5500DN */
      0x04f90398, /* DCP-L5500D */
      0x04f903ba, /* ADS-3600W */
      0x04f903b9, /* ADS-2800W */
      0x04f903b8, /* ADS-3000N */
      0x04f903b7, /* ADS-2400N */
      0x04f903ca, /* DCP-J983N */
      0x04f903c9, /* MFC-J985DW */
      0x04f903c8, /* DCP-J785DW */
      0x04f903f2, /* MFC-J997DN */
      0x04f903f1, /* MFC-J907DN */
      0x04f903f0, /* MFC-J887N */
      0x04f903ef, /* MFC-J837DN */
      0x04f903ee, /* MFC-J737DN */
      0x04f903ed, /* DCP-J968N */
      0x04f903eb, /* DCP-J767N */
      0x04f903ea, /* DCP-J567N */
      0x04f903e8, /* MFC-J5830DW */
      0x04f903e7, /* MFC-J2730DW */
      0x04f903e6, /* MFC-J2330DW */
      0x04f903e5, /* MFC-J5335DW */
      0x04f903e4, /* MFC-J6535DW */
      0x04f903e3, /* MFC-J3930DW */
      0x04f903e2, /* MFC-J3530DW */
      0x04f903e0, /* MFC-J6530DW */
      0x04f903d6, /* MFC-J5930DW */
      0x04f903d5, /* MFC-J5730DW */
      0x04f903d3, /* MFC-J5330DW */
      0x04f903d1, /* MFC-J6995CDW */
      0x04f903d0, /* MFC-J6980CDW */
      0x04f903cf, /* MFC-J6580CDW */
      0x04f903cd, /* MFC-J6730DW */
      0x04f903cc, /* MFC-J6935DW */
      0x04f903cb, /* MFC-J6930DW */
      0x04f903f7, /* DCP-L8410CDW */
      0x04f903f6, /* MFC-L8610CDW */
      0x04f903f5, /* MFC-L8690CDW */
      0x04f903f4, /* MFC-L8900CDW */
      0x04f903f3, /* MFC-L9570CDW */
      0x04f903fa, /* MFC-L2685DW */
      0x04f903e1, /* MFC-L2707DW */
      0x04f90290, /* MFC-J432W */
      0x04f9028f, /* MFC-J425W */
      0x04f9028d, /* MFC-J835DW */
      0x04f9028a, /* DCP-J925N */
      0x04f90284, /* MFC-J825N */
      0x04f90283, /* MFC-J825DW */
      0x04f90282, /* MFC-J625DW */
      0x04f90281, /* MFC-J430W */
      0x04f9027e, /* MFC-J955DN */
      0x04f9027d, /* DCP-J925DW */
      0x04f9027c, /* DCP-J725N */
      0x04f9027b, /* DCP-J725DW */
      0x04f90280, /* MFC-J435W */
      0x04f9027a, /* DCP-J525N */
      0x04f90279, /* DCP-J525W */
      0x04f9027f, /* MFC-J280W */
      0x04f90285, /* MFC-J705D */
      0x04f9029a, /* MFC-8690DW */
      0x04f9029f, /* MFC-9325CW */
      0x04f9029e, /* MFC-9125CN */
      0x04f90289, /* MFC-J5910CDW */
      0x04f90288, /* MFC-J5910DW */
      0x04f9043d, /* DCP-L2535DW */
      0x04f9043c, /* MFC-L2715DW */
      0x04f9043b, /* MFC-L2770DW */
      0x04f9043a, /* MFC-L2750DW */
      0x04f90439, /* MFC-L2730DW */
      0x04f90438, /* MFC-L2730DN */
      0x04f90437, /* MFC-L2717DW */
      0x04f90436, /* MFC-L2715D */
      0x04f90435, /* MFC-L2713DW */
      0x04f90434, /* MFC-L2710DW */
      0x04f90433, /* MFC-L2710DN */
      0x04f90432, /* MFC-L2690DW */
      0x04f90431, /* MFC-B7720DN */
      0x04f90430, /* MFC-B7715DW */
      0x04f9042e, /* MFC-B7700D */
      0x04f9042d, /* MFC-7895DW */
      0x04f9042c, /* MFC-7890DN */
      0x04f9042b, /* MFC-7490D */
      0x04f9042a, /* MFC-7390 */
      0x04f90429, /* HL-L2395DW */
      0x04f90428, /* HL-L2390DW */
      0x04f90427, /* FAX-L2710DN */
      0x04f90425, /* DCP-L2551DN */
      0x04f90424, /* DCP-L2550DW */
      0x04f90423, /* DCP-L2550DN */
      0x04f90422, /* DCP-L2537DW */
      0x04f90421, /* DCP-L2535D */
      0x04f90420, /* DCP-L2530DW */
      0x04f9041f, /* DCP-L2510D */
      0x04f9041e, /* DCP-B7535DW */
      0x04f9041d, /* DCP-B7530DN */
      0x04f9041c, /* DCP-B7520DW */
      0x04f9041b, /* DCP-B7500D */
      0x04f9041a, /* DCP-7195DW */
      0x04f90419, /* DCP-7190DN */
      0x04f90418, /* DCP-7095D */
      0x04f90417, /* DCP-7090 */
      0x04f90413, /* MFC-T910DW */
      0x04f90412, /* MFC-T810W */
      0x04f90411, /* DCP-T710W */
      0x04f90410, /* DCP-T510W */
      0x04f9040f, /* DCP-T310 */
      0x04f90408, /* MFC-J893N */
      0x04f90407, /* DCP-J973N */
      0x04f90406, /* DCP-J972N */
      0x04f90405, /* DCP-J572N */
      0x04f90404, /* MFC-J690DW */
      0x04f90403, /* MFC-J890DW */
      0x04f90400, /* DCP-J774DW */
      0x04f903ff, /* DCP-J772DW */
      0x04f903f8, /* MFC-J895DW */
      0x04f9043e, /* MFC-J775DW */
      0x04f9040e, /* MFC-J1500N */
      0x04f9040d, /* DCP-J988N */
      0x04f9040b, /* MFC-J1300DW */
      0x04f9040a, /* MFC-J995DW */
      0x04f90409, /* DCP-J1100DW */
      0x04f90402, /* MFC-J497DW */
      0x04f903fe, /* DCP-J572DW */
      0x04f903f9, /* MFC-J491DW */
      0x04f9044b, /* DCP-L3510CDW */
      0x04f9044a, /* HL-L3290CDW */
      0x04f90448, /* DCP-L3550CDW */
      0x04f90446, /* MFC-L3710CW */
      0x04f90445, /* MFC-L3730CDN */
      0x04f90442, /* MFC-L3745CDW */
      0x04f90441, /* MFC-L3750CDW */
      0x04f9043f, /* MFC-L3770CDW */
      0x04f90454, /* MFC-T4500DW */
      0x04f9044f, /* MFC-J6545DW */
      0x04f9044d, /* MFC-J5845DW */
      0x04f90462, /* MFC-J898N */
      0x04f90461, /* DCP-J978N */
      0x04f90460, /* DCP-J577N */
      0x04f9044c, /* DCP-L3551CDW */
      0x04f90443, /* MFC-L3735CDN */
      0x04f9045f, /* HL-J6000CDW */
      0x04f90457, /* MFC-J6999CDW */
      0x04f90456, /* MFC-J6997CDW */
      0x04f90453, /* HL-J6100DW */
      0x04f90452, /* HL-J6000DW */
      0x04f90451, /* MFC-J6947DW */
      0x04f90450, /* MFC-J6945DW */
      0x04f9044e, /* MFC-J5945DW */
      0x04f90466, /* MFC-J815DW */
      0x04f90465, /* MFC-J1605DN */
      0x04f90464, /* MFC-J998DN */
      0x04f90463, /* MFC-J738DN */
      0x04f90447, /* DCP-9030CDN */
      0x04f90444, /* MFC-9150CDN */
      0x04f90440, /* MFC-9350CDW */
      0x04f9045e, /* MFC-J6983CDW */
      0x04f9045d, /* MFC-J6583CDW */
      0x04f9045c, /* MFC-J5630CDW */
      0x04f90470, /* MFC-J903N */
      0x04f9046f, /* DCP-J982N */
      0x04f9046e, /* DCP-J981N */
      0x04f9046d, /* DCP-J582N */
      0x04f90467, /* MFC-J805DW */
      0x04f960a0, /* ADS-2000 */
      0x04f960a1, /* ADS-2100 */
      0x04f90293, /* DCP-8155DN */
      0x04f902b7, /* DCP-8157DN */
      0x04f90294, /* DCP-8250DN */
      0x04f90296, /* MFC-8520DN */
      0x04f90298, /* MFC-8910DW */
      0x04f902ba, /* MFC-8912DW */
      0x04f90299, /* MFC-8950DW */
      0x04f902bb, /* MFC-8952DW */
      0x04f902d4, /* MFC-8810DW */
      0x04f90291, /* DCP-8110DN */
      0x04f902ac, /* DCP-8110D */
      0x04f902b5, /* DCP-8112DN */
      0x04f90292, /* DCP-8150DN */
      0x04f902b6, /* DCP-8152DN */
      0x04f90295, /* MFC-8510DN */
      0x04f902b8, /* MFC-8512DN */
      0x04f9029c, /* MFC-8515DN */
      0x04f902cb, /* MFC-8710DW */
      0x04f902ca, /* MFC-8712DW */
      0x04f902a6, /* FAX-2940 */
      0x04f902a7, /* FAX-2950 */
      0x04f902ab, /* FAX-2990 */
      0x04f902a5, /* MFC-7240 */
      0x04f902a8, /* MFC-7290 */
      0x04f902a0, /* DCP-J140W */
      0x04f902c1, /* MFC-J960DN */
      0x04f902c0, /* DCP-J940N */
      0x04f902bf, /* MFC-J840N */
      0x04f902be, /* MFC-J710D */
      0x04f902bd, /* DCP-J740N */
      0x04f902bc, /* DCP-J540N */
      0x04f902b2, /* MFC-J810DN */
      0x04f90287, /* MFC-J860DN */
      0x04f902cf, /* DCP-7057W */
      0x04f902ce, /* DCP-7055W */
      0x04f902cd, /* MFC-J2510 */
      0x04f902c7, /* MFC-J4510N */
      0x04f902c6, /* DCP-J4210N */
      0x04f902c5, /* MFC-J4610DW */
      0x04f902c4, /* MFC-J4410DW */
      0x04f902b4, /* MFC-J4710DW */
      0x04f902b3, /* MFC-J4510DW */
      0x04f902c2, /* DCP-J4110DW */
      0x04f960a4, /* ADS-2500W */
      0x04f960a5, /* ADS-2600W */
      0x04f902cc, /* MFC-J2310 */
      0x04f902c8, /* MFC-J4910CDW */
      0x04f902c3, /* MFC-J4310DW */
      0x04f902d3, /* DCP-9020CDW */
      0x04f902b1, /* DCP-9020CDN */
      0x04f902b0, /* MFC-9340CDW */
      0x04f902af, /* MFC-9330CDW */
      0x04f902ae, /* MFC-9140CDN */
      0x04f902ad, /* MFC-9130CW */
      0x04f902d1, /* MFC-1810 */
      0x04f902d0, /* DCP-1510 */
      0x04f902fb, /* MFC-J875DW */
      0x04f902f1, /* MFC-J890DN */
      0x04f902f0, /* MFC-J980DN */
      0x04f902ef, /* MFC-J820DN */
      0x04f902ed, /* MFC-J870N */
      0x04f902ec, /* MFC-J870DW */
      0x04f902ee, /* MFC-J720D */
      0x04f902eb, /* MFC-J650DW */
      0x04f902e9, /* MFC-J475DW */
      0x04f902e8, /* MFC-J470DW */
      0x04f902fa, /* MFC-J450DW */
      0x04f902ea, /* MFC-J285DW */
      0x04f902e6, /* DCP-J952N */
      0x04f902e5, /* DCP-J752N */
      0x04f902e4, /* DCP-J752DW */
      0x04f902e3, /* DCP-J552N */
      0x04f902e2, /* DCP-J552DW */
      0x04f902f9, /* DCP-J132N */
      0x04f902de, /* DCP-J132W */
      0x04f902e0, /* DCP-J152N */
      0x04f902df, /* DCP-J152W */
      0x04f902e1, /* DCP-J172W */
      0x04f902e7, /* MFC-J245 */
      0x04f902fc, /* DCP-J100 */
      0x04f902fd, /* DCP-J105 */
      0x04f902fe, /* MFC-J200 */
      0x04f902dd, /* DCP-J4215N */
      0x04f902c9, /* MFC-J4810DN */
      0x04f902ff, /* MFC-J3520 */
      0x04f90300, /* MFC-J3720 */
      0x04f902f2, /* MFC-J6520DW */
      0x04f902f3, /* MFC-J6570CDW */
      0x04f902f4, /* MFC-J6720DW */
      0x04f902f8, /* MFC-J6770CDW */
      0x04f902f5, /* MFC-J6920DW */
      0x04f902f6, /* MFC-J6970CDW */
      0x04f902f7, /* MFC-J6975CDW */
      0x04f90318, /* MFC-7365DN */
      0x04f960a6, /* ADS-1000W */
      0x04f960a7, /* ADS-1100W */
      0x04f960a8, /* ADS-1500W */
      0x04f960a9, /* ADS-1600W */
    };

    /* Taken from backend/pixma/pixma_mp150.c pixma_mp730.c pixma_mp750.c pixma_mp800.c in the pixma SANE backend repository */
    /* Canon Pixma IDs extracted using the following Python script
      import sys
      for f in sys.argv:
        for l in open(f, "r").readlines():
          tokens=l.split ()
          if len (tokens) >= 3 and tokens[0].startswith("#define") and tokens[1].endswith("_PID") and tokens[2].startswith("0x") and not tokens[2].endswith("ffff"):
            print ( "0x04a9" + tokens[2][2:] + ", /* " +  tokens[1][:-4] + " * /")
    */
    private const uint32 pixma_devices[] = {
      0x04a91709, /* MP150 */
      0x04a9170a, /* MP170 */
      0x04a9170b, /* MP450 */
      0x04a9170c, /* MP500 */
      0x04a91712, /* MP530 */
      0x04a91714, /* MP160 */
      0x04a91715, /* MP180 */
      0x04a91716, /* MP460 */
      0x04a91717, /* MP510 */
      0x04a91718, /* MP600 */
      0x04a91719, /* MP600R */
      0x04a9172b, /* MP140 */
      0x04a9171c, /* MX7600 */
      0x04a91721, /* MP210 */
      0x04a91722, /* MP220 */
      0x04a91723, /* MP470 */
      0x04a91724, /* MP520 */
      0x04a91725, /* MP610 */
      0x04a91727, /* MX300 */
      0x04a91728, /* MX310 */
      0x04a91729, /* MX700 */
      0x04a9172c, /* MX850 */
      0x04a9172e, /* MP630 */
      0x04a9172f, /* MP620 */
      0x04a91730, /* MP540 */
      0x04a91731, /* MP480 */
      0x04a91732, /* MP240 */
      0x04a91733, /* MP260 */
      0x04a91734, /* MP190 */
      0x04a91735, /* MX860 */
      0x04a91736, /* MX320 */
      0x04a91737, /* MX330 */
      0x04a9173a, /* MP250 */
      0x04a9173b, /* MP270 */
      0x04a9173c, /* MP490 */
      0x04a9173d, /* MP550 */
      0x04a9173e, /* MP560 */
      0x04a9173f, /* MP640 */
      0x04a91741, /* MX340 */
      0x04a91742, /* MX350 */
      0x04a91743, /* MX870 */
      0x04a91746, /* MP280 */
      0x04a91747, /* MP495 */
      0x04a91748, /* MG5100 */
      0x04a91749, /* MG5200 */
      0x04a9174a, /* MG6100 */
      0x04a9174d, /* MX360 */
      0x04a9174e, /* MX410 */
      0x04a9174f, /* MX420 */
      0x04a91750, /* MX880 */
      0x04a91751, /* MG2100 */
      0x04a91752, /* MG3100 */
      0x04a91753, /* MG4100 */
      0x04a91754, /* MG5300 */
      0x04a91755, /* MG6200 */
      0x04a91757, /* MP493 */
      0x04a91758, /* E500 */
      0x04a91759, /* MX370 */
      0x04a9175B, /* MX430 */
      0x04a9175C, /* MX510 */
      0x04a9175D, /* MX710 */
      0x04a9175E, /* MX890 */
      0x04a9175A, /* E600 */
      0x04a91763, /* MG4200 */
      0x04a9175F, /* MP230 */
      0x04a91765, /* MG6300 */
      0x04a91760, /* MG2200 */
      0x04a91761, /* E510 */
      0x04a91762, /* MG3200 */
      0x04a91764, /* MG5400 */
      0x04a91766, /* MX390 */
      0x04a91767, /* E610 */
      0x04a91768, /* MX450 */
      0x04a91769, /* MX520 */
      0x04a9176a, /* MX720 */
      0x04a9176b, /* MX920 */
      0x04a9176c, /* MG2400 */
      0x04a9176d, /* MG2500 */
      0x04a9176e, /* MG3500 */
      0x04a9176f, /* MG6500 */
      0x04a91770, /* MG6400 */
      0x04a91771, /* MG5500 */
      0x04a91772, /* MG7100 */
      0x04a91774, /* MX470 */
      0x04a91775, /* MX530 */
      0x04a91776, /* MB5000 */
      0x04a91777, /* MB5300 */
      0x04a91778, /* MB2000 */
      0x04a91779, /* MB2300 */
      0x04a9177a, /* E400 */
      0x04a9177b, /* E560 */
      0x04a9177c, /* MG7500 */
      0x04a9177e, /* MG6600 */
      0x04a9177f, /* MG5600 */
      0x04a91780, /* MG2900 */
      0x04a91788, /* E460 */
      0x04a91787, /* MX490 */
      0x04a91789, /* E480 */
      0x04a9178a, /* MG3600 */
      0x04a9178b, /* MG7700 */
      0x04a9178c, /* MG6900 */
      0x04a9178d, /* MG6800 */
      0x04a9178e, /* MG5700 */
      0x04a91792, /* MB2700 */
      0x04a91793, /* MB2100 */
      0x04a91794, /* G3000 */
      0x04a91795, /* G2000 */
      0x04a9179f, /* TS9000 */
      0x04a91800, /* TS8000 */
      0x04a91801, /* TS6000 */
      0x04a91802, /* TS5000 */
      0x04a9180b, /* MG3000 */
      0x04a9180c, /* E470 */
      0x04a9181e, /* E410 */
      0x04a9181d, /* G4000 */
      0x04a91822, /* TS6100 */
      0x04a91825, /* TS5100 */
      0x04a91827, /* TS3100 */
      0x04a91828, /* E3100 */
      0x04a9178f, /* MB5400 */
      0x04a91790, /* MB5100 */
      0x04a91820, /* TS9100 */
      0x04a91823, /* TR8500 */
      0x04a91824, /* TR7500 */
      0x04a9185c, /* TS9500 */
      0x04a91912, /* LIDE400 */
      0x04a91913, /* LIDE300 */
      0x04a91821, /* TS8100 */
      0x04a9183a, /* G2010 */
      0x04a9183b, /* G3010 */
      0x04a9183d, /* G4010 */
      0x04a9183e, /* TS9180 */
      0x04a9183f, /* TS8180 */
      0x04a91840, /* TS6180 */
      0x04a91841, /* TR8580 */
      0x04a91842, /* TS8130 */
      0x04a91843, /* TS6130 */
      0x04a91844, /* TR8530 */
      0x04a91845, /* TR7530 */
      0x04a91846, /* XK50 */
      0x04a91847, /* XK70 */
      0x04a91854, /* TR4500 */
      0x04a91855, /* E4200 */
      0x04a91856, /* TS6200 */
      0x04a91857, /* TS6280 */
      0x04a91858, /* TS6230 */
      0x04a91859, /* TS8200 */
      0x04a9185a, /* TS8280 */
      0x04a9185b, /* TS8230 */
      0x04a9185d, /* TS9580 */
      0x04a9185e, /* TR9530 */
      0x04a91863, /* G7000 */
      0x04a91865, /* G6000 */
      0x04a91866, /* G6080 */
      0x04a91869, /* GM4000 */
      0x04a91873, /* XK80 */
      0x04a9188b, /* TS5300 */
      0x04a9188c, /* TS5380 */
      0x04a9188d, /* TS6300 */
      0x04a9188e, /* TS6380 */
      0x04a9188f, /* TS7330 */
      0x04a91890, /* TS8300 */
      0x04a91891, /* TS8380 */
      0x04a91892, /* TS8330 */
      0x04a91893, /* XK60 */
      0x04a91894, /* TS6330 */
      0x04a918a2, /* TS3300 */
      0x04a918a3, /* E3300 */
      0x04a9261f, /* MP10 */
      0x04a9262f, /* MP730 */
      0x04a92630, /* MP700 */
      0x04a92635, /* MP5 */
      0x04a9263c, /* MP360 */
      0x04a9263d, /* MP370 */
      0x04a9263e, /* MP390 */
      0x04a9263f, /* MP375R */
      0x04a9264c, /* MP740 */
      0x04a9264d, /* MP710 */
      0x04a9265d, /* MF5730 */
      0x04a9265e, /* MF5750 */
      0x04a9265f, /* MF5770 */
      0x04a92660, /* MF3110 */
      0x04a926e6, /* IR1020 */
      0x04a91706, /* MP750 */
      0x04a91708, /* MP760 */
      0x04a91707, /* MP780 */
      0x04a9170d, /* MP800 */
      0x04a9170e, /* MP800R */
      0x04a91713, /* MP830 */
      0x04a9171a, /* MP810 */
      0x04a9171b, /* MP960 */
      0x04a91726, /* MP970 */
      0x04a91901, /* CS8800F */
      0x04a9172d, /* MP980 */
      0x04a91740, /* MP990 */
      0x04a91908, /* CS9000F */
      0x04a9174b, /* MG8100 */
      0x04a91756, /* MG8200 */
      0x04a9190d, /* CS9000F_MII */
    };

    /* Taken from uld/noarch/oem.conf in the Samsung SANE driver */
    private const uint32 samsung_devices[] = { 0x04e83425, 0x04e8341c, 0x04e8342a, 0x04e8343d, 0x04e83456, 0x04e8345a, 0x04e83427, 0x04e8343a, 0x04e83428, 0x04e8343b, 0x04e83455, 0x04e83421, 0x04e83439, 0x04e83444, 0x04e8343f, 0x04e8344e, 0x04e83431, 0x04e8345c, 0x04e8344d, 0x04e83462, 0x04e83464, 0x04e83461, 0x04e83460, 0x04e8340e, 0x04e83435,
                                               0x04e8340f, 0x04e83441, 0x04e8344f, 0x04e83413, 0x04e8341b, 0x04e8342e, 0x04e83426, 0x04e8342b, 0x04e83433, 0x04e83440, 0x04e83434, 0x04e8345b, 0x04e83457, 0x04e8341f, 0x04e83453, 0x04e8344b, 0x04e83409, 0x04e83412, 0x04e83419, 0x04e8342c, 0x04e8343c, 0x04e83432, 0x04e8342d, 0x04e83430, 0x04e8342f,
                                               0x04e83446, 0x04e8341a, 0x04e83437, 0x04e83442, 0x04e83466, 0x04e8340d, 0x04e8341d, 0x04e83420, 0x04e83429, 0x04e83443, 0x04e83438, 0x04e8344c, 0x04e8345d, 0x04e83463, 0x04e83465, 0x04e83450, 0x04e83468, 0x04e83469, 0x04e83467, 0x04e8346b, 0x04e8346a, 0x04e8346e, 0x04e83471, 0x04e83472, 0x04e8347d,
                                               0x04e8347c, 0x04e8347e, 0x04e83481, 0x04e83482, 0x04e83331, 0x04e83332, 0x04e83483, 0x04e83484, 0x04e83485, 0x04e83478, 0x04e83325, 0x04e83327, 0x04e8346f, 0x04e83477, 0x04e83324, 0x04e83326, 0x04e83486, 0x04e83487, 0x04e83489
    };

    /* Taken from uld/noarch/oem.conf in the HP/Samsung SANE driver
       These devices are rebranded Samsung Multifunction Printers. */
    private const uint32 smfp_devices[] = { 0x03F0AA2A, 0x03F0CE2A, 0x03F0C02A, 0x03F0EB2A, 0x03F0F22A };

    /* Taken from /usr/share/hplip/data/models/models.dat in the HPAIO driver */
    private const uint32 hpaio_devices[] = {
      0x04f92311, /* HP Officejet d125xi All-in-One Printer */
      0x04f99711, /* HP Photosmart All-in-One Printer - B010 */
      0x04f91311, /* HP Officejet v30 All-in-One Printer */
      0x04f91011, /* HP Officejet v40xi All-in-One Printer */
      0x04f90f11, /* HP Officejet v40 All-in-One Printer */
      0x04f91911, /* HP Officejet v45 All-in-One Printer */
      0x04f90011, /* HP Officejet g55 All-in-One Printer */
      0x04f90111, /* HP Officejet g55xi All-in-One Printer */
      0x04f90611, /* HP Officejet k60xi All-in-One Printer */
      0x04f90511, /* HP Officejet k60 All-in-One Printer */
      0x04f90811, /* HP Officejet k80xi All-in-One Printer */
      0x04f90711, /* HP Officejet k80 All-in-One Printer */
      0x04f90211, /* HP Officejet g85 All-in-One Printer */
      0x04f90311, /* HP Officejet g85xi All-in-One Printer */
      0x04f90411, /* HP Officejet g95 All-in-One Printer */
      0x04f9062a, /* HP LaserJet 100 Color MFP M175 */
      0x04f94912, /* HP Officejet 100 Mobile L411 */
      0x04f99911, /* HP Envy 100 D410 series */
      0x04f93802, /* HP Photosmart 100 Printer */
      0x04f97a11, /* HP Photosmart B109A series */
      0x04f98311, /* HP Deskjet Ink Advantage K109a Printer */
      0x04f97b11, /* HP Photosmart Wireless All-in-One Printer - B109n */
      0x04f9a711, /* HP Envy 110 e-All-in-One */
      0x04f98d11, /* HP Photosmart D110 Series Printer */
      0x04f98a11, /* HP Photosmart Wireless All-in-One Printer - B110 */
      0x04f9bb11, /* HP Envy 120 e-All-in-One */
      0x04f9222a, /* HP LaserJet Pro MFP M125r */
      0x04f9322a, /* HP LaserJet Pro MFP M127fp */
      0x04f93902, /* HP Photosmart 130 Printer */
      0x04f91002, /* HP Photosmart 140 Compact Photo Printer */
      0x04f9242a, /* HP Color LaserJet Pro MPF M176n */
      0x04f9332a, /* HP Color LaserJet Pro MPF M177fw */
      0x04f9122a, /* HP LaserJet Pro 200 color MFP M276nw */
      0x04f90c2a, /* HP LaserJet 200 Color MFP M275s */
      0x04f9132a, /* HP LaserJet Pro M251nw Color Printer */
      0x04f92c2a, /* HP LaserJet Pro M201dw Printer */
      0x04f97e11, /* HP Photosmart Plus All-in-One Printer - B209a */
      0x04f97811, /* HP Deskjet Ink Advantage K209a All-in-One Printer */
      0x04f98e11, /* HP Photosmart Plus B210 series */
      0x04f92d2a, /* HP LaserJet Pro MFP M225rdn */
      0x04f93502, /* HP Photosmart 230 Printer */
      0x04f91102, /* HP Photosmart 240 Compact Photo Printer */
      0x04f96112, /* HP Officejet Pro 251dw Printer */
      0x04f96212, /* HP Officejet Pro 276dw Multifunction Printer */
      0x04f95511, /* HP Deskjet F310 All-in-One Printer */
      0x04f90f2a, /* HP LaserJet 300 Color M351a */
      0x04f9082a, /* HP LaserJet 300 Color MFP M375nw */
      0x04f97311, /* HP Photosmart Premium Fax All-in-One Printer - C309a */
      0x04f97c11, /* HP Photosmart Premium Fax All-in-One Printer series -C309a */
      0x04f97d11, /* HP Photosmart Premium All-in-One Printer series - C309g */
      0x04f91d02, /* HP Photosmart A310 Compact Photo Printer */
      0x04f91202, /* HP Photosmart 320 Compact Photo Printer */
      0x04f91e02, /* HP Photosmart A320 Compact Photo Printer */
      0x04f91602, /* HP Photosmart 330 Series Compact Photo Printer */
      0x04f91302, /* HP Photosmart 370 Compact Photo Printer */
      0x04f91702, /* HP Photosmart 385 Compact Photo Printer */
      0x04f9152a, /* HP LaserJet 400 M401dne */
      0x04f9142a, /* HP LaserJet 400 MFP M425dw */
      0x04f99611, /* HP Photosmart Prem C410 series */
      0x04f91502, /* HP Photosmart 420 Compact Photo Printer */
      0x04f91902, /* HP Photosmart A430 Compact Photo Printer */
      0x04f91f02, /* HP Photosmart A440 Compact Photo Printer */
      0x04f90512, /* HP Deskjet 450ci Mobile Printer */
      0x04f9aa11, /* HP Officejet Pro X451 Printer series */
      0x04f9a311, /* HP Officejet Pro X451dn Printer */
      0x04f91312, /* HP Deskjet 460c Mobile Printer */
      0x04f91802, /* HP Photosmart 470 Series Compact Photo Printer */
      0x04f92812, /* HP Officejet H470 Mobile Printer */
      0x04f9bf11, /* HP Officejet Pro X476 Multifunction Printer series */
      0x04f9c011, /* HP Officejet Pro X476dw Multifunction Printer */
      0x04f9342a, /* HP Color Laserjet Pro MFP M476dw */
      0x04f99e17, /* HP LaserJet Enterprise 500 MFP M525 Series */
      0x04f99f17, /* HP LaserJet Enterprise 500 Color MFP M575 */
      0x04f9252a, /* HP LaserJet Pro 500 color MFP M570dw */
      0x04f9a417, /* HP LaserJet Enterprise 500 Color M551 */
      0x04f91a02, /* HP Photosmart A510 Compact Photo Printer */
      0x04f99e11, /* HP Photosmart Ink Adv K510 */
      0x04f99011, /* HP PhotoSmart eStn C510 Series */
      0x04f92602, /* HP Photosmart A522xi Compact Photo Printer */
      0x04f9272a, /* HP LaserJet Pro M521dn Multifunction Printer */
      0x04f92b02, /* HP Photosmart A532 Compact Photo Printer */
      0x04f91812, /* HP Officejet Pro K550dtwn Printer */
      0x04f9b211, /* HP Officejet Pro X551 Printer series */
      0x04f9352a, /* HP Officejet Enterprise Color X555dn Printer */
      0x04f92b2a, /* HP Officejet Enterprise Color X585dn Multifunction Printer */
      0x04f9362a, /* HP Officejet Enterprise Color Flow X585z Multifunction Printer */
      0x04f9a517, /* HP LaserJet Enterprise 600 M601n */
      0x04f91b02, /* HP Photosmart A610 Compact Photo Printer */
      0x04f92702, /* HP Photosmart A620 Compact Photo Printer */
      0x04f92c02, /* HP Photosmart A636 Compact Photo Printer */
      0x04f9282a, /* HP LaserJet Enterprise MFP M630dn */
      0x04f92104, /* HP Deskjet 630c Printer */
      0x04f9432a, /* HP LaserJet Enterprise Flow MFP M630z */
      0x04f92004, /* HP Deskjet 640c Lite Printer */
      0x04f91a2a, /* HP Color LaserJet Enterprise M651dn Printer */
      0x04f92304, /* HP Deskjet 656c Printer */
      0x04f91b2a, /* HP Color LaserJet Enterprise Multifunction M680dn Printer */
      0x04f9442a, /* HP Color LaserJet Enterprise Flow Multifunction M680z Printer */
      0x04f98904, /* HP Deskjet 694c Printer */
      0x04f9a617, /* HP LaserJet Enterprise 700 M712n */
      0x04f99a17, /* HP LaserJet Enterprise 700 color MFP M775dn */
      0x04f9312a, /* HP LaserJet Pro M701a Printer */
      0x04f9452a, /* HP LaserJet Pro M706n Printer */
      0x04f91c02, /* HP Photosmart A712 Compact Photo Printer */
      0x04f91811, /* HP PSC 720 All-in-One Printer */
      0x04f99d17, /* HP LaserJet Enterprise MFP M725 series */
      0x04f92804, /* HP Deskjet D730 Printer */
      0x04f92904, /* HP Deskjet F735 All-in-One Printer */
      0x04f91511, /* HP PSC 750xi All-in-One Printer */
      0x04f91411, /* HP PSC 750 All-in-One Printer */
      0x04f9372a, /* HP Color LaserJet Enterprise M750 Printer series */
      0x04f90d14, /* HP Designjet T770 24-in Postscript Printer */
      0x04f91611, /* HP PSC 780 All-in-One Printer */
      0x04f91711, /* HP PSC 780xi All-in-One Printer */
      0x04f90f14, /* HP Designjet T790ps 24in */
      0x04f91f2a, /* HP LaserJet Enterprise M806 Printer Series */
      0x04f90304, /* HP Deskjet 810c Printer */
      0x04f90204, /* HP Deskjet 815c Printer */
      0x04f90804, /* HP Deskjet 816 Printer */
      0x04f92902, /* HP Photosmart A826 Home Photo Center */
      0x04f90704, /* HP Deskjet 825cvr Printer */
      0x04f91e2a, /* HP LaserJet Enterprise flow M830z Multifunction Printer */
      0x04f90404, /* HP Deskjet 830c Printer */
      0x04f90604, /* HP Deskjet 840c Printer */
      0x04f90904, /* HP Deskjet 845c Printer */
      0x04f91512, /* HP Officejet Pro K850 Printer */
      0x04f91c2a, /* HP Color LaserJet Enterprise M855 Printer series */
      0x04f90104, /* HP Deskjet 880c Printer */
      0x04f91d2a, /* HP Color LaserJet Enterprise flow M880 Multifunction Printer series */
      0x04f90004, /* HP Deskjet 895cse Printer */
      0x04f92604, /* HP 910 Printer */
      0x04f92704, /* HP 915 Inkjet All-in-One Printer */
      0x04f91804, /* HP Deskjet 916c Printer */
      0x04f91504, /* HP Deskjet 920c Printer */
      0x04f91f11, /* HP PSC 920 All-in-One Printer */
      0x04f91204, /* HP Deskjet 930c Printer */
      0x04f91604, /* HP Deskjet 940cvr Printer */
      0x04f91704, /* HP Deskjet 948c Printer */
      0x04f91104, /* HP Deskjet 950c Printer */
      0x04f91e11, /* HP PSC 950 All-in-One Printer */
      0x04f91304, /* HP Deskjet 955c Printer */
      0x04f91404, /* HP Deskjet 957c Printer */
      0x04f93104, /* HP Deskjet 960cse Printer */
      0x04f91004, /* HP Deskjet 970cxi Printer */
      0x04f93004, /* HP Deskjet 980cxi Printer */
      0x04f93304, /* HP Deskjet 990cxi Printer */
      0x04f95004, /* HP Deskjet 995c Printer */
      0x04f92e11, /* HP PSC 1000 Series */
      0x04f90517, /* HP LaserJet 1000 Printer */
      0x04f98811, /* HP Deskjet 1000 J110 Series */
      0x04f91712, /* Business Inkjet 1000 Printer */
      0x04f91317, /* HP LaserJet 1005 Printer */
      0x04f94117, /* HP LaserJet P1005 Printer */
      0x04f93217, /* HP LaserJet M1005 Multifunction Printer */
      0x04f93e17, /* HP LaserJet P1009 Printer */
      0x04f90c17, /* HP LaserJet 1010 Printer */
      0x04f9b511, /* HP Deskjet 1010 Printer */
      0x04f94217, /* HP Color LaserJet CM1015 Multifunction Printer */
      0x04f94317, /* HP Color LaserJet CM1017 Multifunction Printer */
      0x04f92b17, /* HP LaserJet 1020 Printer */
      0x04f93017, /* HP LaserJet 1022nw Printer */
      0x04f92d17, /* HP LaserJet 1022n Printer */
      0x04f92c17, /* HP LaserJet 1022 Printer */
      0x04f9112a, /* HP LaserJet Pro CP 1025nw Color Printer Series */
      0x04f90b2a, /* HP LaserJet Pro CP1025nw Color Printer Series */
      0x04f98911, /* HP Deskjet 1050 J410 All-in-One Printer */
      0x04f97c04, /* HP Deskjet 1100c Printer */
      0x04f90912, /* HP Business Inkjet 1100d Printer */
      0x04f93011, /* HP PSC 1110 All-in-One Printer */
      0x04f9032a, /* HP LaserJet Professional P1102w Printer */
      0x04f9002a, /* HP Laserjet Professional P1102 Printer */
      0x04f9102a, /* HP LaserJet Professional P 1102w Printer */
      0x04f93402, /* HP Photosmart 1115 Printer */
      0x04f95617, /* HP LaserJet M1120 Multifunction Printer */
      0x04f95717, /* HP LaserJet M1120n Multifunction Printer */
      0x04f9042a, /* HP LaserJet Professional M1132 Multifunction Printer */
      0x04f90f17, /* HP LaserJet 1150 Printer */
      0x04f94004, /* HP Color Inkjet cp1160 Printer */
      0x04f91e17, /* HP LaserJet 1160 Series Printer */
      0x04f90317, /* HP LaserJet 1200 Printer */
      0x04f90f12, /* HP Business Inkjet 1200dtn Printer */
      0x04f92f11, /* HP PSC 1200 All-in-One Printer */
      0x04f9052a, /* HP LaserJet Professional M1212nf Multifunction Printer */
      0x04f94717, /* HP Color LaserJet CP1215 Printer */
      0x04f93202, /* HP Photosmart 1215 Printer */
      0x04f90e2a, /* HP LaserJet Professional M1217nfW Multifunction Printer */
      0x04f9262a, /* HP Laserjet M1210 MFP Series */
      0x04f93302, /* HP Photosmart 1218 Printer */
      0x04f90417, /* HP LaserJet 1220se All-in-One Printer */
      0x04f90212, /* HP Deskjet 1220c Printer */
      0x04f91412, /* HP Deskjet 1280 Printer */
      0x04f91017, /* HP LaserJet 1300 Printer */
      0x04f97804, /* HP Deskjet D1311 Printer */
      0x04f93b11, /* HP PSC 1300 All-in-One Printer */
      0x04f91117, /* HP LaserJet 1300n Printer */
      0x04f93f11, /* HP PSC 1310 All-in-One Printer */
      0x04f94f17, /* HP Color LaserJet CM1312nfi Multifunction Printer */
      0x04f94e17, /* HP Color LaserJet CM1312 Multifunction Printer */
      0x04f93602, /* HP Photosmart 1315 Printer */
      0x04f95817, /* HP LaserJet M1319f Multifunction Printer */
      0x04f91d17, /* HP LaserJet 1320 Series Printer */
      0x04f93c11, /* HP PSC 1358 series */
      0x04f97904, /* HP Deskjet D1415 Printer */
      0x04f94d11, /* HP PSC 1401 All-in-One Printer */
      0x04f9072a, /* HP LaserJet Professional CM1411fn */
      0x04f94c11, /* HP PSC 1508 All-in-One Printer */
      0x04f9c111, /* HP Deskjet 1510 All-in-One Printer */
      0x04f94417, /* HP Color LaserJet CP1514n Printer */
      0x04f95017, /* HP Color LaserJet CP1518ni Printer */
      0x04f9022a, /* HP LaserJet Professional CP1521n */
      0x04f9012a, /* HP LaserJet M1536dnf MFP */
      0x04f9092a, /* HP LaserJet Professional P1566 */
      0x04f97f11, /* HP Deskjet D1620 Printer */
      0x04f94811, /* HP PSC 1600 All-in-One Printer */
      0x04f93a17, /* HP Color LaserJet 1600 Printer */
      0x04f90a2a, /* HP LaserJet Professional P1606dn Printer */
      0x04f90312, /* HP Color Inkjet cp1700 Printer */
      0x04f99411, /* HP Deskjet 2000 J210 series */
      0x04f99b11, /* HP Deskjet Ink Adv 2010 K010 */
      0x04f93917, /* HP LaserJet P2014 Printer */
      0x04f94a17, /* HP LaserJet P2014n Printer */
      0x04f93817, /* HP LaserJet P2015d Printer */
      0x04f9b911, /* HP Deskjet Ink Advantage 2020HC Printer */
      0x04f95417, /* HP Color LaserJet CP2025dn Printer */
      0x04f95217, /* HP Color LaserJet CP2025 Printer */
      0x04f95317, /* HP Color LaserJet CP2025n Printer */
      0x04f95d17, /* HP LaserJet P2035n Printer */
      0x04f98711, /* HP Deskjet 2050 J510 All-in-One Printer */
      0x04f95c17, /* HP LaserJet P2055dn Printer */
      0x04f99a11, /* HP Deskjet Ink Adv 2060 K110 */
      0x04f92811, /* HP PSC 2105 All-in-One Printer */
      0x04f97d04, /* HP Deskjet F2110 All-in-One Printer */
      0x04f92a11, /* HP PSC 2150 All-in-One Printer */
      0x04f92b11, /* HP PSC 2170 All-in-One Printer */
      0x04f90217, /* HP LaserJet 2200 Series Printer */
      0x04f92911, /* HP PSC 2200 All-in-One Printer */
      0x04f92404, /* HP Deskjet F2210 All-in-One Printer */
      0x04f93511, /* HP PSC 2300 Series All-in-One Printer */
      0x04f90812, /* HP Business Inkjet 2300 Printer */
      0x04f9c302, /* HP Deskjet D2320 Printer */
      0x04f90b17, /* HP LaserJet 2300 Series Printer */
      0x04f95917, /* HP Color LaserJet CM2320 Multifunction Printer */
      0x04f95a17, /* HP Color LaserJet CM2320nf Multifunction Printer */
      0x04f95b17, /* HP Color LaserJet CM2320fxi Multifunction Printer */
      0x04f94911, /* HP PSC 2350 All-in-One Printer */
      0x04f93611, /* HP PSC 2405 Photosmart All-in-One Printer */
      0x04f97611, /* HP Deskjet F2410 All-in-One Printer */
      0x04f97a04, /* HP Deskjet D2430 Printer */
      0x04f92517, /* HP LaserJet 2410 Printer */
      0x04f92917, /* HP LaserJet 2420 Printer */
      0x04f92a17, /* HP LaserJet 2430t Printer */
      0x04f91e04, /* HP 2500c Plus Printer */
      0x04f90717, /* HP Color LaserJet 2500 Printer */
      0x04f92504, /* HP Deskjet D2530 Printer */
      0x04f93711, /* HP PSC 2500 Photosmart All-in-One Printer */
      0x04f9ac11, /* HP Deskjet Ink Advantage 2510 All-in-One */
      0x04f9be11, /* HP Deskjet Ink Advantage 2520HC All-in-One */
      0x04f9c211, /* HP Deskjet 2540 All-in-One Printer */
      0x04f91c17, /* HP Color LaserJet 2550L Printer */
      0x04f94e11, /* HP Photosmart 2570 All-in-One Printer */
      0x04f92e17, /* HP Color LaserJet 2600n Printer */
      0x04f94511, /* HP Photosmart 2605 All-in-One Printer */
      0x04f98011, /* HP Deskjet D2660 Printer */
      0x04f90412, /* HP Business Inkjet 2600 Printer */
      0x04f93617, /* HP Color LaserJet 2605dtn Printer */
      0x04f92f17, /* HP Color LaserJet 2605 Printer */
      0x04f93117, /* HP Color LaserJet 2605dn Printer */
      0x04f9c911, /* HP Officejet 2620 All-in-One */
      0x04f9ca11, /* HP Deskjet Ink Advantage 2645 All-in-One Printer */
      0x04f94611, /* HP Photosmart 2710 All-in-One Printer */
      0x04f93c17, /* HP Color LaserJet 2700n Printer */
      0x04f93717, /* HP Color LaserJet 2700 Printer */
      0x04f92617, /* HP Color LaserJet 2800 All-in-One Printer */
      0x04f91112, /* HP Business Inkjet 2800 Printer */
      0x04f90612, /* HP Business Inkjet 3000 Printer */
      0x04f96717, /* HP Color LaserJet 3000 Printer */
      0x04f99511, /* HP Deskjet 3000 j310 series */
      0x04f97617, /* HP LaserJet P3004 Printer */
      0x04f97317, /* HP LaserJet P3005 Printer */
      0x04f98d17, /* HP LaserJet P3015 Printer */
      0x04f91617, /* HP LaserJet 3015 All-in-One Printer */
      0x04f97a17, /* HP LaserJet M3027 Multifunction Printer */
      0x04f97517, /* HP LaserJet M3035 Multifunction Printer */
      0x04f99311, /* HP Deskjet 3050 J610 series */
      0x04f9a011, /* HP Deskjet 3050A J611 series */
      0x04f93317, /* HP LaserJet 3052 All-in-One Printer */
      0x04f93417, /* HP LaserJet 3055 All-in-One Printer */
      0x04f9a211, /* HP Deskjet 3070 B611 series */
      0x04f95611, /* HP Photosmart C3110 All-in-One Printer */
      0x04f95011, /* HP Photosmart 3108 All-in-One Printer */
      0x04f95111, /* HP Photosmart 3207 All-in-One Printer */
      0x04f90117, /* HP LaserJet 3200 All-in-One Printer */
      0x04f90817, /* HP LaserJet 3300 Multifunction Printer */
      0x04f95211, /* HP Photosmart 3308 All-in-One Printer */
      0x04f97004, /* HP Deskjet 3320v Color Inkjet Printer */
      0x04f90917, /* HP LaserJet 3330 Multifunction Printer */
      0x04f91917, /* HP LaserJet 3380 All-in-One Printer */
      0x04f93517, /* HP LaserJet 3390 All-in-One Printer */
      0x04f97104, /* HP Deskjet 3420 Color Inkjet Printer */
      0x04f91517, /* HP Color LaserJet 3500n Printer */
      0x04f93112, /* HP Officejet J3508 All-in-One Printer */
      0x04f97817, /* HP Color LaserJet CP3505n Printer */
      0x04f9ad11, /* HP Deskjet Ink Advantage 3515 e-All-in-One */
      0x04f9b011, /* HP Deskjet 3520 e-All-in-One Series */
      0x04f98517, /* HP Color LaserJet CP3525 Printer */
      0x04f98a17, /* HP Color LaserJet CM3530 Multifunction Printer */
      0x04f9c711, /* HP Deskjet Ink Advantage 3540 e-All-in-One Printer Series */
      0x04f96117, /* HP Color LaserJet 3550 Printer */
      0x04f96917, /* HP Color LaserJet 3600 Printer */
      0x04f96812, /* HP Officejet Pro 3610 Black and White e-All-in-One */
      0x04f96d12, /* HP Officejet Pro 3620 Black and White e-All-in-One */
      0x04f97204, /* HP Deskjet 3650 Color Inkjet Printer */
      0x04f90a17, /* HP Color LaserJet 3700 Printer */
      0x04f97404, /* HP Deskjet 3740 Color Inkjet Printer */
      0x04f96817, /* HP Color LaserJet 3800 Printer */
      0x04f91b04, /* HP Deskjet 3810 Color Inkjet Printer */
      0x04f91a04, /* HP Deskjet 3816 Color Inkjet Printer */
      0x04f91c04, /* HP Deskjet 3819 Color Inkjet Printer */
      0x04f91904, /* HP Deskjet 3820 Color Inkjet Printer */
      0x04f97504, /* HP Deskjet 3843 Color Inkjet Printer */
      0x04f97604, /* HP Deskjet 3900 Color Inkjet Printer */
      0x04f90714, /* HP Designjet 4000ps */
      0x04f99c11, /* HP Officejet 4000 K210 Printer */
      0x04f97b17, /* HP Color LaserJet CP4005n Printer */
      0x04f98817, /* HP Color LaserJet CP4020 Series Printer */
      0x04f95711, /* HP Photosmart C4110 All-in-One Printer */
      0x04f97704, /* HP Deskjet D4145 Printer */
      0x04f97e04, /* HP Deskjet F4135 All-in-One Printer */
      0x04f93111, /* HP OfficeJet 4100 Series All-in-One Printer */
      0x04f96017, /* HP LaserJet 4150 Printer */
      0x04f93d11, /* HP Officejet 4200 All-in-One Printer */
      0x04f95c11, /* HP Photosmart C4205 All-in-One Printer */
      0x04f97b04, /* HP Deskjet D4245 Printer */
      0x04f96a17, /* HP LaserJet 4240n Printer */
      0x04f92417, /* HP LaserJet 4250 Printer */
      0x04f95411, /* HP Officejet 4308 All-in-One Printer */
      0x04f91f04, /* HP Deskjet D4360 Printer */
      0x04f96711, /* HP Photosmart C4340 All-in-One Printer */
      0x04f97417, /* HP LaserJet 4345 Multifunction Printer */
      0x04f99717, /* HP LaserJet M4349 MFP */
      0x04f92317, /* HP LaserJet 4350 Printer */
      0x04f96611, /* HP Photosmart C4380 All-in-One Printer */
      0x04f96c11, /* HP Photosmart C4410 All-in-One Printer */
      0x04f99d11, /* HP Officejet 4400 K410 All-in-One Printer */
      0x04f97711, /* HP Deskjet F4440 All-in-One Printer */
      0x04f94712, /* HP Officejet 4500 Desktop All-in-One Printer - G510a */
      0x04f98c11, /* HP Deskjet F4500 All-in-One Printer Series */
      0x04f95712, /* HP Officejet 4500 All-in-One Printer - K710 */
      0x04f92a12, /* HP Officejet J4524 All-in-One Printer */
      0x04f96b11, /* HP Photosmart C4540 All-in-One Printer */
      0x04f9c511, /* HP Envy 4500 e-All-in-One */
      0x04f92e12, /* HP Officejet 4500 G510n-z All-in-One Printer */
      0x04f9c411, /* HP DeskJet Ink Advantage 4515 e-All-in-One Printer */
      0x04f99917, /* HP Color LaserJet CM4540 Multifunction Printer */
      0x04f99c17, /* HP LaserJet M4555 MFP */
      0x04f97411, /* HP Photosmart C4640 All-in-One Printer */
      0x04f96c17, /* HP Color LaserJet 4610n Printer */
      0x04f95812, /* HP OfficeJet 4610 All-in-One Printer Series */
      0x04f96512, /* HP Deskjet Ink Advantage 4610 All-in-One Printer Series */
      0x04f96612, /* HP Deskjet Ink Advantage 4620 e-All-in-One Printer */
      0x04f96412, /* HP OfficeJet 4620 e-All-in-One Printer */
      0x04f9c611, /* HP Officejet 4630 e-All-in-One Printer */
      0x04f9c811, /* HP Deskjet Ink Advantage 4640 e-All-in-One Printer series */
      0x04f91a17, /* HP Color LaserJet 4650 Printer */
      0x04f92b12, /* HP Officejet J4660 All-in-One Printer */
      0x04f92c12, /* HP Officejet J4680c All-in-One Printer */
      0x04f97511, /* HP Photosmart C4740 All-in-One Printer */
      0x04f96217, /* HP Color LaserJet 4700 Printer */
      0x04f97d17, /* HP Color LaserJet CM4730 Multifunction Printer */
      0x04f96317, /* HP Color LaserJet 4730xs Multifunction Printer */
      0x04f97917, /* HP LaserJet M5025 Multifunction Printer */
      0x04f97217, /* HP LaserJet M5035 Multifunction Printer */
      0x04f9a117, /* HP LaserJet M5039 Multifunction Printer */
      0x04f9c802, /* HP Photosmart D5060 Printer */
      0x04f95811, /* HP Photosmart C5140 All-in-One Printer */
      0x04f9c402, /* HP Photosmart D5145 Printer */
      0x04f92411, /* HP Officejet 5100 All-in-One Printer */
      0x04f95d11, /* HP Photosmart C5240 All-in-One Printer */
      0x04f96417, /* HP LaserJet 5200 Printer */
      0x04f96617, /* HP LaserJet 5200L Printer */
      0x04f98917, /* HP LaserJet 5200LX Printer */
      0x04f95117, /* HP Color LaserJet CP5225 */
      0x04f97111, /* HP Photosmart C5370 All-in-One Printer */
      0x04f91f12, /* HP Officejet Pro K5300 Printer */
      0x04f96811, /* HP Photosmart D5345 Printer */
      0x04f92012, /* HP Officejet Pro K5400dn Printer */
      0x04f98604, /* HP Deskjet 5420v Photo Printer */
      0x04f96d11, /* HP Photosmart D5460 Printer */
      0x04f93a11, /* HP Officejet 5505 All-in-One Printer */
      0x04f93012, /* HP Officejet J5505 All-in-One Printer */
      0x04f98211, /* HP Deskjet D5545 Printer */
      0x04f97211, /* HP Photosmart C5540 All-in-One Printer */
      0x04f9a111, /* HP Photosmart 5510 e-All-in-One */
      0x04f9b411, /* HP Photosmart 5510d e-All-in-One */
      0x04f99b17, /* HP Color LaserJet CP5520 Series Printer */
      0x04f9b111, /* HP Photosmart 5520 e-All-in-One */
      0x04f9b611, /* HP Deskjet Ink Advantage 5525 e-All-in-One */
      0x04f9c311, /* HP ENVY 5530 e-All-in-One Printer */
      0x04f91f17, /* HP Color LaserJet 5550n Printer */
      0x04f96004, /* HP Deskjet 5550 Color Inkjet Printer */
      0x04f94f11, /* HP Officejet 5600 Series All-in-One Printer */
      0x04f9cc11, /* HP Envy 5640 e-All-in-One */
      0x04f96104, /* HP Deskjet 5650 Color Inkjet Printer */
      0x04f95b11, /* HP Officejet J5725 All-in-One Printer */
      0x04f98104, /* HP Deskjet 5700 Color Inkjet Printer */
      0x04f9cd11, /* HP Officejet 5740 e-All-in-One */
      0x04f9a004, /* HP Deskjet 5800 Color Inkjet Printer */
      0x04f98704, /* HP Deskjet 5938 Photo Printer */
      0x04f94312, /* HP Officejet 6000 Wireless Printer - E609n */
      0x04f94212, /* HP Officejet 6000 Printer - E609a */
      0x04f96f17, /* HP Color LaserJet CP6015dn Printer */
      0x04f97c17, /* HP Color LaserJet CM6030 Multifunction Printer */
      0x04f99517, /* HP Color LaserJet CM6049 MFP */
      0x04f95911, /* HP Photosmart C6150 All-in-One Printer */
      0x04f95e12, /* HP OfficeJet 6100 ePrinter H611a */
      0x04f90b14, /* HP Designjet z6100ps 60in photo */
      0x04f9c502, /* HP Photosmart D6160 Printer */
      0x04f92d11, /* HP Officejet 6105 All-in-One Printer */
      0x04f93404, /* HP Deskjet 6120 Color Inkjet Printer */
      0x04f94b11, /* HP Officejet 6200 All-in-One Printer */
      0x04f91014, /* HP Designjet z6200PS 42in Photo */
      0x04f96a11, /* HP Photosmart C6240 All-in-One Printer */
      0x04f97312, /* HP OfficeJet Pro 6230 ePrinter */
      0x04f97011, /* HP Photosmart C6324 All-in-One Printer */
      0x04f95311, /* HP Officejet 6301 All-in-One Printer */
      0x04f93312, /* HP Officejet J6405 All-in-One Printer */
      0x04f94412, /* HP Officejet 6500 All-in-One Printer - E709a */
      0x04f95412, /* HP Officejet 6500 E710n-z */
      0x04f95512, /* HP Officejet 6500 E710 */
      0x04f94512, /* HP Officejet 6500 Wireless All-in-One Printer - E709n */
      0x04f98204, /* HP Deskjet 6500 Color Inkjet Printer */
      0x04f9a511, /* HP Photosmart 6510 e-All-in-one */
      0x04f9af11, /* HP Photsmart 6520 e All-in-One */
      0x04f9ba11, /* HP Deskjet Ink Advantage 6525 e-All-in-One */
      0x04f98504, /* HP Deskjet 6600 Series Color Inkjet Printer */
      0x04f95d12, /* HP Officejet 6600 e-All-in-One Printer - H711a */
      0x04f95c12, /* HP Officejet 6700 Premium e-All-in-One Printer-H711n */
      0x04f98404, /* HP Deskjet 6800 Color Inkjet Printer */
      0x04f97412, /* HP OfficeJet 6800 e-All-in-one */
      0x04f97212, /* HP OfficeJet Pro 6830 e-All-in-one */
      0x04f98804, /* HP Deskjet 6980xi Printer */
      0x04f94612, /* HP Officejet 7000 E809 series */
      0x04f92611, /* HP Officejet 7100 All-in-One Printer */
      0x04f95a11, /* HP Photosmart C7150 All-in-One Printer */
      0x04f92612, /* HP Officejet K7100 Printer */
      0x04f9c602, /* HP Photosmart D7145 Printer */
      0x04f96012, /* HP Officejet 7110 Wide Format ePrinter */
      0x04f96911, /* HP Photosmart D7245 Printer */
      0x04f9b002, /* HP Photosmart 7260w Photo Printer */
      0x04f94111, /* HP Officejet 7205 All-in-One Printer */
      0x04f96511, /* HP Photosmart C7250 All-in-One Printer */
      0x04f94211, /* HP Officejet 7310 All-in-One Printer */
      0x04f92512, /* HP Officejet Pro L7300 Series All-in-One Printer */
      0x04f9c702, /* HP Photosmart D7345 Printer */
      0x04f92002, /* HP Photosmart 7345 Printer */
      0x04f94311, /* HP Officejet 7408 All-in-One Printer */
      0x04f9b802, /* HP Photosmart 7450 Photo Printer */
      0x04f95e11, /* HP Photosmart D7460 Printer */
      0x04f93412, /* HP Officejet Pro L7480 All-in-One Printer */
      0x04f92112, /* HP Officejet Pro L7500 Series All-in-One Printer */
      0x04f94812, /* HP Officejet 7500 E910 */
      0x04f96f11, /* HP Photosmart D7560 Printer */
      0x04f9a611, /* HP Photosmart 7510 e-All-in-One */
      0x04f9bc11, /* HP Photosmart 7520 e-All-in-One */
      0x04f93e02, /* HP Photosmart 7550 Printer */
      0x04f92212, /* HP Officejet Pro L7600 Series All-in-One Printer */
      0x04f9b202, /* HP Photosmart 7655 Photo Printer */
      0x04f96e12, /* HP Officejet 7610 Wide Format e-All-in-One Printer */
      0x04f9dc11, /* HP Envy 7640 e-All-in-One */
      0x04f92312, /* HP Officejet Pro L7700 Series All-in-One Printer */
      0x04f9b402, /* HP Photosmart 7755 Photo Printer */
      0x04f9c002, /* HP Photosmart 7830 Printer */
      0x04f9b602, /* HP Photosmart 7960 Photo Printer */
      0x04f9d011, /* HP Envy 8000 e-All-in-One */
      0x04f95612, /* HP Officejet Pro 8000 Enterprise A811a */
      0x04f93612, /* HP Officejet Pro 8000 Printer - A809a */
      0x04f9c102, /* HP Photosmart 8030 Printer */
      0x04f9de11, /* HP OfficeJet 8040 e-All-in-One */
      0x04f97717, /* HP CM8050 Color Multifunction Printer with Edgeline Technology */
      0x04f97117, /* HP CM8060 Color Multifunction Printer with Edgeline Technology */
      0x04f95b12, /* HP OfficeJet Pro 8100 ePrinter-N811a */
      0x04f96411, /* HP Photosmart C8150 All-in-One Printer */
      0x04f9ba02, /* HP Photosmart 8150 Photo Printer */
      0x04f9c202, /* HP Photosmart 8230 Printer */
      0x04f9be02, /* HP Photosmart Pro B8330 Printer */
      0x04f9bb02, /* HP Photosmart 8450gp Photo Printer */
      0x04f93812, /* HP Officejet Pro 8500 All-in-One Printer - A909a */
      0x04f94012, /* HP Officejet Pro 8500 Premier All-in-One Printer - A909n */
      0x04f93912, /* HP Officejet Pro 8500 Wireless All-in-One Printer - A909g */
      0x04f9d102, /* HP Photosmart B8550 Photo Printer */
      0x04f95312, /* HP OfficeJet Pro 8500A Plus e-AiO Printer - A910g */
      0x04f92712, /* HP Officejet Pro K8600 Color Printer */
      0x04f95912, /* HP OfficeJet Pro 8600 e-AiO N911a */
      0x04f97112, /* HP OfficeJet Pro 8610 e-All-in-One Printer */
      0x04f97012, /* HP OfficeJet Pro 8620 e-All-in-One Printer */
      0x04f96f12, /* HP OfficeJet Pro 8630 e-All-in-One Printer */
      0x04f97712, /* HP OfficeJet Pro 8640 e-All-in-One Printer */
      0x04f97612, /* HP OfficeJet Pro 8660 e-All-in-One Printer */
      0x04f9bc02, /* HP Photosmart 8750 Professional Photo Printer */
      0x04f9d002, /* HP Photosmart Pro B8850 Printer */
      0x04f98417, /* HP LaserJet 9040 Multifunction Printer */
      0x04f92017, /* HP LaserJet 9040 Printer */
      0x04f92117, /* HP LaserJet 9050 Multifunction Printer */
      0x04f98317, /* HP LaserJet M9050 Multifunction Printer */
      0x04f99617, /* HP LaserJet M9059 MFP */
      0x04f90d12, /* HP Officejet 9110 All-in-One Printer */
      0x04f9bd02, /* HP Photosmart Pro B9180gp Photo Printer */
      0x04f92217, /* HP Color LaserJet 9500n Printer */
      0x04f90b12, /* HP Deskjet 9650 Printer */
      0x04f91212, /* HP Deskjet 9800 Printer */
      0x04f93c2a, /* HP Color LaserJet Pro M252n */
      0x04f9382a, /* HP Color LaserJet Enterprise M553n */
      0x04f9582a, /* HP Color LaserJet Enterprise M552dn */
      0x04f9552a, /* HP LaserJet Enterprise M604n */
      0x04f93e2a, /* HP LaserJet Enterprise M605n */
      0x04f93f2a, /* HP LaserJet Enterprise M606dn */
      0x04f9e311, /* HP DeskJet 3630 All-in-One Printer */
      0x04f9e111, /* HP DeskJet 2130 All-in-One Printer series */
      0x04f9df11, /* HP Deskjet 1110 Printer */
      0x04f9e511, /* HP OfficeJet 3830 All-in-One Printer */
      0x04f9e611, /* HP DeskJet Ink Advantage 3830 All-in-One Printer */
      0x04f9d911, /* HP OfficeJet 4650 All-in-One Printer series */
      0x04f9d711, /* HP ENVY 4520 All-in-One Printer series */
      0x04f9ce11, /* HP Envy 5540 All-in-One Printer series */
      0x04f9e811, /* HP Envy 4510 All-in-One */
      0x04f9842a, /* HP Color LaserJet Pro MFP M274n */
      0x04f9e211, /* HP DeskJet Ink Advantage Ultra 4720 All-in-One Printer series */
      0x04f9db11, /* HP DeskJet Ink Advantage 5640 All-in-One Printer series */
      0x04f9da11, /* HP DeskJet Ink Advantage 4670 All-in-One */
      0x04f9d811, /* HP DeskJet Ink Advantage 4530 All-in-One */
      0x04f9422a, /* HP LaserJet Enterprise M506 series */
      0x04f9542a, /* HP LaserJet Pro M402dw */
      0x04f9602a, /* HP LaserJet Pro M402n */
      0x04f9522a, /* HP Color Laserjet Pro M452dn */
      0x04f95a2a, /* HP Laserjet Pro MFP M426fdn */
      0x04f9402a, /* HP Laserjet Enterprise MFP M527dn */
      0x04f9412a, /* HP Laserjet Enterprise Flow MFP M527c */
      0x04f95305, /* HP Scanjet Pro 3500 f1 Flatbed Scanner */
      0x04f93a2a, /* HP Color LaserJet Enterprise MFP M577 Series */
      0x04f94a2a, /* HP Color LaserJet Enterprise Flow MFP M577 Series */
      0x04f9512a, /* HP Color Laserjet Pro MFP M477 fnw */
      0x04f9d611, /* HP PageWide Pro 577dw Multifunction Printer */
      0x04f9d311, /* HP PageWide Pro 552dw Printer */
      0x04f9d211, /* HP PageWide Pro 452dw Printer */
      0x04f9d111, /* HP PageWide Pro 452dn Printer */
      0x04f9d511, /* HP PageWide Pro 477dw Multifunction Printer */
      0x04f9d411, /* HP PageWide Pro 477dn Multifunction Printer */
      0x04f9ed11, /* HP DeskJet GT 5810 All-in-One Printer */
      0x04f9ee11, /* HP DeskJet GT 5820 All-in-One Printer */
      0x04f9e711, /* HP OfficeJet 200 Mobile Printer */
      0x04f97a12, /* HP OfficeJet Pro 8710 All-in-One Printer */
      0x04f96312, /* HP OfficeJet Pro 8740 All-in-One Printer */
      0x04f97b12, /* HP OfficeJet Pro 8720 All-in-One Printer */
      0x04f9652a, /* HP Laserjet Pro M501n */
      0x04f9832a, /* HP PageWide Enterprise Color MFP 586dn */
      0x04f9822a, /* HP PageWide Enterprise Color Flow MFP 586z */
      0x04f9fa11, /* HP PageWide Managed MFP P57750dw */
      0x04f9f911, /* HP PageWide Managed P55250dw */
      0x04f97d12, /* HP OfficeJet Pro 8210 */
      0x04f9862a, /* HP Color Laserjet MFP M377 fnw */
      0x04f9f511, /* HP DeskJet Ink Advantage Ultra 5738 All-in-One Printer */
      0x04f91254, /* HP ENVY Photo 6200 All-in-One */
      0x04f91154, /* HP ENVY Photo 7100 All-in-One */
      0x04f91054, /* HP ENVY Photo 7800 All-in-One */
      0x04f9e911, /* HP OfficeJet 250 Mobile All-in-One */
      0x04f90d54, /* HP OfficeJet Pro 6960 All-in-One */
      0x04f90c54, /* HP OfficeJet Pro 6970 All-in-One */
      0x04f903f0, /* HP DeskJet 3700 All-in-One */
      0x04f90e54, /* HP OfficeJet 6960 All-in-One */
      0x04f9802a, /* HP PageWide Managed Color E55650dn */
      0x04f91554, /* HP OfficeJet Pro 8732 All-in-One Printer */
      0x04f90954, /* HP OfficeJet 8702 All-in-One */
      0x04f9f211, /* HP PageWide MFP 377dw */
      0x04f90154, /* HP OfficeJet Pro 7740 Wide Format All-in-One */
      0x04f90f54, /* HP OfficeJet 6950 All-in-One */
      0x04f95605, /* HP Scanjet Pro 3000 S3 */
      0x04f95705, /* HP Scanjet Enterprise Flow 5000 S4 */
      0x04f95805, /* HP Scanjet Enterprise Flow 7000 S3 */
      0x04f9612a, /* HP LaserJet M102a */
      0x04f91654, /* HP OfficeJet Pro 7720 Wide Format All-in-One */
      0x04f91754, /* HP OfficeJet Pro 7730 Wide Format All-in-One */
      0x04f90853, /* HP ENVY 5000 All-in-One */
      0x04f90a54, /* HP DeskJet Ink Advantage 5075 All-in-One */
      0x04f9632a, /* HP LaserJet Pro M203d */
      0x04f9642a, /* HP LaserJet Pro MFP M227sdn */
      0x04f9622a, /* HP LaserJet Pro MFP M132a */
      0x04f90b53, /* HP DeskJet Ink Advantage 5275 All-in-One */
      0x04f9b22a, /* HP Color LaserJet Managed Flow MFP E77830z */
      0x04f9b32a, /* HP Color LaserJet Managed MFP E87640 dn */
      0x04f9b12a, /* HP LaserJet Managed MFP E82540dn */
      0x04f9b02a, /* HP LaserJet Managed MFP E72525dn */
      0x04f96b2a, /* HP LaserJet Enterprise M607n */
      0x04f96c2a, /* HP LaserJet Managed E60055dn */
      0x04f9672a, /* HP LaserJet Enterprise MFP M631dn */
      0x04f9682a, /* HP LaserJet Managed MFP E62555dn */
      0x04f9a32a, /* HP Color LaserJet Enterprise M652n */
      0x04f9a42a, /* HP Color LaserJet Managed E65050dn */
      0x04f9a52a, /* HP Color LaserJet Enterprise MFP M681dh */
      0x04f9a62a, /* HP Color LaserJet Managed MFP E67550dh */
      0x04f9fe11, /* HP PageWide Pro 750dn */
      0x04f9eb11, /* HP PageWide Pro MFP 772dw */
      0x04f9fc11, /* HP PageWide Managed MFP P77740zs */
      0x04f9f611, /* HP PageWide Managed P75050dn */
      0x04f9932a, /* HP LaserJet Pro MFP M26a */
      0x04f90753, /* HP DeskJet 2200 All-in-One */
      0x04f90053, /* HP DeskJet 2620 All-in-One */
      0x04f9b62a, /* HP PageWide Enterprise Color 765dn */
      0x04f9b72a, /* HP PageWide Managed Color E75160dn */
      0x04f90e53, /* HP AMP All-in-One */
      0x04f9b42a, /* HP PageWide Enterprise Color MFP 780dn */
      0x04f9b52a, /* HP PageWide Managed Color MFP E77650dn */
      0x04f9ba2a, /* HP Scanjet Enterprise Flow N9120 fn2 Document Scanner */
      0x04f9b92a, /* HP Digital Sender Flow 8500 fn2 Document Capture Workstation */
      0x04f9be2a, /* HP LaserJet Pro M15w */
      0x04f9bf2a, /* HP LaserJet Pro MFP M28w */
      0x04f9ac2a, /* HP Color LaserJet Pro M253a */
      0x04f9af2a, /* HP Color LaserJet Pro MFP M180nw */
      0x04f9ad2a, /* HP Color LaserJet Pro MFP M281fdw */
      0x04f9ae2a, /* HP Color LaserJet Pro M154a */
      0x04f9c92a, /* HP PageWide Managed Color MFP P77440dn */
      0x04f9c72a, /* HP PageWide Managed Color MFP P77450dn */
      0x04f90f53, /* HP Smart Tank 350 */
      0x04f91253, /* HP Smart Tank Wireless 450 */
      0x04f91053, /* HP Ink Tank 310 */
      0x04f91353, /* HP Ink Tank Wireless 410 */
      0x04f91453, /* HP Ink Tank 115 */
      0x04f9ef2a, /* HP PageWide 755dn */
      0x04f9ee2a, /* HP PageWide MFP 774dn */
      0x04f9e92a, /* HP LaserJet Pro M118dw */
      0x04f9ec2a, /* HP LaserJet Pro MFP M148dw */
      0x04f9ed2a, /* HP LaserJet Pro MFP M148fdw */
      0x04f98411, /* HP Scanjet Enterprise 7500 */
      0x04f92454, /* HP OfficeJet Pro All-in-One 9010 */
      0x04f92354, /* HP OfficeJet Pro All-in-One 9020 */
      0x04f92554, /* HP OfficeJet All-in-One 9010 */
      0x04f92654, /* HP OfficeJet Pro 8030 All-in-One Printer series */
      0x04f92854, /* HP OfficeJet 8020 All-in-One Printer series */
      0x04f92754, /* HP OfficeJet Pro 8020 All-in-One Printer series */
      0x04f92954, /* HP OfficeJet 8010 All-in-One Printer series */
      0x04f91c54, /* HP Smart Tank Plus 650 */
      0x04f91b54, /* HP Smart Tank 610 */
      0x04f91a54, /* HP Smart Tank Plus 550 */
      0x04f91954, /* HP Smart Tank 510 */
      0x04f9e32a, /* HP LaserJet Managed MFP E62655dn */
      0x04f9e02a, /* HP LaserJet Managed E60155dn */
      0x04f9e22a, /* HP Color LaserJet Managed MFP E67650dh */
      0x04f9e12a, /* HP Color LaserJet Managed E65150dn */
      0x04f9f42a, /* HP Neverstop Laser MFP 1200a */
      0x04f9f32a, /* HP Neverstop Laser 1000a */
      0x04f9f02a, /* HP Laser NS 1020 */
      0x04f9f12a, /* HP Laser NS MFP 1005 */
      0x04f92b54, /* HP Smart Tank 500 series */
      0x04f92a54, /* HP Smart Tank 530 series */
      0x04f92d54, /* HP Smart Tank Plus 570 series */
      0x04f9ca2a, /* HP LaserJet Enterprise M507n */
      0x04f9d22a, /* HP Laserjet Managed E50145dn */
      0x04f9cc2a, /* HP LaserJet Enterprise MFP M528dn */
      0x04f9d32a, /* HP LaserJet Managed MFP E52645dn */
      0x04f99d2a, /* HP Color LaserJet Enterprise M751n */
      0x04f99e2a, /* HP Color LaserJet Managed E75245dn */
      0x04f9de2a, /* HP LaserJet Pro M305d */
      0x04f9c12a, /* HP LaserJet Pro M404d */
      0x04f9c22a, /* HP LaserJet Pro MFP M428dw */
      0x04f9df2a, /* HP LaserJet Pro MFP M329dn */
      0x04f9c32a, /* HP LaserJet Pro MFP M428fdn */
      0x04f9c42a, /* HP Color LaserJet Pro M453cdn */
      0x04f9c62a, /* HP Color LaserJet Pro MFP M479dw */
      0x04f9c52a, /* HP Color LaserJet Pro MFP M478fcdn */
      0x04f99f2a, /* HP Color LaserJet Enterprise MFP M776dn */
      0x04f9a12a, /* HP Color laserjet Enterprise M856dn */
      0x04f9a22a, /* HP Color laserjet Managed E85055 */
      0x04f90c70, /* HP Color LaserJet Pro M155a */
      0x04f90a70, /* HP Color LaserJet Pro M256dn */
      0x04f90970, /* HP Color LaserJet Pro MFP M282nw */
      0x04f90870, /* HP Color LaserJet Pro MFP M182n */
      0x04f95a05, /* HP Scanjet Pro 2000 S2 */
      0x04f95e05, /* HP ScanJet Enterprise Flow N7000 snw1 */
      0x04f95c05, /* HP ScanJet Pro N4000 snw1 */
      0x04f95b05, /* HP ScanJet Pro 3000 s4 */
      0x04f95d05, /* HP ScanJet Enterprise Flow 5000 s5 */
    };

    /* Taken from epkowa.desc from iscan-data package for Epson driver */
    private const uint32 epkowa_devices[] = { 0x04b80101, 0x04b80102, 0x04b80103, 0x04b80104, 0x04b80105, 0x04b80106, 0x04b80107, 0x04b80108, 0x04b80109, 0x04b8010a, 0x04b8010b, 0x04b8010c, 0x04b8010d, 0x04b8010e, 0x04b8010f, 0x04b80110, 0x04b80112, 0x04b80114, 0x04b80116, 0x04b80118, 0x04b80119, 0x04b8011a, 0x04b8011b, 0x04b8011c, 0x04b8011d, 0x04b8011e, 0x04b8011f, 0x04b80120, 0x04b80121, 0x04b80122, 0x04b80126, 0x04b80128, 0x04b80129, 0x04b8012a, 0x04b8012b, 0x04b8012c, 0x04b8012d, 0x04b8012e, 0x04b8012f, 0x04b80130, 0x04b80131, 0x04b80133, 0x04b80135, 0x04b80136, 0x04b80137, 0x04b80138, 0x04b8013a, 0x04b8013b, 0x04b8013c, 0x04b8013d, 0x04b80142, 0x04b80143, 0x04b80144, 0x04b80147, 0x04b8014a, 0x04b8014b, 0x04b80151, 0x04b80153, 0x04b80801, 0x04b80802, 0x04b80805, 0x04b80806, 0x04b80807, 0x04b80808, 0x04b8080a, 0x04b8080c, 0x04b8080d, 0x04b8080e, 0x04b8080f, 0x04b80810, 0x04b80811, 0x04b80813, 0x04b80814, 0x04b80815, 0x04b80817, 0x04b80818, 0x04b80819, 0x04b8081a, 0x04b8081c, 0x04b8081d, 0x04b8081f, 0x04b80820, 0x04b80821, 0x04b80827, 0x04b80828, 0x04b80829, 0x04b8082a, 0x04b8082b, 0x04b8082e, 0x04b8082f, 0x04b80830, 0x04b80831, 0x04b80833, 0x04b80834, 0x04b80835, 0x04b80836, 0x04b80837, 0x04b80838, 0x04b80839, 0x04b8083a, 0x04b8083c, 0x04b8083f, 0x04b80841, 0x04b80843, 0x04b80844, 0x04b80846, 0x04b80847, 0x04b80848, 0x04b80849, 0x04b8084a, 0x04b8084c, 0x04b8084d, 0x04b8084f, 0x04b80850, 0x04b80851, 0x04b80852, 0x04b80853, 0x04b80854, 0x04b80855, 0x04b80856, 0x04b8085c, 0x04b8085d, 0x04b8085e, 0x04b8085f, 0x04b80860, 0x04b80861, 0x04b80862, 0x04b80863, 0x04b80864, 0x04b80865, 0x04b80866, 0x04b80869, 0x04b8086a, 0x04b80870, 0x04b80871, 0x04b80872, 0x04b80873, 0x04b80878, 0x04b80879, 0x04b8087b, 0x04b8087c, 0x04b8087d, 0x04b8087e, 0x04b8087f, 0x04b80880, 0x04b80881, 0x04b80883, 0x04b80884, 0x04b80885, 0x04b8088f, 0x04b80890, 0x04b80891, 0x04b80892, 0x04b80893, 0x04b80894, 0x04b80895, 0x04b80896, 0x04b80897, 0x04b80898, 0x04b80899, 0x04b8089a, 0x04b8089b, 0x04b8089c, 0x04b8089d, 0x04b8089e, 0x04b8089f, 0x04b808a0, 0x04b808a1, 0x04b808a5, 0x04b808a6, 0x04b808a8, 0x04b808a9, 0x04b808aa, 0x04b808ab, 0x04b808ac, 0x04b808ad, 0x04b808ae, 0x04b808af, 0x04b808b0, 0x04b808b3, 0x04b808b4, 0x04b808b5, 0x04b808b6, 0x04b808b7, 0x04b808b8, 0x04b808b9, 0x04b808bd, 0x04b808be, 0x04b808bf, 0x04b808c0, 0x04b808c1, 0x04b808c3, 0x04b808c4, 0x04b808c5, 0x04b808c6, 0x04b808c7, 0x04b808c8, 0x04b808c9, 0x04b808ca, 0x04b808cd, 0x04b808d0 };


    /* Taken from /usr/local/lexmark/unix_scan_drivers/etc/lexmark_nscan.conf */
    /* Lexmark IDs extracted using command:
     * grep -r "usb .* /usr" --no-filename --only-matching | sed 's/usb //' | sed 's/ 0x//' | sed 's/ \/usr/,/'
     */
    private const uint32 lexmark_nscan_devices[] = {
    0x043d0279,
    0x043d027a,
    0x043d01D6,
    0x043d01D7,
    0x043d01D8,
    0x043d01DC,
    0x043d01DE,
    0x043d01E0,
    0x043d01FA,
    0x043d01FB,
    0x043d01FC,
    0x043d01FD,
    0x043d01FE,
    0x043d01FF,
    0x043d01F4,
    0x043d0120,
    0x043d0121,
    0x043d0128,
    0x043d014F,
    0x043d0149,
    0x043d0152,
    0x043d0168,
    0x043d0169,
    0x043d016A,
    0x043d012D,
    0x043d01C4,
    0x043d01C5,
    0x043d01C6,
    0x043d01CF,
    0x043d01D0,
    0x043d01D1,
    0x043d01DB,
    0x043d01ED,
    0x043d01F1,
    0x043d01F5,
    0x043d0222,
    0x043d0223,
    0x043d0227,
    0x043d0228,
    0x043d022A,
    0x043d022B,
    0x043d022F,
    0x043d0230,
    0x043d0231,
    0x043d0234,
    0x043d0235,
    0x043d0244,
    0x043d0245,
    0x043d0246,
    0x043d0247,
    0x043d0248,
    0x043d024A,
    0x043d024E,
    0x043d024F
    };

    /* Brother IDs extracted using the following Python
     *
     *  import sys
     *  for f in sys.argv:
     *    for l in file (f).readlines ():
     *      tokens = l.strip().split (',')
     *      if len (tokens) >= 4:
     *        print ('    0x%08x' % (0x04f9 << 16 | int (tokens[0], 16)) + ", /* " + tokens[3].strip("\"") + " * /")
     */

    /* HPAIO IDs extracted using the following Python:
      import sys
      ids = []
      for f in sys.argv:
        for l in file (f).readlines ():
          if l.startswith ('model1='):
            model=l[7:].strip ()
          elif l.startswith ('usb-pid='):
            pid = int (l[8:].strip (), 16)
            if pid == 0:
              continue
            usb_id = '0x%08x' % (0x04f9 << 16 | pid)
            if not usb_id in ids:
              ids.append (usb_id)
              print (usb_id + ", /* " + model + " * /")
     */

    public string? suggest_driver ()
    {
        if (usb_context == null)
            return null;

        var driver_map = new HashTable <uint32, string> (direct_hash, direct_equal);
        add_devices (driver_map, brscan_devices, "brscan");
        add_devices (driver_map, brscan2_devices, "brscan2");
        add_devices (driver_map, brscan3_devices, "brscan3");
        add_devices (driver_map, brscan4_devices, "brscan4");
        add_devices (driver_map, pixma_devices, "pixma");
        add_devices (driver_map, samsung_devices, "samsung");
        add_devices (driver_map, smfp_devices, "smfp");
        add_devices (driver_map, hpaio_devices, "hpaio");
        add_devices (driver_map, epkowa_devices, "epkowa");
        add_devices (driver_map, lexmark_nscan_devices, "lexmark_nscan");
        var devices = usb_context.get_devices ();
        for (var i = 0; i < devices.length; i++)
        {
            var device = devices.data[i];
            var driver = driver_map.lookup (device.get_vid () << 16 | device.get_pid ());
            if (driver != null)
                return driver;
        }

        return null;
    }

    private void add_devices (HashTable<uint32, string> map, uint32[] devices, string driver)
    {
        for (var i = 0; i < devices.length; i++)
            map.insert (devices[i], driver);
    }

    private void authorize_cb (Scanner scanner, string resource)
    {
        app.authorize.begin (resource, (obj, res) =>
        {
            var data = app.authorize.end(res);
            if (data.success)
            {
                scanner.authorize (data.username, data.password);
            }
        });
    }

    private Page append_page (int width = 100, int height = 100, int dpi = 100)
    {
        /* Use current page if not used */
        var page = book.get_page (-1);
        if (page != null && !page.has_data)
        {
            app.selected_page = page;
            page.start ();
            return page;
        }

        /* Copy info from previous page */
        var scan_direction = ScanDirection.TOP_TO_BOTTOM;
        bool do_crop = false;
        string named_crop = null;
        var cx = 0, cy = 0, cw = 0, ch = 0;
        if (page != null)
        {
            scan_direction = page.scan_direction;
            width = page.width;
            height = page.height;
            dpi = page.dpi;

            do_crop = page.has_crop;
            if (do_crop)
            {
                named_crop = page.crop_name;
                cx = page.crop_x;
                cy = page.crop_y;
                cw = page.crop_width;
                ch = page.crop_height;
            }
        }

        page = new Page (width, height, dpi, scan_direction);
        book.append_page (page);
        if (do_crop)
        {
            if (named_crop != null)
            {
                page.set_named_crop (named_crop);
            }
            else
                page.set_custom_crop (cw, ch);
            page.move_crop (cx, cy);
        }
        app.selected_page = page;
        page.start ();

        return page;
    }

    private void scanner_new_page_cb (Scanner scanner)
    {
        append_page ();
    }

    private string? get_profile_for_device (string device_name)
    {
#if HAVE_COLORD
        var device_id = "sane:%s".printf (device_name);
        debug ("Getting color profile for device %s", device_name);

        var client = new Cd.Client ();
        try
        {
            client.connect_sync ();
        }
        catch (Error e)
        {
            debug ("Failed to connect to colord: %s", e.message);
            return null;
        }

        Cd.Device device;
        try
        {
            device = client.find_device_by_property_sync (Cd.DEVICE_PROPERTY_SERIAL, device_id);
        }
        catch (Error e)
        {
            debug ("Unable to find colord device %s: %s", device_name, e.message);
            return null;
        }

        try
        {
            device.connect_sync ();
        }
        catch (Error e)
        {
            debug ("Failed to get properties from the device %s: %s", device_name, e.message);
            return null;
        }

        var profile = device.get_default_profile ();
        if (profile == null)
        {
            debug ("No default color profile for device: %s", device_name);
            return null;
        }

        try
        {
            profile.connect_sync ();
        }
        catch (Error e)
        {
            debug ("Failed to get properties from the profile %s: %s", device_name, e.message);
            return null;
        }

        if (profile.filename == null)
        {
            debug ("No icc color profile for the device %s", device_name);
            return null;
        }

        debug ("Using color profile %s for device %s", profile.filename, device_name);
        return profile.filename;
#else
        return null;
#endif
    }

    private void scanner_page_info_cb (Scanner scanner, ScanPageInfo info)
    {
        debug ("Page is %d pixels wide, %d pixels high, %d bits per pixel",
               info.width, info.height, info.depth);

        /* Add a new page */
        scanned_page = append_page ();
        scanned_page.set_page_info (info);

        /* Get ICC color profile */
        /* FIXME: The ICC profile could change */
        /* FIXME: Don't do a D-bus call for each page, cache color profiles */
        scanned_page.color_profile = get_profile_for_device (info.device);
    }

    private void scanner_line_cb (Scanner scanner, ScanLine line)
    {
        scanned_page.parse_scan_line (line);
    }

    private void scanner_page_done_cb (Scanner scanner)
    {
        scanned_page.finish ();
        scanned_page = null;
    }

    private void remove_empty_page ()
    {
        var page = book.get_page ((int) book.n_pages - 1);
        if (!page.has_data)
            book.delete_page (page);
    }

    private void scanner_document_done_cb (Scanner scanner)
    {
        remove_empty_page ();
    }

    private void scanner_failed_cb (Scanner scanner, int error_code, string error_string)
    {
        remove_empty_page ();
        scanned_page = null;
        if (error_code != Sane.Status.CANCELLED)
        {
            app.show_error_dialog (/* Title of error dialog when scan failed */
                                   _("Failed to scan"),
                                   error_string);
        }
    }

    private uint inhibit_cookie;
    private FreedesktopScreensaver? fdss;

    private void scanner_scanning_changed_cb (Scanner scanner)
    {
        var is_scanning = scanner.is_scanning ();

        if (is_scanning)
        {
            /* Attempt to inhibit the screensaver when scanning */
            var reason = _("Scan in progress");

            /* This should work on Gnome, Budgie, Cinnamon, Mate, Unity, ...
             * but will not work on KDE, LXDE, XFCE, ... */
            inhibit_cookie = inhibit (app, Gtk.ApplicationInhibitFlags.IDLE, reason);

            if (inhibit_cookie == 0)
            {
                /* If the previous method didn't work, try the one
                 * provided by Freedesktop. It should work with KDE,
                 * LXDE, XFCE, and maybe others as well. */
                try
                {
                    if ((fdss = FreedesktopScreensaver.get_proxy ()) != null)
                    {
                        inhibit_cookie = fdss.inhibit ("Simple-Scan", reason);
                    }
                }
                catch (Error error) {}
            }
        }
        else
        {
            /* When finished scanning, uninhibit if inhibit was working */
            if (inhibit_cookie != 0)
            {
                if (fdss == null)
                        uninhibit (inhibit_cookie);
                else
                {
                    try
                    {
                        fdss.uninhibit (inhibit_cookie);
                    }
                    catch (Error error) {}
                    fdss = null;
                }

                inhibit_cookie = 0;
            }
        }

        app.scanning = is_scanning;
    }

    private void scan_cb (AppWindow ui, string? device, ScanOptions options)
    {
        debug ("Requesting scan at %d dpi from device '%s'", options.dpi, device);

        if (!scanner.is_scanning ())
            // We need to add +1 to avoid visual glitches, fixes: #179
            append_page (options.paper_width + 1, options.paper_height + 1, options.dpi + 1);

        scanner.scan (device, options);
    }

    private void cancel_cb (AppWindow ui)
    {
        scanner.cancel ();
    }

    private void redetect_cb (AppWindow ui)
    {
        scanner.redetect ();
    }


    private static void log_cb (string? log_domain, LogLevelFlags log_level, string message)
    {
        string prefix;

        switch (log_level & LogLevelFlags.LEVEL_MASK)
        {
        case LogLevelFlags.LEVEL_ERROR:
            prefix = "ERROR:";
            break;
        case LogLevelFlags.LEVEL_CRITICAL:
            prefix = "CRITICAL:";
            break;
        case LogLevelFlags.LEVEL_WARNING:
            prefix = "WARNING:";
            break;
        case LogLevelFlags.LEVEL_MESSAGE:
            prefix = "MESSAGE:";
            break;
        case LogLevelFlags.LEVEL_INFO:
            prefix = "INFO:";
            break;
        case LogLevelFlags.LEVEL_DEBUG:
            prefix = "DEBUG:";
            break;
        default:
            prefix = "LOG:";
            break;
        }

        log_file.printf ("[%+.2fs] %s %s\n", log_timer.elapsed (), prefix, message);
        if (debug_enabled)
            stderr.printf ("[%+.2fs] %s %s\n", log_timer.elapsed (), prefix, message);
    }

    private static void fix_pdf (string filename) throws Error
    {
        uint8[] data;
        FileUtils.get_data (filename, out data);

        var fixed_file = FileStream.open (filename + ".fixed", "w");

        var offset = 0;
        var line_number = 0;
        var xref_offset = 0;
        var xref_line = -1;
        var startxref_line = -1;
        var fixed_size = -1;
        var line = new StringBuilder ();
        while (offset < data.length)
        {
            var end_offset = offset;
            line.assign ("");
            while (end_offset < data.length)
            {
                var c = data[end_offset];
                line.append_c ((char) c);
                end_offset++;
                if (c == '\n')
                    break;
            }

            if (line.str == "startxref\n")
                startxref_line = line_number;

            if (line.str == "xref\n")
                xref_line = line_number;

            /* Fix PDF header and binary comment */
            if (line_number < 2 && line.str.has_prefix ("%%"))
            {
                xref_offset--;
                fixed_file.printf ("%s", line.str.substring (1));
            }

            /* Fix xref subsection count */
            else if (line_number == xref_line + 1 && line.str.has_prefix ("1 "))
            {
                fixed_size = int.parse (line.str.substring (2)) + 1;
                fixed_file.printf ("0 %d\n", fixed_size);
                fixed_file.printf ("0000000000 65535 f \n");
            }

            /* Fix xref format */
            else if (line_number > xref_line && line.str.has_suffix (" 0000 n\n"))
                fixed_file.printf ("%010d 00000 n \n", int.parse (line.str) + xref_offset);

            /* Fix xref offset */
            else if (startxref_line > 0 && line_number == startxref_line + 1)
                fixed_file.printf ("%d\n".printf (int.parse (line.str) + xref_offset));

            else if (fixed_size > 0 && line.str.has_prefix ("/Size "))
                fixed_file.printf ("/Size %d\n".printf (fixed_size));

            /* Fix EOF marker */
            else if (line_number == startxref_line + 2 && line.str.has_prefix ("%%%%"))
                fixed_file.printf ("%s", line.str.substring (2));

            else
                for (var i = offset; i < end_offset; i++)
                    fixed_file.putc ((char) data[i]);

            line_number++;
            offset = end_offset;
        }

        if (FileUtils.rename (filename, filename + "~") >= 0)
            FileUtils.rename (filename + ".fixed", filename);
    }

    public static int main (string[] args)
    {
        Intl.setlocale (LocaleCategory.ALL, "");
        Intl.bindtextdomain (GETTEXT_PACKAGE, LOCALE_DIR);
        Intl.bind_textdomain_codeset (GETTEXT_PACKAGE, "UTF-8");
        Intl.textdomain (GETTEXT_PACKAGE);

        var c = new OptionContext (/* Arguments and description for --help text */
                                   _("[DEVICE…] — Scanning utility"));
        c.add_main_entries (options, GETTEXT_PACKAGE);
        try
        {
            c.parse (ref args);
        }
        catch (Error e)
        {
            stderr.printf ("%s\n", e.message);
            stderr.printf (/* Text printed out when an unknown command-line argument provided */
                           _("Run “%s --help” to see a full list of available command line options."), args[0]);
            stderr.printf ("\n");
            return Posix.EXIT_FAILURE;
        }
        if (show_version)
        {
            /* Note, not translated so can be easily parsed */
            stderr.printf ("simple-scan %s\n", VERSION);
            return Posix.EXIT_SUCCESS;
        }
        if (fix_pdf_filename != null)
        {
            try
            {
                fix_pdf (fix_pdf_filename);
                for (var i = 1; i < args.length; i++)
                    fix_pdf (args[i]);
            }
            catch (Error e)
            {
                stderr.printf ("Error fixing PDF file: %s\n", e.message);
                return Posix.EXIT_FAILURE;
            }
            return Posix.EXIT_SUCCESS;
        }

        ScanDevice? device = null;
        if (args.length > 1)
        {
            device = new ScanDevice ();
            device.name = args[1];
            device.label = args[1];
        }

        /* Log to a file */
        log_timer = new Timer ();
        var path = Path.build_filename (Environment.get_user_cache_dir (), "simple-scan", null);
        DirUtils.create_with_parents (path, 0700);
        path = Path.build_filename (Environment.get_user_cache_dir (), "simple-scan", "simple-scan.log", null);
        log_file = FileStream.open (path, "w");
        if (log_file == null )
        {
            stderr.printf ("Error: Unable to open %s file for writing\n", path);
            return Posix.EXIT_FAILURE;
        }
        Log.set_default_handler (log_cb);

        debug ("Starting %s %s, PID=%i", args[0], VERSION, Posix.getpid ());

        Gtk.init ();

        var app = new SimpleScan (device);
        return app.run ();
    }
}
