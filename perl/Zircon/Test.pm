
=head1 Zircon::Test

This is the Zircon test suite.

=over

=item * XML protocol

=over

=item * Run "zircon_remotecontrol_test".

=over

=item * Check:

Two windows appear, titled parent and child.

=item * Check:

The parent window announces that as a server it has received a handshake.

=item * Check:

The child window announces that as a client the handshake succeeded.

=item * Click the "Ping" button in the parent window.

=over

=item * Check:

The parent announces that as a client the ping succeeded.

=item * Check:

The child announces that as a server it received a ping. 

=back

=item * Click the "Ping" button in the child window.

=over

=item * Check:

The child announces that as a client the ping succeeded.

=item * Check:

The parent announces that as a server it received a ping. 

=back

=item * Close both windows.

=back

=item * Run "zircon_remotecontrol_test".

=over

=item * Close the child window.

=item * Click the "Ping" button in the parent window.

=over

=item * Check:

The parent window announces that as a client the ping timed out.

=back

=item * Close the parent window.

=back

=item * Run "zircon_remotecontrol_test".

=over

=item * Close the parent window.

=item * Click the "Ping" button in the child window.

=over

=item * Check:

The child window announces that as a client the ping timed out.

=back

=item * Close the child window.

=back

=back

=back

=cut
