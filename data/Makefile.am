SUBDIRS = icons

utilitiesdir = $(datadir)/applications
utilities_in_files = simple-scan.desktop.in
utilities_DATA = $(utilities_in_files:.desktop.in=.desktop)
@INTLTOOL_DESKTOP_RULE@

gsettings_SCHEMAS = org.gnome.SimpleScan.gschema.xml
@INTLTOOL_XML_NOMERGE_RULE@
@GSETTINGS_RULES@

man1_MANS = simple-scan.1

EXTRA_DIST = $(ui_DATA) $(utilities_in_files) org.gnome.SimpleScan.gschema.xml.in $(man1_MANS)

DISTCLEANFILES = \
	Makefile.in \
	simple-scan.ui \
	simple-scan.gresource.xml \
	$(schema_DATA) \
	$(utilities_DATA) \
	$(gsettings_SCHEMAS)
