resources = gnome.compile_resources ('resources', 'simple-scan.gresource.xml',
                                     source_dir: '.',
                                     c_name: 'resources')

vala_args = [ '--pkg=posix', '--vapidir=' + meson.current_source_dir () ]
dependencies = [ glib_dep, gtk_dep, zlib_dep, cairo_dep, gdk_pixbuf_dep, gusb_dep, sane_dep ]
if colord_dep.found ()
    vala_args += [ '-D', 'HAVE_COLORD' ]
    dependencies += colord_dep
endif
if packagekit_dep.found ()
    vala_args += [ '-D', 'HAVE_PACKAGEKIT' ]
    dependencies += packagekit_dep
endif

simple_scan = executable ('simple-scan',
                          [ 'config.vapi',
                            'book.vala',
                            'book-view.vala',
                            'page.vala',
                            'page-view.vala',
                            'simple-scan.vala',
                            'scanner.vala',
                            'ui.vala',
                            'autosave-manager.vala' ] + resources,
                          dependencies: dependencies,
                          vala_args: vala_args,
                          c_args: [ '-DVERSION="@0@"'.format (meson.project_version ()),
                                    '-DGETTEXT_PACKAGE="simple-scan"',
                                    '-DLOCALE_DIR="@0@"'.format (localedir),
                                    '-DICON_DIR="@0@"'.format (icondir),
                                    '-DI_KNOW_THE_PACKAGEKIT_GLIB2_API_IS_SUBJECT_TO_CHANGE' ],
                          link_args: [ '-lm' ],
                          install: true )
