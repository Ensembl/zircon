
package Zircon::Trace;

use strict;
use warnings;


sub zircon_trace {
    my ($self, $format, @args) = @_;
    my ($pkg, $sub_name) =
        (caller(1))[3] =~ /\A(.*)::(.*)\z/;
    {
        my $key_name = "${pkg}::ZIRCON_TRACE_KEY";
        no strict qw( refs ); ## no critic (TestingAndDebugging::ProhibitNoStrict)
        return unless $$key_name && $ENV{$$key_name};
    }
    my @trace_list = ( );
    my $trace_prefix = $self->zircon_trace_prefix;
    push @trace_list, $trace_prefix if $trace_prefix;
    my $format_full = "%s()";
    $format_full .= ": ${format}" if $format;
    push @trace_list, sprintf $format_full, $sub_name, @args;
    warn sprintf "%s\n", join ': ', @trace_list;
    return;
}

sub zircon_trace_prefix {
    return;
}


our %TRACE; # for e.g. ZIRCON_TRACE=sortable,colour,stamp
sub trace_env_update {
    my ($called) = @_;
    return if keys %TRACE; # run no more than once per Perl

    # Maybe set extra tracing - for otterlace
    if (Bio::Otter::Debug->can('debug') &&
        Bio::Otter::Debug->debug('Zircon')) {
        $ENV{$_}=1 foreach
          (qw( ZIRCON_ZMAP_TRACE
               ZIRCON_CONNECTION_TRACE ZIRCON_PROTOCOL_TRACE
               ZIRCON_CONTEXT_TRACE    ZIRCON_SELECTION_TRACE ));
        # we don't admit being able to turn it off again,
        # because maybe it was set via %ENV from outside
    }

    # Maybe change output style
    if ($ENV{ZIRCON_TRACE}) {
        foreach my $kvp (split ',', $ENV{ZIRCON_TRACE}) {
            my ($k, $v) = $kvp =~ m{^(.*?)(?:=(.*))?$};
            $TRACE{$k} = defined $v ? $v : 1;
        }
        $called->_warn_hook;
    }
    $TRACE{done_env} = 1;

    return;
}

sub _warn_hook {
    $ENV{ZIRCON_TRACE} .= ',child';
    $TRACE{t0} = 1000*int(time() /1000); # short timestamps, locally synchronised

    require Time::HiRes;
    $SIG{__WARN__} = \&__warn_handler;

    return;
}

# Can handles the simplistic case of one connection, colouring all
# warn()s by (are we the child process?)
sub __warn_handler {
    my ($msg) = @_;
    chomp $msg;

    return # Ignore
      if $TRACE{silent};

    $msg =~ s{\n}{\\N}g # Protect the ability to sort(1) output
      if $TRACE{sortable};

    if ($TRACE{colour}) {
        my $clr = $TRACE{child} ? 36 : 33;
        if (my $ptn = $TRACE{bold}) {
            $TRACE{bold} = $ptn = qr{$ptn} unless ref($ptn);
            $msg =~ s{($ptn)}{\x1B[01m${1}\x1B[00;${clr}m}g;
        }
        $msg = qq{\x1B[${clr}m$msg\x1B[00m};
    }

    $msg = sprintf('%11.6f: %s', Time::HiRes::tv_interval([ $TRACE{t0}, 0 ]),
                   $msg) if $TRACE{stamp};

    print STDERR "$msg\n";
    return;
}

1;

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
