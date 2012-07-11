
package Zircon::Protocol::Command;

use strict;
use warnings;

# handshake

sub command_request_handshake {
    my ($self) = @_;

    my $app_id = $self->app_id;
    my $unique_id = $self->selection_id;

    return
        [ 'peer',
          {
              'app_id'    => $app_id,
              'unique_id' => $unique_id,
          }, ];
}

sub command_reply_handshake {
    my ($self, $view, $request_body) = @_;

    my ($request_element, @rest) = @{$request_body};
    die "missing request element" unless defined $request_element;
    die "multiple request elements" if @rest;

    my ($tag, $attribute_hash) = @{$request_element};

    my $tag_expected = 'peer';
    $tag eq $tag_expected
        or die sprintf
        "unexpected body tag: '%s': expected: '%s'"
        , $tag, $tag_expected;

    my ($app_id, $unique_id) =
        @{$attribute_hash}{qw( app_id unique_id )};
    defined $app_id    or die 'missing attribute: app_id';
    defined $unique_id or die 'missing attribute: unique_id';

    $self->connection->remote_selection_id($unique_id);
    $self->server->zircon_server_handshake($unique_id);

    my $message = sprintf
        "Handshake successful with peer '%s', id '%s'"
        , $app_id, $unique_id;

    return $self->command_message_ok($message);
}

# ping

sub command_request_ping {
    my ($self) = @_;

    return undef; ## no critic (Subroutines::ProhibitExplicitReturnUndef)
}

sub command_reply_ping {
    my ($self) = @_;

    $self->server->zircon_server_ping;
    my $message = "ping ok!";

    return $self->command_message_ok($message);
}

# shutdown

sub command_request_shutdown {
    my ($self, $type) = @_;

    my $request =
        defined $type
        ? [ 'shutdown', { 'type' => $type } ]
        : undef;

    return $request;
}

sub command_reply_shutdown {
    my ($self) = @_;

    $self->server->zircon_server_shutdown;
    my $message = "shutting down now!";

    return (
        $self->command_message_ok($message),
        'after' => sub { CORE::exit; } );
}

# goodbye

sub command_request_goodbye {
    my ($self, $type) = @_;

    my $request =
        defined $type
        ? [ 'goodbye', { 'type' => $type } ]
        : undef;

    return $request;
}

sub command_reply_goodbye {
    my ($self) = @_;

    $self->server->zircon_server_goodbye;
    $self->close;
    my $message = "goodbye received, goodbye";

    return $self->command_message_ok($message);
}

# utilities

sub command_message_ok {
    my ($self, $message) = @_;

    return
        [ undef, # ok
          [ 'message', { }, $message ] ];
}

1;
