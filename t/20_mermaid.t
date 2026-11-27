use strict;
use warnings;
use utf8;
use Test::More;
use open qw(:std :encoding(utf-8));

use File::Temp qw(tempdir);

use lib '.';
use t::Util;

# image_types with mermaid: a fenced code block of mermaid is followed
# by the rows of the image of its diagram, below the closing fence.
# The diagrams are drawn by mermaid_command, a stub here which takes
# the options of mmdc, writes a PNG of 64x102 (4 cells wide, 3 rows
# high in 16x34 cells) for each diagram of its input, and logs its
# arguments.  A diagram with BAD in it stops the run, as mmdc does, and
# FAIL in the environment makes it fail with no diagram drawn.

$ENV{HOME} = my $dir = tempdir(CLEANUP => 1);
delete $ENV{XDG_CACHE_HOME};
my $cache = "$dir/.cache/mdee/mermaid";

my $PH = "\x{10EEEE}";

my $log  = "$dir/log";
my $stub = "$dir/mmdc-stub";
$ENV{STUB_LOG} = $log;
{
    open my $fh, '>', $stub or die;
    print $fh "#!$^X\n", <<'STUB';
use strict;
use warnings;
# A stub of mmdc: -i IN -o OUT.  A Markdown input is split as mmdc
# does, at any line which ends with ``` or :::.  A PNG of 64x102 (3
# rows) is written for each diagram, of 64x170 (5 rows) for one which
# has TALL in it.  A diagram with BAD stops the run, FAIL makes it fail
# at once, SLEEP makes it sleep.
my %opt;
for (my $i = 0; $i < @ARGV; $i++) {
    $opt{$ARGV[$i]} = $ARGV[$i + 1] if $ARGV[$i] =~ /^-[iotp]$/;
}
open my $log, '>>', $ENV{STUB_LOG} or die;
print $log "@ARGV\n";
close $log;
sleep $ENV{SLEEP} if $ENV{SLEEP};
exit 1 if $ENV{FAIL};
open my $in, '<', $opt{-i} or die;
my $text = do { local $/; <$in> };
my(@code, @out);
if ($opt{-i} =~ /\.mmd$/) {
    @code = ($text);
    @out = ($opt{-o});
} else {
    @code = $text =~ /^[^\S\n]*[`:]{3}mermaid[^\S\n]*\n([\s\S]*?)[`:]{3}[^\S\n]*$/mg;
    (my $base = $opt{-o}) =~ s/\.md$//;
    @out = map { "$base-$_.png" } 1 .. @code;
}
for my $n (0 .. $#code) {
    exit 1 if $code[$n] =~ /BAD/;
    my $h = $code[$n] =~ /TALL/ ? 170 : 102;
    open my $png, '>:raw', $out[$n] or die;
    print $png "\x89PNG\r\n\x1a\n", pack('N', 13), 'IHDR',
        pack('NNCCCCC', 64, $h, 8, 6, 0, 0, 0), "\0\0\0\0",
        pack('N', 0), 'IEND', "\xae\x42\x60\x82";
}
STUB
    close $fh;
    chmod 0755, $stub;
}
sub runs { my @l; if (open my $fh, '<', $log) { @l = <$fh> } @l }

sub md {
    my($name, $text) = @_;
    open my $fh, '>:encoding(utf-8)', "$dir/$name" or die;
    print $fh $text;
    close $fh;
    "$dir/$name";
}

my $tty = "$dir/tty";
my $base = 'mode=light';
my $img  = "image_term=80x24:16x34,image_tty=$tty,mermaid_command=$stub";

sub mdee_out {
    my($cfg, $md) = @_;
    unlink $tty;
    run("'-Mmd::config($cfg)' $md")->stdout;
}
sub plain { (my $s = shift) =~ s/\e\[[0-9;]*[mK]//g; $s }

my $doc = md('doc.md', join '',
    "# Title\n\n",
    "```mermaid\nflowchart LR\n  A[入力] --> B\n```\n\n",
    "```perl\nprint 1;\n```\n\n",
    "```mermaid\nsequenceDiagram\n  A->>B: hi\n```\n\n",
    "```mermaid\nflowchart LR\n  A[入力] --> B\n```\n\n",
    "end\n");

# without mermaid in image_types, nothing changes and nothing is drawn
{
    my $out = mdee_out("$base,image_types=png:jpeg:gif,$img", $doc);
    unlike($out, qr/$PH/, 'off: no placeholder');
    is(scalar(runs()), 0, 'off: the command is not run');
}

# the rows of the images below the closing fences
{
    my $out = mdee_out("$base,image_types=mermaid,$img", $doc);
    my @l = split /\n/, plain($out);
    my @fence = grep { $l[$_] eq '```' } keys @l;
    is(scalar @fence, 4, 'the code blocks are kept');
    for my $i (@fence[0, 2, 3]) {
        is(scalar(grep { /$PH/ } @l[$i + 1 .. $i + 3]), 3, "three rows below the fence at line $i");
        unlike($l[$i + 4], qr/$PH/, "no more rows below the fence at line $i");
    }
    unlike($l[$fence[1] + 1], qr/$PH/, 'no rows below a code block of perl');
    ok(-s $tty, 'the data of the images is sent');
    my @runs = runs();
    is(scalar @runs, 1, 'the diagrams are drawn in one run');
    like($runs[0], qr/-b white -s 3 -t default\b/, 'the default theme on white in the light mode, scale 3');
    is(scalar(() = glob "$cache/*.png"), 2, 'two diagrams are kept, the same one once');
}

# drawn once: the second time comes from the cache
{
    unlink $log;
    my $out = mdee_out("$base,image_types=mermaid,$img", $doc);
    is(scalar(() = plain($out) =~ /^$PH/mg), 9, 'cache: the rows are there');
    is(scalar(runs()), 0, 'cache: the command is not run');
}

# the dark theme in the dark mode
{
    unlink $log;
    mdee_out("mode=dark,image_types=mermaid,$img", $doc);
    my @runs = runs();
    like($runs[0] // '', qr/-b #0d1117 .*-t dark\b/, 'the dark theme on the dark background of GitHub in the dark mode');
}

# the theme, the background and the scale are given to the command
{
    unlink $log;
    my $md = md('look.md', "```mermaid\ngraph TD\n  L1 --> L2\n```\n");
    mdee_out("mode=dark,image_types=mermaid,$img,mermaid_theme=neutral,mermaid_background=white,mermaid_scale=3", $md);
    my($run) = runs();
    like($run // '', qr/-b white -s 3 -t neutral\b/, 'mermaid_theme, mermaid_background, mermaid_scale');
}

# a diagram that fails is not shown, and the others are
{
    unlink $log;
    my $md = md('bad.md', join '',
        "```mermaid\ngraph TD\n  X --> Y\n```\n\n",
        "```mermaid\nBAD\n```\n\n",
        "```mermaid\ngraph TD\n  Y --> Z\n```\n");
    my $out = mdee_out("$base,image_types=mermaid,$img", $md);
    is(scalar(() = plain($out) =~ /^$PH/mg), 6, 'bad: the other two are shown');
    is(scalar(runs()), 3, 'bad: the run fails and the other two are drawn one by one');
    is(scalar(grep { -z } glob "$cache/*.png"), 1, 'bad: an empty file is kept for it');
    unlink $log;
    mdee_out("$base,image_types=mermaid,$img", $md);
    is(scalar(runs()), 0, 'bad: it is not tried again');
}

# a diagram that fails first stops the run before any is drawn
{
    unlink $log;
    my $md = md('badfirst.md', join '',
        "```mermaid\nBAD first\n```\n\n",
        "```mermaid\ngraph TD\n  Z --> W\n```\n");
    my $out = mdee_out("$base,image_types=mermaid,$img", $md);
    is(scalar(() = plain($out) =~ /^$PH/mg), 3, 'bad first: the other one is shown');
    unlink $log;
    mdee_out("$base,image_types=mermaid,$img", $md);
    is(scalar(runs()), 0, 'bad first: it is not tried again');
}

# two diagrams that fail do not stop the third
{
    unlink $log;
    my $md = md('badtwo.md', join '',
        "```mermaid\nBAD one\n```\n\n",
        "```mermaid\nBAD two\n```\n\n",
        "```mermaid\ngraph TD\n  V --> W\n```\n");
    my $out = mdee_out("$base,image_types=mermaid,$img", $md);
    is(scalar(() = plain($out) =~ /^$PH/mg), 3, 'bad two: the third is shown');
    unlink $log;
    mdee_out("$base,image_types=mermaid,$img", $md);
    is(scalar(runs()), 0, 'bad two: they are not tried again');
}

# a diagram that fails, when the others were drawn before, is kept as
# failed too, and is tried again when its empty file is old
{
    unlink $log;
    my $md = md('later.md', join '',
        "```mermaid\ngraph TD\n  V --> W\n```\n\n",
        "```mermaid\nBAD later\n```\n");
    mdee_out("$base,image_types=mermaid,$img", $md);
    is(scalar(runs()), 2, 'later: the diagram and a probe');
    unlink $log;
    mdee_out("$base,image_types=mermaid,$img", $md);
    is(scalar(runs()), 0, 'later: not tried again');
    # all the empty files, whichever is the one of this diagram
    my $old = time - 2 * 24 * 60 * 60;
    utime $old, $old, grep { -z } glob "$cache/*.png" or die;
    mdee_out("$base,image_types=mermaid,$img", $md);
    is(scalar(runs()), 2, 'later: tried again after a day');
}

# a <!-- inside a code block starts no comment
{
    my $md = md('incode.md', join '',
        "```html\n<!-- start\n```\n\n",
        "```mermaid\ngraph TD\n  I --> J\n```\n\n",
        "<!-- real -->\n");
    like(mdee_out("$base,image_types=mermaid,$img", $md), qr/$PH/, 'a <!-- in a code block hides no diagram');
}

# when the command draws none, nothing is kept, so that they are drawn
# once it works
{
    unlink $log;
    my $md = md('fail.md', "```mermaid\ngraph TD\n  P --> Q\n```\n");
    local $ENV{FAIL} = 1;
    unlike(mdee_out("$base,image_types=mermaid,$img", $md), qr/$PH/, 'fail: not shown');
    delete $ENV{FAIL};
    like(mdee_out("$base,image_types=mermaid,$img", $md), qr/$PH/, 'fail: shown when the command works');
    is(scalar(runs()), 3, 'fail: the diagram and a probe, then tried again');
}

# intact=image: the closing fence and the rows are joined by GS
{
    my $out = mdee_out("$base,image_types=mermaid,$img,intact=image", $doc);
    my @l = split /\n/, plain($out);
    my @line = grep { /$PH/ } @l;
    is(scalar @line, 3, 'intact=image: one line for each diagram');
    like($line[0], qr/^(?:[^\x1D]*$PH[^\x1D]*\x1D){2}[^\x1D]*$PH[^\x1D]*$/, 'intact=image: three rows joined by GS');
    my($i) = grep { $l[$_] =~ /$PH/ } keys @l;
    is($l[$i - 1], '```', 'intact=image: the closing fence is a line of its own');
}

# with refill, the paragraph below a diagram is joined and folded, and
# the rows are not folded
SKIP: {
    require App::Greple::md::Blocks;
    App::Greple::md::Blocks::available() or skip 'no parser for refill', 2;
    my $md = md('refill.md', join '',
        "```mermaid\nflowchart LR\n  A[入力] --> B\n```\n\n",
        "aaaa bbbb cccc\ndddd eeee ffff\n\nend\n");
    my $out = mdee_out("$base,image_types=mermaid,$img,refill=1,fold=1,fold_width=10", $md);
    my @l = split /\n/, plain($out);
    my @text = grep { /[a-f]{4}/ } @l;
    is_deeply([ map { s/\h+$//r } @text ], [ 'aaaa bbbb', 'cccc dddd', 'eeee ffff' ],
              'refill: the paragraph below the diagram is joined and folded');
    is(scalar(grep { /$PH/ && !/^(?:$PH.{2}){4}$/ } @l), 0, 'refill: the rows are not folded');
}

# a paragraph above a diagram stays where it is: the rows are counted
# from the line of the closing fence
SKIP: {
    App::Greple::md::Blocks::available() or skip 'no parser for refill', 1;
    my $md = md('above.md', join '',
        "# Title\n\n",
        "aaaa bbbb cccc\ndddd eeee ffff\n\n",
        "```mermaid\nflowchart LR\n  A[入力] --> B\n```\n\nend\n");
    my $out = mdee_out("$base,image_types=mermaid,$img,refill=1,fold=1,fold_width=10", $md);
    my @text = grep { /[a-f]{4}/ } split /\n/, plain($out);
    is_deeply([ map { s/\h+$//r } @text ], [ 'aaaa bbbb', 'cccc dddd', 'eeee ffff' ],
              'refill: the paragraph above the diagram is joined and folded');
}

# a body with a line which ends with ``` or ::: is drawn from a file
# of its own: in the Markdown file for mmdc it would end the diagram
{
    unlink $log;
    my $md = md('ambiguous.md', join '',
        "````mermaid\ngraph TD\n  A --> B\n  %% not the end :::\n  TALL\n````\n\n",
        "```mermaid\ngraph TD\n  C --> D\n```\n\n",
        "```mermaid\ngraph TD\n  C --> E\n```\n");
    my $out = mdee_out("$base,image_types=mermaid,$img", $md);
    is(scalar(() = plain($out) =~ /^$PH/mg), 11, 'ambiguous: five rows, and three rows twice');
    my @runs = runs();
    is(scalar(grep { /\.mmd\b/ } @runs), 1, 'ambiguous: drawn alone from a .mmd file');
    is(scalar(grep { /\.md\b/ } @runs), 1, 'ambiguous: the others in one run');
    require App::Greple::md::Mermaid;
    ok(App::Greple::md::Mermaid::ambiguous("A:::\rmore\n"), 'ambiguous: ::: before CR');
    ok(App::Greple::md::Mermaid::ambiguous("A```\x{2028}more\n"), 'ambiguous: ``` before U+2028');
    ok(!App::Greple::md::Mermaid::ambiguous("A:::B\n  C --> D\n"), 'ambiguous: not ::: inside a line');
}

# a block of mermaid inside an HTML comment is not drawn
{
    unlink $log;
    my $md = md('comment.md', "<!--\n```mermaid\ngraph TD\n  E --> F\n```\n-->\n\ntext\n");
    my $out = mdee_out("$base,image_types=mermaid,$img", $md);
    unlike($out, qr/$PH/, 'comment: not drawn');
    is(scalar(runs()), 0, 'comment: the command is not run');
}

# when the command does not work, it is not run for every diagram
{
    unlink $log;
    my $md = md('broken.md', join '', map { "```mermaid\ngraph TD\n  G$_ --> H\n```\n\n" } 1 .. 5);
    local $ENV{FAIL} = 1;
    mdee_out("$base,image_types=mermaid,$img", $md);
    is(scalar(runs()), 3, 'broken: one run for all, one alone and a probe, not one for each');
}

# the browser goes to the network through a proxy that is not there,
# unless the command has its own options of puppeteer
{
    unlink $log;
    my $md = md('proxy.md', "```mermaid\ngraph TD\n  P1 --> Q1\n```\n");
    mdee_out("$base,image_types=mermaid,$img", $md);
    my($run) = runs();
    my($json) = ($run // '') =~ /-p (\S+)/;
    ok($json, 'proxy: -p is given');
    unlink $log;
    $md = md('proxy2.md', "```mermaid\ngraph TD\n  P2 --> Q2\n```\n");
    mdee_out("$base,image_types=mermaid,image_term=80x24:16x34,image_tty=$tty,mermaid_command=$stub -p /my/config.json", $md);
    ($run) = runs();
    is(scalar(() = ($run // '') =~ /-p /g), 1, 'proxy: not given with -p of the command');
    is((stat $cache)[2] & 0777, 0700, 'the cache is private to the user');
}

# a command with a space in its path, quoted
{
    unlink $log;
    mkdir "$dir/with space";
    symlink $stub, "$dir/with space/mmdc" or die;
    my $md = md('space.md', "```mermaid\ngraph TD\n  S --> T\n```\n");
    my $out = mdee_out("$base,image_types=mermaid,image_term=80x24:16x34,image_tty=$tty,mermaid_command=\"$dir/with space/mmdc\"", $md);
    like($out, qr/$PH/, 'a quoted path with a space');
}

# an unwritable cache: the text is shown, without the diagram
SKIP: {
    skip 'root can write anywhere', 2 if $> == 0;
    local $ENV{XDG_CACHE_HOME} = "$dir/ro";
    mkdir "$dir/ro"; mkdir "$dir/ro/mdee"; mkdir "$dir/ro/mdee/mermaid";
    chmod 0500, "$dir/ro/mdee/mermaid";
    my $md = md('ro.md', "```mermaid\ngraph TD\n  R --> O\n```\n\nafter\n");
    my $out = mdee_out("$base,image_types=mermaid,$img", $md);
    like($out, qr/after/, 'unwritable cache: the text is shown');
    unlike($out, qr/$PH/, 'unwritable cache: no diagram');
    chmod 0700, "$dir/ro/mdee/mermaid";
}

# a run that takes too long is killed, and nothing is kept
{
    require App::Greple::md::Mermaid;
    no warnings 'once';
    local $App::Greple::md::Mermaid::TIMEOUT = 1;
    local $ENV{SLEEP} = 30;
    unlink $log;
    my $t = time;
    my @f = App::Greple::md::Mermaid::diagram_files(
        codes => [ "graph TD\n  T1 --> T2\n", "graph TD\n  T3 --> T4\n" ],
        command => $stub);
    ok(time - $t < 15, 'timeout: the run is killed');
    ok(!defined $f[0] && !defined $f[1], 'timeout: not drawn');
    is(scalar(runs()), 3, 'timeout: one run for all, one alone and a probe, no more');
    delete $ENV{SLEEP};
    @f = App::Greple::md::Mermaid::diagram_files(
        codes => [ "graph TD\n  T1 --> T2\n" ], command => $stub);
    ok(defined $f[0], 'timeout: nothing kept, drawn the next time');
}

# an interrupt stops the command and leaves no temporary file
SKIP: {
    require App::Greple::md::Mermaid;
    local $ENV{SLEEP} = 30;
    unlink $log;
    my $pid = fork // skip 'no fork', 2;
    if ($pid == 0) {
        App::Greple::md::Mermaid::diagram_files(
            codes => [ "graph TD\n  I1 --> I2\n" ], command => $stub);
        exit 0;
    }
    for (1 .. 50) { last if runs(); select undef, undef, undef, 0.1 }
    kill INT => $pid;
    waitpid $pid, 0;
    is($? >> 8, 130, 'interrupt: exits as by INT');
    select undef, undef, undef, 0.5;
    my @left = grep { !/\.png$/ } glob "$cache/*";
    is(scalar @left, 0, 'interrupt: no temporary file is left');
}

done_testing;
