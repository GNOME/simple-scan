bin_PROGRAMS = simple-scan

simple_scan_SOURCES = \
	simple-scan.c \
	scanner.c \
	scanner.h \
	ui.c \
	ui.h
	
simple_scan_CFLAGS = \
	$(SIMPLE_SCAN_CFLAGS) \
	-DUI_DIR=\"$(datadir)/simple-scan/\"

simple_scan_LDADD = \
	$(SIMPLE_SCAN_LIBS) \
	-lsane
