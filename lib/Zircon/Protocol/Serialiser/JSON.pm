
package Zircon::Protocol::Serialiser::JSON;

use strict;
use warnings;

use JSON;

use parent 'Zircon::Protocol::Serialiser';

sub _init {
    my ($self, $arg_hash) = @_;
    $self->_json(JSON->new);
    return $self->SUPER::_init($arg_hash);
}

sub _json {
    my ($self, @args) = @_;
    ($self->{'_json'}) = @args if @args;
    my $_json = $self->{'_json'};
    return $_json;
}

# JSON creation

sub serialise_element {
    my ($self, $tag, $attribute_hash, @content) = @_;
    @content = grep { defined $_ } @content;
    @content = map  { my $ref = ref($_); $ref ? ($ref eq 'ARRAY' ? $self->serialise_element(@$_) : $_) : $_ } @content;
    $attribute_hash //= {};
    my $element = { %$attribute_hash };
    if (@content) {
        if (@content == 1) {
            $element->{_content} = $content[0];
        } else {
            $element->{_content} = \@content;
        }
    }
    return { $tag => $element };
}

sub finalise_element {
    my ($self, $element) = @_;
    return $self->_json->encode($element);
}

# JSON parsing

sub pre_parse {
    my ($self, $json) = @_;
    return $self->_json->decode($json);
}

sub each_element {
    my ($self, $element_list, $callback) = @_;

    unless (ref($element_list) eq 'ARRAY') {
        $element_list = [ $element_list ];
    }
    foreach my $element ( @$element_list ) {

        ref($element) eq 'HASH'      or die 'element is not a hashref';
        scalar(keys(%$element)) == 1 or die 'multiple element keys';

        my ($tag, $attributes) = each %$element;
        my $content = delete $attributes->{_content};

        my $element = [ $tag, $attributes, $content ];
        $callback->($element);
    }
    return;
}

sub is_element_set {
    my ($self, $element) = @_;
    return ref($element);
}

1;

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
