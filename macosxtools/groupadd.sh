#!/bin/sh
# src: http://wiki.awkwardtv.org/wiki/Manage_users_and_groups_scripts

################################################################################
#   groupadd
#
#   This script emulates the groupadd command that is 
#   standard in many UNIX like Operating Systems.
#
#   This script should be placed in /usr/sbin
#   it should be owned by root:admin and chmod 744  
#


#-------------------------------------------------------------------------------
# constants
#
                                                         # define version number
version='2.0'
                                                            # define script name
script_name='groupadd'
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
                                                                      # find sed
sed=`which sed`
if [ ! -x "$sed" ] ; then
  >&2 echo "$script_name: unable to find/use sed"
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
                                                                     # find expr
expr=`which expr`
if [ ! -x "$expr" ] ; then
  >&2 echo "$script_name: unable to find/use expr"
  exit 10
fi


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
  >&2 echo "Usage: $script_name [-g gid [-o]] group"
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
override=0
define_gid=0
group_id=
while getopts ":hvg:o-:" opt ; do
  case $opt in
    h ) display_usage 0 ;;
    v ) display_version 0 ;;
    g ) define_gid=1
        group_id=$OPTARG ;;
    o ) override=1 ;;
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
                            # check for the existence of the "group_id" parameter
if [ $define_gid -ne 0 ] ; then
  if [ -z "$group" ] ; then
    >&2 echo "$script_name: -g requires a gid"
    display_usage 3
  fi
fi
                              # check for the existence of the "group" parameter
if [ -z "$group" ] ; then
  display_usage 2
fi
                                   # check that the group name doesn't exist yet
if [ `$dscl . -list /Groups | $grep -c "^$group$"` -ne 0 ] ; then
  >&2 echo  "$script_name: group \"$group\" already exists"
  exit 9
fi
                                                      # if no GID passed get one
if [ -z $group_id ] ; then 
  get_free_gid
else 
  if [ $override -ne 1 ] ; then
    if [ `$dscl . -list /Groups gid | $sed -e 's/blank:\{1,\}/:/g' | $cut -f 2 -d : | $grep -c "^$group_id"` -gt 0 ]; then
      >&2 echo "$script_name: gid \"$group_id\" is already in use" 
      exit 4
    fi
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
  echo "Adding group $group"
  echo "${display_indent}with GID $group_id"
fi


#-------------------------------------------------------------------------------
# make the group
#

$dscl . -create /Groups/$group
$dscl . -create /Groups/$group PrimaryGroupID $group_id
$dscl . -create /Groups/$group Password '*'

