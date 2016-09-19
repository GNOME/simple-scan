SUBDIRS = icons

desktopdir = $(datadir)/applications
desktop_in_files = simple-scan.desktop.in
desktop_DATA = $(desktop_in_files:.desktop.in=.desktop)

# Explicitly list the keywords to stop the icon field being translated
# https://bugs.launchpad.net/bugs/1624662
$(desktop_DATA): $(desktop_in_files)
	$(AM_V_GEN) $(MSGFMT) --desktop --keyword=Name --keyword=GenericName --keyword=Comment --keyword=Keywords --template $< -d $(top_srcdir)/po -o $@

gsettings_SCHEMAS = org.gnome.SimpleScan.gschema.xml
@GSETTINGS_RULES@

appstream_in_files = simple-scan.appdata.xml.in
appstream_XML = $(appstream_in_files:.appdata.xml.in=.appdata.xml)
@APPSTREAM_XML_RULES@

$(appstream_XML): $(appstream_in_files)
	$(AM_V_GEN) $(MSGFMT) --xml --template $< -d $(top_srcdir)/po -o $@

dist_man1_MANS = simple-scan.1

EXTRA_DIST = $(desktop_in_files)  \
             $(appstream_in_files) \
             $(gsettings_SCHEMAS) \
             simple-scan.ui \
             simple-scan.gresource.xml

DISTCLEANFILES = \
	$(desktop_DATA) \
	$(appstream_XML)
