/*
 * Copyright (C) 2017 Stéphane Fillion
 * Authors: Stéphane Fillion <stphanef3724@gmail.com>
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later
 * version. See http://www.gnu.org/copyleft/gpl.html the full text of the
 * license.
 */

namespace WebP
{
    // Error codes
    [CCode (cheader_filename = "webp/mux.h", cname = "WebPMuxError", cprefix = "WEBP_MUX_", has_type_id = false)]
    public enum MuxError
    {
        OK                 =  1,
        NOT_FOUND          =  0,
        INVALID_ARGUMENT   = -1,
        BAD_DATA           = -2,
        MEMORY_ERROR       = -3,
        NOT_ENOUGH_DATA    = -4
    }

    // Data type used to describe 'raw' data, e.g., chunk data
    // (ICC profile, metadata) and WebP compressed image data.
    [CCode (cheader_filename = "webp/mux.h", cname = "WebPData", destroy_function = "", has_type_id = false)]
    private struct Data
    {
        [CCode (array_length = false)] unowned uint8[] bytes;
        size_t size;
    }

    // main opaque object.
    [CCode (cheader_filename = "webp/mux.h", cname = "WebPMux", free_function = "WebPMuxDelete")]
    [Compact]
    public class Mux
    {
        // Creates an empty mux object.
        // Returns:
        //   A pointer to the newly created empty mux object.
        //   Or NULL in case of memory error.
        [CCode (cname = "WebPMuxNew")]
        public static Mux? new_mux ();

        // Sets the (non-animated and non-fragmented) image in the mux object.
        // Note: Any existing images (including frames/fragments) will be removed.
        // Parameters:
        //   mux - (in/out) object in which the image is to be set
        //   bitstream - (in) can be a raw VP8/VP8L bitstream or a single-image
        //               WebP file (non-animated and non-fragmented)
        //   copy_data - (in) value 1 indicates given data WILL be copied to the mux
        //               object and value 0 indicates data will NOT be copied.
        // Returns:
        //   WEBP_MUX_INVALID_ARGUMENT - if mux is NULL or bitstream is NULL.
        //   WEBP_MUX_MEMORY_ERROR - on memory allocation error.
        //   WEBP_MUX_OK - on success.
        [CCode (cname = "WebPMuxSetImage")]
        private MuxError _set_image (Data bitstream, bool copy_data);
        [CCode (cname = "vala_set_image")]
        public MuxError set_image (uint8[] bitstream, bool copy_data)
        {
                Data data = { bitstream, bitstream.length };
                return _set_image (data, copy_data);
        }

        // Adds a chunk with id 'fourcc' and data 'chunk_data' in the mux object.
        // Any existing chunk(s) with the same id will be removed.
        // Parameters:
        //   mux - (in/out) object to which the chunk is to be added
        //   fourcc - (in) a character array containing the fourcc of the given chunk;
        //                 e.g., "ICCP", "XMP ", "EXIF" etc.
        //   chunk_data - (in) the chunk data to be added
        //   copy_data - (in) value 1 indicates given data WILL be copied to the mux
        //               object and value 0 indicates data will NOT be copied.
        // Returns:
        //   WEBP_MUX_INVALID_ARGUMENT - if mux, fourcc or chunk_data is NULL
        //                               or if fourcc corresponds to an image chunk.
        //   WEBP_MUX_MEMORY_ERROR - on memory allocation error.
        //   WEBP_MUX_OK - on success.
        [CCode (cname = "WebPMuxSetChunk")]
        private MuxError _set_chunk ([CCode (array_length = false)] uchar[] fourcc,
                                     Data chunk_data,
                                     bool copy_data);
        [CCode (cname = "vala_set_chunk")]
        public MuxError set_chunk (string fourcc, uint8[] chunk_data, bool copy_data)
        requires (fourcc.length == 4)
        {
            Data data = { chunk_data ,chunk_data.length };
            return _set_chunk ((uchar[]) fourcc, data, copy_data);
        }

        // Assembles all chunks in WebP RIFF format and returns in 'assembled_data'.
        // This function also validates the mux object.
        // Note: The content of 'assembled_data' will be ignored and overwritten.
        // Also, the content of 'assembled_data' is allocated using malloc(), and NOT
        // owned by the 'mux' object. It MUST be deallocated by the caller by calling
        // WebPDataClear(). It's always safe to call WebPDataClear() upon return,
        // even in case of error.
        // Parameters:
        //   mux - (in/out) object whose chunks are to be assembled
        //   assembled_data - (out) assembled WebP data
        // Returns:
        //   WEBP_MUX_BAD_DATA - if mux object is invalid.
        //   WEBP_MUX_INVALID_ARGUMENT - if mux or assembled_data is NULL.
        //   WEBP_MUX_MEMORY_ERROR - on memory allocation error.
        //   WEBP_MUX_OK - on success.
        [CCode (cname = "WebPMuxAssemble")]
        private MuxError _assemble (out Data assembled_data);
        [CCode (cname = "vala_assemble")]
        public MuxError assemble (out uint8[] assembled_data)
        {
            Data data;
            MuxError mux_error;
            unowned uint8[] out_array;
            mux_error = _assemble (out data);
            out_array = data.bytes;
            out_array.length = (int) data.size;
            assembled_data = out_array;
            return mux_error;
        }
    }
}
