
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
    $self->{$_} = $args->{"-$_"} for qw(
        view
        reply
        );
    return;
}

# attributes

sub success {
    my ($self) = @_;
    my $success = $self->{'success'};
    return $success;
}

sub view {
    my ($self) = @_;
    my $view = $self->{'view'};
    return $view;
}

sub reply {
    my ($self) = @_;
    my $reply = $self->{'reply'};
    return $reply;
}

1;

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
