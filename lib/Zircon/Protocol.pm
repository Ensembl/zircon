
package Zircon::Protocol;

use strict;
use warnings;

use feature qw( switch );
use Scalar::Util qw( weaken );

use Zircon::Connection;
use Zircon::Protocol::Result::Reply;
use Zircon::Protocol::Result::Timeout;

use base qw(
    Zircon::Protocol::XML
    Zircon::Connection::Handler
    Zircon::Trace
    );
our $ZIRCON_TRACE_KEY = 'ZIRCON_PROTOCOL_TRACE';

sub new {
    my ($pkg, %arg_hash) = @_;
    my $new = { };
    bless $new, $pkg;
    $new->_init(\%arg_hash);
    return $new;
}

sub _init {
    my ($self, $arg_hash) = @_;

    $self->{'is_open'} = 1;
    $self->{'request_id'} = 0;

    for (qw( app_id context selection_id server )) {
        my $attribute = $arg_hash->{"-$_"};
        defined $attribute
            or die "missing -$_ parameter";
    }

    @{$self}{qw( app_id server )} =
        @{$arg_hash}{qw( -app_id -server )};
    weaken $self->{'server'};

    my ($context, $selection_id, $timeout_ms, $timeout_retries, $rolechange_wait) =
        @{$arg_hash}{qw( -context -selection_id -connection_timeout -timeout_retries -rolechange_wait )};
    my $connection_id = sprintf "%s: Connection", $self->app_id;
    my $connection = Zircon::Connection->new(
        '-connection_id' => $connection_id,
        '-name'    => $self->app_id,
        '-context' => $context,
        '-handler' => $self,
        '-timeout_interval' => $timeout_ms,
        '-timeout_retries_initial' => $timeout_retries,
        '-rolechange_wait' => $rolechange_wait, # XXX: temporary, awaiting RT#324544
        );
    $self->{'connection'} = $connection;
    $connection->local_selection_id($selection_id);

    $self->zircon_trace('Initialised local (clipboard %s)', $selection_id);

    return;
}

sub send_handshake {
    my ($self, $remote_selection_id, $callback) = @_;

    $self->connection->remote_selection_id($remote_selection_id);

    my $request = $self->_mkele_peer;

    my $orig_callback = $callback;
    $callback = sub {
        my ($result) = @_;
        if ($result->success) {
            my ($msg, $data, @more) = @{ $result->reply };
            die "need two handshake reply elements" unless $data && !@more;
            die "handshake reply data should contain one node"
              unless 3 == @$data && 1 == @{ $data->[2] };
            my ($app_id, $unique_id, $window_id) =
              $self->_gotele_peer(@{ $data->[2] });
            $self->zircon_trace('Handshake reply from remote (clipboard %s)', $unique_id);
        }
        $orig_callback->($result) if $orig_callback;
    };

    $self->send_command(
        'handshake', undef, $request, $callback);

    return;
}

sub _mkele_peer {
    my ($self) = @_;

    my $app_id = $self->app_id;
    my $unique_id = $self->connection->local_selection_id;

    return
        [ 'peer',
          {
              'app_id'    => $app_id,
              'unique_id' => $unique_id,
              'window_id' => $self->xid_local,
          }, ];
}

sub _gotele_peer {
    my ($self, $peer_ele) = @_;
    my ($tag, $attribute_hash) = @{$peer_ele};

    my $tag_expected = 'peer';
    $tag eq $tag_expected
      or die sprintf
        "unexpected body tag: '%s': expected: '%s'"
          , $tag, $tag_expected;

    my ($app_id, $unique_id, $window_id) =
      @{$attribute_hash}{qw( app_id unique_id window_id )};
    defined $app_id    or die 'missing attribute: app_id';
    defined $unique_id or die 'missing attribute: unique_id';
    defined $window_id or die 'missing attribute: window_id';

    $self->xid_remote($window_id);

    return ($app_id, $unique_id, $window_id);
}

sub send_ping {
    my ($self, $callback) = @_;
    $self->send_command(
        'ping', undef, undef, $callback);
    return;
}

sub send_shutdown_clean {
    my ($self, $callback) = @_;
    my $request = [ 'shutdown', { 'type' => 'clean' } ];
    $self->send_command(
        'shutdown', undef, $request,
        sub {
            my ($result) = @_;
            $self->close if $result->success;
            $callback->($result) if $callback;
        });
    return;
}

sub send_goodbye_exit {
    my ($self, $callback) = @_;
    my $request = [ 'goodbye', { 'type' => 'exit' } ];
    $self->send_command(
        'goodbye', undef, $request, $callback);
    return;
}

sub send_command {
    my ($self, $command, $view, $request, $callback) = @_;
    $self->is_open or die "the connection is closed\n";
    $self->callback($callback);
    $self->zircon_trace('send %s #%d', $command, $self->{'request_id'});
    my $request_xml = $self->request_xml($command, $view, $request);

    my $current_xid = $self->connection->context->widget_xid;
    my $advertised_xid = $self->xid_local;
    if ($current_xid ne $advertised_xid) {
        # should not happen, likely to break timeout control
        warn "Widget Xid $current_xid differs from our advertised Xid $advertised_xid\n";
    }

    $self->connection->send($request_xml);
    return;
}

# connection handlers

sub zircon_connection_request {
    my ($self, $request_xml) = @_;
    my ($request_id, $command, $view, $request) =
        @{$self->request_xml_parse($request_xml)};
    my $reply = $self->_request($command, $view, $request);
    my $reply_xml = $self->reply_xml($request_id, $command, $reply);
    return $reply_xml;
}

sub _request {
    my ($self, $command, $view, $request_body) = @_;

    $self->zircon_trace('command=%s', $command);
    for ($command) {

        when ('handshake') {

            my ($request_element, @rest) = @{$request_body};
            die "missing request element" unless defined $request_element;
            die "multiple request elements" if @rest;

            my ($app_id, $unique_id, $window_id) =
              $self->_gotele_peer($request_element);
            $self->connection->remote_selection_id($unique_id);
            $self->server->zircon_server_handshake($unique_id);
            $self->zircon_trace('Handshake request from remote (clipboard %s)', $unique_id);

            my $message = sprintf
                "Handshake successful with peer '%s', id '%s', xid '%s'"
                , $app_id, $unique_id, $window_id;

            return $self->message_ok($message, [ data => {}, $self->_mkele_peer ]);
        }

        when ('ping') {

            $self->server->zircon_server_ping;
            my $message = "ping ok!";

            return $self->message_ok($message);
        }

        when ('shutdown') {

            $self->connection->after(sub { CORE::exit; });
            $self->server->zircon_server_shutdown;
            my $message = "shutting down now!";

            return $self->message_ok($message);
        }

        when ('goodbye') {

            $self->server->zircon_server_goodbye;
            $self->close;
            my $message = "goodbye received, goodbye";

            return $self->message_ok($message);
        }

        default {
            return
                $self->server->zircon_server_protocol_command(
                    $command, $view, $request_body);
        }

    }

    return; # unreached, quietens perlcritic
}

sub zircon_connection_reply {
    my ($self, $reply_xml) = @_;
    if (my $callback = $self->callback) {
        my ($request_id,
            $command, $return_code, $reason,
            $view, $reply,
            ) = @{$self->reply_xml_parse($reply_xml)};
        my $success =
            defined $return_code
            && $return_code eq 'ok';
        my $result = Zircon::Protocol::Result::Reply->new(
            '-success' => $success,
            '-view'    => $view,
            '-reply'   => $reply,
            );
        $self->zircon_trace('Reply. return_code=%s', $return_code);
        $callback->($result);
        $self->callback(undef);
    }
    else {
        $self->zircon_trace('Reply, no callback.  reply=>>>\n%s\n<<<', $reply_xml);
    }
    return;
}

sub zircon_connection_timeout {
    my ($self) = @_;
    if (my $callback = $self->callback) {
        my $result = Zircon::Protocol::Result::Timeout->new;
        $self->zircon_trace
          ('Timeout. connection state=%s', $self->connection->state);
        $callback->($result);
        $self->callback(undef);
    }
    else {
        $self->zircon_trace
          ('Timeout, no callback.  connection state=%s', $self->connection->state);
    }
    return;
}

# utilities

sub message_ok {
    my ($self, $message, @more) = @_;

    return
        [ undef, # ok
          [ 'message', { }, $message ],
          @more ];
}

sub message_command_unknown {
    my ($self, $reason) = @_;

    return [ [ 'cmd_unknown', $reason ] ];
}

sub message_command_failed {
    my ($self, $reason) = @_;

    return [ [ 'cmd_failed', $reason ] ];
}

sub close {
    my ($self) = @_;
    $self->{'is_open'} = 0;
    return;
}

# attributes

sub app_id {
    my ($self) = @_;
    my $app_id = $self->{'app_id'};
    return $app_id;
}

sub server {
    my ($self) = @_;
    my $server = $self->{'server'};
    return $server;
}

sub connection {
    my ($self) = @_;
    my $connection = $self->{'connection'};
    return $connection;
}

sub is_open {
    my ($self) = @_;
    my $is_open = $self->{'is_open'};
    return $is_open;
}

sub callback {
    my ($self, @args) = @_;
    ($self->{'callback'}) = @args if @args;
    return $self->{'callback'};
}

sub xid_local { # strongly caching, read-only
    my ($self) = @_;
    $self->{'xid_local'} =
      $self->connection->context->widget_xid
        unless defined $self->{'xid_local'};
    return $self->{'xid_local'};
}

sub xid_remote { # delegated
    my ($self, @args) = @_;
    return $self->connection->xid_remote(@args);
}


# tracing

sub zircon_trace_prefix {
    my ($self) = @_;
    return sprintf("Z:Protocol: app_id=%s", $self->app_id);
}

1;

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
