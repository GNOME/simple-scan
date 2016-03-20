dnl Process this file with autoconf to produce a configure script.

AC_INIT(simple-scan, 3.20.0)
AM_INIT_AUTOMAKE([1.11 no-dist-gzip dist-xz foreign])
AM_SILENT_RULES([yes])
AM_MAINTAINER_MODE
AC_CONFIG_MACRO_DIR([m4])

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
    gusb
])

AC_ARG_ENABLE([colord],
    AS_HELP_STRING([--enable-colord],
                   [Enable colord support[[default=auto]]]),
    [enable_colord=$enableval],
    [enable_colord=auto])
have_colord=no
if test x"$enable_colord" != "xno"; then
    PKG_CHECK_MODULES(COLORD, [
        colord
    ],
    [have_colord=yes],
    [if test x"$enable_colord" = xauto; then
        AC_MSG_FAILURE([--enable-colord was given, but could not be found])
     fi
    ])
fi
AM_CONDITIONAL(HAVE_COLORD, test $have_colord = yes)

AC_ARG_ENABLE([packagekit],
    AS_HELP_STRING([--enable-packagekit],
                   [Enable packagekit support[[default=auto]]]),
    [enable_packagekit=$enableval],
    [enable_packagekit=auto])
have_packagekit=no
if test x"$enable_packagekit" != "xno"; then
    PKG_CHECK_MODULES(PACKAGEKIT, [
        packagekit-glib2
    ],
    [have_packagekit=yes],
    [if test x"$enable_packagekit" = xauto; then
        AC_MSG_FAILURE([--enable-packagekit was given, but could not be found])
     fi
    ])
fi    
AM_CONDITIONAL(HAVE_PACKAGEKIT, test $have_packagekit = yes)

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
data/appdata/Makefile
data/icons/Makefile
help/Makefile
po/Makefile.in
src/Makefile
])

dnl ###########################################################################
dnl Summary
dnl ###########################################################################

echo "
                    Simple Scan $VERSION
                    ====================

        prefix:                   $prefix
        PackageKit support:       $have_packagekit
        Color management:         $have_colord
"
