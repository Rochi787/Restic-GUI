namespace ResticGui {

    public class SnapshotsPage : Gtk.Box {

        private weak Application app_ref;
        private weak MainWindow window_ref;
        private Adw.ComboRow repo_picker;
        private Gtk.ListBox snapshot_list;
        private Adw.Clamp clamp;
        private Gtk.Box main_box;
        private Adw.ToolbarView toolbar_view;

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

            snapshot_list = new Gtk.ListBox ();
            snapshot_list.css_classes = { "boxed-list" };
            main_box.append (snapshot_list);

            clamp.child = main_box;
            scroller.child = clamp;
            toolbar_view.content = scroller;
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
            repo_picker.model = new Gtk.StringList (names.data);
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
                clear_list ();

                if (snapshots.length == 0) {
                    var empty_row = new Adw.ActionRow ();
                    empty_row.title = "No snapshots found";
                    snapshot_list.append (empty_row);
                    return;
                }

                foreach (var snap in snapshots) {
                    snapshot_list.append (make_snapshot_row (repo, snap));
                }
            } catch (Error e) {
                clear_list ();
                var error_row = new Adw.ActionRow ();
                error_row.title = "Failed to load snapshots";
                error_row.subtitle = e.message;
                snapshot_list.append (error_row);
            }
        }

        private Adw.ActionRow make_snapshot_row (Repository repo, Snapshot snap) {
            var row = new Adw.ActionRow ();
            row.title = @"$(snap.short_id) — $(snap.time)";
            string paths_joined = string.joinv (", ", snap.paths.data);
            row.subtitle = @"$(snap.hostname) — $(paths_joined)";

            var restore_btn = new Gtk.Button.from_icon_name ("document-revert-symbolic");
            restore_btn.tooltip_text = "Restore…";
            restore_btn.valign = Gtk.Align.CENTER;
            restore_btn.clicked.connect (() => on_restore_clicked (repo, snap));

            var prune_btn = new Gtk.Button.from_icon_name ("user-trash-symbolic");
            prune_btn.tooltip_text = "Forget this snapshot";
            prune_btn.valign = Gtk.Align.CENTER;
            prune_btn.css_classes = { "destructive-action" };
            prune_btn.clicked.connect (() => on_forget_clicked (repo, snap));

            row.add_suffix (restore_btn);
            row.add_suffix (prune_btn);
            return row;
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
                } catch (Error e) {
                    // user cancelled or error — ignore cancellation, toast on real errors
                    if (!(e is Gtk.DialogError.DISMISSED)) {
                        window_ref.show_toast (@"Restore failed: $(e.message)");
                    }
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
