install_data (join_paths ('icons', 'hicolor', 'scalable', '@0@.svg'.format(app_id)),
              install_dir: join_paths (datadir, 'icons', 'hicolor', 'scalable', 'apps'))

install_data (join_paths ('icons', 'hicolor', 'symbolic', '@0@-symbolic.svg'.format(app_id)),
              install_dir: join_paths (datadir, 'icons', 'hicolor', 'symbolic', 'apps'))

install_data ('org.gnome.SimpleScan.gschema.xml',
              install_dir: join_paths (datadir, 'glib-2.0', 'schemas'))
meson.add_install_script ('meson_compile_gschema.py')

i18n.merge_file ('desktop-file',
                 input: 'simple-scan.desktop.in',
                 output: 'simple-scan.desktop',
                 install: true,
                 install_dir: join_paths (datadir, 'applications'),
                 po_dir: '../po',
                 type: 'desktop')

i18n.merge_file ('appdata-file',
                 input: 'simple-scan.appdata.xml.in',
                 output: 'simple-scan.appdata.xml',
                 install: true,
                 install_dir: join_paths (datadir, 'metainfo'),
                 po_dir: '../po')

install_man ('simple-scan.1')

icon_dir = 'icons/scalable/actions'
resource_files = files([
    icon_dir / 'scan-type-adf-symbolic.svg',
    icon_dir / 'scan-type-batch-symbolic.svg',
    'ui/app-window.ui',
    'ui/authorize-dialog.ui',
    'ui/help-overlay.ui',
    'ui/preferences-dialog.ui',
])
resources = gnome.compile_resources ('resources', 'simple-scan.gresource.xml',
                                     dependencies: resource_files,
                                     source_dir: '.',
                                     c_name: 'resources')
