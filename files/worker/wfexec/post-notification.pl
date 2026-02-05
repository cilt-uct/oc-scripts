#!/usr/bin/perl

# Notify middleware of a workflow operation
# https://cilt.atlassian.net/browse/OPENCAST-3291
# https://cilt.atlassian.net/browse/AMA-1291

use strict;
use warnings;
use Data::Dumper;

use WWW::Mechanize;
use Time::Local;
use Try::Tiny;
use JSON;

# Get script arguments
my $mediapackage_id = $ARGV[0];
my $subject = $ARGV[1];
my $debug = $ARGV[2];

die "\nSyntax:\n  $0 #{id} subject\n\n" if (!defined($mediapackage_id) || !defined($subject));

if (!defined($debug)) {
    $debug = 0;
} else {
    $debug = 1;
}

# Get the digest auth configuration from the local config file
sub getOcAuth($) {

    my $propsfile = shift;

    my $url;
    my $user;
    my $pass;

    open FILE, '<', $propsfile or die "Unable to open local Opencast properties file: $!\n";
    while(<FILE>) {
        chomp;
        if ($_ =~ /^org.opencastproject.security.digest.user=(.*)$/) {
            $user = $1;
        }
        if ($_ =~ /^org.opencastproject.security.digest.pass=(.*)$/) {
            $pass = $1;
        }
        if ($_ =~ /^org.opencastproject.admin.ui.url=(.*)$/) {
            $url = $1;
        }

    }
    close FILE;

    return ($url, $user, $pass);
}

my ($server, $oc_user, $oc_pass) = getOcAuth("/opt/opencast/etc/custom.properties");

try {
    my $url = ($server eq "https://mediadev.uct.ac.za") ? "https://srvubuclt004.uct.ac.za" : "https://srvubuclt002.uct.ac.za";

    my $payload = {
        subject => $subject,
        mediapackage_id => $mediapackage_id
    };

    print "$url/d2l/api/notification\n" if $debug;
    print Dumper($payload) if $debug;

    my $json_payload = encode_json($payload);
    my $mech = WWW::Mechanize->new();
    $mech->add_header('Content-Type' => 'application/json');
    $mech->post( "$url/d2l/api/notification", Content => $json_payload);
    warn "HTTP POST failed: " . $mech->status() if (!$mech->success);
} catch {
    warn ("ERR: $_\n");
};
exit 0;
