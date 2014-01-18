
package Zircon::Connection;

use strict;
use warnings;
use feature qw( switch );

use Carp;
use Scalar::Util qw( weaken );
use Try::Tiny;

use base qw( Zircon::Trace );
our $ZIRCON_TRACE_KEY = 'ZIRCON_CONNECTION_TRACE';

my @mandatory_args = qw(
    name
    context
    handler
    );

my $optional_args = {
    'timeout_interval' => 500, # 0.5 seconds
    'timeout_retries_initial' => 10,
    'rolechange_wait' => 500,
    'connection_id'    => __PACKAGE__,
    'local_endpoint' => undef,
};

my @weak_args = qw(
    handler
    );

sub new {
    my ($pkg, %args) = @_;
    my $new = { };
    bless $new, $pkg;
    $new->init(\%args);
    return $new;
}

sub init {
    my ($self, $args) = @_;

    for my $key (@mandatory_args) {
        my $value = $args->{"-${key}"};
        defined $value or die "missing -${key} parameter";
        $self->{$key} = $value;
    }

    while (my ($key, $default) = each %{$optional_args}) {
        my $value = $args->{"-${key}"};
        defined $value or $value = $default;
        $self->$key($value) if defined $value;
    }

    for my $key (@weak_args) {
        weaken $self->{$key};
    }

    $self->trace_env_update;

    # deferred to here in case we're setting local_endpoint
    $self->context->transport_init(
        sub {
            my ($request) = @_;
            return $self->_server_callback($request);
        },
        sub {
            return $self->_fire_after;
        },
        );

    $self->state('inactive');
    $self->update;
    $self->zircon_trace('Initialised');

    return;
}

sub selection_owner_callback {
    my ($self, $key) = @_;
    $self->_do_safely(
        sub { $self->_selection_owner_callback($key); });
    return;
}

sub _selection_owner_callback {
    my ($self, $key) = @_;
    for ($key) {
        when ('local')  { $self->_server_callback; }
        when ('remote') { $self->_client_callback; }
        default {
            die sprintf
                "invalid selection owner callback key: '%s'"
                , $key;
        }
    }
    return;
}

# client

sub send {
    my ($self, $request) = @_;

    $self->zircon_trace("start");

    $self->state eq 'inactive'
        or die 'Zircon: busy connection';

    my $reply;
    my $rv = $self->context->send($request, \$reply, $self->timeout_interval);
    if ($rv > 0) {
        $self->zircon_trace("client got reply '%s'", $reply);
        $self->handler->zircon_connection_reply($reply);
    } elsif ($rv == 0) {
        $self->zircon_trace('client timed out');
        $self->timeout_maybe_callback;
    } else {
        $self->zircon_trace('client failed');
    }

    $self->_fire_after;
    $self->zircon_trace("finish");

    return;
}

sub _fire_after {
    my ($self) = @_;
    if (my $after = $self->after) {
        $self->zircon_trace;
        $self->after->();
        $self->after(undef);
    }
    return;
}

sub _client_callback {
    my ($self) = @_;

    $self->zircon_trace("start: state = '%s'", $self->state);
    my $taken = $self->selection_call(remote => 'taken');

    for ($self->state) {

        when ('client_request') {
            # Remote should have already pasted.  This is ACK of our
            # request.
            $self->state('client_waiting');
            die "Server ACKed our request without reading it" unless $taken;

            # We are about to Own.  Don't let that be mistaken for a
            # valid request!
            $self->selection_call('remote', 'content', "pid=$$: made my request, you should have got it already");
        }

        when ('client_waiting') {
            # Result of get should be a reply.
            die "Server tried to paste after request ACKed" if $taken;
            my $reply = $self->selection_call('remote', 'get');
            $self->reply($reply);
            $self->state('client_reply');

            # We are about to Own.  Don't let that be mistake for a
            # valid request or ACK - it should not be pasted.
            $self->selection_call(remote => content => "pid=$$: thank you for the reply");
        }

        when ('client_reply') {
            die "Server tried to paste our reply ACK" if $taken;
            my $reply = $self->reply;
            $self->handler->zircon_connection_reply($reply);
            $self->state('inactive');
        }

        default {
            die sprintf
                "invalid connection state '%s'", $_;
        }

    }

    $self->zircon_trace("finish: state = '%s'", $self->state);

    return;
}

sub go_client {
    my ($self) = @_;
    $self->selection_call('local', 'clear');
    $self->selection_call('remote', 'own');
    return;
}

# server

sub _server_callback {
    my ($self, $request) = @_;

    $self->zircon_trace("start:   state = '%s'", $self->state);

    $self->zircon_trace("request: '%s'", $request);
    my $reply = $self->handler->zircon_connection_request($request);

    $self->zircon_trace("finish:  state = '%s'", $self->state);

    return $reply;
}

sub go_server {
    my ($self) = @_;
    $self->selection_call('remote', 'clear');
    $self->selection_call('local', 'own');
    return;
}

# selections

sub local_endpoint {
    my ($self, @args) = @_;
    warn "setting local_endpoint to '", $args[0], "'" if @args;
    return $self->context->local_endpoint(@args)
}

sub remote_endpoint {
    my ($self, @args) = @_;
    $self->zircon_trace("setting remote_endpoint to '%s'", $args[0]) if @args;
    return $self->context->remote_endpoint(@args);
}

sub selection_id {
    my ($self, $key, @args) = @_;
    if (@args) {
        my ($id) = @args;
        ( defined $id && $id ne '' )
            or die 'undefined/empty selection ID';
        my $name = sprintf '%s [%s]', $self->name, $key;
        $self->{'selection'}{$key} =
            $self->context->selection_new(
                '-name'         => $name,
                '-id'           => $id,
                '-handler'      => $self,
                '-handler_data' => $key,
            );
        $self->context->window_declare($self) if $key eq 'local';
        $self->zircon_trace("['%s'] set = '%s'", $key, $id);
        $self->update;
    }
    my $selection = $self->{'selection'}{$key};
    my $id = defined $selection ? $selection->id : undef;
    return $id;
}

sub selection {
    my ($self, $key) = @_;
    my $selection = $self->{'selection'}{$key};
    defined $selection
        or die sprintf "Zircon: no selection for key '%s'", $key;
    return $selection;
}

sub selection_call {
    my ($self, $key, $method, @args) = @_;
    my $selection = $self->{'selection'}{$key};
    return unless defined $selection;
    return $selection->$method(@args);
}

# timeouts

sub timeout_start {
    my ($self, $retries) = @_;
    $retries = $self->timeout_retries_initial unless defined $retries;
    my $timeout_handle =
        $self->timeout(
            $self->timeout_interval,
            $self->callback('timeout_maybe_callback'));
    $self->timeout_retries($retries);
    $self->timeout_handle($timeout_handle);
    return;
}

sub timeout_cancel {
    my ($self) = @_;
    my $timeout_handle = $self->timeout_handle;
    if (defined $timeout_handle) {
        $timeout_handle->cancel;
        $self->timeout_handle(undef);
    }
    return;
}

# Time is up, but maybe we will wait again
sub timeout_maybe_callback {
    my ($self) = @_;
    my $retries = $self->timeout_retries;
    my $xid_remote = $self->xid_remote;
    my $again = 0;
    if ($retries && $xid_remote) {
        # If the remote's window still exists, they're just busy
        $again = $self->remote_window_exists;

        $self->zircon_trace
          ('remote window %s %s, %d retr%s left',
           $xid_remote,
           ($again ? "still exists ($again)" : 'gone'),
           $retries, $retries == 1 ? 'y' : 'ies');
    } elsif ($retries) {
        # Assume we are waiting for handshake, benefit of the doubt
        $again = 1;
        $self->zircon_trace('no remote window, wait for handshake [%d]',
                            $retries);
    } # else we waiting long enough

    if ($again) {
        $self->timeout_start($retries - 1);
    } else {
        $self->timeout_callback;
    }
    return;
}

sub remote_window_exists {
    my ($self) = @_;
    return $self->context->window_exists($self->xid_remote, $self->remote_endpoint);
}

sub timeout_callback {
    my ($self) = @_;
    $self->timeout_handle(undef);
    $self->after(undef);
    $self->zircon_trace;
    try { $self->handler->zircon_connection_timeout; }
    catch { die $_; } # propagate any error
    finally { $self->reset; };
    return;
}

sub timeout_interval {
    my ($self, @args) = @_;
    ($self->{'timeout_interval'}) = @args if @args;
    return $self->{'timeout_interval'};
}

sub timeout_handle {
    my ($self, @args) = @_;
    ($self->{'timeout_handle'}) = @args if @args;
    return $self->{'timeout_handle'};
}

sub timeout_retries {
    my ($self, @args) = @_;
    ($self->{'timeout_retries'}) = @args if @args;
    return $self->{'timeout_retries'};
}

sub timeout_retries_initial {
    my ($self, @args) = @_;
    ($self->{'timeout_retries_initial'}) = @args if @args;
    return $self->{'timeout_retries_initial'};
}

sub rolechange_wait {
    my ($self, @args) = @_;
    ($self->{'rolechange_wait'}) = @args if @args;
    return $self->{'rolechange_wait'};
}

sub timeout {
    my ($self, @args) = @_;
    my $timeout_handle =
        $self->context->timeout(@args);
    return $timeout_handle;
}

# callbacks

sub callback {
    my ($self, $method) = @_;
    return $self->{'callback'}{$method} ||=
        $self->_callback($method);
}

sub _callback {
    my ($self, $method) = @_;
    weaken $self; # break circular references
    my $callback = sub {
        defined $self or return; # because a weak reference may become undef
        return $self->$method(@_);
    };
    return $callback;
}

sub _do_safely {
    my ($self, $callback) = @_;
    try {
        $self->timeout_cancel;
        $callback->();
        $self->update;
        if ($self->state eq 'inactive'
            and my $after = $self->after
           ) {
            $self->timeout($self->rolechange_wait, # RT#324544
                           sub { $after->(); });
            # When $rolechange_wait can go back to zero, why not run
            # the $after->() here+now?  Originally in 2d8bbeb
        }
    }
    catch {
        my $msg = $_;
        $msg =~ s/\.?\s*\n*$//;
        $msg .= sprintf(', via _do_safely(state=%s, name=%s)', $self->state, $self->name);
        $self->reset;
        die $msg; # propagate any error
    }
    finally {
        $self->after(undef)
            if $self->state eq 'inactive';
        $self->timeout_start
            unless $self->state eq 'inactive';
    };
    return;
}

sub update {
    my ($self) = @_;
    for ($self->state) {
        when ('inactive') { $self->go_inactive; }
        when (/^client_/) { $self->go_client; }
        when (/^server_/) { $self->go_server; }
        default {
            die sprintf
                "invalid connection state '%s'", $_;
        }
    }
    return;
}

sub reset {
    my ($self) = @_;
    $self->zircon_trace("old state = '%s'", $self->state);
    $self->state('inactive');
    $self->go_inactive;
    return;
}

sub go_inactive {
    my ($self) = @_;
    $self->request('');
    $self->reply('');
    $self->selection_call('local',  'empty');
    $self->selection_call('remote', 'empty');
    $self->go_server;
    return;
}

# tracing

sub zircon_trace_prefix {
    my ($self) = @_;
    return sprintf "connection: %s: id = '%s'", $self->name, $self->connection_id;
}

# attributes

sub name {
    my ($self) = @_;
    my $name = $self->{'name'};
    return $name;
}

sub handler {
    my ($self) = @_;
    return $self->{'handler'};
}

sub context {
    my ($self) = @_;
    return $self->{'context'};
}

sub connection_id {
    my ($self, @args) = @_;
    ($self->{'connection_id'}) = @args if @args;
    return $self->{'connection_id'};
}

sub request {
    my ($self, @args) = @_;
    ($self->{'request'}) = @args if @args;
    return $self->{'request'};
}

sub reply {
    my ($self, @args) = @_;
    ($self->{'reply'}) = @args if @args;
    return $self->{'reply'};
}

sub after {
    my ($self, @args) = @_;
    ($self->{'after'}) = @args if @args;
    return $self->{'after'};
}

sub state {
    my ($self, @args) = @_;
    ($self->{'state'}) = @args if @args;
    return $self->{'state'};
}

sub xid_remote {
    my ($self, @args) = @_;
    ($self->{'xid_remote'}) = @args if @args;
    return $self->{'xid_remote'};
}

1;

=head1 NAME - Zircon::Connection

=head1 METHODS

=head2 C<new()>

Create a Zircon connection.

    my $connection = Zircon::Connection->new(
        -context => $context, # mandatory
        -handler => $handler, # mandatory
        -timeout_interval => $timeout, # optional, in millisec
        -timeout_retries_initial => $count, # optional
        );

=over 4

=item C<$context> (mandatory)

An opaque object that provides an interface to X selections and the
application's event loop.

Perl/Tk applications create this object by calling
C<Zircon::TkZMQ::Context-E<gt>new()>.

=item C<$handler> (mandatory)

An object that processes client requests, server replies and
connection timeouts.

NB: the caller must keep a reference to the handler.  This is because
the connection keeps only a weak reference to the handler to prevent
circular references, since the handler will generally keep a reference
to the connection.

=item C<$timeout> (optional)

The timeout interval in milliseconds.

If at any time the other end of the connection does not respond within
the timeout interval, then the connection calls the handler's timeout
method and then resets.

This value defaults to 500 if not supplied.

=item C<$count> (optional)

The number of times the timeout may be restarted, per phase.  This is
used when we have some reason to think the peer is still present:
remote window still exists, or we are waiting for the handshake to
complete.

=back

=head2 C<local_endpoint()>, C<remote_endpoint()>

Get/set endpoint addresses (selection IDs for pre-ZMQ).

    my $id = $connection->local_endpoint;
    $connection->local_endpoint($id);
    my $id = $connection->remote_endpoint;
    $connection->remote_endpoint($id);

Setting the local selection ID makes the connection respond to
requests from clients using that selection.

Setting the remote selection ID allows the connection to send requests
to a server using that selection.

=head2 C<send()>

Send a request to the server.

    $connection->send($request);

This requires the remote selection ID to be set.

$request is a string.

=head2 C<after()>

Defer an action until after the client/server exchange completes
successfully.

    $connection->after(sub { ... });

The subroutine argument will be called once after the current
client/server exchange completes, provided that the connection did not
reset.

This method should only be called

=over 4

=item * during L<Zircon::Connection::Handler/zircon_connection_request>

To be notified when the client acknowledges your reply

=item * just before the L</send> method

To be notified after we acknowledge the remote server's reply.

=back

If it is called several times then only the last call has any effect.

=head2 C<$handler-E<gt>zircon_connection_request()>

    my $reply = $handler->zircon_connection_request($request);

Process a request from the client and return a reply to be sent to the
client.

This method can call C<$connection-E<gt>after()> to schedule code to
be run after the client acknowledges receiving the reply.

If this raises a Perl error then the connection resets.  The error is
propagated to the application's main loop.

This will only be called if the local selection ID is set.

$request and $reply are strings.

=head2 C<$handler-E<gt>zircon_connection_reply()>

    $handler->zircon_connection_reply($reply);

Process a reply from the server (when acting as a client).

If this raises a Perl error then the connection resets.  The error is
propagated to the application's main loop.

This will only be called if the local selection ID is set.

$reply is a string.

=head2 C<$handler-E<gt>zircon_connection_timeout()>

    $handler->zircon_connection_timeout();

Process a connection timeout.

=head1 SEQUENCE OF EVENTS

    - client : sets request
    - server : reads request
    - client :
    - server : sets reply
    - client : reads reply
    - server :
    - client : processes reply

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
