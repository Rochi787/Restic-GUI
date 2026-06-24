namespace ResticGui {

    public class Snapshot : Object {
        public string short_id { get; set; }
        public string snapshot_id { get; set; }
        public string hostname { get; set; }
        public string time { get; set; }
        public GenericArray<string> paths { get; set; }

        // Comma-joined tags, kept for the existing row subtitle display.
        public string tags { get; set; default = ""; }

        // Same tags as a real array, used for exact-match filtering
        // (Snapshots page: filter by tag) without re-parsing `tags`.
        public GenericArray<string> tag_list { get; set; }

        public Snapshot () {
            paths = new GenericArray<string> ();
            tag_list = new GenericArray<string> ();
        }

        public static Snapshot from_json (Json.Object obj) {
            var s = new Snapshot ();
            s.snapshot_id = obj.has_member ("id") ? obj.get_string_member ("id") : "";
            s.short_id = s.snapshot_id.length >= 8 ? s.snapshot_id.substring (0, 8) : s.snapshot_id;
            s.hostname = obj.has_member ("hostname") ? obj.get_string_member ("hostname") : "";
            s.time = obj.has_member ("time") ? obj.get_string_member ("time") : "";

            if (obj.has_member ("paths")) {
                var arr = obj.get_array_member ("paths");
                arr.foreach_element ((a, i, val) => {
                    s.paths.add (val.get_string ());
                });
            }

            if (obj.has_member ("tags")) {
                var arr = obj.get_array_member ("tags");
                arr.foreach_element ((a, i, val) => {
                    s.tag_list.add (val.get_string ());
                });
                var sb = new StringBuilder ();
                for (int i = 0; i < s.tag_list.length; i++) {
                    if (i > 0) sb.append (", ");
                    sb.append (s.tag_list[i]);
                }
                s.tags = sb.str;
            }

            return s;
        }
    }
}
