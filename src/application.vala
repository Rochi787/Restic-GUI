namespace ResticGui {

    public class Application : Adw.Application {

        public RepoStore repo_store;
        public JobStore job_store;
        public ResticRunner runner;
        public CronManager cron_manager;
        public SystemdManager systemd_manager;
        public WindowsTaskScheduler windows_task_scheduler;
        public SchedulerPrefs scheduler_prefs;

        public Application () {
            Object (
                application_id: "za.co.rochi.resticgui",
                flags: ApplicationFlags.DEFAULT_FLAGS
            );
        }

        protected override void activate () {
            repo_store = new RepoStore ();
            job_store = new JobStore ();
            runner = new ResticRunner ();
            cron_manager = new CronManager ();
            systemd_manager = new SystemdManager ();
            windows_task_scheduler = new WindowsTaskScheduler ();
            scheduler_prefs = new SchedulerPrefs ();

            var window = new MainWindow (this);
            window.present ();
        }
    }
}
