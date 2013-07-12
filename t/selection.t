#! /usr/bin/env perl
use strict;
use warnings;

use Test::More;
use Tk;

use Time::HiRes qw( gettimeofday tv_interval );
use IO::Handle;
use Zircon::Tk::Selection;
use Zircon::Tk::Context;
use Sub::Name;

use lib "t/lib";
use TestShared qw( have_display do_subtests try_err mkwidg );
use SelectionHandler;


our %tk_ln; # used in tangle_spotting_tt

sub main {
    have_display();
    do_subtests(qw( clipboard_ops_tt own_timeouts_tt own_recurse_tt tangle_spotting_tt stack_bottom_level_tt ));
    return 0;
}


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

sub __warn_handler {
    my ($t0_ref, $warns_ref) = @_;
    return sub {
        my ($msg) = @_;
        if ($msg =~ m{^selection: Bob: }) {
            # trace - not part of the test
        } else {
            push @$warns_ref, $msg;
        }
        printf STDERR "[logged after %.4fs] %s", tv_interval($$t0_ref), $msg
          if $ENV{ZIRCON_SELECTION_TRACE} || $ENV{TEST_NOISE};
    };
}

sub own_timeouts_tt {
    plan tests => 13;
    my $M = mkwidg();
    my $tick = $M->repeat(100, sub { });
    my ($handler, $sel) = mkselection($M);

    my @warn;
    my $t0 = [ gettimeofday() ];
    local $SIG{__WARN__} = __warn_handler(\$t0, \@warn);

    $sel->clear;
    $M->after(0, [ \&__hang_around, $M, 0.25e3 ]);
    my $got = try_err {
        local $Zircon::Tk::Selection::OWN_SAFETY_TIMEOUT = 0.2e3;
        $sel->own;
        'done_own';
    };
    is($got, 'done_own', 'own, in tangled waitVariable');
    is(scalar @warn, 4, '  warning count');
    like($warn[0], # 0.0111s
         qr/hang_around: start/, '  tangle');
    like($warn[1], # 0.2005s
         qr/safety timeout.*tangled/, '  safety timeout');
    like($warn[2], # 0.2613s
         qr/hang_around: stop/, '  untangle');
    like($warn[3], # 0.2615s
         qr/waitVariable completed late/, 'exit late');
    ok($sel->owns, '  expects to be owned');
    my $want = "clipboard content chosen later; $sel";
    $sel->content($want);
    $got = do_clipboard(read => $sel, 1);
    is($got, $want, '  transfers OK');

    @warn = ();
    $t0 = [ gettimeofday() ];

    $sel->clear;
    $got = try_err {
        local $Zircon::Tk::Selection::OWN_SAFETY_TIMEOUT = 0;
        $sel->content('should not be seen');
        $sel->own;
        # SelectionOwn should not happen, because safety timeout is first
    };
    like($got, qr{^ERR:Failed to Own .* _own_var=timeout},
         'no SelectionOwn after insta-safety');
    ok(!$sel->owns, '  does not expect to be owned');
    is(scalar @warn, 1, '  warn count');
    like($warn[0], qr{_own_provoke.*: safety timeout!}, '  timeout noted');

    # ...that PropertyNotify is still in the pipeline...

#     Some idempotence or efficiency in the XServer, Xlib or Tk
#     dispatcher already prevents _own_timestamped being called twice.
#     Cannot test the 'too late!' clause.

#    # Cause another tangle, to extend _own_provoke's waitVariable
#    $M->after(0, [ \&__hang_around, $M, 0.25e3 ]);
#
#    $got = try_err {
#        local $Zircon::Tk::Selection::OWN_SAFETY_TIMEOUT = 0.2e3;
#        $sel->own; # two PropertyNotify delivered
#    };
#    ok($sel->owns, '  expects to be owned');

    $got = do_clipboard(read => $sel, 1);
    like($got, qr{^ERR:.*selection doesn't exist}, '  no selection');

    $tick->cancel;
    $M->destroy;
    return;
}


# Generate a waitVariable context on the top of the stack, preventing
# return of any lower down (which I then call "tangled") for $delay
# millisec.
$tk_ln{__hang_around} = __LINE__ + 7;
sub __hang_around {
    my ($w, $delay, $quiet) = @_;
    my $flag = 0;
    my $timer = $w->after($delay, sub { $flag ++ });
    warn sprintf "__hang_around: start(%.3fs)\n", $delay/1E3
      unless $quiet;
    $w->waitVariable(\$flag);
    warn "__hang_around: stop\n"
      unless $quiet;
    return;
}


sub own_recurse_tt {
    plan tests => 8;
    my $M = mkwidg();
    my $tick = $M->repeat(100, sub { });
    my ($handler, $sel) = mkselection($M);

    my @warn;
    my $t0 = [ gettimeofday() ];
    local $SIG{__WARN__} = __warn_handler(\$t0, \@warn);

    my %when =
      (before => [ 0.15e3, # re-own before safety timeout
                   qr{
 ^
 !own\s       # outer
 !clear\s     # inner
 ERR:recursive.*_own_var=complete[^!]+ # own failure + stacktrace
 !done_inner\s
 !own_outer   # success there
 \z
                 }x ],


       after => [ 0.25e3, # re-own after safety timeout
                  qr{
 ^
 !own\s       # outer
 !clear\s     # inner
 ERR:recursive.*_own_var=overdue[^!]+ # own failure + stacktrace
 !done_inner\s
 !own_outer   # success there
 \z
                }x ],

      );

    foreach my $when (sort keys %when) {
        my ($delay, $regex) = @{ $when{$when} };

        @warn = ();
        $t0 = [ gettimeofday() ];

        my @got;
        $sel->clear;
        $M->after(0, [ \&__hang_around, $M, 0.3e3 ]);

        local *Tk::SelectionOwn = sub {
            push @got, '!own';
        }; # redefinition warning is eaten by @warn

        my $again = sub {
            $sel->clear;
            push @got, '!clear';
            push @got, try_err { $sel->own; '!own_again' };
            push @got, '!done_inner';
        };

        $M->after($delay, $again);

        push @got, try_err {
            local $Zircon::Tk::Selection::OWN_SAFETY_TIMEOUT = 0.2e3;
            $sel->own;
            '!own_outer';
        };

        like("@got", $regex, "$when: own again after ${delay}ms");

        like("@warn", qr{SelectionOwn.*failed, owner=external; collision\?}, '  we were warned');
        like("@warn", qr{safety timeout due to tangled waitVariable}, '  and for why');

        local $TODO = 're-entrancy - does this need fixing?';
        my $want = "clipboard content chosen later; $sel/$when";
        $sel->content($want);
        my $got = do_clipboard(read => $sel, 1);
        chomp $got;
        is($got, $want, '  transfers OK');
    }

    $tick->cancel;
    $M->destroy;
    return;
}


sub tangle_spotting_tt {
    plan tests => 14;
    is(Tk::MainWindow->Count, 0, 'other subtests not leaving windows around')
      or return;

    my $M = mkwidg();
    my $lbl = $M->Label(-text => 'junk')->pack;


    is(scalar Zircon::Tk::Context->stack_tangle,
       0, 'initially no tangles');


    my @wait;
    my $fill_wait = sub { @wait = Zircon::Tk::Context->stack_tangle };
    subname '$fill_wait', $fill_wait;

    my $fn = __FILE__;
    $M->after(0, $fill_wait);
    my $ln_update = __LINE__; $M->update;
    is(scalar @wait, 1, 'event handler ran (single update)');
    like($wait[0],
         qr{^update from main::tangle_spotting_tt at \Q$fn\E line $ln_update\z},
         '  update shows with trace line');

    $M->afterIdle($fill_wait);
    $ln_update = __LINE__; $M->idletasks;
    is(scalar @wait, 1, 'event handler ran (single idletasks)');
    like($wait[0],
         qr{^update via Tk::idletasks from main::tangle_spotting_tt at \Q$fn\E line $ln_update\z},
         '  idletasks shows with trace line');


    my $stop;
    @wait = ('junk');
    my $ln_finisher = __LINE__ + 3;
    my $finisher = sub {
        $M->afterIdle( $fill_wait);
        $M->idletasks;
        $stop ++; # liberates __wait_for_stop
        $M->destroy; # liberates waitWindow & MainLoop
    };
    subname '$finisher', $finisher;

    # Set up a big stack of assorted event loops
    $M->after(500, # nb. __hang_around needs an $M->after to escape
              $finisher);
    $M->after(  0, [ \&__my_waiter, $M, 100 ]);
    $M->after( 50, [ \&__hang_around, $M, 150, 'q' ]);
    $M->after(100, [ \&__wait_for_stop, $M, \$stop ]);
    $M->after(150, [ \&__wait_window, $lbl ]);
    my $ln_mainloop = __LINE__; Tk::MainLoop;
    isnt($wait[0], 'junk', 'event stack is done');

    # Check the expected nesting of event handlers is seen
    my @wait_like =
      (qr{^update via Tk::idletasks from main::\$finisher at \Q$fn\E line $ln_finisher\z},
       qr{^waitWindow from main::__wait_window .* line $tk_ln{__wait_window}$},
       qr{^waitVariable from main::__wait_for_stop .* line $tk_ln{__wait_for_stop}$},
       qr{^waitVariable from main::__hang_around .* line $tk_ln{__hang_around}$},
       qr{^DoOneEvent from main::__my_waiter .* line $tk_ln{__my_waiter}$},
       qr{^DoOneEvent via Tk::MainLoop from main::tangle_spotting_tt .* line $ln_mainloop$});
    my $ok = 1;
    is(scalar @wait, scalar @wait_like, 'event loop contexts spotted') or $ok=0;
    for (my $i=0; $i<@wait_like; $i++) {
        next unless defined $wait[$i];
        like($wait[$i], $wait_like[$i], "  $wait_like[$i]") or $ok=0;
    }
    diag explain \@wait unless $ok;
    return;
}

$tk_ln{__wait_window} = __LINE__ + 3;
sub __wait_window {
    my ($widget) = @_;
    $widget->waitWindow;
    return;
}

$tk_ln{__wait_for_stop} = __LINE__ + 3;
sub __wait_for_stop {
    my ($widget, $stopref) = @_;
    $widget->waitVariable($stopref);
    return;
}

$tk_ln{__my_waiter} = __LINE__ + 6;
sub __my_waiter { # differs from __hang_around by processing the events here
    my ($widget, $delay) = @_;
    my $t0 = [ gettimeofday() ];
    my $ticker = $widget->after(10, sub {}); # event stream for prompt exit
    while (tv_interval($t0) < $delay/1000) {
        Tk::DoOneEvent;
    }
    $ticker->cancel;
    return;
}


{
    # This needs to run in the script-body context, not a sub.
    # Test the results later with the enclosed subtest.
    my @wait;
    my $M = mkwidg();
    $M->after(0, sub { @wait = Zircon::Tk::Context->stack_tangle });
    my $ln_update = __LINE__; $M->update;

    $M->after(0, sub {
                  push @wait, Zircon::Tk::Context->stack_tangle;
                  $M->destroy;
              });
    my $ln_mainloop = __LINE__; Tk::MainLoop;

    sub stack_bottom_level_tt {
        plan tests => 3;
        # Check the corner-case at the bottom of the stack, which most
        # normal scripts will provoke.
        my $fn = __FILE__;
        is(scalar @wait, 2, 'wait filled');
        like($wait[0],
             qr{^update from \(script\) at \Q$fn\E line $ln_update$},
             '  bottom level of stack visible');
        like($wait[1],
             qr{^DoOneEvent via Tk::MainLoop from \(script\) at \Q$fn\E line $ln_mainloop$},
             '  bottom level of stack visible with via');
        return;
    }
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


main(); # at the bottom so %tk_ln is filled

1;
