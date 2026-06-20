namespace ResticGui {

    public class ReposPage : Gtk.Box {

        private weak Application app_ref;
        private weak MainWindow window_ref;
        private Gtk.ListBox list_box;
        private Adw.PreferencesGroup group;
        private Adw.ToolbarView toolbar_view;

        public ReposPage (Application app, MainWindow window) {
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
            add_btn.tooltip_text = "Add Repository";
            add_btn.clicked.connect (() => on_add_clicked ());
            header.pack_start (add_btn);
            toolbar_view.add_top_bar (header);

            var scroller = new Gtk.ScrolledWindow ();
            scroller.vexpand = true;

            var clamp = new Adw.Clamp ();
            clamp.maximum_size = 700;
            clamp.margin_top = 24;
            clamp.margin_bottom = 24;
            clamp.margin_start = 12;
            clamp.margin_end = 12;

            group = new Adw.PreferencesGroup ();
            group.title = "Repositories";
            group.description = "Restic repositories you back up into. Supports local paths, SFTP, S3, B2, and rest-server.";

            clamp.child = group;
            scroller.child = clamp;
            toolbar_view.content = scroller;
        }

        public void refresh () {
            // Clear existing rows.
            var child = group.get_first_child ();
            // PreferencesGroup doesn't expose easy clearing, so rebuild it.
            var new_group = new Adw.PreferencesGroup ();
            new_group.title = "Repositories";
            new_group.description = "Restic repositories you back up into. Supports local paths, SFTP, S3, B2, and rest-server.";

            foreach (var repo in app_ref.repo_store.repos) {
                new_group.add (make_repo_row (repo));
            }

            if (app_ref.repo_store.repos.length == 0) {
                var empty_row = new Adw.ActionRow ();
                empty_row.title = "No repositories yet";
                empty_row.subtitle = "Click the + button to add one";
                new_group.add (empty_row);
            }

            var parent = (Gtk.Widget) group.parent;
            if (parent != null) {
                ((Adw.Clamp) parent).child = new_group;
            }
            group = new_group;
        }

        private Adw.ActionRow make_repo_row (Repository repo) {
            var row = new Adw.ActionRow ();
            row.title = repo.name;
            row.subtitle = @"$(repo.backend.label()) — $(repo.location)";

            var check_btn = new Gtk.Button.from_icon_name ("emblem-ok-symbolic");
            check_btn.tooltip_text = "Check connection";
            check_btn.valign = Gtk.Align.CENTER;
            check_btn.clicked.connect (() => on_check_clicked (repo));

            var init_btn = new Gtk.Button.from_icon_name ("document-new-symbolic");
            init_btn.tooltip_text = "Initialize repository";
            init_btn.valign = Gtk.Align.CENTER;
            init_btn.clicked.connect (() => on_init_clicked (repo));

            var edit_btn = new Gtk.Button.from_icon_name ("document-edit-symbolic");
            edit_btn.tooltip_text = "Edit";
            edit_btn.valign = Gtk.Align.CENTER;
            edit_btn.clicked.connect (() => on_edit_clicked (repo));

            var delete_btn = new Gtk.Button.from_icon_name ("user-trash-symbolic");
            delete_btn.tooltip_text = "Delete";
            delete_btn.valign = Gtk.Align.CENTER;
            delete_btn.css_classes = { "destructive-action" };
            delete_btn.clicked.connect (() => on_delete_clicked (repo));

            row.add_suffix (check_btn);
            row.add_suffix (init_btn);
            row.add_suffix (edit_btn);
            row.add_suffix (delete_btn);
            return row;
        }

        private void on_add_clicked () {
            var dialog = new RepoEditDialog (null);
            dialog.saved.connect ((repo) => {
                app_ref.repo_store.add_repo (repo);
                refresh ();
                window_ref.show_toast (@"Repository \"$(repo.name)\" added");
            });
            dialog.present (window_ref);
        }

        private void on_edit_clicked (Repository repo) {
            var dialog = new RepoEditDialog (repo);
            dialog.saved.connect ((updated) => {
                app_ref.repo_store.save ();
                refresh ();
                window_ref.show_toast (@"Repository \"$(updated.name)\" updated");
            });
            dialog.present (window_ref);
        }

        private void on_delete_clicked (Repository repo) {
            var dialog = new Adw.AlertDialog (
                "Delete Repository?",
                @"This removes \"$(repo.name)\" from restic-gui. The actual restic repository data is not deleted."
            );
            dialog.add_response ("cancel", "Cancel");
            dialog.add_response ("delete", "Delete");
            dialog.set_response_appearance ("delete", Adw.ResponseAppearance.DESTRUCTIVE);
            dialog.response.connect ((response) => {
                if (response == "delete") {
                    app_ref.repo_store.remove_repo (repo);
                    refresh ();
                    window_ref.show_toast (@"Repository \"$(repo.name)\" removed");
                }
            });
            dialog.present (window_ref);
        }

        private void on_check_clicked (Repository repo) {
            window_ref.show_toast (@"Checking \"$(repo.name)\"…");
            check_repo_async.begin (repo);
        }

        private async void check_repo_async (Repository repo) {
            bool ok = yield app_ref.runner.check_repo (repo);
            window_ref.show_toast (ok
                ? @"\"$(repo.name)\" is reachable ✓"
                : @"\"$(repo.name)\" could not be reached — check credentials/path");
        }

        private void on_init_clicked (Repository repo) {
            window_ref.show_toast (@"Initializing \"$(repo.name)\"…");
            init_repo_async.begin (repo);
        }

        private async void init_repo_async (Repository repo) {
            try {
                yield app_ref.runner.init_repo (repo);
                window_ref.show_toast (@"Repository \"$(repo.name)\" initialized ✓");
            } catch (Error e) {
                window_ref.show_toast (@"Init failed: $(e.message)");
            }
        }
    }
}
