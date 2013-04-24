
package Zircon::ZMap;

use strict;
use warnings;

use feature qw(switch);

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
            '-connection_timeout' => 2000,
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
    my $tag_attribute_hash_hash = { };
    $tag_attribute_hash_hash->{$_->[0]} = $_->[1] for @{$result->reply};
    my $attribute_hash = $tag_attribute_hash_hash->{'view'} or die "missing view entity";
    my $view_id = $attribute_hash->{'view_id'} or die "missing view_id attribute";
    my $view =
        Zircon::ZMap::View->new(
            '-zmap'    => $self,
            '-handler' => $handler,
        );
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

sub zircon_server_protocol_command {
    my ($self, $command, $view_id, $request_body) = @_;

    my $tag_attribute_hash_hash = { };
    $tag_attribute_hash_hash->{$_->[0]} = $_->[1]
        for @{$request_body};

    for ($command) {

        my $view;
        if (defined $view_id) {
            $view = $self->id_view_hash->{$view_id};
            $view or die sprintf "invalid view id: '%s'", $view_id;
        }
        else {
            my $view_list = $self->view_list;
            ($view) = @{$view_list} if @{$view_list} == 1;
        }

        when ('feature_loading_complete') {
            $view or die "missing view";
            my $status = $tag_attribute_hash_hash->{'status'}{'value'};
            $status or die "missing status";
            my $message = $tag_attribute_hash_hash->{'status'}{'message'};
            $message or die "missing message";
            my $featureset_list = $tag_attribute_hash_hash->{'featureset'}{'names'};
            my @featureset_list = split /[;[:space:]]+/, $featureset_list;
            $view->handler->zircon_zmap_view_features_loaded(
                $status, $message, @featureset_list);
            my $protocol_message = 'got features loaded...thanks !';
            my $reply = $self->protocol->message_ok($protocol_message);
            return $reply;
        }

        default {
            my $reason = "Unknown ZMap protocol command: '${command}'";
            my $reply =
                $self->protocol->message_command_unknown($command, $reason);
            return $reply;
        }

    }

    return; # never reached, quietens "perlcritic --stern"
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
