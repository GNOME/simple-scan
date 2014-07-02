SUBDIRS = icons

desktopdir = $(datadir)/applications
desktop_DATA = simple-scan.desktop
@INTLTOOL_DESKTOP_RULE@

appdatadir = $(datadir)/appdata
dist_appdata_DATA = simple-scan.appdata.xml

gsettings_SCHEMAS = org.gnome.SimpleScan.gschema.xml
@INTLTOOL_XML_NOMERGE_RULE@
@GSETTINGS_RULES@

dist_man1_MANS = simple-scan.1

EXTRA_DIST = simple-scan.desktop.in \
             org.gnome.SimpleScan.gschema.xml.in \
             simple-scan.ui \
             simple-scan.gresource.xml

DISTCLEANFILES = \
	Makefile.in \
	$(schema_DATA) \
	$(desktop_DATA) \
	$(gsettings_SCHEMAS)
