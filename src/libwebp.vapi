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
    // Returns the size of the compressed data (pointed to by *output), or 0 if
    // an error occurred. The compressed data must be released by the caller
    // using the call 'free(*output)'.
    // These functions compress using the lossy format, and the quality_factor
    // can go from 0 (smaller output, lower quality) to 100 (best quality,
    // larger output).
    [CCode (cheader_filename = "webp/encode.h", cname = "WebPEncodeRGB")]
    private size_t _encode_rgb ([CCode (array_length = false)] uint8[] rgb,
                                int width,
                                int height,
                                int stride,
                                float quality_factor,
                                [CCode (array_length = false)] out uint8[] output);
    [CCode (cname = "vala_encode_rgb")]
    public uint8[] encode_rgb (uint8[] rgb, int width, int height, int stride, float quality_factor)
    {
        uint8[] output;
        size_t length;
        length = _encode_rgb (rgb, width, height, stride, quality_factor, out output);
        output.length = (int) length;
        return output;
    }

    // These functions are the equivalent of the above, but compressing in a
    // lossless manner. Files are usually larger than lossy format, but will
    // not suffer any compression loss.
    [CCode (cheader_filename = "webp/encode.h", cname = "WebPEncodeLosslessRGB")]
    private size_t _encode_lossless_rgb ([CCode (array_length = false)] uint8[] rgb,
                                         int width,
                                         int height,
                                         int stride,
                                         [CCode (array_length = false)] out uint8[] output);
    [CCode (cname = "vala_encode_lossless_rgb")]
    public uint8[] encode_lossless_rgb (uint8[] rgb, int width, int height, int stride)
    {
        uint8[] output;
        size_t length;
        length = _encode_lossless_rgb (rgb, width, height, stride, out output);
        output.length = (int) length;
        return output;
    }
}
