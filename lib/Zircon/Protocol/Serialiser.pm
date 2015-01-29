
package Zircon::Protocol::Serialiser;

use strict;
use warnings;

use Carp;
use Scalar::Util qw( weaken );

use Zircon::Timestamp;

use Readonly;
Readonly my $ZIRCON_PROTOCOL_VERSION => '3.0';
Readonly my $ZIRCON_DEFAULT_APP_TAG  => 'zmap';

sub new {
    my ($pkg, %arg_hash) = @_;
    my $new = { };
    bless $new, $pkg;
    $new->_init(\%arg_hash);
    return $new;
}

sub _init {
    my ($self, $arg_hash) = @_;
    $self->_app_id(    $arg_hash->{'-app_id'}    ) or croak "missing -app_id parameter";
    $self->_connection($arg_hash->{'-connection'}) or croak "missing -connection parameter";
    $self->_app_tag(   $arg_hash->{'-app_tag'} // $ZIRCON_DEFAULT_APP_TAG );
    return;
}

# attributes

sub _app_id {
    my ($self, @args) = @_;
    ($self->{'_app_id'}) = @args if @args;
    my $_app_id = $self->{'_app_id'};
    return $_app_id;
}

sub _connection {
    my ($self, @args) = @_;
    if (@args) {
        ($self->{'_connection'}) = @args;
        weaken $self->{'_connection'};
    }
    my $_connection = $self->{'_connection'};
    return $_connection;
}

sub _app_tag {
    my ($self, @args) = @_;
    ($self->{'_app_tag'}) = @args if @args;
    my $_app_tag = $self->{'_app_tag'};
    return $_app_tag;
}

# creation

sub serialise_request {
    my ($self, $command, $view_id, $request, $headers) = @_;
    my $request_body =
        ref $request ? $self->serialise_element(@{$request}) : $request;
    my $request_element = $self->serialise_element(
        'request', {
            'command' => $command,
            'view_id' => $view_id,
        }, $request_body);
    my $app_id = $self->_app_id;
    my $socket_id = $self->_connection->remote_endpoint;
    my $protocol_element = $self->serialise_element(
        $self->_app_tag, {
            %{ $headers // {} },
            'version'      => $ZIRCON_PROTOCOL_VERSION,
            'type'         => 'request',
            'app_id'       => $app_id,
            'socket_id'    => $socket_id,
            $self->_timestamp($headers),
        }, $request_element);
    return $self->finalise_element($protocol_element);
}

sub serialise_reply {
    my ($self, $request_id, $command, $reply, $timestamp) = @_;
    my ($status, @reply_body) = @{$reply};
    my ($return_code, $reason) =
        defined $status ? @{$status} : ( 'ok' );
    my $reply_element =
        defined $status
        ? $self->serialise_element(
            'reply', {
                'command'     => $command,
                'return_code' => $return_code,
                'reason'      => $reason,
            })
        : $self->serialise_element(
            'reply', {
                'command'     => $command,
                'return_code' => 'ok',
            },
            @reply_body)
        ;
    my $app_id = $self->_app_id;
    my $socket_id = $self->_connection->local_endpoint;
    my $protocol_element = $self->serialise_element(
        $self->_app_tag, {
            'version'      => $ZIRCON_PROTOCOL_VERSION,
            'type'         => 'reply',
            'app_id'       => $app_id,
            'socket_id'    => $socket_id,
            'request_id'   => $request_id,
            $self->_timestamp($timestamp),
        }, $reply_element);
    return $self->finalise_element($protocol_element);
}

# Default is null-op
sub finalise_element {
    my ($self, $element) = @_;
    return $element;
}

sub _timestamp {
    my ($self, $headers) = @_;
    return if $self->inhibit_timestamps;

    unless (exists $headers->{clock_sec} and exists $headers->{clock_usec}) {
        $headers = Zircon::Timestamp->timestamp;
    }

    my ($sec, $usec) = @$headers{qw( clock_sec clock_usec )};
    return ('request_time' => "$sec,$usec");
}

# Override in child class to turn off timestamps (in xml.t, for example).
#
sub inhibit_timestamps { return }


# parsing

# Default is null-op
sub pre_parse {
    my ($self, $raw) = @_;
    return $raw;
}

my @request_parse_parameter_list = (
    'tag_expected' => 'request',
    'attribute_required' => [ qw(
        command
        ) ],
    'attribute_used' => [ qw(
        command
        view_id
        ) ],
    );

sub parse_request {
    my ($self, $request) = @_;
    $request = $self->pre_parse($request);
    my ($request_id, $protocol_attribute_hash, $content) =
        @{$self->_protocol_parse($request)};
    my $app_id = $protocol_attribute_hash->{app_id};
    my $content_parse =
        $self->_content_parse($content, @request_parse_parameter_list);
    my $parse = [ $request_id, $app_id, @{$content_parse} ];
    return $parse;
}

my @reply_parse_parameter_list = (
    'tag_expected' => 'reply',
    'attribute_required' => [ qw(
        command
        return_code
        ) ],
    'attribute_used' => [ qw(
        command
        return_code
        reason
        view
        ) ],
    );

sub parse_reply {
    my ($self, $reply) = @_;
    $reply = $self->pre_parse($reply);
    my ($request_id, $protocol_attribute_hash, $content) =
        @{$self->_protocol_parse($reply)};
    my $content_parse =
        $self->_content_parse($content, @reply_parse_parameter_list);
    my $parse = [ $request_id, @{$content_parse} ];
    return $parse;
}

sub _protocol_parse {
    my ($self, $raw) = @_;

    my ($tag, $attribute_hash, $content) = @{$self->_parse_unique_element($raw)};
    my $tag_expected = $self->_app_tag;
    $tag eq $tag_expected
        or die sprintf
        "invalid protocol tag: '%s': expected: '%s'"
        , $tag, $tag_expected;

    my $request_id = $attribute_hash->{'request_id'};
    defined $request_id
        or die "missing protocol attribute: 'request_id'";

    my $parse = [ $request_id, $attribute_hash, $content ];

    return $parse;
}

sub _content_parse {
    my ($self, $raw, %parameter_hash) = @_;

    my (
        $tag_expected,
        $attribute_required,
        $attribute_used,
        ) =
        @parameter_hash{qw(
        tag_expected
        attribute_required
        attribute_used
        )};

    my ($tag, $attribute_hash, $raw_body) = @{ $self->_parse_unique_element($raw) };
    $tag eq $tag_expected
        or die sprintf
        "invalid content tag: '%s': expected: '%s'"
        , $tag, $tag_expected;

    for my $attribute (@{$attribute_required}) {
        (defined $attribute_hash->{$attribute})
            or die sprintf "missing attribute in %s tag: '%s'"
            , $tag, $attribute;
    }

    my $body = defined $raw_body ? $self->_parse_element($raw_body) : undef;
    my $parse = [ @{$attribute_hash}{@{$attribute_used}}, $body ];

    return $parse;
}

sub _parse_unique_element {
    my ($self, $element_list) = @_;
    my $element;
    $self->each_element(
        $element_list,
        sub {
            defined $element and die 'multiple elements';
            ($element) = @_;
        });
    defined $element or die 'missing element';
    return $element;
}

sub _parse_element {
    my ($self, $element) = @_;
    return $self->is_element_set($element) ? $self->_element_set_parse($element) : $self->parse_string($element);
}

sub _element_set_parse {
    my ($self, $element_list) = @_;
    my $results = [ ];
    $self->each_element(
        $element_list,
        sub {
            my ($element) = @_;
            my $body_item = pop @{$element};
            my $body = defined $body_item ? $self->_parse_element($body_item) : undef;
            push @{$element}, $body;
            push @{$results}, $element;
        });
    return $results;
}

# Default is null-op
sub parse_string {
    my ($self, $string) = @_;
    return $string;
}

1;

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
