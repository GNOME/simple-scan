# SIMPLE SCAN

This is the source code to "Simple Scan" a simple GNOME scanning application,
using the sane scanning libraries.

The Simple Scan homepage with further information is located at:
https://launchpad.net/simple-scan



## BUILDING

Unfortunatly Simple Scan is a little bit picky about dependencies when building.
The latest version of Simple Scan is primarily developed on

* Ubuntu 12.04 LTS

and know to successfully build using the following commands:

```
sudo apt-get install bzr
bzr branch lp:simple-scan simple-scan && cd simple-scan
sudo apt-get build-dep simple-scan
sudo apt-get install libsqlite3-dev
sudo apt-get install valac-0.22 vala-0.22
sudo update-alternatives --config valac # select vala-0.22

# one of the follwing
./autogen.sh                           # system-wide installation
./autogen.sh --prefix=`pwd`/install    # for development purposes

make
make install
./install/bin/simple-scan
```

Due to popular demand we have an experimental git mirror at
https://github.com/mnagel/simple-scan
You can clone from there should you prefer git over bzr.
Please keep in mind that the sync bzr->git is done manually.



## DEBUGGING

The following tips might be helpful when debugging.

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
