
package Zircon::Result::Timeout;

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
    return;
}

# attributes

1;
