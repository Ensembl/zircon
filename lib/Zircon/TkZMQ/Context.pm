
package Zircon::TkZMQ::Context;

use strict;
use warnings;

use Carp qw( croak cluck );
use Readonly;
use Scalar::Util qw( weaken refaddr );

use ZMQ::LibZMQ3;
use ZMQ::Constants qw(ZMQ_REP ZMQ_LAST_ENDPOINT);

use Zircon::Tk::Selection;
use Zircon::Tk::WindowExists;
use Zircon::Tk::MonkeyPatches;

use base 'Zircon::Trace';
our $ZIRCON_TRACE_KEY = 'ZIRCON_CONTEXT_TRACE';

Readonly my $ZMQ_DEFAULT_ENDPOINT => 'tcp://127.0.0.1:*';

sub new {
    my ($pkg, %args) = @_;
    my $new = { };
    bless $new, $pkg;
    $new->init(\%args);
    return $new;
}

sub init {
    my ($self, $args) = @_;
    $self->{'waitVariable_hash'} = { };
    my $widget = $args->{'-widget'};
    defined $widget or die 'missing -widget argument';
    $self->{'widget'} = $widget;
    $self->zircon_trace;
    return;
}

sub local_endpoint_init {
    my ($self) = @_;

    my $zmq_context = zmq_init;
    $self->zmq_context($zmq_context);

    my $responder = zmq_socket($zmq_context, ZMQ_REP);
    zmq_bind($responder, $self->local_endpoint);
    $self->zmq_responder($responder);

    my $endpoint = zmq_getsockopt($responder, ZMQ_LAST_ENDPOINT);
    $self->local_endpoint($endpoint);
    $self->zircon_trace('local_endpoint: %s', $endpoint);

    return;
}

# platform
sub platform { return 'ZMQ'; }

sub stack_tangle {
    my ($pkg, $trace_return) = @_;
    # This may be rather specific to the Perl-Tk version,
    # but it has tests.

    my @stack;
    for (my $i=0; 1; $i++) { # exit via last
        my @frame = caller($i);
        last if !@frame;
        push @stack, \@frame;
    }

    my (@wait, @trace, %skip);
    for (my $i=0; $i < @stack; $i++) {
        my ($package, $filename, $line, $subroutine, undef,
            undef, $evaltext, $is_require) = @{ $stack[$i] };
        if ($subroutine eq '(eval)') {
            if ($is_require) {
                $subroutine = '(require)';
            } elsif (defined $evaltext) {
                $subroutine = 'eval""';
            } else {
                $subroutine = 'eval{}';
            }
        }
        push @trace, "$subroutine called from $package at $filename line $line";

        next if $skip{$i}; # mentioned in previous line

        next unless $subroutine =~
          m{^(
                Tk::Widget::wait(Variable|Visibility|Window)| # they call tkwait
                Zircon::Tk::MonkeyPatches::(DoOneEvent|update) # extra stack frames for XS subs
            )$}x;
        my ($wait_type) = $subroutine =~ m{::([^:]+)$};

        my $caller_sub = defined $stack[$i+1] ? $stack[$i+1][3] : '(script)';
        my $via = '';
        if ($caller_sub =~
            m{^(
                  Tk::(MainLoop|updateWidgets)| # they call DoOneEvent
                  Tk::(idletasks|Widget::(B|Unb)usy) # they call update
              )$}x) {
            $via = " via $caller_sub";
            $skip{$i+1} = 1;

            (undef, $filename, $line) = @{ $stack[$i+1] } if $stack[$i+1];
            $caller_sub = $stack[$i+2] ? $stack[$i+2][3] : '(script)';
        }

        push @wait, "$wait_type$via from $caller_sub at $filename line $line";
    }

    @$trace_return = @trace if defined $trace_return;
    return @wait;
}

our %TANGLE_ACK = (MainLoop => 1);
sub warn_if_tangled {
    my ($pkg, $extra_threshold) = @_;
    my (undef, $fn, $ln) = caller();

    my ($max_wait_frames, @max) = (0);
    local $TANGLE_ACK{extra} = $extra_threshold;
    foreach my $k (sort keys %TANGLE_ACK) {
        my $v = $TANGLE_ACK{$k};
        next unless defined $v;
        $max_wait_frames += $v;
        push @max, sprintf('%s:%+d', $k, $v);
    }

    my @trace;
    my @wait = $pkg->stack_tangle(\@trace);
    my $d = @wait;
    if (@wait > $max_wait_frames) {
        warn join '',
          "Event handling loop depth $d > (@max = $max_wait_frames) exceeded, as seen at $fn line $ln\n",
            map {"  $_\n"} @wait;
        warn join '', "Full trace\n", map {"  $_\n"} @trace;
    }
#    else { warn "Event handling loop depth $d <= (@max = $max_wait_frames) OK, as seen at $fn line $ln\n" }

    return;
}

# selections

sub selection_new {
    my ($self, @args) = @_;
    $self->zircon_trace('for (%s)', "@args");
    my $selection =
        Zircon::Tk::Selection->new(
            '-platform' => $self->platform,
            '-widget'   => $self->widget,
            @args);
    return $selection;
}

# timeouts

sub timeout {
    my ($self, @args) = @_;

    my $w = $self->widget;
    Tk::Exists($w)
        or croak "Attempt to set timeout with destroyed widget";
    my $timeout_handle = $w->after(@args);
    $self->zircon_trace('configured (%d millisec)', $args[0]);
    return $timeout_handle;
}

# waiting

sub waitVariable {
    my ($self, $var) = @_;
    $self->waitVariable_hash->{$var} = $var;
    weaken $self->waitVariable_hash->{$var};
    my $w = $self->widget;
    Tk::Exists($w)
        or croak "Attempt to waitVariable with destroyed widget";

    $self->zircon_trace('startWAIT(0x%x) for %s=%s', refaddr($self), $var, $$var);
    $self->warn_if_tangled;
    $w->waitVariable($var); # traced
    $self->zircon_trace('stopWAIT(0x%x) with %s=%s', refaddr($self), $var, $$var);
    Tk::Exists($w)
        or cluck "Widget $w destroyed during waitVariable";
    return;
}

# attributes

sub widget {
    my ($self) = @_;
    my $widget = $self->{'widget'};
    return $widget;
}

sub waitVariable_hash {
    my ($self) = @_;
    my $waitVariable_hash = $self->{'waitVariable_hash'};
    return $waitVariable_hash;
}

sub widget_xid {
    my ($self) = @_;
    return $self->widget->id;
}

# other app's windows

sub window_exists {
    my ($self, $win_id, $prop) = @_;

    # Another process does the checking
    return Zircon::Tk::WindowExists->query($win_id, $prop);
}

sub window_declare {
    my ($self, $connection) = @_;

    # Set the expected property on our window so the peer
    # knows it is us, and not something else re-using the window_id
    my $prop = $connection->local_endpoint;
    my $val = $$;
    $self->widget->property(set => $prop, STRING => 8, $val);
    return ();
}

# ZMQ attribs

sub zmq_context {
    my ($self, @args) = @_;
    ($self->{'zmq_context'}) = @args if @args;
    my $zmq_context = $self->{'zmq_context'};
    return $zmq_context;
}

sub zmq_responder {
    my ($self, @args) = @_;
    ($self->{'zmq_responder'}) = @args if @args;
    my $zmq_responder = $self->{'zmq_responder'};
    return $zmq_responder;
}

sub local_endpoint {
    my ($self, @args) = @_;
    ($self->{'local_endpoint'}) = @args if @args;
    my $local_endpoint = $self->{'local_endpoint'} ||= $ZMQ_DEFAULT_ENDPOINT;
    return $local_endpoint;
}

sub remote_endpoint {
    my ($self, @args) = @_;
    ($self->{'remote_endpoint'}) = @args if @args;
    my $remote_endpoint = $self->{'remote_endpoint'};
    return $remote_endpoint;
}

# tracing

sub zircon_trace_prefix {
    my ($self) = @_;
    my $w = $self->widget;
    my $path = Tk::Exists($w) ? $w->PathName : '(destroyed)';
    return sprintf('Z:T:Context: widget=%s', $path);
}

1;

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
