bin_PROGRAMS = simple-scan

resources.c: $(top_srcdir)/data/simple-scan.gresource.xml $(shell $(GLIB_COMPILE_RESOURCES) --generate-dependencies --sourcedir=$(top_srcdir)/data/ $(top_srcdir)/data/simple-scan.gresource.xml)
	$(AM_V_GEN) $(GLIB_COMPILE_RESOURCES) --target=$@ --sourcedir=$(top_srcdir)/data/ --generate-source $<

simple_scan_SOURCES = \
	config.vapi \
	book.vala \
	book-view.vala \
	colord.vapi \
	page.vala \
	page-view.vala \
	sane.vapi \
	simple-scan.vala \
	scanner.vala \
	ui.vala \
	autosave-manager.vala \
	resources.c

simple_scan_VALAFLAGS = \
	--pkg=zlib \
	--pkg=gudev-1.0 \
	--pkg=gio-2.0 \
	--pkg=gtk+-3.0 \
	--gresources=$(top_srcdir)/data/simple-scan.gresource.xml \
	--debug \
	--target-glib 2.38

if HAVE_COLORD
simple_scan_VALAFLAGS += -D HAVE_COLORD
endif

simple_scan_CFLAGS = \
	-w \
	$(SIMPLE_SCAN_CFLAGS) \
	$(COLORD_CFLAGS) \
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
	$(COLORD_LIBS) \
	-lsane \
	-lm

CLEANFILES = \
	$(patsubst %.vala,%.c,$(filter %.vala, $(SOURCES))) \
	resources.c \
	*_vala.stamp

DISTCLEANFILES = \
	Makefile.in
