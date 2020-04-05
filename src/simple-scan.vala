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

public class SimpleScan : Gtk.Application
{
    static bool show_version;
    static bool debug_enabled;
    static string? fix_pdf_filename = null;
    public const OptionEntry[] options =
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
        /* The inhibit () method use this */
        Object (application_id: "org.gnome.SimpleScan");
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
    }

    public override void activate ()
    {
        base.activate ();
        app.start ();
        scanner.start ();
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

    /* Taken from uld/noarch/oem.conf in the Samsung SANE driver */
    private const uint32 samsung_devices[] = { 0x04e83425, 0x04e8341c, 0x04e8342a, 0x04e8343d, 0x04e83456, 0x04e8345a, 0x04e83427, 0x04e8343a, 0x04e83428, 0x04e8343b, 0x04e83455, 0x04e83421, 0x04e83439, 0x04e83444, 0x04e8343f, 0x04e8344e, 0x04e83431, 0x04e8345c, 0x04e8344d, 0x04e83462, 0x04e83464, 0x04e83461, 0x04e83460, 0x04e8340e, 0x04e83435, 0x04e8340f, 0x04e83441, 0x04e8344f, 0x04e83413, 0x04e8341b, 0x04e8342e, 0x04e83426, 0x04e8342b, 0x04e83433, 0x04e83440, 0x04e83434, 0x04e8345b, 0x04e83457, 0x04e8341f, 0x04e83453, 0x04e8344b, 0x04e83409, 0x04e83412, 0x04e83419, 0x04e8342c, 0x04e8343c, 0x04e83432, 0x04e8342d, 0x04e83430, 0x04e8342f, 0x04e83446, 0x04e8341a, 0x04e83437, 0x04e83442, 0x04e83466, 0x04e8340d, 0x04e8341d, 0x04e83420, 0x04e83429, 0x04e83443, 0x04e83438, 0x04e8344c, 0x04e8345d, 0x04e83463, 0x04e83465, 0x04e83450, 0x04e83468, 0x04e83469, 0x04e83471 };

    /* Taken from /usr/share/hplip/data/models/models.dat in the HPAIO driver */
    private const uint32 hpaio_devices[] = { 0x03f02311, 0x03f09711, 0x03f01311, 0x03f01011, 0x03f00f11, 0x03f01911, 0x03f00011, 0x03f00111, 0x03f00611, 0x03f00511, 0x03f00811, 0x03f00711, 0x03f00211, 0x03f00311, 0x03f00411, 0x03f0062a, 0x03f04912, 0x03f09911, 0x03f03802, 0x03f07a11, 0x03f08311, 0x03f07b11, 0x03f0a711, 0x03f08d11, 0x03f08a11, 0x03f0bb11, 0x03f0222a, 0x03f0322a, 0x03f03902, 0x03f01002, 0x03f0242a, 0x03f0332a, 0x03f0122a, 0x03f00c2a, 0x03f0132a, 0x03f02c2a, 0x03f07e11, 0x03f07811, 0x03f08e11, 0x03f02d2a, 0x03f03502, 0x03f01102, 0x03f06112, 0x03f06212, 0x03f05511, 0x03f00f2a, 0x03f0082a, 0x03f07311, 0x03f07c11, 0x03f07d11, 0x03f01d02, 0x03f01202, 0x03f01e02, 0x03f01602, 0x03f01302, 0x03f01702, 0x03f0152a, 0x03f0142a, 0x03f09611, 0x03f01502, 0x03f01902, 0x03f01f02, 0x03f00512, 0x03f0aa11, 0x03f0a311, 0x03f01312, 0x03f01802, 0x03f02812, 0x03f0bf11, 0x03f0c011, 0x03f0342a, 0x03f09e17, 0x03f09f17, 0x03f0252a, 0x03f0a417, 0x03f01a02, 0x03f09e11, 0x03f09011, 0x03f02602, 0x03f0272a, 0x03f02b02, 0x03f01812, 0x03f0b211, 0x03f0352a, 0x03f02b2a, 0x03f0362a, 0x03f0a517, 0x03f01b02, 0x03f02702, 0x03f02c02, 0x03f0282a, 0x03f02104, 0x03f0432a, 0x03f02004, 0x03f01a2a, 0x03f02304, 0x03f01b2a, 0x03f0442a, 0x03f08904, 0x03f0a617, 0x03f09a17, 0x03f0312a, 0x03f0452a, 0x03f01c02, 0x03f01811, 0x03f09d17, 0x03f02804, 0x03f02904, 0x03f01511, 0x03f01411, 0x03f0372a, 0x03f00d14, 0x03f01611, 0x03f01711, 0x03f00f14, 0x03f01f2a, 0x03f00304, 0x03f00204, 0x03f00804, 0x03f02902, 0x03f00704, 0x03f01e2a, 0x03f00404, 0x03f00604, 0x03f00904, 0x03f01512, 0x03f01c2a, 0x03f00104, 0x03f01d2a, 0x03f00004, 0x03f02604, 0x03f02704, 0x03f01804, 0x03f01504, 0x03f01f11, 0x03f01204, 0x03f01604, 0x03f01704, 0x03f01104, 0x03f01e11, 0x03f01304, 0x03f01404, 0x03f03104, 0x03f01004, 0x03f03004, 0x03f03304, 0x03f05004, 0x03f01712, 0x03f02e11, 0x03f00517, 0x03f08811, 0x03f01317, 0x03f04117, 0x03f03217, 0x03f03e17, 0x03f00c17, 0x03f0b511, 0x03f04217, 0x03f04317, 0x03f02b17, 0x03f03017, 0x03f02d17, 0x03f02c17, 0x03f00b2a, 0x03f0112a, 0x03f08911, 0x03f07c04, 0x03f00912, 0x03f03011, 0x03f0032a, 0x03f0002a, 0x03f0102a, 0x03f03402, 0x03f05617, 0x03f05717, 0x03f0042a, 0x03f00f17, 0x03f04004, 0x03f01017, 0x03f01e17, 0x03f00317, 0x03f00f12, 0x03f02f11, 0x03f0052a, 0x03f04717, 0x03f03202, 0x03f00e2a, 0x03f0262a, 0x03f03302, 0x03f00417, 0x03f00212, 0x03f01412, 0x03f07804, 0x03f03b11, 0x03f01117, 0x03f03f11, 0x03f04f17, 0x03f04e17, 0x03f03602, 0x03f05817, 0x03f01d17, 0x03f03c11, 0x03f07904, 0x03f04d11, 0x03f0072a, 0x03f01417, 0x03f04c11, 0x03f0c111, 0x03f04417, 0x03f05017, 0x03f0022a, 0x03f0012a, 0x03f0092a, 0x03f07f11, 0x03f04811, 0x03f03a17, 0x03f00a2a, 0x03f00312, 0x03f09411, 0x03f09b11, 0x03f03917, 0x03f04a17, 0x03f03817, 0x03f0b911, 0x03f05417, 0x03f05217, 0x03f05317, 0x03f05d17, 0x03f08711, 0x03f05c17, 0x03f09a11, 0x03f02811, 0x03f07d04, 0x03f02a11, 0x03f02b11, 0x03f00217, 0x03f02911, 0x03f02404, 0x03f03511, 0x03f00812, 0x03f00b17, 0x03f0c302, 0x03f05917, 0x03f05a17, 0x03f05b17, 0x03f04911, 0x03f03611, 0x03f07611, 0x03f07a04, 0x03f02517, 0x03f02917, 0x03f02a17, 0x03f01e04, 0x03f00717, 0x03f02504, 0x03f03711, 0x03f0ac11, 0x03f0be11, 0x03f0c211, 0x03f01c17, 0x03f04e11, 0x03f02e17, 0x03f04511, 0x03f08011, 0x03f00412, 0x03f03617, 0x03f02f17, 0x03f03117, 0x03f0c911, 0x03f0ca11, 0x03f04611, 0x03f03c17, 0x03f03717, 0x03f02617, 0x03f01112, 0x03f00612, 0x03f06717, 0x03f09511, 0x03f07617, 0x03f07317, 0x03f08d17, 0x03f01617, 0x03f07a17, 0x03f07517, 0x03f09311, 0x03f0a011, 0x03f03317, 0x03f03417, 0x03f0a211, 0x03f05611, 0x03f05011, 0x03f00117, 0x03f05111, 0x03f00817, 0x03f05211, 0x03f07004, 0x03f00917, 0x03f01917, 0x03f03517, 0x03f07104, 0x03f01517, 0x03f03112, 0x03f07817, 0x03f0ad11, 0x03f0b011, 0x03f08517, 0x03f08a17, 0x03f0c711, 0x03f06117, 0x03f06917, 0x03f06812, 0x03f06d12, 0x03f07204, 0x03f00a17, 0x03f07404, 0x03f06817, 0x03f01b04, 0x03f01a04, 0x03f01c04, 0x03f01904, 0x03f07504, 0x03f07604, 0x03f00714, 0x03f09c11, 0x03f07b17, 0x03f08817, 0x03f05711, 0x03f07704, 0x03f07e04, 0x03f03111, 0x03f06017, 0x03f03d11, 0x03f05c11, 0x03f07b04, 0x03f06a17, 0x03f02417, 0x03f05411, 0x03f01f04, 0x03f06711, 0x03f07417, 0x03f09717, 0x03f02317, 0x03f06611, 0x03f06c11, 0x03f09d11, 0x03f07711, 0x03f04712, 0x03f08c11, 0x03f05712, 0x03f02a12, 0x03f06b11, 0x03f0c511, 0x03f02e12, 0x03f0c411, 0x03f09917, 0x03f09c17, 0x03f07411, 0x03f06c17, 0x03f05812, 0x03f06512, 0x03f06612, 0x03f06412, 0x03f0c611, 0x03f0c811, 0x03f01a17, 0x03f02b12, 0x03f02c12, 0x03f07511, 0x03f06217, 0x03f07d17, 0x03f06317, 0x03f07917, 0x03f07217, 0x03f0a117, 0x03f0c802, 0x03f05811, 0x03f0c402, 0x03f02411, 0x03f05d11, 0x03f06417, 0x03f06617, 0x03f08917, 0x03f05117, 0x03f07111, 0x03f01f12, 0x03f06811, 0x03f02012, 0x03f08604, 0x03f06d11, 0x03f03a11, 0x03f03012, 0x03f08211, 0x03f07211, 0x03f0a111, 0x03f0b411, 0x03f09b17, 0x03f0b111, 0x03f0b611, 0x03f0c311, 0x03f01f17, 0x03f06004, 0x03f04f11, 0x03f0cc11, 0x03f06104, 0x03f05b11, 0x03f08104, 0x03f0cd11, 0x03f0a004, 0x03f08704, 0x03f04312, 0x03f04212, 0x03f06f17, 0x03f07c17, 0x03f09517, 0x03f05911, 0x03f05e12, 0x03f00b14, 0x03f0c502, 0x03f02d11, 0x03f03404, 0x03f04b11, 0x03f01014, 0x03f06a11, 0x03f07312, 0x03f07011, 0x03f05311, 0x03f03312, 0x03f04412, 0x03f05412, 0x03f05512, 0x03f04512, 0x03f08204, 0x03f0a511, 0x03f0af11, 0x03f0ba11, 0x03f08504, 0x03f05d12, 0x03f05c12, 0x03f08404, 0x03f07412, 0x03f07212, 0x03f08804, 0x03f04612, 0x03f02611, 0x03f05a11, 0x03f02612, 0x03f0c602, 0x03f06012, 0x03f03a02, 0x03f06911, 0x03f0b002, 0x03f04111, 0x03f06511, 0x03f04211, 0x03f02512, 0x03f0c702, 0x03f02002, 0x03f03c02, 0x03f04311, 0x03f0b802, 0x03f05e11, 0x03f03412, 0x03f02112, 0x03f04812, 0x03f06f11, 0x03f0a611, 0x03f0bc11, 0x03f03e02, 0x03f02212, 0x03f0b202, 0x03f06e12, 0x03f0dc11, 0x03f02312, 0x03f0b402, 0x03f0c002, 0x03f0b602, 0x03f05612, 0x03f03612, 0x03f0c102, 0x03f0de11, 0x03f07717, 0x03f07117, 0x03f05b12, 0x03f06411, 0x03f0ba02, 0x03f0c202, 0x03f0be02, 0x03f0bb02, 0x03f03812, 0x03f04012, 0x03f03912, 0x03f0d102, 0x03f05312, 0x03f02712, 0x03f05912, 0x03f07112, 0x03f07012, 0x03f06f12, 0x03f07712, 0x03f07612, 0x03f0bc02, 0x03f0d002, 0x03f08417, 0x03f02017, 0x03f02117, 0x03f08317, 0x03f09617, 0x03f00d12, 0x03f0bd02, 0x03f02217, 0x03f00b12, 0x03f01212, 0x03f03c2a, 0x03f0382a, 0x03f0582a, 0x03f0552a, 0x03f03e2a, 0x03f03f2a, 0x03f0e311, 0x03f0e111 };

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
     * import sys
     * ids = []
     * for f in sys.argv:
     *   for l in file (f).readlines ():
     *   if not l.startswith ('usb-pid='):
     *     continue
     *   pid = int (l[8:].strip (), 16)
     *   if pid == 0:
     *     continue
     *   usb_id = '0x%08x' % (0x04f9 << 16 | pid)
     *   if not usb_id in ids:
     *     ids.append (usb_id)
     * print ('{ ' + ', '.join (ids) + ' }')
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
        add_devices (driver_map, samsung_devices, "samsung");
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
        string username, password;
        app.authorize (resource, out username, out password);
        scanner.authorize (username, password);
    }

    private Page append_page ()
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
        var width = 100, height = 100, dpi = 100, cx = 0, cy = 0, cw = 0, ch = 0;
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

            if (!is_inhibited (Gtk.ApplicationInhibitFlags.IDLE))
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
            append_page ();

        scanner.scan (device, options);
    }

    private void cancel_cb (AppWindow ui)
    {
        scanner.cancel ();
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
        c.add_group (Gtk.get_option_group (true));
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
                stderr.printf ("Error fixing PDF file: %s", e.message);
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
        Log.set_default_handler (log_cb);

        debug ("Starting %s %s, PID=%i", args[0], VERSION, Posix.getpid ());

        Gtk.init (ref args);

        var app = new SimpleScan (device);
        return app.run ();
    }
}
