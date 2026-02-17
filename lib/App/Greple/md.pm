# -*- mode: perl; coding: utf-8 -*-
# vim: set fileencoding=utf-8 filetype=perl :
package App::Greple::md;

use 5.024;
use warnings;

our $VERSION = "0.01";

=encoding utf-8

=head1 NAME

App::Greple::md - Greple module for Markdown syntax highlighting

=head1 SYNOPSIS

    greple -Mmd file.md

    greple -Mmd --mode=dark -- file.md

    greple -Mmd --hashed h3=1 -- file.md

    greple -Mmd --cm h1=RD -- file.md

=head1 DESCRIPTION

B<App::Greple::md> is a L<greple|App::Greple> module that provides
Markdown syntax highlighting with cumulative coloring for nested
elements (e.g., links inside headings).

Patterns are processed in priority order: code block state machine,
inline code protection, HTML comment protection, links with OSC 8
hyperlinks, headings (cumulative), emphasis (bold, italic,
strikethrough), blockquotes, and horizontal rules.

=head1 MODULE OPTIONS

These options are specified before C<--> to separate them from
greple options:

    greple -Mmd --mode=dark --cm h1=RD -- file.md

=head2 B<--mode>=I<MODE>

Set color mode to C<light> (default) or C<dark>.

    greple -Mmd --mode=dark -- file.md

=head2 B<--base-color>=I<COLOR>

Override the base color used for headings, bold, links, etc.
Accepts a color name (e.g., C<Crimson>, C<DarkCyan>) or a
L<Term::ANSIColor::Concise> color spec.

    greple -Mmd --base-color=Crimson -- file.md

=head2 B<--cm> I<LABEL>=I<SPEC>

Override the color for a specific label.  Color specs follow
L<Term::ANSIColor::Concise> format and support C<sub{...}> function
specs via L<Getopt::EX::Colormap>.

    greple -Mmd --cm h1=RD -- file.md

=head2 B<--hashed> I<LEVEL>=I<VALUE>

Add closing hashes to headings (e.g., C<### Title> becomes
C<### Title ###>).  Can be set per heading level:

    greple -Mmd --hashed h3=1 --hashed h4=1 -- file.md

=head2 B<--show> I<LABEL>[=I<VALUE>]

Control which elements are highlighted.

    greple -Mmd --show bold=0 -- file.md          # disable bold
    greple -Mmd --show all= --show h1 -- file.md  # only h1

C<--show LABEL=0> or C<--show LABEL=> disables the label.
C<--show LABEL> or C<--show LABEL=1> enables it.
C<all> is a special key that sets all labels at once.

=head1 CONFIGURATION

Module parameters can also be set with the C<config()> function
in the module declaration:

    greple -Mmd::config(mode=dark,base_color=Crimson) file.md

Nested hash parameters use dot notation:

    greple -Mmd::config(hashed.h3=1,hashed.h4=1) file.md

=head2 Table Formatting

By default, Markdown tables are formatted with aligned columns using
L<App::ansicolumn> and separator lines are converted to Unicode
box-drawing characters.  Control with C<table> and C<rule> parameters:

    greple -Mmd::config(table=0) file.md    # disable table formatting
    greple -Mmd::config(rule=0) file.md     # disable box-drawing characters

=head2 OSC 8 Hyperlinks

By default, links are converted to OSC 8 terminal hyperlinks for
clickable URLs in supported terminals.  Disable with:

    greple -Mmd::config(osc8=0) file.md

=head1 COLOR LABELS

The following color labels are available for C<--cm> and C<--show>:

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

=head1 SEE ALSO

L<App::mdee> - Markdown viewer using this module

L<App::Greple>

L<Term::ANSIColor::Concise>

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
    mode       => '',  # light / dark
    osc8       => 1,   # OSC 8 hyperlinks
    base_color => '',  # override base color
    table      => 1,   # table formatting
    rule       => 1,   # box-drawing characters for tables
    hashed     => { h1 => 0, h2 => 0, h3 => 0, h4 => 0, h5 => 0, h6 => 0 },
);

#
# Color definitions
#

my %base_color = (
    light => '<RoyalBlue>=y25',
    dark  => '<RoyalBlue>=y80',
);

my %default_colors = (
    code_mark       => 'L20',
    code_info       => '${base_name}+r60=y70',
    code_block      => '/L23;E',
    code_inline     => '/L23',
    comment         => '${base}+r60',
    link            => '${base}',
    image           => '${base}',
    image_link      => '${base}',
    h1              => 'L25DE/${base}',
    h2              => 'L25DE/${base}+y20',
    h3              => 'L25DN/${base}+y30',
    h4              => '${base}UD',
    h5              => '${base}+y20;U',
    h6              => '${base}+y20',
    bold            => '${base}D',
    italic          => 'I',
    strike          => 'X',
    blockquote      => '${base}D',
    horizontal_rule => 'L15',
);

my %dark_overrides = (
    code_mark       => 'L10',
    code_info       => '${base_name}+r60=y20',
    code_block      => '/L05;E',
    code_inline     => '/L05',
    h1              => 'L00DE/${base}',
    h2              => 'L00DE/${base}-y15',
    h3              => 'L00DN/${base}-y25',
    h4              => '${base}UD',
    h5              => '${base}-y20;U',
    h6              => '${base}-y20',
);

sub default_theme {
    my $mode = shift // 'light';
    my %colors = %default_colors;
    if ($mode eq 'dark') {
        @colors{keys %dark_overrides} = values %dark_overrides;
    }
    $colors{base} = $base_color{$mode};
    if (defined wantarray) {
        %colors;
    } else {
        # Print as bash array assignments: theme_MODE[key]='value'
        for my $key (sort keys %colors) {
            (my $val = $colors{$key}) =~ s/'/'\\''/g;
            printf "theme_%s[%s]='%s'\n", $mode, $key, $val;
        }
    }
}

my $cm;
my @opt_cm;
my %show;

sub finalize {
    my($mod, $argv) = @_;
    $config->deal_with($argv,
                       "mode=s", "base_color=s", "table!", "rule!",
                       "hashed=s%",
                       "cm=s" => \@opt_cm,
                       "show=s%" => \%show);
}

sub setup_colors {
    my $mode = $config->{mode} || 'light';
    my %colors = %default_colors;
    if ($mode eq 'dark') {
        @colors{keys %dark_overrides} = values %dark_overrides;
    }
    # Determine base color
    my $base = $config->{base_color};
    if ($base) {
        # Color names get automatic luminance adjustment
        $base = "<$base>" . ($mode eq 'dark' ? '=y80' : '=y25')
            if $base =~ /^[A-Za-z]\w*$/;
    } else {
        $base = $base_color{$mode} || $base_color{light};
    }
    # ${base_name}: color without luminance (e.g., '<RoyalBlue>')
    (my $base_name = $base) =~ s/=y\d+$//;
    # Expand placeholders
    for my $key (keys %colors) {
        $colors{$key} =~ s/\$\{base_name\}/$base_name/g;
        $colors{$key} =~ s/\$\{base\}/$base/g;
    }
    # Handle + prefix: prepend current color value before load_params
    # (load_params' built-in + doesn't work correctly with sub{...})
    my @final_cm;
    for my $entry (@opt_cm) {
        my $expanded = $entry =~ s/\$\{base_name\}/$base_name/gr
                              =~ s/\$\{base\}/$base/gr;
        if ($expanded =~ /^(\w+)=\+(.*)/) {
            my ($label, $append) = ($1, $2);
            my $current = $colors{$label} // '';
            push @final_cm, "$label=$current$append";
        } else {
            push @final_cm, $expanded;
        }
    }

    $cm = Getopt::EX::Colormap->new(
        HASH => \%colors,
        NEWLABEL => 1,
    );
    $cm->load_params(@final_cm);
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
    "\e[256m" . $#protected . "\e[m";
}

sub restore {
    my $s = shift;
    $s =~ s/\e\[256m(\d+)\e\[m/$protected[$1]/g;
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
# Receives entire file content in $_ (--begin with -G --all --need=0).
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
        my $hashed = $config->{hashed};
        for my $n (reverse 1..6) {
            next unless active("h$n");
            my $hdr = '#' x $n;
            s{^($hdr\h+.*)$}{
                my $line = $1;
                $line .= " $hdr"
                    if $hashed->{"h$n"} && $line !~ /\#$/;
                md_color("h$n", $line);
            }mge;
        }
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

#
# Table formatting
#

sub begin {
    colorize();
    format_table();
}

sub format_table {
    return unless $config->{table};
    my $sep = $config->{rule} ? "\x{2502}" : '|';  # │ or |

    s{(^ {0,3}\|.+\|\n){3,}}{
        my $block = $&;
        my $formatted = call_ansicolumn($block,
            '-s', '|', '-o', $sep, '-t', '--cu=1');
        fix_separator($formatted, $sep);
    }mge;
}

sub call_ansicolumn {
    my ($text, @args) = @_;
    require Command::Run;
    require App::ansicolumn;
    Command::Run->new
        ->command(\&App::ansicolumn::ansicolumn, @args)
        ->with(stdin => $text)
        ->update
        ->data // '';
}

sub fix_separator {
    my ($text, $sep) = @_;
    my $sep_re = $sep eq "\x{2502}" ? "\x{2502}" : '\\|';
    $text =~ s{^$sep_re((?:\h* -+ \h* $sep_re)*\h* -+ \h*)$sep_re$}{
        $sep eq "\x{2502}"
        ? "\x{251C}" . ($1 =~ tr[\x{2502} -][\x{253C}\x{2500}\x{2500}]r) . "\x{2524}"
        : "|" . ($1 =~ tr[ ][-]r) . "|"
    }xmeg;
    $text;
}

1;

__DATA__

option default \
    -G --all --need=0 --filestyle=once --color=always \
    --exit=0 \
    -E '(*FAIL)' \
    --begin &__PACKAGE__::begin
