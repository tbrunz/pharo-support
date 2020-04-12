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

UNZIP_APPLICATION=unzip
REPO_INSTALL_APP=apt-get
REPO_INSTALL_CMD=install

TEMPORARY_DIRS=()


###############################################################################
###############################################################################
#
# Function return codes
#
SUCCESS=0
GEN_FAILURE=1
CANCEL=2
NOT_FOUND=3
REJECTED=4
NO_MATCH=5
CANT_CREATE=6
CMD_FAIL=7
BAD_SWITCH=8


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
# This is the exit point for the script.
#
die () {
    # Remove any temporary files & directories we may have created.
    Remove_Temporaries

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
# Divest ourselves of any temporaries we created.
#
Remove_Temporaries () {
    local THIS_DIR

    # Did we create any temporary directories?
    if (( ${#TEMPORARY_DIRS[@]} > 0 )); then

        # Delete each one, and their contents, without care for errors.
        for THIS_DIR in "${TEMPORARY_DIRS[@]}"; do
            rm -rf "${THIS_DIR}"
        done
    fi
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
# Notify the user that
#
Error_Corrupted_Installer_Paths () {
    Display_Error "" $BAD_SWITCH
}


###############################################################################
#
# Notify the user that this function call requires a parameter.
#
Error_Missing_Parameter () {
    Display_Error "Missing/corrupt function parameter '${1}'" $BAD_SWITCH
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
# Warn if a temporary directory could not be created
#
Warn_of_No_Temp_Directory () {

    Display_Error "Cannot create a temporary directory (in /tmp)!"
}


###############################################################################
#
# Warn if an 'unzip' app was not found and could not be installed
#
Warn_of_No_Unzip_App () {

    Display_Error "Cannot find or install an unzip application!"
}


###############################################################################
#
# Warn if a repository package manager could not be found
#
Warn_of_No_Repo_Install_App () {

    Display_Error "Cannot find a package install application!"
}


###############################################################################
#
# Warn if the ZIP package file could not be unzipped
#
Warn_Cannot_Unzip_File () {

    Display_Error "Cannot unzip the application ZIP file!"
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
#
# If we're directed to use a ZIP file containing the target, then we need
# an unzip utility to extract it.  Ensure that this app is installed in
# the system; if not, try to install it.  Return non-zero on failure.
#
Ensure_Unzip_Installed () {

    # To unzip the installer ZIP file, we need an 'unzip' application.
    which "${UNZIP_APPLICATION}" &> /dev/null

    # If it's already installed, we're done.
    (( $? == 0 )) && return $SUCCESS

    # Otherwise, see if we can install it.
    which "${REPO_INSTALL_APP}" &> /dev/null

    # We need a repo install app or we can't fix this situation.
    (( $? == 0 )) || return $NOT_FOUND

    # Don't install software without first getting the user's permission.
    Get_User_Choice -y "Okay to install '${UNZIP_APPLICATION}'?"

    # If they say 'no', we can't go on...
    (( $? == 0 )) || return $REJECTED

    # Ask the repo manager to install our unzip application.
    "${REPO_INSTALL_APP}" "${REPO_INSTALL_CMD}" "${UNZIP_APPLICATION}"

    # Did it work?  We need that unzip app or we can't fix this situation.
    (( $? == 0 )) || return $CMD_FAIL

    # Finally, verify that we installed what we intended.
    which "${UNZIP_APPLICATION}" &> /dev/null
}


############################################################################
#
# Display a prompt asking for a one-char response, repeat until a valid input
#
# Automatically appends the default to the prompt, capitalized.
# Allows for a blank input, which is interpreted as the default.
#
# $1 = Default input (-x | x) | List of options | Prompt
# $2 = list of [<options>] | Prompt
# $3 = Prompt
#
# Returns 0 if input==default, 1 otherwise
# The first character of the user's input, lowercased, goes into $REPLY
#
# Get_User_Choice --> "Continue? [Y/n]"
# Get_User_Choice "<prompt>" --> "<prompt> [Y/n]"
# Get_User_Choice (y|n|-y|-n) "<prompt>" --> "<prompt> ([Y/n]|[y/N])"
#
# Get_User_Choice "[<list>]" "<prompt>" --> "<prompt> [<list>]"
#     No default; requires an input in the list, returned in $REPLY
#
# Get_User_Choice <def> "[<list>]" "<prompt>" --> "<prompt> [<list>]"
#     Defaulted input; requires an input in the list, returned in $REPLY
#
Get_User_Choice () {
    local OPTIONS
    local DEFAULT="y"
    local PROMPT

    if (( $# == 0 )); then
        PROMPT="Continue?"

    elif (( $# == 1 )); then
        PROMPT=${1}

    elif (( $# == 2 )); then
        PROMPT=${2}
        DEFAULT=$( GetOpt "${1}" )

        if [[ "${DEFAULT}" == "[" ]]; then
            DEFAULT=
            OPTIONS=${1}
            OPTIONS=${OPTIONS##[}
            OPTIONS=${OPTIONS%%]}
        fi
    else
        PROMPT=${3}
        DEFAULT=$( GetOpt "${1}" )
        OPTIONS=${2}

        if [[ "${DEFAULT}" == "[" ]]; then
            DEFAULT=$( GetOpt "${2}" )
            OPTIONS=${1}
        fi

        OPTIONS=${OPTIONS##[}
        OPTIONS=${OPTIONS%%]}

        isSubString "${DEFAULT}" "${OPTIONS}"
        (( $? == 0 )) || DEFAULT=
    fi

    if [[ ${OPTIONS} ]]; then
        OPTIONS=${OPTIONS,,}

        if [[ ${DEFAULT} ]]; then
            OPTIONS=${OPTIONS/${DEFAULT}/${DEFAULT^}}
        fi

        PROMPT=${PROMPT}" [${OPTIONS}] "
    else
        case ${DEFAULT} in
        y )
            PROMPT=${PROMPT}" [Y/n] "
            ;;
        n )
            PROMPT=${PROMPT}" [y/N] "
            ;;
        * )
            PROMPT=${PROMPT}" [${DEFAULT^}]"
            ;;
        esac
    fi

    unset REPLY
    until [[ "${REPLY}" == "y" || "${REPLY}" == "n" ]]; do

        read -e -r -p "${PROMPT}"

        if [[ -z "${REPLY}" ]]
        then
            REPLY=${DEFAULT}
        else
            REPLY=$( GetOpt "${REPLY}" )
            [[ "${REPLY}" == "/" ]] && REPLY=
        fi

        if [[ ${OPTIONS} && -n "${REPLY}" ]]; then
            isSubString "${REPLY}" "${OPTIONS}"

            if (( $? == 0 )); then return
            else REPLY=
            fi
        fi
    done

    [[ "${REPLY}" == "y" ]]
}


###############################################################################
#
# Push the search/display paths onto "the stack".
#
Push_Search_Paths () {
    # Ensure that we have two arguments to push, both viable paths.
    [[ -r "${1}" ]] || Error_Missing_Parameter "Search Path"
    [[ -r "${2}" ]] || Error_Missing_Parameter "Display Path"

    # Bash makes pushing something on the end of an array trivial...
    STACK_OF_SEARCH_PATHS+=( "${1}" )
    STACK_OF_DISPLAY_PATHS+=( "${2}" )
}


###############################################################################
#
# Pop the search/display paths from "the stack".
#
# This uses 4 globals: 2 inputs and 2 state variables.
#
Pop_Search_Paths () {
    local HEAD_INDEX

    # Set the "return values" to nil, in case the stack is empty.
    THIS_SEARCH_PATH=
    THIS_DISPLAY_PATH=

    # Get the index of the last element in the stack array.
    HEAD_INDEX=$(( ${#STACK_OF_SEARCH_PATHS[@]} - 1 ))

    # If the stack has nothing in it, we're done.
    (( ${HEAD_INDEX} >= 0 )) || return $NOT_FOUND

    # Take the last items off the stacks.
    THIS_SEARCH_PATH=${STACK_OF_SEARCH_PATHS[ ${HEAD_INDEX} ]}
    THIS_DISPLAY_PATH=${STACK_OF_DISPLAY_PATHS[ ${HEAD_INDEX} ]}

    # To remove from an array, 'unset' the element.
    unset STACK_OF_SEARCH_PATHS[${HEAD_INDEX}]
    unset STACK_OF_DISPLAY_PATHS[${HEAD_INDEX}]
}


###############################################################################
#
# Initialize 'the stack' of candidate installer/launcher paths.
#
# Maintain two parallel stacks, one for paths that we're searching
# or have discovered something in; the other needs to parallel the
# first, to hold the originating path --one the user will recognize.
#
Initialize_Search_Stack () {
    local SEARCH_PATH

    # The list of candidate search paths must not be empty...
    (( ${#INSTALLER_SEARCH_PATHS[@]} > 0 )) || return $CANT_CREATE

    # Create a pair of empty stacks, to be operated in parallel.
    STACK_OF_SEARCH_PATHS=( )
    STACK_OF_DISPLAY_PATHS=( )

    # Load the search stacks with the user-provided or default search list.
    for SEARCH_PATH in "${INSTALLER_SEARCH_PATHS[@]}"; do

        # The stack pushes the above two globals into two global arrays.
        Push_Search_Paths "${SEARCH_PATH}" "${SEARCH_PATH}"
    done
}


###############################################################################
###############################################################################
#
# Now that we have a chosen installation directory, install it.
#
Install_Pharo_Launcher () {

    # Installing to ${DESTINATION_PATH}
    echo "Installing '${INSTALL_PATH}' to '${DESTINATION_PATH}'... "

}


###############################################################################
###############################################################################
#
# Given $INSTALL_CHOICE, a path in $INSTALLER_PATHS_DISPLAY, find the
# corresponding path in $INSTALLER_PATHS_FOUND and set it in $INSTALL_PATH.
#
Get_Found_Path_From_Display_Path () {
    local INDEX

    # The list we're going to look through must not be empty.
    # (This shouldn't happen -- the user picked from this list.)
    if (( ${#INSTALLER_PATHS_DISPLAY[@]} > 0 )); then

        # Loop through the array of candidate paths by index rather than by
        # element.  Why use an index?  To achieve parallel list access.
        for (( INDEX=0; INDEX<${#INSTALLER_PATHS_DISPLAY[@]}; INDEX++ )); do

            # The user set $INSTALL_CHOICE based on a string in  DISPLAY list.
            # If his choice fails to match this element, go to the next one.
            [[ "${INSTALLER_PATHS_DISPLAY[${INDEX}]}" == \
                "${INSTALL_CHOICE}" ]] || continue

            # We have a match; the index to the match indexes the other list.
            INSTALL_PATH=${INSTALLER_PATHS_FOUND[${INDEX}]}
            return $SUCCESS
        done
    fi

    # If we got this far, we've either exhausted the list and failed to find
    # a match, or the list had no elements in it.  Neither case should
    # happen, since the user picked from this list.  So this is an error.
    Error_Corrupted_Installer_Paths && die $NOT_FOUND
}


###############################################################################
#
# Put up a menu of found installers/launchers & let the user choose one.
#
# Global $INSTALL_CHOICE is the return, a path from $INSTALLER_PATHS_DISPLAY.
# The user has the option of cancelling; if so, return non-zero.
#
Select_From_Menu_of_Multiple_Paths () {
    local OLD_PROMPT
    local CANCEL_TEXT="<cancel>"

    # Preserve $PS3, then set it to prompt for our menu choice.
    OLD_PROMPT=${PS3}
    PS3="Which path to install?"

    # Dialog boxes need a title...
    echo
    echo "Please make a choice from among the following paths: "

    # Use the list in $INSTALLER_PATHS_DISPLAY, but add a 'cancel' to the end.
    select INSTALL_CHOICE in \
        "${#INSTALLER_PATHS_DISPLAY[@]}" "${CANCEL_TEXT}"; do

        # Any empty newline will result in an automatic redisplay.  A number
        # out of range, or garbage, will set the select variable to NULL.
        [[ -n "${INSTALL_CHOICE}" ]] && break

        # Bark at the user if they don't enter a valid choice, then re-do.
        echo "Just pick one of the listed options, okay? "
    done

    # Restore $PS3 to whatever it was originally.
    PS3=${OLD_PROMPT}

    # Return non-zero if the user picked the cancel menu item.
    if [[ "${INSTALL_CHOICE}" == "${CANCEL_TEXT}" ]]; then
        echo 1>&2 "Cancelling ... "
        return $CANCEL
    fi
}


###############################################################################
#
# We found 0, 1, or many installers/folders; Decide how to handle them.
#
# Global $INSTALL_CHOICE is the return, a path from $INSTALLER_PATHS_FOUND.
# Non-zero return means 'do not proceed with the installation'.
#
Choose_or_Approve_Found_Path () {
    local NUMBER_OF_PATHS

    # How many install paths did we resolve?
    NUMBER_OF_PATHS=${#INSTALLER_PATHS_FOUND[@]}

    # If no install paths were resolved, there's nothing to do!
    if (( ${NUMBER_OF_PATHS} < 1 )); then

        echo "Could not find anything to install!  Exiting..."
        return $NOT_FOUND
    fi

    # If only one install path was resolved, ask if we should use it.
    if (( ${NUMBER_OF_PATHS} == 1 )); then

        # Set the same variable used by the 'select' function.
        INSTALL_CHOICE=${INSTALLER_PATHS_DISPLAY[0]}

        # There's only one choice: Use this one or 'cancel'.
        echo "Found path '${INSTALL_CHOICE}' "

        Get_User_Choice -y "Use this path?"
        (( $? == 0 )) || return $REJECTED
    fi

    # If multiple paths were resolved, provide a selection to choose from.
    if (( ${NUMBER_OF_PATHS} > 1 )); then

        Select_From_Menu_of_Multiple_Paths
        (( $? == 0 )) || return $CANCEL
    fi
    # The user picked a 'display' path, which gives as a string (a path);
    # But we can't use that, directly.  We need to translate the 'display'
    # path into its corresponding 'found' path, and install that path.
    Get_Found_Path_From_Display_Path
}


###############################################################################
###############################################################################
#
Search_This_DirPath_for_Files () {
    local THIS_FILE

    # Ensure that the path global is a directory.
    [[ -d "${THIS_PATH}" ]] || return $NOT_FOUND

    # Check each 'file' in the directory given by the path global.
    for THIS_FILE in "${THIS_PATH}"/*; do
        #
        [[ "${THIS_FILE}" =~ ${TARGET_FILE_GREP} ]] || continue
        # We only need one match
        MATCHED_FILE=${THIS_FILE}
        return $SUCCESS
    done

    return $NOT_FOUND
}


###############################################################################
#
Resolve_Directory_with_Zip () {
    local THIS_FILE

    # If this path is not a directory, we can't resolve it.
    [[ -d "${THIS_SEARCH_PATH}" ]] || return $NO_MATCH

    # Examine each 'file' in this directory to find our ZIP file.
    TARGET_FILE_GREP="${ZIP_FILE_ROOT_NAME_GREP}.zip"

    # Does this directory contain a match?
    for THIS_FILE in "${THIS_SEARCH_PATH}"/*; do

        [[ "${THIS_FILE}" =~ ${TARGET_FILE_GREP} ]] || continue

        # For a match, push the path on the stack, as both types.
        Push_Search_Paths "${THIS_SEARCH_PATH}/${THIS_FILE}" \
            "${THIS_SEARCH_PATH}/${THIS_FILE}"
    done
}


###############################################################################
#
Resolve_Installer_Zip_File () {
    local BASE_NAME
    local ZIP_FILE_PATH

    # If this path is not a file, we can't resolve it.
    [[ -f "${THIS_SEARCH_PATH}" ]] || return $NO_MATCH

    # Need the basename for pattern grepping.
    BASE_NAME=$( basename "${THIS_SEARCH_PATH}" )

    # If the file name doesn't end in '.zip', we can't resolve it.
    [[ "${BASE_NAME##*.}" == "zip" ]] || return $NO_MATCH

    # If this path doesn't match the grep pattern, we can't resolve it.
    [[ "${BASE_NAME}" =~ ${ZIP_FILE_ROOT_NAME_GREP} ]] || return $NO_MATCH

    # It's one of our zip files...  We need to have 'unzip' installed.
    Ensure_Unzip_Installed || Warn_of_No_Unzip_App && die $NOT_FOUND

    # We also need a temporary directory to unzip it into.
    ZIP_FILE_PATH=${THIS_SEARCH_PATH}
    THIS_SEARCH_PATH=$( mktemp -q -d )

    # We need to have acquired a temp directory.
    (( $? == 0 )) || Warn_of_No_Temp_Directory && die $CANT_CREATE

    # Remember this directory path, so we can remove it when we're done.
    TEMPORARY_DIRS+=( "${THIS_SEARCH_PATH}" )

    # Unzip the ZIP file found into the temp directory (our new path).
    "${UNZIP_APPLICATION}" "${ZIP_FILE_PATH}" -d "${THIS_SEARCH_PATH}"

    # We need to have successfully unzipped the zip package.
    (( $? == 0 )) || Warn_Cannot_Unzip_File && die $CMD_FAIL

    # Since this worked, return with $THIS_SEARCH_PATH pointing to the
    # directory containing the ZIP file contents; $THIS_DISPLAY_PATH does
    # *not* change, however -- it's still the originating path.  On return,
    # the caller will think this target was always an unzipped directory.
}


###############################################################################
#
Resolve_Directory_with_Unzipped () {
    echo "${USAGE_PROMPT}"
}


###############################################################################
#
Resolve_Unzipped_Directory () {
    echo "${USAGE_PROMPT}"
}


###############################################################################
#
Resolve_Install_Candidates () {
    # Start a list of installer search paths, as there may be more than one.
    # We need two arrays for paths: one to show the user + one which is the
    # path to the expanded/located/resolved target directory.
    INSTALLER_PATHS_FOUND=( )
    INSTALLER_PATHS_DISPLAY=( )

    # Initialize the search stacks, loading them with the candidate paths.
    Initialize_Search_Stack
    (( $? == 0 )) || return $CANT_CREATE

    # Search for installer zip files, or folders of Pharo Launcher files.
    while true; do
        # Pop a path off the stack of search paths, setting $THIS_SEARCH_PATH
        # and $THIS_DISPLAY_PATH.  If this fails, the stack is empty.
        Pop_Search_Paths
        (( $? == 0 )) || break

        # If we can't read the 'file' path, we can't do anything with it!
        [[ ! -r "${THIS_SEARCH_PATH}" ]] && continue

        # For each test, below, evaluate the indicated condition. Either
        # the condition doesn't apply (return), or, if it does, the call
        # will reduce it to one of the following, and adjust ${THIS_PATH}.

        # Test 1 = Is this path a directory containing an installer zip?
        Resolve_Directory_with_Zip "${THIS_SEARCH_PATH}"

        # Test 2 = Is this path an installer zip file?
        Resolve_Installer_Zip_File "${THIS_SEARCH_PATH}"

        # Test 3 = Is this path a directory containing the expanded zip dir?
        Resolve_Directory_with_Unzipped "${THIS_SEARCH_PATH}"

        # Test 4 = Is this path the expanded zip file directory?
        Resolve_Unzipped_Directory "${THIS_SEARCH_PATH}"
        (( $? == 0 )) && continue

        # Test 5 = Is this path a previously-installed launcher directory?
        Resolve_Pharo_Launcher_Directory "${THIS_SEARCH_PATH}"
        (( $? == 0 )) && continue
    done
}


###############################################################################
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
Validate_User_Inputs () {

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
}


###############################################################################
###############################################################################
#
Main () {
    # Read & parse the command line parameters.
    Parse_Command_Line "${@}"

    # Examine what we found and bark at invalid/non-sensical inputs.
    Validate_User_Inputs
    (( $? == 0 )) || return $BAD_SWITCH

    # Use the search path list to find/resolve installation candidates.
    Resolve_Install_Candidates
    (( $? == 0 )) || return $NOT_FOUND

    # Ask the user to select one of the installation candidates.
    Choose_or_Approve_Found_Path
    (( $? == 0 )) || return $CANCEL

    # Using the list of candidates, install per the user's wishes.
    Install_Pharo_Launcher
}

Main "$@"
