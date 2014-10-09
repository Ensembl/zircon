
package Zircon::App;

# Transport/protocol-independent application forking support.

use strict;
use warnings;

use Carp;
use POSIX ();
use Try::Tiny;

use parent qw( Zircon::Trace );
our $ZIRCON_TRACE_KEY = 'ZIRCON_APP_TRACE';

sub new {
    my ($pkg, $program, @arg_list) = @_;

    my $new = { };
    bless($new, $pkg);

    $new->_init($program, \@arg_list);

    return $new;
}

sub _init {
    my ($self, $program, $arg_list) = @_;
    $self->{'_program'}  = $program or croak 'missing program argument';
    $self->{'_arg_list'} = $arg_list;
    return;
}

sub launch {
    my ($self) = @_;

    my @e = $self->app_command;
    warn "Running: @e\n";
    my $pid = fork;
    confess "Error: couldn't fork()\n" unless defined $pid;
    if ($pid) { # parent
        warn "Started $e[0], pid $pid\n";
        $self->pid($pid);
        return $pid;
    }
    { exec @e; }
    # DUP: EditWindow::PfamWindow::_launch_belvu
    # DUP: Hum::Ace::LocalServer
    try {
        warn "exec '@e' failed: $!";
        close STDERR; # _exit does not flush
        close STDOUT;
    }; # no catch, just be sure to _exit
    POSIX::_exit(127); # avoid triggering DESTROY

    return; # unreached, quietens perlcritic
}

sub is_running {
    my ($self) = @_;

    my $pid = $self->pid;
    return unless $pid;

    # Nicked from Proc::Launcher
    #
    if ( kill 0 => $pid ) {
        if ( $!{EPERM} ) {
            # if process id isn't owned by us, it is assumed to have
            # been recycled, i.e. our process died and the process id
            # was assigned to another process.
            $self->zircon_trace("Process $pid active but owned by someone else");
        }
        else {
            return $pid;
        }
    }

    warn __PACKAGE__, ": process $pid has gone away.\n";
    $self->pid(undef);

    return;
}

sub app_command {
    my ($self) = @_;
    my @app_command = ( $self->program );
    my $arg_list = $self->arg_list;
    push @app_command, @{$arg_list} if $arg_list;
    return @app_command;
}

# attributes

sub program {
    my ($self) = @_;
    my $program = $self->{'_program'};
    return $program;
}

sub arg_list {
    my ($self) = @_;
    my $arg_list = $self->{'_arg_list'};
    return $arg_list;
}

sub pid {
    my ($self, @args) = @_;
    ($self->{'pid'}) = @args if @args;
    my $pid = $self->{'pid'};
    return $pid;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
