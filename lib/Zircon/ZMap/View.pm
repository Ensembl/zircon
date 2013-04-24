
package Zircon::ZMap::View;

use strict;
use warnings;

use Try::Tiny;
use Scalar::Util qw( weaken );

sub new {
    my ($pkg, %arg_hash) = @_;
    my $new = { };
    bless $new, $pkg;
    $new->_init(\ %arg_hash);
    return $new;
}

sub _init {
    my ($self, $arg_hash) = @_;
    $self->{"_$_"} = $arg_hash->{"-$_"} for qw( zmap handler view_id );
    weaken $self->{'_handler'} if ref $self->{'_handler'};
    return;
}

# attributes

sub zmap {
    my ($self) = @_;
    my $zmap = $self->{'_zmap'};
    return $zmap;
}

sub handler {
    my ($self) = @_;
    my $handler = $self->{'_handler'};
    return $handler;
}

sub view_id {
    my ($self) = @_;
    my $view_id = $self->{'_view_id'};
    return $view_id;
}

# destructor

sub DESTROY {
    my ($self) = @_;
    try { $self->zmap->view_destroyed($self); }
    catch { warn $_; };
}

1;

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
