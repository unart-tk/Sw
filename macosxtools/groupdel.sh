#!/bin/sh
# http://wiki.awkwardtv.org/wiki/Manage_users_and_groups_scripts
################################################################################
#   groupdel
#
#  This script emulates the groupdel command that is 
#  standard in many UNIX like Operating Systems.
#
#  this script should be placed in /usr/sbin
#  it should be owned by root.admin and chmod 744  
#


#-------------------------------------------------------------------------------
# constants
#
                                                         # define version number
version='2.0'
                                                            # define script name
script_name='groupdel'


#-------------------------------------------------------------------------------
# find the shell utils wee need
#
                                                                     # find dscl
dscl=`which dscl`
if [ ! -x "$dscl" ] ; then
  >&2 echo "$script_name: unable to find/use dscl"
  exit 10
fi
                                                                     # find grep
grep=`which grep`
if [ ! -x "$grep" ] ; then
  >&2 echo "$script_name: unable to find/use grep"
  exit 10
fi


#-------------------------------------------------------------------------------
# check if the scripts is run by the root user
#

check_uid() {
  if [ "`whoami`" = root ] ; then
    uID=0
  else
    if [ "$uID" = "" ] ; then
      uID=-1
    fi
  fi
  export uID
}


#-------------------------------------------------------------------------------
# display script usage
#

display_usage()
{
  >&2 echo "Usage: $script_name group"
  exit $1
}


#-------------------------------------------------------------------------------
# display script version
#

display_version()
{
  >&2 echo "$script_name: version $version by Francois Corthay"
  >&2 echo "based on $script_name by Chris Roberts"
  exit $1
}


################################################################################
# Command line parameters
#
                                                   # get command line parameters
while getopts ":hv-:" opt ; do
  case $opt in
    h ) display_usage 0 ;;
    v ) display_version 0 ;;
    - ) case $OPTARG in
          help )
            display_usage 0 ;;
          version )
            display_version 0 ;;
          * )
            display_usage 2 ;;
        esac ;;
    ? ) >&2 echo "$script_name: invalid option $1"
       display_usage 2 ;;
  esac
done
shift $(($OPTIND - 1))
group="$1"
                              # check for the existence of the "group" parameter
if [ -z "$group" ] ; then
  display_usage 2
fi
                            # check for the existence of the group to be deleted
if [ `$dscl . -list /Groups | $grep -c "^$group$"` -ne 1 ];then
  >&2 echo "$script_name: group \"$group\" not found"
  exit 6
fi
                                          # check that the script is run by root
check_uid
if [ $uID != 0 ] ; then
  >&2 echo "$script_name: you must be root"
  exit 10
fi


#-------------------------------------------------------------------------------
# kill the group
#
$dscl . -delete /Groups/$group

