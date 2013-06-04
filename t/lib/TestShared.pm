package TestShared;
use strict;
use warnings;

use base 'Exporter';
our @EXPORT_OK = qw( do_subtests have_display init_zircon_conn );

use Tk;
use Test::More;

use ConnHandler;

=head1 NAME

TestShared - common stuff for Zircon tests

=cut


sub do_subtests {
    my @sub = @_;

    plan tests => scalar @sub;

    foreach my $sub (@sub) {
        subtest $sub => main->can($sub);
    }

    return 0;
}

sub have_display {
    if (!$ENV{DISPLAY}) {
        plan skip_all => 'Cannot test without $DISPLAY';
        die "should have called exit";
    } else {
        return 1;
    }
}

sub init_zircon_conn {
    my ($M, @id) = @_;

    my $name = $0;
    $name =~ s{.*/}{};

    my $context = Zircon::Tk::Context->new(-widget => $M);
    my $handler = ConnHandler->new;
    my $connection = Zircon::Connection->new(-handler => $handler,
                                             -name => $name,
                                             -context => $context);
    $handler->zconn($connection);

    $connection->local_selection_id($id[0]);
    $connection->remote_selection_id($id[1]);

    return $handler;
}

sub Tk::Error {
    my ($widget,$error,@locations) = @_;
    fail("Tk::Error was called");
    diag(join "\n", $error, @locations);
}

1;
