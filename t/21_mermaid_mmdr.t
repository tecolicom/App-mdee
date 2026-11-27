use strict;
use warnings;
use utf8;
use Test::More;
use open qw(:std :encoding(utf-8));

use File::Temp qw(tempdir);

use lib '.';
use t::Util;

# image_types with mermaid and a mermaid_command whose name starts
# with mmdr (mermaid-rs-renderer): the command has other options than
# mmdc, so it is given no -q, -b, -s or -p, the background in a file
# of -c, and the size of the diagram multiplied by the scale, which it
# is asked for first with --size.  Each diagram is drawn in a run of
# its own, from a .mmd file.  The stub here fails on an option that
# mmdr does not have, tells 64x34 as the size of a diagram, writes a
# PNG of the size it is given, and logs its arguments and the file of
# -c.

$ENV{HOME} = my $dir = tempdir(CLEANUP => 1);
delete $ENV{XDG_CACHE_HOME};
my $cache = "$dir/.cache/mdee/mermaid";

my $PH = "\x{10EEEE}";

my $log  = "$dir/log";
my $stub = "$dir/mmdr-stub";
$ENV{STUB_LOG} = $log;
{
    open my $fh, '>', $stub or die;
    print $fh "#!$^X\n", <<'STUB';
use strict;
use warnings;
my(%opt, $size);
while (@ARGV) {
    my $o = shift;
    if    ($o eq '--size')         { $size = 1 }
    elsif ($o =~ /^-[ioetcwH]$/)   { $opt{$o} = shift }
    else                           { exit 2 }
}
my $conf = '';
if (defined $opt{-c}) {
    open my $c, '<', $opt{-c} or exit 2;
    chomp($conf = do { local $/; <$c> });
}
open my $log, '>>', $ENV{STUB_LOG} or die;
print $log join(' ', map { "$_ $opt{$_}" } grep { defined $opt{$_} } qw(-i -o -e -t -w -H)),
    $size ? ' --size' : '', " conf=$conf\n";
close $log;
exit 1 if $ENV{FAIL};
$opt{-i} =~ /\.mmd$/ or exit 2;
open my $in, '<', $opt{-i} or die;
my $text = do { local $/; <$in> };
exit 1 if $text =~ /BAD/;
if ($size) {
    print $ENV{NOSIZE} ? "?\n" : qq({\n  "width": 64.0,\n  "height": 33.5\n}\n);
    exit 0;
}
my($w, $h) = ($opt{-w} // 64, $opt{-H} // 34);
open my $png, '>:raw', $opt{-o} or die;
print $png "\x89PNG\r\n\x1a\n", pack('N', 13), 'IHDR',
    pack('NNCCCCC', $w, $h, 8, 6, 0, 0, 0), "\0\0\0\0",
    pack('N', 0), 'IEND', "\xae\x42\x60\x82";
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
my $term = "image_term=80x24:16x34,image_tty=$tty";
my $img  = "$term,mermaid_command=$stub";

sub mdee_out {
    my($cfg, $md) = @_;
    unlink $tty;
    run("'-Mmd::config($cfg)' $md")->stdout;
}
sub plain { (my $s = shift) =~ s/\e\[[0-9;]*[mK]//g; $s }

my $doc = md('doc.md', join '',
    "```mermaid\nflowchart LR\n  A[入力] --> B\n```\n\n",
    "```mermaid\nsequenceDiagram\n  A->>B: hi\n  %% not the end :::\n```\n\n",
    "end\n");

# each diagram in two runs, for its size and for the image, which is
# 192x102 (64x34 by the scale 3): 12 cells wide, 3 rows high
{
    my $out = mdee_out("mode=light,image_types=mermaid,$img", $doc);
    is(scalar(() = plain($out) =~ /^$PH/mg), 6, 'three rows for each diagram');
    my @runs = runs();
    is(scalar @runs, 4, 'two runs for each diagram');
    is(scalar(grep { /-i \S+\.mmd / } @runs), 4, 'from a .mmd file each');
    is(scalar(grep { / --size / } @runs), 2, 'the size is asked for');
    my($draw) = grep { !/ --size / } @runs;
    like($draw, qr/-e png -t default -w 192 -H 101 /, 'the theme, and the size by the scale 3');
    like($draw, qr/conf=\{"themeVariables":\{"background":"white"\}\}$/, 'the background in the file of -c');
    is(scalar(() = glob "$cache/*.png"), 2, 'two diagrams are kept');
    is(scalar(grep { !/\.png$/ } glob "$cache/*"), 0, 'no temporary file is left');
}

# drawn once
{
    unlink $log;
    my $out = mdee_out("mode=light,image_types=mermaid,$img", $doc);
    is(scalar(() = plain($out) =~ /^$PH/mg), 6, 'cache: the rows are there');
    is(scalar(runs()), 0, 'cache: the command is not run');
}

# the dark mode, and the look by the config: drawn again
{
    unlink $log;
    mdee_out("mode=dark,image_types=mermaid,$img", $doc);
    my($draw) = grep { !/ --size / } runs();
    like($draw // '', qr/-t dark .*"background":"#0d1117"/, 'the dark theme on the dark background');
    unlink $log;
    mdee_out("mode=light,image_types=mermaid,$img,mermaid_theme=forest,mermaid_background=#fff,mermaid_scale=2", $doc);
    ($draw) = grep { !/ --size / } runs();
    like($draw // '', qr/-t forest -w 128 -H 67 .*"background":"#fff"/, 'mermaid_theme, mermaid_background, mermaid_scale');
}

# with the scale 1 the size is not asked for
{
    unlink $log;
    mdee_out("mode=light,image_types=mermaid,$img,mermaid_scale=1", $doc);
    my @runs = runs();
    is(scalar @runs, 2, 'scale 1: one run for each diagram');
    unlike($runs[0], qr/ -w | --size /, 'scale 1: no size');
}

# a size that is not told: the diagram is drawn in its own size
{
    unlink $log;
    local $ENV{NOSIZE} = 1;
    my $md = md('nosize.md', "```mermaid\ngraph TD\n  N1 --> N2\n```\n");
    my $out = mdee_out("mode=light,image_types=mermaid,$img", $md);
    like($out, qr/$PH/, 'no size: drawn');
    my($draw) = grep { !/ --size / } runs();
    unlike($draw, qr/ -w /, 'no size: no -w');
}

# the command with -c of its own is given no other
{
    unlink $log;
    my $own = md('own.json', qq({"themeVariables":{"background":"#123456"}}\n));
    my $md = md('own.md', "```mermaid\ngraph TD\n  O1 --> O2\n```\n");
    my $out = mdee_out("mode=light,image_types=mermaid,$term,mermaid_command=$stub -c $own", $md);
    like($out, qr/$PH/, 'own -c: drawn');
    is(scalar(grep { !/#123456/ } runs()), 0, 'own -c: the file of the command is used');
}

# the command with a width of its own is not asked for the size
{
    unlink $log;
    my $md = md('width.md', "```mermaid\ngraph TD\n  W1 --> W2\n```\n");
    mdee_out("mode=light,image_types=mermaid,$term,mermaid_command=$stub -w 320", $md);
    my @runs = runs();
    is(scalar @runs, 1, 'own -w: one run');
    like($runs[0], qr/ -w 320 conf=/, 'own -w: the width of the command, and no -H');
}

# a diagram that fails is kept as an empty file, and the other is shown
{
    unlink $log;
    my $md = md('bad.md', join '',
        "```mermaid\nBAD\n```\n\n",
        "```mermaid\ngraph TD\n  G1 --> G2\n```\n");
    my $out = mdee_out("mode=light,image_types=mermaid,$img", $md);
    is(scalar(() = plain($out) =~ /^$PH/mg), 3, 'bad: the other diagram is shown');
    is(scalar(grep { -z } glob "$cache/*.png"), 1, 'bad: kept as an empty file');
    unlink $log;
    mdee_out("mode=light,image_types=mermaid,$img", $md);
    is(scalar(runs()), 0, 'bad: not tried again');
}

# when the command does not work, nothing is kept, and it is not run
# for every diagram: the first diagram and the probe
{
    unlink $log;
    my $md = md('broken.md', join '', map { "```mermaid\ngraph TD\n  H$_ --> I\n```\n\n" } 1 .. 5);
    my $n = () = glob "$cache/*.png";
    local $ENV{FAIL} = 1;
    mdee_out("mode=light,image_types=mermaid,$img", $md);
    is(scalar(runs()), 4, 'broken: one diagram and the probe (the size and the image each), not one for each');
    is(scalar(() = glob "$cache/*.png"), $n, 'broken: nothing is kept');
}

# without a command, the first of mmdc and mmdr found in PATH
{
    require App::Greple::md::Mermaid;
    mkdir "$dir/bin";
    symlink $stub, "$dir/bin/mmdr" or die;
    local $ENV{PATH} = "$dir/none:$dir/bin";
    is(App::Greple::md::Mermaid::default_command(), 'mmdr', 'PATH: mmdr when there is no mmdc');
    symlink $stub, "$dir/bin/mmdc" or die;
    is(App::Greple::md::Mermaid::default_command(), 'mmdr', 'PATH: mmdr first');
    unlink "$dir/bin/mmdr";
    is(App::Greple::md::Mermaid::default_command(), 'mmdc', 'PATH: mmdc when there is no mmdr');
    local $ENV{PATH} = "$dir/none";
    is(App::Greple::md::Mermaid::default_command(), 'mmdr', 'PATH: mmdr when none is found');
}

done_testing;
