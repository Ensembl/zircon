
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
    my $peer_name = $self->app_id;
    my $peer_clipboard =
        $self->protocol->connection->local_selection_id;
    push @{$self->{'_arg_list'}},
    "--peer-name=${peer_name}",
    "--peer-clipboard=${peer_clipboard}",
    ;
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
    my ($view_previous) = values %{$self->id_view_hash};
    my ($command, $view_id) =
        $view_previous
        ? ( 'add_to_view', $view_previous->view_id )
        : ( 'new_view',    undef                   )
        ;
    my $new_view_arg_hash = {
        map { $_ => $arg_hash->{"-$_"} } @_new_view_key_list
    };
    my $view;
    $self->protocol->send_command(
        $command,
        $view_id,
        [ 'sequence', $new_view_arg_hash ],
        sub {
            my ($result) = @_;
            $self->protocol->connection->after(
                sub {
                    $self->wait_finish;
                });
            die "&_new_view: failed" unless $result->success;
            my $handler = $arg_hash->{'-handler'};
            my $name    = $arg_hash->{'-name'};
            $view = $self->_new_view_from_result($handler, $name, $result);
        });
    $self->wait;
    return $view;
}

sub _new_view_from_result {
    my ($self, $handler, $name, $result) = @_;
    my $tag_attribute_hash_hash = { };
    $tag_attribute_hash_hash->{$_->[0]} = $_->[1] for @{$result->reply};
    my $attribute_hash = $tag_attribute_hash_hash->{'view'} or die "missing view entity";
    my $view_id = $attribute_hash->{'view_id'} or die "missing view_id attribute";
    my $view =
        Zircon::ZMap::View->new(
            '-zmap'    => $self,
            '-handler' => $handler,
            '-view_id' => $view_id,
            '-name'    => $name,
        );
    $self->add_view($view_id, $view);
    return $view;
}

sub view_destroyed {
    my ($self, $view) = @_;
    my $result;
    $self->protocol->send_command(
        'close_view',
        $view->view_id,
        undef,
        sub {
            ($result) = @_;
            $self->protocol->connection->after(
                sub { $self->wait_finish; });
        });
    $self->wait;
    ($result && $result->success)
        or die "close_view: failed";
    return;
}

sub send_command_and_xml {
    my ($self, $view, $command, $xml) = @_;
    my $result;
    $self->protocol->send_command(
        $command, $view->view_id, $xml,
        sub {
            ($result) = @_;
            $self->protocol->connection->after(
                sub {
                    $self->wait_finish;
                });
        });
    $self->wait;
    return $result;
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

    my $view = $self->_view_from_id($view_id);
    my $handler = $view->handler;

    my $tag_entity_hash = { };
    $tag_entity_hash->{$_->[0]} = $_ for @{$request_body};

    for ($command) {

        when ('feature_loading_complete') {
            my $reply =
                $self->_command_feature_loading_complete(
                    $handler, $tag_entity_hash);
            return $reply;
        }

        when ('single_select') {
            my $reply =
                $self->_command_single_select(
                    $handler, $tag_entity_hash);
            return $reply;
        }

        when ('multiple_select') {
            my $reply =
                $self->_command_multiple_select(
                    $handler, $tag_entity_hash);
            return $reply;
        }

        when ('feature_details') {
            my $reply =
                $self->_command_feature_details(
                    $handler, $tag_entity_hash);
            return $reply;
        }

        when ('edit') {
            my $reply =
                $self->_command_edit(
                    $handler, $tag_entity_hash);
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

sub _view_from_id {
    my ($self, $view_id) = @_;
    my $view;
    if (defined $view_id) {
        $view = $self->id_view_hash->{$view_id};
        $view or die sprintf "invalid view id: '%s'", $view_id;
    }
    else {
        my $view_list = $self->view_list;
        die "no views"       if @{$view_list} < 1;
        die "multiple views" if @{$view_list} > 1;
        ($view) = @{$view_list};
    }
    return $view;
}

sub _command_feature_loading_complete {
    my ($self, $handler, $tag_entity_hash) = @_;
    my $status_entity = $tag_entity_hash->{'status'};
    $status_entity or die "missing status entity";
    my $status_attribute_hash = $status_entity->[1];
    my $status = $status_attribute_hash->{'value'};
    defined $status or die "missing status";
    my $message = $status_attribute_hash->{'message'};
    defined $message or die "missing message";
    my $featureset_entity = $tag_entity_hash->{'featureset'};
    $featureset_entity or die "missing featureset entity";
    my $featureset_attribute_hash = $featureset_entity->[1];
    my $featureset_list = $featureset_attribute_hash->{'names'};
    defined $featureset_list or die "missing featureset list";
    my @featureset_list = split /[;[:space:]]+/, $featureset_list;
    $handler->zircon_zmap_view_features_loaded(
        $status, $message, @featureset_list);
    my $protocol_message = 'got features loaded...thanks !';
    my $reply = $self->protocol->message_ok($protocol_message);
    return $reply;
}

sub _command_single_select {
    my ($self, $handler, $tag_entity_hash) = @_;
    my $name_list = _select_name_list($tag_entity_hash);
    $handler->zircon_zmap_view_single_select($name_list);
    my $protocol_message = 'single select received...thanks !';
    my $reply = $self->protocol->message_ok($protocol_message);
    return $reply;
}

sub _command_multiple_select {
    my ($self, $handler, $tag_entity_hash) = @_;
    my $name_list = _select_name_list($tag_entity_hash);
    $handler->zircon_zmap_view_multiple_select($name_list);
    my $protocol_message = 'multiple select received...thanks !';
    my $reply = $self->protocol->message_ok($protocol_message);
    return $reply;
}

sub _select_name_list {
    # *not* a method
    my ($tag_entity_hash) = @_;
    my $feature_entity = _feature_entity($tag_entity_hash);
    my $name = $feature_entity->[1]{'name'};
    defined $name or die "missing name";
    my $name_list = [ $name ];
    return $name_list;
}

sub _command_feature_details {
    my ($self, $handler, $tag_entity_hash) = @_;
    my $feature_entity = _feature_entity($tag_entity_hash);
    my $name = $feature_entity->[1]{'name'};
    defined $name or die "missing name";
    my $feature_body = $feature_entity->[2];
    my $tag_feature_body_hash = { };
    push @{$tag_feature_body_hash->{$_->[0]}}, $_ for @{$feature_body};
    my $feature_details_xml =
        $handler->zircon_zmap_view_feature_details_xml(
            $name, $tag_feature_body_hash);
    my $reply =
        [ undef, # ok
          $feature_details_xml, # raw xml
        ];
    return $reply;
}

sub _command_edit {
    my ($self, $handler, $tag_entity_hash) = @_;
    my $featureset_entity = _featureset_entity($tag_entity_hash);
    my $style = $featureset_entity->[1]{'name'};
    defined $style or die "missing style";
    my $feature_entity = _feature_from_featureset($featureset_entity);
    my $name = $feature_entity->[1]{'name'};
    defined $name or die "missing name";
    my $feature_body = $feature_entity->[2];
    my $tag_attribute_list_hash = { };
    push @{$tag_attribute_list_hash->{$_->[0]}}, $_->[1]
        for @{$feature_body};
    my $sub_list =
        $tag_attribute_list_hash->{'subfeature'};
    $handler->zircon_zmap_view_edit(
        $name, $style, $sub_list);
    my $protocol_message = 'edit received...thanks !';
    my $reply = $self->protocol->message_ok($protocol_message);
    return $reply;
}

sub _feature_entity {
    # *not* a method
    my ($tag_entity_hash) = @_;
    my $featureset_entity = _featureset_entity($tag_entity_hash);
    my $feature_entity = _feature_from_featureset($featureset_entity);
    return $feature_entity;
}

sub _featureset_entity {
    # *not* a method
    my ($tag_entity_hash) = @_;
    my $featureset_entity = $tag_entity_hash->{'featureset'};
    $featureset_entity or die "missing featureset entity";
    return $featureset_entity;
}

sub _feature_from_featureset {
    # *not* a method
    my ($featureset_entity) = @_;
    my $featureset_body = $featureset_entity->[2];
    my $tag_feature_hash = { };
    $tag_feature_hash->{$_->[0]} = $_ for @{$featureset_body};
    my $feature_entity = $tag_feature_hash->{'feature'};
    $feature_entity or die "missing feature entity";
    return $feature_entity;
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

# destructor

sub DESTROY {
    my ($self) = @_;
    try {
        $self->protocol->send_command(
            'shutdown',
            undef,
            undef,
            sub {
                my ($result) = @_;
                $self->protocol->connection->after(
                    sub {
                        $self->wait_finish;
                    });
                die "shutdown: failed" unless $result->success;
            });
        $self->wait;
    }
    catch { warn $_; };
    return;
}

1;

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
