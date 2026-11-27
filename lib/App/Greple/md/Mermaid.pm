package App::Greple::md::Mermaid;

# The images of the Mermaid diagrams of a Markdown file.  They are
# drawn by a command (mmdr of mermaid-rs-renderer, or mmdc of
# mermaid-cli) into PNG files in a cache directory, and are
# shown by Text::ANSI::Image as the other images are.

use v5.26;
use warnings;
use utf8;

use Exporter 'import';
our @EXPORT_OK = qw(diagram_files);

use Encode qw(encode_utf8);
use Digest::SHA qw(sha1_hex);
use Fcntl qw(O_WRONLY O_CREAT O_EXCL);
use File::Path qw(make_path);
use File::Spec;
use File::Temp ();
use JSON::PP ();
use POSIX ();
use Text::ParseWords qw(shellwords);

# The commands which draw, in the order they are looked for in PATH
# when none is given; the first when none is found.  $COMMAND, when
# set, is used in place of them.
our @COMMANDS = qw(mmdr mmdc);
our $COMMAND;

sub default_command {
    for my $name (@COMMANDS) {
	for my $dir (File::Spec->path) {
	    my $file = File::Spec->catfile($dir, $name);
	    return $name if -f $file and -x _;
	}
    }
    $COMMANDS[0];
}

# seconds that one run of the command may take
our $TIMEOUT = 60;

# The options of puppeteer given to mmdc: the browser goes to the
# network only through a proxy that is not there, so that a diagram
# cannot fetch anything (a remote image in a node) when it is drawn.
# Nothing is fetched from the network, as for the other images.
our %PUPPETEER = (
    args => [ '--proxy-server=http://127.0.0.1:9', '--proxy-bypass-list=<-loopback>' ],
);

# days that the empty file of a diagram that failed is kept; after
# that it is tried again (mmdc may be a newer one by then)
our $RETRY_DAYS = 1;

# A diagram that any mmdc draws: drawn to see whether the command
# works, when a diagram fails and nothing says that it does
our $PROBE = "graph TD\n  A --> B\n";

# The directory of the drawn diagrams, or undef when there is no place
# for it: a real directory of the user, not a symbolic link, which
# nobody else can read.  A diagram is kept by the digest of the
# command, its options and the code, so that it is drawn once: mmdc
# starts a browser and takes a few seconds.  The files stay after mdee
# ends, which they must on paper, where ansi2pdf reads them after
# greple.
sub cache_dir {
    my $base = $ENV{XDG_CACHE_HOME}
	|| (defined $ENV{HOME} && File::Spec->catdir($ENV{HOME}, '.cache'))
	|| return;
    my $dir = File::Spec->catdir($base, 'mdee', 'mermaid');
    -e $dir or make_path($dir, { mode => 0700, error => \my $err });
    my @st = lstat $dir or return;
    -d _ && $st[4] == $> or return;
    if ($st[2] & 077) {
	chmod $st[2] & 0700, $dir or return;
    }
    $dir;
}

# Whether the command is mmdr, by its name: mmdr has other options
# than mmdc (no -b, -s, -q or -p), draws without a browser, and is
# quick enough to be run for each diagram.
sub is_mmdr {
    my $name = (File::Spec->splitpath($_[0] // ''))[2];
    $name =~ /^mmdr/i;
}

# A body which mmdc would cut in a Markdown file: its pattern (in
# JavaScript, where $ is also before CR, U+2028 and U+2029, and \s has
# U+FEFF) takes a line which ends with ``` or ::: as the end of the
# block.  Such a body is drawn from a file of its own.
sub ambiguous {
    $_[0] =~ /[`:]{3}[\h\x0B\x0C\x{FEFF}]*(?:[\n\r\x{2028}\x{2029}]|\z)/;
}

# The PNG files of the diagrams, in the order of the codes; undef for
# one that could not be drawn.
#
#   codes   => [ CODE, ... ]   the text of each diagram
#   command => 'mmdc ...'      the command, split as a shell does; one
#                              whose name starts with mmdr is run as mmdr
#   theme   => 'default'       the theme of Mermaid (dark in the dark mode)
#   background => 'transparent'  the background, a color of CSS
#   scale   => 3               the scale of the image: the larger, the
#                              more cells it takes, up to the width
#
# The diagrams are drawn in one run, which starts the browser once.  A
# diagram that fails stops the run, so those not drawn are then drawn
# one by one.  One that fails alone is kept as an empty file, so that
# it is not tried again each time, when the command is known to work:
# a diagram is drawn in this call, or else the diagram $PROBE is
# drawn to see.  When that fails too, the command does not
# work (not found, or no browser): nothing more is tried and nothing
# is kept, so that the diagrams are drawn once it works.  A run that
# takes too long is treated as one that fails, but nothing more is
# tried after one diagram alone takes too long.
#
# mmdr draws each diagram in a run of its own, from the beginning.
sub diagram_files {
    my %opt = @_;
    my @codes = @{$opt{codes} // []} or return ();
    my $dir = cache_dir() // return (undef) x @codes;
    my @cmd = shellwords($opt{command} || $COMMAND || default_command());
    @cmd or return (undef) x @codes;
    my $mmdr = is_mmdr($cmd[0]);
    my $background = $opt{background} || 'transparent';
    my $scale = $opt{scale} || 3;
    my $theme = $opt{theme} || 'default';
    # what the digest is made of, which are also the options of mmdc
    my @look = ('-e', 'png', '-b', $background, '-s', $scale, '-t', $theme);
    my @draw = $mmdr ? ('-e', 'png', '-t', $theme) : ('-q', @look);
    my $file = sub {
	my $code = $_[0] =~ s/\n?\z/\n/r;
	File::Spec->catfile($dir, sha1_hex(encode_utf8(join "\0", @cmd, @look, $code)) . '.png');
    };
    my @path = map { $file->($_) } @codes;
    # the empty file of a diagram that failed long ago is forgotten
    for my $p (@path) {
	unlink $p if -e $p and -z _ and -M _ > $RETRY_DAYS;
    }
    my %seen;
    my @todo = grep { !-e $path[$_] and !$seen{$path[$_]}++ } 0 .. $#codes;
    # A file of options, unless the command has its own: those of
    # puppeteer for mmdc, the background for mmdr, which has no option
    # for it.  After the digest, which must not depend on the name of
    # the file.
    my $conf;
    my($flag, $own, $text) = $mmdr
	? ('-c', qr/^(?:-c|--configFile(?:=|$))/,
	   { themeVariables => { background => "$background" } })
	: ('-p', qr/^(?:-p|--puppeteerConfigFile(?:=|$))/, \%PUPPETEER);
    if (@todo and -w $dir and not grep { /$own/ } @cmd) {
	if ($conf = config_file($dir, $text)) {
	    push @draw, $flag, "$conf";
	} else {
	    @todo = ();
	}
    }
    # mmdr has no scale: the size is asked first, and given multiplied
    my $r = { dir => $dir, cmd => \@cmd, opt => \@draw,
	      $mmdr ? (scale => $scale) : () };
    # without a place to write, the diagrams drawn before are shown
    if (@todo and -w $dir) {
	my @batch = grep { !ambiguous($codes[$_]) } @todo;
	my @alone = grep {  ambiguous($codes[$_]) } @todo;
	# Whether the command works is found out in this call: a
	# diagram drawn before does not tell that it works now (the
	# browser may be gone, or its place not set in this shell).
	my $works = 0;
	my %failed;
	if (!$mmdr and @batch > 1) {
	    my $status = draw_md($r, [ @codes[@batch] ], [ @path[@batch] ]);
	    $works ||= grep { -e $path[$_] } @batch;
	    @batch = @alone = () if $status eq 'error';
	}
	for my $i (@batch, @alone) {
	    next if -e $path[$i];
	    my $status = draw_one($r, $codes[$i], $path[$i]);
	    if (-e $path[$i]) {
		$works = 1;
		next;
	    }
	    last if $status eq 'error';
	    $works ||= probe($r) or last;
	    $failed{$i} = 1;
	    last if $status eq 'timeout';
	}
	for my $i (grep { $failed{$_} } @todo) {
	    # never in place of a file drawn meanwhile
	    sysopen(my $fh, $path[$i], O_WRONLY | O_CREAT | O_EXCL, 0600) or next;
	    close $fh;
	}
    }
    map { -s $_ ? $_ : undef } @path;
}

# A file of options in JSON, removed with the object
sub config_file {
    my($dir, $data) = @_;
    my $fh = eval { File::Temp->new(DIR => $dir, SUFFIX => '.json') } or return;
    print $fh JSON::PP->new->utf8->canonical->encode($data), "\n";
    close $fh;
    $fh;
}

# Draw the diagrams by one run of the command, with a Markdown file of
# them all: mmdc writes the image of the Nth diagram to out-N.png.
sub draw_md {
    my($r, $codes, $paths) = @_;
    # in the cache directory, so that rename() does not cross devices
    my $tmp = eval { File::Temp->newdir(DIR => $r->{dir}) } or return 'error';
    my $in  = File::Spec->catfile($tmp, 'in.md');
    my $out = File::Spec->catfile($tmp, 'out.md');
    open my $fh, '>:encoding(utf8)', $in or return 'error';
    print $fh "```mermaid\n", s/\n?\z/\n/r, "```\n\n" for @$codes;
    close $fh;
    # the diagrams before one that fails are drawn
    my $status = run(@{$r->{cmd}}, @{$r->{opt}}, '-i', $in, '-o', $out);
    for my $i (0 .. $#$codes) {
	my $png = File::Spec->catfile($tmp, sprintf 'out-%d.png', $i + 1);
	-s $png and rename $png, $paths->[$i];
    }
    $status;
}

# Whether the command draws the diagram $PROBE
sub probe {
    my $r = shift;
    my $png = eval { File::Temp->new(DIR => $r->{dir}, SUFFIX => '.png') } or return 0;
    draw_one($r, $PROBE, "$png");
    -s "$png" ? 1 : 0;
}

# Draw one diagram from a file of its own, as it is.  With a scale
# (mmdr), the command is first asked for the size of the diagram
# (--size prints it in JSON), and is given that size multiplied: it
# takes a width and a height and draws the diagram as large; with only
# one of them it takes 1200 or 800 for the other.  A diagram whose
# size is not told is drawn in its own size, and so is any diagram
# when the command has a width or a height of its own.
sub draw_one {
    my($r, $code, $path) = @_;
    my($cmd, $opt) = @{$r}{qw(cmd opt)};
    my $tmp = eval { File::Temp->newdir(DIR => $r->{dir}) } or return 'error';
    my $in  = File::Spec->catfile($tmp, 'in.mmd');
    my $out = File::Spec->catfile($tmp, 'out.png');
    open my $fh, '>:encoding(utf8)', $in or return 'error';
    print $fh $code;
    close $fh;
    my @size;
    if ($r->{scale} and $r->{scale} != 1
	and not grep { /^(?:-w|-H|--(?:width|height)(?:=|$))/ } @$cmd) {
	my $json = File::Spec->catfile($tmp, 'size.json');
	my $status = run({ out => $json }, @$cmd, @$opt, '-i', $in, '--size');
	$status =~ /^(?:ok|fail)$/ or return $status;
	my $size = $status eq 'ok' && eval {
	    open my $fh, '<:raw', $json or die;
	    JSON::PP->new->utf8->decode(do { local $/; <$fh> });
	};
	my($w, $h) = map { $_ * $r->{scale} }
	    grep { defined and !ref and /^[\d.]+$/ and $_ > 0 }
	    ref $size eq 'HASH' ? @{$size}{qw(width height)} : ();
	@size = ('-w', POSIX::ceil($w), '-H', POSIX::ceil($h)) if defined $h;
    }
    my $status = run(@$cmd, @$opt, @size, '-i', $in, '-o', $out);
    -s $out and rename $out, $path;
    $status;
}

# Run a command, without a shell, its output thrown away, or its
# standard output written to the file of { out => FILE } given first.
# Returns 'ok', 'fail', 'timeout', or 'error' when it could not be
# started.
#
# The command is in a process group of its own, which is sent TERM
# when it takes longer than $TIMEOUT, and KILL five seconds later.
# puppeteer starts the browser in a session of its own and closes it
# when mmdc gets TERM; after KILL the browser may stay.  The signals
# of the keyboard do not reach that group, so on INT, TERM or HUP the
# group is sent TERM here and the program exits, which removes the
# temporary files.
sub run {
    my $to = ref $_[0] eq 'HASH' ? shift : {};
    my @cmd = @_;
    my $pid = fork // return 'error';
    if ($pid == 0) {
	setpgrp(0, 0);
	open STDIN,  '<', File::Spec->devnull;
	open STDOUT, '>', $to->{out} // File::Spec->devnull or POSIX::_exit(127);
	open STDERR, '>', File::Spec->devnull;
	exec { $cmd[0] } @cmd or POSIX::_exit(127);
    }
    my %signo = (HUP => 1, INT => 2, TERM => 15);
    local @SIG{keys %signo} = map {
	my $n = $signo{$_};
	sub { kill TERM => -$pid; exit 128 + $n };
    } keys %signo;
    my $status = eval {
	local $SIG{ALRM} = sub { die "timeout\n" };
	alarm $TIMEOUT;
	waitpid $pid, 0;
	alarm 0;
	$?;
    };
    alarm 0;
    defined $status and return $status == 0 ? 'ok' : 'fail';
    kill TERM => -$pid;
    eval {
	local $SIG{ALRM} = sub { die "timeout\n" };
	alarm 5;
	waitpid $pid, 0;
	alarm 0;
	1;
    } or do {
	kill KILL => -$pid;
	waitpid $pid, 0;
    };
    alarm 0;
    'timeout';
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

=item B<diagram_files>(B<codes> => [I<CODE>, ...], B<command> => I<COMMAND>, B<theme> => I<THEME>, B<background> => I<COLOR>, B<scale> => I<N>)

Returns the PNG files of the diagrams, in the order of the codes, and
C<undef> for one that could not be drawn.  They are drawn by
I<COMMAND> (split into words as a shell does), into
F<${XDG_CACHE_HOME:-~/.cache}/mdee/mermaid>, a directory only the user
can read, and are drawn again only when the code, the command or the
theme, the background (default C<transparent>) or the scale (default
3) changes.  Nothing is drawn without C<XDG_CACHE_HOME> or C<HOME>,
or when that directory is a symbolic link or belongs to someone else.

A diagram that fails, or takes more than 60 seconds, leaves an empty
file there and is not tried again for a day, when the command is known
to work: another diagram is drawn, or else a small diagram is drawn to
see.  When the command does not work (it is not found, or has no
browser), nothing is kept, and the diagrams are tried again the next
time.  Diagrams drawn before are shown even when the directory cannot
be written.

I<COMMAND> is C<mmdc> of
L<mermaid-cli|https://github.com/mermaid-js/mermaid-cli> or C<mmdr> of
L<mermaid-rs-renderer|https://github.com/1jehuang/mermaid-rs-renderer>,
and a command whose name (that of its first word, so not with
C<nice> or C<env> before it) starts with C<mmdr> is run as the latter.
Without I<COMMAND>, it is mmdr, or mmdc when only that is found in
C<PATH>.

mmdc draws all the diagrams in one run, and those left by a diagram
that fails one by one.  mmdr has no browser to start and draws each
diagram in a run of its own.  It has no options for the background
and the scale: the background is given as C<themeVariables> in a file
of C<-c>, unless I<COMMAND> has its own C<-c> (C<--configFile>), and
for a scale other than 1 it is first asked for the size of the diagram
(C<--size>) and then given that size multiplied (C<-w>, C<-H>), unless
I<COMMAND> has a width or a height of its own.

mmdc draws in a browser started by puppeteer.  When it does not find
one (the mermaid-cli of Homebrew has none), set
C<PUPPETEER_EXECUTABLE_PATH> to Google Chrome or Chromium.  The browser
is given a proxy that is not there, so that a diagram fetches nothing
from the network; this is not done when I<COMMAND> has its own
C<-p> (C<--puppeteerConfigFile>).

=back

=head1 SEE ALSO

L<App::Greple::md>, L<Text::ANSI::Image>

=head1 LICENSE

This software is released under the MIT License.
L<https://opensource.org/licenses/MIT>

=cut
