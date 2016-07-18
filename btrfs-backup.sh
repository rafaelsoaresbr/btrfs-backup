#!/bin/bash -e

# Licensed under the GNU GPLv2 by the Free Software Foundation
# Copyright: Rasmus Eskola 2014

# DISCLAIMER: READ THROUGH AND UNDERSTAND THE SCRIPT BEFORE RUNNING
# I take no responsibility if this script destroys your data, damages hardware,
# or kills your cat etc.

# btrfs-backup.sh
# This script creates local snapshot backups of given subvolumes and sends them
# to a remote file system. Before sending, the script will look for the most recent
# "common" snapshot of a subvolume, ie. a snapshot that exists both locally and
# on the destination. The script then proceeds to send only an incremental update
# from the common snapshot to the newly created snapshot.

# Setup
# The script will ask for a btrfs subvolume that will first be snapshotted into
# the into local directories which resides on the subvolume itself.
# Each snapshot will then be sent to the remote filesystem (monted locally).

get_dir(){
  DIR=$(zenity --file-selection --title="Select a directory" --directory 2>/dev/null)
  case $? in
    0)  zenity --info --title="btrfs-backup" --text="\"$DIR\" selected." 2>/dev/null; echo "$DIR";;
    1)  zenity --error --title="btrfs-backup" --text="No directory selected. Please select a directory." 2>/dev/null; get_dir;;
    -1) zenity --error --title="btrfs-backup" --text="An unexpected error has occurred. Quitting." 2>/dev/null;;
  esac
}

backup(){
	# must be in a format that can be sorted
	TIMESTAMP=$(date +%Y-%m-%d_%H:%M:%S)

	# find most recent subvolume which is on both hosts by first taking the
	# intersection of $LOCAL_LIST and $REMOTE_LIST, then sorting it in reverse
	# order (newest first), then picking the first row out
	MOST_RECENT=$(comm -1 -2 <(echo "$1") <(echo "$2") | sort -r | head -n1)

  if [ "$MOST_RECENT" != "" ] ; then
    zenity --info --title="btrfs-backup" --text="Previous backup detected! Making an incremental backup." 2>/dev/null
    (
		sudo btrfs subvolume snapshot -r "$1" "$2/$TIMESTAMP"
		sync
		sudo btrfs send -v -p "$1/$MOST_RECENT" "$1/$TIMESTAMP" | btrfs receive -v "$2"
    ) |
    zenity --progress --title="btrfs-backup" --text="Copying..." --percentage=0 2>/dev/null
    if [ "$?" = -1 ] ; then
      zenity --error --title="btrfs-backup" --text="An unexpected error has occurred." 2>/dev/null
    fi
  else
    zenity --info --title="btrfs-backup" --text="It's the first backup! It may take long." 2>/dev/null
    (
		sudo btrfs subvolume snapshot -r "$1" "$2/$TIMESTAMP"
		sync
		sudo btrfs send -v "$1/$TIMESTAMP" | btrfs receive -v "$2"
    ) |
    zenity --progress --title="btrfs-backup" --text="Backing up..." --percentage=0 2>/dev/null
    if [ "$?" = -1 ] ; then
      zenity --error --title="btrfs-backup" --text="An unexpected error has occurred." 2>/dev/null
    fi
  fi
}

main(){
  zenity --info --title="btrfs-backup" \
         --text="You are about to make a backup of a btrfs subvolume. First select the SOURCE subvolume." 2>/dev/null
	LOCAL_SUBVOL=get_dir
  zenity --info --title="btrfs-backup" --text="Now select the TARGET subvolume." 2>/dev/null
  REMOTE_BACKUP_PATH=get_dir
  if $(zenity --question --title="btrfs-backup" --default-cancel \
         --text="The following subvolume will be backed up: \"$LOCAL_SUBVOL\" to \"$REMOTE_BACKUP_PATH\". Are you sure you wish to proceed?" 2>/dev/null)
  then
    backup "$LOCAL_SUBVOL" "$REMOTE_BACKUP_PATH"
  else
    zenity --info --title="btrfs-backup" --text="Quitting." 2>/dev/null
  fi
}

LICENSE=$(dirname "$0")/LICENSE
zenity --text-info --title="License" --filename="$LICENSE" --checkbox="I read and accept the terms." 2>/dev/null

case $? in
  0)  main;;
  1)  zenity --info --title="License" --text="You must accept the license to use this software." 2>/dev/null;;
  -1) zenity --error --title="License" --text="An unexpected error has occurred." 2>/dev/null;;
esac
