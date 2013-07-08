package SelectionHandler;
use strict;
use warnings;

sub new {
    my $self = [];
    bless $self, __PACKAGE__;
    return $self;
}

sub selection_owner_callback {
    my ($self, @arg) = @_;
    push @$self, \@arg;
    return;
}

sub take_callbacks {
    my ($self) = @_;
    my @ret = @$self;
    @$self = ();
    return @ret; # scalar or list context OK
}

1;
