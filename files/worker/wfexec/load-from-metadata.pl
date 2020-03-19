#! /usr/bin/perl

use strict;

use WWW::Mechanize;
use Time::Local;
use Try::Tiny;
use JSON;

my $oc_config = "/opt/opencast/etc/custom.properties";

my ($server, $oc_user, $oc_pass) = getOcAuth($oc_config);

my $mpid = $ARGV[0];
my $filename = $ARGV[1];

die "\nSyntax:\n  $0 mediapackageid output-file\n\n" if (!defined($mpid));

if (!defined($filename)) {
    $filename = "/dev/stdout";
}

# Series fields
my $course = "";
my $caption_provider = "unknown";
my $process_completed = 1;
my $process_result = "none";
my $is_personal_series = "false";

# Output
my $final_result = "";

try {
    my $mech = WWW::Mechanize->new( autocheck => 0 );
    $mech->credentials($oc_user, $oc_pass);
    $mech->add_header( 'X-REQUESTED-AUTH' => 'Digest' );

    my $json = new JSON;

    my $event_metadata_json = getEventMetadata($mech, $server, $mpid);
    my $event_m = $json->utf8->canonical->decode($event_metadata_json);

    # Event fields - start_time is GMT
    my $series         = getEventField($event_m, "isPartOf");
    my $event_date     = getEventField($event_m, "startDate");
    my $gmt_start_time = getEventField($event_m, "startTime");
    my $duration       = getEventField($event_m, "duration");
    my $location       = getEventField($event_m, "location");
    my $title          = getEventField($event_m, "title");

    if (defined($series) && $series ne "") {
        my $series_acl = getSeriesACL($mech, $server, $series);
        my $series_metadata_json = getSeriesMetadata($mech, $server, $series);

        if ($series_metadata_json ne "") {
            my $series_m = $json->utf8->canonical->decode($series_metadata_json);
            my $series_title = getSeriesField($series_m, "title");
            $course = getSeriesField($series_m, "course");
            $caption_provider = getSeriesField($series_m, "caption-type");
            $is_personal_series = ( begins_with($series_title, "Personal Series") ? "true" : "false" );

            $process_completed = 1;
        }
    }

} catch {
  $process_completed = 0;
  $process_result = $_;
  chomp $process_result;
} finally {

    open(my $fh, '>', $filename) or die "Could not open result file '$filename' $!";
    print $fh "metadata_load_success=" . ($process_completed ? 'true' : 'false') . "\n";
    print $fh "metadata_load_result=" . $process_result . "\n";
    print $fh "caption_provider=$caption_provider\n";
    print $fh "use_watson=true\n" if ($caption_provider eq "watson");
    print $fh "use_nibity=true\n" if ($caption_provider eq "nibity");
    print $fh "is_personal_series=". $is_personal_series ."\n";
    print $fh "metadata_result=" . $final_result . "\n" if ($final_result ne "");
    close $fh;
};
exit 0;


###############################################################
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

# Series ACL

sub getSeriesACL($$) {

    my $mech = shift;
    my $server = shift;
    my $series = shift;
    my $result = "";

    $mech->get("$server/series/$series/acl.json");
    my $response = $mech->response();

    if (!$response->is_success) {
        $final_result = "Unable to get series ACL for series $series: " . $response->status_line;
    } else {
        $result = $response->decoded_content;
    }

    return $result;
}

# Series Metadata
sub getSeriesMetadata($$) {

    my $mech = shift;
    my $server = shift;
    my $series = shift;
    my $result = "";

    $mech->get("$server/api/series/$series/metadata");
    my $response = $mech->response();
    if (!$response->is_success) {
        $final_result = "Unable to get series metadata for series $series: " . $response->status_line;
    } else {
        $result = $response->decoded_content;
    }

    return $result;
}

# Event Metadata
# /api/events/MPID?withacl=true&withmetadata=true to get location, start, duration, series (isPartOf), ACL, e.g.:
sub getEventMetadata($$) {

  my $mech = shift;
  my $server = shift;
  my $mp = shift;

  $mech->get("$server/api/events/$mp?withacl=true&withmetadata=true");
  my $response = $mech->response();
  if (!$response->is_success) {
       die "Unable to get event metadata for event $mp: " . $response->status_line;
  }
  return $response->decoded_content;
}

# Get event field from JSON
sub getEventField($$) {

  my $jhash = shift;
  my $field = shift;
  my $value;

  # For now assume we only have 1 metadata catalog for an event
  foreach my $item (@{$jhash->{metadata}[0]->{fields}}) {
    if ($item->{'id'} eq $field) {
        $value = $item->{'value'};
    }
  }

  return $value;
}

# Get series field from JSON
sub getSeriesField($$) {

  my $jhash = shift;
  my $field = shift;
  my $value;

  foreach my $catalog (@{$jhash}) {
    foreach my $item (@{$catalog->{fields}}) {
        if ($item->{'id'} eq $field) {
          $value = $item->{'value'};
        }
    }
  }

  return $value;
}

sub begins_with {
    return substr($_[0], 0, length($_[1])) eq $_[1];
}