
package Utterloss::Application;

use strict;
use warnings;

use POSIX();

use Tk;
use Tk::Pane;
use Tk::Button;
use Tk::Radiobutton;

use Zircon::Tk::Context;

use Utterloss::Session;

sub new {
    my ($pkg) = @_;
    my $new = { };
    bless $new, $pkg;
    $new->_init;
    return $new;
}

sub _init {
    my ($self) = @_;
    $self->{'session_hash'} = { };
    $self->window_create;
    $self->zircon_context_create;
    $self->session_pane_create;
    $self->program_frame_create;
    $self->exit_button_create;
    for my $session_dir (glob '/var/tmp/lace_*.done') {
        $self->session_button_create($session_dir);
    }
    return;
}

sub window_create {
    my ($self) = @_;
    my $window = $self->{'window'} = MainWindow->new;
    $window->title('Utterloss');
    return;
}

sub zircon_context_create {
    my ($self) = @_;
    $self->{'zircon_context'} =
        Zircon::Tk::Context->new(
            '-widget' => $self->window,
        );
    return;
}

sub session_pane_create {
    my ($self) = @_;
    $self->{'session_pane'} =
        $self->window
        ->Frame(
            '-borderwidth' => 2,
            '-relief'      => 'sunken',
        )
        ->pack(
            '-side'   => 'top',
            '-expand' => 1,
            '-fill'   => 'both',
        )
        ->Scrolled(
            'Pane',
            '-scrollbars' => 'e',
            '-sticky'     => 'nswe',
        )
        ->pack(
            '-side'   => 'top',
            '-expand' => 1,
            '-fill'   => 'both',
        );
    return;
}

sub program_frame_create {
    my ($self) = @_;

    my $program_frame =
        $self->window->Frame
        ->pack(
            '-side' => 'top',
            '-fill' => 'y',
        );

    my ($zmap_program) = glob '~edgrif/TEST/JEREMY/zmap';
    my $zapmop_program = 'zapmop';
    $self->{'program'} = $zmap_program;
    my $variable = \($self->{'program'});

    for (
        [ 'zmap',   $zmap_program   ],
        [ 'zapmop', $zapmop_program ],
        ) {
        my ($text, $value) = @{$_};
        $program_frame->Radiobutton(
            '-text'     => $text,
            '-anchor'   => 'w',
            '-value'    => $value,
            '-variable' => $variable,
            )
            ->pack(
            '-side' => 'top',
            '-fill' => 'both',
            );
    }

    return;
}

sub exit_button_create {
    my ($self) = @_;

    $self->window->Button(
        '-text'    => 'Exit',
        '-command' => sub { $self->_exit; },
        )
        ->pack(
        '-side' => 'bottom',
        '-fill' => 'both',
        );

    return;
}

sub finish {
    my ($self) = @_;
    $_->finish for values %{$self->session_hash};
    return;
}

sub _exit {
    my ($self) = @_;
    $self->finish;
    POSIX::exit(0);
    return;
}

sub session_button_create {
    my ($self, $session_dir) = @_;

    my ($session_name) =
        $session_dir =~ m|/lace_(.*)\.done\z|
        or die "BUG!!!\n";

    $self->session_pane->Button(
        '-text'    => $session_name,
        '-command' => sub { $self->session_new($session_dir); },
        )
        ->pack(
        '-side'   => 'top',
        '-fill'   => 'both',
        );

    return;
}

sub session_new {
    my ($self, $session_dir) = @_;
    my $session =
        Utterloss::Session->new(
            $self, {
                '-session_dir' => $session_dir,
            });
    $self->session_hash->{$session} = $session;
    return;
}

# attributes

sub session_hash {
    my ($self) = @_;
    my $session_hash = $self->{'session_hash'};
    return $session_hash;
}

sub program {
    my ($self) = @_;
    my $program = $self->{'program'};
    return $program;
}

sub window {
    my ($self) = @_;
    my $window = $self->{'window'};
    return $window;
}

sub zircon_context {
    my ($self) = @_;
    my $zircon_context = $self->{'zircon_context'};
    return $zircon_context;
}

sub session_pane {
    my ($self) = @_;
    my $session_pane = $self->{'session_pane'};
    return $session_pane;
}

1;
