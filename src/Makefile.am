bin_PROGRAMS = simple-scan

simple_scan_SOURCES = \
	book.c \
	book.h \
	page.c \
	page.h \       
	simple-scan.c \
	scanner.c \
	scanner.h \
	ui.c \
	ui.h
	
simple_scan_CFLAGS = \
	$(SIMPLE_SCAN_CFLAGS) \
	-DVERSION=\"$(VERSION)\" \
	-DUI_DIR=\"$(datadir)/simple-scan/\" \
	-DSIMPLE_SCAN_BINARY=\"simple-scan\"

simple_scan_LDADD = \
	$(SIMPLE_SCAN_LIBS) \
	-lsane
