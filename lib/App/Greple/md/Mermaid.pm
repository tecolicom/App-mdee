package App::Greple::md::Mermaid;

# The images of the Mermaid diagrams of a Markdown file.  They are
# drawn by mmdr of mermaid-rs-renderer into PNG files in a temporary
# directory, and are shown by Text::ANSI::Image as the other images
# are.

use v5.26;
use warnings;
use utf8;

use Exporter 'import';
our @EXPORT_OK = qw(diagram_files);

use File::Spec;
use File::Temp ();
use JSON::PP ();
use POSIX ();
use Text::ParseWords qw(shellwords);

# the command which draws, when none is given
our $COMMAND = 'mmdr';

# The directory of the drawn diagrams, made for each run, which nobody
# else can read, or undef when it cannot be made.  It is removed when
# mdee ends, unless it is to be kept: on paper, ansi2pdf reads the
# files after greple.
sub diagram_dir {
    my $keep = shift;
    eval {
	File::Temp::tempdir('mdee-mermaid-XXXXXXXX',
			    TMPDIR => 1, CLEANUP => !$keep);
    };
}

# The PNG files of the diagrams, in the order of the codes; undef for
# one that could not be drawn.
#
#   codes   => [ CODE, ... ]   the text of each diagram
#   command => 'mmdr ...'      the command, split as a shell does
#   theme   => 'default'       the theme of Mermaid (dark in the dark mode)
#   background => 'transparent'  the background, a color of CSS
#   scale   => 3               the scale of the image: the larger, the
#                              more cells it takes, up to the width
#   keep    => 1               the files stay after mdee ends
#
# Each diagram is drawn in a run of its own, each time.  mmdr has no
# options for the background and the scale: the background goes in a
# file of -c, unless the command has its own, and the size is asked
# for first and given multiplied (see draw).  A diagram that cannot be
# drawn is not shown.
sub diagram_files {
    my %opt = @_;
    my @codes = @{$opt{codes} // []} or return ();
    my @cmd = shellwords($opt{command} || $COMMAND);
    @cmd or return (undef) x @codes;
    my $dir = diagram_dir($opt{keep}) // return (undef) x @codes;
    my $background = $opt{background} || 'transparent';
    my $scale = $opt{scale} || 3;
    my $theme = $opt{theme} || 'default';
    my $r = { dir => $dir, cmd => \@cmd, opt => [ '-e', 'png', '-t', $theme ],
	      scale => $scale };
    my $conf;
    if (not grep { /^(?:-c|--configFile(?:=|$))/ } @cmd) {
	$conf = config_file($dir,
	    { themeVariables => { background => "$background" } });
	push @{$r->{opt}}, '-c', "$conf" if $conf;
    }
    my $n = 0;
    map {
	my $path = File::Spec->catfile($dir, ++$n . '.png');
	draw($r, s/\n?\z/\n/r, $path);
	-s $path ? $path : undef;
    } @codes;
}

# A file of options in JSON, removed with the object
sub config_file {
    my($dir, $data) = @_;
    my $fh = eval { File::Temp->new(DIR => $dir, SUFFIX => '.json') } or return;
    print $fh JSON::PP->new->utf8->canonical->encode($data), "\n";
    close $fh;
    $fh;
}

# Draw one diagram from a file of its own.  With a scale, the command
# is first asked for the size of the diagram (--size prints it in
# JSON), and is given that size multiplied: it takes a width and a
# height and draws the diagram as large; with only one of them it
# takes 1200 or 800 for the other.  A diagram whose size is not told
# is drawn in its own size, and so is any diagram when the command has
# a width or a height of its own.
sub draw {
    my($r, $code, $path) = @_;
    my($cmd, $opt) = @{$r}{qw(cmd opt)};
    my $tmp = eval { File::Temp->newdir(DIR => $r->{dir}) } or return;
    my $in  = File::Spec->catfile($tmp, 'in.mmd');
    my $out = File::Spec->catfile($tmp, 'out.png');
    open my $fh, '>:encoding(utf8)', $in or return;
    print $fh $code;
    close $fh;
    my @size;
    if ($r->{scale} != 1
	and not grep { /^(?:-w|-H|--(?:width|height)(?:=|$))/ } @$cmd) {
	my $json = File::Spec->catfile($tmp, 'size.json');
	my $size = run({ out => $json }, @$cmd, @$opt, '-i', $in, '--size') && eval {
	    open my $fh, '<:raw', $json or die;
	    JSON::PP->new->utf8->decode(do { local $/; <$fh> });
	};
	my($w, $h) = map { $_ * $r->{scale} }
	    grep { defined and !ref and /^[\d.]+$/ and $_ > 0 }
	    ref $size eq 'HASH' ? @{$size}{qw(width height)} : ();
	@size = ('-w', POSIX::ceil($w), '-H', POSIX::ceil($h)) if defined $h;
    }
    run(@$cmd, @$opt, @size, '-i', $in, '-o', $out)
	and -s $out and rename $out, $path;
}

# Run a command, without a shell, its output thrown away, or its
# standard output written to the file of { out => FILE } given first.
# True when it ends with success.
sub run {
    my $to = ref $_[0] eq 'HASH' ? shift : {};
    my @cmd = @_;
    my $pid = fork // return;
    if ($pid == 0) {
	open STDIN,  '<', File::Spec->devnull;
	open STDOUT, '>', $to->{out} // File::Spec->devnull or POSIX::_exit(127);
	open STDERR, '>', File::Spec->devnull;
	exec { $cmd[0] } @cmd or POSIX::_exit(127);
    }
    waitpid $pid, 0;
    $? == 0;
}

1;

__END__

=encoding utf-8

=head1 NAME

App::Greple::md::Mermaid - draw the Mermaid diagrams of a Markdown text

=head1 SYNOPSIS

    use App::Greple::md::Mermaid qw(diagram_files);

    my @png = diagram_files(codes => \@codes, theme => 'dark');

=head1 DESCRIPTION

This module draws the Mermaid diagrams for the C<mermaid> type of the
C<image_types> option of L<App::Greple::md>, which shows them with
L<Text::ANSI::Image>.

=over 4

=item B<diagram_files>(B<codes> => [I<CODE>, ...], B<command> => I<COMMAND>, B<theme> => I<THEME>, B<background> => I<COLOR>, B<scale> => I<N>, B<keep> => I<BOOL>)

Returns the PNG files of the diagrams, in the order of the codes, and
C<undef> for one that could not be drawn.  They are drawn by
I<COMMAND> (split into words as a shell does; default C<mmdr> of
L<mermaid-rs-renderer|https://github.com/1jehuang/mermaid-rs-renderer>),
with the theme, the background (default C<transparent>) and the scale
(default 3), each time, into a temporary directory that only the user
can read.  The directory is removed when the program ends, unless
B<keep> is true: on paper, ansi2pdf reads the files after greple.

Each diagram is drawn in a run of its own.  mmdr has no options for
the background and the scale: the background is given as
C<themeVariables> in a file of C<-c>, unless I<COMMAND> has its own
C<-c> (C<--configFile>), and for a scale other than 1 it is first
asked for the size of the diagram (C<--size>) and then given that size
multiplied (C<-w>, C<-H>), unless I<COMMAND> has a width or a height
of its own.

A diagram that cannot be drawn is not shown.

=back

=head1 SEE ALSO

L<App::Greple::md>, L<Text::ANSI::Image>

=head1 LICENSE

This software is released under the MIT License.
L<https://opensource.org/licenses/MIT>

=cut
