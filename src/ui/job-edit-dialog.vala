namespace ResticGui {

    public class JobEditDialog : Adw.Dialog {

        public signal void saved (BackupJob job);

        private BackupJob job;
        private RepoStore repo_store;

        private Adw.EntryRow name_row;
        private Adw.ComboRow repo_row;
        private Gtk.TextView paths_view;
        private Gtk.TextView excludes_view;
        private Adw.ComboRow schedule_preset_row;
        private Adw.EntryRow custom_cron_row;
        private Adw.SwitchRow prune_row;
        private Adw.SpinRow keep_daily_row;
        private Adw.SpinRow keep_weekly_row;
        private Adw.SpinRow keep_monthly_row;
        private Adw.SpinRow keep_yearly_row;

        private const string[] PRESET_LABELS = {
            "Daily at 2:00 AM",
            "Every 6 hours",
            "Weekly (Sunday 3:00 AM)",
            "Custom",
        };
        private const string[] PRESET_CRON = {
            "0 2 * * *",
            "0 */6 * * *",
            "0 3 * * 0",
            "",
        };

        public JobEditDialog (BackupJob? existing, RepoStore repos) {
            repo_store = repos;
            job = existing ?? new BackupJob ();
            if (existing == null) {
                job.id = GLib.Uuid.string_random ();
            }

            title = existing == null ? "Add Backup Job" : "Edit Backup Job";
            content_width = 520;
            content_height = 640;

            build_ui ();
        }

        private void build_ui () {
            var toolbar_view = new Adw.ToolbarView ();
            var header = new Adw.HeaderBar ();
            header.show_end_title_buttons = false;
            header.show_start_title_buttons = false;

            var cancel_btn = new Gtk.Button.with_label ("Cancel");
            cancel_btn.clicked.connect (() => close ());
            header.pack_start (cancel_btn);

            var save_btn = new Gtk.Button.with_label ("Save");
            save_btn.css_classes = { "suggested-action" };
            save_btn.clicked.connect (() => on_save ());
            header.pack_end (save_btn);

            toolbar_view.add_top_bar (header);

            var scroller = new Gtk.ScrolledWindow ();
            scroller.vexpand = true;

            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 18);
            box.margin_top = 18;
            box.margin_bottom = 18;
            box.margin_start = 18;
            box.margin_end = 18;

            // --- Basics ---
            var basics = new Adw.PreferencesGroup ();
            name_row = new Adw.EntryRow ();
            name_row.title = "Job Name";
            name_row.text = job.name;
            basics.add (name_row);

            repo_row = new Adw.ComboRow ();
            repo_row.title = "Repository";
            var names = new GenericArray<string> ();
            int selected_index = 0;
            for (int i = 0; i < repo_store.repos.length; i++) {
                names.add (repo_store.repos[i].name);
                if (repo_store.repos[i].id == job.repo_id) selected_index = i;
            }
            string[] name_arr = new string[names.length];
            for (int i = 0; i < names.length; i++) name_arr[i] = names[i];
            repo_row.model = new Gtk.StringList (name_arr);
            repo_row.selected = selected_index;
            basics.add (repo_row);
            box.append (basics);

            // --- Paths ---
            var paths_group = new Adw.PreferencesGroup ();
            paths_group.title = "Source Paths";
            paths_group.description = "One path per line, e.g. /home/rochi/Documents";
            paths_view = new Gtk.TextView ();
            paths_view.css_classes = { "card" };
            paths_view.top_margin = 8;
            paths_view.bottom_margin = 8;
            paths_view.left_margin = 8;
            paths_view.right_margin = 8;
            paths_view.buffer.text = string.joinv ("\n", job.source_paths.data);
            var paths_scroller = new Gtk.ScrolledWindow ();
            paths_scroller.min_content_height = 90;
            paths_scroller.child = paths_view;
            paths_group.add (paths_scroller);
            box.append (paths_group);

            // --- Excludes ---
            var excl_group = new Adw.PreferencesGroup ();
            excl_group.title = "Excludes";
            excl_group.description = "Glob patterns, one per line, e.g. *.tmp";
            excludes_view = new Gtk.TextView ();
            excludes_view.css_classes = { "card" };
            excludes_view.top_margin = 8;
            excludes_view.bottom_margin = 8;
            excludes_view.left_margin = 8;
            excludes_view.right_margin = 8;
            excludes_view.buffer.text = string.joinv ("\n", job.excludes.data);
            var excl_scroller = new Gtk.ScrolledWindow ();
            excl_scroller.min_content_height = 60;
            excl_scroller.child = excludes_view;
            excl_group.add (excl_scroller);
            box.append (excl_group);

            // --- Schedule ---
            var sched_group = new Adw.PreferencesGroup ();
            sched_group.title = "Schedule";

            schedule_preset_row = new Adw.ComboRow ();
            schedule_preset_row.title = "Frequency";
            schedule_preset_row.model = new Gtk.StringList (PRESET_LABELS);

            int preset_idx = PRESET_CRON.length - 1; // default custom
            for (int i = 0; i < PRESET_CRON.length - 1; i++) {
                if (PRESET_CRON[i] == job.cron_schedule) { preset_idx = i; break; }
            }
            schedule_preset_row.selected = preset_idx;
            sched_group.add (schedule_preset_row);

            custom_cron_row = new Adw.EntryRow ();
            custom_cron_row.title = "Cron Expression";
            custom_cron_row.text = job.cron_schedule;
            custom_cron_row.visible = preset_idx == PRESET_CRON.length - 1;
            sched_group.add (custom_cron_row);

            schedule_preset_row.notify["selected"].connect (() => {
                int idx = (int) schedule_preset_row.selected;
                bool is_custom = idx == PRESET_CRON.length - 1;
                custom_cron_row.visible = is_custom;
                if (!is_custom) custom_cron_row.text = PRESET_CRON[idx];
            });

            box.append (sched_group);

            // --- Retention ---
            var retention_group = new Adw.PreferencesGroup ();
            retention_group.title = "Retention Policy";
            retention_group.description = "Applied via 'restic forget' after each backup.";

            prune_row = new Adw.SwitchRow ();
            prune_row.title = "Prune old snapshots";
            prune_row.active = job.prune_after_forget;
            retention_group.add (prune_row);

            keep_daily_row = new Adw.SpinRow.with_range (0, 365, 1);
            keep_daily_row.title = "Keep Daily";
            keep_daily_row.value = job.keep_daily >= 0 ? job.keep_daily : 7;
            retention_group.add (keep_daily_row);

            keep_weekly_row = new Adw.SpinRow.with_range (0, 52, 1);
            keep_weekly_row.title = "Keep Weekly";
            keep_weekly_row.value = job.keep_weekly >= 0 ? job.keep_weekly : 4;
            retention_group.add (keep_weekly_row);

            keep_monthly_row = new Adw.SpinRow.with_range (0, 60, 1);
            keep_monthly_row.title = "Keep Monthly";
            keep_monthly_row.value = job.keep_monthly >= 0 ? job.keep_monthly : 6;
            retention_group.add (keep_monthly_row);

            keep_yearly_row = new Adw.SpinRow.with_range (0, 50, 1);
            keep_yearly_row.title = "Keep Yearly";
            keep_yearly_row.value = job.keep_yearly >= 0 ? job.keep_yearly : 0;
            retention_group.add (keep_yearly_row);

            box.append (retention_group);

            scroller.child = box;
            toolbar_view.content = scroller;
            child = toolbar_view;
        }

        private void on_save () {
            job.name = name_row.text;

            if (repo_store.repos.length > 0) {
                job.repo_id = repo_store.repos[(int) repo_row.selected].id;
            }

            job.source_paths = new GenericArray<string> ();
            foreach (var line in paths_view.buffer.text.split ("\n")) {
                var trimmed = line.strip ();
                if (trimmed != "") job.source_paths.add (trimmed);
            }

            job.excludes = new GenericArray<string> ();
            foreach (var line in excludes_view.buffer.text.split ("\n")) {
                var trimmed = line.strip ();
                if (trimmed != "") job.excludes.add (trimmed);
            }

            job.cron_schedule = custom_cron_row.text.strip ();
            job.prune_after_forget = prune_row.active;
            job.keep_daily = (int) keep_daily_row.value;
            job.keep_weekly = (int) keep_weekly_row.value;
            job.keep_monthly = (int) keep_monthly_row.value;
            job.keep_yearly = (int) keep_yearly_row.value;

            saved (job);
            close ();
        }
    }
}
