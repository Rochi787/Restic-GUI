namespace ResticGui {

    public enum BackendType {
        LOCAL,
        SFTP,
        S3,
        B2,
        REST_SERVER;

        public string to_string_id () {
            switch (this) {
                case LOCAL: return "local";
                case SFTP: return "sftp";
                case S3: return "s3";
                case B2: return "b2";
                case REST_SERVER: return "rest";
                default: return "local";
            }
        }

        public static BackendType from_string_id (string s) {
            switch (s) {
                case "sftp": return SFTP;
                case "s3": return S3;
                case "b2": return B2;
                case "rest": return REST_SERVER;
                default: return LOCAL;
            }
        }

        public string label () {
            switch (this) {
                case LOCAL: return "Local / Network Path";
                case SFTP: return "SFTP";
                case S3: return "S3 (AWS or compatible)";
                case B2: return "Backblaze B2";
                case REST_SERVER: return "rest-server";
                default: return "Local";
            }
        }
    }

    /**
     * Represents a configured restic repository: where it lives, and the
     * credentials/env vars needed to talk to it. Password is stored via
     * GLib's Secret Schema would be ideal, but for simplicity we keep it
     * in the per-user config file (0600 permissions) for now.
     */
    public class Repository : Object {
        public string id { get; set; }       // internal stable id (uuid-ish)
        public string name { get; set; }      // user-facing label
        public BackendType backend { get; set; default = BackendType.LOCAL; }

        // The actual restic "repository" string, e.g.
        //   /mnt/backups/myrepo
        //   sftp:user@host:/path
        //   s3:https://s3.amazonaws.com/bucket/path
        //   b2:bucketname:path
        //   rest:https://user:pass@host:8000/repo
        public string location { get; set; default = ""; }

        public string password { get; set; default = ""; }

        // Extra env vars needed for the backend, e.g. AWS_ACCESS_KEY_ID,
        // AWS_SECRET_ACCESS_KEY, B2_ACCOUNT_ID, B2_ACCOUNT_KEY.
        public HashTable<string, string> env_vars { get; set; }

        public Repository () {
            env_vars = new HashTable<string, string> (str_hash, str_equal);
        }

        public Json.Node to_json () {
            var obj = new Json.Object ();
            obj.set_string_member ("id", id);
            obj.set_string_member ("name", name);
            obj.set_string_member ("backend", backend.to_string_id ());
            obj.set_string_member ("location", location);
            obj.set_string_member ("password", password);

            var env_obj = new Json.Object ();
            env_vars.foreach ((k, v) => {
                env_obj.set_string_member (k, v);
            });
            obj.set_object_member ("env", env_obj);

            var node = new Json.Node (Json.NodeType.OBJECT);
            node.set_object (obj);
            return node;
        }

        public static Repository from_json (Json.Object obj) {
            var repo = new Repository ();
            repo.id = obj.get_string_member ("id");
            repo.name = obj.get_string_member ("name");
            repo.backend = BackendType.from_string_id (obj.get_string_member ("backend"));
            repo.location = obj.get_string_member ("location");
            repo.password = obj.get_string_member ("password");

            if (obj.has_member ("env")) {
                var env_obj = obj.get_object_member ("env");
                env_obj.foreach_member ((o, name, val) => {
                    repo.env_vars.set (name, val.get_string ());
                });
            }
            return repo;
        }
    }
}
