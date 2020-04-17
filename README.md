# pharo-support
Miscellaneous scripts for installing & configuring Pharo applications & software

### Pharo-Launcher Installer

This bash shell script automates the installation of `Pharo-Launcher` in Linux.  It's primary value-add is that it creates a `.desktop` launcher file that can be used to put an icon in the dock to make launching the app easier.

To use the installer script, download a `PharoLauncher` zip file from https://pharo.org (32-bit or 64-bit).  [Future versions of this scirpt will automate downloading the zip file for you.]  

The location of the zip file, whether or not it's been unzipped, etc. are not important, as this script will perform a search for appropriately-named zip files and unzipped Pharo Launcher directories on your system.

You can either allow the installer script to search through a default set of directories for installation zip files/directories, or you can explicitly specify where to find them on the command line.

Similarly, you can allow the installer script to install to a default directory, or you can explicity specify the destination directory on the command line.

When run with `-u` or without any arguments, it will print a brief usage and quit.  When run with `-h`, it will print out a comprehensive 'help' synopsis and quit.

To install from a specific source, add `-i < source >`; to install to a specific destination, add `-d < destination >`.  The source can be a zip file or directory; directories will be searched.  The destination must be a writable directory.

If the source file found is a zip file, it will be unzipped and the payload extracted for installation.  If more than one candidate installation source is found, a menu of choices will be presented, allowing you to select one.

The script will move the selected `pharolauncher` directory to the destination folder, then create a "launcher" file (a `.desktop` file) and install it to `~/.local/share/applications`; this launcher can be found by searching for `pharo` in the `Show Applications` panel of Gnome.  Clicking the installed launcher icon will launch the Pharo-Launcher application.

This script can be re-run without side-effects.  If the destination directory already exists, you will be prompted to give permission to overwrite existing files.

### Pharo-Adjust-Cursor

This bash shell script edits Pharo shell scripts that launch Pharo applications (e.g., `pharolauncher`, `pharoiot`) to either enable or disable enlarging the GUI pointer.

This is useful on Linux systems with a 4K hi-DPI screen, since currently Pharo can currently enlarge its fonts and other GUI features, but not the cursor.

The cursor is enlarged by first setting an environment variable, `SQUEAK_FAKEBIGCURSOR`, to a non-zero value prior to running the startup command in Pharo application scripts such as `pharo-launcher`, `pharo-ui`, etc.  This is achieved by editing these app scripts to add an `env` prefix to the commands that invoke a virtual machine to load & run a Pharo image file.

This script can edit the Pharo application scripts "in both directions"; that is, it can add the `env` prefix or remove it, depending on which option switch is included on the command line.  Note that there are no side-effects if the same command is issued multiple times in a row.  Each time a Pharo script is edited, a backup file will be created with a name extension appended that reflects the script type being backed up.  (Other than re-running this script to reverse the editing action, any restoration such as reverting from a backup must be done manually.)

If run in a Pharo application directory (such as `pharolauncher`), this script will only edit the Pharo scripts found in that directory.  If run in a directory that itself contains one or more Pharo app directories, it will search for and edit the scripts in each of them.  (If neither situation is met, it will complain, and will also complain if expected Pharo bash scripts aren't found.)

As is typical with my scripts (and most bash scripts), adding the `-h` switch (or `--help`) will show the usage prompt, as will entering the command with no arguments.
