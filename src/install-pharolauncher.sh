#! /usr/bin/env bash
#
# ----------------------------------------------------------------------------
# Install PharoLauncher, the Pharo (Smalltalk) image manager
# ----------------------------------------------------------------------------
#

############################################################################
############################################################################
#
# Everything down to the next set of double lines was extracted from 
# 'core-install.bash', then modified slightly for this standalone script.
#
ERR_WARNING=0
ERR_USAGE=1
ERR_NOSUDO=2
ERR_CMDFAIL=4
ERR_UNSPEC=8
ERR_FILEIO=16
ERR_MISSING=32
ERR_BADSWITCH=64
ERR_CANCEL=128

unset USAGE
unset POST_INSTALL

unset SET_NAME
unset REPO_NAME
unset REPO_URL
unset REPO_GREP
unset SIGNING_KEY
unset PACKAGE_SET
unset PKG_VERSION
unset DEB_PACKAGE
unset SHELL_SCRIPT
unset BACKPORT_DISTRO


############################################################################
#
# Throw an error
#
# $1 = Exit code (set to '0' for 'no exit')
# $2 = Name of the script throwing the error
# $3 = Name of the function/routine throwing the error (optional)
# $4 = Message string
#
ThrowError() {

if (( $# > 3 )); then
    printf "%s: %s: error: %s \n" "${2}" "${3}" "${4}" >&2
else
    printf "%s: error: %s \n" "${2}" "${3}" >&2
fi

# Exit the script if the error code is not ERR_WARNING:
#
(( ${1} != ERR_WARNING )) && exit ${1}
}


############################################################################
#
# Announce that installation is complete, then
# display a prompt to press a key to confirm
#
# $1 = '-n' to suppress the "press any key" prompt
# $1 = '-p' to only show the "press any key" prompt
#
InstallComplete() {

if [[ ${1} != "-p" ]]; then
    echo
    echo "Installation of the '${SET_NAME}' package set is complete. "
fi

if [[ ${1} != "-n" ]]; then

    read -r -s -n 1 -p "Press any key to continue. "
    echo
fi

[[ -n "${POST_INSTALL}" ]] && echo "${POST_INSTALL}"

exit 0
}


############################################################################
#
# Display a prompt asking a Yes/No question, repeat until a valid input
#
# Allows for a blank input to be defaulted.  Automatically appends "(y/n)"
# to the prompt, capitalized according to the value of DEF_INPUT
#
# $1 = Default input, (y|n|<don't care>)
# $2 = Prompt
#
# Returns 0 if Yes, 1 if No
#
Get_YesNo_Defaulted() {
    local DEFAULT=${1##-}
    local PROMPT=${2}

    DEFAULT=${DEFAULT,,}
    DEFAULT=${DEFAULT:0:1}

    case ${DEFAULT} in
    y )
        PROMPT=${PROMPT}" [Y/n] "
        ;;
    n )
        PROMPT=${PROMPT}" [y/N] "
        ;;
    * )
        PROMPT=${PROMPT}" "
        ;;
    esac

    unset REPLY
    until [[ "${REPLY}" == "y" || "${REPLY}" == "n" ]]; do

        read -e -r -p "${PROMPT}"

        if [[ -z "${REPLY}" ]]
        then
            REPLY=${DEFAULT}
        else
            REPLY=${REPLY:0:1}
            REPLY=${REPLY,,}
        fi
    done

    [[ "${REPLY}" == "y" ]]
}


############################################################################
#
# Get the name of this script (for 'usage')
#
# $1 = Name of the calling script
# $2 = "unwind": Okay to unwind the link redirects
#
GetScriptName() {

local SCRIPT="${1}"

CORE_SCRIPT="${BASH_SOURCE[0]}"

if [[ ${2} == [uU]nwind ]]; then

    while [[ -h "${SCRIPT}" ]]; do
        SCRIPT="$( readlink -- "${SCRIPT}" )";
    done
fi

APP_SCRIPT=$( basename "${SCRIPT}" .sh )

SCRIPT_DIR=$( cd "$( dirname "${0}" )" && pwd )
}


############################################################################
#
# Determine the OS version
#
GetOSversion() {

ARCH=$( uname -m )

DISTRO=$( lsb_release -sc )
RELEASE=$( lsb_release -sr )
FLAVOR=Unity

lsb_release -sd | grep -qi gallium
(( $? == 0 )) && FLAVOR=xfce

lsb_release -sd | grep -qi stretch
(( $? == 0 )) && FLAVOR=chromeos

MAJOR=$( lsb_release -sr | cut -d . -f 1 )
MINOR=$( lsb_release -sr | cut -d . -f 2 )

[[ -n "${ARCH}" && -n "${DISTRO}" && -n "${RELEASE}" && \
        -n "${MAJOR}" && -n "${MINOR}" ]] && return

ThrowError "${ERR_UNSPEC}" "${CORE_SCRIPT}" "${FUNCNAME}" \
        "Could not resolve OS version value !"
}


############################################################################
#
# Simple test to see if 'sudo' has already been obtained
#
# $1 = Optional string to indicate operation requiring 'sudo'
#
QualifySudo() {

local DIAGNOSTIC="Cannot run this script without 'sudo' privileges."

[[ -n "${1}" ]] && DIAGNOSTIC="This script requires 'sudo' privileges "${1}

sudo ls /root &>/dev/null

(( $? == 0 )) || ThrowError "${ERR_NOSUDO}" "${APP_SCRIPT}" "${DIAGNOSTIC}"
}


############################################################################
#
# Parse command line switches & peform the installation steps
#
# $1 = Command line switch for application installation script
#

#
# This is the unmodified routine from 'core-install.bash' & has way more 
# code than is needed for this standalone script...  But, why hack it?
#
PerformAppInstallation() {

unset INSTALL
unset UPDATE
unset PPA
unset EXTRA_SWITCH
unset RET_WHEN_DONE

local PACKAGE

#
# '-r' means "Return without running InstallComplete"
#
if [[ ${1} == "-r" ]]; then
    shift
    RET_WHEN_DONE=true
fi

#
# Convert the switch to all lower case, and shorten it:
#
SWITCH=${1,,}
SWITCH=${SWITCH:0:5}
shift

#
# Capture additional switch(es) after the main switch:
#
EXTRA_SWITCH=${1,,}
shift

if [[ -n "${EXTRA_SWITCH}" ]]; then
    #
    # Only additional switches of the form of '--reinstall' are allowed;
    # Clip off the '--' & limit to three (lowercase) characters:
    #
    if [[ ${EXTRA_SWITCH:0:2} != "--" ]]; then SWITCH=""; fi
    EXTRA_SWITCH=${EXTRA_SWITCH:2:3}
fi

#
# Decide how to install:
# NOTE: ';&' means "go on to execute the next case block", while ';;&' means
# "continue testing with the next case (as though a match hadn't occurred)".
#
case ${SWITCH} in

"-u" | "--upd")
    UPDATE=true
    ;&

"-n" | "--nou")
    INSTALL=true
    ;;

"-p" | "--ppa")
    [[ -n "${REPO_NAME}" ]] && PPA=true
    ;;

"-a" | "--apt")
    echo "REPO_NAME = '${REPO_NAME}' "
    echo "REPO_URL  = '${REPO_URL}' "
    echo "REPO_GREP = '${REPO_GREP}' "
    exit
    ;;

"-i" | "--inf")
    echo "${USAGE}"
    if [[ -n "${POST_INSTALL}" ]]; then
        echo "-----"
        echo "${POST_INSTALL}"
    fi
    exit
    ;;
esac

#
# Strip out any '%section name:%' substrings for package installation...
# ...then tokenize to strip out the newlines & extraneous spaces:
#
if [[ -n "${PACKAGE_SET}" ]]; then
    PACKAGE_SET=$( printf %s "${PACKAGE_SET}" | sed -e 's/%[^%]*%/ /g' )
    PACKAGE_SET=$( echo ${PACKAGE_SET} )
fi

#
# Display the 'usage' prompt (-h)?
#
if [[ ${SWITCH} == "-h" || ${SWITCH} == "--hel" ||
        -z "${PPA}${UPDATE}${INSTALL}" ]]; then

    if [[ ${PKG_VERSION} = *.*.* ]]; then
        VERS_FORM=" X.Y.Z     "
    elif [[ ${PKG_VERSION} = *.* ]]; then
        VERS_FORM="  M.N      "
    else
        VERS_FORM=" <version> "
    fi

    echo
    echo -n "usage: ${APP_SCRIPT} "

    [[ -n "${PKG_VERSION}" ]] && echo -n "[ $( printf %s ${VERS_FORM} ) ] "

    if [[ -n "${REPO_NAME}" ]]; then
        echo "[ -p | -u | -n | -i ] "
    else
        echo "[ -u | -n | -i ] "
    fi

    echo
    echo "This script installs the '${SET_NAME}' package set. "
    echo
    echo "Options: "

    if [[ -n "${PKG_VERSION}" ]]; then
        echo -n "   ${VERS_FORM}       = "
        echo    "Version to install (e.g., ${PKG_VERSION}) "
    fi

    if [[ -n "${REPO_NAME}" ]]; then
        echo "    -p --ppa         = Add/remove PPA only; don't install "
        echo "    -u --update      = Add PPA, update, then install "
    else
        echo "    -u --update      = Update, then install "
    fi

    echo "    -n --noupdate    = Do not update, just install "
    echo "    -i --info        = Display post-install info "

    if [[ -n "${REPO_NAME}" ]]; then
        echo
        echo "The PPA '-p' command includes these additional options: "
        echo "       --reinstall   = Attempt to install the PPA unconditionally "
        echo "       --remove      = Remove the PPA, but keep any installed pkgs "
        echo "       --purge       = Remove the PPA, revert updated packages "
    fi

    [[ -n "${USAGE}" ]] && printf %s "${USAGE}"
    echo

    exit ${ERR_USAGE}
fi

#
# Download & install a package signing key?
#
if [[ -n "${SIGNING_KEY}" ]]; then

    # There are three forms of this... Which one are we given?
    #
    QualifySudo

    if [[ "${SIGNING_KEY:0:4}" == "http" ]]; then

        wget "${SIGNING_KEY}" -O- | sudo apt-key add -

    elif [[ "${SIGNING_KEY:0:4}" == "adv " ]]; then

        sudo apt-key ${SIGNING_KEY}
    else
        sudo apt-key add "${SIGNING_KEY}"
    fi

    (( $? > 0 )) && ThrowError "${ERR_CMDFAIL}" "${APP_SCRIPT}" \
            "Could not add the signing key for '${SET_NAME}' !"
    echo
    echo "Added '${SET_NAME}' signing key... "
    sleep 2
    echo
fi

#
# Install a PPA/Repository?
#
if [[ -n "${REPO_NAME}" ]]; then

    # Test to see if the PPA/respository source file is present:
    #
    RESULT=$( cat ${APT_DIR}/*.list ${APT_SOURCES_DIR}/*.list 2>/dev/null | \
            grep -v '^#' | grep -v '^[ \t]*$' | grep "${REPO_GREP}" )

    # If no 'grep' string is provided, or, if one is, but the PPA/repo
    # has not yet been installed, then add the PPA/repository:
    #
    if [[ -z "${REPO_GREP}" || -z "${RESULT}" ]]; then

        case ${EXTRA_SWITCH} in
        "pur" | "rem" )
            ThrowError "${ERR_CMDFAIL}" "${APP_SCRIPT}" \
                    "This PPA isn't installed -- nothing to do !"
            ;;
        "rei" | "" )
            QualifySudo
            echo "Installing repository '${REPO_NAME}'... "
            ;;
        * )
            QualifySudo
            echo "Installing; extra argument is ignored... "
            sleep 2
            ;;
        esac

        QualifySudo
        which apt-add-repository &>/dev/null
        (( $? == 0 )) || sudo apt-get install -y software-properties-common

        sudo apt-add-repository -y "${REPO_URL}"

        (( $? > 0 )) && ThrowError "${ERR_CMDFAIL}" "${APP_SCRIPT}" \
                "Could not add repository '${REPO_NAME}' !"

        Remove_Illicit_Source_Repo "${REPO_URL}"
        echo
        echo "Added repository '${REPO_NAME}'... "
        sleep 2
        echo

    elif [[ -z "${EXTRA_SWITCH}" ]]; then

        if [[ ${INSTALL} != true ]]; then
            echo "Repository '${REPO_NAME}' is already installed ! "
            echo
            sleep 1
        fi

    else
        # If the string is provided, and the PPA/repo is already installed,
        # then see if we should purge it, remove it, or re-install it:
        #
        QualifySudo
        case ${EXTRA_SWITCH} in

        "pur")
            echo "Purging repository '${REPO_NAME}'... "
            sleep 2
            sudo ppa-purge "${REPO_URL}"

            (( $? > 0 )) && ThrowError "${ERR_CMDFAIL}" "${APP_SCRIPT}" \
                    "Could not purge repository '${REPO_NAME}' !"

            echo
            echo "Repository '${REPO_NAME}' has been purged. "
            ;;
        "rem")
            echo "Removing repository '${REPO_NAME}'... "
            sleep 2

            which apt-add-repository &>/dev/null
            (( $? == 0 )) || sudo apt-get install -y software-properties-common

            sudo apt-add-repository -r -y "${REPO_URL}"

            (( $? > 0 )) && ThrowError "${ERR_CMDFAIL}" "${APP_SCRIPT}" \
                    "Could not remove repository '${REPO_NAME}' !"

            echo "Repository '${REPO_NAME}' has been removed. "
            ;;
        "rei")
            echo "Re-installing repository '${REPO_NAME}'... "
            sleep 2

            which apt-add-repository &>/dev/null
            (( $? == 0 )) || sudo apt-get install -y software-properties-common

            echo "Removing repository '${RESULT}'... "
            [[ -z "${RESULT}" ]] || sudo apt-add-repository -r -y "${RESULT}"

            (( $? > 0 )) && ThrowError "${ERR_CMDFAIL}" "${APP_SCRIPT}" \
                    "Could not remove repository '${RESULT}' !"

            echo "Installing repository '${REPO_URL}'... "
            sudo apt-add-repository -y "${REPO_URL}"

            (( $? > 0 )) && ThrowError "${ERR_CMDFAIL}" "${APP_SCRIPT}" \
                    "Could not add repository '${REPO_NAME}' !"

            Remove_Illicit_Source_Repo "${REPO_URL}"
            ;;
        *)
            ThrowError "${ERR_CMDFAIL}" "${APP_SCRIPT}" \
                    "Invalid argument, '${EXTRA_SWITCH}' !"
            ;;
        esac
    fi

    # We're done if the user only wants the PPA/repo installed...
    #
    [[ -n "${PPA}" ]] && return
fi

#
# Backport a package set from a later release?
#
if [[ -n "${BACKPORT_DISTRO}" ]]; then

    PACKAGE_SET="-t ${BACKPORT_DISTRO} ${PACKAGE_SET}"
    PrepBackportConfig

    # 'PrepBackportConfig' returns >0 if a file was written...
    #
    if (( $? > 0 )); then
        echo
        echo "Added '${BACKPORT_DISTRO}' repository... "
        sleep 2
        echo
        UPDATE=true
    fi
fi

#
# Update the package list?
#
if [[ -n "${UPDATE}" ]]; then

    QualifySudo
    sudo apt-get update

    if (( $? > 0 )); then

        echo
        Get_YesNo_Defaulted "y" \
                "Errors detected with package update.. Continue?"

        (( $? > 0 )) && ThrowError "${ERR_CMDFAIL}" "${APP_SCRIPT}" \
                "Could not update the repository package list !"
    fi
fi

#
# Install a repository package set?
#
if [[ -n "${INSTALL}" && -n "${PACKAGE_SET}" ]]; then

    # Remove packages that are already installed and packages that are not in
    # the repositories.  Otherwise, they'll be marked "manually installed"...
    #
    if [[ -n "${PACKAGE_SET}" ]]; then

        PACKAGE_SET="  ${PACKAGE_SET}  "
        echo -n "Checking packages: "

        for PACKAGE in ${PACKAGE_SET}; do

            # If the parameter is a switch (starts with '-'), then leave it
            # in the list -- but don't try to check it:
            #
            RESULT=$( printf %s "${PACKAGE}" | grep '^[-]' )
            (( $? == 0 )) && continue

            RESULT=$( dpkg -s "${PACKAGE}" 2>/dev/null )
            if (( $? > 0 )); then

                # The package is not installed; does it exist?
                # Before checking, clip off any ":i386", etc.
                #
                BASE_PKG=${PACKAGE%:*}
                RESULT=$( apt-cache search "${BASE_PKG}" 2>/dev/null \
                        | grep "^${BASE_PKG}" )
            else
                unset RESULT
            fi
            echo -n "*"

            # If the package is not installed AND is not missing in the repo,
            # then we can leave it in the list; else we must remove it...
            #
            [[ -n "${RESULT}" ]] && continue

            PACKAGE_SET=$( printf %s "${PACKAGE_SET}" | \
                    sed -e "s/ ${PACKAGE} / /" )
        done
    fi
    echo

    QualifySudo
    sudo apt-get install -y ${PACKAGE_SET}

    (( $? > 0 )) && ThrowError "${ERR_CMDFAIL}" "${APP_SCRIPT}" \
            "Could not install the repository package set !"
fi

#
# Install one or more Debian packages?  (Must follow repo package installs)
#
if [[ -n "${INSTALL}" && -n "${DEB_PACKAGE}" ]]; then

    # The packages (files) are actually a list (array)...
    #
    QualifySudo
    if [[ ${DEB_INSTALLER} == "gdebi" ]]; then

        which gdebi 1>/dev/null

        if (( $? > 0 )); then
            sudo apt-get install -y gdebi

            (( $? > 0 )) && ThrowError "${ERR_CMDFAIL}" "${APP_SCRIPT}" \
                "Could not install the 'gdebi' package !"
        fi
    fi

    sudo ${DEB_INSTALLER} "${FILE_LIST[@]}"
#    (( $? > 0 )) && ThrowError "${ERR_CMDFAIL}" "${APP_SCRIPT}" \
#            "Could not install the debian package set !"
fi

#
# Install via a shell script or binary executable? (Needs revision!)
#
if [[ -n "${INSTALL}" && -n "${SHELL_SCRIPT}" ]]; then

    for SCRIPT in "${FILE_LIST[@]}"; do

        QualifySudo
        echo
        echo "Invoking 'bash ${SCRIPT}'... "

        sudo bash "${SCRIPT}"
#        (( $? > 0 )) && ThrowError "${ERR_CMDFAIL}" "${APP_SCRIPT}" \
#            "Could not install the bash script set !"
    done
fi

#
# Did we do an install?
#
[[ -n "${RET_WHEN_DONE}" ]] && return

[[ -n "${INSTALL}" ]] && InstallComplete
}


############################################################################
############################################################################
#
# Extracted from 'install-pharo-launcher.sh' and modified to run standalone.
# Among other things, it does NOT assume the presence of a 'pharo' directory
# containing cached ZIP files, icons, and '.desktop' files.
#

GetScriptName "${0}"
GetOSversion

SET_NAME="Pharo-Launcher"

##SOURCE_DIR=../pharo
##PHARO_PKG_DIR="pharo-launcher"
##APP_PKG_PATH=${SOURCE_DIR}/${PHARO_PKG_DIR}
APP_PKG_PATH=$( pwd )
APP_PKG_BASENAME="PharoLauncher"

## Does our source file directory exist?
##
##[[ -d "${APP_PKG_PATH}" ]] || ThrowError "${ERR_MISSING}" "${APP_SCRIPT}" \
##    "Could not find the source directory, '${APP_PKG_PATH}' !"

# Where in our system do we put things?
# Needed directories will be created...
#
##PHARO_DIR_PATH="${HOME}/Pharo"
PHARO_DIR_PATH=$( pwd )
PHARO_DIR_NAME="pharolauncher"

APP_FILE_NAME="pharo-launcher"
DESKTOP_FILE_NAME="pharo-launcher.desktop"

ICON_DIR_NAME="icons"
ICON_FILE_NAME="pharo-launcher.png"

LAUNCHER_DIR_PATH=~/.local/share/applications

# Linux VMs have the option of using a threaded heartbeat (preferred)
#
THREADED_HB_DIR="/etc/security/limits.d"
PHARO_HB_CONF_FILEPATH="${THREADED_HB_DIR}/pharo.conf"
SQUEAK_HB_CONF_FILEPATH="${THREADED_HB_DIR}/squeak.conf"
NEWSPEAK_HB_CONF_FILEPATH="${THREADED_HB_DIR}/nsvm.conf"

# Make the paths to the installation components.
# Some of these are needed for creating the '.desktop' file.
#
APP_DIR_PATH=${PHARO_DIR_PATH}/${PHARO_DIR_NAME}
APP_FILE_PATH=${APP_DIR_PATH}/${APP_FILE_NAME}

ICON_DIR_PATH=${APP_DIR_PATH}/${ICON_DIR_NAME}
ICON_FILE_PATH=${ICON_DIR_PATH}/${ICON_FILE_NAME}

APP_LAUNCHER_PATH=${ICON_DIR_PATH}/${DESKTOP_FILE_NAME}

# Create the usage prompt text:
#
USAGE="
Installs the latest Pharo (Smalltalk) Launcher application, which automates
downloading & managing collections of Pharo 'images' (environment snapshots).

Pharo is an open-source programming language that is dynamic, object-oriented,
and reflective.  Pharo was inspired by the Smalltalk programming language and
environment, with updates & extentions for modern systems.  Pharo offers strong
live programming features such as immediate object manipulation, live update,
and hot recompilation.  The live programming environment is at the heart of the
system.

Pharo-Launcher is itself implemented as a Pharo app.  The Launcher lists
local and remote image files, and can download images from repositories along
with the appropriate VMs needed to run them.  Local images can be imported,
configured, and launched directly from the Pharo-Launcher GUI.

https://pharo.org/about
https://pharo.org/download
https://files.pharo.org/pharo-launcher/
https://github.com/pharo-project/pharo-launcher
"

POST_INSTALL="
The Pharo-Launcher app is installed in '${PHARO_DIR_PATH}'.

A desktop launcher file for Pharo-Launcher has been created; you may wish to
add it to your favorites/dock for convenience when starting Pharo-Launcher.

To update the installer packages, surf to https://pharo.org/web/download.

"

# Invoked with the '-i' switch?
#
if [[ -z "${1}" || "${1}" == "-i" ]]; then
    PerformAppInstallation "$@"
    exit $?
fi

# To continue, we require the 'unzip' package be installed on this system:
#
which unzip &>/dev/null

(( $? == 0 )) || ThrowError "${ERR_MISSING}" "${APP_SCRIPT}" \
    "Could not find the 'unzip' command !"

# Determine the architecture bitness, and install 32-bit support
# if we're on a 64-bit system.  This allows running 32-bit images.
#
PHARO_BITNESS="x86"
if [[ ${ARCH} == "x86_64" ]]; then
    PHARO_BITNESS="x64"

    QualifySudo
    sudo dpkg --add-architecture i386

    PACKAGE_SET="libx11-6:i386  libgl1-mesa-glx:i386
        libfontconfig1:i386  libssl1.0.0:i386  "

    PerformAppInstallation "-r" "-u"
fi

# Form the target glob from the desired bitness:
#
PHARO_PKG_GLOB="${APP_PKG_BASENAME}.*${PHARO_BITNESS}.zip"

# Locate the target file, based on the desired bitness:
#
APP_PKG_FILE=""

for ZIP_FILE in *.zip; do
    if [[ "${ZIP_FILE}" =~ ${PHARO_PKG_GLOB} ]]; then
        APP_PKG_FILE=${ZIP_FILE}
        break
    fi
done

[[ -n "${APP_PKG_FILE}" && -r "${APP_PKG_FILE}" ]] || 
    ThrowError "${ERR_MISSING}" "${APP_SCRIPT}" \
        "Could not locate the Pharo Launcher zip file !"

# Create the destination directory, as needed...
#
mkdir -p "${APP_DIR_PATH}"

(( $? == 0 )) || ThrowError "${ERR_FILEIO}" "${APP_SCRIPT}" \
    "Could not locate/create '${PHARO_DIR_PATH}' !"

# Unzip the package file into the app directory:
#
echo
unzip "${APP_PKG_FILE}" -d "${PHARO_DIR_PATH}"

(( $? == 0 )) || ThrowError "${ERR_CMDFAIL}" "${APP_SCRIPT}" \
    "Could not unzip the '${APP_PKG_FILE}' package to '${PHARO_DIR_PATH}' !"

# Copy the .desktop launcher file into place and customize for this app:
#
cat > "${APP_LAUNCHER_PATH}" << __DESKTOP_FILE_EOL
[Desktop Entry]
Comment=Pharo Smalltalk environment
Terminal=false
Name=Pharo Smalltalk
Exec=${INSTALL_DIR}/pharo
Type=Application
Icon=${INSTALL_DIR}/icons/Pharo.png
X-Desktop-File-Install-Version=0.22
GenericName=Programming
Categories=Application;Development;
__DESKTOP_FILE_EOL

(( $? == 0 )) || ThrowError "${ERR_FILEIO}" "${APP_SCRIPT}" \
    "Could not create a '.desktop' file in '${ICON_DIR_PATH}' !"

##QualifySudo "to install the PharoLauncher '.desktop' file."

sudo desktop-file-install --dir=${LAUNCHER_DIR_PATH} --mode=644 \
    --set-name="Pharo Launcher" \
    --set-generic-name="Programming" \
    --set-comment="Pharo Smalltalk image file manager" \
    --set-icon=${ICON_FILE_PATH} \
    --set-key="Exec"        --set-value="${APP_FILE_PATH}" \
    --set-key="Terminal"    --set-value="false" \
    --set-key="Type"        --set-value="Application" \
    --set-key="Categories"  --set-value="Development;" \
    "${APP_LAUNCHER_PATH}"

(( $? == 0 )) || ThrowError "${ERR_FILEIO}" "${APP_SCRIPT}" \
    "Could not edit the '.desktop' file, '${APP_LAUNCHER_PATH}' !"

#
# Set the owner, icons, & desktop file permissions.
#
sudo chmod 644 "${LAUNCHER_DIR_PATH}"/*
sudo chown -R $( id -un ):$( id -gn ) "${LAUNCHER_DIR_PATH}"/*

sudo chmod 644 "${ICON_DIR_PATH}"/*
sudo chown -R $( id -un ):$( id -gn ) "${ICON_DIR_PATH}"/*

#
# Need the following for Linux systems to use the threaded heartbeat VM:
#
QualifySudo "to install the threaded heartbeat configuration for Pharo."
sudo mkdir -p "${THREADED_HB_DIR}"

TMP_PATH=$( mktemp -q )
(( $? > 0 )) && ThrowError "${ERR_FILEIO}" "${APP_SCRIPT}" \
        "Could not create a ${TYPE} in '/tmp' ! "
        
cat > "${TMP_PATH}" << __HB_CONF_EOL
*       hard    rtprio  2
*       soft    rtprio  2
__HB_CONF_EOL

sudo chmod 644 "${TMP_PATH}"

sudo cp -rf "${TMP_PATH}" "${PHARO_HB_CONF_FILEPATH}" && \
sudo cp -rf "${TMP_PATH}" "${SQUEAK_HB_CONF_FILEPATH}" && \
sudo cp -rf "${TMP_PATH}" "${NEWSPEAK_HB_CONF_FILEPATH}"

(( $? == 0 )) || ThrowError "${ERR_CMDFAIL}" "${APP_SCRIPT}" \
        "Could not copy any/all the heartbeat files ! "

rm -rf "${TMP_PATH}"

InstallComplete

############################################################################
############################################################################

