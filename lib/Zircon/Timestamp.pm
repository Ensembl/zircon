
package Zircon::Timestamp;

use strict;
use warnings;

use Time::HiRes qw( gettimeofday );

sub timestamp {
    my ($sec, $usec) = gettimeofday;
    return {
        clock_sec  => $sec,
        clock_usec => $usec,
    };
}

1;

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
