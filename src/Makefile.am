bin_PROGRAMS = simple-scan

simple_scan_SOURCES = \
	config.vapi \
	book.vala \
	book-view.vala \
	page.vala \
	page-view.vala \
	sane.vapi \
	simple-scan.vala \
	simple-scan.vapi \
	scanner.vala \
	ui.vala

simple_scan_VALAFLAGS = \
	--pkg=zlib \
	--pkg=gudev-1.0 \
	--pkg=gio-2.0 \
	--pkg=gconf-2.0 \
	--pkg=gtk+-2.0 

simple_scan_CFLAGS = \
	$(SIMPLE_SCAN_CFLAGS) \
	$(WARN_CFLAGS) \
	-DVERSION=\"$(VERSION)\" \
	-DGETTEXT_PACKAGE=\"$(GETTEXT_PACKAGE)\" \
	-DLOCALE_DIR=\"$(localedir)\" \
	-DUI_DIR=\"$(datadir)/simple-scan/\" \
	-DICON_DIR=\"$(datadir)/simple-scan/icons\" \
	-DGCONF_DIR=\"/apps/simple-scan\" \
	-DSIMPLE_SCAN_BINARY=\"simple-scan\"

simple_scan_LDADD = \
	$(SIMPLE_SCAN_LIBS) \
	-lsane \
	-ljpeg \
	-lm

CLEANFILES = \
	$(patsubst %.vala,%.c,$(filter %.vala, $(SOURCES))) \
	*_vala.stamp

DISTCLEANFILES = \
	Makefile.in
