#!/usr/bin/perl -w

# Author: Troels Arvin <tra@sst.dk>
# Patched By : DessaiImrane <dessai.imrane@gmail.com>
#
# $Date: 2013-08-01 15:10:00 +0400 (Thu, 01 August 2013) $
#
# Copyright (c) 2009, Danish National Board of Health.
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#     * Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#     * Neither the name of the  the Danish National Board of Health nor the
#       names of its contributors may be used to endorse or promote products
#       derived from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY the Danish National Board of Health ''AS IS'' AND ANY
# EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL the Danish National Board of Health BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

# This plugin allows you to query the disk usage percentage of a disk,
# via the VMWare vSphere/vcenter API.
# This means that virtual machines may be monitored for disk space problems
# without having to install+configure special agent software or SNMP agents
# on the virtual servers.
# The downside is that the vcenter API is based on the SOAP protocol which
# is an obese and ugly protocol; thus, this plugin may result in higher
# overall resource usage, compared to (e.g.) a SNMP based check.

# Requirements:
# ------------
#  On the server where this script it to be executed:
#  - vcenter/vSphere SDK for Perl:
#    http://www.vmware.com/support/developer/viperltoolkit/
#  - The OS environment may need to be adjusted to allow the vSphere SDK
#    modules to be found by the plugin. E.g., if the SDK is installed in
#    /usr/local/vmware, you may set the following environment variable:
#    PERL5LIB=/usr/local/vmware/lib/vmware-vcli/VMware/share/VMware
#
#  Other requirements:
#  - A vSphere/vCenter server governing the relevant ESX installation.
#  - A user on the vSphere/vcenter server with minimal privileges - just
#    enough to read virtual machine status information. The plugin defaults
#    to using a user called "nagios" (password "nagios"), but this may
#    be adjusted via plugin arguments.

# Written with http://nagiosplug.sourceforge.net/developer-guidelines.html
# in mind. Doesn't use Nagios perl-modules, in order to minimize
# dependencies.

# Reminder: Nagios status codes:
#  0 = OK
#  1 = Warning
#  2 = Critical
#  3 = Unknown

# TODO:
#  - what happens if the guest has CDs / removable flash storage?

use strict;

use Getopt::Std;
use File::Basename;
use Data::Dumper;

# installed by the vcenter SDK:
use XML::LibXML;
use VMware::VIRuntime;

# Defaults:
my $user    =  'shinken';
my $pass    =  'shinken';
my $warn    =        85; # pct
my $crit    =        95; # pct
my $timeout =        30; # seconds
my $vcenter = 'vcenter';
my $exclude =        '';
my $debug   =         0;
my $giga    =         1024*1024*1024;
my $sessionfile = '';

# -------------------------------------------------------------
# Helper functions
# -------------------------------------------------------------

sub VERSION_MESSAGE {
    my $rev='$Revision: 15333 $';
    $rev =~ s/\$Revision: (\d+).*/$1/;
    print "SVN revision: $rev\n";
}

sub HELP_MESSAGE {
    use vars qw($user $pass $warn $crit $timeout);
    print "Usage (all on one line):\n";
    print '  '.basename($0)." -D <vcenter hostname> -N <name of guest>\n";
    print "     [ -u <username> ] [ -p <password> ]\n";
    print "     [ -w <warn %> ]   [ -c <crit %> ]\n";
    print "     [ -t <timeout secs> ] [ -e <exclude regex> ] [ -d ] [-S sessionfile] \n\n";
    print "If disk usage for any disk is above the specified thresholds, \n";
    print "a non-OK status is returned.\n\n";
    print "Defaults:\n";
    print " for -D: $vcenter\n";
    print " for -u: $user\n";
    print " for -p: $pass\n";
    print " for -w: $warn\n";
    print " for -c: $crit\n";
    print " for -t: $timeout\n\n";
    print "The -N parameter is matched case sensitively.\n\n";
    print "For the -e argument, the regular expression dialect is case sensitive\n";
    print "perl regular expressions. Paths which match the regex are excluded \n";
    print "from the check. E.g., to exclude paths called exactly C:\\ or D:\\ \n";
    print "give the following argument to -e: ^[CD]:\\\$ \n";
    print "The -d argument asks for debug mode.\n";
    print "The -S argument is the session file to make authentication faster against vCenter.\n";
    exit 3; 
}

sub err {
    my $arg = shift;
    print STDERR "Error: $arg\n";
    exit 3;
}

sub nagios_exit {
    my $retcode = shift;
    my $msg = shift;
    print $msg;
    exit $retcode;
}

# -------------------------------------------------------------
# Sanity checks, handling of changes of default values
# -------------------------------------------------------------
$Getopt::Std::STANDARD_HELP_VERSION = 1;
my %options;
getopts('hD:N:u:p:w:c:t:e:dS:',\%options) or HELP_MESSAGE();

if (exists $options{'h'}) {
    HELP_MESSAGE();
}

if (not exists $options{'D'}) { err "No vcenter hostname indicated"; }
if (not exists $options{'N'}) { err "No guest name indicated"; }

my $guest = $options{'N'};

if (exists $options{'D'}) { $vcenter = $options{'D'}; }
if (exists $options{'u'}) { $user    = $options{'u'}; }
if (exists $options{'p'}) { $pass    = $options{'p'}; }
if (exists $options{'w'}) { $warn    = $options{'w'}; }
if (exists $options{'c'}) { $crit    = $options{'c'}; }
if (exists $options{'t'}) { $timeout = $options{'t'}; }
if (exists $options{'e'}) { $exclude = quotemeta($options{'e'}); }
if (exists $options{'d'}) { $debug   = 1; }
if (exists $options{'S'}) { $sessionfile    = $options{'S'}; }

if (not $warn =~ m/^-?[\d.]+$/) {
    err "non-numeric value for warn parameter requested";
}

if (not $crit =~ m/^-?[\d.]+$/) {
    err "non-numeric value for crit parameter requested";
}

if ($warn > $crit) {
    err "warn > crit";
}

print "Using exclude regex: $exclude\n" if $exclude and $debug;

# -------------------------------------------------------------
# Connection handling, and data acquisition
# -------------------------------------------------------------
my $url = "https://$vcenter/sdk/webService";

# Give the API an opportunity to handle the timeout, but only
# if it isn't handled within five seconds
$SIG{ALRM} = sub { nagios_exit(3,'Timeout'); };
alarm($timeout+5);


    if (defined($sessionfile) and -e $sessionfile) {
	Opts::set_option("sessionfile", $sessionfile);
	eval {
		my $conn_res = Util::connect($url,$user,$pass);
		$conn_res->{vim_service}->{vim_soap}->{user_agent}->{timeout} = $timeout;
    
	};
	if ($@) {
		Opts::set_option("sessionfile", undef);
		my $conn_res = Util::connect($url, $user, $pass);
		$conn_res->{vim_service}->{vim_soap}->{user_agent}->{timeout} = $timeout;
	}	
    }
    else
    {
	    my $conn_res = Util::connect($url, $user, $pass);
	    $conn_res->{vim_service}->{vim_soap}->{user_agent}->{timeout} = $timeout;
    }
    if (defined($sessionfile))
    {
	    Vim::save_session(session_file => $sessionfile);
    }

    if (!$Util::is_connected) {
        nagios_exit(3,"Could not connect to vcenter server '".$vcenter."'");
    }

    my $vm;
    eval {
        $vm = Vim::find_entity_view(view_type => 'VirtualMachine', filter => { 'guest.guestState' => 'running', 'name' => $guest } );
    };
    if ($@) {
        Util::disconnect;
        nagios_exit(3,"SOAP error while communicating with guest '$guest'");
    }
    Util::disconnect;
    if (!$vm) {
        nagios_exit(3,"Guest '$guest' not found, or not running");
    }
    my @disks = $vm->guest->disk;

alarm(0);

#debug#print Dumper (Vim::get_vim) . "\n\n\n";

# -------------------------------------------------------------
# Evaluate data obtained
# -------------------------------------------------------------
my $path;
my $capacity;
my $freeSpace;

my $used;
my $fill_pct;

my $total_capacity = 0;
my $total_used = 0;

my @error_strings= ();
my @perfdata_strings= ();

my $retcode = 0;

my $i = 0;
my $num_excluded = 0;

print "Disks: " . Dumper (@disks) . "\n\n\n" if $debug;

while (exists $disks[0]->[$i]) {

    $path = $disks[0]->[$i]->diskPath;

    if ($path) {

        if ($exclude && $path =~ m/$exclude/) {

            print "path=$path EXCLUDED from check\n" if $debug;
            $num_excluded++;

        } else {

            $capacity = $disks[0]->[$i]->capacity/$giga;
            $freeSpace = $disks[0]->[$i]->freeSpace/$giga;

            $used = $capacity - $freeSpace;
            $fill_pct = ($used/$capacity)*100;

            $total_capacity += $capacity;
            $total_used+= $used;

            print "DEBUG: path=$path; capacity=$capacity; freeSpace=$freeSpace; used=$used; fill_pct=$fill_pct; total_capacity=$total_capacity; total_used: $total_used\n" if $debug;
            push @perfdata_strings, "'". $path . " UsedSpace'=" . sprintf("%.2f",$used) . "GB;;" . sprintf("%.2f", $capacity);
            push @perfdata_strings, "'". $path . " Usage'=" . int($fill_pct+.5) . "%;" . $warn . ";" . $crit;

	    if ($fill_pct > $warn) {
                push @error_strings, $path . ' usage%=' . int($fill_pct+.5);
                if ($fill_pct > $crit) {
                    $retcode = 2;
                } else {
                    if ($retcode < 1) {
                        # don't decrease a potentially already CRITICAL to WARNING
                        $retcode = 1;
                    }
                }
            }
        }

        $i++;
    }
}
if ($i == 0) {
    $retcode = 3;
    push @error_strings, "no disks found on guest; this is sometimes seen when a guest is being migrated between ESX hosts";
}

# -------------------------------------------------------------
# Build return texts, and determine return code
# -------------------------------------------------------------
my $return_msg = 'DISKUSAGE ';

if ($retcode > 2) {
    $return_msg .= 'UNKNOWN - ' . join('; ', @error_strings);
    nagios_exit(3,$return_msg);
}
if ($retcode >0 ) {
    if ($retcode == 2) {
        $return_msg .= 'CRITICAL';
    } else {
        $return_msg .= 'WARNING';
    }
    if ($num_excluded > 0) {
        $return_msg .= " ($num_excluded paths excluded)";
    }
    $return_msg .= ' - '. join('; ', @error_strings);
} else {
    $return_msg .= "OK ";
    if ($num_excluded > 0) {
        $return_msg .= "($num_excluded paths excluded) ";
    }
    $return_msg .= "- thresholds: warn%=$warn, crit%=$crit";
}

if ($total_capacity > 0) {
	#$return_msg .= "|'total capacity'=${total_capacity}B 'total used'=${total_used}B";
    $return_msg .= "| " . join('; ', @perfdata_strings) ;
}

$return_msg .= "\n";
nagios_exit($retcode,$return_msg);
