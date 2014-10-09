
package Zircon::ZMap;

use strict;
use warnings;

use Readonly;
use Scalar::Util qw( weaken );

use Zircon::ZMap::View;

use parent qw( Zircon::Protocol::Server::AppLauncher );

our $ZIRCON_TRACE_KEY = 'ZIRCON_ZMAP_TRACE';

# Class methods

my @_list = ( );

sub list {
    my ($pkg) = @_;
    # filter the list because weak references may become undef
    my $list = [ grep { defined } @_list ];
    return $list;
}

my $_string_zmap_hash = { };

sub from_string {
    my ($pkg, $string) = @_;
    my $zmap = $_string_zmap_hash->{$string};
    return $zmap;
}

sub _add_zmap {
    my ($pkg, $new) = @_;
    push @_list, $new;
    weaken $_list[-1];
    $_string_zmap_hash->{"$new"} = $new;
    weaken $_string_zmap_hash->{"$new"};
    return;
}

# Constructor

sub new {
    my ($pkg, %arg_hash) = @_;
    my $new = $pkg->SUPER::new(
        -program         => 'zmap',
        %arg_hash,
        );

    $new->{'_id_view_hash'} = { };
    $new->{'_view_list'} = [ ];

    $pkg->_add_zmap($new);

    $new->launch_app;
    return $new;
}

# Object methods

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
    my ($view_previous) = values %{$self->_id_view_hash};
    my ($command, $view_id) =
        $view_previous
        ? ( 'add_to_view', $view_previous->view_id )
        : ( 'new_view',    undef                   )
        ;
    my $new_view_arg_hash = {
        map { $_ => $arg_hash->{"-$_"} } @_new_view_key_list
    };

    my $result;
    $self->send_command(
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
    $self->_add_view($view_id, $view);
    return $view;
}

sub _add_view {
    my ($self, $id, $view) = @_;
    $self->_id_view_hash->{$id} = $view;
    weaken $self->_id_view_hash->{$id};
    push @{$self->_view_list}, $view;
    weaken $self->_view_list->[-1];
    return;
}

sub view_destroyed {
    my ($self, $view) = @_;

    my $result;
    $self->send_command(
        'close_view',
        $view->view_id,
        undef,
        sub { ($result) = @_; },
        );

    ($result && $result->success) or die "close_view: failed";

    return;
}

sub send_command_and_xml {
    my ($self, $view, $command, $xml) = @_;

    my $result;
    $self->send_command(
        $command, $view->view_id, $xml,
        sub {
            ($result) = @_;
        });

    return $result;
}

# protocol server

sub handler_for_view {
    my ($self, $view_id) = @_;
    my $view = $self->_view_from_id($view_id);
    return $view->handler;
}

sub _view_from_id {
    my ($self, $view_id) = @_;
    my $view;
    if (defined $view_id) {
        $view = $self->_id_view_hash->{$view_id};
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

Readonly my %_dispatch_table => (

    feature_loading_complete => {
        method            => \&_command_feature_loading_complete,
        key_entity        => qw( status ),
        required_entities => [ qw( featureset ) ],
    },

    single_select => {
        method            => \&_command_single_select,
        key_entity        => qw( featureset ),
    },

    multiple_select => {
        method            => \&_command_multiple_select,
        key_entity        => qw( featureset ),
    },

    feature_details => {
        method            => \&_command_feature_details,
        key_entity        => qw( featureset ),
    },

    edit => {
        method            => \&_command_edit,
        key_entity        => qw( featureset ),
    },

    );

sub command_dispatch {
    my ($self, $command) = @_;
    return $_dispatch_table{$command};
}

sub _command_feature_loading_complete {
    my ($self, $handler, $status_entity, $tag_entity_hash) = @_;

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
    my ($self, $handler, $featureset_entity_hash) = @_;

    my $name_list = _select_name_list($featureset_entity_hash);
    $handler->zircon_zmap_view_single_select($name_list);

    my $protocol_message = 'single select received...thanks !';
    my $reply = $self->protocol->message_ok($protocol_message);
    return $reply;
}

sub _command_multiple_select {
    my ($self, $handler, $featureset_entity_hash) = @_;
    my $name_list = _select_name_list($featureset_entity_hash);
    $handler->zircon_zmap_view_multiple_select($name_list);
    my $protocol_message = 'multiple select received...thanks !';
    my $reply = $self->protocol->message_ok($protocol_message);
    return $reply;
}

sub _select_name_list {
    # *not* a method
    my ($featureset_entity_hash) = @_;
    my $feature_entity = _feature_from_featureset($featureset_entity_hash);
    my $name = $feature_entity->[1]{'name'};
    defined $name or die "missing name";
    my $name_list = [ $name ];
    return $name_list;
}

sub _command_feature_details {
    my ($self, $handler, $featureset_entity_hash) = @_;
    my $feature_entity = _feature_from_featureset($featureset_entity_hash);
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
    my ($self, $handler, $featureset_entity) = @_;
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

sub _id_view_hash {
    my ($self) = @_;
    my $_id_view_hash = $self->{'_id_view_hash'};
    return $_id_view_hash;
}

# public for otterlace
sub view_list {
    my ($self) = @_;
    # filter the list because weak references may become undef
    my $view_list = [ grep { defined } @{$self->_view_list} ];
    return $view_list;
}

sub _view_list {
    my ($self) = @_;
    my $view_list = $self->{'_view_list'};
    return $view_list;
}

# tracing

sub zircon_trace_prefix {
    my ($self) = @_;
    return 'Z:ZMap';
}

1;

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
