dnl Process this file with autoconf to produce a configure script.

AC_INIT(simple-scan, 3.14.0)
AM_INIT_AUTOMAKE([1.11 no-dist-gzip dist-xz foreign])
AM_SILENT_RULES([yes])
AM_MAINTAINER_MODE
GNOME_MAINTAINER_MODE_DEFINES

AM_PROG_VALAC([0.22.0], [], [AC_MSG_ERROR([Vala compiler not found])])
AM_PROG_CC_C_O

GLIB_GSETTINGS
AC_PATH_PROG(GLIB_COMPILE_RESOURCES, glib-compile-resources)

dnl ###########################################################################
dnl Dependencies
dnl ###########################################################################

dnl Run-time dependencies:
dnl * gnome-icon-theme
dnl * xdg-utils (for xdg-email)

PKG_CHECK_MODULES(SIMPLE_SCAN, [
    glib-2.0 >= 2.32
    gtk+-3.0
    gmodule-export-2.0
    gthread-2.0
    zlib
    cairo
    gdk-pixbuf-2.0
    gudev-1.0
])

PKG_CHECK_MODULES(COLORD, [
    colord
], have_colord=yes, have_colord=no)
AM_CONDITIONAL(HAVE_COLORD, test $have_colord = yes)

AC_CHECK_HEADERS([sane/sane.h],[],[AC_MSG_ERROR([SANE not found])])
AC_CHECK_HEADERS([sane/saneopts.h],[],[AC_MSG_ERROR([SANE not found])])

dnl ###########################################################################
dnl Documentation
dnl ###########################################################################

YELP_HELP_INIT

dnl ###########################################################################
dnl Internationalization
dnl ###########################################################################

IT_PROG_INTLTOOL([0.35.0])
AC_SUBST(GETTEXT_PACKAGE, simple-scan)

dnl ###########################################################################
dnl Files to generate
dnl ###########################################################################

AC_OUTPUT([
Makefile
data/Makefile
data/icons/Makefile
help/Makefile
po/Makefile.in
src/Makefile
])
