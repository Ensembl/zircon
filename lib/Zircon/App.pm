
package Zircon::App;

# Transport/protocol-independent application forking support.

use strict;
use warnings;

use Carp;
use POSIX ();
use Try::Tiny;

sub new {
    my ($pkg, %arg_hash) = @_;

    my $new = { };
    bless($new, $pkg);

    $new->_init(\%arg_hash);
    $new->launch_app;

    return $new;
}

sub _init {
    my ($self, $arg_hash) = @_;
    $self->{'_program'} = $arg_hash->{'-program'} or croak "missing -program parameter";
    $self->{'_arg_list'} = [@{
        $arg_hash->{'-arg_list'} || []
    }]; # copy now because list is modified by subclass _init
    return;
}

sub fork_app {
    my ($self) = @_;

    my @e = $self->app_command;
    warn "Running: @e\n";
    my $pid = fork;
    confess "Error: couldn't fork()\n" unless defined $pid;
    if ($pid) { # parent
        warn "Started $e[0], pid $pid\n";
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

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
