# SIMPLE SCAN

This is the source code to "Simple Scan" a simple GNOME scanning application,
using the sane scanning libraries.

The Simple Scan homepage with further information is located at:
https://launchpad.net/simple-scan



## BUILDING

Install the dependencies (on Ubuntu/Debian):
```
$ sudo apt install bzr meson valac libgtk-3-dev libgusb-dev libcolord-dev libpackagekit-glib2-dev libsane-dev gettext itstool
```

Get the source:
```
$ bzr branch lp:simple-scan
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

Simple Scan config goes to $HOME/.gconf/apps/simple-scan/%gconf.xml
and that file is best edited with the gconf-editor tool.

If you don't have a scanner ready, you can use a virtual "test" scanner:
```
./install/bin/simple-scan --debug test
```

When debugging hardware issues always check xsane and especially scanimage.

* http://xsane.org/
* http://www.sane-project.org/man/scanimage.1.html

## CONTRIBUTING

The preferred way to contribute code to Simple Scan is
to create a merge request on Launchpad.

* Creating a merge request on Launchpad involves creating an account:
https://login.launchpad.net/+new_account
* You need set up a SSH key with Launchpad:
https://launchpad.net/~/+editsshkeys
* How to configure bazaar (whoami) and create commits: 
http://doc.bazaar.canonical.com/latest/en/mini-tutorial/
* Push the changes to a personal repository on Launchpad:
bzr push lp:~$USER/simple-scan/$BRANCHNAME
where $USER is your Launchpad Id and $COMMENT is a newly created branch name.
* Propose merging your new branch to the master branch on:
https://code.launchpad.net/~

If everything is set up correctly the following should work:
```
FEATURE="foobar"
LAUNCHPADID="name"
bzr branch lp:simple-scan simple-scan-$FEATURE && cd simple-scan-$FEATURE
bzr add .
bzr commit -m "add $FEATURE"
bzr push lp:~$LAUNCHPADID/simple-scan/$FEATURE
xdg-open "https://code.launchpad.net/~"
```

If this does not work for you, feel free to contact us
via one of the channels listed below.



## CONTACT

### Websites
* https://launchpad.net/simple-scan
* https://bugs.launchpad.net/simple-scan
* https://answers.launchpad.net/simple-scan

### Mailing Lists
* https://launchpad.net/~simple-scan-users
* https://launchpad.net/~simple-scan-team

### IRC
* Freenode (irc.ubuntu.com): #simple-scan
