#! /usr/bin/env perl
use strict;
use warnings;

use Test::More;
use Tk;

use Time::HiRes qw( gettimeofday tv_interval );
use IO::Handle;
use Zircon::Tk::Selection;

use lib "t/lib";
use TestShared qw( have_display do_subtests try_err mkwidg );
use SelectionHandler;


sub main {
    have_display();
    do_subtests(qw( clipboard_ops_tt own_timeouts_tt ));
    return 0;
}

main();


sub clipboard_ops_tt {
    plan tests => 10;
    my $M = mkwidg();

    # ensure a steady flow of events, so the timeout mechanism in
    # read_clipboard can work
    my $tick;
    my $tick_fast = $M->repeat(100, sub { $tick = 'fast' });
    my $tick_slow = $M->repeat(750, sub { $tick = 'slow' });

    my ($handler, $sel) = mkselection($M);

    my $want = "content to see that clipboard\ntransfers work OK\n".
      "pid=$$ time=".localtime();
    $sel->content($want);
    $sel->own;
    my $got = do_clipboard(read => $sel, 1);
    is($got, $want, 'simple clipboard read');

    $want = '';
    $sel->content($want);
    $sel->own;
    $got = do_clipboard(read => $sel, 1);
    is($got, $want, 'clipboard is empty string');
    is(scalar $handler->take_callbacks, 0, 'no callbacks');

    $sel->clear;
    $got = do_clipboard(read => $sel, 1);
    like($got, qr{^ERR:.*selection doesn't exist}, 'cleared');
    is(scalar $handler->take_callbacks, 0, 'cleared: no callbacks on us');

    $want = "text supplied by child_clipboard for $$";
    $got = 'no read yet';
    $M->after(1250, sub { $got = try_err { $sel->get } });
    do_clipboard(own => $sel, 2, 1500, $want);
    is($got, $want, 'read from child_clipboard');

    $sel->content('mine again');
    $sel->own;
    $got = do_clipboard(own => $sel, 1, 0, 'junk text');
    is($got, '0', 'child own: it sees no callbacks');
    is(scalar $handler->take_callbacks, 1, 'we saw owner callback');
    # child didn't hang around to serve its clipboard to next reader

    $got = do_clipboard(read => $sel, 1);
    like($got, qr{^ERR:.*selection doesn't exist}, 'clipboard inactive');

    $tick_fast->cancel;

    $want = "TIMEOUT";
    $sel->content("too slow to read it");
    $sel->own;
    Tk::DoOneEvent() while $tick ne 'slow';
    $got = do_clipboard(read => $sel, 0.1);
    is($got, $want, 'clipboard timeout works');

    $tick_slow->cancel;
    $M->destroy;

    return;
}

sub mkselection {
    my ($widg, $handler_class) = @_;

    my $handler = SelectionHandler->new;
    my $sel = Zircon::Tk::Selection->new
      (-name => 'Bob',
       -id => "selection_$$",
       -platform => 'Tk',
       -widget => $widg,
       -handler => $handler);

    return ($handler, $sel);
}

sub own_timeouts_tt {
    plan tests => 5;
    my $M = mkwidg();
    my $tick = $M->repeat(100, sub { });
    my ($handler, $sel) = mkselection($M);

    my @warn;
    my $t0 = [ gettimeofday() ];
    local $SIG{__WARN__} = sub {
        my ($msg) = @_;
        push @warn, $msg;
        printf STDERR "[logged after %.4fs] %s", tv_interval($t0), $msg;
    };

    local $Zircon::Tk::Selection::OWN_SAFETY_TIMEOUT = 0.2e3; # rapid for testing

    $sel->clear;
    $M->after(0, [ \&__hang_around, $M, 0.25e3 ]);
    my $got = try_err { $sel->own };
    is(scalar @warn, 4, "tangled waitVariable - warning count");
    like($warn[0], # 0.0111s
         qr/hang_around: start/, '  tangle');
    like($warn[1], # 0.2005s
         qr/safety timeout.*tangled/, '  safety timeout');
    like($warn[2], # 0.2613s
         qr/hang_around: stop/, '  untangle');
    like($warn[3], # 0.2615s
         qr/waitVariable completed late/, 'exit late');
    @warn = ();

    $tick->cancel;
    $M->destroy;
}


# Generate a waitVariable context on the top of the stack, preventing
# return of any lower down (which I then call "tangled") for $delay
# millisec.
sub __hang_around {
    my ($w, $delay) = @_;
    my $flag = 0;
    my $timer = $w->after($delay, sub { $flag ++ });
    warn sprintf "__hang_around: start(%.3fs)\n", $delay/1E3;
    $w->waitVariable(\$flag);
    warn "__hang_around: stop\n";
    return;
}


# Spawn child process to do (stuff),
# read input without blocking our event loop,
# stop at EOF or timeout
sub do_clipboard {
    my ($op, $sel, $timeout, @arg) = @_;
    my $fh = IO::Handle->new;
    my $pid = open $fh, '-|', child_clipboard($op, $sel->id, @arg);
    die "fork failed: $!" unless defined $pid;
    if (!defined $fh->blocking(0)) {
        die "Failed to set non-blocking IO: $?";
    }

    my $t0 = [ gettimeofday() ];
    my $buf = '';
    my $eof; # $fh->eof is true also for "Resource temporarily unavailable"
    while (tv_interval($t0) < $timeout and not $eof) {
        my $n = $fh->sysread($buf, 1024, length($buf));
        # ->sysread because ->read returns ($n=undef,$!=0) at true eof
        if (defined $n) {
            $eof=1 if 0 == $n;
            # else did read some - wait
        } else {
            if (11 == $!) {
                # Resource temporarily unavailable - wait
            } else {
                $buf .= "READ_ERR:$!:".(0+$!);
                last;
            }
        }
        Tk::DoOneEvent();
    }
    if (!$eof) {
        # timeout
        $buf .= "TIMEOUT";
        kill INT => $pid;
    }
    close $fh;
#    warn "child_clipboard exit rc=$?";

    return $buf;
}

sub child_clipboard {
    my (@arg) = @_;
    return ($^X, -E => <<'CODE', @arg); # perl -E '...'
 use strict;
 use warnings;
 use Tk;
 use Zircon::Tk::Selection;

 use lib 't/lib';
 use TestShared qw( try_err mkwidg );
 use SelectionHandler;

 sub main {
   my ($op, $id, @arg) = @_;
   my $M = mkwidg;
   if ($op eq 'read') {
     my $sel = try_err { $M->SelectionGet(-selection => $id) };
     print $sel;
   } elsif ($op eq 'own') {
     my ($time, $content) = @arg;
     my ($handler, $sel) = mkselection($M, $id);
     $sel->content($content);
     $sel->own;
     # set exit timer after ->own lest we process the exit event too soon
     $M->after($time, sub { $M->destroy });
     MainLoop;
     print scalar $handler->take_callbacks;
   } else {
     print "ERR:op=$op\n";
   }
 }

 main(@ARGV);

 sub mkselection {
   my ($w, $id) = @_;
   my $h = SelectionHandler->new;
   my $sel = Zircon::Tk::Selection->new
     (-name => 'Billy', -id => $id,
      -platform => 'Tk', -widget => $w,
      -handler => $h);
   return ($h, $sel);
 }
CODE
}

1;
