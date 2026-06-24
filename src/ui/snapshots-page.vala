namespace ResticGui {

    public class SnapshotsPage : Gtk.Box {

        private weak Application app_ref;
        private weak MainWindow window_ref;
        private Adw.ComboRow repo_picker;
        private Gtk.ListBox snapshot_list;
        private Adw.Clamp clamp;
        private Gtk.Box main_box;
        private Adw.ToolbarView toolbar_view;

        // --- Filtering ---
        private Adw.ComboRow host_filter_row;
        private Adw.ComboRow tag_filter_row;
        private Adw.EntryRow date_from_row;
        private Adw.EntryRow date_to_row;
        private GenericArray<Snapshot> all_snapshots = new GenericArray<Snapshot> ();
        private bool suppress_filter_signal = false;

        public SnapshotsPage (Application app, MainWindow window) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            app_ref = app;
            window_ref = window;
            build_ui ();
        }

        private void build_ui () {
            toolbar_view = new Adw.ToolbarView ();
            this.vexpand = true;
            this.hexpand = true;
            this.append (toolbar_view);
            toolbar_view.vexpand = true;
            toolbar_view.hexpand = true;

            var header = new Adw.HeaderBar ();
            var refresh_btn = new Gtk.Button.from_icon_name ("view-refresh-symbolic");
            refresh_btn.tooltip_text = "Reload snapshots";
            refresh_btn.clicked.connect (() => load_snapshots ());
            header.pack_end (refresh_btn);
            toolbar_view.add_top_bar (header);

            var scroller = new Gtk.ScrolledWindow ();
            scroller.vexpand = true;

            clamp = new Adw.Clamp ();
            clamp.maximum_size = 750;
            clamp.margin_top = 24;
            clamp.margin_bottom = 24;
            clamp.margin_start = 12;
            clamp.margin_end = 12;

            main_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 18);

            var picker_group = new Adw.PreferencesGroup ();
            repo_picker = new Adw.ComboRow ();
            repo_picker.title = "Repository";
            picker_group.add (repo_picker);
            main_box.append (picker_group);

            repo_picker.notify["selected"].connect (() => load_snapshots ());

            build_filter_ui ();

            snapshot_list = new Gtk.ListBox ();
            snapshot_list.css_classes = { "boxed-list" };
            main_box.append (snapshot_list);

            clamp.child = main_box;
            scroller.child = clamp;
            toolbar_view.content = scroller;
        }

        /**
         * Filter controls — scoped to whichever repository is currently
         * selected above, same as the snapshot list itself. Host and tag
         * options are (re)populated from whatever snapshots were just
         * loaded for that repo; date range is free-text (YYYY-MM-DD)
         * compared against each snapshot's date.
         */
        private void build_filter_ui () {
            var filters_group = new Adw.PreferencesGroup ();
            filters_group.title = "Filters";

            host_filter_row = new Adw.ComboRow ();
            host_filter_row.title = "Machine";
            host_filter_row.model = new Gtk.StringList ({ "All hosts" });
            host_filter_row.notify["selected"].connect (() => apply_filters ());
            filters_group.add (host_filter_row);

            tag_filter_row = new Adw.ComboRow ();
            tag_filter_row.title = "Tag";
            tag_filter_row.model = new Gtk.StringList ({ "All tags" });
            tag_filter_row.notify["selected"].connect (() => apply_filters ());
            filters_group.add (tag_filter_row);

            date_from_row = new Adw.EntryRow ();
            date_from_row.title = "From (YYYY-MM-DD)";
            date_from_row.changed.connect (() => apply_filters ());
            filters_group.add (date_from_row);

            date_to_row = new Adw.EntryRow ();
            date_to_row.title = "To (YYYY-MM-DD)";
            date_to_row.changed.connect (() => apply_filters ());
            filters_group.add (date_to_row);

            var clear_row = new Adw.ActionRow ();
            clear_row.title = "Clear filters";
            var clear_btn = new Gtk.Button.from_icon_name ("edit-clear-symbolic");
            clear_btn.valign = Gtk.Align.CENTER;
            clear_btn.clicked.connect (() => on_clear_filters ());
            clear_row.add_suffix (clear_btn);
            clear_row.activatable_widget = clear_btn;
            filters_group.add (clear_row);

            main_box.append (filters_group);
        }

        private void on_clear_filters () {
            suppress_filter_signal = true;
            host_filter_row.selected = 0;
            tag_filter_row.selected = 0;
            date_from_row.text = "";
            date_to_row.text = "";
            suppress_filter_signal = false;
            apply_filters ();
        }

        public void refresh () {
            var names = new GenericArray<string> ();
            foreach (var r in app_ref.repo_store.repos) names.add (r.name);

            if (names.length == 0) {
                repo_picker.model = new Gtk.StringList ({ "No repositories configured" });
                repo_picker.sensitive = false;
                return;
            }

            repo_picker.sensitive = true;
            string[] name_arr = new string[names.length];
            for (int i = 0; i < names.length; i++) name_arr[i] = names[i];
            repo_picker.model = new Gtk.StringList (name_arr);
            if (repo_picker.selected == Gtk.INVALID_LIST_POSITION || repo_picker.selected >= names.length) {
                repo_picker.selected = 0;
            } else {
                load_snapshots ();
            }
        }

        private Repository? current_repo () {
            if (app_ref.repo_store.repos.length == 0) return null;
            int idx = (int) repo_picker.selected;
            if (idx < 0 || idx >= app_ref.repo_store.repos.length) return null;
            return app_ref.repo_store.repos[idx];
        }

        private void load_snapshots () {
            var repo = current_repo ();
            clear_list ();
            if (repo == null) return;

            var loading_row = new Adw.ActionRow ();
            loading_row.title = "Loading snapshots…";
            snapshot_list.append (loading_row);

            load_snapshots_async.begin (repo);
        }

        private void clear_list () {
            Gtk.Widget? child;
            while ((child = snapshot_list.get_first_child ()) != null) {
                snapshot_list.remove (child);
            }
        }

        private async void load_snapshots_async (Repository repo) {
            try {
                var snapshots = yield app_ref.runner.list_snapshots (repo);
                all_snapshots = snapshots;
                populate_filter_options ();
                apply_filters ();
            } catch (Error e) {
                all_snapshots = new GenericArray<Snapshot> ();
                clear_list ();
                var error_row = new Adw.ActionRow ();
                error_row.title = "Failed to load snapshots";
                error_row.subtitle = e.message;
                snapshot_list.append (error_row);
            }
        }

        /** Rebuilds the Machine/Tag dropdown options from whatever snapshots are currently loaded for this repo. */
        private void populate_filter_options () {
            var hosts = new GenericArray<string> ();
            hosts.add ("All hosts");
            var tags = new GenericArray<string> ();
            tags.add ("All tags");

            foreach (var snap in all_snapshots) {
                if (snap.hostname != "" && !contains_str (hosts, snap.hostname)) hosts.add (snap.hostname);
                foreach (var t in snap.tag_list) {
                    if (!contains_str (tags, t)) tags.add (t);
                }
            }

            // Copy into plain, length-tracked string[] before handing to
            // Gtk.StringList — a GenericArray<string>.data property read
            // isn't reliably null-terminated, which shows up as garbage
            // entries in the dropdown otherwise.
            string[] host_arr = new string[hosts.length];
            for (int i = 0; i < hosts.length; i++) host_arr[i] = hosts[i];
            string[] tag_arr = new string[tags.length];
            for (int i = 0; i < tags.length; i++) tag_arr[i] = tags[i];

            suppress_filter_signal = true;
            host_filter_row.model = new Gtk.StringList (host_arr);
            host_filter_row.selected = 0;
            tag_filter_row.model = new Gtk.StringList (tag_arr);
            tag_filter_row.selected = 0;
            suppress_filter_signal = false;
        }

        private bool contains_str (GenericArray<string> arr, string val) {
            foreach (var v in arr) {
                if (v == val) return true;
            }
            return false;
        }

        private string selected_string (Adw.ComboRow row) {
            var model = row.model as Gtk.StringList;
            if (model == null) return "";
            uint idx = row.selected;
            if (idx == Gtk.INVALID_LIST_POSITION || idx >= model.get_n_items ()) return "";
            return model.get_string (idx);
        }

        private bool snapshot_has_tag (Snapshot snap, string tag) {
            foreach (var t in snap.tag_list) {
                if (t == tag) return true;
            }
            return false;
        }

        /** Re-renders the snapshot list from all_snapshots according to the current filter controls. */
        private void apply_filters () {
            if (suppress_filter_signal) return;

            var repo = current_repo ();
            clear_list ();
            if (repo == null) return;

            string host_filter = selected_string (host_filter_row);
            string tag_filter = selected_string (tag_filter_row);
            string date_from = date_from_row.text.strip ();
            string date_to = date_to_row.text.strip ();

            var matches = new GenericArray<Snapshot> ();
            foreach (var snap in all_snapshots) {
                if (host_filter != "" && host_filter != "All hosts" && snap.hostname != host_filter) continue;
                if (tag_filter != "" && tag_filter != "All tags" && !snapshot_has_tag (snap, tag_filter)) continue;

                string snap_date = snap.time.length >= 10 ? snap.time.substring (0, 10) : snap.time;
                if (date_from != "" && snap_date.collate (date_from) < 0) continue;
                if (date_to != "" && snap_date.collate (date_to) > 0) continue;

                matches.add (snap);
            }

            if (matches.length == 0) {
                var empty_row = new Adw.ActionRow ();
                empty_row.title = all_snapshots.length == 0 ? "No snapshots found" : "No snapshots match the current filters";
                snapshot_list.append (empty_row);
                return;
            }

            foreach (var snap in matches) {
                snapshot_list.append (make_snapshot_row (repo, snap));
            }
        }

        private Adw.ActionRow make_snapshot_row (Repository repo, Snapshot snap) {
            var row = new Adw.ActionRow ();
            row.title = @"$(snap.short_id) — $(snap.time)";
            string paths_joined = string.joinv (", ", snap.paths.data);
            string tag_suffix = snap.tags != "" ? @" — tags: $(snap.tags)" : "";
            row.subtitle = @"$(snap.hostname) — $(paths_joined)$(tag_suffix)";

            var browse_btn = new Gtk.Button.from_icon_name ("folder-open-symbolic");
            browse_btn.tooltip_text = "Browse files…";
            browse_btn.valign = Gtk.Align.CENTER;
            browse_btn.clicked.connect (() => on_browse_clicked (repo, snap));

            var restore_btn = new Gtk.Button.from_icon_name ("document-revert-symbolic");
            restore_btn.tooltip_text = "Restore…";
            restore_btn.valign = Gtk.Align.CENTER;
            restore_btn.clicked.connect (() => on_restore_clicked (repo, snap));

            var prune_btn = new Gtk.Button.from_icon_name ("user-trash-symbolic");
            prune_btn.tooltip_text = "Forget this snapshot";
            prune_btn.valign = Gtk.Align.CENTER;
            prune_btn.css_classes = { "destructive-action" };
            prune_btn.clicked.connect (() => on_forget_clicked (repo, snap));

            row.add_suffix (browse_btn);
            row.add_suffix (restore_btn);
            row.add_suffix (prune_btn);
            return row;
        }

        private void on_browse_clicked (Repository repo, Snapshot snap) {
            var dialog = new SnapshotBrowserDialog (app_ref, window_ref, repo, snap);
            dialog.present (window_ref);
        }

        private void on_restore_clicked (Repository repo, Snapshot snap) {
            var dialog = new Gtk.FileDialog ();
            dialog.title = "Choose restore destination";
            dialog.select_folder.begin (window_ref, null, (obj, res) => {
                try {
                    var folder = dialog.select_folder.end (res);
                    if (folder == null) return;
                    string target = folder.get_path ();
                    window_ref.show_toast (@"Restoring $(snap.short_id) to $(target)…");
                    restore_async.begin (repo, snap, target);
                } catch (Gtk.DialogError.DISMISSED e) {
                    // User closed/cancelled the folder picker — nothing to do.
                } catch (Error e) {
                    window_ref.show_toast (@"Restore failed: $(e.message)");
                }
            });
        }

        private async void restore_async (Repository repo, Snapshot snap, string target) {
            try {
                yield app_ref.runner.restore_snapshot (repo, snap.snapshot_id, target);
                window_ref.show_toast (@"Restored $(snap.short_id) to $(target) ✓");
            } catch (Error e) {
                window_ref.show_toast (@"Restore failed: $(e.message)");
            }
        }

        private void on_forget_clicked (Repository repo, Snapshot snap) {
            var dialog = new Adw.AlertDialog (
                "Forget Snapshot?",
                @"This permanently removes snapshot $(snap.short_id) from the repository (after the next prune)."
            );
            dialog.add_response ("cancel", "Cancel");
            dialog.add_response ("forget", "Forget");
            dialog.set_response_appearance ("forget", Adw.ResponseAppearance.DESTRUCTIVE);
            dialog.response.connect ((response) => {
                if (response == "forget") {
                    forget_async.begin (repo, snap);
                }
            });
            dialog.present (window_ref);
        }

        private async void forget_async (Repository repo, Snapshot snap) {
            try {
                yield app_ref.runner.forget_snapshot (repo, snap.snapshot_id, true);
                window_ref.show_toast (@"Forgot snapshot $(snap.short_id) ✓");
                load_snapshots ();
            } catch (Error e) {
                window_ref.show_toast (@"Forget failed: $(e.message)");
            }
        }
    }
}
