
package Zircon::Trace;

use strict;
use warnings;

sub trace_env_update {
    my ($called) = @_;
    return unless Bio::Otter::Debug->can('debug');

    if (Bio::Otter::Debug->debug('Zircon')) {
        $ENV{$_}=1 foreach
          (qw( ZIRCON_CONNECTION_TRACE ZIRCON_PROTOCOL_TRACE
               ZIRCON_CONTEXT_TRACE    ZIRCON_SELECTION_TRACE ));
        # we don't admit being able to turn it off again,
        # because maybe it was set via %ENV from outside
    }

    return;
}

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

1;

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
