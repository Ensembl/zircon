
package Zircon::ZMap::View::Handler;

use strict;
use warnings;

sub zircon_zmap_view_features_loaded {
    my ($self, $status, $client_message, @feature_list) = @_;
    my $message =
        sprintf "features loaded: %s\n%s"
        , $client_message, (join ', ', @feature_list);
    $self->zircon_server_log($message);
    return;
}

1;

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
