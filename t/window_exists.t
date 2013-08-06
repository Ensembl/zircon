#! /usr/bin/env perl
use strict;
use warnings;

use lib "t/lib";
use TestShared qw( have_display do_subtests mkwidg try_err );

use Test::More;
use Try::Tiny;
use Time::HiRes qw( usleep );
use Tk;

use Zircon::Tk::WindowExists;


sub main {
    have_display();
    do_subtests(qw( here_and_gone_tt tied_handles_tt ));
    return 0;
}

main();


sub is_wait {
    my ($want_val, $msg, $code) = @_;

    my ($tries, $got_val);
    for (my $n=0; $n<10; $n++) {
        $got_val = $code->();
        $tries = $n;
        last if $want_val eq $got_val;
        usleep 100e3;
    }

    return is($got_val, $want_val, "$msg (tries=$tries)");
}


sub here_and_gone_tt {
    plan tests => 2;
    my $M = mkwidg();

    # Check for exit code
    my $we = 'Zircon::Tk::WindowExists';
    my $gone = $M->Frame->pack;
    my $gone_id = $gone->id;
    $gone->property(qw( set win_exist STRING 8 value ));
    my $q = sub { $we->query($gone_id, 'win_exist') };
    $gone->update;
    is_wait('value', 'see frame beforehand', $q);
    $gone->destroy;
    $M->update;
    is_wait(0, 'see absence of gone-frame', $q);

    return;
}


sub tied_handles_tt {
    plan tests => 3;
    my $M = mkwidg();
    my $winid = $M->id;
    $M->property(qw( set tied_exist STRING 8 knot ));
    $M->update;

    # Need to emulate Bio::Otter::LogFile and Bio::Otter::Log::TieHandle
    # without upsetting how prove gets its results
    my $tied_err = tie *STDERR, 'KnottyFh', 'warns', 'arg0'
      or die "tie failed ($!)";
    warn "DATA: second line\n";

    is_deeply([ $tied_err->take_content ],
              [ 'DATA: first: arg0', "DATA: second line\n" ],
              'tied_err is KnottyFh');

    # B:O:LogFile ties STDOUT, STDERR.  We don't want to mess with
    # STDOUT.  The child process doesn't touch STDERR, hence...
    my $tied_in = tie *STDIN, 'KnottyFh', 'in'
      or die "tie failed ($!)";

    my $dut = 'Zircon::Tk::WindowExists'; # device under test
    my $got = try_err { $dut->query($winid, 'tied_exist') };
    is($got, 'knot', 'child process sees our window');

    my $w2 = $M->Label(-text => 'talk to XServer now')->pack;
    $M->update;
    like($w2->id, qr{^0x}, 'can still talk to XServer');

    return;
}


package KnottyFh;

sub TIEHANDLE {
    my ($class, $name, @arg) = @_;
    my $self = { name => $name, printed => [] };
    bless $self, $class;
    $self->PRINTF('DATA: first: %s', $arg[0]) if @arg;
    return $self;
}

sub PRINT {
    my ($self, @rest) = @_;
    push @{ $self->{printed} }, "@rest";

    if ($rest[0] =~ /^DATA:/) {
        # muffle the reassurance data
    } else {
        # pass-through any real warnings, for debugging
        my $msg = "@rest";
        chomp $msg;
        print STDOUT "#KFH# [w] $msg\n";
    }
    return;
}

sub PRINTF {
    my ($self, $fmt, @rest) = @_;
    return $self->PRINT(sprintf($fmt, @rest));
}

sub take_content {
    my ($self) = @_;
    return splice @{ $self->{printed} };
}

sub UNTIE {
    my ($self) = @_;

    $self->{dead} = 1; # unused, just symbolic

    # Without this method, we can get warnings
    #
    #    untie attempted while 1 inner references still exist at /nfs/users/nfs_m/mca/gitwk-anacode/zircon/lib/Zircon/Tk/WindowExists.pm line 79.
    #
    # http://www.perlmonks.org/?node_id=562150
    return;
}
