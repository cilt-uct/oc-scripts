#! /usr/bin/perl


## Output some random test data

my $trackname=$ARGV[0];
my $filename = $ARGV[1];

die "\nSyntax:\n $0 track-filename output-file\n\n" if (!defined($trackname));

if (!defined($filename)) {
    $filename = "/dev/stdout";
}

## Write result
open(my $fh, '>', $filename) or die "File ERROR: failed to open result file '$filename' $!";
print $fh "test$$=$trackname\n";
close $fh;

exit 0;

