[CCode (cprefix = "Cd", lower_case_cprefix = "cd_", cheader_filename = "colord.h")]
namespace Colord {
	public class Client : GLib.Object {
        public Client ();
		public bool connect_sync (GLib.Cancellable? cancellable = null) throws GLib.Error;
		public Device find_device_by_property_sync (string key, string value, GLib.Cancellable? cancellable = null) throws GLib.Error;
	}
	public class Device : GLib.Object {
		public bool connect_sync (GLib.Cancellable? cancellable = null) throws GLib.Error;
		public Profile? get_default_profile ();
	}
	public class Profile : GLib.Object {
		public bool connect_sync (GLib.Cancellable? cancellable = null) throws GLib.Error;
		public string? filename { get; }
	}
	public const string DEVICE_PROPERTY_SERIAL;
}
