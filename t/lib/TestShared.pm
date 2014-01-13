package TestShared;
use strict;
use warnings;

use base 'Exporter';
our @EXPORT_OK = qw( do_subtests have_display init_zircon_conn try_err mkwidg );

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
                                             -context => $context);
    $handler->zconn($connection);

    $connection->local_endpoint($id[0]);
    $connection->remote_endpoint($id[1]);

    return $handler;
}


sub try_err(&) {
    my ($code) = @_;
    return try { goto &$code } catch {"ERR:$_"};
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


sub Tk::Error {
    my ($widget,$error,@locations) = @_;
    fail("Tk::Error was called");
    diag(join "\n", $error, @locations);
    return ();
}

1;
