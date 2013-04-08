
package Zircon::Trace;

use strict;
use warnings;

use base qw( Exporter );

our @EXPORT = qw( zircon_trace ); ## no critic (Modules::ProhibitAutomaticExportation)

sub zircon_trace {
    my ($self, $format, @args) = @_;
    my ($pkg, $sub_name) =
        (caller(1))[3] =~ /\A(.*)::(.*)\z/;
    {
        my $key_name = "${pkg}::ZIRCON_TRACE_KEY";
        no strict qw( refs ); ## no critic (TestingAndDebugging::ProhibitNoStrict)
        return unless $$key_name && $ENV{$$key_name};
    }
    my ($format_extra, @args_extra) = $self->zircon_trace_format;
    my $format_full = "%s::%s()";
    $format_full .= ": ${format_extra}" if $format_extra;
    $format_full .= ": ${format}" if $format;
    $format_full .= "\n";
    warn sprintf $format_full
        , $pkg, $sub_name, @args_extra, @args;
    return;
}

sub zircon_trace_format {
    return;
}

1;

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
