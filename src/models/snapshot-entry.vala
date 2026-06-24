namespace ResticGui {

    /**
     * One entry from `restic ls <snapshot> --json`, used to build an
     * in-memory file/directory tree for browsing a snapshot's contents
     * (see SnapshotBrowserDialog).
     *
     * Restic's `ls --json` output is newline-delimited JSON: a single
     * "snapshot" header line, followed by one line per file/dir entry
     * with "struct_type":"node". We only keep the node lines and ignore
     * anything we don't recognize, rather than failing the whole listing
     * over one unexpected line (restic's exact json shape has shifted
     * slightly across versions).
     */
    public class SnapshotEntry : Object {
        public string path { get; set; default = ""; }       // full path within the snapshot, e.g. "/home/user/file.txt"
        public string name { get; set; default = ""; }        // basename
        public string entry_type { get; set; default = "file"; } // "file", "dir", "symlink", etc.
        public int64 size { get; set; default = 0; }
        public string mtime { get; set; default = ""; }

        /** Parent directory path, e.g. "/home/user/file.txt" -> "/home/user". */
        public string parent_path () {
            if (path == "/" || path == "") return "/";
            int idx = path.last_index_of ("/");
            if (idx <= 0) return "/";
            return path.substring (0, idx);
        }

        public static SnapshotEntry? from_json_line (string line) {
            string trimmed = line.strip ();
            if (trimmed == "") return null;

            try {
                var parser = new Json.Parser ();
                parser.load_from_data (trimmed, -1);
                var root = parser.get_root ();
                if (root == null) return null;
                var obj = root.get_object ();
                if (obj == null) return null;

                // Skip the leading "snapshot" summary line and anything
                // that isn't a file-tree node entry.
                string struct_type = obj.has_member ("struct_type") ? obj.get_string_member ("struct_type") : "";
                if (struct_type != "node") return null;

                var entry = new SnapshotEntry ();
                entry.path = obj.has_member ("path") ? obj.get_string_member ("path") : "";
                entry.entry_type = obj.has_member ("type") ? obj.get_string_member ("type") : "file";
                entry.size = obj.has_member ("size") ? obj.get_int_member ("size") : 0;
                entry.mtime = obj.has_member ("mtime") ? obj.get_string_member ("mtime") : "";

                if (entry.path == "") return null;

                int idx = entry.path.last_index_of ("/");
                entry.name = idx >= 0 ? entry.path.substring (idx + 1) : entry.path;
                if (entry.name == "") entry.name = entry.path;

                return entry;
            } catch (Error e) {
                // Tolerate the odd malformed/empty line rather than
                // failing the whole listing.
                return null;
            }
        }
    }
}
