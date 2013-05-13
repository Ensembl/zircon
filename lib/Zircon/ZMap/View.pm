
package Zircon::ZMap::View;

use strict;
use warnings;

use Try::Tiny;
use Scalar::Util qw( weaken );

sub new {
    my ($pkg, %arg_hash) = @_;
    my $new = { };
    bless $new, $pkg;
    $new->_init(\ %arg_hash);
    return $new;
}

sub _init {
    my ($self, $arg_hash) = @_;
    $self->{"_$_"} = $arg_hash->{"-$_"} for qw( zmap handler view_id name );
    weaken $self->{'_handler'} if ref $self->{'_handler'};
    return;
}

sub get_mark {
    my ($self) = @_;
    my $result = $self->send_command_and_xml('get_mark');
    $result->success or return; # absent mark is a failure!
    my $hash = $result->reply->[0][1];
    my $start = abs($hash->{'start'});
    my $end   = abs($hash->{'end'});
    if ($end < $start) {
        ($start, $end) = ($end, $start);
    }
    return ($start, $end);
}

sub load_features {
    my ($self, @featuresets) = @_;
    my $xml = $self->handler->zircon_zmap_view_load_features_xml(@featuresets);    
    my $result = $self->send_command_and_xml('load_features', $xml);
    $result->success or die "&load_features: failed";
    return;
}

sub delete_featuresets {
    my ($self, @featuresets) = @_;
    my $xml = $self->handler->zircon_zmap_view_delete_featuresets_xml(@featuresets);
    my $result = $self->send_command_and_xml('delete_feature', $xml);
    $result->success or die "&delete_featuresets: failed";
    return;
}

sub zoom_to_subseq {
    my ($self, $subseq) = @_;
    my $xml = $self->handler->zircon_zmap_view_zoom_to_subseq_xml($subseq);
    my $result = $self->send_command_and_xml('zoom_to', $xml);
    my $success = $result->success;
    return $success;
}

sub send_command_and_xml {
    my ($self, @arg_list) = @_;
    my $result = $self->zmap->send_command_and_xml($self, @arg_list);
    return $result;
}

# attributes

sub zmap {
    my ($self) = @_;
    my $zmap = $self->{'_zmap'};
    return $zmap;
}

sub handler {
    my ($self) = @_;
    my $handler = $self->{'_handler'};
    return $handler;
}

sub view_id {
    my ($self) = @_;
    my $view_id = $self->{'_view_id'};
    return $view_id;
}

sub name {
    my ($self) = @_;
    my $name = $self->{'_name'};
    return $name;
}

# destructor

sub DESTROY {
    my ($self) = @_;
    try { $self->zmap->view_destroyed($self); }
    catch { warn $_; };
    return;
}

1;

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
