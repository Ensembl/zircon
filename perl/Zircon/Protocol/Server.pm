
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

sub zircon_zmap_view_features_loaded {
    my ($self, $status, $client_message, @feature_list) = @_;
    my $message =
        sprintf "features loaded: %s\n%s"
        , $client_message, (join ', ', @feature_list);
    $self->zircon_server_log($message);
    return;
}

sub zircon_server_log {
    my ($self, $message) = @_;
    warn sprintf "%s: %s\n", $self, $message;
    return;
}

1;
