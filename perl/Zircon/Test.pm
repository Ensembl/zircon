
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

=item * Click the "Exit" button in both windows.

=over

=item * Check:

Each window closes when clicked.

=back

=back

=item * Run "zircon_remotecontrol_test".

=over

=item * Click the "Exit" button in the child window.

=over

=item * Check:

The child window closes.

=back

=item * Click the "Ping" button in the parent window.

=over

=item * Check:

The parent window announces that as a client the ping timed out.

=back

=item * Click the "Exit" button in the parent window.

=over

=item * Check:

The parent window closes.

=back

=back

=item * Run "zircon_remotecontrol_test".

=over

=item * Click the "Exit" button in the parent window.

=over

=item * Check:

The parent window closes.

=back

=item * Click the "Ping" button in the child window.

=over

=item * Check:

The child window announces that as a client the ping timed out.

=back

=item * Click the "Exit" button in the child window.

=over

=item * Check:

The child window closes.

=back

=back

=item * Run "zircon_remotecontrol_test".

=over

=item * Click the "Goodbye" button in the child window.

=over

=item * Check:

The child window closes.

=item * Check:

The parent window announces that as a server it has received a goodbye.

=back

=item * Click the "Ping" button in the parent window.

=over

=item * Check:

The parent window announces an error as the connection is closed.

=back

=item * Click the "Exit" button in the parent window.

=over

=item * Check:

The parent window closes.

=back

=back

=item * Run "zircon_remotecontrol_test".

=over

=item * Click the "Goodbye" button in the parent window.

=over

=item * Check:

The parent window closes.

=item * Check:

The child window announces that as a server it has received a goodbye.

=back

=item * Click the "Ping" button in the child window.

=over

=item * Check:

The child window announces an error as the connection is closed.

=back

=item * Click the "Exit" button in the child window.

=over

=item * Check:

The child window closes.

=back

=back

=item * Run "zircon_remotecontrol_test".

=over

=item * Click the "Shutdown" button in the parent window.

=over

=item * Check:

The child window closes.

=item * Check:

The parent window announces that as a client the shutdown succeeded.

=back

=item * Click the "Ping" button in the parent window.

=over

=item * Check:

The parent window announces an error as the connection is closed.

=back

=item * Click the "Exit" button in the parent window.

=over

=item * Check:

The parent window closes.

=back

=back

=item * Run "zircon_remotecontrol_test".

=over

=item * Click the "Shutdown" button in the child window.

=over

=item * Check:

The parent window closes.

=item * Check:

The child window announces that as a client the shutdown succeeded.

=back

=item * Click the "Ping" button in the child window.

=over

=item * Check:

The child window announces an error as the connection is closed.

=back

=item * Click the "Exit" button in the child window.

=over

=item * Check:

The child window closes.

=back

=back

=back

=back

=cut
