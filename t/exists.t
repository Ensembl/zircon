#! /usr/bin/env perl
use strict;
use warnings;

use lib "t/lib";
use TestShared qw( have_display init_zircon_conn do_subtests );

use Test::More;
use Try::Tiny;
use Tk;

use Zircon::Tk::Context;
use Zircon::Connection;


sub main {
    have_display();
    do_subtests(qw( predestroy_tt postdestroy_tt waitdestroy_tt owndestroy_tt extwindow_tt ));
    return 0;
}

main();

sub try_err(&) {
    my ($code) = @_;
    return try { goto &$code } catch {"ERR:$_"};
}


sub mkwidg {
    my $M = MainWindow->new;
    my $make_it_live = $M->id;

    # for quieter tests,
    # but also under prove(1) without -v prevents some failures(?)
    $M->withdraw;

    return $M;
}

sub predestroy_tt {
    plan tests => 1;

    # make a window which is already destroyed
    my $M = mkwidg();
    $M->destroy;

    # Zircon can't use it
    my $got = try_err { init_zircon_conn($M, qw( me_local me_remote )) };

    like($got, qr{^ERR:Attempt to construct with invalid widget},
         "Z:T:Context->new with destroyed widget");

    return;
}


sub want_re {
    my ($what) = @_;
    return qr{^ERR:Attempt to .*$what.* with destroyed widget at };
}

sub postdestroy_tt {
    plan tests => 8;

    my $M = mkwidg();
    my $handler = try_err { init_zircon_conn($M, qw( me_local me_remote )) };
    is(ref($handler), 'ConnHandler', 'postdestroy_tt: init');
    my $sel = $handler->zconn->selection('local');

    $M->destroy;

    # Z:Connection
    my $do_fail = sub { fail('timeout happened') };
    my $got = try_err { $handler->zconn->timeout(100, $do_fail) };
    like($got, want_re('timeout'), 'timeout after destroy');

    $got = try_err { $handler->zconn->send('message'); 'done' };
    like($got, want_re('clear|own'), 'send after destroy');

    # Z:T:Selection
    $got = try_err { $sel->get(); };
    like($got, want_re('get'), 'get after destroy');

    my $old_own = $sel->owns;
    $got = try_err { $sel->owns(0); $sel->own(); };
    like($got, want_re('own'), 'own after destroy');
    $sel->owns($old_own);

    # Z:T:Context
    my $boom = 0;
    local $SIG{ALRM} = sub { $boom=1 };
    alarm(2);
    $got = try_err { $handler->zconn->context->waitVariable(\$boom); "boom=$boom" };
    alarm(0);
    like($got, want_re('waitVariable'), 'waitVariable after destroy');

    $got = try_err { $handler->zconn->context->window_exists(1234) };
    like($got, want_re('check window_exists'), 'window_exists after destroy');

    $got = try_err { $handler->zconn->reset; 'done' };
    is($got, 'done', 'reset should still work');

    return;
}


sub waitdestroy_tt {
    plan tests => 4;

    my $M = mkwidg();
    my $handler = try_err { init_zircon_conn($M, qw( me_local me_remote )) };
    is(ref($handler), 'ConnHandler', 'waitdestroy_tt: init');

    my ($flag, @warn) = (0);
    local $SIG{ALRM} = sub { $flag='boom' };
    local $SIG{__WARN__} = sub { push @warn, "@_" };
    $M->after(50, sub {
                  $M->destroy; # yes, while we're threaded in an event for it
                  $flag = 1;
              });
    alarm(2);
    my $got = try_err { $handler->zconn->context->waitVariable(\$flag); "flag=$flag" };
    alarm(0);
    is($got, 'flag=1', 'waitVariable with destruction during');
    is(scalar @warn, 1, 'produces warning');
    like($warn[0], qr{destroyed during waitVariable.*main::main}s,
         'is the expected long cluck');

    return;
}


sub owndestroy_tt {
    plan tests => 4;
    my $M = mkwidg();
    my $handler = init_zircon_conn($M, qw( me_local me_remote ));

    my $sel = $handler->zconn->selection('local');
    bless $sel, 'Selection::Footshooting'; # rebless

    my ($flag, @warn) = (0);
    local $SIG{ALRM} = sub {
        $flag='boom';
    };

    alarm(2);
    my $got = try_err {
        local $SIG{__WARN__} = # in scope above, this causes Tk.so segfault!?
          sub { push @warn, "@_" };
        $sel->owns(0);
        $sel->own();
        "flag=$flag";
    };
    alarm(0);
    ok(!Tk::Exists($M), 'window was destroyed');

    like($got, qr{destroyed during waitVariable at}, 'own with destruction during');
    is(scalar @warn, 1, 'produces warnings')
      or diag explain \@warn;
    like($warn[0], qr{PropertyNotify on destroyed}, 'ordering of destory');

    return;
}


sub extwindow_tt {
    plan tests => 3;
    my $M = mkwidg();
    my $handler = init_zircon_conn($M, qw( me_local me_remote ));

    my $pid = open my $fh, '-|', qw( perl -MTk -E ), <<'CHILD';
  my $M = MainWindow->new(-title => "Child for extwindow_tt");
#  $M->withdraw;
  my $w = $M->Label(-text => "foo");
  print "made ", $w->id,  ": ", $M->id, "\n";
  MainLoop;
CHILD

    my $info = <$fh>;
    like($info, qr{0x\w+}, 'child process told us of window');
    my ($extid) = $info =~ m{(0x\w+)};

diag explain { pid => $pid, info => $info, extid => $extid };

    my $got = try_err { $handler->zconn->context->window_exists($extid) };
    is($got, 1, 'we see child process window');
    kill 'INT', $pid
      or warn "kill child failed: $!";

    $got = try_err { $handler->zconn->context->window_exists($extid) };
    is($got, 0, 'we see child process window is gone');

    return;
}

package Selection::Footshooting;
use strict;
use warnings;

use base 'Zircon::Tk::Selection';

sub widget {
    my ($self, @arg) = @_;
    my $w = $self->SUPER::widget;
    my $caller = (caller(1))[3];
    if ($caller =~ m{_own_timestamped$} && Tk::Exists($w)) {
        $self->widget->destroy;
    }
    return $w;
}
