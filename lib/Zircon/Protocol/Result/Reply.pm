
package Zircon::Protocol::Result::Reply;

use strict;
use warnings;

sub new {
    my ($pkg, %args) = @_;
    my $new = { };
    bless $new, $pkg;
    $new->init(\%args);
    return $new;
}

sub init {
    my ($self, $args) = @_;
    my $success = $args->{'-success'} ? 1 : 0;
    $self->{'success'} = $success;
    return;
}

# attributes

sub success {
    my ($self) = @_;
    my $success = $self->{'success'};
    return $success;
}

1;

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
