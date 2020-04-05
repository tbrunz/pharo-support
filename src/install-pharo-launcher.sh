#! /usr/bin/env bash
#

###############################################################################
#
# Application-specific operating parameters
#
THIS_APP=$( basename ${0} '.sh' )

VERSION_GREP="[[:digit:]]+[.][[:digit:]]+[.][[:digit:]]+"
ARCH_GREP="(x86|x64)"

ZIP_FILE_ROOT_NAME_GREP="PharoLauncher-linux-${VERSION_GREP}-${ARCH_GREP}"

INSTALLER_DIR_NAME_GREP="pharolauncher"

APPLICATION_SCRIPT_NAME="pharo-launcher"

INSTALLER_SEARCH_PATHS=(
    '.'
    '${HOME}/Downloads'
    '${HOME}'
)

DEFAULT_DESTINATION='${HOME}/Pharo'

USAGE_INSTALLER="[[-i] /inst/folder[/<inst.zip>]]"
USAGE_DESTINATION="[[-d] /dest/folder]"
USAGE_PROMPT="usage: ${THIS_APP} ${USAGE_INSTALLER} ${USAGE_DESTINATION}"


###############################################################################
###############################################################################
#
Display_Usage () {
    echo "
${USAGE_PROMPT}"
}


###############################################################################
#
Display_Help () {
    echo "
${USAGE_PROMPT}

    This script installs the latest Pharo (Smalltalk) Launcher application,
    which automates downloading & managing collections of Pharo 'images'
    (environment snapshots).

    If one parameter is provided, it will be interpreted as the destination
    folder where the Pharo Launcher application folder will be installed.
    If two parameters are provided, the first will be interpreted as the
    location of the installer (either the zip file or its unzipped contents)
    and the second as the destination folder.

    These parameters can also be proceded by '-i' or '--installer=' for the
    installer and '-d' or '--destination=' for the destination folder.  If
    the installer folder/zip file is not provided, it will be searched for
    starting in '.' then '~/Downloads' then '~'.  If the destination folder
    is not provided, it will default to '~/Pharo/pharolauncher'.

    This installer will also create a '.desktop' file for the installed Pharo
    Launcher application, saved to the '~/.local/share/applications' folder.

    Pharo is an open-source programming language that is dynamic, object-
    oriented, and reflective.  Pharo was inspired by the Smalltalk IDE &
    programming language, with updates & extentions for modern systems.
    Pharo offers strong live programming features such as immediate object
    manipulation, live update, and hot recompilation.  The live programming
    environment is at the heart of the system.

    Pharo-Launcher is itself implemented as a Pharo app.  The Launcher lists
    local and remote image files, and can download images from repositories
    along with the appropriate VMs needed to run them.  Local images can be
    imported, configured, and launched directly from the Pharo-Launcher GUI.

    https://pharo.org/about
    https://pharo.org/download
    https://files.pharo.org/pharo-launcher/
    https://github.com/pharo-project/pharo-launcher
"
}


###############################################################################
###############################################################################
#
# Function return codes
#
SUCCESS=0
IGNORED=1
NOT_APP=2
IS_APP=3
NO_FILES=4
NO_SCRIPTS=5
HAS_DIRS=6
NO_DIRS=7
VM_DIR=8
CANT_WRITE=9


###############################################################################
#
# This is the exit point for the script.
#
die () {
    # If no parameter is supplied, default to '1' (not '0').
    # Use 'exit $SUCCESS' (or 'exit Success') to quit with code True.
    [[ -z "${1}" ]] && exit 1

    # If $1 is a number, use that number as the exit code.
    # If $1 is a string, '$(( ))' will resolve it as '0'.
    exit $(( ${1} ))
}


###############################################################################
#
# Display a feedback message to the user.
#
Display_Message () {
    # If no parameter is supplied, send it anyway (i.e., blank line).
    echo "${@}"
}


###############################################################################
#
# Echo the argument to the Standard Error stream.  Optionally, die.
#
Display_Error () {
    local ERROR_MSG=${1}
    local EXIT_SIGNAL=${2}

    if [[ -n "${ERROR_MSG}" ]]; then
        # If $1 is provided, display it as an error message.
        echo 1>&2 "${ERROR_MSG}"
    else
        # If $1 is not defined, we have a programming error...
        Warn_of_Bad_Argument "${FUNCNAME}"
    fi

    # If $2 is not provided, resume the script after displaying the message.
    [[ -z "${EXIT_SIGNAL}" ]] && return

    # If $2 is defined, then quit the script, using $2 as the exit code.
    die $(( ${EXIT_SIGNAL} ))
}


###############################################################################
#
# Notify the user of what's likely a programming bug: Bad/missing arguments.
#
Warn_of_Bad_Argument () {
    local FUNCTION_NAME=${1}

    [[ -n "${FUNCTION_NAME}" ]] || FUNCTION_NAME="<unnamed function>"

    Display_Error "Bad/missing arguments invoking '${FUNCTION_NAME}'!"
}


###############################################################################
#
# Notify the user of what's likely a programming bug: Unexpected return code.
#
Warn_of_Bad_Return_Code () {
    local FUNCTION_NAME=${1}

    [[ -n "${FUNCTION_NAME}" ]] || FUNCTION_NAME="<unnamed function>"

    Display_Error "Bad return code from '${FUNCTION_NAME}'!"
}


###############################################################################
#
# Warn about directories that we don't have write permission for.
#
Warn_of_Directory_Not_Writable () {
    local SCRIPT_PATH=${1}
    local SCRIPT_DIR
    local ERROR_MSG

    if [[ -n "${SCRIPT_PATH}" ]]; then
        SCRIPT_DIR="directory '$( dirname "${SCRIPT_PATH}" )'"
    else
        SCRIPT_DIR="<argument not provided>"
    fi

    printf -v ERROR_MSG "%s " \
        "Cannot write/delete files in ${SCRIPT_DIR}, Skipping..."

    Display_Error "${ERROR_MSG}"
}


###############################################################################
#
# Warn about directories that aren't Pharo apps, yet have no subdirectories.
#
Warn_If_Not_Pharo_Directory () {
    local THIS_DIR=${1}
    local ERROR_MSG

    if [[ -n "${THIS_DIR}" ]]; then
        THIS_DIR="'${THIS_DIR}'"
    else
        THIS_DIR="<argument not provided>"
    fi

    printf -v ERROR_MSG "%s \n%s %s " \
        "Nothing to do!  Directory ${THIS_DIR}" \
        "is not a Pharo application directory," \
        "and it has no Pharo app subdirectories."

    Display_Error "${ERROR_MSG}"
}


###############################################################################
#
# Warn if the working directory appears to be a virtual machine directory.
#
Warn_of_Virtual_Machine_Directory () {
    local VM_DIRECTORY=${1}
    local ERROR_MSG

    if [[ -n "${VM_DIRECTORY}" ]]; then
        VM_DIRECTORY="'${VM_DIRECTORY}'"
    else
        VM_DIRECTORY="<argument not provided>"
    fi

    printf -v ERROR_MSG "%s " \
        "Ignoring directory ${VM_DIRECTORY}: virtual machine directory?"

    Display_Error "${ERROR_MSG}"
}


###############################################################################
#
# Warn about recognized Pharo app directories that have no scripts in them.
#
Warn_of_App_Without_Scripts () {
    local TARGET=${1}
    local ERROR_MSG

    # Both WORKING_DIRECTORY & PHARO_APP_NAME should be defined
    # if/when this function is called...
    printf -v ERROR_MSG "%s %s \n%s " \
        "Directory '${WORKING_DIRECTORY}'" \
        "appears to be a ${PHARO_APP_NAME}" \
        "directory, but it doesn't contain any ${TARGET}."

    Display_Error "${ERROR_MSG}"
}


###############################################################################
#
# Notify the user of files that we're modifying.
#
Notify_of_File_Modified () {
    local FILE_PATH=${1}
    local EDIT_RESULT=${2}

    # If there are any arguments, the first one must be a file...
    [[ -z "${FILE_PATH}" || ! -f "${FILE_PATH}" ]] && \
        FILE_PATH="<argument not provided>"

    # Note that $2 is optional, and if missing, there is no side effect.
    Display_Message "Editing file '${FILE_PATH}'... ${EDIT_RESULT}"
}


###############################################################################
#
# Ensure the provided argument is a valid directory path.
#
Ensure_is_a_Directory () {

    # $1 must be provided, and it must be a directory, else fatal error.
    [[ -n "${1}" &&  -d "${1}" ]] && return

    Warn_of_Bad_Argument "${FUNCNAME}" && die
}


###############################################################################
#
# Ensure that the provided argument is a valid directory, but not a VM dir.
#
Ensure_is_Not_a_VM_Directory () {
    local THIS_DIR=${1}
    local ERROR_MSG

    # First, we must have an argument, and it must be a directory path:
    Ensure_is_a_Directory "${THIS_DIR}"

    # Additionally, the path must not match a string indicating a Pharo VM.
    [[ ! "${THIS_DIR}" =~ ${VM_TAG} ]] && return

    return $VM_DIR
}



###############################################################################
###############################################################################
#




###############################################################################
#
Parse_Command_Line () {
    # [-h|-u] [[-i] /inst/folder[/<inst.zip>]] [[-d] /dest/folder]

    # Get the command line switches, as either '-s' or '--switch'.
    COMMAND_LINE_SWITCH=${1,,}
    COMMAND_LINE_SWITCH=${COMMAND_LINE_SWITCH##*-}
}


###############################################################################
#
Main () {
    # Read & parse the command line parameters.
    Parse_Command_Line "${@}"

    case ${COMMAND_LINE_SWITCH} in
    'u' )
        Display_Usage && die
        ;;
    'h' )
        Display_Help && die
        ;;
    * )
        echo "Doing this-and-that..."
    esac
}

Main "$@"
