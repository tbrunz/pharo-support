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
    "."
    "${HOME}/Downloads"
    "${HOME}"
)

DEFAULT_DESTINATION="${HOME}/Pharo"

USAGE_INSTALLER="[[-i] /inst/folder[/<inst.zip>]]"
USAGE_DESTINATION="[[-d] /dest/folder]"
USAGE_PROMPT="usage: ${THIS_APP} ${USAGE_INSTALLER} ${USAGE_DESTINATION}"


###############################################################################
###############################################################################
#
Display_Usage () {
    echo "${USAGE_PROMPT}"
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
BAD_SWITCH=1


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
# Notify the user that this command line switch must be the only argument.
#
Error_Invalid_Switch () {
    Display_Error "Invalid switch '${1}': must appear by itself" $BAD_SWITCH
}


###############################################################################
#
# Notify the user that this command line switch was found more than once.
#
Error_Duplicate_Switch () {
    Display_Error "Duplicate command line switch: '${1}'" $BAD_SWITCH
}


###############################################################################
#
# Notify the user that the command line switch is not recognized.
#
Error_Unknown_Switch () {
    Display_Error "Unknown command line switch, '${1}' " $BAD_SWITCH
}


###############################################################################
#
# Notify the user that this command line switch requires an argument.
#
Error_Missing_Argument () {
    Display_Error "Missing argument for switch '${1}'" $BAD_SWITCH
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
Install_Pharo_Launcher () {
    echo "installing to '${DESTINATION_PATH}' "
    echo "searching for installers in "
    for PATH in "${INSTALLER_SEARCH_PATHS[@]}"; do
        echo "    '${PATH}' "
    done
}


###############################################################################
#
Process_Switch () {
    local ARG1=${1}
    local ARG2=${2}

    # Reduce the switch to the lower-case version of its first character.
    SWITCH=${ARG1:0:1}
    SWITCH=${SWITCH,,}

    # If ARG2 is also a switch, ignore it & return the ARG1 switch.
    [[ "${ARG2:0:1}" == "-" ]] && return

    # If the switch is a type that does not have an argument, return it.
    [[ "${SWITCH}" == 'u' ]] && return
    [[ "${SWITCH}" == 'h' ]] && return

    # Then this is a switch that must have an argument, so consume ARG2.
    PARAMETER=${ARG2}
    DOUBLE_SHIFT=true
}


###############################################################################
#
Parse_Parameters () {
    local ARG1=${1}
    local ARG2=${2}

    # We need to set three globals as a result of parsing ARG1/ARG2.
    SWITCH=""
    PARAMETER=""
    DOUBLE_SHIFT=""

    # If this is not a switch, return it as a parameter & ignore ARG2.
    if [[ "${ARG1:0:1}" != "-" ]]; then
        PARAMETER=${ARG1}
        return
    fi

    # Remove the leading '-'.
    ARG1=${ARG1#?}

    # If the parameter starts with only one '-', it's a standalone switch.
    if [[ "${ARG1:0:1}"  != '-' ]]; then
        Process_Switch "${ARG1}" "${ARG2}"
        return
    fi

    # Remove the second '-'.
    ARG1=${ARG1#?}

    # Now start looking for an '=' sign.
    for (( THIS_CHAR=0; THIS_CHAR<${#ARG1}; THIS_CHAR++ )); do

        if [[ "${ARG1:${THIS_CHAR}:1}" == '=' ]]; then
            # Split the ARG1 string into two & ignore ARG2.
            THIS_CHAR=$(( ++THIS_CHAR ))
            ARG2=${ARG1:${THIS_CHAR}}

            # Process the switch part & the parameter part separately.
            Process_Switch "${ARG1}" "${ARG2}"

            # We must NOT shift twice, since we split ARG1 in this case.
            DOUBLE_SHIFT=""
            return
        fi
    done

    # If we reach this point, then there is no '=' in ARG1.
    # In this case, treat it as though it were a standalone switch.
    Process_Switch "${ARG1}" "${ARG2}"
}


###############################################################################
#
Parse_Command_Line () {
    USAGE_SWITCH=
    HELP_SWITCH=
    INSTALLER_PATH=
    DESTINATION_PATH=
    DUPLICATE_SWITCH=

    # One by one, step through the list of command line parameters.
    while [[ -n "${1}" ]]; do

        # Parse this parameter + the following, to allow for '-s <arg>'.
        Parse_Parameters "${1}" "${2}"

        case ${SWITCH} in
        'u' )
            if [[ -z "${USAGE_SWITCH}" ]]; then
                USAGE_SWITCH="-u"
            else
                [[ -z "${DUPLICATE_SWITCH}" ]] && DUPLICATE_SWITCH=${SWITCH}
            fi
            ;;
        'h' )
            if [[ -z "${HELP_SWITCH}" ]]; then
                HELP_SWITCH="-h"
            else
                [[ -z "${DUPLICATE_SWITCH}" ]] && DUPLICATE_SWITCH=${SWITCH}
            fi
            ;;
        'i' )
            [[ -n "${PARAMETER}" ]] || Error_Missing_Argument "-${SWITCH}"

            if [[ -z "${INSTALLER_PATH}" ]]; then
                INSTALLER_PATH=${PARAMETER}
            else
                [[ -z "${DUPLICATE_SWITCH}" ]] && DUPLICATE_SWITCH=${SWITCH}
            fi
            ;;
        'd' )
            [[ -n "${PARAMETER}" ]] || Error_Missing_Argument "-${SWITCH}"

            if [[ -z "${DESTINATION_PATH}" ]]; then
                DESTINATION_PATH=${PARAMETER}
            else
                [[ -z "${DUPLICATE_SWITCH}" ]] && DUPLICATE_SWITCH=${SWITCH}
            fi
            ;;
        * )
            Error_Unknown_Switch "${SWITCH}"
            ;;
        esac

        shift
        [[ -n "${DOUBLE_SHIFT}" ]] && shift
    done
}


###############################################################################
#
Main () {
    # Read & parse the command line parameters.
    Parse_Command_Line "${@}"

    # The 'usage' switch must appear by itself.
    if [[ -n "${USAGE_SWITCH}" ]]; then
        [[ -n "${HELP_SWITCH}${INSTALLER_PATH}${DESTINATION_PATH}" ]] && \
            Error_Invalid_Switch "${USAGE_SWITCH}"
        Display_Usage && die
    fi

    # The 'help' switch must appear by itself.
    if [[ -n "${HELP_SWITCH}" ]]; then
        [[ -n "${USAGE_SWITCH}${INSTALLER_PATH}${DESTINATION_PATH}" ]] && \
            Error_Invalid_Switch "${HELP_SWITCH}"
        Display_Help && die
    fi

    # There must be no duplicate switches.
    if [[ -n "${DUPLICATE_SWITCH}" ]]; then
        Error_Duplicate_Switch "-${DUPLICATE_SWITCH}"
    fi

    # If the destination path is missing, default it.
    [[ -n "${DESTINATION_PATH}" ]] || DESTINATION_PATH=${DEFAULT_DESTINATION}

    # If the installer path is provided, substitute it for the search list.
    [[ -n "${INSTALLER_PATH}" ]] && \
        INSTALLER_SEARCH_PATHS=( "${INSTALLER_PATH}" )

    # At this point, we have a valid command line, so install.
    Install_Pharo_Launcher
}

Main "$@"
