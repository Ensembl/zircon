package TestShared;
use strict;
use warnings;

use base 'Exporter';
our @EXPORT_OK = qw( do_subtests have_display init_zircon_conn mkwidg endpoint_pair );

use Tk;
use Test::More;
use Try::Tiny;

use ConnHandler;

=head1 NAME

TestShared - common stuff for Zircon tests

=head1 AUTHOR

Matthew Astley mca@sanger.ac.uk

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

    my $context = Zircon::TkZMQ::Context->new(-widget => $M);
    my $handler = ConnHandler->new;
    my $connection = Zircon::Connection->new(-handler => $handler,
                                             -name => $name,
                                             -context => $context,
                                             -local_endpoint => $id[0],
        );
    $handler->zconn($connection);

    $connection->remote_endpoint($id[1]);

    return $handler;
}


sub mkwidg {
    my @mw_arg = @_;
    my $M = MainWindow->new(@mw_arg);
    my $make_it_live = $M->id;

    # for quieter tests,
    #
    # but also under prove(1) without -v prevents some failures(?)
    # in t/exists.t owndestroy_tt
    $M->withdraw;

    # necessary for window to be seen promply by Zircon::Tk::WindowExists ..?
    $M->idletasks;

    return $M;
}

{
    my $_port = 55667; # FIXME: dangerous to choose fixed ports

    sub endpoint_pair {
        my $base = 'tcp://127.0.0.1:';
        return ( $base . $_port++, $base . $_port++ );
    }
}

sub Tk::Error {
    my ($widget,$error,@locations) = @_;
    fail("Tk::Error was called");
    diag(join "\n", $error, @locations);
    return ();
}

1;
