
package Zircon::Connection;

use strict;
use warnings;
use feature qw( switch );

use Carp;
use Scalar::Util qw( weaken );
use Try::Tiny;

my @mandatory_args = qw(
    context
    handler
    );

my $optional_args = {
    'timeout_interval' => 500, # 0.5 seconds
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
        $self->$key($value);
    }

    for my $key (@weak_args) {
        weaken $self->{$key};
    }

    $self->state('inactive');
    $self->update;

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

    $self->trace("start");

    $self->state eq 'inactive'
        or die 'Zircon: busy connection';
    $self->selection('remote')->content($request);
    $self->state('client_request');
    $self->update;
    $self->timeout_start;

    $self->trace("finish");

    return;
}

sub _client_callback {
    my ($self) = @_;

    $self->trace("start: state = '%s'", $self->state);

    for ($self->state) {

        when ('client_request') {
            $self->state('client_waiting');
        }

        when ('client_waiting') {
            my $reply = $self->selection('remote')->get;
            $self->reply($reply);
            $self->state('client_reply');
        }

        when ('client_reply') {
            my $reply = $self->reply;
            $self->handler->zircon_connection_reply($reply);
            $self->state('inactive');
        }

        default {
            die sprintf
                "invalid connection state '%s'", $_;
        }

    }

    $self->trace("finish: state = '%s'", $self->state);

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
    my ($self) = @_;

    $self->trace("start: state = '%s'", $self->state);

    for ($self->state) {

        when ('inactive') {
            my $request = $self->selection('local')->get;
            $self->request($request);
            $self->state('server_request');
        }

        when ('server_request') {
            my $request = $self->request;
            my $reply = $self->handler->zircon_connection_request($request);
            $self->selection('local')->content($reply);
            $self->state('server_reply');
        }

        when ('server_reply') {
            $self->state('inactive');
        }

        default {
            die sprintf
                "invalid connection state '%s'", $_;
        }

    }

    $self->trace("finish: state = '%s'", $self->state);

    return;
}

sub go_server {
    my ($self) = @_;
    $self->selection_call('remote', 'clear');
    $self->selection_call('local', 'own');
    return;
}

# selections

sub local_selection_id {
    my ($self, @args) = @_;
    return $self->selection_id('local', @args);
}

sub remote_selection_id {
    my ($self, @args) = @_;
    return $self->selection_id('remote', @args);
}

sub selection_id {
    my ($self, $key, @args) = @_;
    if (@args) {
        my ($id) = @args;
        ( defined $id && $id ne '' )
            or die 'undefined/empty selection ID';
        $self->{'selection'}{$key} =
            $self->context->selection_new(
                '-id'           => $id,
                '-handler'      => $self,
                '-handler_data' => $key,
            );
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
    my ($self) = @_;
    my $timeout_handle =
        $self->timeout(
            $self->timeout_interval,
            $self->callback('timeout_callback'));
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

sub timeout_callback {
    my ($self) = @_;
    $self->timeout_handle(undef);
    $self->after(undef);
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
            $self->timeout(
                0, sub { $after->(); });
        }
    }
    catch {
        $self->reset;
        die $_; # propagate any error
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

my $trace = $ENV{'ZIRCON_CONNECTION_TRACE'};

sub trace {
    my ($self, $format, @args) = @_;
    return unless $trace;
    my ($sub_name) = (caller(1))[3];
    warn sprintf "%s(): ${format}\n", $sub_name, @args;
    return;
}

# attributes

sub handler {
    my ($self) = @_;
    return $self->{'handler'};
}

sub context {
    my ($self) = @_;
    return $self->{'context'};
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

1;

=head1 NAME - Zircon::Connection

=head1 METHODS

=head2 C<new()>

Create a Zircon connection.

    my $connection = Zircon::Connection->new(
        -context => $context, # mandatory
        -handler => $handler, # mandatory
        -timeout_interval => $timeout, # optional
        );

=over 4

=item C<$context> (mandatory)

An opaque object that provides an interface to X selections and the
application's event loop.

Perl/Tk applications create this object by calling
C<Zircon::Tk::Context-E<gt>new()>.

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

=back

=head2 C<local_selection_id()>, C<remote_selection_id()>

Get/set selection IDs.

    my $id = $connection->local_selection_id;
    $connection->local_selection_id($id);
    my $id = $connection->remote_selection_id;
    $connection->remote_selection_id($id);

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

Only the handler's zircon_connection_request method should call this
method.  If it is called several times then only the last call has any
effect.

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
