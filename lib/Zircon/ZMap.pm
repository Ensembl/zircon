
package Zircon::ZMap;

use strict;
use warnings;

use feature qw(switch);

use Try::Tiny;
use Scalar::Util qw( refaddr );

use Zircon::Protocol;
use Zircon::ZMap::View;

use base qw(
    Zircon::ZMap::Core
    Zircon::Protocol::Server
    );
our $ZIRCON_TRACE_KEY = 'ZIRCON_ZMAP_TRACE';

my $_id = 0;

sub _init { ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
    my ($self, $arg_hash) = @_;
    $self->Zircon::ZMap::Core::_init($arg_hash); ## no critic (Subroutines::ProtectPrivateSubs)

    foreach my $k (qw( app_id context timeout_ms timeout_retries )) {
        $self->{"_$k"} = $arg_hash->{"-$k"}; # value may be undef
    }
    $self->{'_id'} = $_id++;
    $self->{'_protocol'} = $self->_protocol; # needs app_id etc.

    my $peer_socket = $self->protocol->connection->local_endpoint;
    # for zmap_command, used later in new
    push @{$self->{'_arg_list'}}, "--peer-socket=${peer_socket}";
    return;
}

sub _protocol {
    my ($self) = @_;
    my $id = $self->id;
    my $app_id = $self->app_id;
    my $protocol =
        Zircon::Protocol->new(
            '-app_id'       => $app_id,
            '-context'      => $self->context,
            '-server'       => $self,
            '-connection_timeout' => $self->{'_timeout_ms'},
            '-timeout_retries' => $self->{'_timeout_retries'},
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

    my $result;
    $self->protocol->send_command(
        $command,
        $view_id,
        [ 'sequence', $new_view_arg_hash ],
        sub { ($result) = @_; },
        );

    die "&_new_view: failed" unless $result && $result->success;

    my $handler = $arg_hash->{'-handler'};
    my $name    = $arg_hash->{'-view_name'} || $arg_hash->{'-name'};
    my $view = $self->_new_view_from_result($handler, $name, $result);

    return $view;
}

sub waitVariable_with_fail {
    my ($self, $var_ref) = @_;
    my $to_intvl = $self->protocol->connection->timeout_interval;
    my $to_nretr = $self->protocol->connection->timeout_retries_initial;
    my $fail_timeout = $to_intvl * ($to_nretr + 2); # millisec * count

    my $wait_finish = sub {
        $$var_ref ||= 'fail_timeout';
        $self->zircon_trace
          ('fail_timeout(0x%x), var %s=%s after %d ms * (%d + 2) retries = %.2f sec',
           refaddr($self), $var_ref, $$var_ref,
           $to_intvl, $to_nretr, $fail_timeout);
    };
    my $handle = $self->context->timeout($fail_timeout, $wait_finish);
    $self->zircon_trace('startWAIT(0x%x), var %s=%s',
                        refaddr($self), $var_ref, $$var_ref);

    local $Zircon::TkZMQ::Context::TANGLE_ACK{'Z:Z:waitVariable_with_fail'} = 1;
    # Justify one extra level of event-loop.
    # Re-entering this code will provoke warnings.

    $self->context->waitVariable($var_ref);
    $self->zircon_trace('stopWAIT(0x%x), var %s=%s',
                        refaddr($self), $var_ref, $$var_ref);
    $handle->cancel;
    return;
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
        );

    ($result && $result->success) or die "close_view: failed";

    return;
}

sub send_command_and_xml {
    my ($self, $view, $command, $xml) = @_;

    my $result;
    $self->protocol->send_command(
        $command, $view->view_id, $xml,
        sub {
            ($result) = @_;
        });

    return $result;
}


sub launch_zmap {
    my ($self) = @_;

    my $wait = 0;
    $self->launch_zmap_wait_finish(sub { $wait = 'ok' });

    # we hope the Zircon handshake callback calls $self->launch_zmap_wait_finish->()
    my $pid = $self->Zircon::ZMap::Core::launch_zmap;
    $self->waitVariable_with_fail(\ $wait);
    if ($wait ne 'ok') {
        kill 'TERM', $pid; # can't talk to it -> don't want it
        die "launch_zmap(): timeout waiting for the handshake; killed pid $pid";
        # wait() happens in event loop
    }

    return;
}

# protocol server

sub zircon_server_handshake {
    my ($self, @arg_list) = @_;
    $self->protocol->connection->after(
        sub { $self->launch_zmap_wait_finish->(); });
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
                $self->protocol->message_command_unknown($reason);
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
    my (undef, $status_attribute_hash, $status_sub_entity_list) = @{$status_entity};
    my $status = $status_attribute_hash->{'value'};
    defined $status or die "missing status";
    my $status_sub_entity_hash = { map { $_->[0] => $_ } @{$status_sub_entity_list} };
    my $message_entity = $status_sub_entity_hash->{'message'};
    defined $message_entity or die "missing message entity";
    my $message = $message_entity->[2];
    defined $message or die "missing message";
    my $feature_count = $status_attribute_hash->{'features_loaded'};
    defined $feature_count or die "missing feature count";
    my $featureset_entity = $tag_entity_hash->{'featureset'};
    $featureset_entity or die "missing featureset entity";
    my $featureset_attribute_hash = $featureset_entity->[1];
    my $featureset_list = $featureset_attribute_hash->{'names'};
    defined $featureset_list or die "missing featureset list";
    my @featureset_list = split /[[:space:]]*;[[:space:]]*/, $featureset_list;

    my $after_sub = $handler->zircon_zmap_view_features_loaded(
        $status, $message, $feature_count, @featureset_list);
    $self->protocol->connection->after($after_sub) if $after_sub;

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
        $feature_details_xml
        ? [ undef, $feature_details_xml ] # ok, with raw xml
        : $self->protocol->message_command_failed('no feature details...failed');
        ;
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
    my $success =
        $handler->zircon_zmap_view_edit(
            $name, $style, $sub_list);
    if ($success) {
        my $protocol_message = 'edit received...thanks !';
        my $reply = $self->protocol->message_ok($protocol_message);
        return $reply;
    }
    else {
        my $protocol_message = 'object not editable...failed !';
        my $reply = $self->protocol->message_command_failed($protocol_message);
        return $reply;
    }
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

sub launch_zmap_wait_finish {
    my ($self, @args) = @_;
    ($self->{'_launch_zmap_wait_finish'}) = @args if @args;
    my $launch_zmap_wait_finish = $self->{'_launch_zmap_wait_finish'};
    return $launch_zmap_wait_finish;
}

# destructor

sub DESTROY {
    my ($self) = @_;

    # Beware trapping new references to $self in closures which are
    # stashed elsewhere.  DESTROY will run again when they go away.
    if ($self->{'_destroyed_already'}) {
        warn "DESTROY $self again - do nothing this time\n"; # RT395938
        return;
    }
    $self->{'_destroyed_already'} = 1;

    my $wait = 0;
    my $wait_finish_ok = sub { $wait = 'ok' };

    my $callback = sub {
        my ($result) = @_;
        $self->protocol->connection->after($wait_finish_ok);
        die "shutdown: failed" unless $result->success;
    };

    try {
        $self->protocol->send_command('shutdown', undef, undef, $callback);
    }
    catch { warn $_; };
    return;
}

1;

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
