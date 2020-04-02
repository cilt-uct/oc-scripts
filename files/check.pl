#! /usr/bin/perl

use strict;
use File::Find::Rule;
use Cwd;
use Getopt::Long;
use Class::Unload;
use Class::Inspector;

sub uniq {
    my %seen;
    grep !$seen{$_}++, @_;
}

my $help = 0;
my $debug = 0;
my $dir = "/opt/opencast";
my @ignore_list = qw(Error feature warnings strict POSIX);

GetOptions ('debug' => \$debug, 'help' => \$help);

if ($help) {
    print "Options:\n\n" .
           " --debug     Show status and warnings\n";
    exit(1);
}

my @result = ();
my @files = File::Find::Rule->file()
                            ->name( '*.pl' )
                            ->in( $dir );

for my $file (@files) {
  open my $fh, "<", $file;  # lexical file handles, automatic error handling

  while (defined( my $line = <$fh> )) {
    my @matches = $line =~ /^use (\w*::\w*::\w*|\w*::\w*|\w*).*\;/g;
    
    foreach my $tester (@ignore_list) {
        @matches = grep ! /$tester/, @matches;
    }
    push @result, @matches;
  }
  close $fh;
}

@result = uniq(@result);
my @indiciesToKeep = grep { $result[$_] ne 'strict' } 0..$#result;
@result = @result[@indiciesToKeep];

my $err = 0;
foreach my $item (@result) {
    print "Checking $item: " if $debug;
    if (Class::Inspector->installed($item)) {
        print "Found\n" if $debug;
    } else {
        print "ERROR not found\n" if $debug;
        print "ERROR ($item) not found\n" if !$debug;
        $err = ++($err)
    }
}

if ($err == 0) {
    print "Found all modules :)\n"
}
