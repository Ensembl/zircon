package Zircon::Tk::MonkeyPatches;
use strict;
use warnings;

require Tk;
require Tk::Widget;

use Sub::Name;

=head1 NAME

Zircon::Tk::MonkeyPatches - tweak some Tk methods

=head1 DESCRIPTION

Requiring this module will ensure that L<Tk/DoOneEvent> and
L<Tk::Widget/update> methods are visible in stack traces.

This is done for the benefit for L<Zircon::Tk::Context/stack_tangle>.

=cut

sub patch {
    my ($namespace, $method) = @_;
    my $subname = "$namespace\::$method";
    my $old = $namespace->can($method)
      or die "Cannot patch $subname - not found";
    my $new = sub {
        return $old->(@_);
    };
    subname $method, $new;
    no strict 'refs';
    no warnings 'redefine';
    *$subname = $new;
    return;
}

patch(qw( Tk DoOneEvent ));
patch(qw( Tk::Widget update ));

1;
