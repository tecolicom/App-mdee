use strict;
use warnings;
use utf8;
use Test::More;
use open qw(:std :encoding(utf-8));

# Unit tests for reflow_block: joins the lines of one paragraph the way
# ansifold's fill_up does, keeping the break after a hard break and
# before a list marker or horizontal rule line.
use_ok('App::Greple::md');

sub reflow_block { App::Greple::md::reflow_block(@_) }

my @cases = (
    [ 'plain lines',          [ 'para line one', 'para line two' ], 0,
                              [ 'para line one para line two' ] ],
    [ 'trailing single space', [ 'ends with space ', 'next' ], 0,
                              [ 'ends with space next' ] ],
    [ 'hard break (spaces)',  [ 'hard  ', 'kept', 'joined' ], 0,
                              [ 'hard  ', 'kept joined' ] ],
    [ 'hard break (backslash)', [ 'back\\', 'kept' ], 0,
                              [ 'back\\', 'kept' ] ],
    [ 'japanese',             [ '日本語の', '段落。', '続き' ], 0,
                              [ '日本語の段落。続き' ] ],
    [ 'english and japanese', [ 'English and', '日本語' ], 0,
                              [ 'English and 日本語' ] ],
    [ 'list item with lazy line', [ '- item one', '  continued', 'lazy' ], 0,
                              [ '- item one continued lazy' ] ],
    [ 'blockquote depth 1',   [ '> quote a', '> quote b', 'lazy' ], 1,
                              [ '> quote a quote b lazy' ] ],
    [ 'blockquote depth 2',   [ '> > deep a', '> > deep b' ], 2,
                              [ '> > deep a deep b' ] ],
    [ 'pandoc #. list',       [ '#. auto one', '   cont', '#. auto two' ], 0,
                              [ '#. auto one cont', '#. auto two' ] ],
    [ 'horizontal rule',      [ 'Text', '***' ], 0,
                              [ 'Text', '***' ] ],
    [ 'table rows',           [ 'before table', '| C | D |', '|---|---|', '| 3 | 4 |' ], 0,
                              [ 'before table', '| C | D |', '|---|---|', '| 3 | 4 |' ] ],
    [ 'line after table rows', [ '| C | D |', '|---|---|', '| 3 | 4 |', 'after table' ], 0,
                              [ '| C | D |', '|---|---|', '| 3 | 4 |', 'after table' ] ],
    [ 'crlf lines',           [ "crlf a\r", "crlf b\r" ], 0,
                              [ "crlf a crlf b\r" ] ],
    [ 'crlf hard break',      [ "hard  \r", "kept\r" ], 0,
                              [ "hard  \r", "kept\r" ] ],
);

for my $case (@cases) {
    my($name, $lines, $depth, $want) = @$case;
    my @got = reflow_block([ @$lines ], $depth);
    is_deeply(\@got, $want, $name);
}

done_testing;
