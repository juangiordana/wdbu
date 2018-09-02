#! /usr/bin/env bash

##
## Settings.
##

# Relative path to backup configuration file.
SETTINGS_FILE='etc/backup.conf'

# Automatically mount backup root directory.
AUTO_MOUNT=0

##
## Validations.
##

# Got root?
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root." 1>&2
    exit 1
fi

# Validate command line arguments.
if [[ $# -ne 2 ]]; then
   echo "Usage: '$0 <dir_files> <dir_backup>'." 1>&2
   exit 1
fi

# Validate that the files (source) directory exists.
if [ ! -d "$1" ] ; then
    echo "Error: files directory '$1' does not exists or is not a directory." 1>&2
    exit 1
fi

##
## Runtime configuration.
##

# Files (sources) root directory.
ROOT_FILES="$1"

# Backup (destination) root directory.
ROOT_BACKUP="$2"

# Automatically unmount backup root directory if necessary.
AUTO_UMOUNT="${AUTO_MOUNT}"

# Backup directory prefix.
DESTDIR="${ROOT_BACKUP}/$( date +%F'-'%H'-'%M'-'%S )"

##
## Functions.
##

# $1 database name.
# $2 full path to destination file.
bkp_mysql_mysqldump_struct () {
    if [ -z "$1" ] || [ -z "$2" ] ; then
        echo "Error: Missing arguments in bkp_mysql_mysqldump_struct()." 1>&2
        exit 1
    fi

    echo "   - Dumping database structure for '${1}'."

    # --compact implies:
    #   --skip-add-drop-table
    #   --skip-add-locks,
    #   --skip-comments
    #   --skip-disable-keys
    #   --skip-set-charset
    DUMPOPTS="--compact --set-charset"
    DUMPOPTS="${DUMPOPTS} --no-data"
    mysqldump ${DUMPOPTS} --databases ${1} > ${2}

    if [ $? -ne 0 ] ; then
        echo "Error: mysqldump exited with status: ${?}." 1>&2
        exit 1
    fi
}

# $1 database name.
# $2 full path to destination file.
# $3 ignored tables (optional).
bkp_mysql_mysqldump () {
    if [ -z "$1" ] || [ -z "$2" ] ; then
        echo "Error: Missing arguments in bkp_mysql_mysqldump()." 1>&2
        exit 1
    fi

    # Dump full database information.
    echo "   - Dumping database data for '${1}'."

    # --opt implies:
    #   --add-drop-table
    #   --add-locks
    #   --create-options
    #   --disable-keys
    #   --extended-insert
    #   --lock-tables
    #   --quick
    #   --set-charset
    DUMPOPTS="--opt"
    DUMPOPTS="${DUMPOPTS} --skip-add-drop-table --skip-create-options --skip-quick"
    DUMPOPTS="${DUMPOPTS} --skip-comments --no-create-db --no-create-info"
    DUMPOPTS="${DUMPOPTS} --lock-tables --single-transaction"

    # Ignore tables.
    if [ -n "${3}" ] ; then
        for j in ${3}
        do
            echo "     - Ignoring table '${j}'."
            DUMPOPTS="${DUMPOPTS} --ignore-table='${j}'"
        done
    fi

    mysqldump ${DUMPOPTS} --databases ${1} > ${2}

    if [ $? -ne 0 ] ; then
        echo "Error: mysqldump exited with status: ${?}." 1>&2
        exit 1
    fi
}

##
## Action!
##

# Automatically mount backup root directory.
if [ "${AUTO_MOUNT}" -eq 1 ] ; then
    mountpoint -q ${ROOT_BACKUP}

    if [ $? -ne 0 ] ; then
        mount ${ROOT_BACKUP}

        if [ $? -ne 0 ] ; then
            echo "Error: Unable to mount '${ROOT_BACKUP}'." 1>&2
            exit 1
        fi
    else
        # Ensure ${ROOT_BACKUP} is mounted in read-write mode.
        mount -o remount,rw ${ROOT_BACKUP}

        if [ $? -ne 0 ] ; then
            echo "Error: Unable to remount '${ROOT_BACKUP}' in read-write mode." 1>&2
            exit 1
        fi
    fi
fi

# Create files destination directory inside the root backup directory.
mkdir -p ${DESTDIR}

if [ $? -ne 0 ] ; then
    echo "Error: Unable to create backup directory '${DESTDIR}'." 1>&2
    exit 1
fi

# Begin backup.
echo -e "--\n-- New Backup started -" $( date +%F'-'%X ) "\n--"

cd "${DESTDIR}"

# List of directories that will not be backed up in this instance.
NOBACKUP="lost+found"

# List of databases.
MYSQL_ALL_DBS=$( mysql -e 'SHOW DATABASES' )


if [ -z "${MYSQL_ALL_DBS}" ] ; then
    echo "Warning: No databases found. MySQL backups will be skipped."
fi


for PATHNAME in $( find ${ROOT_FILES} -maxdepth 1 -mindepth 1 -type d | sort )
do
    #DIRNAME=${PATHNAME%/*}
    BASENAME=${PATHNAME##*/}

    # If there is no backup configuration file, skip directory.
    if [ ! -r ${PATHNAME}/${SETTINGS_FILE} ] ; then
        NOBACKUP="${NOBACKUP}\n${PATHNAME}"
        continue
    fi

    echo "*) ${BASENAME}"

    # Create a container for current backup directory.
    mkdir -p ${DESTDIR}/${BASENAME}

    if [ $? -ne 0 ] ; then
        echo "Error: Unable to create backup directory '${DESTDIR}/${BASENAME}'." 1>&2
        exit 1
    fi

    # Source $SETTINGS_FILE file to find out if we must run the backup.
    source ${PATHNAME}/${SETTINGS_FILE}

    # Backup files in current directory.
    if [ -n "${BACKUP_FILES}" ] ; then
        echo "   - Creating files backup."

        RSYNC_OPTS='--archive --delete-after --delete-excluded'

        # Build list of excluded files or directories.
        if [ -n "${EXCLUDE}" ] ; then
            for j in ${EXCLUDE}
            do
                echo "     - Ignoring '${j}'."
                RSYNC_OPTS="${RSYNC_OPTS} --exclude ${j}"
            done
            unset EXCLUDE
        fi

        rsync ${RSYNC_OPTS} ${PATHNAME} ${DESTDIR}

        if [ $? -ne 0 ] ; then
            echo "Error: rsync exited with status: ${?}." 1>&2
            exit 1
        fi

        unset BACKUP_FILES
    fi


    # Dump MySQL databases.
    if [ -n "${MYSQL_ALL_DBS}" ] && [ -n "${MYSQL_DBS}" ] ; then
        for j in ${MYSQL_DBS}
        do
            if echo "${j}" | grep -q "${MYSQL_ALL_DBS}" ; then
                # Dump database structure only.
                bkp_mysql_mysqldump_struct $j ${DESTDIR}/${BASENAME}/${j}-struct.sql

                # Dump full database information.
                bkp_mysql_mysqldump $j ${DESTDIR}/${BASENAME}/${j}.sql ${MYSQL_IGNORE}
            fi
        done
    else
        echo "   - No database backup for ${BASENAME}."
    fi

    unset MYSQL_DBS MYSQL_IGNORE


    # Make a .tar[.(xz|bz2|gz)] of current directory.
    if  [ "${COMPRESS}" = "bzip" ] ; then
        echo "   - Creating ${BASENAME}.tar.bz2."
        TAROPTS="cjf ${BASENAME}.tar.bz2"
    elif  [ "${COMPRESS}" = "gzip" ] ; then
        echo "   - Creating ${BASENAME}.tar.gz."
        TAROPTS="czf ${BASENAME}.tar.gz"
    elif  [ "${COMPRESS}" = "lzma" ] ; then
        echo "   - Creating ${BASENAME}.tar.xz."
        TAROPTS="cJf ${BASENAME}.tar.xz"
    else
        echo "   - Creating ${BASENAME}.tar."
        TAROPTS="cf ${BASENAME}.tar"
    fi

    tar ${TAROPTS} ${BASENAME}

    if [ $? -ne 0 ] ; then
        echo "Error: tar exited with status: ${?}." 1>&2
        exit 1
    fi

    unset COMPRESS


    # Remove previously copied files.
    rm -r ${DESTDIR}/${BASENAME}

    echo -en "\n"
done


echo -e "The Backup was successfully stored inside ${DESTDIR}.\n"

if [ -n "${NOBACKUP}" ] ; then
    echo -e "--\n-- The following directories were excluded:\n--"
    echo -e "${NOBACKUP}"
fi

# Automatically unmount Backup directory.
if [ ${AUTO_UMOUNT} -eq 1 ] ; then
    umount ${ROOT_BACKUP}

    if [ $? -ne 0 ] ; then
        echo "Warning: Unable to unmount ${ROOT_BACKUP}" 1>&2
        echo "You MUST unmount ${ROOT_BACKUP} manually." 1>&2
        exit 1
    fi
fi

# Exit successfully.
exit 0
