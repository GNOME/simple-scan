/*
 * Copyright (C) 2009-2011 Canonical Ltd.
 * Author: Robert Ancell <robert.ancell@canonical.com>
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later
 * version. See http://www.gnu.org/copyleft/gpl.html the full text of the
 * license.
 */

/* Workaround for https://bugzilla.gnome.org/show_bug.cgi?id=651507 */
extern void cairo_surface_show_page (Cairo.Surface surface);

public class Book
{
    private List<Page> pages;

    private bool needs_saving;
    
    private FileOutputStream? ps_stream = null;

    public signal void page_added (Page page);
    public signal void page_removed (Page page);
    public signal void reordered ();
    public signal void cleared ();
    public signal void needs_saving_changed ();

    public Book ()
    {
    }

    public void clear ()
    {
        pages = null;
        cleared ();
    }

    private void page_changed_cb (Page page)
    {
        set_needs_saving (true);
    }

    public Page append_page (int width, int height, int dpi, ScanDirection scan_direction)
    {
        var page = new Page (width, height, dpi, scan_direction);
        page.pixels_changed.connect (page_changed_cb);
        page.crop_changed.connect (page_changed_cb);

        pages.append (page);
        page_added (page);
        set_needs_saving (true);

        return page;
    }

    public void move_page (Page page, uint location)
    {
        pages.remove (page);
        pages.insert (page, (int) location);
        reordered ();
        set_needs_saving (true);
    }

    public void delete_page (Page page)
    {
        page.pixels_changed.disconnect (page_changed_cb);
        page.crop_changed.disconnect (page_changed_cb);
        page_removed (page);
        pages.remove (page);
        set_needs_saving (true);
    }

    public uint get_n_pages ()
    {
        return pages.length ();
    }

    public Page get_page (int page_number)
    {
        if (page_number < 0)
            page_number = (int) pages.length () + page_number;
        return pages.nth_data (page_number);
    }

    public uint get_page_index (Page page)
    {
        return pages.index (page);
    }

    private File make_indexed_file (string uri, int i)
    {
        if (i == 0)
            return File.new_for_uri (uri);

        /* Insert index before extension */
        var basename = Path.get_basename (uri);
        string prefix = uri, suffix = "";
        var extension_index = basename.last_index_of_char ('.');
        if (extension_index >= 0)
        {          
            suffix = basename.slice (extension_index, basename.length);
            prefix = uri.slice (0, uri.length - suffix.length);
        }

        return File.new_for_uri ("%s-%d%s".printf (prefix, i, suffix));
    }

    private void save_multi_file (string type, File file) throws Error
    {
        int i = 0;
        foreach (var page in pages)
        {
            page.save (type, make_indexed_file (file.get_uri (), i));
            i++;
        }
    }

    private void save_ps_pdf_surface (Cairo.Surface surface, Gdk.Pixbuf image, double dpi)
    {
        var context = new Cairo.Context (surface);
        context.scale (72.0 / dpi, 72.0 / dpi);
        Gdk.cairo_set_source_pixbuf (context, image, 0, 0);
        context.get_source ().set_filter (Cairo.Filter.BEST);
        context.paint ();
    }

    private Cairo.Status write_cairo_data (uchar[] data)
    {
        try
        {
            ps_stream.write_all (data, null, null);
        }
        catch (Error e)
        {
            warning ("Error writing data: %s", e.message);
            return Cairo.Status.WRITE_ERROR;
        }

        return Cairo.Status.SUCCESS;
    }

    private void save_ps (File file) throws Error
    {
        ps_stream = file.replace (null, false, FileCreateFlags.NONE, null);
        var surface = new Cairo.PsSurface.for_stream (write_cairo_data, 0, 0);
        ps_stream = null;

        foreach (var page in pages)
        {
            var image = page.get_image (true);
            var width = image.get_width () * 72.0 / page.get_dpi ();
            var height = image.get_height () * 72.0 / page.get_dpi ();
            surface.set_size (width, height);
            save_ps_pdf_surface (surface, image, page.get_dpi ());
            cairo_surface_show_page (surface);
        }
    }

    private uchar[]? compress_zlib (uchar[] data)
    {
        var stream = ZLib.DeflateStream (ZLib.Level.BEST_COMPRESSION);
        var out_data = new uchar[data.length];

        stream.next_in = data;
        stream.avail_in = data.length;
        stream.next_out = out_data;
        stream.avail_out = data.length;
        while (stream.avail_in > 0)
        {
            if (stream.deflate (ZLib.Flush.FINISH) == ZLib.Status.STREAM_ERROR)
                break;
        }

        if (stream.avail_in > 0)
            return null;

        // FIXME: Reallocate
        var n_written = data.length - stream.avail_out;

        return out_data;
    }

#if 0  
    private void jpeg_init_cb (struct jpeg_compress_struct info) {}
    private boolean jpeg_empty_cb (struct jpeg_compress_struct info) { return true; }
    private void jpeg_term_cb (struct jpeg_compress_struct info) {}

    private uchar[] compress_jpeg (Gdk.Pixbuf image, out size_t n_written)
    {
        struct jpeg_compress_struct info;
        struct jpeg_error_mgr jerr;
        struct jpeg_destination_mgr dest_mgr;
        int r;
        uchar *pixels;
        uchar *data;
        size_t max_length;

        info.err = jpeg_std_error (&jerr);
        jpeg_create_compress (&info);

        pixels = image.get_pixels ();
        info.image_width = image.get_width ();
        info.image_height = image.get_height ();
        info.input_components = 3;
        info.in_color_space = JCS_RGB; /* TODO: JCS_GRAYSCALE? */
        jpeg_set_defaults (&info);

        max_length = info.image_width * info.image_height * info.input_components;
        data = g_malloc (sizeof (uchar) * max_length);
        dest_mgr.next_output_byte = data;
        dest_mgr.free_in_buffer = max_length;
        dest_mgr.init_destination = jpeg_init_cb;
        dest_mgr.empty_output_buffer = jpeg_empty_cb;
        dest_mgr.term_destination = jpeg_term_cb;
        info.dest = &dest_mgr;

        jpeg_start_compress (&info, true);
        for (r = 0; r < info.image_height; r++)
        {
            JSAMPROW row[1];
            row[0] = pixels + r * image.get_rowstride ();
            jpeg_write_scanlines (&info, row, 1);
        }
        jpeg_finish_compress (&info);
        *n_written = max_length - dest_mgr.free_in_buffer;

        jpeg_destroy_compress (&info);

        return data;
    }
#endif

    private void save_pdf (File file) throws Error
    {
        var stream = file.replace (null, false, FileCreateFlags.NONE, null);
        var writer = new PDFWriter (stream);

        /* Header */
        writer.write_string ("%%PDF-1.3\n");

        /* Comment with binary as recommended so file is treated as binary */
        writer.write_string ("%%\xe2\xe3\xcf\xd3\n");

        /* Catalog */
        var catalog_number = writer.start_object ();
        writer.write_string ("%u 0 obj\n".printf (catalog_number));
        writer.write_string ("<<\n");
        writer.write_string ("/Type /Catalog\n");
        //FIXMEwriter.write_string ("/Metadata %u 0 R\n".printf (catalog_number + 1));
        writer.write_string ("/Pages %u 0 R\n".printf (catalog_number + 1)); //+2
        writer.write_string (">>\n");
        writer.write_string ("endobj\n");

        /* Metadata */
        /* FIXME writer.write_string ("\n");
        number = writer.start_object ();
        writer.write_string ("%u 0 obj\n".printf (number));
        writer.write_string ("<<\n");
        writer.write_string ("/Type /Metadata\n");
        writer.write_string ("/Subtype /XML\n");
        writer.write_string ("/Length %u\n".printf (...));
        writer.write_string (">>\n");
        writer.write_string ("stream\n");
        // ...
        writer.write_string ("\n");
        writer.write_string ("endstream\n");
        writer.write_string ("endobj\n");*/

        /* Pages */
        writer.write_string ("\n");
        var pages_number = writer.start_object ();
        writer.write_string ("%u 0 obj\n".printf (pages_number));
        writer.write_string ("<<\n");
        writer.write_string ("/Type /Pages\n");
        writer.write_string ("/Kids [");
        for (var i = 0; i < get_n_pages (); i++)
            writer.write_string (" %u 0 R".printf (pages_number + 1 + (i*3)));
        writer.write_string (" ]\n");
        writer.write_string ("/Count %u\n".printf (get_n_pages ()));
        writer.write_string (">>\n");
        writer.write_string ("endobj\n");

        for (var i = 0; i < get_n_pages (); i++)
        {
            var page = get_page (i);
            var image = page.get_image (true);
            var width = image.get_width ();
            var height = image.get_height ();
            var pixels = image.get_pixels ();
            var page_width = width * 72.0 / page.get_dpi ();
            var page_height = height * 72.0 / page.get_dpi ();

            int depth = 8;
            string color_space = "DeviceRGB";
            string? filter = null;
            char[] width_buffer = new char[double.DTOSTR_BUF_SIZE];
            char[] height_buffer = new char[double.DTOSTR_BUF_SIZE];
            uchar[] data;
            if (page.is_color ())
            {
                depth = 8;
                color_space = "DeviceRGB";
                var data_length = height * width * 3 + 1;
                data = new uchar[data_length];
                for (var row = 0; row < height; row++)
                {
                    var in_offset = row * image.get_rowstride ();
                    var out_offset = row * width * 3;
                    for (var x = 0; x < width; x++)
                    {
                        var in_o = in_offset + x*3;
                        var out_o = out_offset + x*3;

                        data[out_o] = pixels[in_o];
                        data[out_o+1] = pixels[in_o+1];
                        data[out_o+2] = pixels[in_o+2];
                    }
                }
            }
            else if (page.get_depth () == 2)
            {
                int shift_count = 6;
                depth = 2;
                color_space = "DeviceGray";
                var data_length = height * ((width * 2 + 7) / 8);
                data = new uchar[data_length];
                var offset = 0;
                data[offset] = 0;
                for (var row = 0; row < height; row++)
                {
                    /* Pad to the next line */
                    if (shift_count != 6)
                    {
                        offset++;
                        data[offset] = 0;
                        shift_count = 6;
                    }

                    var in_offset = row * image.get_rowstride ();
                    for (var x = 0; x < width; x++)
                    {
                        var p = pixels[in_offset + x*3];
                        if (p >= 192)
                            data[offset] |= 3 << shift_count;
                        else if (p >= 128)
                            data[offset] |= 2 << shift_count;
                        else if (p >= 64)
                            data[offset] |= 1 << shift_count;
                        if (shift_count == 0)
                        {
                            offset++;
                            data[offset] = 0;
                            shift_count = 6;
                        }
                        else
                            shift_count -= 2;
                    }
                }
            }
            else if (page.get_depth () == 1)
            {
                int mask = 0x80;

                depth = 1;
                color_space = "DeviceGray";
                var data_length = height * ((width + 7) / 8);
                data = new uchar[data_length];
                var offset = 0;
                data[offset] = 0;
                for (var row = 0; row < height; row++)
                {
                    /* Pad to the next line */
                    if (mask != 0x80)
                    {
                        offset++;
                        data[offset] = 0;
                        mask = 0x80;
                    }

                    var in_offset = row * image.get_rowstride ();
                    for (var x = 0; x < width; x++)
                    {
                        if (pixels[in_offset+x*3] != 0)
                            data[offset] |= (uchar) mask;
                        mask >>= 1;
                        if (mask == 0)
                        {
                            offset++;
                            data[offset] = 0;
                            mask = 0x80;
                        }
                    }
                }
            }
            else
            {
                depth = 8;
                color_space = "DeviceGray";
                var data_length = height * width + 1;
                data = new uchar [data_length];
                for (var row = 0; row < height; row++)
                {
                    var in_offset = row * image.get_rowstride ();
                    var out_offset = row * width;
                    for (var x = 0; x < width; x++)
                        data[out_offset+x] = pixels[in_offset+x*3];
                }
            }

            /* Compress data */
            var compressed_data = compress_zlib (data);
            if (compressed_data != null)
            {
                /* Try if JPEG compression is better */
                if (depth > 1)
                {
#if 0
                    size_t jpeg_length;
                    var jpeg_data = compress_jpeg (image, out jpeg_length);
                    if (jpeg_length < compressed_data.length)
                    {
                        filter = "DCTDecode";
                        data = jpeg_data;
                    }
#endif
                }

                if (filter == null)
                {
                    filter = "FlateDecode";
                    data = compressed_data;
                }
            }

            /* Page */
            writer.write_string ("\n");
            var number = writer.start_object ();
            writer.write_string ("%u 0 obj\n".printf (number));
            writer.write_string ("<<\n");
            writer.write_string ("/Type /Page\n");
            writer.write_string ("/Parent %u 0 R\n".printf (pages_number));
            writer.write_string ("/Resources << /XObject << /Im%d %u 0 R >> >>\n".printf (i, number+1));
            writer.write_string ("/MediaBox [ 0 0 %s %s ]\n".printf (page_width.format (width_buffer, "%.2f"), page_height.format (height_buffer, "%.2f")));
            writer.write_string ("/Contents %u 0 R\n".printf (number+2));
            writer.write_string (">>\n");
            writer.write_string ("endobj\n");

            /* Page image */
            writer.write_string ("\n");
            number = writer.start_object ();
            writer.write_string ("%u 0 obj\n".printf (number));
            writer.write_string ("<<\n");
            writer.write_string ("/Type /XObject\n");
            writer.write_string ("/Subtype /Image\n");
            writer.write_string ("/Width %d\n".printf (width));
            writer.write_string ("/Height %d\n".printf (height));
            writer.write_string ("/ColorSpace /%s\n".printf (color_space));
            writer.write_string ("/BitsPerComponent %d\n".printf (depth));
            writer.write_string ("/Length %d\n".printf (data.length));
            if (filter != null)
                writer.write_string ("/Filter /%s\n".printf (filter));
            writer.write_string (">>\n");
            writer.write_string ("stream\n");
            writer.write (data);
            writer.write_string ("\n");
            writer.write_string ("endstream\n");
            writer.write_string ("endobj\n");

            /* Page contents */
            var command = "q\n%s 0 0 %s 0 0 cm\n/Im%d Do\nQ".printf (page_width.format (width_buffer, "%f"), page_height.format (height_buffer, "%f"), i);
            writer.write_string ("\n");
            number = writer.start_object ();
            writer.write_string ("%u 0 obj\n".printf (number));
            writer.write_string ("<<\n");
            writer.write_string ("/Length %d\n".printf (command.length + 1));
            writer.write_string (">>\n");
            writer.write_string ("stream\n");
            writer.write_string (command);
            writer.write_string ("\n");
            writer.write_string ("endstream\n");
            writer.write_string ("endobj\n");
        }

        /* Info */
        writer.write_string ("\n");
        var info_number = writer.start_object ();
        writer.write_string ("%u 0 obj\n".printf (info_number));
        writer.write_string ("<<\n");
        writer.write_string ("/Creator (Simple Scan %s)\n".printf (Config.VERSION));
        writer.write_string (">>\n");
        writer.write_string ("endobj\n");

        /* Cross-reference table */
        var xref_offset = writer.offset;
        writer.write_string ("xref\n");
        writer.write_string ("1 %zu\n".printf (writer.object_offsets.length ()));
        foreach (var offset in writer.object_offsets)
            writer.write_string ("%010zu 0000 n\n".printf (offset));

        /* Trailer */
        writer.write_string ("trailer\n");
        writer.write_string ("<<\n");
        writer.write_string ("/Size %zu\n".printf (writer.object_offsets.length ()));
        writer.write_string ("/Info %u 0 R\n".printf (info_number));
        writer.write_string ("/Root %u 0 R\n".printf (catalog_number));
        //FIXME: writer.write_string ("/ID [<...> <...>]\n");
        writer.write_string (">>\n");
        writer.write_string ("startxref\n");
        writer.write_string ("%zu\n".printf (xref_offset));
        writer.write_string ("%%%%EOF\n");
    }

    public void save (string type, File file) throws Error
    {
        if (strcmp (type, "jpeg") == 0)
            save_multi_file ("jpeg", file);
        else if (strcmp (type, "png") == 0)
            save_multi_file ("png", file);
        else if (strcmp (type, "tiff") == 0)
            save_multi_file ("tiff", file);
        else if (strcmp (type, "ps") == 0)
            save_ps (file);
        else if (strcmp (type, "pdf") == 0)
            save_pdf (file);
    }

    public void set_needs_saving (bool needs_saving)
    {
        var needed_saving = this.needs_saving;
        this.needs_saving = needs_saving;
        if (needed_saving != needs_saving)
            needs_saving_changed ();
    }

    public bool get_needs_saving ()
    {
        return needs_saving;
    }
}

private class PDFWriter
{
    public size_t offset = 0;
    public List<uint> object_offsets;
    private FileOutputStream stream;

    public PDFWriter (FileOutputStream stream)
    {
        this.stream = stream;
    }

    public void write (uchar[] data)
    {
        try
        {
            stream.write_all (data, null, null);
        }
        catch (Error e)
        {
            warning ("Error writing PDF: %s", e.message);
        }
        offset += data.length;
    }

    public void write_string (string text)
    {
        write ((uchar[]) text);
    }

    public uint start_object ()
    {
        object_offsets.append ((uint)offset);
        return object_offsets.length ();
    }
}
