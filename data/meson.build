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

# Note the keywords explicitly listed to stop the icon field being translated
# https://bugs.launchpad.net/bugs/1624662
custom_target ('simple-scan.desktop',
               output: 'simple-scan.desktop',
               input: 'simple-scan.desktop.in',
               command: [ msgfmt, '--desktop', '--keyword=Name', '--keyword=GenericName', '--keyword=Comment', '--keyword=Keywords', '--template', '@INPUT@', '-d', podir, '-o', '@OUTPUT@' ],
               install: true,
               install_dir: join_paths (datadir, 'applications'))

custom_target ('simple-scan.appdata.xml',
               output: 'simple-scan.appdata.xml',
               input: 'simple-scan.appdata.xml.in',
               command: [ msgfmt, '--xml', '--template', '@INPUT@', '-d', podir, '-o', '@OUTPUT@' ],
               install: true,
               install_dir: join_paths (datadir, 'appdata'))

install_man ('simple-scan.1')
