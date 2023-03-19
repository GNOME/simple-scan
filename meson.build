project ('simple-scan', ['vala', 'c'],
         version: '44.0',
         license: 'GPLv3+',
         default_options: [
             'warning_level=1',
             'buildtype=debugoptimized',
         ],
         meson_version: '>= 0.40.0')

gnome = import ('gnome')
i18n = import ('i18n')

app_id = 'org.gnome.SimpleScan'

# Paths
mandir = join_paths (get_option ('prefix'), get_option ('mandir'))
localedir = join_paths (get_option ('prefix'), get_option ('localedir'))
datadir = join_paths (get_option ('prefix'), get_option ('datadir'))
icondir = join_paths (datadir, 'simple-scan', 'icons')

# Dependencies
glib_dep = dependency ('glib-2.0', version: '>= 2.38')
gtk_dep = dependency ('gtk+-3.0', version: '>=3.24')
gmodule_dep = dependency ('gmodule-export-2.0')
gthread_dep = dependency ('gthread-2.0')
libhandy_dep = dependency ('libhandy-1', version: '>= 1.6.0', required: false)
zlib_dep = dependency ('zlib')
cairo_dep = dependency ('cairo')
gdk_pixbuf_dep = dependency ('gdk-pixbuf-2.0')
gusb_dep = dependency ('gusb', version: '>= 0.2.7')
colord_dep = dependency ('colord', required: false)
packagekit_dep = dependency ('packagekit-glib2', version: '>= 1.1.5', required: false)
webp_dep = dependency ('libwebp', required: false)
webpmux_dep = dependency ('libwebpmux', required: false)
sane_dep = dependency ('sane-backends')
msgfmt = find_program  ('msgfmt')
itstool = find_program  ('itstool')

libhandy_subproj = libhandy_dep
if not libhandy_dep.found()
  libhandy_subproj = subproject(
    'libhandy',
    default_options: [
      'examples=false',
      'glade_catalog=disabled',
      'tests=false',
    ]
  )

  # When using libhandy as subproject, make sure we get the VAPI file
  libhandy_dep = declare_dependency(
    dependencies: [
      libhandy_subproj.get_variable('libhandy_dep'),
      libhandy_subproj.get_variable('libhandy_vapi'),
    ]
  )
endif

subdir ('po')
subdir ('data')
subdir ('help')
subdir ('src')
