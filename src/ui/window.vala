namespace ResticGui {

    public class MainWindow : Adw.ApplicationWindow {

        private Adw.NavigationSplitView split_view;
        private Adw.ToastOverlay toast_overlay;
        public weak Application app_ref;

        private ReposPage repos_page;
        private JobsPage jobs_page;
        private SnapshotsPage snapshots_page;

        public MainWindow (Application app) {
            Object (application: app, title: "Restic Backup Manager");
            app_ref = app;

            default_width = 1000;
            default_height = 650;

            build_ui ();

            if (!ResticRunner.is_installed ()) {
                show_toast ("Warning: 'restic' binary not found in PATH.");
            }
        }

        private void build_ui () {
            toast_overlay = new Adw.ToastOverlay ();

            split_view = new Adw.NavigationSplitView ();

            // --- Sidebar ---
            var sidebar_list = new Gtk.ListBox ();
            sidebar_list.selection_mode = Gtk.SelectionMode.SINGLE;
            sidebar_list.css_classes = { "navigation-sidebar" };

            sidebar_list.append (make_sidebar_row ("Repositories", "drive-harddisk-symbolic"));
            sidebar_list.append (make_sidebar_row ("Backup Jobs", "appointment-soon-symbolic"));
            sidebar_list.append (make_sidebar_row ("Snapshots", "edit-copy-symbolic"));

            var sidebar_header = new Adw.HeaderBar ();
            sidebar_header.title_widget = new Adw.WindowTitle ("Restic GUI", "");

            var sidebar_toolbar = new Adw.ToolbarView ();
            sidebar_toolbar.add_top_bar (sidebar_header);
            sidebar_toolbar.content = sidebar_list;

            var sidebar_page = new Adw.NavigationPage (sidebar_toolbar, "Restic GUI");
            split_view.sidebar = sidebar_page;

            // --- Content pages ---
            repos_page = new ReposPage (app_ref, this);
            jobs_page = new JobsPage (app_ref, this);
            snapshots_page = new SnapshotsPage (app_ref, this);

            var content_page = new Adw.NavigationPage (repos_page, "Repositories");
            split_view.content = content_page;

            sidebar_list.row_selected.connect ((row) => {
                if (row == null) return;
                int idx = row.get_index ();
                switch (idx) {
                    case 0:
                        split_view.content = new Adw.NavigationPage (repos_page, "Repositories");
                        repos_page.refresh ();
                        break;
                    case 1:
                        split_view.content = new Adw.NavigationPage (jobs_page, "Backup Jobs");
                        jobs_page.refresh ();
                        break;
                    case 2:
                        split_view.content = new Adw.NavigationPage (snapshots_page, "Snapshots");
                        snapshots_page.refresh ();
                        break;
                }
            });
            sidebar_list.select_row (sidebar_list.get_row_at_index (0));

            toast_overlay.child = split_view;
            content = toast_overlay;
        }

        private Gtk.ListBoxRow make_sidebar_row (string label, string icon_name) {
            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10);
            box.margin_top = 8;
            box.margin_bottom = 8;
            box.margin_start = 10;
            box.margin_end = 10;
            box.append (new Gtk.Image.from_icon_name (icon_name));
            box.append (new Gtk.Label (label));
            var row = new Gtk.ListBoxRow ();
            row.child = box;
            return row;
        }

        public void show_toast (string message) {
            var toast = new Adw.Toast (message);
            toast.timeout = 4;
            toast_overlay.add_toast (toast);
        }

        public JobsPage get_jobs_page () { return jobs_page; }
        public ReposPage get_repos_page () { return repos_page; }
        public SnapshotsPage get_snapshots_page () { return snapshots_page; }
    }
}
