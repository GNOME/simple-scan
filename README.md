[![Build Status](https://gitlab.gnome.org/GNOME/simple-scan/badges/master/build.svg)](https://gitlab.gnome.org/GNOME/simple-scan/pipelines)
[![License](https://img.shields.io/badge/License-GPL%20v3-blue.svg)](https://gitlab.gnome.org/GNOME/simple-scan/blob/master/COPYING)

# Introduction

*Document Scanner* is a document scanning application for [GNOME](https://www.gnome.org/)
It allows you to capture images using [image scanners](https://en.wikipedia.org/wiki/Image_scanner)
(e.g. flatbed scanners) that have suitable [SANE drivers](http://sane-project.org/) installed.

# Building the flatpak with GNOME Builder

It is recommended to use the development flatpak for developing this application.
That way you won't have to download all dependencies yourself and it'll be consistent between all distros.

1. Download [GNOME Builder](https://flathub.org/apps/details/org.gnome.Builder)
2. Click the `Clone Repository` button in Builder and use https://gitlab.gnome.org/GNOME/simple-scan.git as the URL.
3. Click the Run button in the headerbar

Note that this flatpak requires access to all devices (--device=all), and so isn't made for general use.
For this reason and until a more suitable solution is found to interact with a host `saned`, please don't
try to publish it on Flathub.

# Building manually from source

Install the dependencies

For Ubuntu/Debian:

```
sudo apt install -y meson valac gcc gettext itstool libfribidi-dev libgirepository1.0-dev libgtk-4-dev libadwaita-1-dev libgusb-dev libcolord-dev libpackagekit-glib2-dev libwebp-dev libsane-dev git ca-certificates
```

For Fedora:

```
sudo dnf install -y meson vala gettext itstool fribidi-devel gtk4-devel libadwaita-devel gobject-introspection-devel libgusb-devel colord-devel PackageKit-glib-devel libwebp-devel sane-backends-devel git
```

For Arch Linux:

```
sudo pacman -S meson vala gettext itstool fribidi gtk4 libadwaita gobject-introspection libgusb colord libwebp sane git

```

Get the source:

```
git clone https://gitlab.gnome.org/GNOME/simple-scan.git
cd simple-scan
```

Build and run:

```
meson --prefix $PWD/_install _build
ninja -C _build all install
XDG_DATA_DIRS=_install/share:$XDG_DATA_DIRS ./_install/bin/simple-scan
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
