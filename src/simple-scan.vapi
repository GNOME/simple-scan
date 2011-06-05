// FIXME: Buf reference
public delegate bool PixbufSaveFunc (uint8[] buf, out GLib.Error error);
bool gdk_pixbuf_save_to_callbackv (Gdk.Pixbuf pixbuf, PixbufSaveFunc save_func, string type, [CCode (array_length = false)] string[] option_keys, [CCode (array_length = false)] string[] option_values) throws GLib.Error;
