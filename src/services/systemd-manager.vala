namespace ResticGui {

    public errordomain SystemdConvertError {
        UNSUPPORTED,
    }

    public errordomain SystemdError {
        WRITE_FAILED,
        CONVERT_FAILED,
        EXEC_FAILED,
    }

    /**
     * Alternative to CronManager: schedules backup jobs as per-user
     * systemd timers instead of crontab entries. Each enabled job gets
     * its own standalone script (see BackupJob.build_script — no
     * dependency on the app's env-file scheme), plus a matching
     * .service/.timer pair under ~/.config/systemd/user/. Units are
     * named restic-gui-<job-id>.{service,timer}.
     *
     * Every sync() regenerates everything from scratch, removes units
     * for jobs that are gone or disabled, reloads the user daemon, and
     * enables+starts the timers that should be running.
     */
    public class SystemdManager : Object {
        private const string UNIT_PREFIX = "restic-gui-";

        private string unit_dir;
        private string script_dir;
        private string log_dir;

        public SystemdManager () {
            unit_dir = Path.build_filename (Environment.get_user_config_dir (), "systemd", "user");
            var state_dir = Path.build_filename (Environment.get_user_state_dir (), "restic-gui");
            script_dir = Path.build_filename (state_dir, "scripts");
            log_dir = Path.build_filename (state_dir, "logs");
            DirUtils.create_with_parents (unit_dir, 0700);
            DirUtils.create_with_parents (script_dir, 0700);
            DirUtils.create_with_parents (log_dir, 0700);
        }

        private string unit_name (BackupJob job) {
            return @"$(UNIT_PREFIX)$(job.id)";
        }

        private string script_path_for (BackupJob job) {
            return Path.build_filename (script_dir, @"$(job.id).sh");
        }

        private string service_path_for (BackupJob job) {
            return Path.build_filename (unit_dir, @"$(unit_name (job)).service");
        }

        private string timer_path_for (BackupJob job) {
            return Path.build_filename (unit_dir, @"$(unit_name (job)).timer");
        }

        public string log_path_for (BackupJob job) {
            return Path.build_filename (log_dir, @"$(job.id).log");
        }

        private void write_script (BackupJob job, Repository repo) throws SystemdError {
            var path = script_path_for (job);
            try {
                FileUtils.set_contents (path, job.build_script (repo));
                FileUtils.chmod (path, 0700);
            } catch (Error e) {
                throw new SystemdError.WRITE_FAILED (@"Failed to write script for \"$(job.name)\": $(e.message)");
            }
        }

        private void write_service_unit (BackupJob job) throws SystemdError {
            var sb = new StringBuilder ();
            sb.append ("[Unit]\n");
            sb.append_printf ("Description=restic-gui backup job: %s\n", job.name);
            sb.append ("\n[Service]\n");
            sb.append ("Type=oneshot\n");
            sb.append_printf ("ExecStart=%s\n", script_path_for (job));
            sb.append_printf ("StandardOutput=append:%s\n", log_path_for (job));
            sb.append_printf ("StandardError=append:%s\n", log_path_for (job));
            sb.append ("\n# Managed by restic-gui — edits here are overwritten on next sync.\n");

            try {
                FileUtils.set_contents (service_path_for (job), sb.str);
            } catch (Error e) {
                throw new SystemdError.WRITE_FAILED (@"Failed to write service unit for \"$(job.name)\": $(e.message)");
            }
        }

        private void write_timer_unit (BackupJob job) throws SystemdError {
            string on_calendar;
            try {
                on_calendar = cron_to_oncalendar (job.cron_schedule);
            } catch (SystemdConvertError e) {
                throw new SystemdError.CONVERT_FAILED (@"Job \"$(job.name)\": $(e.message)");
            }

            var sb = new StringBuilder ();
            sb.append ("[Unit]\n");
            sb.append_printf ("Description=Timer for restic-gui backup job: %s\n", job.name);
            sb.append ("\n[Timer]\n");
            sb.append_printf ("OnCalendar=%s\n", on_calendar);
            sb.append ("Persistent=true\n");
            sb.append ("\n[Install]\n");
            sb.append ("WantedBy=timers.target\n");
            sb.append ("\n# Managed by restic-gui — edits here are overwritten on next sync.\n");
            sb.append_printf ("# Converted from cron expression \"%s\" — verify with:\n", job.cron_schedule);
            sb.append_printf ("#   systemd-analyze calendar '%s'\n", on_calendar);

            try {
                FileUtils.set_contents (timer_path_for (job), sb.str);
            } catch (Error e) {
                throw new SystemdError.WRITE_FAILED (@"Failed to write timer unit for \"$(job.name)\": $(e.message)");
            }
        }

        private void run_systemctl (string[] args) throws SystemdError {
            var sb = new StringBuilder ("systemctl --user");
            foreach (var a in args) {
                sb.append (" ");
                sb.append (a);
            }
            try {
                string stdout_buf, stderr_buf;
                int status;
                Process.spawn_command_line_sync (sb.str, out stdout_buf, out stderr_buf, out status);
                if (status != 0) {
                    throw new SystemdError.EXEC_FAILED (stderr_buf.strip () != "" ? stderr_buf.strip () : @"systemctl $(sb.str) failed");
                }
            } catch (SpawnError e) {
                throw new SystemdError.EXEC_FAILED (e.message);
            }
        }

        private string[] existing_managed_units () {
            var result = new GenericArray<string> ();
            Dir dir;
            try {
                dir = Dir.open (unit_dir);
            } catch (Error e) {
                return result.data;
            }
            string? name;
            while ((name = dir.read_name ()) != null) {
                if (name.has_prefix (UNIT_PREFIX) && (name.has_suffix (".service") || name.has_suffix (".timer"))) {
                    result.add (name);
                }
            }
            return result.data;
        }

        /**
         * Regenerates all managed service/timer units + scripts from the
         * given jobs, removes units for jobs that are gone or disabled,
         * reloads the systemd user daemon, and enables+starts timers for
         * every enabled job.
         */
        public void sync (GenericArray<BackupJob> jobs, RepoStore repo_store) throws SystemdError {
            var wanted_units = new GenericArray<string> ();

            foreach (var job in jobs) {
                if (!job.enabled) continue;
                var repo = repo_store.find_by_id (job.repo_id);
                if (repo == null) continue;

                write_script (job, repo);
                write_service_unit (job);
                write_timer_unit (job);
                wanted_units.add (@"$(unit_name (job)).service");
                wanted_units.add (@"$(unit_name (job)).timer");
            }

            // Remove stale units (disabled/deleted jobs) before reload.
            foreach (var existing in existing_managed_units ()) {
                bool still_wanted = false;
                foreach (var w in wanted_units) {
                    if (w == existing) { still_wanted = true; break; }
                }
                if (!still_wanted) {
                    if (existing.has_suffix (".timer")) {
                        try { run_systemctl ({ "disable", "--now", existing }); } catch (Error e) { /* best effort */ }
                    }
                    FileUtils.unlink (Path.build_filename (unit_dir, existing));
                }
            }

            run_systemctl ({ "daemon-reload" });

            foreach (var job in jobs) {
                if (!job.enabled) continue;
                var repo = repo_store.find_by_id (job.repo_id);
                if (repo == null) continue;
                run_systemctl ({ "enable", "--now", @"$(unit_name (job)).timer" });
            }
        }

        /** Removes every restic-gui-managed unit and disables its timer. Used when switching away from systemd. */
        public void teardown_all () throws SystemdError {
            foreach (var existing in existing_managed_units ()) {
                if (existing.has_suffix (".timer")) {
                    try { run_systemctl ({ "disable", "--now", existing }); } catch (Error e) { /* best effort */ }
                }
                FileUtils.unlink (Path.build_filename (unit_dir, existing));
            }
            run_systemctl ({ "daemon-reload" });
        }

        // --- cron -> systemd OnCalendar conversion (best-effort) ---
        //
        // minute/hour/day-of-month/month fields in cron use almost the
        // same syntax systemd calendar specs do (*, comma lists, a-b
        // ranges, */n steps), so they're passed through more or less
        // verbatim. Day-of-week is the odd one out: cron uses 0-6
        // (0=Sunday) but systemd wants names like Mon, Tue, Sun-Thu.
        // Anything beyond that (step values in day-of-week, non-5-field
        // expressions) is rejected rather than silently mistranslated.

        private static string cron_field_passthrough (string field) {
            if (field.has_prefix ("*/")) {
                return "0/" + field.substring (2);
            }
            return field;
        }

        private static string? cron_dow_to_systemd (string field) throws SystemdConvertError {
            if (field == "*") return null;
            string[] names = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" };
            var parts = field.split (",");
            var out_parts = new GenericArray<string> ();
            foreach (var part in parts) {
                if (part.contains ("-")) {
                    var bounds = part.split ("-");
                    if (bounds.length != 2) {
                        throw new SystemdConvertError.UNSUPPORTED (@"can't translate day-of-week range '$part'");
                    }
                    int a = int.parse (bounds[0]);
                    int b = int.parse (bounds[1]);
                    out_parts.add (@"$(names[a % 7])-$(names[b % 7])");
                } else if (part.contains ("/")) {
                    throw new SystemdConvertError.UNSUPPORTED ("step values in day-of-week aren't supported for systemd conversion — use a custom cron entry per weekday, or edit the .timer file by hand");
                } else {
                    int n = int.parse (part);
                    out_parts.add (names[n % 7]);
                }
            }
            return string.joinv (",", out_parts.data);
        }

        /** Converts a 5-field cron expression to a systemd OnCalendar= value. */
        public static string cron_to_oncalendar (string cron_expr) throws SystemdConvertError {
            var raw = cron_expr.strip ().split_set (" \t");
            var cleaned = new GenericArray<string> ();
            foreach (var f in raw) if (f != "") cleaned.add (f);
            if (cleaned.length != 5) {
                throw new SystemdConvertError.UNSUPPORTED (
                    @"expected a 5-field cron expression (minute hour dom month dow), got '$cron_expr'");
            }

            string minute = cleaned[0];
            string hour = cleaned[1];
            string dom = cleaned[2];
            string month = cleaned[3];
            string dow = cleaned[4];

            string? dow_part = cron_dow_to_systemd (dow);
            string dom_part = cron_field_passthrough (dom);
            string month_part = cron_field_passthrough (month);
            string hour_part = cron_field_passthrough (hour);
            string minute_part = cron_field_passthrough (minute);

            var sb = new StringBuilder ();
            if (dow_part != null) {
                sb.append (dow_part);
                sb.append (" ");
            }
            sb.append_printf ("*-%s-%s %s:%s:00", month_part, dom_part, hour_part, minute_part);
            return sb.str;
        }
    }
}
