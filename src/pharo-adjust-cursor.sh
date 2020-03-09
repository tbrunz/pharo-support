#! /usr/bin/env bash
#

###############################################################################
#
# Application-specific operating parameters
#
# These values should be valid over the long-term.
# Edit & save the script to update if Pharo Project changes these.
#

# $VM_TAG is used to identify directory paths for Pharo virtual machines.
VM_TAG="vm"
VM_ENV_VAR="SQUEAK_FAKEBIGCURSOR"

# Create an associative array of tags to be matched in file names, which
# will uniquely indentify the type of Pharo application a directory holds.
# An array will allow use of a loop to locate the matching app file names.
declare -A PHARO_APP_KEYWORDS=(
    ["KEYWORD_APP_PHARO_LAUNCHER"]="pharo-launcher"
    ["KEYWORD_APP_PHARO_THINGS"]="PharoThings"
)

# Create an associative array of Pharo application name scrings.
# These allow us to translate a tag that matches a file name to a
# string which is more suitable for use in user messages.
declare -A PHARO_APP_NAMES=(
    ["${PHARO_APP_KEYWORDS["KEYWORD_APP_PHARO_LAUNCHER"]}"]="Pharo Launcher"
    ["${PHARO_APP_KEYWORDS["KEYWORD_APP_PHARO_THINGS"]}"]="Pharo IoT"
)

# Create an associative array of file names of the bash scripts that
# we're targeting for modification.  We will attempt to make exact
# matches of file names to these strings to select files for editing.
declare -A PHARO_SCRIPT_NAMES=(
    ["SCRIPT_NAME_PHARO_LAUNCHER"]="pharo-launcher"
    ["SCRIPT_NAME_PHARO_THINGS_APP"]="pharo"
    ["SCRIPT_NAME_PHARO_THINGS_GUI"]="pharo-ui"
)

# Create an associative array of notification phrases that will be used to
# select the editing action for bash scripts that are to be modified, and
# will also be used in messages to notify the user what was done.
declare -A SCRIPT_EDIT_ACTIONS=(
    ["INSERT_BIG_CURSOR"]="inserted"
    ["REMOVE_BIG_CURSOR"]="removed"
)

# Create an associative array of file name extensions that will be used
# to name backup files created before editing the bash scripts.
declare -A SCRIPT_BACKUP_EXTENSIONS=(
    ["${SCRIPT_EDIT_ACTIONS["INSERT_BIG_CURSOR"]}"]="original"
    ["${SCRIPT_EDIT_ACTIONS["REMOVE_BIG_CURSOR"]}"]="bigcursor"
)


###############################################################################
###############################################################################
#
Display_Usage () {
    local APP

    APP=$( basename ${0} '.sh' )

    echo "
usage: ${APP} [i|b|f|a|y] (install big cursor) [r|s|o|d|n] (restore original)

    This script will edit bash scripts that launch Pharo applications
    (i.e., pharolauncher, pharoiot, etc.) to either enable or disable
    enlarging the GUI pointer.  This is useful on Linux systems with
    a 4K hi-DPI screen, since currently, Pharo can enlarge its fonts
    and other GUI features, but not the cursor.

    The cursor is enlarged by first setting an environment variable,
    ${VM_ENV_VAR}, to a non-zero value prior to running the
    application script (i.e., pharo-launcher, pharo-ui, etc.).  This
    script achieves this by editing the app scripts to add an 'env'
    prefix to the commands that launch a Pharo virtual machine.

    ${APP} can edit the Pharo application scripts in both
    directions, to add the 'env' prefix or remove it, depending on
    the option switch included on the command line.  There are no
    side-effects if the same command is issued multiple times in a
    row.  Each edit will create a backup file, with a name extension
    appended that reflects the script version backed up.  Restoring
    a backup must be done manually.
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
# Patterns in the Pharo scripts to search for and replace with:
#
PATTERN_0="env[[:space:]]+${VM_ENV_VAR}=1"
PATTERN_1="env ${VM_ENV_VAR}=1"
PATTERN_2='exec'
PATTERN_3='"\$LINUX'
PATTERN_4='vm\/\$VM'


###############################################################################
#
# Rules for Pharo Launcher, file 'pharo-launcher':
#
# Example: ~/Pharo/pharolauncher/pharo-launcher
#
#    exec "$LINUX/pharo" \
#
#    exec env SQUEAK_FAKEBIGCURSOR=1 \
#        "$LINUX/pharo" \
#
PharoLauncher_InstallBigCursor () {
    sed -i -r -e "/${PATTERN_2}/ s|^([[:space:]]*${PATTERN_2}[[:space:]]+)(${PATTERN_3}.+)$|\1${PATTERN_1} \\\\\n\t\2|" \
        "${SCRIPT_PATH_TO_EDIT}"
}

PharoLauncher_RemoveBigCursor () {
    sed -i -r -e "/${PATTERN_0}/ N; s|^([[:space:]]*${PATTERN_2}[[:space:]]+)${PATTERN_0}.*\n[[:space:]]*(${PATTERN_3}.+)$|\1\2|" \
        "${SCRIPT_PATH_TO_EDIT}"
}


###############################################################################
#
# Rules for Pharo IOT, file 'pharo':
#
# Example: ~/Pharo/pharoiot/pharo
#
#    vm/$VM/pharo --headless PharoThings
#
#    env SQUEAK_FAKEBIGCURSOR=1 vm/$VM/pharo --headless PharoThings
#
PharoIOT_InstallBigCursor () {
    sed -i -r -e "/^[[:space:]]+${PATTERN_4}/ s|^([[:space:]]+)(${PATTERN_4}.+)$|\1${PATTERN_1} \2|" \
        "${SCRIPT_PATH_TO_EDIT}"
}

PharoIOT_RemoveBigCursor () {
    sed -i -r -e "/^[[:space:]]+${PATTERN_0}/ s|^([[:space:]]+)${PATTERN_0}[[:space:]]+(.*)$|\1\2|" \
        "${SCRIPT_PATH_TO_EDIT}"
}


###############################################################################
#
# Rules for Pharo IOT, file 'pharo-ui':
#
# Example: ~/Pharo/pharoiot/pharo-ui
#
#    vm/$VM/pharo PharoThings
#
#    env SQUEAK_FAKEBIGCURSOR=1 vm/$VM/pharo PharoThings
#
PharoUI_InstallBigCursor () {
    sed -i -r -e "/^[[:space:]]+${PATTERN_4}/ s|^([[:space:]]+)(${PATTERN_4}.+)$|\1${PATTERN_1} \2|" \
        "${SCRIPT_PATH_TO_EDIT}"
}

PharoUI_RemoveBigCursor () {
    sed -i -r -e "/^[[:space:]]+${PATTERN_0}/ s|^([[:space:]]+)${PATTERN_0}[[:space:]]+(.*)$|\1\2|" \
        "${SCRIPT_PATH_TO_EDIT}"
}


###############################################################################
#
# Create an associative array of function names to call for editing
# the Pharo application bash scripts.
#
# The keys to these will be assembled dynamically at run-time and
# used to select the function for modifying the target bash script.
#
declare -A CONVERSIONS

       KEY=${PHARO_APP_KEYWORDS["KEYWORD_APP_PHARO_LAUNCHER"]}
KEY=${KEY}_${PHARO_SCRIPT_NAMES["SCRIPT_NAME_PHARO_LAUNCHER"]}
KEY=${KEY}_${SCRIPT_EDIT_ACTIONS["INSERT_BIG_CURSOR"]}

CONVERSIONS[${KEY}]="PharoLauncher_InstallBigCursor"

       KEY=${PHARO_APP_KEYWORDS["KEYWORD_APP_PHARO_LAUNCHER"]}
KEY=${KEY}_${PHARO_SCRIPT_NAMES["SCRIPT_NAME_PHARO_LAUNCHER"]}
KEY=${KEY}_${SCRIPT_EDIT_ACTIONS["REMOVE_BIG_CURSOR"]}

CONVERSIONS[${KEY}]="PharoLauncher_RemoveBigCursor"

       KEY=${PHARO_APP_KEYWORDS["KEYWORD_APP_PHARO_THINGS"]}
KEY=${KEY}_${PHARO_SCRIPT_NAMES["SCRIPT_NAME_PHARO_THINGS_APP"]}
KEY=${KEY}_${SCRIPT_EDIT_ACTIONS["INSERT_BIG_CURSOR"]}

CONVERSIONS[${KEY}]="PharoIOT_InstallBigCursor"

       KEY=${PHARO_APP_KEYWORDS["KEYWORD_APP_PHARO_THINGS"]}
KEY=${KEY}_${PHARO_SCRIPT_NAMES["SCRIPT_NAME_PHARO_THINGS_APP"]}
KEY=${KEY}_${SCRIPT_EDIT_ACTIONS["REMOVE_BIG_CURSOR"]}

CONVERSIONS[${KEY}]="PharoIOT_RemoveBigCursor"

       KEY=${PHARO_APP_KEYWORDS["KEYWORD_APP_PHARO_THINGS"]}
KEY=${KEY}_${PHARO_SCRIPT_NAMES["SCRIPT_NAME_PHARO_THINGS_GUI"]}
KEY=${KEY}_${SCRIPT_EDIT_ACTIONS["INSERT_BIG_CURSOR"]}

CONVERSIONS[${KEY}]="PharoUI_InstallBigCursor"

       KEY=${PHARO_APP_KEYWORDS["KEYWORD_APP_PHARO_THINGS"]}
KEY=${KEY}_${PHARO_SCRIPT_NAMES["SCRIPT_NAME_PHARO_THINGS_GUI"]}
KEY=${KEY}_${SCRIPT_EDIT_ACTIONS["REMOVE_BIG_CURSOR"]}

CONVERSIONS[${KEY}]="PharoUI_RemoveBigCursor"


###############################################################################
###############################################################################
#
# Backup file constants
#
DEFAULT_FILE="tmp"
TEMPLATE_EXT="XXXX"

###############################################################################
#
# Clone the file to be edited to a new file with a unique name.
#
Make_Backup_File () {
    # If a backup extension is provided, TARGET_BACKUP_PATH will be defined.
    local BACKUP_EXTENSION=${2}

    # The backup file path becomes the return value -- as a global.
    BACKUP_FILE_PATH=${1}

    # If no file/dir path parameter is provided, default it.
    [[ -n "${BACKUP_FILE_PATH}" ]] || BACKUP_FILE_PATH=${DEFAULT_FILE}

    # Canonicalize the path to be a full absolute file/dir path.
    BACKUP_FILE_PATH=$( readlink -f -n "${BACKUP_FILE_PATH}" )

    # If the path is a directory path, default the filename part.
    [[ -d "${BACKUP_FILE_PATH}" ]] && \
        BACKUP_FILE_PATH="${BACKUP_FILE_PATH}/${DEFAULT_FILE}"

    # If provided, try to create the backup file with a given extension.
    if [[ -n "${BACKUP_EXTENSION}" ]]; then

        # Form the target backup path by adding the extension string to it.
        TARGET_BACKUP_PATH="${BACKUP_FILE_PATH}.${BACKUP_EXTENSION}"

        # This is also (tentatively) the file path we'll use for the backup.
        BACKUP_FILE_PATH=${TARGET_BACKUP_PATH}

        # If the desired file path is already in use, we will have to add
        # random characters to the extension to force it to be unique.
        # This is done by making the follow-on test be true.
        [[ -x "${BACKUP_FILE_PATH}" ]] && BACKUP_EXTENSION=""
    fi

    # If no extension was provided, or the target path is already in use,
    # add the template extension and let the OS determine & create the
    # backup file using a random string of alpha-numeric characters.
    if [[ -z "${BACKUP_EXTENSION}" ]]; then
        # Turn the path into a template for 'mktemp' to expand.
        BACKUP_FILE_PATH="${BACKUP_FILE_PATH}.${TEMPLATE_EXT}"

        # Create a file with a unique name extension.
        BACKUP_FILE_PATH=$( mktemp "${BACKUP_FILE_PATH}" ) || \
            return $CANT_WRITE
    fi

    # Create or overwrite the backup file with the file to be edited.
    cp -a "${SCRIPT_PATH_TO_EDIT}" "${BACKUP_FILE_PATH}" || \
        return $CANT_WRITE
}


###############################################################################
#
# Decide if we keep the backup file, and if so, make the name sensible.
#
Cleanup_Script_Backup () {
    local OLDER_BACKUP_PATH

    # Compare the edit result to the backup file; if these two files are
    # identical, then delete the useless backup file and we're done.
    diff "${BACKUP_FILE_PATH}" "${SCRIPT_PATH_TO_EDIT}" &>/dev/null

    if (( $? == 0 )); then
        Notify_of_File_Modified "${SCRIPT_PATH_TO_EDIT}" \
            "No changes made"

        # Delete the backup we just created, as it's no longer relevant.
        rm -f "${BACKUP_FILE_PATH}" && return
        return $CANT_WRITE
    fi

    # The edited file differs from the original, so keep the backup.
    # Notify the user that the script file was changed & how.
    Notify_of_File_Modified "${SCRIPT_PATH_TO_EDIT}" \
        "Code was ${SCRIPT_EDIT_ACTION}"

    # If the backup file path is the same as the target path, we're done.
    [[ "${BACKUP_FILE_PATH}" == "${TARGET_BACKUP_PATH}" ]] && return

    # If not, then the desired path is already in use by another file.
    # But it's possible that our backup matches this other file.
    # If this is the case, then we can delete our backup & we're done.
    diff "${BACKUP_FILE_PATH}" "${TARGET_BACKUP_PATH}" &>/dev/null

    if (( $? == 0 )); then
        # Appropriate the older backup by updating its date-time stamp.
        touch "${TARGET_BACKUP_PATH}" &>/dev/null

        # Delete the backup we just created, as it's no longer relevant.
        rm -f "${BACKUP_FILE_PATH}" && return
        return $CANT_WRITE
    fi

    # If our backup and the older backup are different, we need to keep
    # both files, but we still want to appropriate the target pathname.
    # Solution: Make another backup file with a randomized extension.
    OLDER_BACKUP_PATH=$( mktemp "${TARGET_BACKUP_PATH}.${TEMPLATE_EXT}" ) || \
        return $CANT_WRITE

    # Clone the older backup file to the file with the randomized extension.
    cp -a "${TARGET_BACKUP_PATH}" "${OLDER_BACKUP_PATH}" || \
        return $CANT_WRITE

    # And now rename our backup to have the target backup name.
    mv "${BACKUP_FILE_PATH}" "${TARGET_BACKUP_PATH}" || \
        return $CANT_WRITE
}


###############################################################################
#
# Create a backup for a file we're about to edit.
#
Backup_Script_File () {
    local BACKUP_EXTENSION

    # Make a backup filename extension, based on the edit action.
    BACKUP_EXTENSION=${SCRIPT_BACKUP_EXTENSIONS["${SCRIPT_EDIT_ACTION}"]}

    # Create a backup file using the file to edit & the extension.
    # This call will set BACKUP_FILE_PATH and TARGET_BACKUP_PATH.
    Make_Backup_File "${SCRIPT_PATH_TO_EDIT}" "${BACKUP_EXTENSION}" || \
        return $CANT_WRITE
}


###############################################################################
#
# For bash scripts we recognize, apply the requested edit action.
#
BASH_TAG="Bourne"

Edit_Pharo_Script () {
    local SCRIPT_NAME
    local EDIT_FUNCTION_KEY
    local EDIT_FUNCTION

    # The path to the script to edit is a global for the edit functions.
    SCRIPT_PATH_TO_EDIT=${1}

    # Must ensure that the argument is a valid path to a regular file.
    # Enhancement: Resolve links to scripts and treat as '-f'.
    [[ -f "${SCRIPT_PATH_TO_EDIT}" ]] || return $IGNORED

    # We only edit bash script files; skip other types of file.
    file "${SCRIPT_PATH_TO_EDIT}" | grep -q "${BASH_TAG}" || return $IGNORED

    # We need the file name to form a key to look up the edit function.
    SCRIPT_NAME=$( basename "${SCRIPT_PATH_TO_EDIT}" )

    # Form an associative array key from the Pharo application type,
    # the script name, and the editing action desired by the user.
    EDIT_FUNCTION_KEY=${PHARO_APP_KEYWORD}_${SCRIPT_NAME}_${SCRIPT_EDIT_ACTION}

    # Use the key to resolve the name of the function needed to edit the file.
    EDIT_FUNCTION=${CONVERSIONS["${EDIT_FUNCTION_KEY}"]}

    # If this key is bogus (i.e., the file is not a target bash script),
    # then the resolved function name will be a blank string.
    # This situation is not an error; it just means "not our file".
    [[ -n "${EDIT_FUNCTION}" ]] || return $IGNORED

    # Create a backup of the file before we edit it!
    Backup_Script_File || return $CANT_WRITE

    # Here's the payoff, the moment we've been waiting for...
    ${EDIT_FUNCTION} || return $CANT_WRITE

    # Clean up after ourselves -- Decide what to do with the backup file.
    Cleanup_Script_Backup
}


###############################################################################
#
# Process the set of files that were found in a Pharo app directory.
#
Process_Pharo_Files () {
    local NUM_PROCESSED=0

    # Having collected a list of files in the working directory,
    # we require that at least one filename matched a keyword for a
    # Pharo application.  If this is not the case, there's nothing to
    # do here, since we won't modify scripts that are not the scripts
    # of a Pharo application.  This isn't fatal, and is expected,
    # so don't display a warning or quit; just move on to the next.
    [[ -n "${PHARO_APP_KEYWORD}" ]] || return $NOT_APP

    # This is a directory that corresponds to a Pharo application
    # that we recognize.  'Globalize' its display name (for messages).
    PHARO_APP_NAME=${PHARO_APP_NAMES["${PHARO_APP_KEYWORD}"]}

    # If there aren't any files in this directory, issue a warning,
    # then abandon this directory and move on to the next one.
    (( ${#PHARO_FILE_PATHS[@]} < 1 )) && \
        Warn_of_App_Without_Scripts "files" && return $NO_FILES

    # Since this directory contains files, we expect to find at least
    # one target bash script to edit.  Check if the list of files
    # we've accumulated has at least one script.  If not, then issue a
    # warning; otherwise, assume it's a bash script and try to edit it.
    for FILE_PATH in "${PHARO_FILE_PATHS[@]}"; do
        # Assume each file is a bash script and attempt to edit it.
        Edit_Pharo_Script "${FILE_PATH}"

        # If it was successfully edited, then increment our counter.
        # If there's a write permissions issue, return that as an error.
        case $? in
        $SUCCESS )
            (( NUM_PROCESSED++ ))
            ;;
        $CANT_WRITE )
            # If we can't write/delete this file, we probably can't
            # write/delete for anything else in this directory.
            return $CANT_WRITE
            ;;
        esac
    done

    # If we edited at least one script, we were successful...
    (( NUM_PROCESSED > 0 )) && return

    # If we didn't edit any scripts, return an error; this is unexpected,
    # since we recognized this directory as a known Pharo application,
    # so there should have been at least one bash script to edit.
    return $NO_SCRIPTS
}


###############################################################################
#
# Recur one level into subdirectories, processing those that have Pharo apps.
#
Process_Subdirectories () {
    local NUM_PROCESSED=0

    # Do not process the subdirectories of a Pharo application directory.
    # Why? Because a Pharo application directory should not contain
    # subdirectories of other Pharo applications.  Having matched a
    # Pharo application keyword previously is sufficient indication
    # of this situation, so just ignore any subdirectories & return.
    # (Bash doesn't do recursion (easily) anyway, so it's just as well.)
    [[ -z "${PHARO_APP_KEYWORD}" ]] || return $IS_APP

    # Verify that we have at least one subdirectory to examine.
    (( ${#SUBDIRECTORIES[@]} > 0 )) || return $NO_DIRS

    # Important: Since we're about to recur into a set of subdirectories,
    # we *must* set a flag to *not* mess with SUBDIRECTORIES[],
    # because we're using it here to track our recursions.
    TOP_LEVEL=
    for SUBDIRECTORY in "${SUBDIRECTORIES[@]}"; do
        # Examine each subdirectory, one-by-one, but only check the
        # files we find in them; do not recur deeper in the filesystem.
        # The user must launch this script from either a Pharo app dir,
        # or from a directory containing Pharo app subdirs.  If launched
        # too high up in the directory tree, the check above will be
        # triggered, and nothing will be done (aside from a warning).
        Examine_Directory "${SUBDIRECTORY}"

        # Don't process unless an app subdirectory is found, and if
        # successful, move on to the next subdirectory.
        (( $? == IS_APP )) || continue

        # If the directory is a Pharo application, process its files.
        Process_Pharo_Files

        # If the file processing succeeds, increment the counter,
        # and if it failed, tell the user why.
        case $? in
        $SUCCESS )
            (( NUM_PROCESSED++ ))
            continue
            ;;
        $NO_FILES )
            Warn_of_App_Without_Scripts "files"
            ;;
        $NO_SCRIPTS )
            Warn_of_App_Without_Scripts "bash scripts"
            ;;
        $CANT_WRITE )
            Warn_of_Directory_Not_Writable "${WORKING_DIRECTORY}"
            ;;
        * )
            Warn_of_Bad_Return_Code "Process_Pharo_Files"
        esac
    done

    # If we successfully processed at least one directory, success.
    # Any other return code means nothing was edited.
    (( NUM_PROCESSED > 0 )) && return
}


###############################################################################
#
# Obtain a list of paths to files in the working directory, plus a list
# of subdirectories (and then only if this is the top-level directory).
# Data goes into globals.  Returns a code to indicate what was found.
#
Examine_Directory () {
    local FILE_NAME

    WORKING_DIRECTORY=${1}
    PHARO_APP_KEYWORD=""
    PHARO_FILE_PATHS=()

    # Check that the directory is a directory, but not a Pharo VM directory.
    Ensure_is_Not_a_VM_Directory "${WORKING_DIRECTORY}" || return $VM_DIR

    # One by one, examine each item found in the working directory:
    for FILE_PATH in "${WORKING_DIRECTORY}"/*; do

        # Determine what kind of 'file' this FILE_PATH is.  We're
        # interested in both bash script files and subdirectories.
        if [[ -d "${FILE_PATH}" ]]; then
            # If it's a directory, do NOT accumulate it in the list of
            # subdirectories UNLESS we're examining a top-level directory.
            # Otherwise, we would clobber an array being used in a loop!
            [[ -n "${TOP_LEVEL}" ]] && SUBDIRECTORIES+=( "${FILE_PATH}" )
        else
            PHARO_FILE_PATHS+=( "${FILE_PATH}" )
        fi

        # If we haven't yet matched an application keyword, then check
        # the filename against the list of known application keywords
        # that uniquely identify which Pharo app this directory holds.
        if [[ -z "${PHARO_APP_KEYWORD}" ]]; then
            # Examine just the file/directory name, not the full path.
            FILE_NAME=$( basename "${FILE_PATH}" )

            # Iterate through the list of keywords for known Phara apps.
            for APP_KEYWORD in "${PHARO_APP_KEYWORDS[@]}"; do

                # Try to match against just the filename, since the full
                # path could contain directory names that falsely match.
                PHARO_APP_KEYWORD=$( printf "%s" \
                    "${FILE_NAME}" | grep -o "${APP_KEYWORD}" )

                # If this file doesn't identify a Pharo app, then it will
                # remain an empty string, enabling the test on the next file.
                # Once we've made a match, stop checking in this directory.
                [[ -n "${PHARO_APP_KEYWORD}" ]] && break
            done
        fi
    done

    # If a keyword was matched, this is a recognized Pharo application.
    [[ -n "${PHARO_APP_KEYWORD}" ]] && return $IS_APP

    # Otherwise, if we found subdirectories, some could be Pharo apps.
    (( ${#SUBDIRECTORIES[@]} > 0 )) && return $HAS_DIRS

    # Otherwise, this isn't an app directory and it has no subdirectories.
    return $NO_DIRS
}


###############################################################################
#
Process_Directory () {
    local THIS_DIRECTORY=${1}

    # Consider this directory to be the top-level directory.
    # Examine its contents, then decide what to do.
    Examine_Directory "${THIS_DIRECTORY}"

    # If this is a Pharo application directory, modify its bash scripts;
    # otherwise, examine every subdirectory and for those that contain
    # Pharo applications, modify their bash scripts accordingly.
    # If it's a Pharo virtual machine directory, then warn and quit.
    case $? in
    $IS_APP )
        Process_Pharo_Files

        # If the file processing failed, tell the user why.
        case $? in
        $SUCCESS )
            return
            ;;
        $NO_FILES )
            Warn_of_App_Without_Scripts "files" && die
            ;;
        $NO_SCRIPTS )
            Warn_of_App_Without_Scripts "bash scripts" && die
            ;;
        $CANT_WRITE )
            Warn_of_Directory_Not_Writable "${WORKING_DIRECTORY}" && die
            ;;
        * )
            Warn_of_Bad_Return_Code "Process_Pharo_Files" && die
        esac
        ;;
    $HAS_DIRS )
        Process_Subdirectories && return

        # Any other return code means nothing was edited.
        Warn_If_Not_Pharo_Directory "${THIS_DIRECTORY}" && die
        ;;
    $NO_DIRS )
        Warn_If_Not_Pharo_Directory "${WORKING_DIRECTORY}" && die
        ;;
    $VM_DIR )
        Warn_of_Virtual_Machine_Directory "${WORKING_DIRECTORY}" && die
        ;;
    * )
        Warn_of_Bad_Return_Code "Examine_Directory" && die
    esac
}


###############################################################################
#
Main () {
    # If no switch is provided, show the usage information.
    (( $# == 0 )) && Display_Usage && die

    # Get the command line switches, as either '-s' or '--switch'.
    SCRIPT_EDIT_ACTION=${1,,}
    SCRIPT_EDIT_ACTION=${SCRIPT_EDIT_ACTION##*-}

    case ${SCRIPT_EDIT_ACTION:0:1} in
    'h' )
        Display_Usage && die
        ;;
    'i' | 'b' | 'f' | 'a' | 'y' )
        SCRIPT_EDIT_ACTION=${SCRIPT_EDIT_ACTIONS["INSERT_BIG_CURSOR"]}
        ;;
    'r' | 's' | 'o' | 'd' | 'n' )
        SCRIPT_EDIT_ACTION=${SCRIPT_EDIT_ACTIONS["REMOVE_BIG_CURSOR"]}
        ;;
    * )
        Display_Error "Can't decipher action to take!" && die
    esac

    # Start with the assumption that the working directory is a top-lovel
    # directory, which may be either a Pharo application directory, or a
    # directory containing one or more Pharo applications in subdirectories.
    TOP_LEVEL=true
    SUBDIRECTORIES=( )

    Process_Directory "${PWD}"
}

Main "$@"
