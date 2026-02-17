package App::Greple::md;

use 5.024;
use warnings;

our $VERSION = "0.01";

=encoding utf-8

=head1 NAME

App::Greple::md - Greple module for Markdown syntax highlighting

=head1 SYNOPSIS

    greple -Mmd file.md

    greple -Mmd::config(mode=dark) file.md

    greple -Mmd --cm h1=RD -- file.md

=head1 DESCRIPTION

B<App::Greple::md> is a L<greple|App::Greple> module that provides
Markdown syntax highlighting with cumulative coloring for nested
elements (e.g., links inside headings).

All colorization is handled by the C<colorize()> function invoked via
C<--print>.  Patterns are processed in priority order: code block
state machine, inline code protection, HTML comment protection, links
with OSC 8 hyperlinks, headings (cumulative), emphasis (bold, italic,
strikethrough), blockquotes, and horizontal rules.

Default colors can be overridden by C<--cm LABEL=spec> as a module
option (before C<-->):

=head2 Color Labels

The following color labels are available for override:

    code_fence      Fenced code block opening/closing fence
    code_lang       Fenced code block language specifier
    code_body       Fenced code block body
    inline_code     Inline code spans
    comment         HTML comments
    link            Inline links [text](url)
    image           Images ![alt](url)
    image_link      Image links [![alt](img)](url)
    h1 - h6         Headings
    bold            Bold text (**text** or __text__)
    italic          Italic text (*text* or _text_)
    strike          Strikethrough text (~~text~~)
    blockquote      Blockquote marker (>)
    horizontal_rule Horizontal rules (---, ***, ___)

=head2 Dark Mode

Use C<mode=dark> configuration to activate dark mode colors:

    greple -Mmd::config(mode=dark) file.md

=head2 OSC 8 Hyperlinks

By default, links are converted to OSC 8 terminal hyperlinks for
clickable URLs in supported terminals.  Disable with C<osc8=0>:

    greple -Mmd::config(osc8=0) file.md

=head1 SEE ALSO

L<App::Greple>

L<Getopt::EX::Config>

L<Term::ANSIColor::Concise>

=head1 AUTHOR

Kazumasa Utashiro

=head1 LICENSE

Copyright 2025-2026 Kazumasa Utashiro.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

use URI::Escape;
use Getopt::EX::Config;
use Term::ANSIColor::Concise qw(ansi_color);

my $config = Getopt::EX::Config->new(
    mode => '',      # light / dark
    osc8 => 1,       # OSC 8 hyperlinks
);

#
# Color definitions
#

my %default_colors = (
    code_fence      => 'L20',
    code_lang       => 'L18',
    code_body       => '/L23;E',
    inline_code     => 'L15/L23',   # backtick delimiters
    inline_code_body => '/L23',    # code content
    comment         => 'L15',
    link            => 'CU',
    image           => 'CU',
    image_link      => 'CU',
    h1              => 'L25DE/<RoyalBlue>=y25',
    h2              => 'L25DE/<RoyalBlue>=y25+y20',
    h3              => 'L25DN/<RoyalBlue>=y25+y30',
    h4              => '<RoyalBlue>=y25;UD',
    h5              => '<RoyalBlue>=y25;U',
    h6              => '<RoyalBlue>=y25',
    bold            => '<RoyalBlue>=y25;D',
    italic          => 'I',
    strike          => 'X',
    blockquote      => '<RoyalBlue>=y25;D',
    horizontal_rule => 'L15',
);

my %dark_overrides = (
    code_fence      => 'L10',
    code_lang       => 'L12',
    code_body       => '/L05;E',
    inline_code     => 'L12/L05',
    inline_code_body => '/L05',
    h1              => 'L00DE/<RoyalBlue>=y80',
    h2              => 'L00DE/<RoyalBlue>=y80-y15',
    h3              => 'L00DN/<RoyalBlue>=y80-y25',
    h4              => '<RoyalBlue>=y80;UD',
    h5              => '<RoyalBlue>=y80;U',
    h6              => '<RoyalBlue>=y80',
    bold            => '<RoyalBlue>=y80;D',
    blockquote      => '<RoyalBlue>=y80;D',
);

my %colors;
my %user_colors;

sub initialize {
    my($mod, $argv) = @_;
    $config->deal_with($argv, "cm=s%" => \%user_colors);
}

sub setup_colors {
    %colors = %default_colors;
    if ($config->{mode} eq 'dark') {
	@colors{keys %dark_overrides} = values %dark_overrides;
    }
    @colors{keys %user_colors} = values %user_colors;
}

#
# Apply color by label
#

sub md_color {
    my($label, $text) = @_;
    my $spec = $colors{$label};
    return $text unless defined $spec && $spec ne '';
    my $func;
    if ($spec =~ s/;sub\{(.*)\}$//) {
	$func = $1;
    }
    $text = ansi_color($spec, $text) if $spec ne '';
    if ($func) {
	local $_ = $text;
	$text = eval $func;
	warn "md_color: $@" if $@;
    }
    $text;
}

#
# Protection mechanism
#
# NUL-byte placeholders protect processed regions (inline code,
# comments, links) from being matched by later patterns.
#

my @protected;

sub protect {
    my $text = shift;
    push @protected, $text;
    "\x01" . $#protected . "\x02";
}

sub restore {
    my $s = shift;
    $s =~ s/\x01(\d+)\x02/$protected[$1]/g;
    $s;
}

#
# OSC 8 hyperlink generation
#

sub osc8 {
    return $_[1] unless $config->{osc8};
    my($url, $text) = @_;
    my $escaped = uri_escape_utf8($url, "^\\x20-\\x7e");
    "\e]8;;${escaped}\e\\${text}\e]8;;\e\\";
}

#
# Link text inner pattern: backtick spans, backslash escapes, normal chars
#

my $LT = qr/(?:`[^`\n]*+`|\\.|[^`\\\n\]]++)+/;

#
# colorize() - the main function
#
# Receives entire file content in $_ (--print with -G --all --need=0).
# Processes all patterns with multiline regexes.
#

sub colorize {
    setup_colors();
    @protected = ();

    ############################################################
    # 1. Fenced code blocks (multiline)
    ############################################################

    s{^( {0,3})(`{3,}|~{3,})(.*)\n((?s:.*?))^( {0,3})\2(\h*)$}{
	my($oi, $fence, $lang, $body, $ci, $trail) = ($1, $2, $3, $4, $5, $6);
	my $result = md_color('code_fence', "$oi$fence");
	$result .= md_color('code_lang', $lang) if length($lang);
	$result .= "\n";
	if (length($body)) {
	    $result .= join '', map { md_color('code_body', $_) }
		split /(?<=\n)/, $body;
	}
	$result .= md_color('code_fence', "$ci$fence") . $trail;
	protect($result)
    }mge;

    ############################################################
    # 2. Inline code protection
    ############################################################

    s/(?<bt>`++)(((?!\g{bt}).)+)(\g{bt})/
	protect(md_color('inline_code', $+{bt}) . md_color('inline_code_body', $2) . md_color('inline_code', $4))
    /ge;

    ############################################################
    # 3. HTML comment protection (multiline)
    ############################################################

    s/(^<!--(?![->])(?s:.*?)-->)/protect(md_color('comment', $1))/mge;

    ############################################################
    # 4. Image links: [![alt](img)](url)
    ############################################################

    s{\[!\[($LT)\]\(([^)\n]+)\)\]\(<?([^>)\s\n]+)>?\)}{
	protect(
	    osc8($2, md_color('image_link', "!"))
	    . osc8($3, md_color('image_link', "[$1]"))
	)
    }ge;

    ############################################################
    # 5. Images: ![alt](url)
    ############################################################

    s{!\[($LT)\]\(<?([^>)\s\n]+)>?\)}{
	protect(osc8($2, md_color('image', "![$1]")))
    }ge;

    ############################################################
    # 6. Links: [text](url) (not preceded by !)
    ############################################################

    s{(?<!!)\[($LT)\]\(<?([^>)\s\n]+)>?\)}{
	protect(osc8($2, md_color('link', "[$1]")))
    }ge;

    ############################################################
    # 7. Horizontal rule (before emphasis to prevent conflict)
    ############################################################

    s/^([ ]{0,3}(?:[-*_][ ]*){3,})$/protect(md_color('horizontal_rule', $1))/mge;

    ############################################################
    # 8. Headings h6 -> h1 (cumulative over links)
    ############################################################

    s/^(######+\h+.*)$/md_color('h6', $1)/mge;
    s/^(#####\h+.*)$/md_color('h5', $1)/mge;
    s/^(####\h+.*)$/md_color('h4', $1)/mge;
    s/^(###\h+.*)$/md_color('h3', $1)/mge;
    s/^(##\h+.*)$/md_color('h2', $1)/mge;
    s/^(#\h+.*)$/md_color('h1', $1)/mge;

    ############################################################
    # 9. Bold: **text** and __text__
    ############################################################

    s/(?<![\\`])\*\*.*?(?<!\\)\*\*/md_color('bold', $&)/ge;
    s/(?<![\\`\w])__.*?(?<!\\)__(?!\w)/md_color('bold', $&)/ge;

    ############################################################
    # 10. Italic: _text_ and *text*
    ############################################################

    s/(?<![\\`\w])_(?:(?!_).)+(?<!\\)_(?!\w)/md_color('italic', $&)/ge;
    s/(?<![\\`\*])\*(?:(?!\*).)+(?<!\\)\*(?!\*)/md_color('italic', $&)/ge;

    ############################################################
    # 11. Strikethrough: ~~text~~
    ############################################################

    s/(?<![\\`])~~.+?(?<!\\)~~/md_color('strike', $&)/ge;

    ############################################################
    # 12. Blockquote: color only the > marker
    ############################################################

    s/^(>+\h?)(.*)$/md_color('blockquote', $1) . $2/mge;

    ############################################################
    # 13. Restore protected regions
    ############################################################

    $_ = restore($_);

    $_;
}

1;

__DATA__

option default \
    -G --all --need=0 --filestyle=once --color=always \
    --exit=0 \
    -E '\z.' \
    --begin &__PACKAGE__::colorize
