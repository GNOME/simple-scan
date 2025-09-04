project ('simple-scan', ['vala', 'c'],
         version: '49.0',
         license: 'GPLv3+',
         default_options: [
             'warning_level=1',
             'buildtype=debugoptimized',
         ],
         meson_version: '>= 0.57.0')

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
gtk_dep = dependency ('gtk4', version: '>=4.10.0')
gmodule_dep = dependency ('gmodule-export-2.0')
gthread_dep = dependency ('gthread-2.0')
libadwaita_dep = dependency('libadwaita-1', version: '>= 1.2.0')
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

subdir ('po')
subdir ('data')
subdir ('help')
subdir ('src')
