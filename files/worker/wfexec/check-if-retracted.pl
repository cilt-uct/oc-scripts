#! /usr/bin/perl

## Check if a retract workflow was run on the event 
## set workflow property called retracted_event = true/false
# https://jira.cilt.uct.ac.za/browse/OPENCAST-2989
# https://jira.cilt.uct.ac.za/browse/OPENCAST-2902

# Created: Ngoni Choga (2020-09-14)

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
use MIME::Base64;
use Time::Local;
use Try::Tiny;
use JSON;
use utf8;

# Get script arguments
my $mediapackage_id = $ARGV[0];
my $filename = $ARGV[1];

my $retracted;
my $process_result = "none";
my $process_completed = 0;

if (!defined($filename)) {
    $filename = "/dev/stdout";
}

die "\nSyntax:\n  $0 mediapackage-id output-file\n\n" if (!defined($mediapackage_id));

# Get authentication details for Opencast
my $oc_config = "/opt/opencast/etc/custom.properties";

my ($oc_host, $oc_user, $oc_pass) = getOcAuth($oc_config);
my @args = (Authorization => "Basic " . MIME::Base64::encode( $oc_user . ':' . $oc_pass ));

try {
    # Login to Opencast
    my $mech = WWW::Mechanize->new( autocheck => 1 );

    my $json = new JSON;

    my $event_workflows_json = getWorkflows($mech, $oc_host, $mediapackage_id);
    my $event_m = $json->utf8->canonical->decode($event_workflows_json);
    $retracted = hasBeenRetracted($event_m);

    if (defined($retracted) && $retracted ne "") {
      $process_completed = 1;
    }
    
    if ($debug) {
        print "retracted_event: $retracted\n";
        print "-------------------------\n";
    }

} catch {
    $process_completed = 0;
    $process_result = $_;
    chomp $process_result;
} finally {
    open(my $fh, '>', $filename) or die "Could not open result file '$filename' $!";
    print $fh "retracted_event=" . $retracted . "\n";
    close $fh;
};

exit 0;

# Get the basic auth configuration
sub getOcAuth($) {

  my $propsfile = shift;

  my $url;
  my $user;
  my $pass;

  open FILE, '<', $propsfile or die "Unable to open local Opencast properties file: $!\n";
  while(<FILE>) {
    chomp;
    if ($_ =~ /^org.opencastproject.security.admin.user=(.*)$/) {
        $user = $1;
    }
    if ($_ =~ /^org.opencastproject.security.admin.pass=(.*)$/) {
        $pass = $1;
    }
    if ($_ =~ /^org.opencastproject.admin.ui.url=(.*)$/) {
        $url = $1;
    }

  }
  close FILE;

  return ($url, $user, $pass);
}

# get json containing all workflow operations run on an event
sub getWorkflows($$) {

  my $mech = shift;
  my $server = shift;
  my $mp = shift;

  $mech->get("$server/admin-ng/event/$mp/workflows.json", @args);
  my $response = $mech->response();
  if (!$response->is_success) {
       die "Unable to get event metadata for event $mp: " . $response->status_line;
  }
  return $response->decoded_content;
}

# identify whether any of the workflows are the retract workflow
sub hasBeenRetracted($) {
  my $workflow_json = shift;
  my $set_retract = "false";
  my $workflow = "Retract";

  foreach my $item (@{$workflow_json->{results}}) {
    if ($item->{'title'} eq $workflow) {
        $set_retract = "true";
    }
  }

  return $set_retract;
}
