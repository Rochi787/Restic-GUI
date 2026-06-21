using Secret;

// NOTE: was "ResticGUI" (mismatched casing) — corrected to match the
// namespace used by every other file in the project (ResticGui); the
// mismatched version wouldn't resolve from callers elsewhere.
public class ResticGui.SecretManager : GLib.Object {

    // Define a clear schema identifier for the system keyring index
    private static Secret.Schema restic_schema;

    static construct {
        restic_schema = new Secret.Schema (
            "org.rochi.resticgui.Repository",
            Secret.SchemaFlags.NONE,
            "repo_id", Secret.SchemaAttributeType.STRING
        );
    }

    /**
     * Securely stores a backup repository password in the native system keyring.
     *
     * NOTE: Secret.password_store()'s attributes aren't passed as a
     * HashTable — the VAPI binds them as a null-terminated varargs list
     * of "key", value pairs after the cancellable argument, matching the
     * underlying secret_password_store_sync() C signature.
     */
    public async bool store_password (string repo_id, string password) {
        try {
            return yield Secret.password_store (
                restic_schema,
                Secret.COLLECTION_DEFAULT,
                "Restic Backup Vault: %s".printf (repo_id),
                password,
                null,
                "repo_id", repo_id
            );
        } catch (GLib.Error e) {
            critical ("Could not save password to keyring securely: %s", e.message);
            return false;
        }
    }

    /**
     * Look up a password securely without needing plain-text files.
     */
    public async string? lookup_password (string repo_id) {
        try {
            return yield Secret.password_lookup (
                restic_schema,
                null,
                "repo_id", repo_id
            );
        } catch (GLib.Error e) {
            warning ("Error looking up credentials from storage: %s", e.message);
            return null;
        }
    }

    /**
     * Purge stored data if the repository profile is deleted by the user.
     */
    public async bool clear_password (string repo_id) {
        try {
            return yield Secret.password_clear (
                restic_schema,
                null,
                "repo_id", repo_id
            );
        } catch (GLib.Error e) {
            warning ("Could not wipe clean password registry: %s", e.message);
            return false;
        }
    }
}
