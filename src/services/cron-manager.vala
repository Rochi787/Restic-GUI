namespace ResticGui {

    public errordomain CronError {
        READ_FAILED,
        WRITE_FAILED,
    }

    /**
     * Manages cron entries for restic-gui without touching any of the
     * user's other crontab lines. All managed lines live between
     * BEGIN/END marker comments; on save we read the existing crontab,
     * strip out anything between the markers, and splice in the fresh
     * set of job lines.
     */
    public class CronManager : Object {
        private const string BEGIN_MARKER = "# >>> restic-gui managed jobs (do not edit by hand) >>>";
        private const string END_MARKER = "# <<< restic-gui managed jobs <<<";

        private string env_dir;
        private string log_dir;

        public CronManager () {
            var state_dir = Path.build_filename (Environment.get_user_state_dir (), "restic-gui");
            env_dir = Path.build_filename (state_dir, "env");
            log_dir = Path.build_filename (state_dir, "logs");
            DirUtils.create_with_parents (env_dir, 0700);
            DirUtils.create_with_parents (log_dir, 0700);
        }

        private string env_file_for (Repository repo) {
            return Path.build_filename (env_dir, @"$(repo.id).env");
        }

        private string log_file_for (BackupJob job) {
            return Path.build_filename (log_dir, @"$(job.id).log");
        }

        /** Writes the per-repo env file (RESTIC_REPOSITORY, password, backend creds). */
        private void write_env_file (Repository repo) {
            var sb = new StringBuilder ();
            sb.append_printf ("RESTIC_REPOSITORY=%s\n", shell_escape (repo.location));
            sb.append_printf ("RESTIC_PASSWORD=%s\n", shell_escape (repo.password));
            repo.env_vars.foreach ((k, v) => {
                sb.append_printf ("%s=%s\n", k, shell_escape (v));
            });

            var path = env_file_for (repo);
            try {
                FileUtils.set_contents (path, sb.str);
                FileUtils.chmod (path, 0600);
            } catch (Error e) {
                warning ("Failed to write env file for repo %s: %s", repo.name, e.message);
            }
        }

        private static string shell_escape (string s) {
            return s; // values are written unquoted into a sourced env file; assume no embedded newlines
        }

        private string read_current_crontab () {
            try {
                string stdout_buf, stderr_buf;
                int status;
                Process.spawn_command_line_sync ("crontab -l", out stdout_buf, out stderr_buf, out status);
                return stdout_buf;
            } catch (Error e) {
                return "";
            }
        }

        private void write_crontab (string content) throws CronError {
            try {
                var launcher = new SubprocessLauncher (SubprocessFlags.STDIN_PIPE);
                var proc = launcher.spawnv ({ "crontab", "-" });
                var stdin = proc.get_stdin_pipe ();
                stdin.write_all (content.data, null);
                stdin.close (null);
                proc.wait ();
                if (!proc.get_successful ()) {
                    throw new CronError.WRITE_FAILED ("crontab - exited with an error");
                }
            } catch (Error e) {
                throw new CronError.WRITE_FAILED (e.message);
            }
        }

        /**
         * Regenerates the managed block from the given jobs/repos and
         * installs it into the user's crontab, preserving everything else.
         */
        public void sync (GenericArray<BackupJob> jobs, RepoStore repo_store) throws CronError {
            var existing = read_current_crontab ();

            // Strip out any existing managed block.
            var lines = existing.split ("\n");
            var kept = new GenericArray<string> ();
            bool inside_block = false;
            foreach (var line in lines) {
                if (line.strip () == BEGIN_MARKER) { inside_block = true; continue; }
                if (line.strip () == END_MARKER) { inside_block = false; continue; }
                if (!inside_block) kept.add (line);
            }

            var sb = new StringBuilder ();
            foreach (var line in kept) {
                if (line.strip () == "") continue;
                sb.append (line);
                sb.append ("\n");
            }

            sb.append (BEGIN_MARKER);
            sb.append ("\n");

            foreach (var job in jobs) {
                if (!job.enabled) continue;
                var repo = repo_store.find_by_id (job.repo_id);
                if (repo == null) continue;

                write_env_file (repo);
                var cmd = job.build_command (env_file_for (repo), log_file_for (job));
                sb.append_printf ("%s %s\n", job.cron_schedule, cmd);
            }

            sb.append (END_MARKER);
            sb.append ("\n");

            write_crontab (sb.str);
        }

        public string log_path_for (BackupJob job) {
            return log_file_for (job);
        }
    }
}
