bin_PROGRAMS = simple-scan

simple_scan_SOURCES = \
	book.c \
	book.h \
	book-view.c \
	book-view.h \
	page.c \
	page.h \
	page-view.c \
	page-view.h \
	simple-scan.c \
	scanner.c \
	scanner.h \
	ui.c \
	ui.h

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
	-lm

DISTCLEANFILES = \
	Makefile.in
