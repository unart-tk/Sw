#!/bin/sh
# http://wiki.awkwardtv.org/wiki/Manage_users_and_groups_scripts
################################################################################
#   useradd
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
script_name='useradd'
                                                                 # display items
display_indent='  '
debug=0


#-------------------------------------------------------------------------------
# find the shell utils wee need
#
                                                                     # find dscl
dscl=`which dscl`
if [ ! -x "$dscl" ] ; then
  >&2 echo "$script_name: unable to find/use dscl"
  exit 10
fi
                                                                    # find ditto
ditto=`which ditto`
if [ ! -x "$ditto" ] ; then
  >&2 echo "$script_name: unable to find/use ditto"
  exit 10
fi
                                                                      # find cut
cut=`which cut`
if [ ! -x "$cut" ] ; then
  >&2 echo "$script_name: unable to find/use cut"
  exit 10
fi
                                                                     # find expr
expr=`which expr`
if [ ! -x "$expr" ] ; then
  >&2 echo "$script_name: unable to find/use expr"
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
                                                                     # find head
head=`which head`
if [ ! -x "$head" ] ; then
  >&2 echo "$script_name: unable to find/use head"
  exit 10
fi
                                                                     # find tail
tail=`which tail`
if [ ! -x "$tail" ] ; then
  >&2 echo "$script_name: unable to find/use tail"
  exit 10
fi
                                                                       # find rm
rm=`which rm`
if [ ! -x "$rm" ] ; then
  >&2 echo "$script_name: unable to find/use rm"
  exit 10
fi


#-------------------------------------------------------------------------------
# get a free GID greater than 1000
#

get_free_uid() 
{
  continue="no"
  number_used="dontknow"
  fnumber=1000
  until [ $continue = "yes" ] ; do
    if [ `$dscl . -list /Users uid | $sed -e 's/blank:\{1,\}/:/g' | $cut -f 2 -d : | $grep -c "^$fnumber$"` -gt 0 ] ; then
      number_used=true
    else
      number_used=false
    fi
    if [ $number_used = "true" ] ; then
      fnumber=`$expr $fnumber + 1`
    else
      user_id="$fnumber"
      continue="yes"
    fi
  done;
}


#-------------------------------------------------------------------------------
# get a free GID greater than 500
#

get_free_gid() 
{
  continue="no"
  number_used="dontknow"
  fnumber=500
  until [ $continue = "yes" ] ; do
    if [ `$dscl . -list /Groups gid | $sed -e 's/blank:\{1,\}/:/g' | $cut -f 2 -d : | $grep -c "^$fnumber$"` -gt 0 ] ; then
      number_used=true
    else
      number_used=false
    fi
    if [ $number_used = "true" ] ; then
      fnumber=`$expr $fnumber + 1`
    else
      group_id="$fnumber"
      continue="yes"
    fi
  done;
}


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
  usage_indent='               '
  >&2 echo "Usage: $script_name [-u uid [-o]] [-g group] [-G group,...]"
  >&2 echo "${usage_indent}[-d home] [-m [-k template]] [-s shell] [-c comment]"
  >&2 echo "${usage_indent}[-f inactive] [-e expire]"
  >&2 echo "${usage_indent}[-p passwd] user"
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
define_user_id=0
override_user_id=0
define_initial_group=0
define_other_groups=0
define_home_directory=0
define_login_shell=0
define_comment=0
create_home_directory=0
define_skeleton_dir=0
define_inactive_days=0
define_expire_date=0
define_password=0
while getopts ":hvu:og:G:d:s:c:mk:f:e:p:-:" opt ; do
  case $opt in
    h ) display_usage 0 ;;
    v ) display_version 0 ;;
    u ) define_user_id=1
        user_id=$OPTARG ;;
    o ) override_user_id=1 ;;
    g ) define_initial_group=1
        initial_group=$OPTARG ;;
    G ) define_other_groups=1
        other_groups=$OPTARG ;;
    d ) define_home_directory=1
        home_directory=$OPTARG ;;
    m ) create_home_directory=1 ;;
    k ) define_skeleton_dir=1
        skeleton_dir=$OPTARG ;;
    s ) define_login_shell=1
        login_shell=$OPTARG ;;
    c ) define_comment=1
        comment=$OPTARG ;;
    f ) define_inactive_days=1
        inactive_days=$OPTARG ;;
    e ) define_expire_date=1
        expire_date=$OPTARG ;;
    p ) define_password=1
        password=$OPTARG ;;
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
                                         # check that the user doesn't exist yet
if [ `$dscl . -list /Users | $grep -c "^$user$"` -ne 0 ] ; then
  >&2 echo  "$script_name: user \"$user\" exists"
  exit 9
fi
                                                               # get / check UID
if [ $define_user_id -eq 0 ] ; then
  get_free_uid
else
  if [ `$dscl . -list /Users uid | $sed -e 's/blank:\{1,\}/:/g' | $cut -f 2 -d : | $grep -c "^$fnumber$"` -eq 0 ] ; then
    override_user_id=0
  else
    if [ $override_user_id -eq 0 ] ; then
      >&2 echo "$script_name: uid $user_id already exists"
      exit 4
    fi
  fi
fi
                                                               # get / check GID
create_initial_group=0
if [ $define_initial_group -eq 0 ] ; then
  get_free_gid
  create_initial_group=1
  initial_group="$user"
else
  if [ `$dscl . -list /Groups | $grep -c "^$initial_group$"` -eq 0 ] ; then
    >&2 echo "$script_name: unknown group $initial_group"
    exit 6
  else
    group_id=`$dscl . -list /Groups gid | $sed -e 's/blank:\{1,\}/:/g' | $grep "^$initial_group:" | $cut -f 2 -d ':'`
  fi
fi
                                                            # check other groups
if [ $define_other_groups -ne 0 ] ; then
  other_groups=`echo $other_groups | $sed -e 's/,/ /g'`
  for group in $other_groups ; do
    if [ `$dscl . -list /Groups | $grep -c "^$group$"` -eq 0 ] ; then
      >&2 echo "$script_name: unknown group $group"
      exit 6
    fi
  done
fi
                                                         # define home directory
if [ $define_home_directory -eq 0 ] ; then
  home_directory="/Users/$user"
fi
                                                          # check home directory
if [ -d "$home_directory" ] ; then
  create_home_directory=0
else
  if [ $create_home_directory -eq 0 ] ; then
    >&2 echo "$script_name: invalid home directory $home_directory"
    exit 12
  fi
fi
                                                            # skeleton directory
copy_skeleton_dir=0
if [ $define_skeleton_dir -ne 0 ] ; then
  if [ -d "$skeleton_dir" ] ; then
    if [ $create_home_directory -no 0 ] ; then
      copy_skeleton_dir=1
    fi
  else
    >&2 echo "$script_name: invalid skeleton directory $skeleton_dir"
    >&2 echo "${display_indent}have a look at /System/Library/User\ Template/"
    exit 12
  fi
fi
                                                                   # login shell
if [ $define_login_shell -eq 0 ] ; then
  login_shell=`which bash`
fi
if [ ! -x "$login_shell" ] ; then
  >&2 echo "$script_name: invalid shell \"$login_shell\""
  exit 3
fi
                                                           # check inactive days
if [ $define_inactive_days -ne 0 ] ; then
  non_numbers=`echo $inactive_days | $grep "[^0-9]"`
  if [ -n "$non_numbers" ] ; then
    >&2 echo "$script_name: invalid numeric argument \"$inactive_days\""
    exit 3
  fi
fi
                                                             # check expire date
if [ $define_expire_date -ne 0 ] ; then
  date_ok=1
  year=`echo $expire_date | $cut -d '-' -f 1`
  if [ -z "$year" ] ; then
    date_ok=0
  fi
  non_numbers=`echo $year | $grep "[^0-9]"`
  if [ -n "$non_numbers" ] ; then
    date_ok=0
  fi
  month=`echo $expire_date | $cut -d '-' -f 2`
  if [ -z "$month" ] ; then
    date_ok=0
  fi
  non_numbers=`echo $month | $grep "[^0-9]"`
  if [ -n "$non_numbers" ] ; then
    date_ok=0
  fi
  day=`echo $expire_date | $cut -d '-' -f 3`
  if [ -z "$day" ] ; then
    date_ok=0
  fi
  non_numbers=`echo $day | $grep "[^0-9]"`
  if [ -n "$non_numbers" ] ; then
    date_ok=0
  fi
  if [ $date_ok -eq 0 ] ; then
    >&2 echo "$script_name: invalid date \"$expire_date\""
    exit 3
  fi
fi
                                          # check that the script is run by root
check_uid
if [ $uID != 0 ] ; then
  >&2 echo "$script_name: you must be root"
  exit 10
fi


#-------------------------------------------------------------------------------
# display debug info
#

if [ $debug -ne 0 ] ; then
  echo "Adding user $user"
  echo "${display_indent}with UID $user_id"
  if [ $override_user_id -ne 0 ] ; then
    echo "${display_indent}${display_indent}overriding existing UID"
  fi
  echo "${display_indent}with GID $group_id ($initial_group)"
  if [ $create_initial_group -ne 0 ] ; then
    echo "${display_indent}${display_indent}to be created"
  fi
  if [ $define_other_groups -ne 0 ] ; then
    echo "${display_indent}also member of groups: $other_groups"
  fi
  echo "${display_indent}with home directory $home_directory"
  if [ $create_home_directory -ne 0 ] ; then
    echo "${display_indent}${display_indent}to be created"
  fi
  if [ $copy_skeleton_dir -ne 0 ] ; then
    echo "${display_indent}copying skeleton from $skeleton_dir"
  fi
  echo "${display_indent}with login shell $login_shell"
  if [ $define_comment -ne 0 ] ; then
    echo "${display_indent}with comment (real name) $comment"
  fi
  if [ $define_inactive_days -ne 0 ] ; then
    echo "${display_indent}with inactive days $inactive_days before password expires"
  fi
  if [ $define_expire_date -ne 0 ] ; then
    echo "${display_indent}with expire date $expire_date"
  fi
  if [ $define_password -ne 0 ] ; then
    echo "${display_indent}with password $password"
  fi
fi


#-------------------------------------------------------------------------------
# create the user
#
                                                               # create the user
$dscl . -create /Users/$user
                                                                    # define UID
$dscl . -create /Users/$user UniqueID $user_id
                                                                    # define GID
if [ $create_initial_group -eq 0 ] ; then
  $dscl . -append /Groups/$initial_group GroupMembership $user
else
  $dscl . -create /Groups/$initial_group
  $dscl . -create /Groups/$initial_group PrimaryGroupID $group_id
  $dscl . -create /Groups/$initial_group Password '*'
  $dscl . -create /Groups/$initial_group GroupMembership $user
fi
                                                           # add to other groups
if [ $define_other_groups -ne 0 ] ; then
  for group in $other_groups ; do
    $dscl . -append /Groups/$group GroupMembership $user
  done
fi
                                                         # define home directory
if [ $create_home_directory -ne 0 ] ; then
  mkdir -p $home_directory
  chown $user:$initial_group $home_directory
fi
$dscl . -create /Users/$user NFSHomeDirectory $home_directory
                                                       # copy skeleton directory
if [ $copy_skeleton_dir -ne 0 ] ; then
  $ditto $skeleton_dir $home_directory
fi
                                                            # define login shell
$dscl . -create /Users/$user UserShell $login_shell
                                                              # define real name
if [ $define_comment -ne 0 ] ; then
  $dscl . -create /Users/$user RealName  $comment
fi
                                  # define inactive days before password expires
if [ $define_inactive_days -ne 0 ] ; then
#  niutil -createprop . /users/$user inactive $inactive_days
  echo "Not setting \"inactive days\" property"
fi
                                                            # define expire date
if [ $define_comment -ne 0 ] ; then
#  niutil -createprop . /users/$user expire $expire_date
  echo "Not setting \"expire\" property"
fi
                                                                  # set password
if [ $define_password -ne 0 ] ; then
  $dscl / -passwd /Users/$user $password
fi

