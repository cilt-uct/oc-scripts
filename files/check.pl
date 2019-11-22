#! /usr/bin/perl

use strict;
use File::Find::Rule;
use Cwd;
use Data::Dumper;

sub uniq {
    my %seen;
    grep !$seen{$_}++, @_;
}

my $debug = 0;
my @result = ();

my $dir = getcwd; # '/opt';
$dir = '/opt' if $debug;

# Find all the subdirectories of the work directory - ansible copies this to /opt
# follows means we also go through system linked folders
my @subdirs = File::Find::Rule->directory->extras({ follow => 1 })->name( '*opencast*' )->in( $dir );
print Dumper(@subdirs) if $debug;

my @files = File::Find::Rule->file()
                            ->name( '*.pl' )
                            ->in( @subdirs );

# while (defined(my $file = glob '/opt/opencast/wfexec/*.pl')) {
for my $file (@files) {
  open my $fh, "<", $file;  # lexical file handles, automatic error handling

  while (defined( my $line = <$fh> )) {
    my @matches = $line =~ /^use (\w*::\w*::\w*|\w*::\w*|\w*).*\;/g;
    print Dumper(@matches) if $debug;
    push @result, @matches;
  }
  close $fh;
}

@result = uniq(@result);
my @indiciesToKeep = grep { $result[$_] ne 'strict' } 0..$#result;
@result = @result[@indiciesToKeep];

my $err = 0;
foreach my $item (@result) {
    my $rc =  eval "use $item; 1; ";
    print "Checking $item: " if $debug;
    if (!$rc) {
        print "ERROR not found\n" if $debug;
        print "ERROR ($item) not found\n" if !$debug;
        $err = ++($err)
    }
    else {
        print "Found\n" if $debug;
    }
}

if ($err == 0) {
    print "Found all modules :)\n"
}
