namespace ResticGui {

    public errordomain WinScheduleConvertError {
        UNSUPPORTED,
    }

    public errordomain WinTaskError {
        WRITE_FAILED,
        CONVERT_FAILED,
        EXEC_FAILED,
    }

    /**
     * Alternative to CronManager/SystemdManager: schedules backup jobs
     * using the Windows Task Scheduler (schtasks.exe) so restic-gui can
     * run on Windows. Each enabled job gets its own standalone
     * PowerShell script (see BackupJob.build_script_windows — no
     * dependency on the app's bash/env-file scheme) plus a scheduled
     * task under "\ResticGui\<job-id>" that runs it.
     *
     * schtasks has no clean "list everything we created" query, so we
     * keep a small manifest file of task names we've created; sync()
     * diffs against it to remove tasks for jobs that are gone/disabled.
     */
    public class WindowsTaskScheduler : Object {
        private const string TASK_FOLDER = "\\ResticGui\\";

        private string script_dir;
        private string log_dir;
        private string manifest_path;
        private SecretManager secret_manager = new SecretManager ();

        public WindowsTaskScheduler () {
            var state_dir = Path.build_filename (Environment.get_user_state_dir (), "restic-gui");
            script_dir = Path.build_filename (state_dir, "win-scripts");
            log_dir = Path.build_filename (state_dir, "logs");
            DirUtils.create_with_parents (script_dir, 0700);
            DirUtils.create_with_parents (log_dir, 0700);
            manifest_path = Path.build_filename (state_dir, "win-tasks.json");
        }

        /** Whether schtasks.exe is available on this machine (i.e. we're on Windows). */
        public static bool is_available () {
            return Environment.find_program_in_path ("schtasks.exe") != null
                || Environment.find_program_in_path ("schtasks") != null;
        }

        private string task_name (BackupJob job) {
            return @"$(TASK_FOLDER)$(job.id)";
        }

        private string script_path_for (BackupJob job) {
            return Path.build_filename (script_dir, @"$(job.id).ps1");
        }

        public string log_path_for (BackupJob job) {
            return Path.build_filename (log_dir, @"$(job.id).log");
        }

        private void write_script (BackupJob job, Repository repo, string password) throws WinTaskError {
            var path = script_path_for (job);
            try {
                FileUtils.set_contents (path, job.build_script_windows (repo, password, log_path_for (job)));
            } catch (Error e) {
                throw new WinTaskError.WRITE_FAILED (@"Failed to write script for \"$(job.name)\": $(e.message)");
            }
        }

        // --- manifest of task names we've created, since schtasks has no
        // reliable "list tasks matching this prefix" we can depend on ---

        private string[] load_manifest () {
            var result = new GenericArray<string> ();
            if (!FileUtils.test (manifest_path, FileTest.EXISTS)) return result.data;
            try {
                var parser = new Json.Parser ();
                parser.load_from_file (manifest_path);
                var root = parser.get_root ();
                if (root == null) return result.data;
                var arr = root.get_array ();
                arr.foreach_element ((a, i, val) => {
                    result.add (val.get_string ());
                });
            } catch (Error e) {
                // treat an unreadable/missing manifest as "no known tasks"
            }
            return result.data;
        }

        private void save_manifest (GenericArray<string> names) {
            var arr = new Json.Array ();
            foreach (var n in names) arr.add_string_element (n);
            var node = new Json.Node (Json.NodeType.ARRAY);
            node.set_array (arr);
            var generator = new Json.Generator ();
            generator.set_root (node);
            try {
                generator.to_file (manifest_path);
            } catch (Error e) {
                warning ("Failed to save Windows task manifest: %s", e.message);
            }
        }

        private void run_schtasks (string[] args) throws WinTaskError {
            string[] argv = new string[args.length + 1];
            argv[0] = "schtasks";
            for (int i = 0; i < args.length; i++) argv[i + 1] = args[i];

            try {
                string stdout_buf, stderr_buf;
                int status;
                Process.spawn_sync (null, argv, null, SpawnFlags.SEARCH_PATH, null,
                    out stdout_buf, out stderr_buf, out status);
                if (status != 0) {
                    throw new WinTaskError.EXEC_FAILED (
                        stderr_buf.strip () != "" ? stderr_buf.strip () : "schtasks command failed");
                }
            } catch (SpawnError e) {
                throw new WinTaskError.EXEC_FAILED (e.message);
            }
        }

        private void delete_task (string name) {
            try {
                run_schtasks ({ "/Delete", "/TN", name, "/F" });
            } catch (Error e) {
                // best effort — task may already be gone
            }
        }

        private void create_or_update_task (BackupJob job) throws WinTaskError {
            string[] schedule_args;
            try {
                schedule_args = cron_to_schtasks_args (job.cron_schedule);
            } catch (WinScheduleConvertError e) {
                throw new WinTaskError.CONVERT_FAILED (@"Job \"$(job.name)\": $(e.message)");
            }

            string action = @"powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"$(script_path_for (job))\"";

            var args = new GenericArray<string> ();
            args.add ("/Create");
            args.add ("/TN"); args.add (task_name (job));
            args.add ("/TR"); args.add (action);
            foreach (var a in schedule_args) args.add (a);
            args.add ("/RL"); args.add ("LIMITED");
            args.add ("/F"); // overwrite if it already exists

            run_schtasks (args.data);
        }

        /**
         * Regenerates all managed scripts + scheduled tasks from the
         * given jobs, and removes tasks for jobs that are gone or
         * disabled (per the manifest from the last sync).
         *
         * Each enabled job's repo password is fetched from the system
         * keyring via SecretManager rather than the in-memory
         * Repository.password field (which is empty for repos freshly
         * loaded from repos.json). Jobs whose repo has no password in
         * the keyring are skipped — no script/task is written for them
         * — and their names are returned so the caller can warn the
         * user, instead of silently writing a task with an empty
         * RESTIC_PASSWORD.
         */
        public async string[] sync (GenericArray<BackupJob> jobs, RepoStore repo_store) throws WinTaskError {
            var wanted = new GenericArray<string> ();
            var skipped = new GenericArray<string> ();

            foreach (var job in jobs) {
                if (!job.enabled) continue;
                var repo = repo_store.find_by_id (job.repo_id);
                if (repo == null) continue;

                string? password = yield secret_manager.lookup_password (repo.id);
                if (password == null) {
                    warning ("No keyring password found for repo \"%s\" — skipping scheduled task for job \"%s\"", repo.name, job.name);
                    skipped.add (job.name);
                    continue;
                }

                write_script (job, repo, password);
                create_or_update_task (job);
                wanted.add (task_name (job));
            }

            foreach (var existing in load_manifest ()) {
                bool still_wanted = false;
                foreach (var w in wanted) {
                    if (w == existing) { still_wanted = true; break; }
                }
                if (!still_wanted) delete_task (existing);
            }

            save_manifest (wanted);
            return skipped.data;
        }

        /** Removes every restic-gui-managed task. Used when switching away from Task Scheduler. */
        public void teardown_all () throws WinTaskError {
            foreach (var name in load_manifest ()) {
                delete_task (name);
            }
            save_manifest (new GenericArray<string> ());
        }

        // --- cron -> schtasks /SC ... conversion (best-effort) ---
        //
        // schtasks' CLI only understands a handful of shapes (MINUTE/
        // HOURLY/DAILY/WEEKLY/MONTHLY with one /MO step and one /ST start
        // time), nowhere near as expressive as cron. Only the patterns
        // this app's own presets produce — and similarly simple custom
        // ones — are supported; anything more exotic (multiple values,
        // mixed dom+dow, month-specific schedules) is rejected with a
        // clear error rather than silently mistranslated. If you need
        // something fancier, edit the task in Task Scheduler by hand
        // after the first sync creates it.

        private static string[] DOW_NAMES = { "SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT" };

        public static string[] cron_to_schtasks_args (string cron_expr) throws WinScheduleConvertError {
            var raw = cron_expr.strip ().split_set (" \t");
            var cleaned = new GenericArray<string> ();
            foreach (var f in raw) if (f != "") cleaned.add (f);
            if (cleaned.length != 5) {
                throw new WinScheduleConvertError.UNSUPPORTED (
                    @"expected a 5-field cron expression (minute hour dom month dow), got '$cron_expr'");
            }

            string minute = cleaned[0];
            string hour = cleaned[1];
            string dom = cleaned[2];
            string month = cleaned[3];
            string dow = cleaned[4];

            if (month != "*") {
                throw new WinScheduleConvertError.UNSUPPORTED (
                    "month-specific schedules aren't supported for Windows Task Scheduler conversion");
            }

            // "Every N hours" — the one case where minute/hour aren't both fixed.
            if (minute == "0" && hour.has_prefix ("*/") && dom == "*" && dow == "*") {
                string n = hour.substring (2);
                return { "/SC", "HOURLY", "/MO", n, "/ST", "00:00" };
            }

            if (minute.contains ("*") || minute.contains ("/") || minute.contains (",")) {
                throw new WinScheduleConvertError.UNSUPPORTED (
                    "only a fixed minute value is supported (besides the 'every N hours' pattern)");
            }
            if (hour.contains ("*") || hour.contains ("/") || hour.contains (",")) {
                throw new WinScheduleConvertError.UNSUPPORTED (
                    "only a fixed hour value is supported (besides the 'every N hours' pattern)");
            }
            int min_val = int.parse (minute);
            int hour_val = int.parse (hour);
            string start_time = "%02d:%02d".printf (hour_val, min_val);

            // Daily: dom=*, dow=*
            if (dom == "*" && dow == "*") {
                return { "/SC", "DAILY", "/ST", start_time };
            }

            // Weekly: dom=*, dow=fixed value or comma list (no ranges/steps)
            if (dom == "*" && dow != "*") {
                if (dow.contains ("-") || dow.contains ("/")) {
                    throw new WinScheduleConvertError.UNSUPPORTED (
                        "day-of-week ranges/steps aren't supported for Windows Task Scheduler conversion — use a comma list of fixed days");
                }
                var parts = dow.split (",");
                var names = new GenericArray<string> ();
                foreach (var p in parts) {
                    int n = int.parse (p);
                    names.add (DOW_NAMES[n % 7]);
                }
                string d_list = string.joinv (",", names.data);
                return { "/SC", "WEEKLY", "/D", d_list, "/ST", start_time };
            }

            // Monthly: dom=fixed value, dow=*
            if (dom != "*" && dow == "*") {
                if (dom.contains ("-") || dom.contains ("/") || dom.contains (",")) {
                    throw new WinScheduleConvertError.UNSUPPORTED (
                        "only a single fixed day-of-month is supported for Windows Task Scheduler conversion");
                }
                int d = int.parse (dom);
                return { "/SC", "MONTHLY", "/D", d.to_string (), "/ST", start_time };
            }

            throw new WinScheduleConvertError.UNSUPPORTED (
                "this cron pattern doesn't map onto schtasks' DAILY/WEEKLY/MONTHLY/HOURLY shapes — edit the task by hand in Task Scheduler instead");
        }
    }
}
