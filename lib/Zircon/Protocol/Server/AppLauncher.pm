
package Zircon::Protocol::Server::AppLauncher;

# base class for Zircon::Protocol users with additions application launching support

use strict;
use warnings;

use Scalar::Util qw( refaddr );
use Try::Tiny;

use Zircon::Protocol;

use Readonly;
Readonly my $DEFAULT_HANDSHAKE_TIMEOUT_SECS => 5;
Readonly my $DEFAULT_PEER_SOCKET_OPT        => '--peer-socket';

use parent qw(
    Zircon::Protocol::Server
    Zircon::Trace
);

sub _init { ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
    my ($self, $app_class, $arg_hash) = @_;

    $self->_app_class($app_class);
    my $init_method = "${app_class}::_init";
    $self->$init_method($arg_hash); ## no critic (Subroutines::ProtectPrivateSubs)

    foreach my $k (qw( context handshake_timeout_secs peer_socket_opt )) {
        $self->{"_$k"} = $arg_hash->{"-$k"}; # value may be undef
    }
    $self->handshake_timeout_secs($DEFAULT_HANDSHAKE_TIMEOUT_SECS) unless $self->handshake_timeout_secs;
    $self->peer_socket_opt(       $DEFAULT_PEER_SOCKET_OPT)        unless $self->peer_socket_opt;

    $self->{'_protocol'} = $self->_new_protocol($arg_hash);

    my $peer_socket     = $self->protocol->connection->local_endpoint;
    my $peer_socket_opt = $self->peer_socket_opt;
    my $peer_arg        = "${peer_socket_opt}=${peer_socket}";

    # for app_command, used later in new
    push @{$self->{'_arg_list'}}, $peer_arg;

    return;
}

sub _new_protocol {
    my ($self, $arg_hash) = @_;
    my $protocol =
        Zircon::Protocol->new(
            %$arg_hash,
            '-server'       => $self,
        );
    return $protocol;
}

sub launch_app {
    my ($self) = @_;

    my $wait = 0;
    $self->_launch_app_wait_finish(sub { $wait = 'ok' });

    my $app_class = $self->_app_class;
    my $launch_method = "${app_class}::fork_app";

    # we hope the Zircon handshake callback calls $self->_launch_app_wait_finish->()
    my $pid = $self->$launch_method();
    $self->_waitVariable_with_fail(\ $wait);
    if ($wait ne 'ok') {
        kill 'TERM', $pid; # can't talk to it -> don't want it
        die "launch_app() for '$app_class': timeout waiting for the handshake; killed pid $pid";
        # wait() happens in event loop
    }

    $self->pid($pid);
    return;
}

sub _waitVariable_with_fail {
    my ($self, $var_ref) = @_;
    my $handshake_timeout_secs = $self->handshake_timeout_secs;

    my $wait_finish = sub {
        $$var_ref ||= 'fail_timeout';
        $self->zircon_trace
          ('fail_timeout(0x%x), var %s=%s after %d secs',
           refaddr($self), $var_ref, $$var_ref, $handshake_timeout_secs);
    };
    my $handle = $self->context->timeout($handshake_timeout_secs * 1000, $wait_finish);
    $self->zircon_trace('startWAIT(0x%x), var %s=%s, timeout %d secs',
                        refaddr($self), $var_ref, $$var_ref, $handshake_timeout_secs);

    # Justify one extra level of event-loop.

    $self->context->waitVariable($var_ref);
    $self->zircon_trace('stopWAIT(0x%x), var %s=%s',
                        refaddr($self), $var_ref, $$var_ref);
    $self->context->cancel_timeout($handle);
    return;
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

    warn "Zircon::ZMap: process $pid has gone away.\n";
    $self->pid(undef);
    return;
}

# protocol server

sub zircon_server_handshake {
    my ($self, @arg_list) = @_;
    $self->protocol->connection->after(
        sub { $self->_launch_app_wait_finish->(); });
    $self->Zircon::Protocol::Server::zircon_server_handshake(@arg_list);
    return;
}

sub send_command {
    my ($self, $command, @args) = @_;

    unless ($self->is_running) {
        my $app_class = $self->_app_class;
        warn "${app_class}: child has gone, cannot send command '$command'\n";
        return;
    }

    return $self->protocol->send_command($command, @args);
}

# attributes

sub _app_class {
    my ($self, @args) = @_;
    ($self->{'_app_class'}) = @args if @args;
    my $_app_class = $self->{'_app_class'};
    return $_app_class;
}

sub app_id {
    my ($self) = @_;
    my $app_id = $self->{'_app_id'};
    return $app_id;
}

sub protocol {
    my ($self) = @_;
    my $protocol = $self->{'_protocol'};
    return $protocol;
}

sub context {
    my ($self) = @_;
    my $context = $self->{'_context'};
    return $context;
}

sub pid {
    my ($self, @args) = @_;
    ($self->{'_pid'}) = @args if @args;
    my $pid = $self->{'_pid'};
    return $pid;
}

sub handshake_timeout_secs {
    my ($self, @args) = @_;
    ($self->{'_handshake_timeout_secs'}) = @args if @args;
    my $handshake_timeout_secs = $self->{'_handshake_timeout_secs'};
    return $handshake_timeout_secs;
}

sub peer_socket_opt {
    my ($self, @args) = @_;
    ($self->{'_peer_socket_opt'}) = @args if @args;
    my $peer_socket_opt = $self->{'_peer_socket_opt'};
    return $peer_socket_opt;
}

sub _launch_app_wait_finish {
    my ($self, @args) = @_;
    ($self->{'_launch_app_wait_finish'}) = @args if @args;
    my $_launch_app_wait_finish = $self->{'_launch_app_wait_finish'};
    return $_launch_app_wait_finish;
}

# destructor

sub DESTROY {
    my ($self) = @_;

    # Beware trapping new references to $self in closures which are
    # stashed elsewhere.  DESTROY will run again when they go away.
    if ($self->{'_destroyed_already'}) {
        warn "DESTROY $self again - do nothing this time\n"; # RT395938
        return;
    }
    $self->{'_destroyed_already'} = 1;

    return unless $self->is_running;

    my $wait = 0;
    my $wait_finish_ok = sub { $wait = 'ok' };

    my $callback = sub {
        my ($result) = @_;
        $self->protocol->connection->after($wait_finish_ok);
        die "shutdown: failed" unless $result and $result->success;
    };

    try {
        $self->send_command('shutdown', undef, undef, $callback);
    }
    catch { warn $_; };
    return;
}

1;

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
