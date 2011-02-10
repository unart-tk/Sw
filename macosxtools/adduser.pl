#!/usr/bin/perl -w
# adduser script for Open Directory (works on local and remote nodes)
# by Andre LaBranche, dre@mac.com, updated 9/9/06

# To add support for other user attributes:
# 1) Add a line to the GetOptions block of the process_cli_options subroutine
# (example below for LastName attrib):
#    'LastName=s'         => \$SuppliedData{LastName},
# *IMPORTANT* - you must use the DS attribute name
# 2) Add a line in the show_usage subroutine to describe the new attribute.
# For more information about DS attribute names, view the DirectoryService
# man page. In Tiger, the DS attributes are listed in DirServicesConst.h, in
# /System/Library/Frameworks/DirectoryService.framework/Headers/

# TODO:
# create new homedir for local users (use createhomedir)
#   - sensitive to loc?
#   - sensitive to site-specific custom-templates?
# Remove shadow hashes of deleted users? System Prefs doens't do this...
# Add admins to appserverusr and appserveradm groups
# Operate on non-running DS Nodes
# create group for new users if adding to local node
# support shadow hashes, validate them

use Getopt::Long;
use strict;
use English;

### Variable declarations
# Require at least the following attributes (include default values)
my %RequiredData = (
    'RecordName'       => "username",
    'RealName'         => "User Name",
    'NFSHomeDirectory' => "/home/username",
    'PrimaryGroupID'   => "20",
    'UserShell'        => "/bin/bash"
);

# This list defines the order for interactive prompts
# Make sure that every item in this list also appears in %RequiredData
my @PromptOrder = (
    'RecordName',       'RealName',
    'NFSHomeDirectory', 'PrimaryGroupID',
    'UserShell'
);

# user / group record data
my %SuppliedData    = ();   # The attributes fed to dsimport will be stored here
my $attribute_count = 0;    # used in the dsimport record description header
my @secondary_groups;       # list of group memberships for new user

# exclusive switches
my $delete;                 # switch for doing user deletes
my $help;                   # switch for showing usage help
my $listnodes;              # switch for listing directory service nodes

# other switches
my $v = '';                 # switch for verbose mode
my $debug;                  # undefined unless in debug mode
my $noprompt;               # switch for disabling confirmation of user deletes

# other supplied paramaters
my $admin;                  # admin username for authorizing the user add
my $adminpass;              # admin password for authorizing the user add
my $DSnode;                 # user-specified target DS node (optional)
my $DSfilepath;             # path to a non-running dslocal database

# generated variables
my $dsimport_log;           # name of current dsimport log file
my $attrib;                 # holds individual attributes during loops
my $node;                   # the target directory node for the new user
my @old_groups;             # list of old groups when deleting user
my $localroot = 0;          # becomes true if you're root and operating locally
my @getpwuid;               # getpwuid results for finding the way $HOME
my $homedir;                # $HOME of $EUID
my $ProductBuildVersion;    # Mac OS X version number
my $uid = 501;              # starting point for local UIDs
my @results;                # exit status of cli helpers

# shorthand for cli helpers
my $dscl        = "/usr/bin/dscl";
my $dseditgroup = "/usr/sbin/dseditgroup";
my $groups      = "/usr/bin/groups";
my $dsimport    = "/usr/bin/dsimport";
my $ls          = "/bin/ls";
my $cat         = "/bin/cat";
my $rm          = "/bin/rm";
my $defaults    = "/usr/bin/defaults";
my $stty        = "/bin/stty";
my $tail        = "/usr/bin/tail";
my $chmod       = "/bin/chmod";
my $touch       = "/usr/bin/touch";

### Begin Program
# We will behave a bit differently between Tiger / Leopard
# - Leopard dscl supports -f, Tiger does not
# - Choose default DS Node (NetInfo for Tiger, DSLocal for Leopard)
&get_system_version;

# Process the command line options
&process_cli_options;

# Some of the cli tools work without further auth if you are root and
# operating on a local store.
&check_for_local_root;

# One-shot cli options
&show_usage if $help;
&list_nodes if $listnodes;

# If we're deleting a user...
&delete_user if $delete;

# Prepare user data and program options
&adduser_preflight;

# Check for name collisions in RecordName or RealName
&check_for_collisions;

# if we are root and operating locally, use dscl, otherwise use dsimport
# dscl can operate on non-running DS Nodes in Leopard, and honors root
# dsimport can auto-pick UIDs if not supplied, but does not honor root
if   ($localroot) { &adduser_dscl }
else              { &adduser_dsimport }

# Add user to groups specified on the cli, if any
if (@secondary_groups) {
    &add_user_to_groups;
}

# print a report of all the commands we used and their exit status
&print_report if $debug;
exit 0;

### Begin Subroutines
sub show_usage {
    my @exe_path;    # path to this executable
    my $name;        # this executable's name

    # get the executable name
    @exe_path = split( /\W/, $0 );
    $name = $exe_path[$#exe_path];    # grabs last item of @exe_path array
    print <<EOF;
Usage: $name [<attributes>] [-DSnode <node>] [-admin <admin>]
               [-adminpass <password>] [-listnodes] [-v]
	       [-groups group1[,group2,...]
       $name -delete <username> [-DSnode <node] [-v]
	       [-admin <admin>] [-adminpass <password>] [-noprompt]

    -DSNode node                   Add user to specified DS node
                                   (defaults to local)
    -DSfilepath                    path to a non-running DSLocal database
    -admin user                    admin username
    -adminpass password            admin password
    -listnodes                     list available DS nodes
    -v                             Show verbose debug output
    -delete username		   Username to be deleted
    -groups group1,group2,...	   List of extra groups for new user
    -noprompt			   Don't confirm deletions
    -help                          Show this usage help

    <attributes> are any of:
      -RecordName username         Short username
      -FirstName First             First name
      -LastName Last               Last name
      -RealName "First Last"       Full name
      -NFSHomeDirectory home       Home directory path
      -UniqueID uid                Unix user ID
      -PrimaryGroupID gid          Unix primary group
      -GeneratedUID                globally unique id
      -UserShell shell             Login shell
      -Password password           Password
      -Comment "a comment"         Comment
      -naprivs <privs>             ARD privs  (e.g. -1073741569)
EOF
    exit 0;
}

sub process_cli_options {

    # Each option that needs a value is followed by a short token
    # that defines the data type. s is for string, i is for integer
    GetOptions(
        'RecordName=s'       => \$SuppliedData{RecordName},
        'FirstName=s'        => \$SuppliedData{FirstName},
        'LastName=s'         => \$SuppliedData{LastName},
        'RealName=s'         => \$SuppliedData{RealName},
        'NFSHomeDirectory=s' => \$SuppliedData{NFSHomeDirectory},
        'UniqueID=i'         => \$SuppliedData{UniqueID},
        'PrimaryGroupID=i'   => \$SuppliedData{PrimaryGroupID},
        'GeneratedUID=s'     => \$SuppliedData{GeneratedUID},
        'UserShell=s'        => \$SuppliedData{UserShell},
        'Password=s'         => \$SuppliedData{Password},
        'Comment=s'          => \$SuppliedData{Comment},
        'naprivs=i'          => \$SuppliedData{naprivs},
        'DSnode=s'           => \$DSnode,
        'DSfilepath=s'       => \$DSfilepath,
        'admin=s'            => \$admin,
        'adminpass=s'        => \$adminpass,
        'h'                  => \$help,
        'help'               => \$help,
        'v'                  => \$v,
        'listnodes'          => \$listnodes,
        'delete=s'           => \$delete,
        'noprompt'           => \$noprompt,
        'groups=s'           => \@secondary_groups
    );

    # verbose means "-v" on the cli
    if ( $v ne '' ) {
        $v     = "-v";
        $debug = 1;
    }

    # Use the local node unless told otherwise
    if ( !defined $DSnode ) {
        if ( $ProductBuildVersion =~ /^8/ ) {
            $node = "/NetInfo/DefaultLocalNode";    # tiger
        }
        elsif ( $ProductBuildVersion =~ /^9/ ) {
            $node = "/Local/Default";               #leopard
        }
    }
    else {
        $node = $DSnode;
    }

    # Not sure why /BSD/local isn't a valid target for dsimport...
    if ( defined $DSnode && $DSnode eq "/BSD/local" ) {
        print "/BSD/local is not supported by this script\n";
        &print_report;
        exit 1;
    }
    print "Using DS node $node\n" if $debug;

    # DSfilepath doesn't work in Tiger
    if ( ( defined $DSfilepath ) && ($ProductBuildVersion =~ /^8/) ) {
	print "The DSfilepath option does not work in Tiger.\n";
	exit 1;
    };
}

sub adduser_preflight {

    ## prompt for admin username if we need it
    if ($localroot) { }
    elsif ( !$admin ) {
        if ( $node =~ /local/i ) {
            print "Administrator username: ";
        }
        else {
            print "Directory admin username for $node: ";
        }
        chomp( $admin = <STDIN> );
    }

    # make sure we got everything we need from cli options, prompt if not
    #foreach $attrib ( sort keys %RequiredData ) {
    foreach $attrib (@PromptOrder) {
        if ( !defined $SuppliedData{$attrib} ) {

            # prompt with default value (if any)
            print "$attrib [$RequiredData{$attrib}]: ";
            chomp( $SuppliedData{$attrib} = <STDIN> );

            # if user pressed enter for default, set it accordingly
            if ( $SuppliedData{$attrib} eq "" ) {
                $SuppliedData{$attrib} = $RequiredData{$attrib};
            }
            print "$attrib = $SuppliedData{$attrib}\n" if $debug;
        }
    }

    # prompt for new user password if not supplied on command line
    if ( !defined $SuppliedData{Password} ) {
        my $pw1;    # These store the interactively supplied passwords
        my $pw2;    # (this one is for double-checking)

        # prompt twice for password
        print "Password for $SuppliedData{RecordName}: ";
        system("$stty -echo");
        chomp( $pw1 = <STDIN> );
        print "\nRetype password: ";
        chomp( $pw2 = <STDIN> );
        system("$stty echo");
        print "\n";

        # verify password
        if ( $pw1 ne $pw2 ) {
            print "The passowrds you supplied do not match, please try again\n";
            &print_report;
            exit 1;
        }

        $SuppliedData{Password} = $pw1;
        print "Using password supplied on the command line\n" if $debug;
    }

    # Count attributes
    foreach $attrib ( keys %SuppliedData ) {
        $attribute_count++ if defined $SuppliedData{$attrib};
    }

    # We'll add the AuthMethod attribute manually, so account for that
    $attribute_count++;
}

sub log_exit_status {
    my $estatus      = $? >> 8;
    my $tool         = $_[0];     # command name
    my $full_command = $_[1];

    # append to our list of results
    push @results, "$full_command";
    push @results, $estatus;

    if ( $? == -1 ) {
        print "failed to execute $tool: $!\n";
        &print_report;
        exit 1;
    }
    elsif ( $? & 127 ) {
        printf "child died with signal %d, %s coredump\n", ( $? & 127 ),
          ( $? & 128 ) ? 'with' : 'without';
        &print_report;
        exit 1;
    }
    else {

        #printf "$tool exited %d\n", $estatus if $debug;
    }
    return $estatus;
}

sub check_for_collisions {
    my $fullname_check;
    my $username_check;
    chomp( $username_check =
          `$dscl $node search Users RecordName $SuppliedData{RecordName}` );

    &log_exit_status( 'dscl',
        "$dscl $node read /Users/$SuppliedData{RecordName} RecordName" );

    if ( $username_check =~ /$SuppliedData{RecordName}/ ) {
        print "$SuppliedData{RecordName} already exists in $node, exiting.\n";
        &print_report;
        exit 1;
    }

    chomp( $fullname_check =
          `$dscl $node search Users RealName "$SuppliedData{RealName}"` );

    &log_exit_status( 'dscl',
        "$dscl $node search Users RealName \"$SuppliedData{RealName}\" RealName"
    );

    if ( $fullname_check =~ /$SuppliedData{RealName}/ ) {
        print "$SuppliedData{RealName} already exists in $node\n";
        &print_report;
        exit 1;
    }
}

sub list_nodes {
    my $available_nodes;    # list of available DS nodes
    my $dscl_out;           # holds dscl output
    $dscl_out = `$dscl localhost read /Search | egrep '^CSPSearchPath'`;
    &log_exit_status( 'dscl',
        "$dscl localhost read /Search | egrep '^CSPSearchPath'" );
    $dscl_out =~ /^.*? (.*?)$/;
    $available_nodes = $1;
    $available_nodes =~ s/\s/\n/g;
    print "$available_nodes\n";
    exit 0;
}

sub adduser_dsimport {

    # deal with special characters in the password
    $SuppliedData{Password} =~ s/\\/\\\\/g;    # sub \ to \\
    $SuppliedData{Password} =~ s/:/\\:/g;      # sub : to \:

    # create and open a file for dsimport
    system("$touch /tmp/adduser.$$");
    &log_exit_status( 'touch', "$touch /tmp/adduser.$$" );
    open( OUT, ">/tmp/adduser.$$" );

    # make sure others don't read it
    system("$chmod 700 /tmp/adduser.$$");
    &log_exit_status( 'chmod', "$chmod 700 /tmp/adduser.$$" );

    # Write record description header - this is all one line.
    print OUT "0x0A 0x5C 0x3A 0x2C dsRecTypeStandard:Users $attribute_count ";
    foreach $attrib ( sort keys %SuppliedData ) {
        print OUT "dsAttrTypeStandard:$attrib "
          if defined $SuppliedData{ ${ \$attrib } };
    }
    print OUT "dsAttrTypeStandard:AuthMethod\n";

    # iterate again and write out the actual data (second line)
    foreach $attrib ( sort keys %SuppliedData ) {
        print OUT "$SuppliedData{${\$attrib}}:"
          if defined $SuppliedData{ ${ \$attrib } };
    }
    print OUT "dsAuthMethodStandard\\:dsAuthClearText\n";
    close(OUT);

    print "Assembled dsimport file:\n" if $debug;
    system("$cat /tmp/adduser.$$")     if $debug;
    &log_exit_status( 'cat', "$cat /tmp/adduser.$$" );

    # dsimport doesn't honor local root...
    &get_admin_name;

    if ($adminpass) {
        my $cmd_string =
          "$dsimport -g /tmp/adduser.$$ $node -I -u $admin -p $adminpass -v";
        print "$cmd_string\n" if $debug;
        system("$cmd_string > /dev/null 2>&1");
        &log_exit_status( 'dsimport', "$cmd_string" );
    }
    else {
        my $cmd_string = "$dsimport -g /tmp/adduser.$$ $node -I -u $admin -v";
        print "$cmd_string\n" if $debug;
        system("$cmd_string > /dev/null 2>&1");
        &log_exit_status( 'dsimport', "$cmd_string" );
    }

    # check to see if anything failed
    # first figure out where we are. We do this cause if we're running via sudo,
    # dsimport probably stashes the log in /var/root/Library/Logs/...
    @getpwuid = getpwuid($EUID);
    $homedir  = $getpwuid[7];
    print "EUID's home is: $homedir\n" if $debug;
    chomp( $dsimport_log =
          `$ls -tr1 $homedir/Library/Logs/ImportExport | $tail -n 1` );
    &log_exit_status( 'ls',
        "$ls -tr1 $homedir/Library/Logs/ImportExport | $tail -n 1" );
    print "\ndsimport results:\n" if $debug;
    my $log_output;
    $log_output = `$cat $homedir/Library/Logs/ImportExport/$dsimport_log`;
    print "$log_output\n" if $debug;
    &log_exit_status( 'cat',
        "$cat $homedir/Library/Logs/ImportExport/$dsimport_log" );

    if ( $log_output =~ /failed/ ) {
        print "$log_output";
        &print_report;
        print "There was a failure in dsimport, exiting.\n";
        exit 1;
    }

    # clean up the temp file
    #system("$rm /tmp/adduser.$$");
    #&log_exit_status( 'rm', "$rm /tmp/adduser.$$" );
}

sub adduser_dscl {
    my $user = $SuppliedData{RecordName};    #shorthand
    my $attrib;                              # loop variable for attributes

    # fill in missing pieces that dsimport can autogenerate

    # get the next UID if one was not supplied
    if ( !defined $SuppliedData{UniqueID} ) {

        # Start here
        while (`$dscl $node search Users UniqueID $uid`) {
            &log_exit_status( 'dscl',
                "$dscl $node search Users UniqueID $uid" );
            $uid++;
        }

        print "found uid $uid\n" if $debug;
        $SuppliedData{UniqueID} = $uid;
    }

    # create the record first
    system("$dscl $node create /Users/$user");
    &log_exit_status( 'dscl', "$dscl $node create /Users/$user" );

    # set the password. dscl will set a shadow password and take care of the
    # related attributes (AuthenticationAuthority)
    if ( defined $SuppliedData{Password} ) {
        system("$dscl $node passwd /Users/$user $SuppliedData{Password}");
        &log_exit_status( 'dscl',
            "$dscl $node passwd /Users/$user $SuppliedData{Password}" );
        delete $SuppliedData{Password};
    }
    else {
        die("We didn't get a password for $user, dying \n");
    }

    foreach $attrib ( keys %SuppliedData ) {
        next if ( $attrib eq "RecordName" );
        if ( defined $SuppliedData{$attrib} ) {
            system(
"$dscl $node create /Users/$user $attrib \"$SuppliedData{${\$attrib}}\""
            );
            &log_exit_status( 'dscl',
"$dscl $node create /Users/$user $attrib \"$SuppliedData{${\$attrib}}\""
            );
        }
    }

    # $dscl $node create /Users/$user
    # This produces:
    # _writers_passwd: bob
    # _writers_picture: bob
    # _writers_tim_password: bob
    # AppleMetaNodeLocation: /NetInfo/DefaultLocalNode
    # GeneratedUID: 32B40FE2-449E-416F-8496-60E436D7C736
    # RecordName: bob
    # RecordType: dsRecTypeStandard:Users

    # .writers_hint, .writers_realname

    # exit status

}

sub delete_user {
    my $username_check;
    my $confirm_delete;
    my $dseditgroup_args;    #stores common dseditgroup cli args

    # make sure the user to be deleted currently exists
    chomp( $username_check = `$dscl $node read /Users/$delete RecordName` );

    &log_exit_status( 'dscl', "$dscl $node read /Users/$delete RecordName" );

    if ( $username_check =~ /$delete/ ) {
        print "User $delete found, preparing to delete...\n" if $debug;
    }
    else {
        print
          "$delete doesn't exist in $node, so it cannot be deleted; exiting.\n";
        &print_report;
        exit 1;
    }

    # check to see if we need an admin name
    &get_admin_name unless $localroot;

    # Confirm deletion unless we got -noprompt
    if ( !defined $noprompt ) {
        print "Are you sure you want to delete $delete from $node?\n";
        print "Type control-c to cancel, return to continue... ";
        $confirm_delete = <STDIN>;
    }

    # We'll need the group list later, so get it while it's hot!
    my $tmp_out;
    chomp( $tmp_out = `$groups $delete` );
    print "Found old groups $tmp_out\n" if $debug;
    @old_groups = split( /\s/, $tmp_out );

    # dscl -u <admin> <node> delete /Users/<username>

    if ($localroot) {
        system("$dscl $node delete /Users/$delete");
        &log_exit_status( 'dscl', "$dscl $node delete /Users/$delete" );
    }
    elsif ($adminpass) {
        system("$dscl -u $admin -P $adminpass $node delete /Users/$delete");
        &log_exit_status( 'dscl',
            "$dscl -u $admin -P $adminpass $node delete /Users/$delete" );
    }
    else {
        system("$dscl -u $admin -p $node delete /Users/$delete");
        &log_exit_status( 'dscl',
            "$dscl -u $admin -p $node delete /Users/$delete" );
    }

    # delete the user's group memberships as well
    my $group;    # loop var

    if ($localroot) {
        $dseditgroup_args = "$v -o edit -n $node -d $delete -t user";
    }
    elsif ($adminpass) {
        $dseditgroup_args =
          "$v -o edit -n $node -u $admin -P $adminpass -d $delete -t user";
    }
    else {
        $dseditgroup_args =
          "$v -o edit -n $node -u $admin -p -d $delete -t user";
    }

    foreach $group (@old_groups) {
        print "$dseditgroup $dseditgroup_args $group\n"
          if $debug;
        system("$dseditgroup $dseditgroup_args $group");
        &log_exit_status( 'dseditgroup',
            "$dseditgroup $dseditgroup_args $group" );
    }
    &print_report if defined $debug;
    exit;
}

sub add_user_to_groups {
    my $group;               #loop var for groups
    my $dseditgroup_args;    #use for common dseditgroup cli args
    my $user = $SuppliedData{RecordName};
    @secondary_groups = split( /,/, join( ',', @secondary_groups ) );

 # use a $debug argument set to "" or "-v" to get rid of some of these if blocks
    if ($localroot) {
        $dseditgroup_args = "-o edit -q $v -n $node -a $user -t user";
    }
    elsif ($adminpass) {
        $dseditgroup_args =
          "-o edit -q $v -P $adminpass -n $node -u $admin -a $user -t user";
    }
    else {
        $dseditgroup_args =
          "-o edit -q $v -p -n $node -u $admin -a $user -t user";
    }

    print "Adding user to the following groups: @secondary_groups\n" if $debug;
    foreach $group (@secondary_groups) {
        system("$dseditgroup $dseditgroup_args $group");
        &log_exit_status( 'dseditgroup',
            "$dseditgroup $dseditgroup_args $group" );
    }
}

sub check_for_local_root {

    # if we are root and operating on a local store, we can use dscl and
    # dseditgroup without further authentication.
    print "EUID: $EUID\n" if $debug;
    if ( ( ( $node =~ /local/i ) || defined $DSfilepath ) && ( $EUID == 0 ) ) {
        $localroot = 1;
    }
    print "localroot: $localroot\n" if $debug;
}

sub get_system_version {
    my $VersionPath;
    if ( -e '/System/Library/CoreServices/ServerVersion.plist' ) {
        $VersionPath = "/System/Library/CoreServices/ServerVersion";
    }
    else {
        $VersionPath = "/System/Library/CoreServices/SystemVersion";
    }

    $ProductBuildVersion = `defaults read $VersionPath ProductBuildVersion`;
    chomp $ProductBuildVersion;
    print "version string is $ProductBuildVersion\n" if $debug;
}

sub print_report {
    my $item;      # loop var
    my $status;    # loop var
    my $i = 0;     # loop index
    print "\nStatus | Command\n";
    print "----------------\n";

    #foreach $item (@results) {
    while ( $item = shift @results ) {
        $status = shift @results;
        printf '%6d | ', $status;
        print "$item\n";
    }
}

sub get_admin_name {

    # prompt for admin username if we need it
    if ($localroot) { }
    elsif ( !$admin ) {
        if ( $node =~ /local/i ) {
            print "Administrator username: ";
        }
        else {
            print "Directory admin username for $node: ";
        }
        chomp( $admin = <STDIN> );
    }
}
