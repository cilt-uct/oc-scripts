#! /usr/bin/perl

use strict;

use WWW::Mechanize;
use LWP::Protocol::https;
use Time::Local;
use Try::Tiny;
use JSON;

my $oc_config = "/opt/opencast/etc/custom.properties";
my $tt_ws = "http://srvslscet001.uct.ac.za/timetable/";

my %tt_comment;
$tt_comment{'true'}  = "TIMETABLED event: edit and publish";
$tt_comment{'false'} = "Check CONSENT, edit and publish";

my ($server, $oc_user, $oc_pass) = getOcAuth($oc_config);

# print "server: $server user: $oc_user pass: $oc_pass\n";

my $mpid = $ARGV[0];
my $filename = $ARGV[1];

die "\nSyntax:\n  $0 mediapackageid output-file\n\n" if (!defined($mpid));

if (!defined($filename)) {
    $filename = "/dev/stdout";
}

my $numEventAttempts = 0;

my $timetable_completed = 0;
my $timetable_result = "";
my $timetabled = "false";
my $visibility = "unknown";
my $course = "unknown";
my $caption_provider = "unknown";
my $location = "unknown";
my $tt_info = "none";

## Should this event be marked for trimming?
my $event_trim = "true";

try {
  my $mech = WWW::Mechanize->new( autocheck => 0 );
  $mech->credentials($oc_user, $oc_pass);
  $mech->add_header( 'X-REQUESTED-AUTH' => 'Digest' );

  my $json = new JSON;

  ## Test event data

  #my $series = "8d3ec06f-8c5a-499b-ac1f-aa2ee8841c01";
  #my $course = "MAM1000W,2017";
  #my $event_date="2017-08-14";
  #my $start_time="08:00";
  #my $end_time="08:50";
  #my $location = "nlt";

  ## Get the mediapackage info
  my $event_metadata_json = getEventMetadata($mech, $server, $mpid);
  my $event_m = $json->utf8->canonical->decode($event_metadata_json);

  # Event fields - start_time is GMT

  my $series         = getEventField($event_m, "isPartOf");
  my $event_date     = getEventField($event_m, "startDate");
  my $gmt_start_time = getEventField($event_m, "startTime");
  my $duration       = getEventField($event_m, "duration");
  my $location       = getEventField($event_m, "location");
  my $title          = getEventField($event_m, "title");

  my $start_time = GMT_LocalStartTime($event_date);

  # Date portion of W3CDTF format for startDate
  $event_date = substr($event_date, 0, 10);

  my $end_time = StartDuration_EndTime($event_date . "T" . $start_time, $duration);

  # Don't mark for trim if this is a backup event
  if ((index(lc($title), "[backup]") != -1) || (index(lc($title), "[hold]") != -1) ||
      (index(lc($title), "(backup)") != -1) || (index(lc($title), "(hold)") != -1)) {
    $event_trim = "false";
  }

  ## Get the series info
  if (defined($series) && $series ne "") {
      my $series_acl = getSeriesACL($mech, $server, $series);

      if ($series_acl =~ /ROLE_ANONYMOUS/) {
        $visibility = "public";
      } else {
        $visibility = "vula";
      }

      my $series_metadata_json = getSeriesMetadata($mech, $server, $series);

    if ($series_metadata_json ne "") {
      my $series_m = $json->utf8->canonical->decode($series_metadata_json);
        $course = getSeriesField($series_m, "course");
        $caption_provider = getSeriesField($series_m, "caption-type");
    }
  }

  ## Adjust the start and end times to cater for early start or late end
  ($start_time, $end_time) = adjustCheckTime($start_time, $end_time);

  ## Check with the timetable webservice
  my $tt_result = "false";

  if (!defined($course) || $course eq "") {
      $course = "none";
  }

  if (($course ne "none") && defined($event_date) && defined($start_time) && defined($end_time) && defined($location)) {
      my $tt = WWW::Mechanize->new( autocheck => 0 );

      $tt->get($tt_ws . "?course=$course&event-date=$event_date&start=$start_time&end=$end_time&venue=$location");
      my $response = $tt->response();

      if (!$response->is_success) {
        die "Unable to check timetable: " . $response->status_line;
      } else {
        $tt_result = $response->decoded_content;
      }
  }

  ## Conclusion
  if (($tt_result eq "true") && ($visibility ne "public")) {
      $timetabled = "true";
  }

  $tt_info = "$course;$location;$event_date;$start_time;$end_time;$visibility";
  $timetable_completed = 1;
} catch {
  $timetable_completed = 0;
  $timetable_result = $_;
  chomp $timetable_result;
} finally {

  ## Write result
  open(my $fh, '>', $filename) or die "Could not open result file '$filename' $!";
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
    $timetable_completed = 0;
    #$timetable_result = "Unable to get series ACL for series $series: " . $response->status_line;
    die "Unable to get series ACL for series $series: " . $response->status_line;
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
    $timetable_completed = 0;
    #$timetable_result = "Unable to get series metadata for series $series: " . $response->status_line;
    die "Unable to get series metadata for series $series: " . $response->status_line;
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
  $numEventAttempts++;
  my $response = $mech->response();
  if (!$response->is_success) {
    if ($numEventAttempts < 3) {
      sleep(60);
      return getEventMetadata($mech, $server, $mp);
    } else {
      die "Unable to get event metadata for event $mp: " . $response->status_line;
    }
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

# Convert to localtime, from http://www.perlmonks.org/?node_id=873435

sub GMT_LocalStartTime
{
  my $t = shift;
  my ($startDate, $startTime) = split(/T/,$t,2);
  my ($year, $month, $day) =
      $startDate =~ /(\d+)-(\d\d)-(\d\d)/;
  my ($hour, $minute, $rest) = split(/:/, $startTime, 3);

  my $epoch = timegm (0,0,$hour,$day,$month-1,$year);

  my ($lyear,$lmonth,$lday,$lhour,$isdst) =
            (localtime($epoch))[5,4,3,2,-1];

  $lyear += 1900;  # year is 1900 based
  $lmonth++;       # month number is zero based
  return ( sprintf("%02d:%s", $lhour,$minute) );
}

# Calculate end time from start and duration

sub StartDuration_EndTime
{
  my $start_dt = shift;
  my $duration = shift;

  my ($year, $month, $day, $hour, $min) = $start_dt =~ /(\d+)-(\d\d)-(\d\d)T(\d\d):(\d\d)/;
  my $time = timelocal(0, $min, $hour, $day, $month-1, $year);
  my ($d_h, $d_m, $d_s) = split(/:/, $duration);
  my $endtime = $time + $d_s + $d_m * 60 + $d_h * 3600;
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($endtime);

  return ( sprintf("%02d:%02d", $hour, $min) );
}

# Adjust start and end times

sub adjustCheckTime($$)
{
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


