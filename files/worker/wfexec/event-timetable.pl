#! /usr/bin/perl

use strict;

use Data::Dumper;
use WWW::Mechanize;
use LWP::Protocol::https;
use DateTime;
use DateTime::Duration;
use DateTime::Format::Duration;
use DateTime::Format::W3CDTF;
use Try::Tiny;
use JSON;

my $debug = 0;
my $oc_config = "/opt/opencast/etc/custom.properties";
my $tt_ws = "http://srvslscet001.uct.ac.za/timetable/";

my %tt_comment;
$tt_comment{'true'}  = "TIMETABLED event: edit and publish";
$tt_comment{'false'} = "Check CONSENT, edit and publish";

my ($server, $oc_user, $oc_pass) = getOcAuth($oc_config);
print "server: $server user: $oc_user pass: $oc_pass\n" if $debug;

my $mpid = $ARGV[0];
my $filename = $ARGV[1];

die "\nSyntax:\n  $0 mediapackageid output-file\n\n" if (!defined($mpid));

if (!defined($filename)) {
    $filename = "/dev/stdout";
}

my $w3c = DateTime::Format::W3CDTF->new;
my $dfd_t = DateTime::Format::Duration->new( pattern => '%H:%M:%S' );

my $json = new JSON;
my $sleep = 30;
$sleep = 1 if $debug;

my $mech = WWW::Mechanize->new( autocheck => 0 );
$mech->credentials($oc_user, $oc_pass);
$mech->add_header( 'X-REQUESTED-AUTH' => 'Digest' );

my $numEventAttempts = 0;

my $timetable_completed = 0;
my $timetable_result = "";
my $timetabled = "false";
my $visibility = "unknown";
my $course = "none";
my $caption_provider = "unknown";
my $location = "unknown";
my $title = "unknown";
my $series = "";
my $tt_info = "none";
my $tt_result = "false";
my $event_trim = "true"; # Should this event be marked for trimming?
my ($series, $event_date, $duration, $title, $start_time, $end_time) = ("","","","","","");
($series, $event_date, $duration, $title, $start_time, $end_time) = getEventDetails($mech, $server, $mpid);
print Dumper($series, $event_date, $duration, $title, $start_time, $end_time) if $debug;

# Don't mark for trim if this is a backup event
if ((index(lc($title), "[backup]") != -1) || (index(lc($title), "[hold]") != -1) ||
    (index(lc($title), "(backup)") != -1) || (index(lc($title), "(hold)") != -1) ||
    ($title eq "unknown") || ($title eq "")) {
    $event_trim = "false";
}

## Get the series info
if (defined($series) && $series ne "") {

    ($visibility, $course, $caption_provider) = getSeriesDetails($mech, $server, $series);
    print Dumper($visibility, $course, $caption_provider) if $debug;

    if (!defined($course) || $course eq "") {
      $course = "none";
    }

    if ($course ne "none") {
        if (!($course =~ /[\w]{3}[\d]{4}[\w]{1},[\d]{4}/)) {
            die "Course Code ERROR: ". $course;
        }

        ## Check with the timetable webservice
        if (($course =~ /[\w]{3}[\d]{4}[\w]{1},[\d]{4}/) && defined($event_date) && defined($start_time) && defined($end_time) && defined($location)) {

            my ($st, $et) = adjustCheckTime($start_time, $end_time);

            my $tt_url = $tt_ws . "?course=$course&event-date=$event_date&start=$st&end=$et&venue=$location";
            print "timetable_url: ". $tt_url ."\n" if $debug;
            my $tt = WWW::Mechanize->new( autocheck => 0 );
            $tt->get($tt_url);
            my $response = $tt->response();
            if (!$response->is_success) {
                die "Timetable ERROR [". $response->status_line ."]: ". $tt_url;
            } else {
                $tt_result = $response->decoded_content;
            }
        }
    }
}

## Conclusion
if (($tt_result eq "true") && ($visibility ne "public")) {
    $timetabled = "true";
}

$tt_info = "$course;$location;$event_date;$start_time;$end_time;$visibility";
$timetable_completed = 1;

## Write result
open(my $fh, '>', $filename) or die "File ERROR: failed to open result file '$filename' $!";
print $fh "timetabled=$timetabled\n";
print $fh "timetable_info=$tt_info\n";
print $fh "timetable_comment=" . $tt_comment{$timetabled} . "\n"  if ($timetable_completed);
print $fh "timetable_comment=" . $timetable_result . "\n"  if (!$timetable_completed);
print $fh "timetable_success=" . ($timetable_completed ? 'true' : 'false') . "\n";
print $fh "event_location=$location\n";
print $fh "event_trim=$event_trim\n";
print $fh "caption_provider=$caption_provider\n";
print $fh "use_watson=true\n" if ($caption_provider eq "watson");
print $fh "use_nibity=true\n" if ($caption_provider eq "nibity");
close $fh;

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

# Series Metadata
sub getSeriesDetails($$$) {

    my $mech = shift;
    my $server = shift;
    my $series_id = shift;

    my $meta;
    my ($visibility, $course, $caption_provider, $series_acl) = ("vula", "", "", "");

    try {
        $series_acl = getMetadata($mech, "$server/series/$series/acl.json", 0) =~ /ROLE_ANONYMOUS/;
    } catch {
        $series_acl = getMetadata($mech, "$server/admin-ng/series/$series/access.json", 0) =~ /ROLE_ANONYMOUS/;
    };

    if ($series_acl) {
        $visibility = "public";
    }

    try {
        $meta = getMetadata($mech, "$server/api/series/$series/metadata", 1);
    } catch {
        $meta = getMetadata($mech, "$server/admin-ng/series/$series/metadata.json", 1);
    };

    if (defined($meta)) {
        $course = getSeriesField($meta, "course");
        $caption_provider = getSeriesField($meta, "caption-type");
    }

    return ($visibility, $course, $caption_provider)
}

# Event Metadata
sub getEventDetails($$$) {

    my $mech = shift;
    my $server = shift;
    my $mp = shift;

    ## Get the mediapackage info from api / admin-ng
    my ($series, $event_date, $duration, $title, $start_time, $end_time) = ("","","","","","");
    try {
        $numEventAttempts = 0;
        my $event_m = getMetadata($mech, "$server/api/events/$mp/metadata?type=dublincore%2Fepisode", 1);

        $series     = getEventField($event_m, "isPartOf", 0);
        $event_date = $w3c->parse_datetime(getEventField($event_m, "startDate", 0) ."T". getEventField($event_m, "startTime", 0) ."Z");
        $duration   = getEventField($event_m, "duration", 0);
        $title      = getEventField($event_m, "title", 0);
        $location   = getEventField($event_m, "location", 0);
    } catch {
        $numEventAttempts = 0;
        my $event_m = getMetadata($mech, "$server/admin-ng/event/$mp/metadata.json", 1);

        $series     = getEventField($event_m, "isPartOf", 1);
        $event_date = $w3c->parse_datetime(getEventField($event_m, "startDate", 1));
        $duration   = getEventField($event_m, "duration", 1);
        $title      = getEventField($event_m, "title", 1);
        $location   = getEventField($event_m, "location", 1);
    };

    my $local_time = $event_date->clone()->set_time_zone('GMT')->set_time_zone('Africa/Johannesburg');
    my $local_end_time = $local_time + $dfd_t->parse_duration($duration);

    $start_time = $local_time->strftime("%H:%M");
    $event_date = $local_time->strftime("%Y-%m-%d");
    $end_time   = $local_end_time->strftime("%H:%M");

    return ($series, $event_date, $duration, $title, $start_time, $end_time);
}

sub getMetadata($$$) {
    my $mech = shift;
    my $url = shift;
    my $encode = shift;

    $mech->get($url);
    $numEventAttempts++;
    my $response = $mech->response();
    if (!$response->is_success) {
        if ($numEventAttempts < 3) {
            sleep($sleep);
            return getMetadata($mech, $url);
        } else {
            die "Metadata ERROR [". $response->status_line ."]: ". $url;
        }
    }
    if ($encode) {
        return $json->utf8->canonical->decode($response->decoded_content);
    }
    return $response->decoded_content;
}

# Get event field from JSON
sub getEventField($$$) {

    my $jhash = shift;
    my $check = shift;
    my $use_field = shift;
    my $value;

    if ($use_field) {
        foreach my $fields (@{$jhash}[0]->{'fields'}) {
            foreach my $item (@{$fields}) {
                if ($item->{'id'} eq $check) {
                    $value = $item->{'value'};
                }
            }
        }
    } else {
        foreach my $field (@{$jhash}) {
            if ($field->{'id'} eq $check) {
                $value = $field->{'value'};
            }
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


# Adjust start and end times
sub adjustCheckTime($$) {
    my $s = shift;
    my $e = shift;

    my ($s_h, $s_m) = $s =~ /(\d\d):(\d\d)/;
    my ($e_h, $e_m) = $e =~ /(\d\d):(\d\d)/;

    # Bump from hh:50 to start of next hour (hh+1:00)
    if ($s_m >= 50) {
        $s_h++;
        $s = sprintf("%02d:00", $s_h);
    }

    # Move end time back to :45.
    if ($e_m > 45) {
        $e = sprintf("%02d:45", $s_h);
    }

    return ($s, $e);
}
