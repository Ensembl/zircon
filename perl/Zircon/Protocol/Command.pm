
package Zircon::Protocol::Command;

use strict;
use warnings;

use feature qw( switch );

# request handler

sub command_request {
    my ($self, $command, $view, $request_body) = @_;

    for ($command) {

        when ('handshake') {

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

        when ('ping') {

            $self->server->zircon_server_ping;
            my $message = "ping ok!";

            return $self->command_message_ok($message);
        }

        when ('shutdown') {

            $self->server->zircon_server_shutdown;
            my $message = "shutting down now!";

            return (
                $self->command_message_ok($message),
                'after' => sub { CORE::exit; } );
        }

        when ('goodbye') {

            $self->server->zircon_server_goodbye;
            $self->close;
            my $message = "goodbye received, goodbye";

            return $self->command_message_ok($message);
        }

        default {
            return
                $self->server->zircon_server_protocol_command(
                    $command, $view, $request_body);
        }

    }

    return; # unreached, quietens perlcritic
}

# utilities

sub command_message_ok {
    my ($self, $message) = @_;

    return
        [ undef, # ok
          [ 'message', { }, $message ] ];
}

1;

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
