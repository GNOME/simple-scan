bin_PROGRAMS = simple-scan

resources.c: $(top_srcdir)/data/simple-scan.gresource.xml $(shell $(GLIB_COMPILE_RESOURCES) --generate-dependencies --sourcedir=$(top_srcdir)/data/ $(top_srcdir)/data/simple-scan.gresource.xml)
	$(AM_V_GEN) $(GLIB_COMPILE_RESOURCES) --target=$@ --sourcedir=$(top_srcdir)/data/ --generate-source $<

simple_scan_SOURCES = \
	config.vapi \
	book.vala \
	book-view.vala \
	colord.vapi \
	fixes.vapi \
	packagekit-glib2.vapi \
	page.vala \
	page-view.vala \
	sane.vapi \
	simple-scan.vala \
	scanner.vala \
	ui.vala \
	autosave-manager.vala \
	resources.c

simple_scan_VALAFLAGS = \
	--pkg=posix \
	--pkg=zlib \
	--pkg=gusb \
	--pkg=gio-2.0 \
	--pkg=gtk+-3.0 \
	--gresources=$(top_srcdir)/data/simple-scan.gresource.xml \
	--debug \
	--target-glib 2.38

if HAVE_COLORD
simple_scan_VALAFLAGS += -D HAVE_COLORD
endif

if HAVE_PACKAGEKIT
simple_scan_VALAFLAGS += -D HAVE_PACKAGEKIT
endif

simple_scan_CFLAGS = \
	-w \
	$(SIMPLE_SCAN_CFLAGS) \
	$(COLORD_CFLAGS) \
	$(PACKAGEKIT_CFLAGS) \    
	$(WARN_CFLAGS) \
	-DVERSION=\"$(VERSION)\" \
	-DGETTEXT_PACKAGE=\"$(GETTEXT_PACKAGE)\" \
	-DLOCALE_DIR=\"$(localedir)\" \
	-DUI_DIR=\"$(datadir)/simple-scan/\" \
	-DICON_DIR=\"$(datadir)/simple-scan/icons\" \
	-DGCONF_DIR=\"/apps/simple-scan\" \
	-DSIMPLE_SCAN_BINARY=\"simple-scan\" \
	-DI_KNOW_THE_PACKAGEKIT_GLIB2_API_IS_SUBJECT_TO_CHANGE

simple_scan_LDADD = \
	$(SIMPLE_SCAN_LIBS) \
	$(COLORD_LIBS) \
	$(PACKAGEKIT_LIBS) \    
	-lsane \
	-lm

CLEANFILES = \
	$(patsubst %.vala,%.c,$(filter %.vala, $(SOURCES))) \
	resources.c \
	*_vala.stamp
