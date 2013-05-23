package TestShared;
use strict;
use warnings;

use base 'Exporter';
our @EXPORT_OK = qw( have_display );

use Tk;
use Test::More;

=head1 NAME

TestShared - common stuff for Zircon tests

=cut


sub have_display {
    if (!$ENV{DISPLAY}) {
        plan skip_all => 'Cannot test without $DISPLAY';
        die "should have called exit";
    } else {
        return 1;
    }
}

sub Tk::Error {
    my ($widget,$error,@locations) = @_;
    fail("Tk::Error was called");
    diag(join "\n", $error, @locations);
}

1;
