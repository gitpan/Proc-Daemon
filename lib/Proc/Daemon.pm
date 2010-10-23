################################################################################
##  File:
##      Daemon.pm
##  Authors:
##      Earl Hood         earl@earlhood.com
##      Detlef Pilzecker  deti@cpan.org
##  Description:
##      see Daemon.pod file
################################################################################
##  Copyright (C) 1997-2010 by Earl Hood and Detlef Pilzecker.
##
##  All rights reserved.
##
##  This module is free software. It may be used, redistributed and/or modified
##      under the same terms as Perl itself.
################################################################################


package Proc::Daemon;

use strict;
use POSIX();

$Proc::Daemon::VERSION = '0.04';


################################################################################
# Create the Daemon object:
# my $daemon = Proc::Daemon->new( [ %Daemon_Settings ] )
#
#   %Daemon_Settings are hash key=>values and can be:
#     work_dir     => '/working/daemon/directory'   -> defaults to '/'
#     child_STDIN  => '/path/to/daemon/STDIN.file'  -> defautls to '/dev/null'
#     child_STDOUT => '/path/to/daemon/STDOUT.file' -> defaults to *\STDIN
#     child_STDERR => '/path/to/daemon/STDERR.file' -> defaults to *\STDIN
#     pid_file =>     '/path/to/pid/file.txt'       -> defaults to
#       undef (= write no file)
#     exec_command => 'perl /home/script.pl'        -> execute a system command
#       via Perls *exec PROGRAM* at the end of the Init routine and never return.
#       Must be an arrayref if you want to create several daemons at once.
#
# Returns: the blessed object.
################################################################################
sub new {
    my ( $class, %args ) = @_;

    my $self = \%args;
    bless( $self, $class );

    return $self;
}


################################################################################
# Become a daemon:
# $daemon->Init
#
# or, for more daemons with other settings in the same script:
# Use a hash as below. The argument must (!) now be a hashref: {...}
# even if you don't modify the initial settings (=> use empty hashref).
# $daemon->Init( { [ %Daemon_Settings ] } )
#
# or, if no Daemon->new() object was created and for backward compatibility:
# Proc::Daemon::Init( [ { %Daemon_Settings } ] )
#   In this case the argument must be <undef> or a hashref!
#
# %Daemon_Settings see &new.
#
# Returns to the parent: the PID of the daemon created.
# Returns to the child : 0 | never returns if used with 'exec_command'.
################################################################################
sub Init {
    my Proc::Daemon $self = shift;
    my $settings_ref = shift;


    # For backward compatibility:
    # Check if $self has been blessed into the package, otherwise do it now.
    if ( ref( $self ) ne 'Proc::Daemon' ) {
       $self = ref( $self ) eq 'HASH' ? Proc::Daemon->new( %$self ) : Proc::Daemon->new();
    }
    # If $daemon->Init is used again in the same script, get
    # the new arguments and check/adjust the settings again.
    elsif ( ref( $settings_ref ) eq 'HASH' ) {
        map { $self->{ $_ } = $$settings_ref{ $_ } } keys %$settings_ref;
    }


    # Open a filehandle to the anonymous temporary pid file.
    open( MEMORY, "+>", undef ) || die "Can not open anonymous temporary pidfile: $!";


    # If system commands are to be executed, put them in a list.
    my @exec_command = ref( $self->{exec_command} ) eq 'ARRAY' ? @{ $self->{exec_command} } : ( $self->{exec_command} );
    $#exec_command = 0 if $#exec_command < 0;

    # Run a daemon once or for every system command.
    foreach my $exec_command ( @exec_command ) {
        # First parent is running here.


        # Using this subroutine or loop multiple times we must modify the files:
        # 'child_STDIN', 'child_STDOUT', 'child_STDERR' and 'pid_file' for every
        # daemon. A highter number will be appended to the files.
        $self->adjust_settings();


        # First fork.
        my $pid = Fork();
        unless ( $pid || ! defined $pid ) {
            # First child runs here.


            # Detach ourselves from the terminal.
            die "Cannot detach from controlling terminal" if POSIX::setsid() < 0;

            # Prevent possibility of acquiring a controling terminal.
            local $SIG{'HUP'} = 'IGNORE';

            # Second fork.
            $pid = Fork();
            unless ( $pid || ! defined $pid ) {
                # Here is the second child running.


                # Set the new working directory.
                chdir $self->{work_dir};

                # Clear file creation mask.
                umask 0;

                # Close open file handles/descriptors.
                # MEMORY also will be closed here.
                foreach ( 0 .. OpenMax() ) { POSIX::close( $_ ) }

                # Reopen STDIN, STDOUT and STDERR to '..._path' or write to /dev/null
                open ( STDIN,  ( $self->{child_STDIN}  ? "+>$self->{child_STDIN}"  : "+>/dev/null" ) );
                open ( STDOUT, ( $self->{child_STDOUT} ? "+>$self->{child_STDOUT}" : "+>&STDIN"    ) );
                open ( STDERR, ( $self->{child_STDERR} ? "+>$self->{child_STDERR}" : "+>&STDIN"    ) );


                # Execute a system command and never return.
                if ( $exec_command ) {
                    exec $exec_command;
                    exit; # Not a real exit, but needed since Perl warns you if
                    # there is no statement like 'die', 'warn', or 'exit'
                    # following 'exec'. The 'exec' function executes a system
                    # command and never returns.
                }


                # Return the childs own PID (0)
                return $pid;
            }

            # First child (= second parent) runs here.

            # Print the PID of the second child into ...
            # ... the anonymous temporary pid file.
            $pid ||= '';
            print MEMORY "$pid\n";
            close MEMORY;

            # ... the real 'pid_file'.
            if ( $self->{pid_file} ) {
                open( PIDFILE, "+>", $self->{pid_file} ) || die "Can not open pidfile (pid_file => '$self->{pid_file}'): $!";
                print PIDFILE $pid;
                close PIDFILE;
            }

            # Don't 'wait' for the second child to exit,
            # even if we don't have a value in $exec_command

            exit;
        }


        # Only first parent runs here.


        # Wait for the first child to exit!!
        wait;
    }


    # Only first parent runs here.


    # Get the second child/ren PIDs out of the anonymous temporary pid file.
    seek( MEMORY, 0, 0 );
    my @pid = map { chomp $_; $_ eq '' ? undef : $_ } <MEMORY>;
    close MEMORY;

    # Return the daemon PIDs (from second child/ren) to the first parent.
    return ( wantarray ? @pid : $pid[0] );
}
# For backward capability:
*init = \&Init;


################################################################################
# Set some defaults and adjust some settings.
# Args: ( $self )
# Returns: nothing
################################################################################
sub adjust_settings {
    my Proc::Daemon $self = shift;

    # Set default 'work_dir' if needed.
    $self->{work_dir} ||= '/';

    $self->fix_filename('child_STDIN')  if $self->{child_STDIN}  && $self->{child_STDIN}  ne '/dev/null';

    $self->fix_filename('child_STDOUT') if $self->{child_STDOUT} && $self->{child_STDOUT} ne '/dev/null';

    $self->fix_filename('child_STDERR') if $self->{child_STDERR} && $self->{child_STDERR} ne '/dev/null';

    # Check 'pid_file's name
    if ( $self->{pid_file} ) {
        die "Pidfile (pid_file => '$self->{pid_file}') can not be only a number. I must be able to distinguish it from a PID number in &get_pid('...')." if $self->{pid_file} =~ /^\d+$/;

        $self->fix_filename('pid_file');
    }

    return;
}


################################################################################
# - If the keys value is only a filename add the path of 'work_dir'.
# - If we have already set a file for this key with the same "path/name",
#   add a number to the file.
# Args: ( $self, $key )
#   key: one of 'child_STDIN', 'child_STDOUT', 'child_STDERR', 'pid_file'
# Returns: nothing
################################################################################
my %memory;
sub fix_filename {
    my Proc::Daemon $self = shift;
    my $key = shift;
    my $var = $self->{ $key };

    # add path to filename
    if ( $var =~ s/^\.\/// || $var !~ /\// ) {
        $var = $self->{work_dir} =~ /\/$/ ?
            $self->{work_dir} . $var : $self->{work_dir} . '/' . $var;
    }

    # If the file was already in use, modify it with '_number':
    # filename_X | filename_X.ext
    if ( $memory{ $key }{ $var } ) {
        $var =~ s/([^\/]+)$//;
        my @i = split( /\./, $1 );
        my $j = $#i ? $#i - 1 : 0;

        $memory{ "$key\_num" } ||= 0;
        $i[ $j ] =~ s/_$memory{ "$key\_num" }$//;
        $memory{ "$key\_num" }++;
        $i[ $j ] .= '_' . $memory{ "$key\_num" };
        $var .= join( '.', @i );
    }

    $memory{ $key }{ $var } = 1;
    $self->{ $key } = $var;

    return;
}


################################################################################
# Fork(): Retries to fork over 30 seconds if possible to fork at all and
#   if necessary.
# Returns the child PID to the parent process and 0 to the child process.
#   If the fork is unsuccessful it C<warn>s and returns C<undef>.
################################################################################
sub Fork {
    my $pid;
    my $loop = 0;

    FORK: {
        if ( defined( $pid = fork ) ) {
            return $pid;
        }

        # EAGAIN - fork cannot allocate sufficient memory to copy the parent's
        #          page tables and allocate a task structure for the child.
        # ENOMEM - fork failed to allocate the necessary kernel structures
        #          because memory is tight.
        # Last the loop after 30 seconds
        if ( $loop < 6 && ( $! == POSIX::EAGAIN() ||  $! == POSIX::ENOMEM() ) ) {
            $loop++; sleep 5; redo FORK;
        }
    }

    warn "Can't fork: $!";

    return undef;
}


################################################################################
# OpenMax( [ NUMBER ] )
# Returns the maximum number of possible file descriptors. If sysconf()
# does not give me a valid value, I return NUMBER (default is 64).
################################################################################
sub OpenMax {
    my $openmax = POSIX::sysconf( &POSIX::_SC_OPEN_MAX );

    return ( ! defined( $openmax ) || $openmax < 0 ) ?
        ( shift || 64 ) : $openmax;
}


################################################################################
# Check if the (daemon) process is alive:
# Status( [ number or string ] )
#
# Examples:
#   $object->Status() - Tries to get the PID out of the settings in new() and checks it.
#   $object->Status( 12345 ) - Number of PID to check.
#   $object->Status( './pid.txt' ) - Path to file containing one PID to check.
#   $object->Status( 'perl /home/my_perl_daemon.pl' ) - Command line entry of the
#               running program to check. Requires Proc::ProcessTable to work.
#
# Returns the PID (alive) or 0 (dead).
################################################################################
sub Status {
    my Proc::Daemon $self = shift;
    my $pid = shift;

    # Get the process ID.
    ( $pid, undef ) = $self->get_pid( $pid );

    # Return if no PID was found.
    return 0 if ! $pid;

    # The kill(2) system call will check whether it's possible to send
    # a signal to the pid (that means, to be brief, that the process
    # is owned by the same user, or we are the super-user). This is a
    # useful way to check that a child process is alive (even if only
    # as a zombie) and hasn't changed its UID.
    return ( kill( 0, $pid ) ? $pid : 0 );
}


################################################################################
# Kill the (daemon) process:
# Kill_Daemon( [ number or string ] )
#
# Examples:
#   $object->Kill_Daemon() - Tries to get the PID out of the settings in new() and kill it.
#   $object->Kill_Daemon( 12345 ) - Number of PID to kill.
#   $object->Kill_Daemon( './pid.txt' ) - Path to file containing one PID to kill.
#   $object->Kill_Daemon( 'perl /home/my_perl_daemon.pl' ) - Command line entry of the
#               running program to kill. Requires Proc::ProcessTable to work.
#
# Returns the number of processes successfully killed,
# which mostly is not the same as the PID number.
################################################################################
sub Kill_Daemon {
    my Proc::Daemon $self = shift;
    my $pid = shift;
    my $pidfile;

    # Get the process ID.
    ( $pid, $pidfile ) = $self->get_pid( $pid );

    # Return if no PID was found.
    return 0 if ! $pid;

    # Kill the process.
    my $killed = kill( 9, $pid );

    if ( $killed && $pidfile ) {
        # Set PID in pid file to '0'.
        if ( open( PIDFILE, "+>", $pidfile ) ) {
            print PIDFILE '0';
            close PIDFILE;
        }
        else { warn "Can not open pidfile (pid_file => '$pidfile'): $!" }
    }

    return $killed;
}


################################################################################
# Return the PID of a process:
# get_pid( number or string )
#
# Examples:
#   $object->get_pid() - Tries to get the PID out of the settings in new().
#   $object->get_pid( 12345 ) - Number of PID to return.
#   $object->get_pid( './pid.txt' ) - Path to file containing the PID.
#   $object->get_pid( 'perl /home/my_perl_daemon.pl' ) - Command line entry of
#               the running program. Requires Proc::ProcessTable to work.
#
# Returns an array with ( 'the PID | <undef>', 'the pid_file | <undef>' )
################################################################################
sub get_pid {
    my Proc::Daemon $self = shift;
    my $string = shift || '';
    my ( $pid, $pidfile );

    if ( $string ) {
        # $string is already a PID.
        if ( $string =~ /^\d+$/ ) {
            $pid = $string;
        }
        # Open the pidfile and get the PID from it.
        elsif ( open( MEMORY, "<", $string ) ) {
            $pid = <MEMORY>;
            close MEMORY;

            die "I found no valid PID ('$pid') in the pidfile: '$string'" if $pid =~ /\D/s;

            $pidfile = $string;
        }
        # Get the PID by the system process table.
        else {
            $pid = $self->get_pid_by_proc_table_attr( 'cmndline', $string );
        }
    }


    # Try to get the PID out of the new() settings.
    if ( ! $pid ) {
        # Try to get the PID out of the 'pid_file' setting.
        if ( $self->{pid_file} && open( MEMORY, "<", $self->{pid_file} ) ) {
            $pid = <MEMORY>;
            close MEMORY;

            if ( ! $pid || ( $pid && $pid =~ /\D/s ) ) { $pid = undef }
            else { $pidfile = $self->{pid_file} }
        }

        # Try to get the PID out of the system process
        # table by the 'exec_command' setting.
        if ( ! $pid && $self->{exec_command} ) {
            $pid = $self->get_pid_by_proc_table_attr( 'cmndline', $self->{exec_command} );
        }
    }

    return ( $pid, $pidfile );
}


################################################################################
# This sub requires the Proc::ProcessTable module to be installed!!!
#
# Search for the PID of a process in the process table:
# $object->get_pid_by_proc_table_attr( 'unix_process_table_attribute', 'string that must match' )
#
#   unix_process_table_attribute examples:
#   For more see the README.... files at http://search.cpan.org/~durist/Proc-ProcessTable/
#     uid      - UID of process
#     pid      - process ID
#     ppid     - parent process ID
#     fname    - file name
#     state    - state of process
#     cmndline - full command line of process
#     cwd      - current directory of process
#
# Example:
#   get_pid_by_proc_table_attr( 'cmndline', 'perl /home/my_perl_daemon.pl' )
#
# Returns the process PID on success, otherwise <undef>.
################################################################################
sub get_pid_by_proc_table_attr {
    my Proc::Daemon $self = shift;
    my ( $command, $match ) = @_;
    my $pid;

    # eval - Module may not be installed
    eval {
        require Proc::ProcessTable;

        my $table = Proc::ProcessTable->new()->table;

        foreach ( @$table ) {
            next if $_->$command ne $match;
            $pid = $_->pid;
            last;
        }
    };

    warn "- Problem in get_pid_by_proc_table_attr( '$command', '$match' ):\n  $@  You may not use a command line entry to get the PID of your process.\n  This function requires Proc::ProcessTable (http://search.cpan.org/~durist/Proc-ProcessTable/) to work.\n" if $@;

    return $pid;
}

1;