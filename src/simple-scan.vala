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
    public static const OptionEntry[] options =
    {
        { "version", 'v', 0, OptionArg.NONE, ref show_version,
          /* Help string for command line --version flag */
          N_("Show release version"), null},
        { "debug", 'd', 0, OptionArg.NONE, ref debug_enabled,
          /* Help string for command line --debug flag */
          N_("Print debugging messages"), null},
        { "fix-pdf", 0, 0, OptionArg.STRING, ref fix_pdf_filename,
          N_("Fix PDF files generated with older versions of Simple Scan"), "FILENAME..."},
        { null }
    };
    private static Timer log_timer;
    private static FileStream? log_file;

    private ScanDevice? default_device = null;
    private bool have_devices = false;
    private GUsb.Context usb_context;
    private UserInterface ui;
    private Scanner scanner;
    private Book book;

    public SimpleScan (ScanDevice? device = null)
    {
        default_device = device;
    }

    public override void startup ()
    {
        base.startup ();

        ui = new UserInterface ();
        book = ui.book;
        ui.start_scan.connect (scan_cb);
        ui.stop_scan.connect (cancel_cb);
        ui.email.connect (email_cb);

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
            ui.set_scan_devices (device_list);
            ui.selected_device = default_device.name;
        }
    }

    public override void activate ()
    {
        base.activate ();
        ui.start ();
        scanner.start ();
    }

    public override void shutdown ()
    {
        base.shutdown ();
        book = null;
        ui = null;
        usb_context = null;
        scanner.free ();
    }

    private void update_scan_devices_cb (Scanner scanner, List<ScanDevice> devices)
    {
        var devices_copy = devices.copy ();

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

        ui.set_scan_devices (devices_copy, missing_driver);
    }
    
    /* Taken from /usr/local/Brother/sane/Brsane.ini from brscan driver */
    private const uint32 brscan_devices[] = { 0x04f90110, 0x04f90111, 0x04f90112, 0x04f9011d, 0x04f9011e, 0x04f9011f, 0x04f9012b, 0x04f90124, 0x04f90153, 0x04f90125, 0x04f90113, 0x04f90114, 0x04f90115, 0x04f90116, 0x04f90119, 0x04f9011a, 0x04f9011b, 0x04f9011c, 0x04f9012e, 0x04f9012f, 0x04f90130, 0x04f90128, 0x04f90127, 0x04f90142, 0x04f90143, 0x04f90140, 0x04f90141, 0x04f9014e, 0x04f9014f, 0x04f90150, 0x04f90151, 0x04f9010e, 0x04f9013a, 0x04f90120, 0x04f9010f, 0x04f90121, 0x04f90122, 0x04f90132, 0x04f9013d, 0x04f9013c, 0x04f90136, 0x04f90135, 0x04f9013e, 0x04f9013f, 0x04f90144, 0x04f90146, 0x04f90148, 0x04f9014a, 0x04f9014b, 0x04f9014c, 0x04f90157, 0x04f90158, 0x04f9015d, 0x04f9015e, 0x04f9015f, 0x04f90160 };

    /* Taken from /usr/local/Brother/sane/models2/*.ini from brscan2 driver */
    private const uint32 brscan2_devices[] = { 0x04f901c9, 0x04f901ca, 0x04f901cb, 0x04f901cc, 0x04f901ec, 0x04f901e4, 0x04f901e3, 0x04f901e2, 0x04f901e1, 0x04f901e0, 0x04f901df, 0x04f901de, 0x04f901dd, 0x04f901dc, 0x04f901db, 0x04f901da, 0x04f901d9, 0x04f901d8, 0x04f901d7, 0x04f901d6, 0x04f901d5, 0x04f901d4, 0x04f901d3, 0x04f901d2, 0x04f901d1, 0x04f901d0, 0x04f901cf, 0x04f901ce, 0x04f9020d, 0x04f9020c, 0x04f9020a };

    /* Taken from /usr/local/Brother/sane/models3/*.ini from brscan3 driver */
    private const uint32 brscan3_devices[] = { 0x04f90222, 0x04f90223, 0x04f90224, 0x04f90225, 0x04f90229, 0x04f9022a, 0x04f9022c, 0x04f90228, 0x04f90236, 0x04f90227, 0x04f9022b, 0x04f9022d, 0x04f9022e, 0x04f9022f, 0x04f90230, 0x04f9021b, 0x04f9021a, 0x04f90219, 0x04f9023f, 0x04f90216, 0x04f9021d, 0x04f9021c, 0x04f90220, 0x04f9021e, 0x04f9023e, 0x04f90235, 0x04f9023a, 0x04f901c9, 0x04f901ca, 0x04f901cb, 0x04f901cc, 0x04f901ec, 0x04f9020d, 0x04f9020c, 0x04f90257, 0x04f9025d, 0x04f90254, 0x04f9025b, 0x04f9026b, 0x04f90258, 0x04f9025e, 0x04f90256, 0x04f90240, 0x04f9025f, 0x04f90260, 0x04f90261, 0x04f90278, 0x04f9026f, 0x04f9026e, 0x04f9026d, 0x04f90234, 0x04f90239, 0x04f90253, 0x04f90255, 0x04f90259, 0x04f9025a, 0x04f9025c, 0x04f90276 };

    /* Taken from /opt/brother/scanner/brscan4/models4/*.ini from brscan4 driver */
    private const uint32 brscan4_devices[] = { 0x04f90314, 0x04f90313, 0x04f90312, 0x04f90311, 0x04f90310, 0x04f9030f, 0x04f90366, 0x04f90365, 0x04f90364, 0x04f90350, 0x04f9034f, 0x04f9034e, 0x04f9034b, 0x04f90349, 0x04f90347, 0x04f90346, 0x04f90343, 0x04f90342, 0x04f90341, 0x04f90340, 0x04f9033d, 0x04f9033c, 0x04f9033a, 0x04f90339, 0x04f90392, 0x04f90373, 0x04f9036e, 0x04f9036d, 0x04f9036c, 0x04f9036b, 0x04f9036a, 0x04f90369, 0x04f90368, 0x04f90367, 0x04f90338, 0x04f90337, 0x04f90335, 0x04f90331, 0x04f90330, 0x04f90329, 0x04f90328, 0x04f90326, 0x04f90324, 0x04f90322, 0x04f90321, 0x04f90320, 0x04f90372, 0x04f90371, 0x04f90370, 0x04f9036f, 0x04f90361, 0x04f90360, 0x04f9035e, 0x04f9035d, 0x04f9035c, 0x04f9035b, 0x04f90379, 0x04f90378, 0x04f90376, 0x04f9037a, 0x04f9037b, 0x04f90377, 0x04f9037f, 0x04f9037e, 0x04f9037d, 0x04f9037c, 0x04f9035a, 0x04f90359, 0x04f90358, 0x04f90357, 0x04f90356, 0x04f90355, 0x04f90354, 0x04f90353, 0x04f90351, 0x04f90390, 0x04f903b3, 0x04f90396, 0x04f90395, 0x04f90394, 0x04f90393, 0x04f90380, 0x04f90381, 0x04f903bd, 0x04f90383, 0x04f90397, 0x04f90386, 0x04f90384, 0x04f90385, 0x04f90388, 0x04f90389, 0x04f9038b, 0x04f9038a, 0x04f9038c, 0x04f9038e, 0x04f9038f, 0x04f9038d, 0x04f903bc, 0x04f903bb, 0x04f903b6, 0x04f903b5, 0x04f903b4, 0x04f90290, 0x04f9028f, 0x04f9028d, 0x04f9028a, 0x04f90284, 0x04f90283, 0x04f90282, 0x04f90281, 0x04f9027e, 0x04f9027d, 0x04f9027c, 0x04f9027b, 0x04f90280, 0x04f9027a, 0x04f90279, 0x04f9027f, 0x04f90285, 0x04f9029a, 0x04f9029f, 0x04f9029e, 0x04f90289, 0x04f90288, 0x04f960a0, 0x04f960a1, 0x04f90293, 0x04f902b7, 0x04f90294, 0x04f90296, 0x04f90298, 0x04f902ba, 0x04f90299, 0x04f902bb, 0x04f902d4, 0x04f90291, 0x04f902ac, 0x04f902b5, 0x04f90292, 0x04f902b6, 0x04f90295, 0x04f902b8, 0x04f9029c, 0x04f902cb, 0x04f902ca, 0x04f902a6, 0x04f902a7, 0x04f902ab, 0x04f902a5, 0x04f902a8, 0x04f902a0, 0x04f902c1, 0x04f902c0, 0x04f902bf, 0x04f902be, 0x04f902bd, 0x04f902bc, 0x04f902b2, 0x04f90287, 0x04f902cf, 0x04f902ce, 0x04f902cd, 0x04f902c7, 0x04f902c6, 0x04f902c5, 0x04f902c4, 0x04f902b4, 0x04f902b3, 0x04f902c2, 0x04f960a4, 0x04f960a5, 0x04f902cc, 0x04f902c8, 0x04f902c3, 0x04f902d3, 0x04f902b1, 0x04f902b0, 0x04f902af, 0x04f902ae, 0x04f902ad, 0x04f902d1, 0x04f902d0, 0x04f902fb, 0x04f902f1, 0x04f902f0, 0x04f902ef, 0x04f902ed, 0x04f902ec, 0x04f902ee, 0x04f902eb, 0x04f902e9, 0x04f902e8, 0x04f902fa, 0x04f902ea, 0x04f902e6, 0x04f902e5, 0x04f902e4, 0x04f902e3, 0x04f902e2, 0x04f902f9, 0x04f902de, 0x04f902e0, 0x04f902df, 0x04f902e1, 0x04f902e7, 0x04f902fc, 0x04f902fd, 0x04f902fe, 0x04f902dd, 0x04f902c9, 0x04f902ff, 0x04f90300, 0x04f902f2, 0x04f902f3, 0x04f902f4, 0x04f902f8, 0x04f902f5, 0x04f902f6, 0x04f902f7, 0x04f90318, 0x04f960a6, 0x04f960a7, 0x04f960a8, 0x04f960a9 }; 

    /* Taken from uld/noarch/oem.conf in the Samsung SANE driver */
    private const uint32 samsung_devices[] = { 0x04e83425, 0x04e8341c, 0x04e8342a, 0x04e8343d, 0x04e83456, 0x04e8345a, 0x04e83427, 0x04e8343a, 0x04e83428, 0x04e8343b, 0x04e83455, 0x04e83421, 0x04e83439, 0x04e83444, 0x04e8343f, 0x04e8344e, 0x04e83431, 0x04e8345c, 0x04e8344d, 0x04e83462, 0x04e83464, 0x04e83461, 0x04e83460, 0x04e8340e, 0x04e83435, 0x04e8340f, 0x04e83441, 0x04e8344f, 0x04e83413, 0x04e8341b, 0x04e8342e, 0x04e83426, 0x04e8342b, 0x04e83433, 0x04e83440, 0x04e83434, 0x04e8345b, 0x04e83457, 0x04e8341f, 0x04e83453, 0x04e8344b, 0x04e83409, 0x04e83412, 0x04e83419, 0x04e8342c, 0x04e8343c, 0x04e83432, 0x04e8342d, 0x04e83430, 0x04e8342f, 0x04e83446, 0x04e8341a, 0x04e83437, 0x04e83442, 0x04e83466, 0x04e8340d, 0x04e8341d, 0x04e83420, 0x04e83429, 0x04e83443, 0x04e83438, 0x04e8344c, 0x04e8345d, 0x04e83463, 0x04e83465, 0x04e83450, 0x04e83468, 0x04e83469, 0x04e83471 };

    /* Taken from /usr/share/hplip/data/models/models.dat in the HPAIO driver */
    private const uint32 hpaio_devices[] = { 0x03f02311, 0x03f09711, 0x03f01311, 0x03f01011, 0x03f00f11, 0x03f01911, 0x03f00011, 0x03f00111, 0x03f00611, 0x03f00511, 0x03f00811, 0x03f00711, 0x03f00211, 0x03f00311, 0x03f00411, 0x03f0062a, 0x03f04912, 0x03f09911, 0x03f03802, 0x03f07a11, 0x03f08311, 0x03f07b11, 0x03f0a711, 0x03f08d11, 0x03f08a11, 0x03f0bb11, 0x03f0222a, 0x03f0322a, 0x03f03902, 0x03f01002, 0x03f0242a, 0x03f0332a, 0x03f0122a, 0x03f00c2a, 0x03f0132a, 0x03f02c2a, 0x03f07e11, 0x03f07811, 0x03f08e11, 0x03f02d2a, 0x03f03502, 0x03f01102, 0x03f06112, 0x03f06212, 0x03f05511, 0x03f00f2a, 0x03f0082a, 0x03f07311, 0x03f07c11, 0x03f07d11, 0x03f01d02, 0x03f01202, 0x03f01e02, 0x03f01602, 0x03f01302, 0x03f01702, 0x03f0152a, 0x03f0142a, 0x03f09611, 0x03f01502, 0x03f01902, 0x03f01f02, 0x03f00512, 0x03f0aa11, 0x03f0a311, 0x03f01312, 0x03f01802, 0x03f02812, 0x03f0bf11, 0x03f0c011, 0x03f0342a, 0x03f09e17, 0x03f09f17, 0x03f0252a, 0x03f0a417, 0x03f01a02, 0x03f09e11, 0x03f09011, 0x03f02602, 0x03f0272a, 0x03f02b02, 0x03f01812, 0x03f0b211, 0x03f0352a, 0x03f02b2a, 0x03f0362a, 0x03f0a517, 0x03f01b02, 0x03f02702, 0x03f02c02, 0x03f0282a, 0x03f02104, 0x03f0432a, 0x03f02004, 0x03f01a2a, 0x03f02304, 0x03f01b2a, 0x03f0442a, 0x03f08904, 0x03f0a617, 0x03f09a17, 0x03f0312a, 0x03f0452a, 0x03f01c02, 0x03f01811, 0x03f09d17, 0x03f02804, 0x03f02904, 0x03f01511, 0x03f01411, 0x03f0372a, 0x03f00d14, 0x03f01611, 0x03f01711, 0x03f00f14, 0x03f01f2a, 0x03f00304, 0x03f00204, 0x03f00804, 0x03f02902, 0x03f00704, 0x03f01e2a, 0x03f00404, 0x03f00604, 0x03f00904, 0x03f01512, 0x03f01c2a, 0x03f00104, 0x03f01d2a, 0x03f00004, 0x03f02604, 0x03f02704, 0x03f01804, 0x03f01504, 0x03f01f11, 0x03f01204, 0x03f01604, 0x03f01704, 0x03f01104, 0x03f01e11, 0x03f01304, 0x03f01404, 0x03f03104, 0x03f01004, 0x03f03004, 0x03f03304, 0x03f05004, 0x03f01712, 0x03f02e11, 0x03f00517, 0x03f08811, 0x03f01317, 0x03f04117, 0x03f03217, 0x03f03e17, 0x03f00c17, 0x03f0b511, 0x03f04217, 0x03f04317, 0x03f02b17, 0x03f03017, 0x03f02d17, 0x03f02c17, 0x03f00b2a, 0x03f0112a, 0x03f08911, 0x03f07c04, 0x03f00912, 0x03f03011, 0x03f0032a, 0x03f0002a, 0x03f0102a, 0x03f03402, 0x03f05617, 0x03f05717, 0x03f0042a, 0x03f00f17, 0x03f04004, 0x03f01017, 0x03f01e17, 0x03f00317, 0x03f00f12, 0x03f02f11, 0x03f0052a, 0x03f04717, 0x03f03202, 0x03f00e2a, 0x03f0262a, 0x03f03302, 0x03f00417, 0x03f00212, 0x03f01412, 0x03f07804, 0x03f03b11, 0x03f01117, 0x03f03f11, 0x03f04f17, 0x03f04e17, 0x03f03602, 0x03f05817, 0x03f01d17, 0x03f03c11, 0x03f07904, 0x03f04d11, 0x03f0072a, 0x03f01417, 0x03f04c11, 0x03f0c111, 0x03f04417, 0x03f05017, 0x03f0022a, 0x03f0012a, 0x03f0092a, 0x03f07f11, 0x03f04811, 0x03f03a17, 0x03f00a2a, 0x03f00312, 0x03f09411, 0x03f09b11, 0x03f03917, 0x03f04a17, 0x03f03817, 0x03f0b911, 0x03f05417, 0x03f05217, 0x03f05317, 0x03f05d17, 0x03f08711, 0x03f05c17, 0x03f09a11, 0x03f02811, 0x03f07d04, 0x03f02a11, 0x03f02b11, 0x03f00217, 0x03f02911, 0x03f02404, 0x03f03511, 0x03f00812, 0x03f00b17, 0x03f0c302, 0x03f05917, 0x03f05a17, 0x03f05b17, 0x03f04911, 0x03f03611, 0x03f07611, 0x03f07a04, 0x03f02517, 0x03f02917, 0x03f02a17, 0x03f01e04, 0x03f00717, 0x03f02504, 0x03f03711, 0x03f0ac11, 0x03f0be11, 0x03f0c211, 0x03f01c17, 0x03f04e11, 0x03f02e17, 0x03f04511, 0x03f08011, 0x03f00412, 0x03f03617, 0x03f02f17, 0x03f03117, 0x03f0c911, 0x03f0ca11, 0x03f04611, 0x03f03c17, 0x03f03717, 0x03f02617, 0x03f01112, 0x03f00612, 0x03f06717, 0x03f09511, 0x03f07617, 0x03f07317, 0x03f08d17, 0x03f01617, 0x03f07a17, 0x03f07517, 0x03f09311, 0x03f0a011, 0x03f03317, 0x03f03417, 0x03f0a211, 0x03f05611, 0x03f05011, 0x03f00117, 0x03f05111, 0x03f00817, 0x03f05211, 0x03f07004, 0x03f00917, 0x03f01917, 0x03f03517, 0x03f07104, 0x03f01517, 0x03f03112, 0x03f07817, 0x03f0ad11, 0x03f0b011, 0x03f08517, 0x03f08a17, 0x03f0c711, 0x03f06117, 0x03f06917, 0x03f06812, 0x03f06d12, 0x03f07204, 0x03f00a17, 0x03f07404, 0x03f06817, 0x03f01b04, 0x03f01a04, 0x03f01c04, 0x03f01904, 0x03f07504, 0x03f07604, 0x03f00714, 0x03f09c11, 0x03f07b17, 0x03f08817, 0x03f05711, 0x03f07704, 0x03f07e04, 0x03f03111, 0x03f06017, 0x03f03d11, 0x03f05c11, 0x03f07b04, 0x03f06a17, 0x03f02417, 0x03f05411, 0x03f01f04, 0x03f06711, 0x03f07417, 0x03f09717, 0x03f02317, 0x03f06611, 0x03f06c11, 0x03f09d11, 0x03f07711, 0x03f04712, 0x03f08c11, 0x03f05712, 0x03f02a12, 0x03f06b11, 0x03f0c511, 0x03f02e12, 0x03f0c411, 0x03f09917, 0x03f09c17, 0x03f07411, 0x03f06c17, 0x03f05812, 0x03f06512, 0x03f06612, 0x03f06412, 0x03f0c611, 0x03f0c811, 0x03f01a17, 0x03f02b12, 0x03f02c12, 0x03f07511, 0x03f06217, 0x03f07d17, 0x03f06317, 0x03f07917, 0x03f07217, 0x03f0a117, 0x03f0c802, 0x03f05811, 0x03f0c402, 0x03f02411, 0x03f05d11, 0x03f06417, 0x03f06617, 0x03f08917, 0x03f05117, 0x03f07111, 0x03f01f12, 0x03f06811, 0x03f02012, 0x03f08604, 0x03f06d11, 0x03f03a11, 0x03f03012, 0x03f08211, 0x03f07211, 0x03f0a111, 0x03f0b411, 0x03f09b17, 0x03f0b111, 0x03f0b611, 0x03f0c311, 0x03f01f17, 0x03f06004, 0x03f04f11, 0x03f0cc11, 0x03f06104, 0x03f05b11, 0x03f08104, 0x03f0cd11, 0x03f0a004, 0x03f08704, 0x03f04312, 0x03f04212, 0x03f06f17, 0x03f07c17, 0x03f09517, 0x03f05911, 0x03f05e12, 0x03f00b14, 0x03f0c502, 0x03f02d11, 0x03f03404, 0x03f04b11, 0x03f01014, 0x03f06a11, 0x03f07312, 0x03f07011, 0x03f05311, 0x03f03312, 0x03f04412, 0x03f05412, 0x03f05512, 0x03f04512, 0x03f08204, 0x03f0a511, 0x03f0af11, 0x03f0ba11, 0x03f08504, 0x03f05d12, 0x03f05c12, 0x03f08404, 0x03f07412, 0x03f07212, 0x03f08804, 0x03f04612, 0x03f02611, 0x03f05a11, 0x03f02612, 0x03f0c602, 0x03f06012, 0x03f03a02, 0x03f06911, 0x03f0b002, 0x03f04111, 0x03f06511, 0x03f04211, 0x03f02512, 0x03f0c702, 0x03f02002, 0x03f03c02, 0x03f04311, 0x03f0b802, 0x03f05e11, 0x03f03412, 0x03f02112, 0x03f04812, 0x03f06f11, 0x03f0a611, 0x03f0bc11, 0x03f03e02, 0x03f02212, 0x03f0b202, 0x03f06e12, 0x03f0dc11, 0x03f02312, 0x03f0b402, 0x03f0c002, 0x03f0b602, 0x03f05612, 0x03f03612, 0x03f0c102, 0x03f0de11, 0x03f07717, 0x03f07117, 0x03f05b12, 0x03f06411, 0x03f0ba02, 0x03f0c202, 0x03f0be02, 0x03f0bb02, 0x03f03812, 0x03f04012, 0x03f03912, 0x03f0d102, 0x03f05312, 0x03f02712, 0x03f05912, 0x03f07112, 0x03f07012, 0x03f06f12, 0x03f07712, 0x03f07612, 0x03f0bc02, 0x03f0d002, 0x03f08417, 0x03f02017, 0x03f02117, 0x03f08317, 0x03f09617, 0x03f00d12, 0x03f0bd02, 0x03f02217, 0x03f00b12, 0x03f01212, 0x03f03c2a, 0x03f0382a, 0x03f0582a, 0x03f0552a, 0x03f03e2a, 0x03f03f2a, 0x03f0e311, 0x03f0e111 };

    /* Taken from epkowa.desc from iscan-data package for Epson driver */
    private const uint32 epkowa_devices[] = { 0x04b80101, 0x04b80102, 0x04b80103, 0x04b80104, 0x04b80105, 0x04b80106, 0x04b80107, 0x04b80108, 0x04b80109, 0x04b8010a, 0x04b8010b, 0x04b8010c, 0x04b8010d, 0x04b8010e, 0x04b8010f, 0x04b80110, 0x04b80112, 0x04b80114, 0x04b80116, 0x04b80118, 0x04b80119, 0x04b8011a, 0x04b8011b, 0x04b8011c, 0x04b8011d, 0x04b8011e, 0x04b8011f, 0x04b80120, 0x04b80121, 0x04b80122, 0x04b80126, 0x04b80128, 0x04b80129, 0x04b8012a, 0x04b8012b, 0x04b8012c, 0x04b8012d, 0x04b8012e, 0x04b8012f, 0x04b80130, 0x04b80131, 0x04b80133, 0x04b80135, 0x04b80136, 0x04b80137, 0x04b80138, 0x04b8013a, 0x04b8013b, 0x04b8013c, 0x04b8013d, 0x04b80142, 0x04b80143, 0x04b80144, 0x04b80147, 0x04b8014a, 0x04b8014b, 0x04b80151, 0x04b80153, 0x04b80801, 0x04b80802, 0x04b80805, 0x04b80806, 0x04b80807, 0x04b80808, 0x04b8080a, 0x04b8080c, 0x04b8080d, 0x04b8080e, 0x04b8080f, 0x04b80810, 0x04b80811, 0x04b80813, 0x04b80814, 0x04b80815, 0x04b80817, 0x04b80818, 0x04b80819, 0x04b8081a, 0x04b8081c, 0x04b8081d, 0x04b8081f, 0x04b80820, 0x04b80821, 0x04b80827, 0x04b80828, 0x04b80829, 0x04b8082a, 0x04b8082b, 0x04b8082e, 0x04b8082f, 0x04b80830, 0x04b80831, 0x04b80833, 0x04b80834, 0x04b80835, 0x04b80836, 0x04b80837, 0x04b80838, 0x04b80839, 0x04b8083a, 0x04b8083c, 0x04b8083f, 0x04b80841, 0x04b80843, 0x04b80844, 0x04b80846, 0x04b80847, 0x04b80848, 0x04b80849, 0x04b8084a, 0x04b8084c, 0x04b8084d, 0x04b8084f, 0x04b80850, 0x04b80851, 0x04b80852, 0x04b80853, 0x04b80854, 0x04b80855, 0x04b80856, 0x04b8085c, 0x04b8085d, 0x04b8085e, 0x04b8085f, 0x04b80860, 0x04b80861, 0x04b80862, 0x04b80863, 0x04b80864, 0x04b80865, 0x04b80866, 0x04b80869, 0x04b8086a, 0x04b80870, 0x04b80871, 0x04b80872, 0x04b80873, 0x04b80878, 0x04b80879, 0x04b8087b, 0x04b8087c, 0x04b8087d, 0x04b8087e, 0x04b8087f, 0x04b80880, 0x04b80881, 0x04b80883, 0x04b80884, 0x04b80885, 0x04b8088f, 0x04b80890, 0x04b80891, 0x04b80892, 0x04b80893, 0x04b80894, 0x04b80895, 0x04b80896, 0x04b80897, 0x04b80898, 0x04b80899, 0x04b8089a, 0x04b8089b, 0x04b8089c, 0x04b8089d, 0x04b8089e, 0x04b8089f, 0x04b808a0, 0x04b808a1, 0x04b808a5, 0x04b808a6, 0x04b808a8, 0x04b808a9, 0x04b808aa, 0x04b808ab, 0x04b808ac, 0x04b808ad, 0x04b808ae, 0x04b808af, 0x04b808b0, 0x04b808b3, 0x04b808b4, 0x04b808b5, 0x04b808b6, 0x04b808b7, 0x04b808b8, 0x04b808b9, 0x04b808bd, 0x04b808be, 0x04b808bf, 0x04b808c0, 0x04b808c1, 0x04b808c3, 0x04b808c4, 0x04b808c5, 0x04b808c6, 0x04b808c7, 0x04b808c8, 0x04b808c9, 0x04b808ca, 0x04b808cd, 0x04b808d0 };

    /* Brother IDs extracted using the following Python
     * import sys   
     * ids = []
     * for f in sys.argv:
     *   for l in file (f).readlines ():
     *     tokens = l.strip().split (',')
     *     if len (tokens) >= 4:
     *         ids.append ('0x%08x' % (0x04f9 << 16 | int (tokens[0], 16)))
     * print ('{ ' + ', '.join (ids) + ' }')
     */

    /* HPAIO IDs extraced using the following Python:
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
        var devices = GUsb.context_get_devices (usb_context);
        /* Fixed in GUsb 0.2.7: https://github.com/hughsie/libgusb/commit/83a6b1a20653c1a17f0a909f08652b5e1df44075 */
        /*var devices = GUSB.context_get_devices (context);*/
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
        ui.authorize (resource, out username, out password);
        scanner.authorize (username, password);
    }

    private Page append_page ()
    {
        /* Use current page if not used */
        var page = book.get_page (-1);
        if (page != null && !page.has_data)
        {
            ui.selected_page = page;
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
        ui.selected_page = page;
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

        var client = new Colord.Client ();
        try
        {
            client.connect_sync ();
        }
        catch (Error e)
        {
            debug ("Failed to connect to colord: %s", e.message);
            return null;
        }

        Colord.Device device;
        try
        {
            device = client.find_device_by_property_sync (Colord.DEVICE_PROPERTY_SERIAL, device_id);
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
        var page = append_page ();
        page.set_page_info (info);

        /* Get ICC color profile */
        /* FIXME: The ICC profile could change */
        /* FIXME: Don't do a D-bus call for each page, cache color profiles */
        page.color_profile = get_profile_for_device (info.device);
    }

    private void scanner_line_cb (Scanner scanner, ScanLine line)
    {
        var page = book.get_page ((int) book.n_pages - 1);
        page.parse_scan_line (line);
    }

    private void scanner_page_done_cb (Scanner scanner)
    {
        var page = book.get_page ((int) book.n_pages - 1);
        page.finish ();
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
        if (error_code != Sane.Status.CANCELLED)
        {
            ui.show_error (/* Title of error dialog when scan failed */
                           _("Failed to scan"),
                           error_string,
                           have_devices);
        }
    }

    private void scanner_scanning_changed_cb (Scanner scanner)
    {
        ui.scanning = scanner.is_scanning ();
    }

    private void scan_cb (UserInterface ui, string? device, ScanOptions options)
    {
        debug ("Requesting scan at %d dpi from device '%s'", options.dpi, device);

        if (!scanner.is_scanning ())
            append_page ();

        scanner.scan (device, options);
    }

    private void cancel_cb (UserInterface ui)
    {
        scanner.cancel ();
    }

    private string? get_temporary_filename (string prefix, string extension)
    {
        /* NOTE: I'm not sure if this is a 100% safe strategy to use g_file_open_tmp(), close and
         * use the filename but it appears to work in practise */

        var filename = "%sXXXXXX.%s".printf (prefix, extension);
        string path;
        try
        {
            var fd = FileUtils.open_tmp (filename, out path);
            Posix.close (fd);
        }
        catch (Error e)
        {
            warning ("Error saving email attachment: %s", e.message);
            return null;
        }

        return path;
    }

    private void email_cb (UserInterface ui, string profile, int quality)
    {
        var saved = false;
        var command_line = "xdg-email";

        /* Save text files as PDFs */
        if (profile == "text")
        {
            /* Open a temporary file */
            var path = get_temporary_filename ("scan", "pdf");
            if (path != null)
            {
                var file = File.new_for_path (path);
                ui.show_progress_dialog ();
                try
                {
                    book.save ("pdf", quality, file);
                }
                catch (Error e)
                {
                    ui.hide_progress_dialog ();
                    warning ("Unable to save email file: %s", e.message);
                    return;
                }
                command_line += " --attach %s".printf (path);
            }
        }
        else
        {
            for (var i = 0; i < book.n_pages; i++)
            {
                var path = get_temporary_filename ("scan", "jpg");
                if (path == null)
                {
                    saved = false;
                    break;
                }

                var file = File.new_for_path (path);
                try
                {
                    book.get_page (i).save ("jpeg", quality, file);
                }
                catch (Error e)
                {
                    warning ("Unable to save email file: %s", e.message);
                    return;
                }
                command_line += " --attach %s".printf (path);

                if (!saved)
                    break;
            }
        }

        debug ("Launching email client: %s", command_line);
        try
        {
            Process.spawn_command_line_async (command_line);
        }
        catch (Error e)
        {
            warning ("Unable to start email: %s", e.message);
        }
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
                                   _("[DEVICE...] - Scanning utility"));
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
                           _("Run '%s --help' to see a full list of available command line options."), args[0]);
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

        debug ("Starting Simple Scan %s, PID=%i", VERSION, Posix.getpid ());

        Gtk.init (ref args);

        var app = new SimpleScan (device);
        return app.run ();
    }
}
