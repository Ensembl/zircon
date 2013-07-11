
package Zircon::Tk::Context;

use strict;
use warnings;

use Carp qw( croak cluck );
use Scalar::Util qw( refaddr );
use Zircon::Tk::Selection;
use Zircon::Tk::WindowExists;
use Zircon::Tk::MonkeyPatches;
use base 'Zircon::Trace';
our $ZIRCON_TRACE_KEY = 'ZIRCON_CONTEXT_TRACE';


sub new {
    my ($pkg, %args) = @_;
    my $new = { };
    bless $new, $pkg;
    $new->init(\%args);
    return $new;
}

sub init {
    my ($self, $args) = @_;
    my $widget = $args->{'-widget'};
    defined $widget or die 'missing -widget argument';
    $self->{'widget'} = $widget;
    $self->zircon_trace;
    return;
}

# platform
sub platform { return 'Tk'; }

sub stack_tangle {
    my ($self) = @_;
    # This may be rather specific to the Perl-Tk version,
    # but it has tests.

    my @stack;
    for (my $i=0; 1; $i++) { # exit via last
        my @frame = caller($i);
        last if !@frame;
        push @stack, \@frame;
    }

    my (@wait, @trace);
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
#print STDERR "  $trace[-1]\n";

        next unless $subroutine =~
          m{^(
                Tk::Widget::wait(Variable|Visibility|Window)| # they call tkwait
                Zircon::Tk::MonkeyPatches::(DoOneEvent|update) # extra stack frames for XS subs
            )$}x;
         my ($wait_type) = $subroutine =~ m{::([^:]+)$};

        my $caller_sub = $stack[$i+1][3];
        my $via = '';
        if ($caller_sub =~
            m{^(
                  Tk::(MainLoop|updateWidgets)| # they call DoOneEvent
                  Tk::(idletasks|Widget::(B|Unb)usy) # they call update
              )$}x) {
            $via = " via $caller_sub";
            $i++;
            $caller_sub = $stack[$i+1][3];
        }

        push @wait, "$wait_type$via from $caller_sub at $filename line $line";
    }

    return @wait;
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
    my $w = $self->widget;
    Tk::Exists($w)
        or croak "Attempt to waitVariable with destroyed widget";
    $self->zircon_trace('startWAIT(0x%x) for %s=%s', refaddr($self), $var, $$var);
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

sub widget_xid {
    my ($self) = @_;
    return $self->widget->id;
}

# other app's windows

sub window_exists {
    my ($self, $win_id) = @_;

    # Another process does the checking
    my $we = $self->{_window_exists} ||= Zircon::Tk::WindowExists->new;
    return $we->query($win_id);
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
