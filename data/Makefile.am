uidir = $(datadir)/simple-scan
ui_DATA = simple-scan.ui
	
utilitiesdir = $(datadir)/applications
utilities_DATA = simple-scan.desktop

schemadir = @GCONF_SCHEMA_FILE_DIR@
schema_in_files = simple-scan.schemas.in
schema_DATA = $(schema_in_files:.schemas.in=.schemas)
@INTLTOOL_SCHEMAS_RULE@

EXTRA_DIST = $(ui_DATA) $(utilities_DATA) $(schema_in_files)

DISTCLEANFILES = $(schema_DATA)
