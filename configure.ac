dnl Process this file with autoconf to produce a configure script.

AC_INIT(configure.ac)
AM_INIT_AUTOMAKE(simple-scan, 1.0.0)
AM_MAINTAINER_MODE
GNOME_MAINTAINER_MODE_DEFINES
m4_ifdef([AM_SILENT_RULES],[AM_SILENT_RULES([yes])])

AC_ISC_POSIX
AC_PROG_CC_C_O
AM_PROG_CC_STDC
AC_HEADER_STDC

AM_GCONF_SOURCE_2

GNOME_COMPILE_WARNINGS(yes)

dnl ###########################################################################
dnl Dependencies
dnl ###########################################################################

dnl Run-time dependencies:
dnl * gnome-icon-theme
dnl * xdg-utils (for xdg-email)

PKG_CHECK_MODULES(SIMPLE_SCAN, [
    gtk+-2.0
    gconf-2.0
    gmodule-export-2.0
    gthread-2.0
    cairo
    gdk-pixbuf-2.0
    cairo-pdf
    dbus-glib-1
    gudev-1.0
])

AC_CHECK_HEADERS([sane/sane.h],[],[AC_MSG_ERROR([SANE not found])])
AC_CHECK_HEADERS([sane/saneopts.h],[],[AC_MSG_ERROR([SANE not found])])

dnl ###########################################################################
dnl Documentation
dnl ###########################################################################

GNOME_DOC_INIT

dnl ###########################################################################
dnl Internationalization
dnl ###########################################################################

IT_PROG_INTLTOOL([0.35.0])
GETTEXT_PACKAGE=simple-scan
AC_SUBST(GETTEXT_PACKAGE)
AM_GLIB_GNU_GETTEXT

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
