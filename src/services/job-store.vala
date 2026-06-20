namespace ResticGui {

    public class JobStore : Object {
        private string config_path;
        public GenericArray<BackupJob> jobs { get; private set; }

        public JobStore () {
            var config_dir = Path.build_filename (Environment.get_user_config_dir (), "restic-gui");
            DirUtils.create_with_parents (config_dir, 0700);
            config_path = Path.build_filename (config_dir, "jobs.json");
            jobs = new GenericArray<BackupJob> ();
            load ();
        }

        public void load () {
            jobs = new GenericArray<BackupJob> ();
            if (!FileUtils.test (config_path, FileTest.EXISTS)) return;

            try {
                var parser = new Json.Parser ();
                parser.load_from_file (config_path);
                var root = parser.get_root ();
                if (root == null) return;

                var arr = root.get_array ();
                arr.foreach_element ((a, i, val) => {
                    jobs.add (BackupJob.from_json (val.get_object ()));
                });
            } catch (Error e) {
                warning ("Failed to load job store: %s", e.message);
            }
        }

        public void save () {
            var arr = new Json.Array ();
            foreach (var j in jobs) {
                arr.add_element (j.to_json ());
            }
            var root = new Json.Node (Json.NodeType.ARRAY);
            root.set_array (arr);

            var generator = new Json.Generator ();
            generator.set_root (root);
            generator.pretty = true;

            try {
                generator.to_file (config_path);
            } catch (Error e) {
                warning ("Failed to save job store: %s", e.message);
            }
        }

        public void add_job (BackupJob job) {
            jobs.add (job);
            save ();
        }

        public void remove_job (BackupJob job) {
            for (int i = 0; i < jobs.length; i++) {
                if (jobs[i].id == job.id) {
                    jobs.remove_index (i);
                    break;
                }
            }
            save ();
        }
    }
}
