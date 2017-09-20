foreach size: [ '16x16', '22x22', '24x24', '32x32', '48x48', 'scalable' ]
    suffix = 'png'
    if size == 'scalable'
        suffix = 'svg'
    endif
    install_data (join_paths ('icons', size , 'object-crop.' + suffix),
                  install_dir: join_paths (icondir, 'hicolor', size, 'actions'))
endforeach

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
