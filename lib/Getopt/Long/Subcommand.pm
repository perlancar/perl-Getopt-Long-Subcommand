package Getopt::Long::Subcommand;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
                       GetOptionsWithSubcommands
               );

sub GetOptionsWithSubcommands {
    my %args = @_;

    if ($args{}

            $comp = shift;

    my $hash;
    if (ref($_[0]) eq 'HASH') {
        $hash = shift;
    }

    my $shell;
    if ($ENV{COMP_SHELL}) {
        ($shell = $ENV{COMP_SHELL}) =~ s!.+/!!;
    } elsif ($ENV{COMMAND_LINE}) {
        $shell = 'tcsh';
    } else {
        $shell = 'bash';
    }

    if ($ENV{COMP_LINE} || $ENV{COMMAND_LINE}) {
        my ($words, $cword);
        if ($ENV{COMP_LINE}) {
            require Complete::Bash;
            ($words,$cword) = @{Complete::Bash::parse_cmdline(undef,undef,'=')};
        } elsif ($ENV{COMMAND_LINE}) {
            require Complete::Tcsh;
            $shell = 'tcsh';
            ($words, $cword) = @{ Complete::Tcsh::parse_cmdline() };
        }

        require Complete::Getopt::Long;

        shift @$words; $cword--; # strip program name
        my $compres = Complete::Getopt::Long::complete_cli_arg(
            words => $words, cword => $cword, getopt_spec=>{ @_ },
            completion => $comp);

        if ($shell eq 'bash') {
            print Complete::Bash::format_completion($compres);
        } elsif ($shell eq 'tcsh') {
            print Complete::Tcsh::format_completion($compres);
        } else {
            die "Unknown shell '$shell'";
        }

        exit 0;
    }

    require Getopt::Long;
    my $old_conf = Getopt::Long::Configure('no_ignore_case', 'bundling');
    if ($hash) {
        Getopt::Long::GetOptions($hash, @_);
    } else {
        Getopt::Long::GetOptions(@_);
    }
    Getopt::Long::Configure($old_conf);
}

1;
#ABSTRACT: Process command-line options, with subcommands and completion

=head1 SYNOPSIS

# EXAMPLE: bin/demo-getopt-long-subcommand


=head1 DESCRIPTION

This module extends L<Getopt::Long> with subcommands and tab completion ability.

How it works: it first parses C<@ARGV> for common options and subcommand name.
After retrieving subcommand, it will parse again the remaining C<@ARGV> for
subcommand-specific options.

Completion: scripts using this module can complete themselves. Just put your
script somewhere in your C<PATH> and run something like this in your bash shell:
C<complete -C script-name script-name>. See also L<shcompgen> to manage
completion scripts for multiple applications easily.
C<GetOptionsWithSubcommands> will detect C<COMP_LINE> or C<COMMAND_LINE> (for
tcsh) and provide completion answer.


=head1 FUNCTIONS

Not exported by default, but exportable.

=head2 GetOptionsWithSubcommands(%args)

Arguments:

=over

=item * summary => str

=item * options => hash

A hash of option names and its specification. The specification is what you
would feed to L<Getopt::Long>'s C<GetOptions>.

=item * subcommands => hash

A hash of subcommand name and its specification. The specification looks like
GetOptionsWithSubcommands argument, with keys like C<summary>, C<options>,
C<subcommands> (nested subcommands is in todo list).

=back


=head1 TODO

Nested subcommands.

Autohelp.

autoversion.


=head1 SEE ALSO

L<Getopt::Long>

L<Getopt::Long::Complete>

L<Perinci::CmdLine> - a more full featured command-line application framework,
also with subcommands and completion.

L<Pod::Weaver::Section::Completion::GetoptLongSubcommand>

=cut
