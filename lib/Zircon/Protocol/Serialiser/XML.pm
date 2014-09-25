
package Zircon::Protocol::Serialiser::XML;

use strict;
use warnings;

use feature qw( switch );

use parent 'Zircon::Protocol::Serialiser';

# XML creation

sub serialise_element {
    my ($self, $tag, $attribute_hash, @content_xml) = @_;
    my $tag_xml = join ' ', $tag, map {
        _attribute_xml($_, $attribute_hash->{$_});
    } sort keys %{$attribute_hash};
    @content_xml = grep { defined $_ } @content_xml;
    my $content_xml = join "\n",
      map { ref($_) ? $self->serialise_element(@$_) : $_ } @content_xml;
    return @content_xml
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

sub is_element_set {
    my ($self, $xml) = @_;
    return $xml =~ /[<>]/;
}

sub parse_string {
    my ($self, $xml) = @_;
    local $_ = $xml;
    _xml_unescape();
    s/^\s+|\s+$//sg;
    return $_;
}

my $element_list_xml_pattern = qr!
    \G
    (?:[[:space:]]*)                                        # leading space
    (?: # alternative #1 - element 
        < [[:space:]]* ([[:alpha:]_]+)                      # begin open tag
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

# this *is* used in _xml_unescape but perlcritic cannot see code in s///e
sub _xml_entity { ## no critic(Subroutines::ProhibitUnusedPrivateSubroutines)
    my ($name) = @_;
    for ($name) {
        when ('lt')   { return '<'; }
        when ('gt')   { return '>'; }
        when ('quot') { return '"'; }
        when ('apos') { return "'"; }
        when ('amp')  { return '&'; }
    }
    die sprintf "unknown XML entity: '%s'", $name;
}

sub _xml_unescape {
    s/&#([[:digit:]]+);/chr $1/eg;
    s/&([[:alpha:]]+);/_xml_entity $1/eg;
    return;
}

sub each_element {
    my ($self, $element_list_xml, $callback) = @_;
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
        _xml_unescape for values %{$attributes};
        my $element = [ $tag, $attributes, $body_xml ];
        $callback->($element);
    }
    return;
}

1;

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
