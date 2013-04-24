
package Zircon::ZMap;

use strict;
use warnings;

use Try::Tiny;

use Zircon::Protocol;
use Zircon::ZMap::View;

use base qw(
    Zircon::ZMap::Core
    Zircon::Protocol::Server
    );

my $_id = 0;

sub _init { ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
    my ($self, $arg_hash) = @_;
    $self->Zircon::ZMap::Core::_init($arg_hash); ## no critic (Subroutines::ProtectPrivateSubs)
    my ($app_id, $context) =
        @{$arg_hash}{qw( -app_id -context )};
    $self->{'_id'} = $_id++;
    $self->{'_app_id'} = $app_id;
    $self->{'_context'} = $context;
    $self->{'_protocol'} = $self->_protocol;
    return;
}

sub _protocol {
    my ($self) = @_;
    my $id = $self->id;
    my $app_id = $self->app_id;
    my $selection_id =
        sprintf '%s_%s', $app_id, $id;
    my $protocol =
        Zircon::Protocol->new(
            '-app_id'       => $app_id,
            '-selection_id' => $selection_id,
            '-context'      => $self->context,
            '-server'       => $self,
        );
    return $protocol;
}

sub new_view {
    my ($self, %arg_hash) = @_;
    my $view = $self->_new_view(\ %arg_hash);
    return $view;
}

my @_new_view_key_list = qw(
    name
    start
    end
    config_file
    );

sub _new_view {
    my ($self, $arg_hash) = @_;
    my $new_view_arg_hash = {
        map { $_ => $arg_hash->{"-$_"} } @_new_view_key_list
    };
    my $view;
    $self->protocol->send_command(
        'new_view',
        undef, # no view
        [ 'sequence', $new_view_arg_hash ],
        sub {
            my ($result) = @_;
            $self->protocol->connection->after(
                sub {
                    $self->wait_finish;
                });
            die "&_new_view: failed" unless $result->success;
            my $handler = $arg_hash->{'-handler'};
            $view = $self->_new_view_from_result($handler, $result);
        });
    $self->wait;
    return $view;
}

sub _new_view_from_result {
    my ($self, $handler, $result) = @_;
    my $view_id = $result->view;
    my $view = Zircon::ZMap::View->new($self);
    $self->add_view($view_id, $view);
    return $view;
}

sub waitVariable {
    my ($self, $var) = @_;
    $self->context->waitVariable($var);
    return;
}

sub launch_zmap {
    my ($self) = @_;
    $self->Zircon::ZMap::Core::launch_zmap;
    $self->wait; # don't return until the Zircon handshake callback calls wait_finish()
    return;
}

sub zmap_arg_list {
    my ($self) = @_;
    my $peer_name = $self->app_id;
    my $protocol = $self->protocol;
    my $connection = $protocol->connection;
    my $peer_clipboard =
        $connection->local_selection_id;
    my $zmap_arg_list = [
        @{$self->Zircon::ZMap::Core::zmap_arg_list},
        "--peer-name=${peer_name}",
        "--peer-clipboard=${peer_clipboard}",
        ];
    return $zmap_arg_list;
}

# protocol server

sub zircon_server_handshake {
    my ($self, @arg_list) = @_;
    $self->protocol->connection->after(
        sub {
            $self->wait_finish; # make the caller return
        });
    $self->Zircon::Protocol::Server::zircon_server_handshake(@arg_list);
    return;
}

# attributes

sub id {
    my ($self) = @_;
    my $id = $self->{'_id'};
    return $id;
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

1;

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk