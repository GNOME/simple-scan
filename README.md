[![Build Status](https://gitlab.gnome.org/GNOME/simple-scan/badges/master/build.svg)](https://gitlab.gnome.org/GNOME/simple-scan/pipelines)
[![License](https://img.shields.io/badge/License-GPL%20v3-blue.svg)](https://gitlab.gnome.org/GNOME/simple-scan/blob/master/COPYING)

# Introduction

*Document Scanner* is a document scanning application for [GNOME](https://www.gnome.org/)
It allows you to capture images using [image scanners](https://en.wikipedia.org/wiki/Image_scanner)
(e.g. flatbed scanners) that have suitable [SANE drivers](http://sane-project.org/) installed.

# Building from source

Install the dependencies

For Ubuntu/Debian:
```
$ sudo apt install git meson valac libgtk-3-dev libgusb-dev libcolord-dev libpackagekit-glib2-dev libwebp-dev libsane-dev gettext itstool
```

For Fedora:
```
$ sudo dnf install -y meson vala gettext itstool gtk3-devel libgusb-devel colord-devel PackageKit-glib-devel libwebp-devel sane-backends-devel
```

For Arch Linux:
```
sudo pacman -S meson vala gettext itstool gtk3 libusb colord libpackagekit-glib libwebp sane
```

Get the source:
```
$ git clone https://gitlab.gnome.org/GNOME/simple-scan.git
$ cd simple-scan
```

Build and run:
```
$ meson --prefix $PWD/_install _build
$ ninja -C _build all install
$ XDG_DATA_DIRS=_install/share:$XDG_DATA_DIRS ./_install/bin/simple-scan
```

# Debugging

There is a `--debug` command line switch to enable more verbose logging:
```
$ simple-scan --debug
```

Log messages can also be found in the `$HOME/.cache/simple-scan` folder.

If you don't have a scanner ready, you can use a virtual `test` scanner:
```
$ simple-scan --debug test
```

This app works by using the [SANE API](http://sane-project.org/html/) to
capture images. It chooses the settings it thinks are appropriate for what you
are trying to do. Drivers have many options and are of differing quality - it
is useful to work out if any issues are caused by the app or the drivers. To
confirm it is a driver issue you can use the graphical tool (XSane) or the
command line
[scanimage](http://www.sane-project.org/man/scanimage.1.html) provided
by the SANE project - these allow to to easily see and control all the
settings your driver provides.

If XSane is also not working, then the issue could be caused by wrongly
loaded backend. To enable debug traces on Sane, set `SANE_DEBUG_DLL`
environment variable:

```
$ export SANE_DEBUG_DLL=255
```

When set, SANE backends will show informational messages while
*Document Scanner* is running

Example:

With HP MFP 135a scanner, there is missing `libusb-0.1.so.4`
shared library, during loading `smfp` prioprietary backend:

```
[dll] sane_get_devices
[dll] load: searching backend `smfp' in `/usr/lib/x86_64-linux-gnu/sane:/usr/lib/sane'
[dll] load: trying to load `/usr/lib/x86_64-linux-gnu/sane/libsane-smfp.so.1'
[dll] load: couldn't open `/usr/lib/x86_64-linux-gnu/sane/libsane-smfp.so.1' (No such file or directory)
[dll] load: trying to load `/usr/lib/sane/libsane-smfp.so.1'
[dll] load: dlopen()ing `/usr/lib/sane/libsane-smfp.so.1'
[dll] load: dlopen() failed (libusb-0.1.so.4: No such file or directory)
```

# Contributing

To contribute code create merge requests on
[gitlab.gnome.org](https://gitlab.gnome.org/GNOME/simple-scan). If you
find issues please [report them](https://gitlab.gnome.org/GNOME/simple-scan/issues).

## Translation

A lot of information about translation process can be found at
[GNOME TranslationProject](https://wiki.gnome.org/TranslationProject/).
The translation files for *Document Scanner* User Interface and User Guide,
are available [here](https://l10n.gnome.org/module/simple-scan/).

To be able to run Document Scanner in selected language, the `LANGUAGE` could be used.
For example to run Document Scanner in Polish language:

```
$ LANGUAGE=pl XDG_DATA_DIRS=_install/share:$XDG_DATA_DIRS ./_install/bin/simple-scan
```
