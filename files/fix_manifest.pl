#! /usr/bin/perl

# Change the manifest of a media package to refer to local urls
#
# 2017-05-08: Created : Corne Oosthuizen
#
# 2017-05-17: Corne Oosthuizen
#    Added an argument to change the id of a mediapackage
#
# 2018-02-08: Corne Oosthuizen
#    Changed to new layout of manifest url
#
# TODO: remove published

use XML::Twig;
use List::Util 'first';
use Cwd;

use strict;
no warnings 'all';

my $path = $ARGV[0];
my $newid = $ARGV[1];
my $file_manifest = "$path/manifest.xml";

my @file_catalogs = glob("$path/catalog-*.xml");
my $file_catalog = $file_catalogs[0];

sub changeManifest($$) {

    my ($file, $newid) = @_;

    local $/ = undef;
    open FILE, $file or die "Couldn't open file: $!";
    binmode FILE;
    my $doc = <FILE>;
    close FILE;

    my $handler = {
                    url => sub {
                        my @parts = split (":", $_->text);
                        my $parts_len = scalar @parts;

                        #print $_->text;
                        #print "@parts[$parts_len-2]\n";
                        if ($parts_len > 1) {
                            #my $match = first { /track-/ } @parts;
                            my @files = glob(@parts[$parts_len-2].".*"); #urn:matterhorn:a9cb5ffa-1a38-475c-9b32-210617401061:1:track-0:presenter.mkv
                            #print "@files\n";
                            $_->set_text(@files[0]);
                        }
                    },
                    #to_delete elements
                    publications => sub { $_->delete() },
                    checksum => sub { $_->delete() },
                };

    my $twig = XML::Twig->new( twig_handlers => $handler);
    $twig->parse($doc);

    if (length($newid) > 0) {
        my ($event) = $twig->findnodes('/mediapackage[@id]');
        $event->set_att(id => $newid);
    }

    $twig->print_to_file($file);
}

sub changeCatalog($$) {

    my ($file, $newid) = @_;

    local $/ = undef;
    open FILE, $file or die "Couldn't open file: $!";
    binmode FILE;
    my $doc = <FILE>;
    close FILE;

    my $handler = {
                    'dcterms:identifier' => sub {
                            $_->set_text($newid);
                    },
                };

    my $twig = XML::Twig->new( twig_handlers => $handler);
    $twig->parse($doc);
    $twig->print_to_file($file);
}

if (length($newid) > 0) {
    print "\nUsing NewId: ". $newid ."\n";
}

my $dir = cwd();
chdir $path;
changeManifest($file_manifest, $newid);

if (length($newid) > 0) {
    changeCatalog($file_catalog, $newid);
}
chdir $dir;
