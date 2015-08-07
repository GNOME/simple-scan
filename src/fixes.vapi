namespace GUsb {
	/* Fixed in 0.2.7: https://github.com/hughsie/libgusb/commit/83a6b1a20653c1a17f0a909f08652b5e1df44075 */
	public GLib.GenericArray<GUsb.Device> context_get_devices (GUsb.Context context);
}
