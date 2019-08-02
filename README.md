[![Build Status](https://gitlab.gnome.org/GNOME/simple-scan/badges/master/build.svg)](https://gitlab.gnome.org/GNOME/simple-scan/pipelines)
[![License](https://img.shields.io/badge/License-GPL%20v3-blue.svg)](https://gitlab.gnome.org/GNOME/simple-scan/blob/master/COPYING)

# Introduction

*Document Scanner* is a document scanning application for [GNOME](https://www.gnome.org/)
It allows you to capture images using [image scanners](https://en.wikipedia.org/wiki/Image_scanner)
(e.g. flatbed scanners) that have suitable [SANE drivers](http://sane-project.org/) installed.

# Building from source

Install the dependencies (first line is Ubuntu/Debian, second is Fedora):
```
$ sudo apt install git meson valac libgtk-3-dev libgusb-dev libcolord-dev libpackagekit-glib2-dev libwebp-dev libsane-dev gettext itstool
```
```
$ sudo dnf install -y meson vala gettext itstool gtk3-devel libgusb-devel colord-devel PackageKit-glib-devel libwebp-devel sane-backends-devel
```

Get the source:
```
$ git clone https://gitlab.gnome.org/GNOME/simple-scan.git
$ cd simple-scan
```

Build and run:
```
$ meson --prefix $PWD/install build/
$ ninja -C build/ all install
$ XDG_DATA_DIRS=install/share:$XDG_DATA_DIRS ./install/bin/simple-scan
```

# Debugging

There is a --debug command line switch to enable more verbose logging:
```
$ simple-scan --debug
```

Log messages can also be found in the `$HOME/.cache/simple-scan` folder.

If you don't have a scanner ready, you can use a virtual "test" scanner:
```
$ simple-scan --debug test
```

This app works by using the [SANE API](http://sane-project.org/html/) to
capture images. It chooses the settings it thinks are appropriate for what you
are trying to do. Drivers have many options and are of differring quality - it
is useful to work out if any issues are caused by the app or the drivers. To
confirm it is a driver issue you can use the graphical tool (XSane) or the
command line
[scanimage](http://www.sane-project.org/man/scanimage.1.html) provided
by the SANE project - these allow to to easily see and control all the
settings your driver provides.

# Contributing

To contribute code create merge requests on
[gitlab.gnome.org](https://gitlab.gnome.org/GNOME/simple-scan). If you
find issues please [report them](https://gitlab.gnome.org/GNOME/simple-scan/issues).
