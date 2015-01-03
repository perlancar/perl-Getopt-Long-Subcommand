package Getopt::Long::Subcommand;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;
use Log::Any '$log';

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(
                    GetOptions
            );

my @known_cmdspec_keys = qw(
    options
    subcommands
);

sub _gl_getoptions {
    require Getopt::Long;

    my ($which, $ospec0, $res) = @_;
    $log->tracef('Performing Getopt::Long::GetOptions (%s)', $which);

    my $ospec;
    if ($which eq 'strip') {
        $ospec = { map {$_=>sub{}} keys %$ospec0 };
    } else {
        $ospec = { map {
            my $k = $_;
            $k => (
                ref($ospec0->{$k}) eq 'CODE' ? sub {
                    my ($cb, $val) = @_;
                    $ospec0->{$k}->($cb, $val, $res);
                } : $ospec0->{$k}
            )} keys %$ospec0 };
    }

    my $old_conf = Getopt::Long::Configure(
        'no_ignore_case', 'bundling',
        ('pass_through') x !!($which eq 'strip'),
    );
    local $SIG{__WARN__} = sub{} if $which eq 'strip';
    $log->tracef('@ARGV before Getopt::Long::GetOptions: %s', \@ARGV);
    $log->tracef('spec for Getopt::Long::GetOptions: %s', $ospec);
    my $gl_res = Getopt::Long::GetOptions(%$ospec);
    $log->tracef('@ARGV after  Getopt::Long::GetOptions: %s', \@ARGV);
    Getopt::Long::Configure($old_conf);
    $gl_res;
}

sub _strip_opts_from_argv {
    _gl_getoptions('strip', @_);
}

sub _GetOptions {
    my ($is_completion, $cmdspec, $main_cmdspec, $level, $path, $stash,
        @ospecs) = @_;

    # check command spec
    {
        use experimental 'smartmatch';
        $log->tracef("Checking cmdspec keys: %s", [keys %$cmdspec]);
        for (keys %$cmdspec) {
            $_ ~~ @known_cmdspec_keys
                or die "Unknown command specification key '$_'" .
                    ($path ? " (under $path)" : "") . "\n";
        }
    }

    $main_cmdspec //= $cmdspec;
    $level //= 0;
    $path //= '';
    my $res = {success=>undef};
    $stash //= {};
    $res->{stash} = $stash;

    my $has_opts = $cmdspec->{options} && keys(%{$cmdspec->{options}});
    push @ospecs, $cmdspec->{options} if !@ospecs && $has_opts;

    my $has_subcommands = $cmdspec->{subcommands} &&
        keys(%{$cmdspec->{subcommands}});

    my %ospec;

    # XXX refactor. we do this in several places to make sure ospecs is filled
    if ($is_completion) {
        %ospec = ();
        for my $os (@ospecs) {
            $ospec{$_} = $os->{$_} for keys %$os;
        }
        $stash->{comp_ospecs}[$level] = \%ospec;
    }

    # parse/strip all known options first, to get subcommand name from first
    # element of @ARGV
    my ($sc_name, $sc_spec, $sc_has_opts, $sc_has_subcommands);
    if ($has_subcommands) {
        $stash->{comp_subcommands}[$level] = $cmdspec->{subcommands}
            if $is_completion;
        local @ARGV = @ARGV;
        my %ospec;
        for my $os (@ospecs) {
            $ospec{$_} = $os->{$_} for keys %$os;
        }
        _strip_opts_from_argv(\%ospec) if @ospecs;
        shift @ARGV for 1..$level; # discard parent command names
        @ARGV or do {
            if ($is_completion) {
                $stash->{comp_type} = 'subcommand';
                $stash->{comp_subcommand_level} = $level;
            } else {
                warn "Missing subcommand".($path ? " for $path":"")."\n";
                $res->{success} = 0;
            }
            return $res;
        };
        $sc_name = shift @ARGV;
        $sc_spec = $cmdspec->{subcommands}{$sc_name} or do {
            if ($is_completion) {
                $stash->{comp_type} = 'subcommand';
                $stash->{comp_subcommand_level} = $level;
            } else {
                warn "Unknown subcommand '$sc_name'".
                    ($path ? " for $path":"")."\n";
                $res->{success} = 0;
            }
            return $res;
        };
        $stash->{subcommand} = $path .
            (defined($sc_name) ? (length($path) ? "/$sc_name" : $sc_name) : '');
        $res->{subcommand} = $sc_name;
        $sc_has_opts = $sc_spec->{options} &&
            keys(%{$sc_spec->{options}});
        push @ospecs, $sc_spec->{options} if $sc_has_opts;
        $sc_has_subcommands = $sc_spec->{subcommands} &&
            keys(%{$sc_spec->{subcommands}});
    }

    %ospec = ();
    for my $os (@ospecs) {
        $ospec{$_} = $os->{$_} for keys %$os;
    }
    $stash->{comp_ospecs}[$level] = \%ospec if $is_completion;

    if ($sc_has_subcommands) {
        # we still need to collect nested subcommand's options
        $res->{subcommand_res} = _GetOptions(
            $is_completion,
            $sc_spec, $main_cmdspec,
            $level + 1,
            $path . (length($path) ? "/$sc_name" : $sc_name),
            $stash,
            @ospecs);
        shift @ARGV; # reshift subcommand name because we use 'local' previously
        $res->{success} = $res->{subcommand_res}{success};
    } else {
        # merge all option specifications into a single one to feed to
        # Getopt::Long

        unless ($is_completion) {
            my $gl_res = _gl_getoptions('getopts', \%ospec, $res);
            unless ($gl_res) {
                $res->{success} = 0;
                return $res;
            }

            shift @ARGV; # reshift subcommand name because we use 'local' previously
        }
        $res->{success} = 1;
    }

    $log->tracef('Final @ARGV: %s', \@ARGV);
    $res;
}

sub GetOptions {
    my %cmdspec = @_;

    # figure out if we run in completion mode
    my ($is_completion, $shell, $words, $cword);
  CHECK_COMPLETION:
    {
        if ($ENV{COMP_SHELL}) {
            ($shell = $ENV{COMP_SHELL}) =~ s!.+/!!;
        } elsif ($ENV{COMMAND_LINE}) {
            $shell = 'tcsh';
        } else {
            $shell = 'bash';
        }

        if ($ENV{COMP_LINE} || $ENV{COMMAND_LINE}) {
            if ($ENV{COMP_LINE}) {
                $is_completion++;
                require Complete::Bash;
                ($words, $cword) = @{Complete::Bash::parse_cmdline(
                    undef,undef,'=')};
            } elsif ($ENV{COMMAND_LINE}) {
                $is_completion++;
                require Complete::Tcsh;
                $shell = 'tcsh';
                ($words, $cword) = @{ Complete::Tcsh::parse_cmdline() };
            } else {
                last CHECK_COMPLETION;
            }

            shift @$words; $cword--; # strip program name
            @ARGV = @$words;
        }
    }

    my $res = _GetOptions($is_completion, \%cmdspec);

    if ($is_completion) {
        my $ospec = $res->{stash}{comp_ospecs}[-1];
        require Complete::Getopt::Long;
        my $compres = Complete::Getopt::Long::complete_cli_arg(
            words => $words, cword => $cword, getopt_spec=>$ospec,
            extras => {
                stash => $res->{stash},
            },
            completion => sub {
                my %args = @_;

                my $word  = $args{word} // '';
                my $type  = $args{type};
                my $stash = $args{stash};

                $cmdspec{completion},
            },
        );

        if ($shell eq 'bash') {
            print Complete::Bash::format_completion($compres);
        } elsif ($shell eq 'tcsh') {
            print Complete::Tcsh::format_completion($compres);
        } else {
            die "Unknown shell '$shell'";
        }

        exit 0;
    }

    # cleanup unneeded details
    $res->{subcommand} = $res->{stash}{subcommand};
    delete $res->{stash};
    delete $res->{subcommand_res};
    return $res;
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

How parsing works: we first try to gather all options specifications. First is
the common options. If there are subcommands, subcommand name is then first
stripped from first element of C<@ARGV>. We then gather subcommand options. If
subcommand also has nested subcommand, the process is repeated. Finally, we
merged all options specifications into a single one and hand it off to
L<Getopt::Long>.

then retrieved from the first element of C<@ARGV>. After that, subcommand
options will be parsed from C<@ARGV>. If subcommand has a nested subcommand, the
process is repeated.

Completion: Scripts using this module can complete themselves. Just put your
script somewhere in your C<PATH> and run something like this in your bash shell:
C<complete -C script-name script-name>. See also L<shcompgen> to manage
completion scripts for multiple applications easily.

How completion works: Eenvironment variable C<COMP_LINE> or C<COMMAND_LINE> (for
tcsh) is first checked. If it exists, we are in completion mode and C<@ARGV> is
parsed/formed from it. We then gather and merge all options specifications just
like normal parsing. Finally we hand it off to L<Complete::Getopt::Long>.


=head1 FUNCTIONS

=head2 GetOptions(%cmdspec) => hash

Exported by default.

Process options and/or subcommand names specified in C<%cmdspec>, and remove
them from C<@ARGV> (thus modifying it). Will warn to STDERR on errors. Actual
command-line options parsing will be done using L<Getopt::Long>.

Return hash structure, with these keys: C<success> (bool, false if parsing
options failed e.g. unknown option/subcommand, illegal option value, etc),
C<subcommand> (str, subcommand name, if there is any; if there are nested
subcommands then it will be a path separated name, e.g. C<sub1/subsub1>).

Arguments:

=over

=item * summary => str

Used by autohelp (not yet implemented).

=item * options => hash

A hash of option names and its specification. The specification is the same as
what you would feed to L<Getopt::Long>'s C<GetOptions>.

=item * subcommands => hash

A hash of subcommand name and its specification. The specification looks like
C<GetOptions> argument, with keys like C<summary>, C<options>, C<subcommands>
(for nested subcommands).

=back

Differences with C<Getopt::Long>'s C<GetOptions>:

=over

=item *

Accept a command/subcommand specification (C<%cmdspec>) instead of just options
specification (C<%ospec>) like in C<Getopt::Long>).

=item *

This module's function returns hash instead of bool.

=item *

Coderefs in C<options> will receive an extra argument C<$res> which is the
result hash (being built). So the arguments that the coderefs get is:

 ($callback, $value, $res)

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

Autohelp. With summaries already in the spec, it's easy to generate useful help
message.

Summary for each option, e.g. perhaps C<< options => { 'opt1=s' =>
{summary=>'...', getopt=>\$foo}} >> instead of just C<< options => { 'opt1=s' =>
\$foo } >>. That is, we give a hashref for each option.

autoversion.

Autocomplete subcommand name.

Suggest correction for misspelled subcommand ('Did you mean foo?').


=head1 SEE ALSO

L<Getopt::Long>

L<Getopt::Long::Complete>

L<Perinci::CmdLine> - a more full featured command-line application framework,
also with subcommands and completion.

L<Pod::Weaver::Section::Completion::GetoptLongSubcommand>

=cut
