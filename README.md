
# NAME

mdv - Markdown viewer using greple and nup

# SYNOPSIS

    mdv [ options ] file ...

     -h  --help             show help
         --version          show version
     -d  --debug            debug mode
     -n  --dryrun           dry-run mode
         --fold             enable line folding (default: on)
         --no-fold          disable line folding
         --table            enable table formatting (default: on)
         --no-table         disable table formatting
         --nup              use nup for paged output (default: on)
         --no-nup           disable nup, output to stdout
     -w  --width=#          fold width (default: 80)
     -C  --pane=#           number of columns
     -R  --row=#            number of rows
     -G  --grid=#           grid layout (e.g., 2x3)
     -P  --page=#           page height in lines
     -S  --pane-width=#     pane width (default: 85)
    --bs --border-style=#   border style
         --pager=#          pager command (empty to disable)
         --no-pager         disable pager

# VERSION

Version 0.01

# DESCRIPTION

**mdv** is a Markdown viewer command that combines [greple(1)](http://man.he.net/man1/greple) for
syntax highlighting with [nup(1)](http://man.he.net/man1/nup) for multi-column paged output.

It provides colorized display of Markdown files with support for:

- Headers (h1-h5) with distinct styling
- Bold text
- Inline code (backticks)
- Code blocks (fenced with \`\`\`)
- HTML comments (dimmed)
- Tables (formatted with ansicolumn)
- List items with proper indentation

# OPTIONS

## General Options

- **-h**, **--help**

    Show help message.

- **--version**

    Show version.

- **-d**, **--debug**

    Enable debug mode.

- **-n**, **--dryrun**

    Dry-run mode. Show the command without executing.

## Processing Options

- **--fold**, **--no-fold**

    Enable or disable line folding for list items.  When enabled, long
    lines in list items are wrapped with proper indentation using
    [ansifold(1)](http://man.he.net/man1/ansifold).  Default is enabled.

- **--table**, **--no-table**

    Enable or disable table formatting.  When enabled, Markdown tables
    are formatted using [ansicolumn(1)](http://man.he.net/man1/ansicolumn) for aligned column display.
    Default is enabled.

- **--nup**, **--no-nup**

    Enable or disable [nup(1)](http://man.he.net/man1/nup) for multi-column paged output.  When
    disabled, output goes directly to stdout without formatting.
    Default is enabled.

- **-w** _N_, **--width**=_N_

    Set the fold width for text wrapping. Default is 80.
    Only effective when `--fold` is enabled.

## Layout Options (passed to nup)

- **-C** _N_, **--pane**=_N_

    Set the number of columns (panes).

- **-R** _N_, **--row**=_N_

    Set the number of rows.

- **-G** _CxR_, **--grid**=_CxR_

    Set grid layout. For example, `-G2x3` creates 2 columns and 3 rows.

- **-P** _N_, **--page**=_N_

    Set the page height in lines.

- **-S** _N_, **--pane-width**=_N_

    Set the pane width in characters. Default is 85.

- **--bs**=_STYLE_, **--border-style**=_STYLE_

    Set the border style.

## Pager Options

- **--pager**=_COMMAND_

    Set the pager command.
    Use `--pager=` (empty) or `--no-pager` to disable pager.

- **--no-pager**

    Disable pager.

# EXAMPLES

    mdv README.md              # view markdown file
    mdv -C2 document.md        # 2-column view
    mdv -G2x2 manual.md        # 2x2 grid (4-up)
    mdv -w60 narrow.md         # narrower text width
    mdv --no-pager file.md     # without pager
    mdv --no-nup file.md       # output to stdout without nup
    mdv --no-fold file.md      # disable line folding
    mdv --no-table file.md     # disable table formatting

# DEPENDENCIES

This command requires the following:

- [App::Greple](https://metacpan.org/pod/App%3A%3AGreple) - pattern matching and highlighting
- [App::Greple::tee](https://metacpan.org/pod/App%3A%3AGreple%3A%3Atee) - filter integration
- [App::ansifold](https://metacpan.org/pod/App%3A%3Aansifold) - ANSI-aware text folding
- [App::ansicolumn](https://metacpan.org/pod/App%3A%3Aansicolumn) - ANSI-aware column formatting
- [App::nup](https://metacpan.org/pod/App%3A%3Anup) - N-up multi-column paged output
- [Getopt::Long::Bash](https://metacpan.org/pod/Getopt%3A%3ALong%3A%3ABash) - bash option parsing

# SEE ALSO

[nup(1)](http://man.he.net/man1/nup), [greple(1)](http://man.he.net/man1/greple), [ansifold(1)](http://man.he.net/man1/ansifold), [ansicolumn(1)](http://man.he.net/man1/ansicolumn)

# AUTHOR

Kazumasa Utashiro

# LICENSE

Copyright 2025 Kazumasa Utashiro.

This software is released under the MIT License.
[https://opensource.org/licenses/MIT](https://opensource.org/licenses/MIT)
