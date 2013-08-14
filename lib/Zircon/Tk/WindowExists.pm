package Zircon::Tk::WindowExists;

use strict;
use warnings;

use Try::Tiny;
use POSIX;
use IO::Handle;

sub query {
    my ($pkg, $window_id, $prop) = @_;
    die "Need window_id and property name" unless $window_id && $prop;

    my @cmd = ($pkg->_xprop, '-id' => $window_id, $prop);
    my $pid = open my $out, '-|';

    if (!defined $pid) {
        die "fork failed: $!";
    } elsif ($pid) { # parent
        my $in = join '', <$out>;
        if ($in =~ s{^[^=]+= *}{}) {
            # 'PropName(STRING) = "foo"' + returncode 0
            $in =~ s{^"|"\n$}{}g; # trim wrappings, leave taint
            return $in;
        } else {
            # 'PropName' + returncode 1 (window is gone)
            # 'PropName: not found' + returncode 0 (not this window)
            return 0;
        }
    } else { # child
        # Hide STDERR before exec, to prevent alarming noise

        try { untie *STDERR };
        open STDERR, '>', '/dev/null'; # or we may emit noise

        { exec @cmd };
        print "$pkg: failed to exec @cmd";
        try { close STDOUT }; # for flush
        POSIX::_exit(127); # avoid DESTROY and END actions
    }
}


my $fn;
sub _xprop {
    $fn = __path_find('xprop') unless defined $fn;
    return $fn;
}

sub __path_find {
    my ($prog) = @_;
    my $path = $ENV{PATH};
    foreach my $dir (split /:/, $path) {
        my $fn = "$dir/$prog";
        return $fn if -x $fn && -f _;
    }
    die "Could not find $prog on PATH=$path";
}

# ensure at compile time that we have it
__PACKAGE__->_xprop;

1;
