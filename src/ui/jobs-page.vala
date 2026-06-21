namespace ResticGui {

    public class JobsPage : Gtk.Box {

        private weak Application app_ref;
        private weak MainWindow window_ref;
        private Adw.PreferencesGroup group;
        private Adw.Clamp clamp;
        private Adw.ToolbarView toolbar_view;
        private Gtk.DropDown scheduler_dropdown;
        private GenericArray<SchedulerBackend> available_backends;
        private bool suppress_dropdown_signal = false;

        public JobsPage (Application app, MainWindow window) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            app_ref = app;
            window_ref = window;
            build_ui ();
            refresh ();
        }

        private void build_ui () {
            toolbar_view = new Adw.ToolbarView ();
            this.vexpand = true;
            this.hexpand = true;
            this.append (toolbar_view);
            toolbar_view.vexpand = true;
            toolbar_view.hexpand = true;

            var header = new Adw.HeaderBar ();

            var add_btn = new Gtk.Button.from_icon_name ("list-add-symbolic");
            add_btn.tooltip_text = "Add Backup Job";
            add_btn.clicked.connect (() => on_add_clicked ());
            header.pack_start (add_btn);

            build_scheduler_dropdown ();
            header.pack_start (scheduler_dropdown);

            var sync_btn = new Gtk.Button.from_icon_name ("view-refresh-symbolic");
            sync_btn.tooltip_text = "Sync to scheduler";
            sync_btn.clicked.connect (() => on_sync_clicked ());
            header.pack_end (sync_btn);

            toolbar_view.add_top_bar (header);

            var scroller = new Gtk.ScrolledWindow ();
            scroller.vexpand = true;

            clamp = new Adw.Clamp ();
            clamp.maximum_size = 700;
            clamp.margin_top = 24;
            clamp.margin_bottom = 24;
            clamp.margin_start = 12;
            clamp.margin_end = 12;

            group = new Adw.PreferencesGroup ();
            group.title = "Backup Jobs";
            group.description = "Each enabled job is written into your crontab, systemd user timers, or Windows Task Scheduler, depending on the scheduler picked above. Use the save icon on a job to export it as a standalone script instead.";

            clamp.child = group;
            scroller.child = clamp;
            toolbar_view.content = scroller;
        }

        /**
         * Builds the scheduler dropdown from whichever backends are
         * actually usable on this machine (detected at runtime rather
         * than compile time, so the same binary behaves correctly on
         * Linux, macOS, and Windows).
         */
        private void build_scheduler_dropdown () {
            available_backends = new GenericArray<SchedulerBackend> ();
            var labels = new GenericArray<string> ();

            if (Environment.find_program_in_path ("crontab") != null) {
                available_backends.add (SchedulerBackend.CRON);
                labels.add (SchedulerBackend.CRON.label ());
            }
            if (Environment.find_program_in_path ("systemctl") != null) {
                available_backends.add (SchedulerBackend.SYSTEMD);
                labels.add (SchedulerBackend.SYSTEMD.label ());
            }
            if (WindowsTaskScheduler.is_available ()) {
                available_backends.add (SchedulerBackend.WINDOWS_TASK);
                labels.add (SchedulerBackend.WINDOWS_TASK.label ());
            }
            if (available_backends.length == 0) {
                // Shouldn't happen on a supported platform, but keep the
                // dropdown non-empty rather than crashing.
                available_backends.add (SchedulerBackend.CRON);
                labels.add (SchedulerBackend.CRON.label ());
            }

            // Copy into a plain, length-tracked string[] before handing it
            // to from_strings(). Gtk.DropDown.from_strings() expects a
            // null-terminated array; passing GenericArray<string>.data
            // directly doesn't reliably get null-terminated by Vala (a
            // property read doesn't carry length info the way a real
            // array variable does), which is what was showing up as
            // garbage text in the dropdown entries.
            string[] label_arr = new string[labels.length];
            for (int i = 0; i < labels.length; i++) {
                label_arr[i] = labels[i];
            }

            scheduler_dropdown = new Gtk.DropDown.from_strings (label_arr);
            scheduler_dropdown.tooltip_text = "Scheduler backend used by \"Sync\"";

            suppress_dropdown_signal = true;
            uint initial = 0;
            for (uint i = 0; i < available_backends.length; i++) {
                if (available_backends[i] == app_ref.scheduler_prefs.backend) { initial = i; break; }
            }
            scheduler_dropdown.selected = initial;
            // Persist whatever we actually landed on, in case the saved
            // preference wasn't available on this machine.
            app_ref.scheduler_prefs.backend = available_backends[initial];
            suppress_dropdown_signal = false;

            scheduler_dropdown.notify["selected"].connect (() => {
                if (suppress_dropdown_signal) return;
                on_scheduler_changed ();
            });
        }

        public void refresh () {
            var new_group = new Adw.PreferencesGroup ();
            new_group.title = "Backup Jobs";
            new_group.description = "Each enabled job is written into your crontab, systemd user timers, or Windows Task Scheduler, depending on the scheduler picked above. Use the save icon on a job to export it as a standalone script instead.";

            foreach (var job in app_ref.job_store.jobs) {
                new_group.add (make_job_row (job));
            }

            if (app_ref.job_store.jobs.length == 0) {
                var empty_row = new Adw.ActionRow ();
                empty_row.title = "No backup jobs yet";
                empty_row.subtitle = "Click the + button to schedule one";
                new_group.add (empty_row);
            }

            clamp.child = new_group;
            group = new_group;
        }

        private Adw.ActionRow make_job_row (BackupJob job) {
            var row = new Adw.ActionRow ();
            var repo = app_ref.repo_store.find_by_id (job.repo_id);
            string repo_name = repo != null ? repo.name : "(missing repo)";

            row.title = job.name;
            row.subtitle = @"$(repo_name) — schedule: $(job.cron_schedule) — $(job.source_paths.length) path(s)";

            var enabled_switch = new Gtk.Switch ();
            enabled_switch.active = job.enabled;
            enabled_switch.valign = Gtk.Align.CENTER;
            enabled_switch.state_set.connect ((state) => {
                job.enabled = state;
                app_ref.job_store.save ();
                return false;
            });

            var run_btn = new Gtk.Button.from_icon_name ("media-playback-start-symbolic");
            run_btn.tooltip_text = "Run now";
            run_btn.valign = Gtk.Align.CENTER;
            run_btn.clicked.connect (() => on_run_now (job));

            var export_btn = new Gtk.Button.from_icon_name ("document-save-symbolic");
            export_btn.tooltip_text = "Export as shell script…";
            export_btn.valign = Gtk.Align.CENTER;
            export_btn.clicked.connect (() => on_export_clicked (job));

            var edit_btn = new Gtk.Button.from_icon_name ("document-edit-symbolic");
            edit_btn.tooltip_text = "Edit";
            edit_btn.valign = Gtk.Align.CENTER;
            edit_btn.clicked.connect (() => on_edit_clicked (job));

            var delete_btn = new Gtk.Button.from_icon_name ("user-trash-symbolic");
            delete_btn.tooltip_text = "Delete";
            delete_btn.valign = Gtk.Align.CENTER;
            delete_btn.css_classes = { "destructive-action" };
            delete_btn.clicked.connect (() => on_delete_clicked (job));

            row.add_suffix (enabled_switch);
            row.add_suffix (run_btn);
            row.add_suffix (export_btn);
            row.add_suffix (edit_btn);
            row.add_suffix (delete_btn);
            return row;
        }

        private void on_add_clicked () {
            if (app_ref.repo_store.repos.length == 0) {
                window_ref.show_toast ("Add a repository first.");
                return;
            }
            var dialog = new JobEditDialog (null, app_ref.repo_store);
            dialog.saved.connect ((job) => {
                app_ref.job_store.add_job (job);
                refresh ();
                window_ref.show_toast (@"Job \"$(job.name)\" added — remember to Sync");
            });
            dialog.present (window_ref);
        }

        private void on_edit_clicked (BackupJob job) {
            var dialog = new JobEditDialog (job, app_ref.repo_store);
            dialog.saved.connect ((updated) => {
                app_ref.job_store.save ();
                refresh ();
                window_ref.show_toast (@"Job \"$(updated.name)\" updated — remember to Sync");
            });
            dialog.present (window_ref);
        }

        private void on_delete_clicked (BackupJob job) {
            var dialog = new Adw.AlertDialog (
                "Delete Backup Job?",
                @"This removes \"$(job.name)\" and its scheduled entry."
            );
            dialog.add_response ("cancel", "Cancel");
            dialog.add_response ("delete", "Delete");
            dialog.set_response_appearance ("delete", Adw.ResponseAppearance.DESTRUCTIVE);
            dialog.response.connect ((response) => {
                if (response == "delete") {
                    app_ref.job_store.remove_job (job);
                    refresh ();
                    do_sync_quietly ();
                }
            });
            dialog.present (window_ref);
        }

        /**
         * Runs sync for whichever scheduler backend is currently active.
         * Returns the names of any enabled jobs that were skipped because
         * their repo's password couldn't be found in the system keyring
         * (rather than silently writing an empty RESTIC_PASSWORD for
         * them) — callers should surface these to the user.
         */
        private async string[] sync_current_backend () throws Error {
            switch (app_ref.scheduler_prefs.backend) {
                case SchedulerBackend.SYSTEMD:
                    return yield app_ref.systemd_manager.sync (app_ref.job_store.jobs, app_ref.repo_store);
                case SchedulerBackend.WINDOWS_TASK:
                    return yield app_ref.windows_task_scheduler.sync (app_ref.job_store.jobs, app_ref.repo_store);
                default:
                    return yield app_ref.cron_manager.sync (app_ref.job_store.jobs, app_ref.repo_store);
            }
        }

        private async void teardown_backend (SchedulerBackend backend) throws Error {
            switch (backend) {
                case SchedulerBackend.SYSTEMD:
                    app_ref.systemd_manager.teardown_all ();
                    break;
                case SchedulerBackend.WINDOWS_TASK:
                    app_ref.windows_task_scheduler.teardown_all ();
                    break;
                default:
                    yield app_ref.cron_manager.sync (new GenericArray<BackupJob> (), app_ref.repo_store);
                    break;
            }
        }

        private string skipped_suffix (string[] skipped) {
            if (skipped.length == 0) return "";
            return @" — but $(skipped.length) job(s) skipped (no password in keyring — reopen in Edit Repository): $(string.joinv (", ", skipped))";
        }

        private void on_sync_clicked () {
            on_sync_clicked_async.begin ();
        }

        private async void on_sync_clicked_async () {
            try {
                var skipped = yield sync_current_backend ();
                window_ref.show_toast (@"$(app_ref.scheduler_prefs.backend.label ()) synced ✓$(skipped_suffix (skipped))");
            } catch (Error e) {
                window_ref.show_toast (@"Sync failed: $(e.message)");
            }
        }

        private void do_sync_quietly () {
            do_sync_quietly_async.begin ();
        }

        private async void do_sync_quietly_async () {
            try {
                var skipped = yield sync_current_backend ();
                if (skipped.length > 0) {
                    window_ref.show_toast (@"Sync$(skipped_suffix (skipped))");
                }
            } catch (Error e) {
                window_ref.show_toast (@"Sync failed: $(e.message)");
            }
        }

        private void on_scheduler_changed () {
            uint idx = scheduler_dropdown.selected;
            if (idx >= available_backends.length) return;
            var new_backend = available_backends[idx];
            var old_backend = app_ref.scheduler_prefs.backend;
            if (new_backend == old_backend) return;

            app_ref.scheduler_prefs.backend = new_backend;
            app_ref.scheduler_prefs.save ();

            on_scheduler_changed_async.begin (old_backend, new_backend);
        }

        private async void on_scheduler_changed_async (SchedulerBackend old_backend, SchedulerBackend new_backend) {
            // Tear down the old backend's managed entries first, so jobs
            // don't end up scheduled twice while both are still wired up.
            try {
                yield teardown_backend (old_backend);
            } catch (Error e) {
                window_ref.show_toast (@"Couldn't fully clear old schedule: $(e.message)");
            }

            try {
                var skipped = yield sync_current_backend ();
                window_ref.show_toast (@"Switched scheduler to $(new_backend.label ()) and synced ✓$(skipped_suffix (skipped))");
            } catch (Error e) {
                window_ref.show_toast (@"Sync failed: $(e.message)");
            }
        }

        private void on_export_clicked (BackupJob job) {
            var repo = app_ref.repo_store.find_by_id (job.repo_id);
            if (repo == null) {
                window_ref.show_toast ("Job's repository is missing — can't export.");
                return;
            }
            export_async.begin (job, repo);
        }

        /**
         * Fetches the repo's real password from the system keyring
         * before building the export script, rather than trusting
         * Repository.password — which is empty unless the repo's edit
         * dialog happens to have been opened earlier in this session.
         */
        private async void export_async (BackupJob job, Repository repo) {
            var secret_manager = new SecretManager ();
            string? password = yield secret_manager.lookup_password (repo.id);
            if (password == null) {
                window_ref.show_toast (@"No password found in the keyring for \"$(repo.name)\" — open Edit Repository and re-enter/save it before exporting.");
                return;
            }

            bool on_windows = Path.DIR_SEPARATOR == '\\';
            string ext = on_windows ? "ps1" : "sh";
            string contents = on_windows ? job.build_script_windows (repo, password) : job.build_script (repo, password);

            var dialog = new Gtk.FileDialog ();
            dialog.title = "Save backup script";
            dialog.initial_name = @"$(slugify (job.name)).$(ext)";

            dialog.save.begin (window_ref, null, (obj, res) => {
                try {
                    var file = dialog.save.end (res);
                    if (file == null) return;
                    string path = file.get_path ();
                    FileUtils.set_contents (path, contents);
                    if (!on_windows) FileUtils.chmod (path, 0700);
                    window_ref.show_toast (@"Saved script to $(path) — it contains your repo password, keep it private");
                } catch (Error e) {
                    if (!(e is Gtk.DialogError.DISMISSED)) {
                        window_ref.show_toast (@"Export failed: $(e.message)");
                    }
                }
            });
        }

        private static string slugify (string name) {
            var sb = new StringBuilder ();
            unichar c;
            int i = 0;
            string lower = name.down ();
            while (lower.get_next_char (ref i, out c)) {
                if (c.isalnum ()) {
                    sb.append_unichar (c);
                } else if (sb.len > 0 && !sb.str.has_suffix ("-")) {
                    sb.append_c ('-');
                }
            }
            var result = sb.str;
            while (result.has_suffix ("-")) result = result.substring (0, result.length - 1);
            return result == "" ? "backup-job" : result;
        }

        private void on_run_now (BackupJob job) {
            var repo = app_ref.repo_store.find_by_id (job.repo_id);
            if (repo == null) {
                window_ref.show_toast ("Job's repository is missing.");
                return;
            }
            window_ref.show_toast (@"Running \"$(job.name)\"…");
            run_now_async.begin (repo, job);
        }

        private async void run_now_async (Repository repo, BackupJob job) {
            try {
                yield app_ref.runner.backup_now (repo, job.source_paths, job.excludes);
                window_ref.show_toast (@"Backup \"$(job.name)\" completed ✓");
                if (job.prune_after_forget) {
                    yield app_ref.runner.forget_prune (repo, job);
                }
            } catch (Error e) {
                window_ref.show_toast (@"Backup failed: $(e.message)");
            }
        }
    }
}
