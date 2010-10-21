include $(top_srcdir)/gnome-doc-utils.make

dist-hook: doc-dist-hook

DOC_ID = simple-scan
DOC_INCLUDES = legal.xml
DOC_FIGURES =
DOC_PAGES = index.page \
            adf.page \
            crop.page \
            dpi.page \
            email.page \
            print.page \
            reorder.page \
            rotate.page \
            save.page \
            scanner.page \
            scanning.page

DOC_LINGUAS =

DISTCLEANFILES = \
	Makefile.in

REAL_LINGUAS = de

DOC_LINGUAS = POT $(REAL_LINGUAS)

$(_DOC_LC_DOCS) : po.stamp

po.stamp: $(wildcard translations/*.po)
	for p in $?; do $(mkdir_p) $$(basename $$p .po)/; \
	cp -a $$p $$(basename $$p .po)/; done
	touch $@
    
update-pot: translations/simple-scan-help.pot
POT/POT.po: $(foreach page,$(DOC_PAGES),C/$(page))
translations/simple-scan-help.pot: POT/POT.po
	$(mkdir_p) $(dir $@)
	sed 's|^#: /.*/\(.*\)|#: \1|g' $^ > $@

dist-hook: doc-dist-hook

EXTRA_DIST = translations po.stamp
DISTCLEANFILES = translations/simple-scan-help.pot

.PHONY: update-pot
