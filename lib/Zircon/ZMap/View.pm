
package Zircon::ZMap::View;

use strict;
use warnings;

sub new {
    my ($pkg, @arg_list) = @_;
    my $new = { };
    bless $new, $pkg;
    $new->_init(@arg_list);
    return $new;
}

sub _init {
    my ($self, $zmap) = @_;
    $self->{'_zmap'} = $zmap;
    return;
}

# attributes

sub zmap {
    my ($self) = @_;
    my $zmap = $self->{'_zmap'};
    return $zmap;
}

1;

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
