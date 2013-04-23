#! /usr/bin/env perl
use strict;
use warnings;

use Test::More;
use Tk;

use Zircon::Tk::Context;
use Zircon::Connection;


sub main {
    if (!$ENV{DISPLAY}) {
        plan skip_all => 'Cannot test without $DISPLAY';
    } else {
        plan tests => 7;
        my $handler = do_init();
        # hold the ref to prevent garbage collection
        MainLoop();
    }
    return 0;
}

sub do_init {
    my $M = TestWin->new;

    my @id = qw( timestamp_serv timestamp_cli );
    $M->clip_ids(@id);
#    $M->after(5000, sub { fail("whole-test timeout"); $M->destroy });

    my $context = Zircon::Tk::Context->new(-widget => $M);
    my $handler = ConnHandler->new;
    my $connection = Zircon::Connection->new(-handler => $handler,
                                             -name => 'timestamp.t',
                                             -context => $context);
    $handler->zconn($connection);
    $M->state_bump('new');

    $connection->local_selection_id($id[0]);
    $connection->remote_selection_id($id[1]);

    return $handler;
}

sub Tk::Error {
    my ($widget,$error,@locations) = @_;
    fail("Tk::Error was called");
    diag(join "\n", $error, @locations);
}

main();



package TestWin;
use IO::Handle;
use Test::More;
use base qw( Tk::Derived Tk::MainWindow );
Tk::Widget->Construct('TestWin');

sub Populate {
    my ($self, @arg) = @_;
    $self->SUPER::Populate(@arg);

    $self->{want_states} = [qw[ new started instructed requested replied reaped finishing ]];

    $self->title("$0 pid=$$");
    my $S = $self->Button(-command => [ $self, 'start' ], -text => 'start')->pack;
    my $I = $self->Button(-command => [ $self, 'instruct' ], -text => 'instruct')->pack;

#    $self->iconify;
#    $self->afterIdle(sub { $S->invoke });

### event data not available via -command and ->invoke ?
#  map {( $_ => Tk::Ev($_) )} qw[ T t E # ]
#  use YAML 'Dump'; warn Dump({ info => \%info });

    $self->bind('<Destroy>' => [ $self, 'being_destroyed', Tk::Ev('W') ]);

    return ();
}

sub clip_ids {
    my ($self, @arg) = @_;
    $self->{clip_id} = \@arg # [ ours, theirs ]
      if @arg;
    return @{ $self->{clip_id} };
}

sub start {
    my ($self, %info) = @_;

    # start the client
    my @cmd = (qw( bin/zircon_pipe -Q ), reverse $self->clip_ids);
    $self->{chld_pid} = open $self->{chld_fh}, '|-', @cmd
      or die "Failed to pipe to @cmd: $!";

    $self->state_bump(started => "(@cmd) => pid $$self{chld_pid}");
#    $self->afterIdle([ $self, 'instruct' ]);
    return ();
}

sub instruct {
    my ($self) = @_;
    my $cin = $self->{chld_fh};

    # ask it to contact us
    $cin->autoflush(1);
    $cin->print("shakey handy\n") or die "print to child: $!";
    $self->state_bump('instructed');
    return;
}

sub being_destroyed {
    my ($self, $win) = @_;

    # The bind also covers subwidgets (buttons, labels) - ignore
    return unless $win == $self;

    $self->state_bump('finishing');
    return;
}


sub state_bump {
    my ($self, $new_state, @info) = @_;
    my $want_state = shift @{ $self->{want_states} };
    is($new_state, $want_state, "state_bump to $want_state. info=(@info)");
    my $after = "do_after__$new_state";
    $self->$after(@info) if $self->can($after);
    return ();
}

sub do_after__replied {
    my ($self) = @_;

    # close the child
    $self->{chld_fh}->close;

    my $gone_pid = wait;
    $self->state_bump(reaped => "exit code !=$! ?=$?");
    # weird, $!=="No child processes".  Doesn't matter to us.

    $self->destroy;
}



package ConnHandler;

sub new {
    my ($pkg) = @_;
    return bless { }, __PACKAGE__;
}

sub zconn {
    my ($self, @arg) = @_;
    ($self->{zconn}) = @arg if @arg;
    return $self->{zconn} or
      die "Need zconn set now";
}

sub zircon_connection_timeout {
    my ($self, @info) = @_;
    $self->widget->state_bump(timeout => @info);
    $self->widget->destroy;
    return;
}

sub zircon_connection_request {
    my ($self, $request) = @_;
    $self->widget->state_bump(requested => $request);
    my $reply = 'howdy doo';
    $self->zconn->after(sub { $self->zcreq_done($reply) });
    return $reply;
}

sub zircon_connection_reply {
    my ($self, $reply) = @_;
    $self->widget->state_bump(reply => $reply);
    return;
}

sub zcreq_done {
    my ($self, $reply) = @_;
    $self->widget->state_bump(replied => $reply);
    return;
}

sub widget {
    my ($self) = @_;
    return $self->zconn->context->widget;
}
