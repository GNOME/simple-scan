namespace GUsb {
	/* Fixed in 0.2.7: https://github.com/hughsie/libgusb/commit/83a6b1a20653c1a17f0a909f08652b5e1df44075 */
	public GLib.GenericArray<GUsb.Device> context_get_devices (GUsb.Context context);
}

/* Copied from Vala version because it has incorrect field (fixed in PK 1.0.8) and does async badly */
[CCode (cprefix = "Pk", cheader_filename = "packagekit-glib2/packagekit.h", lower_case_cprefix = "pk_")]
namespace Pk {
	public class Task : GLib.Object {
		[CCode (has_construct_function = false)]
		public Task ();    
		[CCode (finish_function = "pk_task_generic_finish")]
		public async Pk.Results resolve_async (Pk.Bitfield filters, [CCode (array_length = false, array_null_terminated = true)] string[] packages, GLib.Cancellable? cancellable, Pk.ProgressCallback progress_callback) throws GLib.Error;
		[CCode (finish_function = "pk_task_generic_finish")]
		public async Pk.Results install_packages_async ([CCode (array_length = false, array_null_terminated = true)] string[] package_ids, GLib.Cancellable? cancellable, Pk.ProgressCallback progress_callback) throws GLib.Error;
	}
	public class Results : GLib.Object {
		public GLib.GenericArray<weak Pk.Package> get_package_array ();
		public Pk.Error get_error_code ();
	}
	public class Package : GLib.Object {
		public unowned string get_id ();    
	}
	public class Progress : GLib.Object {
	}
	public class Error : GLib.Object {
		[NoAccessorMethod]
		public string details { owned get; set; }
	}
	[CCode (instance_pos = 2.9)]
	public delegate void ProgressCallback (Pk.Progress progress, Pk.ProgressType type);
	[CCode (cprefix = "PK_PROGRESS_TYPE_", type_id = "pk_progress_type_get_type ()")]
	public enum ProgressType {
		PACKAGE_ID,
		TRANSACTION_ID,
		PERCENTAGE,
		ALLOW_CANCEL,
		STATUS,
		ROLE,
		CALLER_ACTIVE,
		ELAPSED_TIME,
		REMAINING_TIME,
		SPEED,
		DOWNLOAD_SIZE_REMAINING,
		UID,
		PACKAGE,
		ITEM_PROGRESS,
		TRANSACTION_FLAGS,
		INVALID
	}
	[SimpleType]
	public struct Bitfield : uint64 {
	}
	[CCode (cname = "PkFilterEnum", cprefix = "PK_FILTER_ENUM_", type_id = "pk_filter_enum_get_type ()")]
	public enum Filter {
		UNKNOWN,
		NONE,
		INSTALLED,
		NOT_INSTALLED,
		DEVELOPMENT,
		NOT_DEVELOPMENT,
		GUI,
		NOT_GUI,
		FREE,
		NOT_FREE,
		VISIBLE,
		NOT_VISIBLE,
		SUPPORTED,
		NOT_SUPPORTED,
		BASENAME,
		NOT_BASENAME,
		NEWEST,
		NOT_NEWEST,
		ARCH,
		NOT_ARCH,
		SOURCE,
		NOT_SOURCE,
		COLLECTIONS,
		NOT_COLLECTIONS,
		APPLICATION,
		NOT_APPLICATION,
		DOWNLOADED,
		NOT_DOWNLOADED,
	}
}
