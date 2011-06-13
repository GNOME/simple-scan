dnl Process this file with autoconf to produce a configure script.

AC_INIT(configure.ac)
AM_INIT_AUTOMAKE(simple-scan, 2.32.0.2)
AM_CONFIG_HEADER(config.h)
AM_MAINTAINER_MODE
GNOME_MAINTAINER_MODE_DEFINES
m4_ifdef([AM_SILENT_RULES],[AM_SILENT_RULES([yes])])

AC_ISC_POSIX
dnl should be 0.12.1
AM_PROG_VALAC([0.12.0])
AM_PROG_CC_C_O
AC_HEADER_STDC

GLIB_GSETTINGS

GNOME_COMPILE_WARNINGS(maximum)

dnl ###########################################################################
dnl Dependencies
dnl ###########################################################################

dnl Run-time dependencies:
dnl * gnome-icon-theme
dnl * xdg-utils (for xdg-email)

PKG_CHECK_MODULES(SIMPLE_SCAN, [
    gtk+-3.0
    gmodule-export-2.0
    gthread-2.0
    zlib
    cairo
    gdk-pixbuf-2.0
    cairo-pdf
    gudev-1.0
])

AC_CHECK_HEADERS([sane/sane.h],[],[AC_MSG_ERROR([SANE not found])])
AC_CHECK_HEADERS([sane/saneopts.h],[],[AC_MSG_ERROR([SANE not found])])
AC_CHECK_HEADERS([jpeglib.h],[],[AC_MSG_ERROR([libjpeg not found])])

dnl ###########################################################################
dnl Documentation
dnl ###########################################################################

GNOME_DOC_INIT

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
