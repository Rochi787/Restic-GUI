namespace ResticGui {

    public enum SchedulerBackend {
        CRON,
        SYSTEMD,
        WINDOWS_TASK;

        public string to_string_id () {
            switch (this) {
                case SYSTEMD: return "systemd";
                case WINDOWS_TASK: return "wintask";
                default: return "cron";
            }
        }

        public static SchedulerBackend from_string_id (string s) {
            switch (s) {
                case "systemd": return SYSTEMD;
                case "wintask": return WINDOWS_TASK;
                default: return CRON;
            }
        }

        public string label () {
            switch (this) {
                case SYSTEMD: return "systemd timers";
                case WINDOWS_TASK: return "Windows Task Scheduler";
                default: return "cron";
            }
        }
    }

    /**
     * Tiny persisted preference: which scheduler backend the Jobs page's
     * "Sync" button targets. Kept separate from JobStore since it's a
     * global app setting, not per-job data.
     */
    public class SchedulerPrefs : Object {
        private string config_path;
        public SchedulerBackend backend { get; set; default = SchedulerBackend.CRON; }

        public SchedulerPrefs () {
            var config_dir = Path.build_filename (Environment.get_user_config_dir (), "restic-gui");
            DirUtils.create_with_parents (config_dir, 0700);
            config_path = Path.build_filename (config_dir, "scheduler.json");
            load ();
        }

        private void load () {
            if (!FileUtils.test (config_path, FileTest.EXISTS)) return;
            try {
                var parser = new Json.Parser ();
                parser.load_from_file (config_path);
                var root = parser.get_root ();
                if (root == null) return;
                var obj = root.get_object ();
                if (obj.has_member ("backend")) {
                    backend = SchedulerBackend.from_string_id (obj.get_string_member ("backend"));
                }
            } catch (Error e) {
                warning ("Failed to load scheduler prefs: %s", e.message);
            }
        }

        public void save () {
            var obj = new Json.Object ();
            obj.set_string_member ("backend", backend.to_string_id ());
            var node = new Json.Node (Json.NodeType.OBJECT);
            node.set_object (obj);

            var generator = new Json.Generator ();
            generator.set_root (node);
            generator.pretty = true;
            try {
                generator.to_file (config_path);
            } catch (Error e) {
                warning ("Failed to save scheduler prefs: %s", e.message);
            }
        }
    }
}
