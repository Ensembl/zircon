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
    do_subtests(qw( clean_exit_tt destroy_tt tied_handles_tt ));
    return 0;
}

main();


sub is_wait {
    my ($want_val, $msg, $code) = @_;

    my ($tries, $got_val);
    for (my $n=0; $n<10; $n++) {
        $got_val = $code->();
        $tries = $n;
        last if $want_val == $got_val;
        usleep 100e3;
    }

    return is($got_val, $want_val, "$msg (tries=$tries)");
}


sub clean_exit_tt {
    plan tests => 5;
    my $M = mkwidg();

    # Check for exit code
    my $we = Zircon::Tk::WindowExists->new;
    my $gone = $M->Frame->pack;
    my $gone_id = $gone->id;
    $gone->update;
    is_wait(1, 'see frame beforehand', sub { $we->query( $gone_id ) });
    $gone->destroy;
    $M->update;
    is_wait(0, 'see absence of gone-frame', sub { $we->query( $gone_id ) });
    my $exit = $we->tidy;
    is(sprintf('0x%X', $exit), '0x100', 'child exit code: Xlib exit');

    # Check for clean exit
    $we = Zircon::Tk::WindowExists->new;
    is($we->query( $M->id ), 1, "see our MainWindow")
      or diag explain { id => $M->id, exists => Tk::Exists($M) };
    close $we->out; # emulate the parent closing
    sleep 1; # bodge delay, giving child time to see EOF
    $exit = $we->tidy; # sends SIGINT to be sure
    is(sprintf('0x%X', $exit), '0x0', 'child exit code: EOF');

    return;
}


sub destroy_tt {
    plan tests => 3;

    my $dut = Zircon::Tk::WindowExists->new; # device under test
    my $M = mkwidg();
    my $winid = $M->id;
    is($dut->query($winid), 1, 'sees our window');

    my $pid = $dut->pid;
    undef $dut;

    undef $!;
    my $count = kill KILL => $pid;
    my $rc = $!;
    is($count, 0, 'pid gone after undef'); # gone = dead + reaped
    is(0+$rc, 3, "pid not killed ($rc)");

    return;
}


sub tied_handles_tt {
    plan tests => 3;
    my $M = mkwidg();
    my $winid = $M->id;

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

    my $dut = Zircon::Tk::WindowExists->new; # device under test
    my $got = try_err { $dut->query($winid) };
    is($got, 1, 'child process sees our window');

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
