namespace ResticGui {

    public errordomain ResticError {
        EXEC_FAILED,
        PARSE_FAILED,
        NOT_FOUND,
    }

    /**
     * Thin async wrapper around the `restic` binary. Every call sets
     * RESTIC_REPOSITORY / RESTIC_PASSWORD / backend-specific env vars
     * from the Repository object, then shells out and captures stdout.
     */
    public class ResticRunner : Object {

        private SecretManager secret_manager = new SecretManager ();

        public static bool is_installed () {
            return Environment.find_program_in_path ("restic") != null;
        }

        private async string[] build_envp (Repository repo) throws Error {
            string[] envp = Environ.get ();
            envp = Environ.set_variable (envp, "RESTIC_REPOSITORY", repo.location, true);

            string? password = yield secret_manager.lookup_password (repo.id);
            if (password == null) {
                throw new ResticError.EXEC_FAILED (
                    @"No password found in the system keyring for repository \"$(repo.name)\" — open Edit Repository and re-enter/save it.");
            }
            envp = Environ.set_variable (envp, "RESTIC_PASSWORD", password, true);

            repo.env_vars.foreach ((k, v) => {
                envp = Environ.set_variable (envp, k, v, true);
            });
            return envp;
        }

        private async string run_raw (Repository repo, string[] args) throws Error {
            if (!is_installed ()) {
                throw new ResticError.NOT_FOUND ("restic binary not found in PATH");
            }

            string[] argv = new string[args.length + 1];
            argv[0] = "restic";
            for (int i = 0; i < args.length; i++) argv[i + 1] = args[i];

            var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE);
            launcher.set_environ (yield build_envp (repo));

            Subprocess proc;
            try {
                proc = launcher.spawnv (argv);
            } catch (Error e) {
                throw new ResticError.EXEC_FAILED (@"Failed to launch restic: $(e.message)");
            }

            Bytes stdout_buf, stderr_buf;
            yield proc.communicate_async (null, null, out stdout_buf, out stderr_buf);

            if (!proc.get_successful ()) {
                string err_text = (string) stderr_buf.get_data ();
                throw new ResticError.EXEC_FAILED (err_text.strip ());
            }

            return (string) stdout_buf.get_data ();
        }

        /** Initialize a brand-new repository. */
        public async void init_repo (Repository repo) throws Error {
            yield run_raw (repo, { "init" });
        }

        /** Check whether a repository is reachable/initialized. */
        public async bool check_repo (Repository repo) {
            try {
                yield run_raw (repo, { "cat", "config" });
                return true;
            } catch (Error e) {
                return false;
            }
        }

        /** List all snapshots in a repo. */
        public async GenericArray<Snapshot> list_snapshots (Repository repo) throws Error {
            var raw = yield run_raw (repo, { "snapshots", "--json" });
            var result = new GenericArray<Snapshot> ();

            var parser = new Json.Parser ();
            parser.load_from_data (raw, -1);
            var root = parser.get_root ();
            if (root == null) return result;

            var arr = root.get_array ();
            arr.foreach_element ((a, i, val) => {
                result.add (Snapshot.from_json (val.get_object ()));
            });
            return result;
        }

        /** Run a manual backup of the given paths right now. */
        public async string backup_now (Repository repo, GenericArray<string> paths, GenericArray<string>? excludes = null) throws Error {
            var args = new GenericArray<string> ();
            args.add ("backup");
            foreach (var p in paths) args.add (p);
            if (excludes != null) {
                foreach (var e in excludes) {
                    args.add ("--exclude");
                    args.add (e);
                }
            }
            return yield run_raw (repo, args.data);
        }

        /** Restore a snapshot to a target directory. */
        public async string restore_snapshot (Repository repo, string snapshot_id, string target_dir) throws Error {
            return yield run_raw (repo, { "restore", snapshot_id, "--target", target_dir });
        }

        /** Forget + prune according to retention flags. */
        public async string forget_prune (Repository repo, BackupJob job) throws Error {
            var args = new GenericArray<string> ();
            args.add ("forget");
            if (job.prune_after_forget) args.add ("--prune");
            if (job.keep_last >= 0) { args.add ("--keep-last"); args.add (job.keep_last.to_string ()); }
            if (job.keep_daily >= 0) { args.add ("--keep-daily"); args.add (job.keep_daily.to_string ()); }
            if (job.keep_weekly >= 0) { args.add ("--keep-weekly"); args.add (job.keep_weekly.to_string ()); }
            if (job.keep_monthly >= 0) { args.add ("--keep-monthly"); args.add (job.keep_monthly.to_string ()); }
            if (job.keep_yearly >= 0) { args.add ("--keep-yearly"); args.add (job.keep_yearly.to_string ()); }
            return yield run_raw (repo, args.data);
        }

        /** Forget (and optionally prune) one specific snapshot by id. */
        public async string forget_snapshot (Repository repo, string snapshot_id, bool prune = true) throws Error {
            var args = new GenericArray<string> ();
            args.add ("forget");
            args.add (snapshot_id);
            if (prune) args.add ("--prune");
            return yield run_raw (repo, args.data);
        }

        /** List files within a snapshot (for browsing before restore). */
        public async string list_snapshot_files (Repository repo, string snapshot_id, string path = "/") throws Error {
            return yield run_raw (repo, { "ls", snapshot_id, path });
        }
    }
}
