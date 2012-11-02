
package Zircon::Protocol::Server;

use strict;
use warnings;

sub zircon_server_handshake {
    my ($self, $id) = @_;
    my $message = sprintf 'handshake: id: %s', $id;
    $self->zircon_server_log($message);
    return;
}

sub zircon_server_ping {
    my ($self, $id) = @_;
    my $message = 'ping';
    $self->zircon_server_log($message);
    return;
}

sub zircon_server_shutdown {
    my ($self, $id) = @_;
    my $message = 'shutdown';
    $self->zircon_server_log($message);
    return;
}

sub zircon_server_goodbye {
    my ($self, $id) = @_;
    my $message = 'goodbye';
    $self->zircon_server_log($message);
    return;
}

sub zircon_server_protocol_command {
    my ($self, $command, $view, $request_body) = @_;
    my $message = sprintf "invalid command: '%s'", $command;
    $self->zircon_server_log($message);
    return;
}

sub zircon_server_log {
    my ($self, $message) = @_;
    warn sprintf "%s: %s\n", $self, $message;
    return;
}

1;

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
