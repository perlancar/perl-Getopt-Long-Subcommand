package Getopt::Long::Subcommand;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(
                    GetOptions
            );

sub _gl_getoptions {
    require Getopt::Long;

    my ($which, $ospecs0, $res) = @_;

    my $ospecs;
    if ($which eq 'strip') {
        $ospecs = { map {$_=>sub{}} keys %$ospecs0 };
    } else {
        $ospecs = { map {
            my $k = $_;
            $k => (
                ref($ospecs0->{$k}) eq 'CODE' ? sub {
                    my ($cb, $val) = @_;
                    $ospecs0->{$k}->($cb, $val, $res);
                } : $ospecs0->{$k}
            )} keys %$ospecs0 };
    }

    my $old_conf = Getopt::Long::Configure('no_ignore_case', 'bundling');
    local $SIG{__WARN__} = sub{} if $which eq 'strip';
    my $gl_res = Getopt::Long::GetOptions(%$ospecs);
    Getopt::Long::Configure($old_conf);
    $gl_res;
}

sub _strip_opts_from_argv {
    _gl_getoptions('strip', @_);
}

sub _GetOptions {
    my ($args) = @_;

    my $has_opts = $args->{options} && keys(%{$args->{options}});
    my $has_subcommands = $args->{subcommands} && keys(%{$args->{subcommands}});

    my $res = {success=>undef};

    my ($sc_name, $sc_spec);
    if ($has_subcommands) {
        local @ARGV = @ARGV;
        _strip_opts_from_argv() if $has_opts;
        @ARGV or do { warn "Missing subcommand\n"; return $res };
        $sc_name = shift @ARGV;
        $sc_spec = $args->{subcommands}{$sc_name} or do {
            warn "Unknown subcommand '$sc_name'\n"; return $res };
        $res->{subcommand} = $sc_name;
        $res->{spec} = $sc_spec;
    }

    {
        # merge common options with subcommand options
        my %ospecs;
        if ($has_opts) {
            $ospecs{$_} = $args->{options}{$_} for keys %{$args->{options}};
        }
        if ($has_subcommands && $sc_spec->{options} &&
                keys %{ $sc_spec->{options} }) {
            $ospecs{$_} = $sc_spec->{options}{$_}
                for keys %{$sc_spec->{options}};
        }
        my $gl_res = _gl_getoptions('getopts', \%ospecs, $res);
        return $res unless $gl_res;
        shift @ARGV; # reshift subcommand name because we use 'local' previously
        $res->{success} = 1;
    }

    $res;
}

sub GetOptions {
    my %args = @_;

    my $res = _GetOptions(\%args);
    return $res;

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
            completion => $args{completion});

        if ($shell eq 'bash') {
            print Complete::Bash::format_completion($compres);
        } elsif ($shell eq 'tcsh') {
            print Complete::Tcsh::format_completion($compres);
        } else {
            die "Unknown shell '$shell'";
        }

        exit 0;
    }
}

1;
#ABSTRACT: Process command-line options, with subcommands and completion

=head1 SYNOPSIS

 use Getopt::Long::Subcommand; # exports GetOptions

 my %opts;
 my $res = GetOptions(
     summary => 'Summary about your program ...',

     # common options recognized by all subcommands
     options => {
         'help|h|?' => sub {
             my ($cb, $val, $res) = @_;
             if ($res->{subcommand}) {
                 say "Help message for $res->{subcommand} ...";
             } else {
                 say "General help message ...";
             }
             exit 0;
         },
         'version|v' => sub {
             say "Program version $main::VERSION";
             exit 0;
         },
         'verbose' => \$opts{verbose},
     },

     # list your subcommands here
     subcommands => {
         subcmd1 => {
             summary => 'The first subcommand',
             # subcommand-specific options
             options => {
                 'foo=i' => \$opts{foo},
             },
         },
         subcmd1 => {
             summary => 'The second subcommand',
             options => {
                 'bar=s' => \$opts{bar},
                 'baz'   => \$opts{baz},
             },
         },
     },
 );
 die "GetOptions failed!\n" unless $res->{success};
 say "Running subcommand $res->{subcommand} ...";

To run your script:

 % script
 Missing subcommand

 % script --help
 General help message ...

 % script subcmd1
 Running subcommand subcmd1 ...

 % script subcmd1 --help
 Help message for subcmd1 ...

 % script --verbose subcmd2 --baz --bar val
 Running subcommand subcmd2 ...

 % script subcmd3
 Unknown subcommand 'subcmd3'
 GetOptions failed!


=head1 DESCRIPTION

B<STATUS: EARLY RELEASE, EXPERIMENTAL.>

This module extends L<Getopt::Long> with subcommands and tab completion ability.

How it works: it first parses C<@ARGV> for common options and subcommand name.
After retrieving subcommand, it will parse again the remaining C<@ARGV> for
subcommand-specific options.

Completion: scripts using this module can complete themselves. Just put your
script somewhere in your C<PATH> and run something like this in your bash shell:
C<complete -C script-name script-name>. See also L<shcompgen> to manage
completion scripts for multiple applications easily. C<GetOptions> will detect
C<COMP_LINE> or C<COMMAND_LINE> (for tcsh) and provide completion answer.


=head1 FUNCTIONS

=head2 GetOptions(%args) => bool

Exported by default. Process options and remove them from C<@ARGV> (thus
modifying it). Return false on failure and hashref on success. The hashref will
contain these keys: C<subcommand> (subcommand name, string or array of strings
on nested subcommands), C<spec> (subcommand spec hash, or the reference to the
main spec (C<%args>) if there is no subcommand).

Arguments:

=over

=item * summary => str

=item * options => hash

A hash of option names and its specification. The specification is the same as
what you would feed to L<Getopt::Long>'s C<GetOptions>.

=item * subcommands => hash

A hash of subcommand name and its specification. The specification looks like
C<GetOptions> argument, with keys like C<summary>, C<options>, C<subcommands>
(nested subcommands is in todo list).

=back


=head1 FAQ

=head2 How to avoid modifying @ARGV? How to process from another array, like Getopt::Long's GetOptionsFromArray?

Instead of adding another function, you can use C<local>.

 {
     local @ARGV = ['--some', 'value'];
     GetOptions(...);
 }
 # the original @ARGV is restored


=head1 TODO

Hooks (when there is missing subcommand, when Getopt::Long::GetOptions fails,
...).

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
