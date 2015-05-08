
package Zircon::Protocol::Server::AppLauncher;

# base class for Zircon::Protocol users with additions application launching support

use strict;
use warnings;

use Scalar::Util qw( refaddr );
use Time::HiRes qw( usleep );
use Try::Tiny;

use Module::Runtime qw( require_module );

use Zircon::Protocol;

use Readonly;
Readonly my $DEFAULT_APP_CLASS                  => 'Zircon::App';
Readonly my $DEFAULT_HANDSHAKE_TIMEOUT_SECS     => 5;
Readonly my $DEFAULT_POST_HANDSHAKE_DELAY_MSECS => 0;
Readonly my $DEFAULT_PEER_SOCKET_OPT            => '--peer-socket';

use parent qw(
    Zircon::Protocol::Server
    Zircon::Trace
);

our $ZIRCON_TRACE_KEY = 'ZIRCON_APPLAUNCHER_TRACE';

sub new {
    my ($pkg, %arg_hash) = @_;

    my $new = { };
    bless($new, $pkg);

    $new->_init(\%arg_hash);
    return $new;
}

sub _init {
    my ($self, $arg_hash) = @_;

    foreach my $k (qw( app_class context program arg_list
                       handshake_timeout_secs post_handshake_delay_msecs peer_socket_opt )) {
        $self->{"_$k"} = $arg_hash->{"-$k"}; # value may be undef
    }
    unless ($self->app_class) {
        $self->app_class($DEFAULT_APP_CLASS);
        $self->zircon_trace("using default app class '%s'", $self->app_class);
    }
    $self->handshake_timeout_secs(    $DEFAULT_HANDSHAKE_TIMEOUT_SECS    ) unless $self->handshake_timeout_secs;
    $self->post_handshake_delay_msecs($DEFAULT_POST_HANDSHAKE_DELAY_MSECS) unless $self->post_handshake_delay_msecs;
    $self->peer_socket_opt(           $DEFAULT_PEER_SOCKET_OPT           ) unless $self->peer_socket_opt;

    $self->{'_protocol'} = $self->_new_protocol($arg_hash);

    my $peer_socket     = $self->protocol->connection->local_endpoint;
    my $peer_socket_opt = $self->peer_socket_opt;
    my $peer_arg        = "${peer_socket_opt}=${peer_socket}";

    require_module($self->app_class);
    my $app = $self->app_class->new(
        $self->program,
        @{$self->arg_list},
        $peer_arg,
        );
    $self->_app_forker($app);

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

    # we hope the Zircon handshake callback calls $self->_launch_app_wait_finish->()
    my $pid = $self->_app_forker->launch();
    $self->_waitVariable_with_fail(\ $wait);
    if ($wait ne 'ok') {
        kill 'TERM', $pid; # can't talk to it -> don't want it
        my $trace_tag = $self->trace_tag;
        die "launch() for '${trace_tag}': timeout waiting for the handshake; killed pid $pid";
        # wait() happens in event loop
    }

    # Give remote a chance to receive our handshake reply before we do anything else
    my $delay_msecs = $self->post_handshake_delay_msecs;
    if ($delay_msecs) {
        usleep( $delay_msecs * 1000 );
    }

    $self->zircon_trace('launch_app succeeded');
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
        my $trace_tag = $self->trace_tag;
        warn "${trace_tag}: child has gone, cannot send command '$command'\n";
        return;
    }

    return $self->protocol->send_command($command, @args);
}

sub zircon_server_protocol_command {
    my ($self, $command, $view_id, $request_body) = @_;

    my $view_handler = $self->handler_for_view($view_id);

    my $tag_entity_hash = { };
    $tag_entity_hash->{$_->[0]} = $_ for @{$request_body};

    if (my $dispatch = $self->command_dispatch($command)) {

        my $key_entity;
        if (my $key = $dispatch->{key_entity}) {
            $key_entity = $tag_entity_hash->{$key};
            unless ($key_entity) {
                warn "Key entity '$key' not found in command '$command'\n";
                return $self->protocol->message_command_failed("Key entity '$key' not found");
            }
        }

        if (my $required = $dispatch->{required_entities}) {
            foreach my $key ( @$required ) {
                unless ($tag_entity_hash->{$key}) {
                    warn "Entity '$key' not found in command '$command'\n";
                    return $self->protocol->message_command_failed("Entity '$key' not found");
                }
            }
        }

        my $method = $dispatch->{method};
        return $self->$method($view_handler, $key_entity, $tag_entity_hash);
    }
    else {
        my $reason = "Unknown protocol command: '${command}'";
        return $self->protocol->message_command_unknown($reason);
    }

    return; # never reached, quietens "perlcritic --stern"
}

# Override as appropriate (optional)
#
sub handler_for_view {
    my ($self, $view_id) = @_;
    return $view_id;
}

# Override as appropriate (not going to achive much if not)
#
sub command_dispatch {
    my ($self, $command) = @_;
    return;
}

# delegated

sub is_running {
    my ($self) = @_;
    return $self->_app_forker->is_running;
}

sub pid {
    my ($self) = @_;
    return $self->_app_forker->pid;
}

# attributes

sub app_class {
    my ($self, @args) = @_;
    ($self->{'_app_class'}) = @args if @args;
    my $app_class = $self->{'_app_class'};
    return $app_class;
}

sub _app_forker {
    my ($self, @args) = @_;
    ($self->{'_app_forker'}) = @args if @args;
    my $_app_forker = $self->{'_app_forker'};
    return $_app_forker;
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

sub program {
    my ($self, @args) = @_;
    ($self->{'_program'}) = @args if @args;
    my $program = $self->{'_program'};
    return $program;
}

sub trace_tag {
    my ($self) = @_;
    return sprintf "%s:%s", $self->app_class, $self->program;
}

sub arg_list {
    my ($self, @args) = @_;
    ($self->{'_arg_list'}) = @args if @args;
    my $arg_list = $self->{'_arg_list'};
    return $arg_list;
}

sub handshake_timeout_secs {
    my ($self, @args) = @_;
    ($self->{'_handshake_timeout_secs'}) = @args if @args;
    my $handshake_timeout_secs = $self->{'_handshake_timeout_secs'};
    return $handshake_timeout_secs;
}

sub post_handshake_delay_msecs {
    my ($self, @args) = @_;
    ($self->{'_post_handshake_delay_msecs'}) = @args if @args;
    my $post_handshake_delay_msecs = $self->{'_post_handshake_delay_msecs'};
    return $post_handshake_delay_msecs;
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

    $self->zircon_trace('%s', $self);
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
