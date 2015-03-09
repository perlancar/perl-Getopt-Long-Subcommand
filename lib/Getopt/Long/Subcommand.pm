package Getopt::Long::Subcommand;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;
use Log::Any::IfLOG '$log';

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(
                    GetOptions
            );

# XXX completion is actually only allowed at the top-level
my @known_cmdspec_keys = qw(
    options
    subcommands
    summary description
    completion
);

sub _cmdspec_opts_to_gl_ospec {
    my ($cmdspec_opts, $is_completion, $res) = @_;
    return { map {
        if ($is_completion) {
            # we don't want side-effects during completion (handler printing or
            # existing, etc), so we set an empty coderef for all handlers.
            ($_ => sub{});
        } else {
            my $k = $_;
            my $v = $cmdspec_opts->{$k};
            my $handler = ref($v) eq 'HASH' ? $v->{handler} : $v;
            if (ref($handler) eq 'CODE') {
                my $orig_handler = $handler;
                $handler = sub {
                    my ($cb, $val) = @_;
                    $orig_handler->($cb, $val, $res);
                };
            }
            ($k => $handler);
        }
    } keys %$cmdspec_opts };
}

sub _gl_getoptions {
    require Getopt::Long;

    my ($ospec, $pass_through) = @_;
    $log->tracef('[comp][glsubc] Performing Getopt::Long::GetOptions');

    my $old_conf = Getopt::Long::Configure(
        'no_ignore_case', 'bundling',
        ('pass_through') x !!$pass_through,
    );
    local $SIG{__WARN__} = sub {} if $pass_through;
    $log->tracef('[comp][glsubc] @ARGV before Getopt::Long::GetOptions: %s', \@ARGV);
    $log->tracef('[comp][glsubc] spec for Getopt::Long::GetOptions: %s', $ospec);
    my $gl_res = Getopt::Long::GetOptions(%$ospec);
    $log->tracef('[comp][glsubc] @ARGV after  Getopt::Long::GetOptions: %s', \@ARGV);
    Getopt::Long::Configure($old_conf);
    $gl_res;
}

sub _GetOptions {
    my ($cmdspec, $is_completion, $res, $stash) = @_;

    $res //= {success=>undef};
    $stash //= {
        path => '', # for displaying error message
        level => 0,
    };

    # check command spec
    {
        use experimental 'smartmatch';
        $log->tracef("[comp][glsubc] Checking cmdspec keys: %s", [keys %$cmdspec]);
        for (keys %$cmdspec) {
            $_ ~~ @known_cmdspec_keys
                or die "Unknown command specification key '$_'" .
                    ($stash->{path} ? " (under $stash->{path})" : "") . "\n";
        }
    }

    my $has_opts = $cmdspec->{options} && keys(%{$cmdspec->{options}});
    unless ($has_opts) {
        $res->{success} = 1;
        return $res;
    }

    my $has_subcommands = $cmdspec->{subcommands} &&
        keys(%{$cmdspec->{subcommands}});
    my $pass_through = $has_subcommands || $is_completion;

    my $ospec = _cmdspec_opts_to_gl_ospec(
        $cmdspec->{options}, $is_completion, $res);
    unless (_gl_getoptions($ospec, $pass_through)) {
        $res->{success} = 0;
        return $res;
    }

    # for doing completion
    if ($is_completion) {
        $res->{comp_ospec} //= {};
        for (keys %$ospec) {
            $res->{comp_ospec}{$_} = $ospec->{$_};
        }
    }

    if ($has_subcommands) {
        # for doing completion of subcommand names
        if ($is_completion) {
            $res->{comp_subcommand_names}[$stash->{level}] =
                [sort keys %{$cmdspec->{subcommands}}];
        }

        unless (@ARGV) {
            warn "Missing subcommand".
                ($stash->{path} ? " for $stash->{path}":"")."\n"
                    unless $is_completion;
            $res->{success} = 0;
            return $res;
        }
        my $sc_name = shift @ARGV;

        # for doing completion of subcommand names
        if ($is_completion) {
            push @{ $res->{comp_subcommand_name} }, $sc_name;
        }

        my $sc_spec = $cmdspec->{subcommands}{$sc_name};
        unless ($sc_spec) {
            warn "Unknown subcommand '$sc_name'".
                ($stash->{path} ? " for $stash->{path}":"")."\n"
                    unless $is_completion;
            $res->{success} = 0;
            return $res;
        };
        $res->{subcommand} //= [];
        push @{ $res->{subcommand} }, $sc_name;
        local $stash->{path} = ($stash->{path} ? "/" : "") . $sc_name;
        local $stash->{level} = $stash->{level}+1;
        _GetOptions($sc_spec, $is_completion, $res, $stash);
    }
    $res->{success} //= 1;

    $log->tracef('[comp][glsubc] Final @ARGV: %s', \@ARGV) unless $stash->{path};
    #$log->tracef('[comp][glsubc] TMP: stash=%s', $stash);
    #$log->tracef('[comp][glsubc] TMP: res=%s', $res);
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

    my $res = _GetOptions(\%cmdspec, $is_completion);

    if ($is_completion) {
        my $ospec = $res->{comp_ospec};
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

                # complete subcommand names
                if ($type eq 'arg' &&
                        $args{argpos} < @{$res->{comp_subcommand_names}//[]}) {
                    require Complete::Util;
                    return Complete::Util::complete_array_elem(
                        array => $res->{comp_subcommand_names}[$args{argpos}],
                        word  => $res->{comp_subcommand_name}[$args{argpos}],
                    );
                }

                $args{getopt_res} = $res;
                $args{subcommand} = $res->{comp_subcommand_name};
                $cmdspec{completion}->(%args) if $cmdspec{completion};
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

    $res;
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
         'help|h|?' => {
             summary => 'Display help message',
             handler => sub {
                 my ($cb, $val, $res) = @_;
                 if ($res->{subcommand}) {
                     say "Help message for $res->{subcommand} ...";
                 } else {
                     say "General help message ...";
                 }
                 exit 0;
             },
         'version|v' => {
             summary => 'Display program version',
             handler => sub {
                 say "Program version $main::VERSION";
                 exit 0;
             },
         'verbose' => {
             handler => \$opts{verbose},
         },
     },

     # list your subcommands here
     subcommands => {
         subcmd1 => {
             summary => 'The first subcommand',
             # subcommand-specific options
             options => {
                 'foo=i' => {
                     handler => \$opts{foo},
                 },
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

     # tell how to complete option value and arguments. see
     # Getopt::Long::Complete for more details, the arguments are the same
     # except there is an additional 'subcommand' that gives the subcommand
     # name.
     completion => sub {
         my %args = @_;
         ...
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

How parsing works: First we call C<Getopt::Long::GetOptions> with the top-level
options, passing through unknown options if we have subcommands. Then,
subcommand name is taken from the first argument. If subcommand has options, the
process is repeated. So C<Getopt::Long::GetOptions> is called once at every
level.

Completion: Scripts using this module can complete themselves. Just put your
script somewhere in your C<PATH> and run something like this in your bash shell:
C<complete -C script-name script-name>. See also L<shcompgen> to manage
completion scripts for multiple applications easily.

How completion works: Environment variable C<COMP_LINE> or C<COMMAND_LINE> (for
tcsh) is first checked. If it exists, we are in completion mode and C<@ARGV> is
parsed/formed from it. We then perform parsing to get subcommand names. Finally
we hand it off to L<Complete::Getopt::Long>.


=head1 FUNCTIONS

=head2 GetOptions(%cmdspec) => hash

Exported by default.

Process options and/or subcommand names specified in C<%cmdspec>, and remove
them from C<@ARGV> (thus modifying it). Will warn to STDERR on errors. Actual
command-line options parsing will be done using L<Getopt::Long>.

Return hash structure, with these keys: C<success> (bool, false if parsing
options failed e.g. unknown option/subcommand, illegal option value, etc),
C<subcommand> (array of str, subcommand name, if there is any; nested
subcommands will be listed in order, e.g. C<< ["sub1", "subsub1"] >>).

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


=head1 SEE ALSO

L<Getopt::Long>

L<Getopt::Long::Complete>

L<Perinci::CmdLine> - a more full featured command-line application framework,
also with subcommands and completion.

L<Pod::Weaver::Section::Completion::GetoptLongSubcommand>

=cut
