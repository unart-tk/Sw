#!/bin/sh
# http://wiki.awkwardtv.org/wiki/Manage_users_and_groups_scripts
################################################################################
#   userdel
#
#   This script emulates the useradd command that is 
#   standard in many UNIX like Operating Systems.
#
#   This script should be placed in /usr/sbin
#   it should be owned by root.admin and chmod 755  


#-------------------------------------------------------------------------------
# constants
#
                                                         # define version number
version='2.0'
                                                            # define script name
script_name='userdel'


#-------------------------------------------------------------------------------
# find the shell utils wee need
#
                                                                     # find dscl
dscl=`which dscl`
if [ ! -x "$dscl" ] ; then
  >&2 echo "$script_name: unable to find/use dscl"
  exit 10
fi
                                                                      # find cut
cut=`which cut`
if [ ! -x "$cut" ] ; then
  >&2 echo "$script_name: unable to find/use cut"
  exit 10
fi
                                                                     # find grep
grep=`which grep`
if [ ! -x "$grep" ] ; then
  >&2 echo "$script_name: unable to find/use grep"
  exit 10
fi
                                                                      # find sed
sed=`which sed`
if [ ! -x "$sed" ] ; then
  >&2 echo "$script_name: unable to find/use sed"
  exit 10
fi
                                                                       # find rm
rm=`which rm`
if [ ! -x "$rm" ] ; then
  >&2 echo "$script_name: unable to find/use rm"
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
  >&2 echo "Usage: $script_name [-r] user"
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
remove_directory=0
while getopts ":hvr-:" opt ; do
  case $opt in
    h ) display_usage 0 ;;
    v ) display_version 0 ;;
    r ) remove_directory=1 ;;
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
user="$1"
                               # check for the existence of the "user" parameter
if [ -z "$user" ] ; then
  display_usage 2
fi
                                                    # check that the user exists
if [ `$dscl . -list /Users | $grep -c "^$user$"` -eq 0 ] ; then
  >&2 echo  "$script_name: user \"$user\" not found"
  exit 6
fi
                                           # check if the user runs applications
if [ `ps aux | $grep -c "^$user "` -ne 0 ] ; then
  >&2 echo  "$script_name: user \"$user\" is currently logged in"
  exit 8
fi
                                          # check that the script is run by root
check_uid
if [ $uID != 0 ] ; then
  >&2 echo "$script_name: you must be root"
  exit 10
fi


#-------------------------------------------------------------------------------
# delete the user
#
                                                     # delete the home directory
if [ $remove_directory -ne 0 ]; then 
  home_directory=`dscl . -read /Users/$user | grep NFSHomeDirectory | sed -e 's/.*: //'`
  $rm -rf $home_directory
fi
                                                               # delete the user
$dscl . -delete /Users/$user

                                               # remove the user from all groups
group_list=`$dscl . -list /Groups`
for group in $group_list ; do
  group_members=`$dscl . -read /Groups/$group GroupMembership`
  if [ `echo "$group_members" | grep -c 'GroupMembership: '` -ne 0 ] ; then
    group_members=`echo "$group_members" | $sed -e 's/.*GroupMembership: //'`
#    echo "$group: $group_members"
  fi
  remove_user=0
  for member in $group_members ; do
    if [ "$member" = "$user" ] ; then
      remove_user=1
    fi
  done
  if [ $remove_user -ne 0 ] ; then
#    echo "removing $user in group $group"
    $dscl . -delete /Groups/$group GroupMembership $user
  fi
done

