
package Zircon::XML;

use strict;
use warnings;

# XML creation

sub request_xml {
    my ($self, $command, $view, $request) = @_;
    my $request_body_xml =
        defined $request ? _element_xml(@{$request}) : undef;
    my $request_element_xml = _element_xml(
        'request', {
            'command' => $command,
            'view'    => $view,
        }, $request_body_xml);
    my $app_id = $self->app_id;
    my $clipboard_id = $self->selection_id;
    my $request_id = $self->{'request_id'}++;
    my $zmap_element_xml = _element_xml(
        'zmap', {
            'version'      => '2.0',
            'type'         => 'request',
            'app_id'       => $app_id,
            'clipboard_id' => $clipboard_id,
            'request_id'   => $request_id,
        }, $request_element_xml);
    return $zmap_element_xml;
}

sub reply_xml {
    my ($self, $request_id, $command, $reply) = @_;
    my ($status, $reply_body) = @{$reply};
    my ($return_code, $reason) =
        defined $status ? @{$status} : ( 'ok' );
    my $reply_body_xml = _element_xml(@{$reply_body});
    my $reply_element_xml = _element_xml(
        'reply', {
            'command'     => $command,
            'return_code' => $return_code,
            'reason'      => $reason,
        }, $reply_body_xml);
    my $app_id = $self->app_id;
    my $clipboard_id = $self->selection_id;
    my $zmap_element_xml = _element_xml(
        'zmap', {
            'version'      => '2.0',
            'type'         => 'reply',
            'app_id'       => $app_id,
            'clipboard_id' => $clipboard_id,
            'request_id'   => $request_id,
        }, $reply_element_xml);
    return $zmap_element_xml;
}

sub _element_xml {
    my ($tag, $attribute_hash, $content_xml) = @_;
    my $tag_xml = join ' ', $tag, map {
        _attribute_xml($_, $attribute_hash->{$_});
    } keys %{$attribute_hash};
    return defined $content_xml
        ? sprintf "<%s>\n%s\n</%s>", $tag_xml, $content_xml, $tag
        : sprintf "<%s />", $tag_xml;
}

sub _attribute_xml {
    my ($key, $value) = @_;
    defined $value or return;
    $value =~ s/&/&amp;/g;
    $value =~ s/"/&quot;/g;
    $value =~ s/</&lt;/g;
    $value =~ s/>/&gt;/g;
    return sprintf '%s="%s"', $key, $value;
}

# XML parsing

sub request_xml_parse {
    my ($self, $request_xml) = @_;

    my $protocol_tag_expected = 'zmap';
    my ($protocol_tag,
        $protocol_attribute_hash,
        $content_xml,
        ) = @{ _unique_element($request_xml) };
    $protocol_tag eq $protocol_tag_expected
        or die sprintf
        "invalid protocol tag: '%s': expected: '%s'"
        , $protocol_tag, $protocol_tag_expected;

    my $request_id = $protocol_attribute_hash->{'request_id'};
    defined $request_id
        or die "missing protocol attribute: 'request_id'";

    my $content_tag_expected = 'request';
    my ($content_tag,
        $content_attribute_hash,
        $body_xml,
        ) = @{ _unique_element($content_xml) };
    $content_tag eq $content_tag_expected
        or die sprintf
        "invalid content tag: '%s': expected: '%s'"
        , $content_tag, $content_tag_expected;

    my $request =
        defined $body_xml ? _unique_element($body_xml) : undef;

    my $command =
        $content_attribute_hash->{'command'};
    defined $command
        or die "missing request attribute: 'command'";

    my $view =
        $content_attribute_hash->{'view'};

    my $parse = [ $request_id, $command, $view, $request ];

    return $parse;
}

sub reply_xml_parse {
    my ($self, $reply_xml) = @_;

    my $protocol_tag_expected = 'zmap';
    my ($protocol_tag,
        $protocol_attribute_hash,
        $content_xml,
        ) = @{ _unique_element($reply_xml) };
    $protocol_tag eq $protocol_tag_expected
        or die sprintf
        "invalid protocol tag: '%s': expected: '%s'"
        , $protocol_tag, $protocol_tag_expected;

    my $request_id = $protocol_attribute_hash->{'request_id'};
    defined $request_id
        or die "missing protocol attribute: 'request_id'";

    my $content_tag_expected = 'reply';
    my ($content_tag,
        $content_attribute_hash,
        $body_xml,
        ) = @{ _unique_element($content_xml) };
    $content_tag eq $content_tag_expected
        or die sprintf
        "invalid content tag: '%s': expected: '%s'"
        , $content_tag, $content_tag_expected;

    my $reply =
        defined $body_xml ? _unique_element($body_xml) : undef;

    for (qw( command return_code )) {
        my $attribute = $content_attribute_hash->{$_};
        defined $attribute
            or die sprintf
            "missing reply attribute: '%s'"
            , $attribute;
    }
    my ($command, $return_code, $reason) =
        @{$content_attribute_hash}{qw(
            command return_code reason)};

    my $view =
        $content_attribute_hash->{'view'};

    my $parse = [
        $request_id,
        $command, $return_code, $reason,
        $view, $reply ];

    return $parse;
}

sub _unique_element {
    my ($element_xml) = @_;
    my $element;
    _each_element(
        $element_xml,
        sub {
            defined $element and die 'multiple elements';
            ($element) = @_;
        });
    defined $element or die 'missing element';
    return $element;
}

my $element_list_xml_pattern = qr!
    \G
    (?:[[:space:]]*)                                        # leading space
    (?: # alternative #1 - element 
        < [[:space:]]* ([[:alpha:]]+)                       # begin open tag
        ((?:[[:space:]]*[[:alpha:]_]+="[^"]*")*)            # attributes
        [[:space:]]*
        (?:
            / [[:space:]]* >                                # end empty tag
        |
            >                                               # end open tag
            (.*)                                            # element body
            < [[:space:]]* / [[:space:]]* \1 [[:space:]]* > # close tag
        )
    |   # alternative #2 - garbage
        (.*)\z
    )
    !xms;

my $attributes_xml_pattern = qr!
    ([[:alpha:]_]+)="([^"]*)"
    !xms;

sub _each_element {
    my ($element_list_xml, $callback) = @_;
    while ( $element_list_xml =~ /$element_list_xml_pattern/gc ) {
        my ($tag, $attributes_xml, $body_xml, $garbage) =
            ($1, $2, $3, $4);
        if ( defined $garbage ) {
            return if $garbage eq '';
            die 'trailing garbage';
        }
        my $attributes = {
            $attributes_xml =~ /$attributes_xml_pattern/g,
        };
        my $element = [ $tag, $attributes, $body_xml ];
        $callback->($element);
    }
    return;
}

1;
