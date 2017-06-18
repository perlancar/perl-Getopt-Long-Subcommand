#!perl

use 5.010001;
use strict;
use warnings;
use Test::More 0.98;

use Getopt::Long::Subcommand;

subtest "basics" => sub {
    local @ARGV;
    my @output;

    my @spec = (
        configure => [ 'no_ignore_case', 'no_getopt_compat', 'gnu_compat', 'pass_through' ],
        summary   => 'Program summary',
        options   => {
            'help|h|?' => {
                summary => 'Display help',
                handler => sub { push @output, 'General help message' },
            },
            'version|v' => {
                summary => 'Display version',
                handler => sub { push @output, 'Version 1.0' },
            },
        },
        subcommands => {
            sc1 => {
                summary => 'Subcommand1 summary',
                options => {
                    'opt1|option1=s' => {
                        handler => sub { push @output, "set sc1.opt1|option1=$_[1]" },
                    },
                    'opt2|option2=s' => {
                        handler => sub { push @output, "set sc1.opt2|option2=$_[1]" },
                    },
                },
            },
            sc2 => {
                summary => 'Subcommand2 summary',
                options => {
                    'help|h|?' => {
                        summary => 'Display subcommand2 help',
                        handler => sub { push @output, 'Sc2 help message' },
                    },
                    'opt1|option1=i' => {
                        handler => sub { push @output, "set sc2.opt1|option1=$_[1]" },
                    },
                },
            },
        },
    );

    subtest "subcommand options" => sub {
        subtest "--option1 sc1 sc2" => sub {
            @output = ();
            @ARGV   = (qw/--option1 sc1 sc2/);
            my $res = GetOptions(@spec);
            is_deeply( \@output, [] );
            is_deeply( $res, { success => 0, subcommand => [] } );
        };
        subtest "sc1 --option1 sc2" => sub {
            @output = ();
            @ARGV   = (qw/sc1 --option1 sc2/);
            my $res = GetOptions(@spec);
            is_deeply( \@output, ['set sc1.opt1|option1=sc2'] );
            is_deeply( $res, { success => 1, subcommand => ['sc1'] } );
        };
        subtest "sc1 --opt1 sc2" => sub {
            @output = ();
            @ARGV   = (qw/sc1 --opt1 sc2/);
            my $res = GetOptions(@spec);
            is_deeply( \@output, ['set sc1.opt1|option1=sc2'] );
            is_deeply( $res, { success => 1, subcommand => ['sc1'] } );
        };
    };
};

done_testing;
