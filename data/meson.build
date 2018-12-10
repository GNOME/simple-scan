install_data ('org.gnome.SimpleScan.gschema.xml',
              install_dir: join_paths (datadir, 'glib-2.0', 'schemas'))
meson.add_install_script ('meson_compile_gschema.py')

i18n.merge_file ('desktop-file',
                 input: 'org.gnome.SimpleScan.desktop.in',
                 output: 'org.gnome.SimpleScan.desktop',
                 install: true,
                 install_dir: join_paths (datadir, 'applications'),
                 po_dir: '../po',
                 type: 'desktop')

i18n.merge_file ('appdata-file',
                 input: 'org.gnome.SimpleScan.appdata.xml.in',
                 output: 'org.gnome.SimpleScan.appdata.xml',
                 install: true,
                 install_dir: join_paths (datadir, 'metainfo'),
                 po_dir: '../po')

install_man ('simple-scan.1')
