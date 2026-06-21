project('restic-gui', ['vala', 'c'],
  version: '0.1.0',
  meson_version: '>= 0.59.0'
)

gnome = import('gnome')

dependencies = [
  dependency('glib-2.0'),
  dependency('gobject-2.0'),
  dependency('gio-2.0'),
  dependency('gtk4'),
  dependency('libadwaita-1'),
  dependency('json-glib-1.0'),
  dependency('libsecret-1') 
]

sources = files(
  'src/main.vala',
  'src/application.vala',
  'src/models/repository.vala',
  'src/models/backup-job.vala',
  'src/models/snapshot.vala',
  'src/services/restic-runner.vala',
  'src/services/repo-store.vala',
  'src/services/job-store.vala',
  'src/services/cron-manager.vala',
  'src/services/systemd-manager.vala',
  'src/services/windows-task-scheduler.vala',
  'src/services/scheduler-prefs.vala',
  'src/services/secret-manager.vala',
  'src/ui/window.vala',
  'src/ui/repos-page.vala',
  'src/ui/repo-edit-dialog.vala',
  'src/ui/jobs-page.vala',
  'src/ui/job-edit-dialog.vala',
  'src/ui/snapshots-page.vala',
)

executable('restic-gui',
  sources,
  dependencies: dependencies,
  install: true,
)
