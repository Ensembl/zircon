
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

1;

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
