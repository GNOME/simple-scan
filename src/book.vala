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

public delegate void ProgressionCallback (double fraction);

// Assumes first page has index 0
public enum FlipEverySecond {
    Even = 1,
    Odd = 0,
}

public class Book : Object
{
    private List<Page> pages;

    public uint n_pages { get { return pages.length (); } }

    public signal void page_added (Page page);
    public signal void page_removed (Page page);
    public signal void reordered ();
    public signal void cleared ();
    public signal void changed ();

    public Book ()
    {
        pages = new List<Page> ();
    }

    ~Book ()
    {
        foreach (var page in pages)
        {
            page.pixels_changed.disconnect (page_changed_cb);
            page.crop_changed.disconnect (page_changed_cb);
        }
    }

    public void clear ()
    {
        foreach (var page in pages)
        {
            page.pixels_changed.disconnect (page_changed_cb);
            page.crop_changed.disconnect (page_changed_cb);
        }
        pages = null;
        cleared ();
    }

    private void page_changed_cb (Page page)
    {
        changed ();
    }

    public void append_page (Page page)
    {
        page.pixels_changed.connect (page_changed_cb);
        page.crop_changed.connect (page_changed_cb);

        pages.append (page);
        page_added (page);
        changed ();
    }

    public void move_page (Page page, uint location)
    {
        pages.remove (page);
        pages.insert (page, (int) location);
        reordered ();
        changed ();
    }

    public void reverse ()
    {
        var new_pages = new List<Page> ();
        foreach (var page in pages)
            new_pages.prepend (page);
        pages = (owned) new_pages;

        reordered ();
        changed ();
    }

    public void combine_sides ()
    {
        var n_front = n_pages - n_pages / 2;
        var new_pages = new List<Page> ();
        for (var i = 0; i < n_pages; i++)
        {
            if (i % 2 == 0)
                new_pages.append (pages.nth_data (i / 2));
            else
                new_pages.append (pages.nth_data (n_front + (i / 2)));
        }
        pages = (owned) new_pages;

        reordered ();
        changed ();
    }

    public void flip_every_second (FlipEverySecond flip)
    {
        var new_pages = new List<Page> ();
        for (var i = 0; i < n_pages; i++)
        {
            var page = pages.nth_data (i);
            if (i % 2 == (int)flip) {
                page.rotate_left();
                page.rotate_left();
                new_pages.append (page);
            } else {
                new_pages.append (page);
            }
        }
        pages = (owned) new_pages;

        reordered ();
        changed ();
    }

    public void combine_sides_reverse ()
    {
        var new_pages = new List<Page> ();
        for (var i = 0; i < n_pages; i++)
        {
            if (i % 2 == 0)
                new_pages.append (pages.nth_data (i / 2));
            else
                new_pages.append (pages.nth_data (n_pages - 1 - (i / 2)));
        }
        pages = (owned) new_pages;

        reordered ();
        changed ();
    }

    public void delete_page (Page page)
    {
        page.pixels_changed.disconnect (page_changed_cb);
        page.crop_changed.disconnect (page_changed_cb);
        pages.remove (page);
        page_removed (page);
        changed ();
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

    public async void save_async (string mime_type, int quality, File file,
        ProgressionCallback? progress_cb, Cancellable? cancellable = null) throws Error
    {
        var book_saver = new BookSaver ();
        yield book_saver.save_async (this, mime_type, quality, file,
            progress_cb, cancellable);
    }

    public async void postprocess_async (string mime_type, File file, bool postproc_enabled,
        string postproc_script, string postproc_arguments, bool postproc_keep_original) throws Error
        {
            var book_saver = new BookSaver ();
            yield book_saver.postprocess_async (mime_type, file, postproc_enabled,
                postproc_script, postproc_arguments, postproc_keep_original);
        }
}

private class BookSaver
{
    private uint n_pages;
    private int quality;
    private File file;
    private unowned ProgressionCallback progression_callback;
    private double progression;
    private Mutex progression_mutex;
    private Cancellable? cancellable;
    private AsyncQueue<WriteTask> write_queue;
    private ThreadPool<EncodeTask> encoder;
    private SourceFunc save_async_callback;
    private Postprocessor postprocessor = new Postprocessor();

    /* save_async get called in the main thread to start saving. It
     * distributes all encode tasks to other threads then yield so
     * the ui can continue operating. The method then return once saving
     * is completed, cancelled, or failed */
    public async void save_async (Book book, string mime_type, int quality, File file,
        ProgressionCallback? progression_callback, Cancellable? cancellable) throws Error
    {
        var timer = new Timer ();

        this.n_pages = book.n_pages;
        this.quality = quality;
        this.file = file;
        this.cancellable = cancellable;
        this.save_async_callback = save_async.callback;
        this.write_queue = new AsyncQueue<WriteTask> ();
        this.progression = 0;
        this.progression_mutex = Mutex ();

        /* Configure a callback that monitor saving progression */
        if (progression_callback == null)
            this.progression_callback = (fraction) =>
            {
                debug ("Save progression: %f%%", fraction*100.0);
            };
        else
            this.progression_callback = progression_callback;

        /* Configure an encoder */
        ThreadPoolFunc<EncodeTask>? encode_delegate = null;
        switch (mime_type)
        {
        case "image/jpeg":
            encode_delegate = encode_jpeg;
            break;
        case "image/png":
            encode_delegate = encode_png;
            break;
#if HAVE_WEBP
        case "image/webp":
            encode_delegate = encode_webp;
            break;
#endif
        case "application/pdf":
            encode_delegate = encode_pdf;
            break;
        }
        encoder = new ThreadPool<EncodeTask>.with_owned_data (encode_delegate, (int) get_num_processors (), false);

        /* Configure a writer */
        Thread<Error?> writer;

        switch (mime_type)
        {
        case "image/jpeg":
        case "image/png":
#if HAVE_WEBP
        case "image/webp":
#endif
            writer = new Thread<Error?> (null, write_multifile);
            break;
        case "application/pdf":
            writer = new Thread<Error?> (null, write_pdf);
            break;
        default:
            writer = new Thread<Error?> (null, () => null);
            break;
        }

        /* Issue encode tasks */
        for (var i = 0; i < n_pages; i++)
        {
            var encode_task = new EncodeTask ();
            encode_task.number = i;
            encode_task.page = book.get_page(i);
            encoder.add ((owned) encode_task);
        }

        /* Waiting for saving to finish */
        yield;

        /* Any error from any thread ends up here */
        var error = writer.join ();
        if (error != null)
            throw error;

        timer.stop ();
        debug ("Save time: %f seconds", timer.elapsed (null));
    }

    public async void postprocess_async(string mime_type, File file, bool postproc_enabled,
        string postproc_script, string postproc_arguments, bool postproc_keep_original) throws Error
    {
        if ( postproc_enabled && postproc_script.length != 0 ) {
        /* Perform post-processing */
            var timer = new Timer ();
            var return_code = postprocessor.process(postproc_script,
                                                    mime_type,              // MIME Type
                                                    postproc_keep_original, // Keep Original
                                                    file.get_path(),        // Filename
                                                    postproc_arguments      // Arguments
                                                    );
            if ( return_code != 0 ) {
                warning ("Postprocessing script execution failed. ");
            }
            timer.stop ();
            debug ("Postprocessing time: %f seconds", timer.elapsed (null));
        }
    }

    /* Those methods are run in the encoder threads pool. It process
     * one encode_task issued by save_async and reissue the result with
     * a write_task */

    private void encode_png (owned EncodeTask encode_task)
    {
        var page = encode_task.page;
        var icc_data = page.get_icc_data_encoded ();
        var write_task = new WriteTask ();
        var image = page.get_image (true);

        string[] keys = { "x-dpi", "y-dpi", "icc-profile", null };
        string[] values = { "%d".printf (page.dpi), "%d".printf (page.dpi), icc_data, null };
        if (icc_data == null)
            keys[2] = null;

        try
        {
            image.save_to_bufferv (out write_task.data, "png", keys, values);
        }
        catch (Error error)
        {
            write_task.error = error;
        }
        write_task.number = encode_task.number;
        write_queue.push ((owned) write_task);

        update_progression ();
    }

    private void encode_jpeg (owned EncodeTask encode_task)
    {
        var page = encode_task.page;
        var icc_data = page.get_icc_data_encoded ();
        var write_task = new WriteTask ();
        var image = page.get_image (true);

        string[] keys = { "x-dpi", "y-dpi", "quality", "icc-profile", null };
        string[] values = { "%d".printf (page.dpi), "%d".printf (page.dpi), "%d".printf (quality), icc_data, null };
        if (icc_data == null)
            keys[3] = null;

        try
        {
            image.save_to_bufferv (out write_task.data, "jpeg", keys, values);
        }
        catch (Error error)
        {
            write_task.error = error;
        }
        write_task.number = encode_task.number;
        write_queue.push ((owned) write_task);

        update_progression ();
    }

#if HAVE_WEBP
    private void encode_webp (owned EncodeTask encode_task)
    {
        var page = encode_task.page;
        var icc_data = page.get_icc_data_encoded ();
        var write_task = new WriteTask ();
        var image = page.get_image (true);
        var webp_data = WebP.encode_rgb (image.get_pixels (),
                                         image.get_width (),
                                         image.get_height (),
                                         image.get_rowstride (),
                                         (float) quality);
#if HAVE_COLORD
        WebP.MuxError mux_error;
        var mux = WebP.Mux.new_mux ();
        uint8[] output;

        mux_error = mux.set_image (webp_data, false);
        debug ("mux.set_image: %s", mux_error.to_string ());

        if (icc_data != null)
        {
            mux_error = mux.set_chunk ("ICCP", icc_data.data, false);
            debug ("mux.set_chunk: %s", mux_error.to_string ());
            if (mux_error != WebP.MuxError.OK)
                warning ("icc profile data not saved with page %i", encode_task.number);
        }

        mux_error = mux.assemble (out output);
        debug ("mux.assemble: %s", mux_error.to_string ());
        if (mux_error != WebP.MuxError.OK)
            write_task.error = new FileError.FAILED (_("Unable to encode page %i").printf (encode_task.number));

        write_task.data = (owned) output;
#else

        if (webp_data.length == 0)
            write_task.error = new FileError.FAILED (_("Unable to encode page %i").printf (encode_task.number));

        write_task.data = (owned) webp_data;
#endif
        write_task.number = encode_task.number;
        write_queue.push ((owned) write_task);

        update_progression ();
    }
#endif

    private void encode_pdf (owned EncodeTask encode_task)
    {
        var page = encode_task.page;
        var image = page.get_image (true);
        var width = image.width;
        var height = image.height;
        unowned uint8[] pixels = image.get_pixels ();
        int depth = 8;
        string color_space = "DeviceRGB";
        string? filter = null;
        uint8[] data;

        if (page.is_color)
        {
            depth = 8;
            color_space = "DeviceRGB";
            var data_length = height * width * 3;
            data = new uint8[data_length];
            for (var row = 0; row < height; row++)
            {
                var in_offset = row * image.rowstride;
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
        else if (page.depth == 2)
        {
            int shift_count = 6;
            depth = 2;
            color_space = "DeviceGray";
            var data_length = height * ((width * 2 + 7) / 8);
            data = new uint8[data_length];
            var offset = 0;
            for (var row = 0; row < height; row++)
            {
                /* Pad to the next line */
                if (shift_count != 6)
                {
                    offset++;
                    shift_count = 6;
                }

                var in_offset = row * image.rowstride;
                for (var x = 0; x < width; x++)
                {
                    /* Clear byte */
                    if (shift_count == 6)
                        data[offset] = 0;

                    /* Set bits */
                    var p = pixels[in_offset + x*3];
                    if (p >= 192)
                        data[offset] |= 3 << shift_count;
                    else if (p >= 128)
                        data[offset] |= 2 << shift_count;
                    else if (p >= 64)
                        data[offset] |= 1 << shift_count;

                    /* Move to the next position */
                    if (shift_count == 0)
                    {
                        offset++;
                        shift_count = 6;
                    }
                    else
                        shift_count -= 2;
                }
            }
        }
        else if (page.depth == 1)
        {
            int mask = 0x80;

            depth = 1;
            color_space = "DeviceGray";
            var data_length = height * ((width + 7) / 8);
            data = new uint8[data_length];
            var offset = 0;
            for (var row = 0; row < height; row++)
            {
                /* Pad to the next line */
                if (mask != 0x80)
                {
                    offset++;
                    mask = 0x80;
                }

                var in_offset = row * image.rowstride;
                for (var x = 0; x < width; x++)
                {
                    /* Clear byte */
                    if (mask == 0x80)
                        data[offset] = 0;

                    /* Set bit */
                    if (pixels[in_offset+x*3] != 0)
                        data[offset] |= (uint8) mask;

                    /* Move to the next bit */
                    mask >>= 1;
                    if (mask == 0)
                    {
                        offset++;
                        mask = 0x80;
                    }
                }
            }
        }
        else
        {
            depth = 8;
            color_space = "DeviceGray";
            var data_length = height * width;
            data = new uint8 [data_length];
            for (var row = 0; row < height; row++)
            {
                var in_offset = row * image.rowstride;
                var out_offset = row * width;
                for (var x = 0; x < width; x++)
                    data[out_offset+x] = pixels[in_offset+x*3];
            }
        }

        /* Compress data and use zlib compression if it is smaller than JPEG.
         * zlib compression is slower in the worst case, so do JPEG first
         * and stop zlib if it exceeds the JPEG size */
        var write_task = new WriteTaskPDF ();
        uint8[]? jpeg_data = null;
        try
        {
            jpeg_data = compress_jpeg (image, quality, page.dpi);
        }
        catch (Error error)
        {
            write_task.error = error;
        }
        var zlib_data = compress_zlib (data, jpeg_data.length);
        if (zlib_data != null)
        {
            filter = "FlateDecode";
            data = zlib_data;
        }
        else
        {
            /* JPEG encoder converts to 8-bit RGB, see issue #459 */
            depth = 8;
            color_space = "DeviceRGB";
            filter = "DCTDecode";
            data = jpeg_data;
        }

        write_task.number = encode_task.number;
        write_task.data = data;
        write_task.width = width;
        write_task.height = height;
        write_task.color_space = color_space;
        write_task.depth = depth;
        write_task.filter = filter;
        write_task.dpi = page.dpi;
        write_queue.push (write_task);

        update_progression ();
    }

    private Error? write_multifile ()
    {
        for (var i=0; i < n_pages; i++)
        {
            if (cancellable.is_cancelled ())
            {
                finished_saving ();
                return null;
            }

            var write_task = write_queue.pop ();
            if (write_task.error != null)
            {
                finished_saving ();
                return write_task.error;
            }

            var indexed_file = make_indexed_file (file.get_uri (), write_task.number, n_pages);
            try
            {
                var stream = indexed_file.replace (null, false, FileCreateFlags.NONE);
                stream.write_all (write_task.data, null);
            }
            catch (Error error)
            {
                finished_saving ();
                return error;
            }
        }

        update_progression ();
        finished_saving ();
        return null;
    }

    /* Those methods are run in the writer thread. It receive all
     * write_tasks sent to it by the encoder threads and write those to
     * disk. */

    private Error? write_pdf ()
    {
        /* Generate a random ID for this file */
        var id = "";
        for (var i = 0; i < 4; i++)
            id += "%08x".printf (Random.next_int ());

        FileOutputStream? stream = null;
        try
        {
            stream = file.replace (null, false, FileCreateFlags.NONE, null);
        }
        catch (Error error)
        {
            finished_saving ();
            return error;
        }
        var writer = new PDFWriter (stream);

        /* Choose object numbers */
        var catalog_number = writer.add_object ();
        var metadata_number = writer.add_object ();
        var pages_number = writer.add_object ();
        var info_number = writer.add_object ();
        var page_numbers = new uint[n_pages];
        var page_image_numbers = new uint[n_pages];
        var page_content_numbers = new uint[n_pages];
        for (var i = 0; i < n_pages; i++)
        {
            page_numbers[i] = writer.add_object ();
            page_image_numbers[i] = writer.add_object ();
            page_content_numbers[i] = writer.add_object ();
        }
        var struct_tree_root_number = writer.add_object ();

        /* Header */
        writer.write_string ("%PDF-1.3\n");

        /* Comment with binary as recommended so file is treated as binary */
        writer.write_string ("%\xe2\xe3\xcf\xd3\n");

        /* Catalog */
        writer.start_object (catalog_number);
        writer.write_string ("%u 0 obj\n".printf (catalog_number));
        writer.write_string ("<<\n");
        writer.write_string ("/Type /Catalog\n");
        writer.write_string ("/Metadata %u 0 R\n".printf (metadata_number));
        writer.write_string ("/MarkInfo << /Marked true >>\n");
        writer.write_string ("/StructTreeRoot %u 0 R\n".printf (struct_tree_root_number));
        writer.write_string ("/Pages %u 0 R\n".printf (pages_number));
        writer.write_string (">>\n");
        writer.write_string ("endobj\n");

        /* Metadata */
        var now = new DateTime.now_local ();
        var date_string = now.format ("%FT%H:%M:%S%:z");
        /* NOTE: The id has to be hardcoded to this value according to the spec... */
        var metadata = """<?xpacket begin="%s" id="W5M0MpCehiHzreSzNTczkc9d"?>
<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
         xmlns:xmp="http://ns.adobe.com/xap/1.0/">
  <rdf:Description rdf:about=""
                   xmlns:pdfaid="http://www.aiim.org/pdfa/ns/id/"
                   xmlns:xmp="http://ns.adobe.com/xap/1.0/">
    <pdfaid:part>1</pdfaid:part>
    <pdfaid:conformance>A</pdfaid:conformance>
    <xmp:CreatorTool>Simple Scan %s</xmp:CreatorTool>
    <xmp:CreateDate>%s</xmp:CreateDate>
    <xmp:ModifyDate>%s</xmp:ModifyDate>
    <xmp:MetadataDate>%s</xmp:MetadataDate>
  </rdf:Description>
</rdf:RDF>
<?xpacket end="w"?>""".printf (((unichar) 0xFEFF).to_string (), VERSION, date_string, date_string, date_string);
        writer.write_string ("\n");
        writer.start_object (metadata_number);
        writer.write_string ("%u 0 obj\n".printf (metadata_number));
        writer.write_string ("<<\n");
        writer.write_string ("/Type /Metadata\n");
        writer.write_string ("/Subtype /XML\n");
        writer.write_string ("/Length %u\n".printf (metadata.length));
        writer.write_string (">>\n");
        writer.write_string ("stream\n");
        writer.write_string (metadata);
        writer.write_string ("\n");
        writer.write_string ("endstream\n");
        writer.write_string ("endobj\n");

        /* Pages */
        writer.write_string ("\n");
        writer.start_object (pages_number);
        writer.write_string ("%u 0 obj\n".printf (pages_number));
        writer.write_string ("<<\n");
        writer.write_string ("/Type /Pages\n");
        writer.write_string ("/Kids [");
        for (var i = 0; i < n_pages; i++)
            writer.write_string (" %u 0 R".printf (page_numbers[i]));
        writer.write_string (" ]\n");
        writer.write_string ("/Count %u\n".printf (n_pages));
        writer.write_string (">>\n");
        writer.write_string ("endobj\n");

        /* Process each page in order */
        var tasks_in_standby = new Queue<WriteTaskPDF> ();
        for (int i = 0; i < n_pages; i++)
        {
            if (cancellable.is_cancelled ())
            {
                finished_saving ();
                return null;
            }

            var write_task = tasks_in_standby.peek_head ();
            if (write_task != null && write_task.number == i)
                tasks_in_standby.pop_head ();
            else
            {
                while (true)
                {
                    write_task = (WriteTaskPDF) write_queue.pop ();
                    if (write_task.error != null)
                    {
                        finished_saving ();
                        return write_task.error;
                    }
                    if (write_task.number == i)
                        break;

                    tasks_in_standby.insert_sorted (write_task, (a, b) => {return a.number - b.number;});
                }
            }

            var page_width = write_task.width * 72.0 / write_task.dpi;
            var page_height = write_task.height * 72.0 / write_task.dpi;
            var width_buffer = new char[double.DTOSTR_BUF_SIZE];
            var height_buffer = new char[double.DTOSTR_BUF_SIZE];

            /* Page */
            writer.write_string ("\n");
            writer.start_object (page_numbers[i]);
            writer.write_string ("%u 0 obj\n".printf (page_numbers[i]));
            writer.write_string ("<<\n");
            writer.write_string ("/Type /Page\n");
            writer.write_string ("/Parent %u 0 R\n".printf (pages_number));
            writer.write_string ("/Resources << /XObject << /Im%d %u 0 R >> >>\n".printf (i, page_image_numbers[i]));
            writer.write_string ("/MediaBox [ 0 0 %s %s ]\n".printf (page_width.format (width_buffer, "%.2f"), page_height.format (height_buffer, "%.2f")));
            writer.write_string ("/Contents %u 0 R\n".printf (page_content_numbers[i]));
            writer.write_string (">>\n");
            writer.write_string ("endobj\n");

            /* Page image */
            writer.write_string ("\n");
            writer.start_object (page_image_numbers[i]);
            writer.write_string ("%u 0 obj\n".printf (page_image_numbers[i]));
            writer.write_string ("<<\n");
            writer.write_string ("/Type /XObject\n");
            writer.write_string ("/Subtype /Image\n");
            writer.write_string ("/Width %d\n".printf (write_task.width));
            writer.write_string ("/Height %d\n".printf (write_task.height));
            writer.write_string ("/ColorSpace /%s\n".printf (write_task.color_space));
            writer.write_string ("/BitsPerComponent %d\n".printf (write_task.depth));
            writer.write_string ("/Length %d\n".printf (write_task.data.length));
            if (write_task.filter != null)
                writer.write_string ("/Filter /%s\n".printf (write_task.filter));
            writer.write_string (">>\n");
            writer.write_string ("stream\n");
            writer.write (write_task.data);
            writer.write_string ("\n");
            writer.write_string ("endstream\n");
            writer.write_string ("endobj\n");

            /* Structure tree */
            writer.write_string ("\n");
            writer.start_object (struct_tree_root_number);
            writer.write_string ("%u 0 obj\n".printf (struct_tree_root_number));
            writer.write_string ("<<\n");
            writer.write_string ("/Type /StructTreeRoot\n");
            writer.write_string (">>\n");
            writer.write_string ("endobj\n");

            /* Page contents */
            var command = "q\n%s 0 0 %s 0 0 cm\n/Im%d Do\nQ".printf (page_width.format (width_buffer, "%f"), page_height.format (height_buffer, "%f"), i);
            writer.write_string ("\n");
            writer.start_object (page_content_numbers[i]);
            writer.write_string ("%u 0 obj\n".printf (page_content_numbers[i]));
            writer.write_string ("<<\n");
            writer.write_string ("/Length %d\n".printf (command.length));
            writer.write_string (">>\n");
            writer.write_string ("stream\n");
            writer.write_string (command);
            writer.write_string ("\n");
            writer.write_string ("endstream\n");
            writer.write_string ("endobj\n");
        }

        /* Info */
        writer.write_string ("\n");
        writer.start_object (info_number);
        writer.write_string ("%u 0 obj\n".printf (info_number));
        writer.write_string ("<<\n");
        writer.write_string ("/Creator (Simple Scan %s)\n".printf (VERSION));
        writer.write_string (">>\n");
        writer.write_string ("endobj\n");

        /* Cross-reference table */
        writer.write_string ("\n");
        var xref_offset = writer.offset;
        writer.write_string ("xref\n");
        writer.write_string ("0 %zu\n".printf (writer.object_offsets.length + 1));
        writer.write_string ("%010zu 65535 f \n".printf (writer.next_empty_object (0)));
        for (var i = 0; i < writer.object_offsets.length; i++)
            if (writer.object_offsets[i] == 0)
                writer.write_string ("%010zu 65535 f \n".printf (writer.next_empty_object (i + 1)));
            else
                writer.write_string ("%010zu 00000 n \n".printf (writer.object_offsets[i]));

        /* Trailer */
        writer.write_string ("\n");
        writer.write_string ("trailer\n");
        writer.write_string ("<<\n");
        writer.write_string ("/Size %zu\n".printf (writer.object_offsets.length + 1));
        writer.write_string ("/Info %u 0 R\n".printf (info_number));
        writer.write_string ("/Root %u 0 R\n".printf (catalog_number));
        writer.write_string ("/ID [<%s> <%s>]\n".printf (id, id));
        writer.write_string (">>\n");
        writer.write_string ("startxref\n");
        writer.write_string ("%zu\n".printf (xref_offset));
        writer.write_string ("%%EOF\n");

        update_progression ();
        finished_saving ();
        return null;
    }

    /* update_progression is called once by page by encoder threads and
     * once at the end by writer thread. */
    private void update_progression ()
    {
        double step = 1.0 / (double)(n_pages+1);
        progression_mutex.lock ();
        progression += step;
        progression_mutex.unlock ();
        Idle.add (() =>
        {
            progression_callback (progression);
            return false;
        });
    }

    /* finished_saving is called by the writer thread when it's done,
     * meaning there is nothing left to do or saving has been
     * cancelled */
    private void finished_saving ()
    {
        /* At this point, any remaining encode_task ought to remain unprocessed */
        ThreadPool.free ((owned) encoder, true, true);

        /* Wake-up save_async method in main thread */
        Idle.add ((owned)save_async_callback);
    }

    /* Utility methods */

    private static uint8[]? compress_zlib (uint8[] data, uint max_size)
    {
        var stream = ZLib.DeflateStream (ZLib.Level.BEST_COMPRESSION);
        var out_data = new uint8[max_size];

        stream.next_in = data;
        stream.next_out = out_data;
        while (true)
        {
            /* Compression complete */
            if (stream.avail_in == 0)
                break;

            /* Out of space */
            if (stream.avail_out == 0)
                return null;

            if (stream.deflate (ZLib.Flush.FINISH) == ZLib.Status.STREAM_ERROR)
                return null;
        }

        var n_written = out_data.length - stream.avail_out;
        out_data.resize ((int) n_written);

        return out_data;
    }

    private static uint8[] compress_jpeg (Gdk.Pixbuf image, int quality, int dpi) throws Error
    {
        uint8[] jpeg_data;
        string[] keys = { "quality", "x-dpi", "y-dpi", null };
        string[] values = { "%d".printf (quality), "%d".printf (dpi), "%d".printf (dpi), null };

        image.save_to_bufferv (out jpeg_data, "jpeg", keys, values);
        return jpeg_data;
    }
}

private class EncodeTask
{
    public int number;
    public Page page;
}

private class WriteTask
{
    public int number;
    public uint8[] data;
    public Error error;
}

private class WriteTaskPDF : WriteTask
{
    public int width;
    public int height;
    public string color_space;
    public int depth;
    public string? filter;
    public int dpi;
}

private class PDFWriter
{
    public size_t offset = 0;
    public uint[] object_offsets;
    private FileOutputStream stream;

    public PDFWriter (FileOutputStream stream)
    {
        this.stream = stream;
        object_offsets = new uint[0];
    }

    public void write (uint8[] data)
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
        write ((uint8[]) text.to_utf8 ());
    }

    public uint add_object ()
    {
        object_offsets.resize (object_offsets.length + 1);
        var index = object_offsets.length - 1;
        object_offsets[index] = 0;
        return index + 1;
    }

    public void start_object (uint index)
    {
        object_offsets[index - 1] = (uint)offset;
    }

    public int next_empty_object (int start)
    {
        for (var i = start; i < object_offsets.length; i++)
            if (object_offsets[i] == 0)
                return i + 1;
        return 0;
    }
}

public File make_indexed_file (string uri, uint i, uint n_pages)
{
    if (n_pages == 1)
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
    var width = n_pages.to_string().length;
    var number_format = "%%0%dd".printf (width);
    var filename = prefix + "-" + number_format.printf (i + 1) + suffix;
    return File.new_for_uri (filename);
}
