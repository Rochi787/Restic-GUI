namespace ResticGui {

    /**
     * Loads/saves the list of configured Repository objects to a JSON
     * file in the user's config dir. File permissions are tightened to
     * 0600 since this contains repo passwords / cloud credentials.
     */
    public class RepoStore : Object {
        private string config_path;
        public GenericArray<Repository> repos { get; private set; }

        public RepoStore () {
            var config_dir = Path.build_filename (Environment.get_user_config_dir (), "restic-gui");
            DirUtils.create_with_parents (config_dir, 0700);
            config_path = Path.build_filename (config_dir, "repos.json");
            repos = new GenericArray<Repository> ();
            load ();
        }

        public void load () {
            repos = new GenericArray<Repository> ();
            if (!FileUtils.test (config_path, FileTest.EXISTS)) return;

            try {
                var parser = new Json.Parser ();
                parser.load_from_file (config_path);
                var root = parser.get_root ();
                if (root == null) return;

                var arr = root.get_array ();
                arr.foreach_element ((a, i, val) => {
                    repos.add (Repository.from_json (val.get_object ()));
                });
            } catch (Error e) {
                warning ("Failed to load repo store: %s", e.message);
            }
        }

        public void save () {
            var arr = new Json.Array ();
            foreach (var r in repos) {
                arr.add_element (r.to_json ());
            }
            var root = new Json.Node (Json.NodeType.ARRAY);
            root.set_array (arr);

            var generator = new Json.Generator ();
            generator.set_root (root);
            generator.pretty = true;

            try {
                generator.to_file (config_path);
                // Tighten permissions since this holds credentials.
                FileUtils.chmod (config_path, 0600);
            } catch (Error e) {
                warning ("Failed to save repo store: %s", e.message);
            }
        }

        public void add_repo (Repository repo) {
            repos.add (repo);
            save ();
        }

        public void remove_repo (Repository repo) {
            for (int i = 0; i < repos.length; i++) {
                if (repos[i].id == repo.id) {
                    repos.remove_index (i);
                    break;
                }
            }
            save ();
        }

        public Repository? find_by_id (string id) {
            foreach (var r in repos) {
                if (r.id == id) return r;
            }
            return null;
        }
    }
}
