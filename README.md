[![Build Status](https://gitlab.gnome.org/GNOME/simple-scan/badges/master/build.svg)](https://gitlab.gnome.org/GNOME/simple-scan/pipelines)

# SIMPLE SCAN

This is the source code to "Simple Scan" a simple GNOME scanning application,
using the [SANE](http://sane-project.org/) scanning libraries.

## BUILDING

Install the dependencies (on Ubuntu/Debian):
```
$ sudo apt install git meson valac libgtk-3-dev libgusb-dev libcolord-dev libpackagekit-glib2-dev libwebp-dev libsane-dev gettext itstool
```

Get the source:
```
$ git clone https://gitlab.gnome.org/GNOME/simple-scan.git
```

Build locally with:
```
$ meson --prefix $PWD/install build/
$ ninja -C build/ all install
$ XDG_DATA_DIRS=install/share:$XDG_DATA_DIRS ./install/bin/simple-scan
```

## DEBUGGING

There is a --debug command line switch to enable more verbose logging:
```
./install/bin/simple-scan --debug
```

Log messages can also be found in the $HOME/.cache/simple-scan folder.

If you don't have a scanner ready, you can use a virtual "test" scanner:
```
./install/bin/simple-scan --debug test
```

When debugging hardware issues always check xsane and especially scanimage.

* http://xsane.org/
* http://www.sane-project.org/man/scanimage.1.html

## CONTRIBUTING

The preferred way to contribute code to Simple Scan is
to create a merge request on gitlab.gnome.org.

## CONTACT

### Websites
* https://gitlab.gnome.org/GNOME/simple-scan
* https://gitlab.gnome.org/GNOME/simple-scan/issues

### IRC
* Freenode (irc.ubuntu.com): #simple-scan
