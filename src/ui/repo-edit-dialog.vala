namespace ResticGui {

    public class RepoEditDialog : Adw.Dialog {

        public signal void saved (Repository repo);

        private Repository repo;
        private bool is_new;

        private Adw.EntryRow name_row;
        private Adw.ComboRow backend_row;
        private Adw.EntryRow location_row;
        private Adw.EntryRow password_row;

        // Backend-specific credential rows, shown/hidden based on backend.
        private Adw.EntryRow aws_key_row;
        private Adw.EntryRow aws_secret_row;
        private Adw.EntryRow b2_id_row;
        private Adw.EntryRow b2_key_row;
        private Adw.PreferencesGroup creds_group;

        public RepoEditDialog (Repository? existing) {
            is_new = existing == null;
            repo = existing ?? new Repository ();
            if (is_new) {
                repo.id = GLib.Uuid.string_random ();
            }

            title = is_new ? "Add Repository" : "Edit Repository";
            content_width = 480;
            content_height = 560;

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

            var basics_group = new Adw.PreferencesGroup ();

            name_row = new Adw.EntryRow ();
            name_row.title = "Name";
            name_row.text = repo.name;
            basics_group.add (name_row);

            backend_row = new Adw.ComboRow ();
            backend_row.title = "Backend";
            var model = new Gtk.StringList (new string[] {
                BackendType.LOCAL.label (),
                BackendType.SFTP.label (),
                BackendType.S3.label (),
                BackendType.B2.label (),
                BackendType.REST_SERVER.label (),
            });
            backend_row.model = model;
            backend_row.selected = backend_to_index (repo.backend);
            backend_row.notify["selected"].connect (() => update_creds_visibility ());
            basics_group.add (backend_row);

            location_row = new Adw.EntryRow ();
            location_row.title = "Location";
            location_row.text = repo.location;
            basics_group.add (location_row);

            password_row = new Adw.EntryRow ();
            password_row.title = "Repository Password";
            password_row.set_input_purpose (Gtk.InputPurpose.PASSWORD);
            // EntryRow doesn't natively hide text without extra work; using visibility toggle icon.
            password_row.text = repo.password;
            basics_group.add (password_row);

            box.append (basics_group);

            // Hint row explaining location format per backend.
            var hint_label = new Gtk.Label (location_hint_text (repo.backend));
            hint_label.wrap = true;
            hint_label.css_classes = { "dim-label", "caption" };
            hint_label.halign = Gtk.Align.START;
            box.append (hint_label);
            backend_row.notify["selected"].connect (() => {
                hint_label.label = location_hint_text (index_to_backend (backend_row.selected));
            });

            creds_group = new Adw.PreferencesGroup ();
            creds_group.title = "Backend Credentials";

            aws_key_row = new Adw.EntryRow ();
            aws_key_row.title = "AWS_ACCESS_KEY_ID";
            aws_key_row.text = repo.env_vars.get ("AWS_ACCESS_KEY_ID") ?? "";
            creds_group.add (aws_key_row);

            aws_secret_row = new Adw.EntryRow ();
            aws_secret_row.title = "AWS_SECRET_ACCESS_KEY";
            aws_secret_row.set_input_purpose (Gtk.InputPurpose.PASSWORD);
            aws_secret_row.text = repo.env_vars.get ("AWS_SECRET_ACCESS_KEY") ?? "";
            creds_group.add (aws_secret_row);

            b2_id_row = new Adw.EntryRow ();
            b2_id_row.title = "B2_ACCOUNT_ID";
            b2_id_row.text = repo.env_vars.get ("B2_ACCOUNT_ID") ?? "";
            creds_group.add (b2_id_row);

            b2_key_row = new Adw.EntryRow ();
            b2_key_row.title = "B2_ACCOUNT_KEY";
            b2_key_row.set_input_purpose (Gtk.InputPurpose.PASSWORD);
            b2_key_row.text = repo.env_vars.get ("B2_ACCOUNT_KEY") ?? "";
            creds_group.add (b2_key_row);

            box.append (creds_group);
            update_creds_visibility ();

            scroller.child = box;
            toolbar_view.content = scroller;
            child = toolbar_view;
        }

        private void update_creds_visibility () {
            var backend = index_to_backend (backend_row.selected);
            bool show_aws = backend == BackendType.S3;
            bool show_b2 = backend == BackendType.B2;
            aws_key_row.visible = show_aws;
            aws_secret_row.visible = show_aws;
            b2_id_row.visible = show_b2;
            b2_key_row.visible = show_b2;
            creds_group.visible = show_aws || show_b2;
        }

        private string location_hint_text (BackendType backend) {
            switch (backend) {
                case BackendType.LOCAL:
                    return "e.g. /mnt/backups/myrepo";
                case BackendType.SFTP:
                    return "e.g. sftp:user@host:/path/to/repo";
                case BackendType.S3:
                    return "e.g. s3:https://s3.amazonaws.com/bucket-name/path";
                case BackendType.B2:
                    return "e.g. b2:bucket-name:path";
                case BackendType.REST_SERVER:
                    return "e.g. rest:https://user:pass@host:8000/repo";
                default:
                    return "";
            }
        }

        private static uint backend_to_index (BackendType b) {
            switch (b) {
                case BackendType.LOCAL: return 0;
                case BackendType.SFTP: return 1;
                case BackendType.S3: return 2;
                case BackendType.B2: return 3;
                case BackendType.REST_SERVER: return 4;
                default: return 0;
            }
        }

        private static BackendType index_to_backend (uint i) {
            switch (i) {
                case 1: return BackendType.SFTP;
                case 2: return BackendType.S3;
                case 3: return BackendType.B2;
                case 4: return BackendType.REST_SERVER;
                default: return BackendType.LOCAL;
            }
        }

        private void on_save () {
            repo.name = name_row.text;
            repo.backend = index_to_backend (backend_row.selected);
            repo.location = location_row.text;
            repo.password = password_row.text;

            if (repo.backend == BackendType.S3) {
                repo.env_vars.set ("AWS_ACCESS_KEY_ID", aws_key_row.text);
                repo.env_vars.set ("AWS_SECRET_ACCESS_KEY", aws_secret_row.text);
            } else if (repo.backend == BackendType.B2) {
                repo.env_vars.set ("B2_ACCOUNT_ID", b2_id_row.text);
                repo.env_vars.set ("B2_ACCOUNT_KEY", b2_key_row.text);
            }

            saved (repo);
            close ();
        }
    }
}
