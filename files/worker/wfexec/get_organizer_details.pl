#! /usr/bin/perl

## Get the information to send a consent request email to
## the Organizer and NotificationList of a series
# https://jira.cilt.uct.ac.za/browse/OPENCAST-2247

# TODO: get notification list from series metadata when it is added

my $debug = 0;

use Data::Dumper;
use DateTime;
use DateTime::Format::Strptime;
use DateTime::Format::W3CDTF;
use LWP::UserAgent;
use HTTP::Cookies;
use HTTP::Request;
use HTTP::Request::Common qw(PUT POST);
use WWW::Mechanize;
use Time::Local;
use Try::Tiny;
use JSON;
use utf8;

# Get script arguments
my $mediapackage_id = $ARGV[0];
my $filename = $ARGV[1];

if (!defined($filename)) {
    $filename = "/dev/stdout";
}

die "\nSyntax:\n  $0 mediapackage-id output-file\n\n" if (!defined($mediapackage_id));

# Get authentication details for Opencast
my $oc_config = "/opt/opencast/etc/custom.properties";

my ($oc_host, $oc_user, $oc_pass) = getOcAuth($oc_config);

my $process_completed = 1;
my $process_result = "none";
my $series = '';
my $series_title = '';
my $series_owner_id;
my @series_notification_list;
my $valid_notification_list = '';
my $normalised_date = '';

my $organizer_name = '';
my $organizer_email = '';
my $submitter_name = '';
my $submitter_email = '';
my $cc = '';
my $site_id = '';

try {
    # Login to Opencast
    my $mech = WWW::Mechanize->new( autocheck => 0 );
    $mech->credentials($oc_user, $oc_pass);
    $mech->add_header( 'X-REQUESTED-AUTH' => 'Digest' );

    my $json = new JSON;

    my $event_workflow_json = getWorklowSubmitter($mech, $oc_host, $mediapackage_id);
    $submitter_name = $event_workflow_json->{name};
    $submitter_email = $event_workflow_json->{email};
    my $event_metadata_json = getEventMetadata($mech, $oc_host, $mediapackage_id);
    my $event_m = $json->utf8->canonical->decode($event_metadata_json);

    # Event fields - start_time is GMT
    $series = getEventField($event_m, "isPartOf");
    my $start_date = getEventField($event_m, "startDate");
    $normalised_date = normaliseDate($start_date);

    if (defined($series) && $series ne "") {
        my $series_metadata_json = getSeriesMetadata($mech, $server, $series);

        if ($series_metadata_json ne "") {
            my $series_m = $json->utf8->canonical->decode($series_metadata_json);
            $series_title = getSeriesField($series_m, "title");
            $series_owner_id = getSeriesField($series_m, "creator-id");
            @series_notification_list = getSeriesField($series_m, "notification-list");
            $site_id = getSeriesField($series_m, "site-id");
        }
    }
    if (@series_notification_list) {

        my @check_cc = ();

        foreach (@series_notification_list) {
            if (isValidEmailSyntax(@$_)) {
                push (@check_cc, @$_);
            }
        }

        if (@check_cc) {
            $cc = join ',', @check_cc;
            $valid_notification_list = "true"
        } else {
            $cc = "null";
            $valid_notification_list = "false"
        }

    }

    if (defined($series_owner_id) && $series_owner_id ne "") {
        my $user_details_json = getUserDetails($mech, $server, $series_owner_id);
        my $user_details_m = $json->utf8->canonical->decode($user_details_json);

        $organizer_name = $user_details_m->{user}->{name};
        $organizer_email = $user_details_m->{user}->{email};
        $process_completed = 1;
    }

    if ($debug) {
        print "Series: $series\n";
        print "title: $series_title\n";
        print "Name: $organizer_name\n";
        print "Email: $organizer_email [". isValidEmailSyntax($organizer_email) ."] \n";
        print "CC: $cc\n";
        print "-------------------------\n";
    }

} catch {
    $process_completed = 0;
    $process_result = $_;
    chomp $process_result;
} finally {

    open(my $fh, '>', $filename) or die "Could not open result file '$filename' $!";
    print $fh "get_organizer_success=" . ($process_completed ? 'true' : 'false') . "\n";
    print $fh "get_organizer_result=" . $process_result . "\n";
    print $fh "series_id=$series\n";
    print $fh "series_title=$series_title\n";
    print $fh "organizer_name=" . ($submitter_email eq "" ? $organizer_name : $submitter_name) . "\n";
    print $fh "organizer_email=" . ($submitter_email eq "" ? $organizer_email : $submitter_email) . "\n";
    print $fh "organizer_email_valid=". ( isValidEmailSyntax($organizer_email) ? "true" : "false" ) ."\n";
    print $fh "notification_list=$cc\n";
    print $fh "valid_notification_list=$valid_notification_list\n";
    print $fh "start_date=$normalised_date\n";
    print $fh "site_id=$site_id\n";
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

sub getWorklowSubmitter($$) {

  my $mech = shift;
  my $server = shift;
  my $mp = shift;

  my $json = new JSON;

  $mech->get("$server/admin-ng/event/$mp/workflows.json");
  my $response = $mech->response();
  if (!$response->is_success) {
       die "Unable to get event metadata for event $mp: " . $response->status_line;
  }

  my $workflows = $json->utf8->canonical->decode($response->decoded_content);
  my @results = @{$workflows->{results}};
  my $workflow_id = getWorkflowID(@results);
  
  $mech->get("$server/admin-ng/event/$mp/workflows/$workflow_id");
  my $response = $mech->response();
  if (!$response->is_success) {
       die "Unable to get event metadata for event $mp: " . $response->status_line;
  }

  my $workflow_json = $json->utf8->canonical->decode($response->decoded_content);
  my $creator_details = $workflow_json->{creator};
  return $creator_details;
}

sub getWorkflowID($$) {

  my @results = shift;
  my $first_workflow_id = "";
  my $first_workflow_date = "";
  my $dateformat = DateTime::Format::Strptime->new(pattern => '%Y-%m-%dT%H:%M:%SZ');

  for my $workflow( @results ) {
    my $current_date = $dateformat->parse_datetime($workflow->{submitted});

    if( $first_workflow_date eq "" ) {
      $first_workflow_id = $workflow->{id};
      $first_workflow_date = $current_date;
    } elsif( DateTime->compare($current_date, $first_workflow_date) == -1 ) {
      $first_workflow_id = $workflow->{id};
      $first_workflow_date = $current_date;
    }
  }

  return $first_workflow_id;
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

# User Details
# /users/{username}.json:
sub getUserDetails($$) {

  my $mech = shift;
  my $server = shift;
  my $username = shift;

  $mech->get("$server/users/$username.json");
  my $response = $mech->response();
  if (!$response->is_success) {
       die "Unable to get user details for $username: " . $response->status_line;
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

## get a particular field from an issue
sub getField($$$){
   my $structure = shift;
   my $field = shift;
   my $value_field = shift || 'value';
   my $value = '';

   if (defined $structure->{$field}) {
       if (ref($structure->{$field}) eq 'HASH') {
           $value = $structure->{$field}->{$value_field};
       } else {
           $value = $structure->{$field};
   	}
   }
   return $value;
}

## Does it look like an email address?
sub isValidEmailSyntax($) {
  my $addr = shift;

  ## Simple regexp from http://www.webmasterworld.com/forum13/251.htm
  return ($addr =~ /^(\w|\-|\_|\.)+\@((\w|\-|\_)+\.)+[a-zA-Z]{2,}$/);
}

## Turn the date into a normalised date-time readable string
sub normaliseDate($) {
  my $start_date = shift;
  my $date = substr($start_date, 0, 10);
  my $time = substr($start_date, 11, 8);
  my $formatter = DateTime::Format::Strptime->new(pattern => "%F  %T",time_zone=>'UTC');
  my $dt_obj = $formatter->parse_datetime("$date  $time");
  $dt_obj->set_time_zone('Africa/Johannesburg');
  return $dt_obj->strftime("%a, %d %b %Y %T");
}
