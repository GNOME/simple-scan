SUBDIRS = icons

desktopdir = $(datadir)/applications
desktop_DATA = simple-scan.desktop
@INTLTOOL_DESKTOP_RULE@

appdatadir = $(datadir)/appdata
appdata_DATA = simple-scan.appdata.xml
@INTLTOOL_XML_RULE@

gsettings_SCHEMAS = org.gnome.SimpleScan.gschema.xml
@GSETTINGS_RULES@

dist_man1_MANS = simple-scan.1

EXTRA_DIST = simple-scan.desktop.in \
             simple-scan.appdata.xml.in \
             org.gnome.SimpleScan.gschema.xml.in \
             simple-scan.ui \
             simple-scan.gresource.xml

DISTCLEANFILES = \
	Makefile.in \
	$(schema_DATA) \
	$(desktop_DATA) \
	$(appdata_DATA) \
	$(gsettings_SCHEMAS)
