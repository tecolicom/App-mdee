package App::Greple::md::Mermaid;

# The images of the Mermaid diagrams of a Markdown file.  They are
# drawn by a command (mmdr of mermaid-rs-renderer, or mmdc of
# mermaid-cli) into PNG files in a directory of the temporary
# directory, and are shown by Text::ANSI::Image as the other images
# are.

use v5.26;
use warnings;
use utf8;

use Exporter 'import';
our @EXPORT_OK = qw(diagram_files);

use Encode qw(encode_utf8 decode);
use File::Basename qw(basename);
use Digest::SHA qw(sha1_hex);
use File::Spec;
use File::Temp ();
use JSON::PP ();
use POSIX ();
use Text::ParseWords qw(shellwords);

# The commands which draw, in the order they are looked for in PATH
# when none is given; the first when none is found.  $COMMAND, when
# set, is used in place of them.
our @COMMANDS = qw(mmdc mmdr);
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

# Whether the command is mmdr, by its name: mmdr has other options
# than mmdc (no -b, -s, -q or -p) and draws without a browser
sub is_mmdr { kind($_[0]) eq 'mmdr' }

# The kind of the command, by its name: mmdr, mermaidx (of PyPI, which
# runs mermaid.js in Python, without a browser), or mmdc for any other
sub kind {
    my $name = (File::Spec->splitpath($_[0] // ''))[2];
    $name =~ /^mmdr/i     ? 'mmdr'
  : $name =~ /^mermaidx/i ? 'mermaidx'
  :                         'mmdc';
}

# The options of puppeteer given to mmdc: the browser goes to the
# network only through a proxy that is not there, so that a diagram
# cannot fetch anything (a remote image in a node) when it is drawn.
# Nothing is fetched from the network, as for the other images.
our %PUPPETEER = (
    args => [ '--proxy-server=http://127.0.0.1:9', '--proxy-bypass-list=<-loopback>' ],
);

# The browsers that mmdc is given, the first found, when
# PUPPETEER_EXECUTABLE_PATH is not set: puppeteer looks only for its
# own, which the mermaid-cli of Homebrew does not have.  A name
# without a slash is looked for in PATH.
our @BROWSERS = (
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    '/Applications/Chromium.app/Contents/MacOS/Chromium',
    qw(google-chrome google-chrome-stable chromium chromium-browser),
);

sub browser {
    return if $ENV{PUPPETEER_EXECUTABLE_PATH};
    for my $name (@BROWSERS) {
	for my $file ($name =~ m{/} ? $name
		      : map { File::Spec->catfile($_, $name) } File::Spec->path) {
	    return $file if -f $file and -x _;
	}
    }
    return;
}

# The directory of the drawn diagrams, mdee-mermaid-UID in the
# temporary directory, or undef when there is no place for it: a real
# directory of the user, not a symbolic link, which nobody else can
# read, for /tmp is shared.  A diagram is kept by the digest of the
# command, its options and the code, so that the same diagram is the
# same file, and is drawn once.  The files stay after mdee ends, which
# they must on paper, where ansi2pdf reads them after greple, and are
# left for the system to clean up; one that is gone is drawn again.
sub cache_dir {
    my $dir = File::Spec->catdir(File::Spec->tmpdir, "mdee-mermaid-$>");
    -e $dir or mkdir $dir, 0700;
    my @st = lstat $dir or return;
    -d _ && $st[4] == $> or return;
    if ($st[2] & 077) {
	chmod $st[2] & 0700, $dir or return;
    }
    $dir;
}

# The PNG files of the diagrams, in the order of the codes; undef for
# one that could not be drawn.
#
#   codes   => [ CODE, ... ]   the text of each diagram
#   command => 'mmdc ...'      the command, split as a shell does; one
#                              whose name starts with mmdr is run as mmdr
#   theme   => 'default'       the theme of Mermaid (dark in the dark mode)
#   background => 'transparent'  the background, a color of CSS
#   scale   => 1.5             the scale of the image: the larger, the
#                              more cells it takes, up to the width
#
# Each diagram is drawn in a run of its own, but mmdc, which starts a
# browser for each run, draws all that are to be drawn in one run
# first, and those it could not one by one.  mmdc is given the look
# by its options, and the options of puppeteer (%PUPPETEER) in a file
# of -p.  mmdr has no options for the background and the scale: the
# background goes in a file of -c, and the size is asked for first
# and given multiplied (see draw).  The file is not given when the
# command has its own.  A diagram that cannot be drawn is not shown,
# and is tried again the next time.
sub diagram_files {
    my %opt = @_;
    my @codes = @{$opt{codes} // []} or return ();
    my $dir = cache_dir() // return (undef) x @codes;
    my @cmd = shellwords($opt{command} || $COMMAND || default_command());
    @cmd or return (undef) x @codes;
    my $kind = kind($cmd[0]);
    my $mmdr = $kind eq 'mmdr';
    my $background = $opt{background} || 'transparent';
    my $scale = $opt{scale} || 1.5;
    my $theme = $opt{theme} || 'default';
    # what the digest is made of, which are also the options of mmdc
    my @look = ('-t', $theme, '-b', $background, '-s', $scale);
    my $r = { dir => $dir, cmd => \@cmd,
	      opt => {
		  mmdr     => [ '-e', 'png', '-t', $theme ],
		  mmdc     => [ '-e', 'png', '-q', @look ],
		  # PNG by the name of the output file
		  mermaidx => [ '-q', '-t', $theme, '-b', $background, '--scale', $scale ],
	      }->{$kind},
	      $mmdr ? (scale => $scale) : () };
    # a file of options: the background for mmdr, the browser for mmdc
    my($flag, $own, $data) = @{ {
	mmdr => [ '-c', qr/^(?:-c|--configFile(?:=|$))/,
		  { themeVariables => { background => "$background" } } ],
	mmdc => [ '-p', qr/^(?:-p|--puppeteerConfigFile(?:=|$))/,
		  { %PUPPETEER, map { (executablePath => $_) } browser() } ],
    }->{$kind} // [] };
    # the file of each diagram, by the digest
    my @path = map {
	File::Spec->catfile($dir,
	    sha1_hex(encode_utf8(join "\0", @cmd, @look, s/\n?\z/\n/r)) . '.png');
    } @codes;
    # those to be drawn, once each; without a place to write, the
    # diagrams drawn before are shown
    my(%seen, @todo);
    if (-w $dir) {
	for my $i (0 .. $#codes) {
	    push @todo, [ $path[$i], $codes[$i] =~ s/\n?\z/\n/r ]
		if !-e $path[$i] and !$seen{$path[$i]}++;
	}
    }
    my(%error, $conf);
    if (@todo) {
	# the file of options, after the digest, which must not depend
	# on the name of the file
	if ($flag and not grep { /$own/ } @cmd) {
	    $conf = config_file($dir, $data);
	    push @{$r->{opt}}, $flag, "$conf" if $conf;
	}
	my $progress = progress(basename($cmd[0]));
	my $diagrams = sub { "$_[0] Mermaid diagram" . ($_[0] > 1 ? 's' : '') };
	$progress->('drawing ' . $diagrams->(scalar @todo) . '...');
	# mmdc starts a browser for each run: all in one run first
	draw_all($r, $progress, @todo) if $kind eq 'mmdc' and @todo > 1;
	my @left = grep { !-s $_->[0] } @todo;
	for my $n (1 .. @left) {
	    my($path, $code) = @{$left[$n - 1]};
	    $progress->("drawing Mermaid diagram $n of " . @left . '...') if @left > 1;
	    $error{$path} = draw($r, $code, $path);
	}
	$progress->();
    }
    map {
	my $path = $path[$_];
	# what the command said when it failed, for the author to see
	if ($opt{errors} and defined $error{$path} and $error{$path} ne '') {
	    $opt{errors}[$_] = [ basename($cmd[0]), split /\n/, $error{$path} ];
	}
	-s $path ? $path : undef;
    } 0 .. $#codes;
}

# Lines on the terminal while the diagrams are drawn, which may take
# seconds with mmdc, so that one knows that something is going on:
# shown on the standard error when it is a terminal, a line for each
# step, with the seconds gone by on the line of the last.  Returns a
# function to call with the text that follows the name of the command,
# and with nothing at the end.  run() calls $TICK every tenth of a
# second while it waits, which puts the seconds again when they have
# changed.
our $TICK;
sub progress {
    my $name = shift;
    -t STDERR or return sub {};
    my $start = time;
    my($text, $sec) = ('', 0);
    my $line = sub {
	print STDERR "\r\e[K$name: $text", $sec ? " (${sec}s)" : '';
    };
    $TICK = sub {
	my $s = time - $start;
	$line->() if length $text and $s != $sec and ($sec = $s);
    };
    sub {
	if (@_) {
	    return if $_[0] eq $text;
	    print STDERR "\n" if length $text;
	    $text = shift;
	    $line->();
	} else {
	    undef $TICK;
	    print STDERR "\n" if length $text;
	}
    };
}

# Draw the diagrams in one run of mmdc, from a Markdown file of their
# code blocks, which it draws into OUT-1.png, OUT-2.png and so on.  It
# draws none when one has an error, and the diagrams are then drawn
# one by one, which tells the error of each.  A code with a fence of
# its own is not put in the file.
#
# Without -q, it writes a line with OUT-N.png when it has drawn one,
# which the line on the terminal counts.
sub draw_all {
    my($r, $progress, @todo) = @_;
    return if grep { $_->[1] =~ /^\h*(?:```|~~~)/m } @todo;
    my($cmd, $opt) = @{$r}{qw(cmd opt)};
    my $tmp = eval { File::Temp->newdir(DIR => $r->{dir}) } or return;
    my $in  = File::Spec->catfile($tmp, 'in.md');
    my $out = File::Spec->catfile($tmp, 'out.md');
    my $log = File::Spec->catfile($tmp, 'log.txt');
    open my $fh, '>:encoding(utf8)', $in or return;
    print $fh map { "```mermaid\n$_->[1]```\n\n" } @todo;
    close $fh;
    my $count = @todo;
    local $TICK = $TICK && do {
	my $tick = $TICK;
	sub {
	    my $done = 0;
	    if (open my $l, '<:raw', $log) {
		$done = grep { /out-\d+\.png\s*$/ } <$l>;
	    }
	    $progress->("$done of $count drawn") if $done;
	    $tick->();
	};
    };
    run({ out => $log }, @$cmd, grep({ $_ ne '-q' } @$opt), '-i', $in, '-o', $out)
	or return;
    for my $n (1 .. @todo) {
	my $png = File::Spec->catfile($tmp, "out-$n.png");
	rename $png, $todo[$n - 1][0] if -s $png;
    }
}

# A file of options in JSON, removed with the object
sub config_file {
    my($dir, $data) = @_;
    my $fh = eval { File::Temp->new(DIR => $dir, SUFFIX => '.json') } or return;
    print $fh JSON::PP->new->utf8->canonical->encode($data), "\n";
    close $fh;
    $fh;
}

# Draw one diagram from a file of its own.  With a scale (mmdr), the
# command is first asked for the size of the diagram (--size prints it in
# JSON), and is given that size multiplied: it takes a width and a
# height and draws the diagram as large; with only one of them it
# takes 1200 or 800 for the other.  A diagram whose size is not told
# is drawn in its own size, and so is any diagram when the command has
# a width or a height of its own.  Returns undef when it is drawn, or
# else what the command wrote to the standard error, without control
# characters.
sub draw {
    my($r, $code, $path) = @_;
    my($cmd, $opt) = @{$r}{qw(cmd opt)};
    my $tmp = eval { File::Temp->newdir(DIR => $r->{dir}) } or return '';
    my $in  = File::Spec->catfile($tmp, 'in.mmd');
    my $out = File::Spec->catfile($tmp, 'out.png');
    my $err = File::Spec->catfile($tmp, 'err.txt');
    open my $fh, '>:encoding(utf8)', $in or return '';
    print $fh $code;
    close $fh;
    my @size;
    if ($r->{scale} and $r->{scale} != 1
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
    if (run({ err => $err }, @$cmd, @$opt, @size, '-i', $in, '-o', $out)
	and -s $out and rename($out, $path)) {
	return undef;
    }
    open my $e, '<:raw', $err or return '';
    my $text = decode('UTF-8', do { local $/; <$e> } // '');
    $text =~ s/\e(?:\[[0-9;?]*[ -\/]*[\@-~]|\][^\a\e]*(?:\a|\e\\)?|.)//gs;
    $text =~ s/\r?\n/\n/g;
    $text =~ s/\t/ /g;
    $text =~ s/[\x00-\x09\x0b-\x1f\x7f\x{80}-\x{9f}]//g;
    # the stack of JavaScript (mmdc) is not for the author: it starts
    # with a line of "at FUNCTION (FILE)", or of "FUNCTION (URL)"
    $text =~ s/^(?:\h+at\h(?:.*\()?|\S+\h\()(?:file|https?|node):.*//ms;
    # nor that of Python (mermaidx): the error at its end, without the
    # name of the exception which carries it
    if ($text =~ /^Traceback \(most recent call last\):/m) {
	$text =~ s/\A.*^[\w.]+(?:Error|Exception): (?:Mermaid rendering failed: )?//ms;
    }
    $text =~ s/\A\n+|\s+\z//g;
    # a long one, as a panic with its backtrace, is cut to ten lines
    my @line = split /\n/, $text;
    join "\n", @line > 10 ? (@line[0..9], '...') : @line;
}

# Run a command, without a shell, its output thrown away, or its
# standard output and standard error written to the files of
# { out => FILE, err => FILE } given first.
# True when it ends with success.
sub run {
    my $to = ref $_[0] eq 'HASH' ? shift : {};
    my @cmd = @_;
    my $pid = fork // return;
    if ($pid == 0) {
	open STDIN,  '<', File::Spec->devnull;
	open STDOUT, '>', $to->{out} // File::Spec->devnull or POSIX::_exit(127);
	open STDERR, '>', $to->{err} // File::Spec->devnull;
	# a command which is not there says nothing: it is not a fault
	# of the text
	no warnings 'exec';
	exec { $cmd[0] } @cmd or POSIX::_exit(127);
    }
    if ($TICK) {
	until (waitpid($pid, POSIX::WNOHANG()) == $pid) {
	    select undef, undef, undef, 0.1;
	    $TICK->();
	}
    } else {
	waitpid $pid, 0;
    }
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

=item B<diagram_files>(B<codes> => [I<CODE>, ...], B<command> => I<COMMAND>, B<theme> => I<THEME>, B<background> => I<COLOR>, B<scale> => I<N>, B<errors> => I<ARRAYREF>)

Returns the PNG files of the diagrams, in the order of the codes, and
C<undef> for one that could not be drawn.  They are drawn by
I<COMMAND> (split into words as a shell does; default C<mmdc> of
L<mermaid-cli|https://github.com/mermaid-js/mermaid-cli>, or C<mmdr>
of L<mermaid-rs-renderer|https://github.com/1jehuang/mermaid-rs-renderer>
when only that is found in C<PATH>; a command whose name starts with
C<mmdr> is run as C<mmdr>, one with C<mermaidx> as C<mermaidx> of
L<PyPI|https://pypi.org/project/mermaidx/>, and any other as C<mmdc>),
into F<mdee-mermaid-I<UID>> of the temporary directory (C<TMPDIR>, or
F</tmp>), a directory only the user can read, and are drawn again only
when the code, the command or the theme, the background (default
C<transparent>) or the scale (default 1.5) changes, or when the file is
gone: the files are left for the system to clean up.  Nothing is
drawn when that directory is a symbolic link or belongs to someone
else.  Diagrams drawn before are shown even when the directory
cannot be written.

Each diagram is drawn in a run of its own.  mmdc, which starts a
browser for each run, is first given all the diagrams to be drawn in
one Markdown file, and draws each in a run of its own only when that
fails, as it does when one of them has an error.  mmdr has no options for
the background and the scale: the background is given as
C<themeVariables> in a file of C<-c>, unless I<COMMAND> has its own
C<-c> (C<--configFile>), and for a scale other than 1 it is first
asked for the size of the diagram (C<--size>) and then given that size
multiplied (C<-w>, C<-H>), unless I<COMMAND> has a width or a height
of its own.

A diagram that cannot be drawn is not shown, and is tried again the
next time.  With B<errors>, what the command wrote to the standard
error then is put in the array, at the index of the code, as
C<[NAME, LINE, ...]>: the name of the command and the lines, without
control characters and escape sequences, and without the stack of
JavaScript that B<mmdc> writes after its error, ten at most.  A command that
is not installed, or that fails without a word, puts nothing.

I<COMMAND> is C<mmdr> of
L<mermaid-rs-renderer|https://github.com/1jehuang/mermaid-rs-renderer>
or C<mmdc> of L<mermaid-cli|https://github.com/mermaid-js/mermaid-cli>,
or C<mermaidx> of L<PyPI|https://pypi.org/project/mermaidx/>, and a
command whose name (that of its first word, so not with C<nice> or
C<env> before it) starts with C<mmdr> or C<mermaidx> is run as that
one, and any other as mmdc.  mermaidx, which runs mermaid.js in
Python without a browser, is given the look by its options (C<-t>,
C<-b>, C<--scale>) and no file of options, and the traceback of
Python before its error is left out of the message.
Without I<COMMAND>, it is mmdc, which is Mermaid itself and draws
the diagrams as GitHub does, or mmdr when only that is found in
C<PATH>.

mmdc is given the look by its options (C<-b>, C<-s>, C<-t>), and
draws in a browser started by puppeteer, which looks only for its
own (the mermaid-cli of Homebrew has none): unless
C<PUPPETEER_EXECUTABLE_PATH> is set, it is given Google Chrome or
Chromium, the first found of C<@BROWSERS> (the applications of macOS,
and C<google-chrome>, C<google-chrome-stable>, C<chromium> and
C<chromium-browser> in C<PATH>), as C<executablePath>.  The browser is given a proxy that is
not there, so that a diagram fetches nothing from the network; this
is not done when I<COMMAND> has its own C<-p>
(C<--puppeteerConfigFile>).

=back

=head1 SEE ALSO

L<App::Greple::md>, L<Text::ANSI::Image>

=head1 LICENSE

This software is released under the MIT License.
L<https://opensource.org/licenses/MIT>

=cut
