install_data (join_paths ('icons', 'hicolor', 'scalable', '@0@.svg'.format(app_id)),
              install_dir: join_paths (datadir, 'icons', 'hicolor', 'scalable', 'apps'))

install_data (join_paths ('icons', 'hicolor', 'symbolic', '@0@-symbolic.svg'.format(app_id)),
              install_dir: join_paths (datadir, 'icons', 'hicolor', 'symbolic', 'apps'))

install_data ('org.gnome.SimpleScan.gschema.xml',
              install_dir: join_paths (datadir, 'glib-2.0', 'schemas'))
meson.add_install_script ('meson_compile_gschema.py')

i18n.merge_file (input: 'simple-scan.desktop.in',
                 output: 'simple-scan.desktop',
                 install: true,
                 install_dir: join_paths (datadir, 'applications'),
                 po_dir: '../po',
                 type: 'desktop')

appdata_file = i18n.merge_file (input: 'org.gnome.SimpleScan.appdata.xml.in',
                 output: 'org.gnome.SimpleScan.appdata.xml',
                 install: true,
                 install_dir: join_paths (datadir, 'metainfo'),
                 po_dir: '../po')

# Validate Appdata
appstreamcli = find_program('appstreamcli', required: false)
if appstreamcli.found()
  test('validate-appdata',
        appstreamcli,
        args: ['validate', '--no-net', '--explain', appdata_file.full_path()],
        depends: appdata_file)
endif

install_man ('simple-scan.1')

resource_files = files([
    'icons/scalable/actions/scan-type-adf-symbolic.svg',
    'icons/scalable/actions/scan-type-batch-symbolic.svg',
    'icons/scalable/actions/crop-symbolic.svg',
    'icons/scalable/actions/right-large-symbolic.svg',
    'icons/scalable/actions/interleave-before.svg',
    'icons/scalable/actions/interleave-after.svg',
    'icons/scalable/actions/interleave-reverse-after.svg',
    'icons/scalable/actions/reverse-before.svg',
    'icons/scalable/actions/reverse-after.svg',
    'icons/scalable/actions/flip-before.svg',
    'icons/scalable/actions/flip-even.svg',
    'icons/scalable/actions/flip-odd.svg',
    'ui/app-window.ui',
    'ui/authorize-dialog.ui',
    'ui/drivers-dialog.ui',
    'ui/help-overlay.ui',
    'ui/preferences-dialog.ui',
    'ui/reorder-pages-item.ui',
    'ui/reorder-pages-dialog.ui',
])
resources = gnome.compile_resources ('resources', 'simple-scan.gresource.xml',
                                     dependencies: resource_files,
                                     source_dir: '.',
                                     c_name: 'resources')
