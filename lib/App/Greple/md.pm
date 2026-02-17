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
option (before C<-->).  Color specs follow
L<Term::ANSIColor::Concise> format and support C<sub{...}> function
specs via L<Getopt::EX::Colormap>.

=head2 Color Labels

The following color labels are available for override:

    code_mark        Code delimiters (fences and backticks)
    code_info        Fenced code block info string
    code_block       Fenced code block body
    code_inline      Inline code body
    comment          HTML comments
    link             Inline links [text](url)
    image            Images ![alt](url)
    image_link       Image links [![alt](img)](url)
    h1 - h6          Headings
    bold             Bold text (**text** or __text__)
    italic           Italic text (*text* or _text_)
    strike           Strikethrough text (~~text~~)
    blockquote       Blockquote marker (>)
    horizontal_rule  Horizontal rules (---, ***, ___)

=head2 Dark Mode

Use C<mode=dark> configuration to activate dark mode colors:

    greple -Mmd::config(mode=dark) file.md

=head2 OSC 8 Hyperlinks

By default, links are converted to OSC 8 terminal hyperlinks for
clickable URLs in supported terminals.  Disable with C<osc8=0>:

    greple -Mmd::config(osc8=0) file.md

=head2 Field Visibility

The C<--show> option controls which elements are highlighted:

    greple -Mmd --show bold=0 -- file.md       # disable bold
    greple -Mmd --show all= --show h1 -- file.md  # only h1

C<--show LABEL=0> or C<--show LABEL=> disables the label.
C<--show LABEL> or C<--show LABEL=1> enables it.
C<all> is a special key that sets all labels at once.

=head1 SEE ALSO

L<App::Greple>

L<Getopt::EX::Colormap>

L<Getopt::EX::Config>

=head1 AUTHOR

Kazumasa Utashiro

=head1 LICENSE

Copyright 2025-2026 Kazumasa Utashiro.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

use URI::Escape;
use Getopt::EX::Config;
use Getopt::EX::Colormap;

my $config = Getopt::EX::Config->new(
    mode => '',      # light / dark
    osc8 => 1,       # OSC 8 hyperlinks
);

#
# Color definitions
#

my %default_colors = (
    code_mark       => 'L20',
    code_info       => 'L18',
    code_block      => '/L23;E',
    code_inline     => '/L23',
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
    code_mark       => 'L10',
    code_info       => 'L12',
    code_block      => '/L05;E',
    code_inline     => '/L05',
    h1              => 'L00DE/<RoyalBlue>=y80',
    h2              => 'L00DE/<RoyalBlue>=y80-y15',
    h3              => 'L00DN/<RoyalBlue>=y80-y25',
    h4              => '<RoyalBlue>=y80;UD',
    h5              => '<RoyalBlue>=y80;U',
    h6              => '<RoyalBlue>=y80',
    bold            => '<RoyalBlue>=y80;D',
    blockquote      => '<RoyalBlue>=y80;D',
);

my $cm;
my @opt_cm;
my %show;

sub finalize {
    my($mod, $argv) = @_;
    $config->deal_with($argv,
		       "cm=s" => \@opt_cm,
		       "show=s%" => \%show);
}

sub setup_colors {
    my %colors = %default_colors;
    if ($config->{mode} eq 'dark') {
	@colors{keys %dark_overrides} = values %dark_overrides;
    }
    $cm = Getopt::EX::Colormap->new(
	HASH => \%colors,
	NEWLABEL => 1,
    );
    $cm->load_params(@opt_cm);
}

sub active {
    my $label = shift;
    return 0 if exists $show{$label} && !$show{$label};
    return 1 unless exists $cm->{HASH}{$label};
    $cm->{HASH}{$label} ne '';
}

#
# Apply color by label
#

sub md_color {
    my($label, $text) = @_;
    $cm->color($label, $text);
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
	my $result = md_color('code_mark', "$oi$fence");
	$result .= md_color('code_info', $lang) if length($lang);
	$result .= "\n";
	if (length($body)) {
	    $result .= join '', map { md_color('code_block', $_) }
		split /(?<=\n)/, $body;
	}
	$result .= md_color('code_mark', "$ci$fence") . $trail;
	protect($result)
    }mge;

    ############################################################
    # 2. Inline code protection
    ############################################################

    s/(?<bt>`++)(((?!\g{bt}).)+)(\g{bt})/
	protect(md_color('code_mark', $+{bt}) . md_color('code_inline', $2) . md_color('code_mark', $4))
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

    if (active('horizontal_rule')) {
	s/^([ ]{0,3}(?:[-*_][ ]*){3,})$/protect(md_color('horizontal_rule', $1))/mge;
    }

    ############################################################
    # 8. Headings h6 -> h1 (cumulative over links)
    ############################################################

    if (active('header')) {
	s/^(######\h+.*)$/md_color('h6', $1)/mge if active('h6');
	s/^(#####\h+.*)$/md_color('h5', $1)/mge  if active('h5');
	s/^(####\h+.*)$/md_color('h4', $1)/mge   if active('h4');
	s/^(###\h+.*)$/md_color('h3', $1)/mge    if active('h3');
	s/^(##\h+.*)$/md_color('h2', $1)/mge     if active('h2');
	s/^(#\h+.*)$/md_color('h1', $1)/mge      if active('h1');
    }

    ############################################################
    # 9. Bold: **text** and __text__
    ############################################################

    if (active('bold')) {
	s/(?<![\\`])\*\*.*?(?<!\\)\*\*/md_color('bold', $&)/ge;
	s/(?<![\\`\w])__.*?(?<!\\)__(?!\w)/md_color('bold', $&)/ge;
    }

    ############################################################
    # 10. Italic: _text_ and *text*
    ############################################################

    if (active('italic')) {
	s/(?<![\\`\w])_(?:(?!_).)+(?<!\\)_(?!\w)/md_color('italic', $&)/ge;
	s/(?<![\\`\*])\*(?:(?!\*).)+(?<!\\)\*(?!\*)/md_color('italic', $&)/ge;
    }

    ############################################################
    # 11. Strikethrough: ~~text~~
    ############################################################

    if (active('strike')) {
	s/(?<![\\`])~~.+?(?<!\\)~~/md_color('strike', $&)/ge;
    }

    ############################################################
    # 12. Blockquote: color only the > marker
    ############################################################

    if (active('blockquote')) {
	s/^(>+\h?)(.*)$/md_color('blockquote', $1) . $2/mge;
    }

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
