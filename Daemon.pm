##---------------------------------------------------------------------------##
##  File:
##	@(#) Daemon.pm 1.1 98/01/27 13:08:58
##  Author:
##	Earl Hood	ehood@medusa.acs.uci.edu
##---------------------------------------------------------------------------##
##  Copyright (C) 1997          Earl Hood, ehood@medusa.acs.uci.edu
##      All rights reserved.
##
##  This program is free software; you can redistribute it and/or
##  modify it under the same terms as Perl itself.
##---------------------------------------------------------------------------##

package Proc::Daemon;

use strict;
use vars qw( $VERSION );
$VERSION = "0.01";

##---------------------------------------------------------------------------##

use Carp;
use POSIX;

sub init {
    my($pid, $sess_id);

    ## Fork and exit parent ##
    FORK: {
	if ($pid = fork) { 		## parent process
	    exit 0;
	} elsif (defined $pid) {	## child process
	    last FORK;
	} elsif ($! =~ /No more process/) {
	    sleep 5;
	    redo FORK;
	} else {
	    croak "Can't fork: $!";
	}
    }

    ## Detach ourselves from the terminal ##
    croak "Cannot detach from controlling terminal"
	unless $sess_id = POSIX::setsid();
    
    chdir "/";		## Change working directory
    umask 0;		## Clear file creation mask

    $sess_id;
}

##---------------------------------------------------------------------------##

1;

__END__

=head1 NAME

Proc::Daemon - Run Perl programs as daemon process

=head1 SYNOPSIS

    use Proc::Daemon;
    $sess_id = Proc::Daemon::init;

    ## ... your code here ...

=head1 DESCRIPTION

This module contains the routine B<init> which can be called by a perl
program to initialize itself as a daemon.  The routine achieves this
by the following:

=over 4

=item 1

Forks a child and exits the parent process.

=item 2

Becomes a session leader (which detaches the program from
the controlling terminal).

=item 3

Changes the current working directory to "/".

=item 4

Clears the file creation mask.

=back

The calling program is responible for closing unnecessary open
file handles.

The return value is the session id returned from setsid().

If an error occurs in init so it cannot perform the above steps, than
it croaks with an error message.  One can prevent program termination
by using eval.

=head1 AUTHOR

Earl Hood, ehood@medusa.acs.uci.edu

http://www.oac.uci.edu/indiv/ehood/

=cut

