// SPDX-License-Identifier: GPL-3.0-or-later
/*
 * Copyright (C) 2022 Alexander Vogt
 * Author: Alexander Vogt <a.vogt@fulguritus.com>
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later
 * version. See http://www.gnu.org/copyleft/gpl.html the full text of the
 * license.
 */

public class Postprocessor {

    public Postprocessor(){

    }

    public int process(string script, string mime_type, bool keep_original, string source_file, string arguments) throws Error {
        // Code copied and adapted from https://valadoc.org/glib-2.0/GLib.Process.spawn_sync.html
        string[] spawn_args = {script, mime_type, keep_original ? "true" : "false", source_file, arguments };
        string[] spawn_env = Environ.get ();
        string  process_stdout;
        string  process_stderr;
        int     process_status;

        print ("Executing script%s\n", script);
        Process.spawn_sync (null,               // inherit parent's working dir
						spawn_args,
						spawn_env,
						SpawnFlags.SEARCH_PATH,
						null,
						out process_stdout,
						out process_stderr,
						out process_status);
	    debug ("status: %d\n", process_status);
	    debug ("STDOUT: \n");
	    debug (process_stdout);
	    debug ("STDERR: \n");
	    debug (process_stderr);

	    return process_status;
    }
}
