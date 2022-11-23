#!/usr/bin/perl
use strict;
use feature 'say';
use warnings FATAL => 'all';

use Getopt::Long;

sub killAllRunning() {
    chomp(my @lines = `ps -ef | grep port-forward | grep -v grep`);

    my @killPidList = ();
    foreach my $line (@lines){
        say $line;
        (my $pid = $line) =~ s/^\s*\d+\s*(\d+)\s.+$/$1/;
        if (defined $pid){
            push(@killPidList, $pid);
            say "pid to kill: $pid"
        }
    }

    print "run these kill these[y/n]? ";
    my $input = <STDIN>;

    if ($input =~ /^y/i){
        foreach my $pid (@killPidList){
            system("kill", $pid);
        }
    }
}

my $filename = "";
chomp(my $kenv = `kubens -c`);
my $ps;
my $killall;
(my $exeName = $0) =~ s/^(?:.+\/)([^\/]+)$/$1/;
my $USAGE = "usage: $exeName --file <file> | $exeName --ps | $exeName --killall";

GetOptions(
    "file=s" => \$filename,
    "killall" => \$killall,
    "ps" => \$ps,
) or die $USAGE;

if (defined $ps) {
    system("ps -e -o command | grep port-forward | grep -v grep");
    exit $?;
}

if (defined $killall) {
    killAllRunning();
    exit(0);
}

if (!defined $filename) {
    say STDERR "filename is empty";
    die $USAGE;
}

if ($kenv !~ /staging|sandbox|production/) {
   die "Invalid value for kenv"
}

if (! -r $filename){
    die "Not readable: $filename";
}

chomp(my @lines = `cat $filename`);

# File format is: pod:port

my %desiredPodToPortMap = ();
foreach my $line (@lines) {
    my ($pod, $port) = split(/,/, $line, -1);
    # say "pod=$pod";
    # say "port=$port";
    $desiredPodToPortMap{$pod} = $port;
}

chomp(my @running = `ps -e -o command | grep port-forward | grep -v grep`);
# chomp(my @running = `/Users/dibokette/bin/port-forward_temp`);
my %runningPodToLocalPortMap = ();
foreach my $runEntry (@running){
    if ($runEntry =~ m/^.+port-forward (.+?)-$kenv\S+ (\d+).+$/) {
        $runningPodToLocalPortMap{$1} = $2;
    }
}

chomp(my @kpods = `kubectl get pods | cut -d ' ' -f 1`);
# chomp(my @kpods = `/Users/dibokette/bin/kpods_temp | grep $kenv | cut -d ' ' -f 1`);
$? != 0 and die "Could not run kubectl - need to run avp?";

my %podToFullnameMap = ();
foreach my $kpod (@kpods){
    (my $podname = $kpod) =~ s/(^.+?)-${kenv}-.+$/$1/;
    # $kpod =~ s/(^.+?)-${kenv}-.+$/$1/;
    $podToFullnameMap{$podname} = $kpod;
}

say "KPODS map:";
foreach my $pod (sort {$a cmp $b} keys %podToFullnameMap){
    if (exists $desiredPodToPortMap{$pod} || exists $runningPodToLocalPortMap{$pod}){
        say "$pod -- $podToFullnameMap{$pod}";
    }
}

say "RUNNING map:";
foreach my $runningPod (sort {$a cmp $b} keys %runningPodToLocalPortMap){
    say "$runningPod -- $runningPodToLocalPortMap{$runningPod}";
}

say "DESIRED map:";
foreach my $desiredPod (sort {$a cmp $b} keys %desiredPodToPortMap){
    say "$desiredPod -- $desiredPodToPortMap{$desiredPod}";
}

say "Commands to run:";
my @commandList = ();
foreach my $desiredPod (sort {$a cmp $b} keys %desiredPodToPortMap){
    if (exists $runningPodToLocalPortMap{$desiredPod}){
        # this pod is already running
        next;
    }

    my $podFullname = $podToFullnameMap{$desiredPod};
    if (!defined $podFullname){
        die "Unable to find pod $desiredPod via kpods command"
    }

    my $port = $desiredPodToPortMap{$desiredPod};
    my $remotePort = "8080";
    if ($port =~ m/^(\d+):(\d+)$/) {
        $port = $1;
        $remotePort = $2;
    }

    my $cmd = "kubectl port-forward $podFullname $port:$remotePort &";
    say $cmd;
    push (@commandList, $cmd);
}

if (@commandList == 0){
    say "Did not get any commands to run";
    exit(0);
}

print "run these kubectl commands[y/n]? ";
my $input = <STDIN>;

if ($input =~ /^y/i){
    foreach my $cmd (@commandList){
        system($cmd);
    }
} else {
    say "Doing nothing";
    exit(0);
}

