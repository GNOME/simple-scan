uidir = $(datadir)/simple-scan
ui_DATA = simple-scan.ui

utilitiesdir = $(datadir)/applications
utilities_in_files = simple-scan.desktop.in
utilities_DATA = $(utilities_in_files:.desktop.in=.desktop)
@INTLTOOL_DESKTOP_RULE@

schemadir = @GCONF_SCHEMA_FILE_DIR@
schema_in_files = simple-scan.schemas.in
schema_DATA = $(schema_in_files:.schemas.in=.schemas)
@INTLTOOL_SCHEMAS_RULE@

man1_MANS = simple-scan.1

EXTRA_DIST = $(ui_DATA) $(utilities_in_files) $(schema_in_files) $(man1_MANS)

DISTCLEANFILES = $(schema_DATA) $(utilities_DATA)
