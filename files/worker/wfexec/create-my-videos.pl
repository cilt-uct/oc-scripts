#! /usr/bin/perl

use strict;

require LWP::UserAgent;
require HTTP::Request;

use WWW::Mechanize;
use Try::Tiny;
use JSON;
use Attempt;
no if $] >= 5.018, warnings =>  "experimental::smartmatch";

my $debug = 0;
my $oc_config = "/opt/opencast/etc/custom.properties";
my $vula_config = "/opt/opencast/etc/org.opencastproject.userdirectory.sakai-vula.cfg";

my ($server, $oc_user, $oc_pass) = getOcAuth($oc_config);
print "server: $server user: $oc_user pass: $oc_pass\n" if $debug;

my ($vula_server, $vula_user, $vula_pass) = getVulaAuth($vula_config);
# $vula_server = "https://vuladev.uct.ac.za" if $debug;
# $vula_server = "https://srvubucle104.uct.ac.za:8443"; ## REMOVE THIS LINE WHEN ALL SAKAI SERVERS ARE UPDATED ##

print "vula_server: $vula_server user: $vula_user pass: $vula_pass\n" if $debug;

my $mpid = $ARGV[0];
my $filename = $ARGV[1];
my $file_result = "not found";

die "\nSyntax:\n  $0 mediapackageid output-file\n\n" if (!defined($mpid));

if (!defined($filename)) {
    $filename = "/dev/stdout";
}

try {
    my $mech = WWW::Mechanize->new( autocheck => 0 );
    $mech->credentials($oc_user, $oc_pass);
    $mech->add_header( 'X-REQUESTED-AUTH' => 'Digest' );
    $mech->add_header( 'Accept' => 'application/v1.1.0+json' );
    $mech->add_header( 'X-Opencast-Matterhorn-Authorization' => 'true' );

    my $json = new JSON;

    my $event_metadata_json = getEventMetadata($mech, $server, $mpid);
    my $event_m = $json->utf8->canonical->decode($event_metadata_json);

    my $series_id = getEventField($event_m, "isPartOf");

    if (defined($series_id) && $series_id ne "") {
        my $series_metadata = decode_json(getSeriesMetadata($mech, $server, $series_id));
        my $userEid = getSeriesField($series_metadata, "creator-id");

        if ($userEid =~ m/[0-9]{8}|[a-zA-Z]{6}[0-9]{3}|[T|t][0-9]{7}/){
            $file_result = "userEid: ". $userEid;

            my ($session, $server_direct) = ('','');
            my $ua= LWP::UserAgent->new;
            $ua->timeout(60);
            $ua->env_proxy;

            attempt {
                print "  Attempting login: \n" if $debug;
                ### Start a Sakai session
                my $login_response = $ua->post("$vula_server/sakai-ws/rest/uct/loginToServer", [
                    id => $vula_user,
                    pw => $vula_pass
                ]);

                if ($login_response->is_success) {
                    ($session, $server_direct) = split(',', $login_response->decoded_content);
                    print "  Logged into: $server_direct\n" if $debug;
                } else {
                    $file_result = $login_response->code ."|Login Failed [$vula_server]";
                    print "  $file_result\n" if $debug;
                    die $file_result;
                }
            } tries => 5, delay => 20;

            if ($session ne '') {
                my $tool_response = $ua->post("$vula_server/sakai-ws/rest/uct/addExternalToolToUserHomeById", [
                        sessionid => $session,
                        tooltitle => "My Videos",
                        ltilaunchurl => "https://media.uct.ac.za/lti",
                        lticustomparams => "tool=ltitools/manage/\nsid=$series_id\ntype=personal",
                        toolid => "sakai.opencast.personal",
                        userEid => $userEid
                    ]);

                print "Tool response: " . $tool_response->code . "\n" if $debug;
                if ($tool_response->code == 200) {
                    my ($action, $site_id) = split(':', $tool_response->decoded_content);

                    if (($action eq "added") || ($action eq "updated")) {

                        # Set up the metadata JSON
                		my @ext_fields;

                		# DublinCore
                		push @ext_fields, fieldHash("site-id", $site_id);
                		my $ext_json = $json->pretty->encode(\@ext_fields);

                        print $ext_json ."\n" if $debug;

                        if (updateSeriesMetadata($mech, $series_id, "ext/series", $ext_json)) {
                            $file_result = "metadata: ". $action .' '. $series_id .' '. $site_id;
                        } else {
                            $file_result = "metadata_error: ". $action .' '. $series_id .' '. $site_id;
                        }
                    } else {
                        $file_result = "set_tool_error: ". $action .' '. $series_id .' '. $site_id;
                    }
                } else { # tool response
                    $file_result = "error [". $mpid ."] tool response: ". $tool_response->code;
                }

                my $logout_response = $ua->post("$vula_server/sakai-ws/rest/login/logout", [ sessionid => $session ]);

            } # not logged in
        } # if proper user EID
   } # if we have a series_id

} catch {
  $file_result = "error [". $mpid ."] $_";
} finally {
    print "update_LTI_tool=" . $file_result . "\n" if $debug;
    open(my $fh, '>', $filename) or die "Could not open result file '$filename' $!";
    print $fh "update_LTI_tool=" . $file_result . "\n";
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

sub getVulaAuth($) {

    my $propsfile = shift;

    my $host;
    my $user;
    my $pass;

    open FILE, '<', $propsfile or die "Unable to open local Opencast properties file: $!\n";
    while(<FILE>) {
        chomp;
        if ($_ =~ /^org.opencastproject.userdirectory.sakai.user=(.*)$/) {
            $user = $1;
        }
        if ($_ =~ /^org.opencastproject.userdirectory.sakai.password=(.*)$/) {
            $pass = $1;
        }
        if ($_ =~ /^org.opencastproject.userdirectory.sakai.url=(.*)$/) {
            $host = $1;
        }
    }
    close FILE;

    return ($host, $user, $pass);
}

# Series Metadata
sub getSeriesMetadata($$$) {

    my $mech = shift;
    my $server = shift;
    my $series = shift;
    my $result = "";

    $mech->get("$server/api/series/$series/metadata");
    my $response = $mech->response();
    if (!$response->is_success) {
        $result = "";
    } else {
        $result = $response->decoded_content;
    }

    return $result;
}

# Event Metadata
# /api/events/MPID?withacl=true&withmetadata=true to get location, start, duration, series (isPartOf), ACL, e.g.:
sub getEventMetadata($$$) {

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

sub fieldHash($$) {
    my $id = shift;
    my $value = shift;
    my %field;
    $field{"id"} = $id;
    $field{"value"} = $value;
    return \%field;
}

# Update series metadata - untested
sub updateSeriesMetadata($$$$) {

	my $mech = shift;
	my $seriesid = shift;
	my $metadata_type = shift;
	my $metadata_json = shift;

    # /api/series/da61b95f-0073-4a74-b1ef-791d039f8b14/metadata?type=ext%2Fseries

	my $ws = "api/series/$seriesid/metadata?type=$metadata_type";
	my $url = "$server/$ws";

	$mech->put($url, Content => "metadata=". $metadata_json);
	my $response = $mech->response();

    print $response->decoded_content ."\n";
	if (!$response->is_success) {
		return 0;
	} else {
		return 1;
	}
}
