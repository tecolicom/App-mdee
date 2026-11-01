package App::Greple::md::Blocks;

use 5.026;
use warnings;
use utf8;

our $VERSION = "1.14";

use Exporter 'import';
our @EXPORT_OK = qw(blocks available);

# The paragraphs of a Markdown text, for the refill of App::Greple::md:
# blocks($text) returns the blocks as {type, depth, first, last}, where
# type is Para or Plain for a paragraph, depth the number of block
# quotes the block is in, and first and last its line numbers (from 1).
# The positions come from the CommonMark module (libcmark, in this
# process) or from pandoc with its sourcepos extension, whichever the
# parser option names; without it, from the first one that is available.
sub blocks {
    my($text, %opt) = @_;
    my $parser = $opt{parser} || (available())[0]
        // die "refill: neither the CommonMark module nor pandoc with sourcepos is available\n";
    if ($parser eq 'cmark') {
        return cmark_blocks($text);
    } elsif ($parser eq 'pandoc') {
        return pandoc_blocks($text);
    } else {
        die "refill_parser: $parser: use cmark or pandoc\n";
    }
}

# The parsers that work here, cmark first.
sub available {
    state @parsers = (
        (eval { require CommonMark; 1 } ? 'cmark' : ()),
        (pandoc_works() ? 'pandoc' : ()),
    );
    @parsers;
}

# pandoc with the sourcepos extension (2.11.3 or later): run the reader
# that pandoc_blocks uses, so that the check and the use agree.
sub pandoc_works {
    system(q(printf "x\n" | pandoc -f gfm+sourcepos+definition_lists -t json >/dev/null 2>&1)) == 0;
}

# CommonMark gives every node its first and last line.  Only the
# paragraphs are needed; libcmark has no tables and no definition
# lists, so a table and a term with its definitions are paragraphs to
# it, which refill_block keeps apart by their lines.
sub cmark_blocks {
    my $text = shift;
    require CommonMark;
    my $doc = CommonMark->parse(string => $text, sourcepos => 1);
    my $iter = $doc->iterator;
    my($depth, @blocks) = (0);
    while (my($ev, $node) = $iter->next) {
        my $type = $node->get_type;
        if ($type == CommonMark::NODE_BLOCK_QUOTE()) {
            $depth += $ev == CommonMark::EVENT_ENTER() ? 1 : -1;
            next;
        }
        next unless $ev == CommonMark::EVENT_ENTER()
            and $type == CommonMark::NODE_PARAGRAPH();
        push @blocks, {
            type  => 'Para',
            depth => $depth,
            first => $node->get_start_line,
            last  => $node->get_end_line,
        };
    }
    @blocks;
}

# Run pandoc on the text and return the blocks it reports with a source
# position.  With the sourcepos extension pandoc wraps a block in a Div whose
# data-pos is "L:C-L:C", or several such segments separated by ";" when
# the block is interrupted by markers it consumed (a list item's
# continuation lines).  An end column of 1 means the block ended with
# the line before.  A paragraph followed by a horizontal rule without a
# blank line is reported up to the rule, so the end is also cut at the
# line before the next block that starts below the first line.  depth
# is the number of block quotes the block is in.
#
# A block that has attributes of its own (a heading, a code block, a
# table) is not wrapped: its position is in its attributes, at the
# index below in its content.  A table's segments are not in order.
my %attr_index = (Div => 0, Header => 1, CodeBlock => 0, Table => 0, Figure => 0);
sub pandoc_blocks {
    my $text = shift;
    require Command::Run;
    require JSON::PP;
    my $result = Command::Run->new
        ->command(qw(pandoc -f gfm+sourcepos+definition_lists -t json))
        ->with(stdin => $text)
        ->run;
    die "refill: pandoc failed\n" if $result->{result} != 0;
    my $doc = JSON::PP->new->decode($result->{data});
    my @blocks;
    my $walk; $walk = sub {
        my($node, $depth) = @_;
        if (ref $node eq 'HASH') {
            my $t = $node->{t} // '';
            if (defined(my $i = $attr_index{$t})) {
                my $attr = $node->{c}[$i];
                my %kv = map { @$_ } @{$attr->[2]};
                if (defined(my $pos = $kv{'data-pos'})) {
                    my($first, $last);
                    while ($pos =~ /(\d+):\d+-(\d+):(\d+)/g) {
                        my($from, $to) = ($1, $3 == 1 ? $2 - 1 : $2);
                        $first = $from if !defined $first or $from < $first;
                        $last  = $to   if !defined $last  or $to > $last;
                    }
                    my $inner = $node->{c}[1];
                    push @blocks, {
                        type  => $t ne 'Div' ? $t
                               : @$inner == 1 ? $inner->[0]{t} : 'Blocks',
                        depth => $depth,
                        first => $first,
                        last  => $last,
                    } if defined $first;
                }
            }
            $depth++ if $t eq 'BlockQuote';
            $walk->($node->{c}, $depth) if ref $node->{c};
        } elsif (ref $node eq 'ARRAY') {
            $walk->($_, $depth) for @$node;
        }
    };
    $walk->($doc->{blocks}, 0);
    my @starts = sort { $a <=> $b } keys %{{ map { $_->{first} => 1 } @blocks }};
    for my $b (@blocks) {
        my($next) = grep { $_ > $b->{first} } @starts;
        $b->{last} = $next - 1 if defined $next and $next - 1 < $b->{last};
    }
    @blocks;
}

1;

__END__

=encoding utf-8

=head1 NAME

App::Greple::md::Blocks - find the paragraphs of a Markdown text

=head1 SYNOPSIS

    use App::Greple::md::Blocks qw(blocks available);

    my @blocks = blocks($text);                    # first available parser
    my @blocks = blocks($text, parser => 'cmark'); # or 'pandoc'
    my @parsers = available();                     # ('cmark', 'pandoc')

=head1 DESCRIPTION

This module gives L<App::Greple::md> the line numbers of the
paragraphs in a Markdown text, for its C<refill> option, which joins
the lines of each paragraph.  The text itself is not changed or
rendered: the module is only asked where the paragraphs are.

Each block is a hash with C<type> (C<Para> or C<Plain> for a
paragraph), C<depth> (the number of block quotes the block is in) and
C<first> and C<last> (its first and last line, counted from 1).

Two parsers are supported:

=over 4

=item C<cmark>

The L<CommonMark> module, an interface to libcmark, run in this
process.  It is fast, but it does not know GFM tables and definition
lists, which it reports as paragraphs; L<App::Greple::md> keeps their
lines apart by their shape.

=item C<pandoc>

L<pandoc|https://pandoc.org> 2.11.3 or later, run as a child process
with C<-f gfm+sourcepos+definition_lists -t json>.

=back

C<available()> returns the names of the parsers that work on this
system, C<cmark> first, and C<blocks()> uses the first of them unless
C<parser> is given.

=head1 SEE ALSO

L<App::Greple::md>, L<CommonMark>, L<https://pandoc.org>

=head1 AUTHOR

Kazumasa Utashiro

=head1 LICENSE

Copyright 2026 Kazumasa Utashiro.

This software is released under the MIT License.
L<https://opensource.org/licenses/MIT>

=cut
