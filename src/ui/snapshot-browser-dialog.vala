namespace ResticGui {

    /**
     * Lets the user drill into a snapshot's file tree (one `restic ls
     * --json` call up front, navigated locally) and, per file or folder:
     *   - Open it with the OS's default app (restored to a temp dir first)
     *   - Restore it to a chosen folder
     *   - Dump it to disk as-is (file) or as a .zip (folder)
     *
     * This fills the gap noted in the README ("`restic ls` has a runner
     * method but no UI yet") and mirrors the browse/dump/open/restore
     * feature set of the restic-browser project, scoped to one snapshot
     * at a time.
     */
    public class SnapshotBrowserDialog : Adw.Dialog {

        private weak Application app_ref;
        private weak Gtk.Window window_ref;
        private Repository repo;
        private Snapshot target_snapshot;

        private GenericArray<SnapshotEntry> all_entries = new GenericArray<SnapshotEntry> ();
        private string current_path = "/";

        private Adw.ToolbarView toolbar_view;
        private Adw.WindowTitle window_title;
        private Gtk.Button up_btn;
        private Gtk.ListBox list_box;
        private Adw.ToastOverlay toast_overlay;

        public SnapshotBrowserDialog (Application app, Gtk.Window window, Repository repo, Snapshot target_snapshot) {
            app_ref = app;
            window_ref = window;
            this.repo = repo;
            this.target_snapshot = target_snapshot;

            title = @"Browse $(target_snapshot.short_id)";
            content_width = 620;
            content_height = 680;

            build_ui ();
            load_entries ();
        }

        private void build_ui () {
            toolbar_view = new Adw.ToolbarView ();

            var header = new Adw.HeaderBar ();
            window_title = new Adw.WindowTitle (@"Snapshot $(target_snapshot.short_id)", "/");
            header.title_widget = window_title;

            var close_btn = new Gtk.Button.with_label ("Close");
            close_btn.clicked.connect (() => close ());
            header.pack_start (close_btn);

            up_btn = new Gtk.Button.from_icon_name ("go-up-symbolic");
            up_btn.tooltip_text = "Up one level";
            up_btn.sensitive = false;
            up_btn.clicked.connect (() => navigate_up ());
            header.pack_start (up_btn);

            var dump_folder_btn = new Gtk.Button.from_icon_name ("folder-download-symbolic");
            dump_folder_btn.tooltip_text = "Dump current folder as zip…";
            dump_folder_btn.clicked.connect (() => on_dump_current_folder ());
            header.pack_end (dump_folder_btn);

            var restore_folder_btn = new Gtk.Button.from_icon_name ("document-revert-symbolic");
            restore_folder_btn.tooltip_text = "Restore current folder…";
            restore_folder_btn.clicked.connect (() => on_restore_current_folder ());
            header.pack_end (restore_folder_btn);

            toolbar_view.add_top_bar (header);

            toast_overlay = new Adw.ToastOverlay ();

            var scroller = new Gtk.ScrolledWindow ();
            scroller.vexpand = true;

            list_box = new Gtk.ListBox ();
            list_box.css_classes = { "boxed-list" };
            list_box.margin_top = 12;
            list_box.margin_bottom = 12;
            list_box.margin_start = 12;
            list_box.margin_end = 12;

            scroller.child = list_box;
            toast_overlay.child = scroller;
            toolbar_view.content = toast_overlay;
            child = toolbar_view;
        }

        private void show_toast (string message) {
            var toast = new Adw.Toast (message);
            toast.timeout = 4;
            toast_overlay.add_toast (toast);
        }

        private void load_entries () {
            clear_list ();
            var loading_row = new Adw.ActionRow ();
            loading_row.title = "Loading snapshot contents…";
            list_box.append (loading_row);

            load_entries_async.begin ();
        }

        private async void load_entries_async () {
            try {
                all_entries = yield app_ref.runner.list_snapshot_tree (repo, target_snapshot.snapshot_id);
                render_current_dir ();
            } catch (Error e) {
                clear_list ();
                var error_row = new Adw.ActionRow ();
                error_row.title = "Failed to list snapshot contents";
                error_row.subtitle = e.message;
                list_box.append (error_row);
            }
        }

        private void clear_list () {
            Gtk.Widget? child;
            while ((child = list_box.get_first_child ()) != null) {
                list_box.remove (child);
            }
        }

        private void navigate_to (string path) {
            current_path = path;
            window_title.subtitle = current_path;
            up_btn.sensitive = current_path != "/";
            render_current_dir ();
        }

        private void navigate_up () {
            if (current_path == "/") return;
            int idx = current_path.last_index_of ("/");
            string parent = idx > 0 ? current_path.substring (0, idx) : "/";
            navigate_to (parent);
        }

        private void render_current_dir () {
            clear_list ();

            var children = new GenericArray<SnapshotEntry> ();
            foreach (var entry in all_entries) {
                if (entry.path != current_path && entry.parent_path () == current_path) {
                    children.add (entry);
                }
            }

            if (children.length == 0) {
                var empty_row = new Adw.ActionRow ();
                empty_row.title = "(empty folder)";
                list_box.append (empty_row);
                return;
            }

            // Directories first, then files, both alphabetically. Uses
            // GLib.List.insert_sorted() rather than GenericArray, since
            // that API is stable and well-documented for this kind of
            // "insert keeping order" job.
            var sorted = new GLib.List<SnapshotEntry> ();
            foreach (var entry in children) {
                sorted.insert_sorted (entry, (a, b) => row_rank (a, b));
            }

            foreach (var entry in sorted) {
                list_box.append (make_entry_row (entry));
            }
        }

        // Returns <0 if `a` should sort before `b`.
        private static int row_rank (SnapshotEntry a, SnapshotEntry b) {
            bool a_dir = a.entry_type == "dir";
            bool b_dir = b.entry_type == "dir";
            if (a_dir != b_dir) return a_dir ? -1 : 1;
            return a.name.collate (b.name);
        }

        private Adw.ActionRow make_entry_row (SnapshotEntry entry) {
            var row = new Adw.ActionRow ();
            bool is_dir = entry.entry_type == "dir";
            row.title = entry.name;
            row.subtitle = is_dir ? "Folder" : format_size (entry.size);

            var icon = new Gtk.Image.from_icon_name (is_dir ? "folder-symbolic" : "text-x-generic-symbolic");
            row.add_prefix (icon);

            if (is_dir) {
                row.activatable = true;
                row.activated.connect (() => navigate_to (entry.path));

                var open_btn = new Gtk.Button.from_icon_name ("go-next-symbolic");
                open_btn.tooltip_text = "Open folder";
                open_btn.valign = Gtk.Align.CENTER;
                open_btn.clicked.connect (() => navigate_to (entry.path));
                row.add_suffix (open_btn);
            } else {
                var open_btn = new Gtk.Button.from_icon_name ("document-open-symbolic");
                open_btn.tooltip_text = "Open with default app";
                open_btn.valign = Gtk.Align.CENTER;
                open_btn.clicked.connect (() => on_open_file (entry));
                row.add_suffix (open_btn);
            }

            var restore_btn = new Gtk.Button.from_icon_name ("document-revert-symbolic");
            restore_btn.tooltip_text = is_dir ? "Restore this folder…" : "Restore this file…";
            restore_btn.valign = Gtk.Align.CENTER;
            restore_btn.clicked.connect (() => on_restore_entry (entry));
            row.add_suffix (restore_btn);

            var dump_btn = new Gtk.Button.from_icon_name ("folder-download-symbolic");
            dump_btn.tooltip_text = is_dir ? "Dump as zip…" : "Dump to file…";
            dump_btn.valign = Gtk.Align.CENTER;
            dump_btn.clicked.connect (() => on_dump_entry (entry));
            row.add_suffix (dump_btn);

            return row;
        }

        private string format_size (int64 bytes) {
            double size = bytes;
            string[] units = { "B", "KB", "MB", "GB", "TB" };
            int i = 0;
            while (size >= 1024.0 && i < units.length - 1) {
                size /= 1024.0;
                i++;
            }
            return "%.1f %s".printf (size, units[i]);
        }

        // --- Open: restore a single file to a temp dir, then launch it with the OS default app ---

        private void on_open_file (SnapshotEntry entry) {
            open_file_async.begin (entry);
        }

        private async void open_file_async (SnapshotEntry entry) {
            try {
                string temp_dir = DirUtils.make_tmp ("restic-gui-open-XXXXXX");
                string restored_path = yield app_ref.runner.restore_path (repo, target_snapshot.snapshot_id, entry.path, temp_dir);
                var file = File.new_for_path (restored_path);
                yield AppInfo.launch_default_for_uri_async (file.get_uri (), null, null);
            } catch (Error e) {
                show_toast (@"Couldn't open file: $(e.message)");
            }
        }

        // --- Restore: full restore of a file or folder to a user-chosen directory ---

        private void on_restore_entry (SnapshotEntry entry) {
            var dialog = new Gtk.FileDialog ();
            dialog.title = "Choose restore destination";
            dialog.select_folder.begin (window_ref, null, (obj, res) => {
                try {
                    var folder = dialog.select_folder.end (res);
                    if (folder == null) return;
                    string target = folder.get_path ();
                    show_toast (@"Restoring $(entry.name)…");
                    restore_entry_async.begin (entry, target);
                } catch (Gtk.DialogError.DISMISSED e) {
                    // User cancelled the folder picker — nothing to do.
                } catch (Error e) {
                    show_toast (@"Restore failed: $(e.message)");
                }
            });
        }

        private async void restore_entry_async (SnapshotEntry entry, string target) {
            try {
                yield app_ref.runner.restore_path (repo, target_snapshot.snapshot_id, entry.path, target);
                show_toast (@"Restored $(entry.name) to $(target) ✓");
            } catch (Error e) {
                show_toast (@"Restore failed: $(e.message)");
            }
        }

        private void on_restore_current_folder () {
            var fake_entry = new SnapshotEntry ();
            fake_entry.path = current_path;
            fake_entry.name = current_path == "/" ? "(whole snapshot)" : current_path.substring (current_path.last_index_of ("/") + 1);
            fake_entry.entry_type = "dir";
            on_restore_entry (fake_entry);
        }

        // --- Dump: write a file as-is, or a folder as a .zip, to a chosen file ---

        private void on_dump_entry (SnapshotEntry entry) {
            bool is_dir = entry.entry_type == "dir";
            var dialog = new Gtk.FileDialog ();
            dialog.title = is_dir ? "Save folder as zip" : "Save file";
            dialog.initial_name = is_dir ? @"$(entry.name).zip" : entry.name;

            dialog.save.begin (window_ref, null, (obj, res) => {
                try {
                    var file = dialog.save.end (res);
                    if (file == null) return;
                    string path = file.get_path ();
                    show_toast (@"Dumping $(entry.name)…");
                    dump_entry_async.begin (entry, path, is_dir);
                } catch (Gtk.DialogError.DISMISSED e) {
                    // User cancelled the save dialog — nothing to do.
                } catch (Error e) {
                    show_toast (@"Dump failed: $(e.message)");
                }
            });
        }

        private async void dump_entry_async (SnapshotEntry entry, string output_path, bool as_zip) {
            try {
                yield app_ref.runner.dump_path_to_file (repo, target_snapshot.snapshot_id, entry.path, output_path, as_zip);
                show_toast (@"Saved $(entry.name) to $(output_path) ✓");
            } catch (Error e) {
                show_toast (@"Dump failed: $(e.message)");
            }
        }

        private void on_dump_current_folder () {
            var fake_entry = new SnapshotEntry ();
            fake_entry.path = current_path;
            fake_entry.name = current_path == "/" ? "snapshot-root" : current_path.substring (current_path.last_index_of ("/") + 1);
            fake_entry.entry_type = "dir";
            on_dump_entry (fake_entry);
        }
    }
}
