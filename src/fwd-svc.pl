#!/usr/bin/perl
use strict;
use feature ":5.10";
use warnings FATAL => 'all';

use Getopt::Long;

my $promptForKill = 1;

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

    if (@killPidList == 0){
        say "No PIDs to kill.";
        return;
    }

    my $input = "y";
    if ($promptForKill != 0){
        print "kill these[y/n]? ";
        $input = <STDIN>;
    }

    if ($input =~ /^y/i){
        foreach my $pid (@killPidList){
            system("kill", $pid);
        }
    }
}

sub getFilename() {
    my $DIR = $ENV{FWD_SVC_CONFIG_DIR} // "$ENV{HOME}/forwards";
    chomp(my @files = `ls -1 $DIR | grep '.csv\$'`);

    my $index = 0;
    foreach my $file (@files) {
        my $pos = ++$index;
        say "${pos}) $file";
        system("cat $DIR/$file | xargs -n 1 echo '    '")
    }

    print "which number? ";
    my $input = <STDIN>;

    if ($input !~ /^\d+$/) {
        die "Didn't get a number";
    }

    if ($input < 1 || $input > $index){
        die "invalid number";
    }

    return "$DIR/$files[$input - 1]";
}

#####################################################
# Main Script
#####################################################

my $filename;
chomp(my $kenv = `kubens -c`);
my $ps;
my $killall;
(my $exeName = $0) =~ s/^(?:.+\/)([^\/]+)$/$1/;
my $USAGE = "usage: $exeName --file <file> | $exeName --[ps|ls] | $exeName --killall";

GetOptions(
    "file=s" => \$filename,
    "killall" => \$killall,
    "ps" => \$ps,
    "ls" => \$ps,
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
    $filename = getFilename();
    if (!defined $filename) {
        say STDERR "filename is empty";
        die $USAGE;
    }
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
    $line =~ s/^(.*?)#.*$/$1/;

    if ($line =~ /^\s*$/) {
        next;
    }

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

say "kpods - filtered on pods we're currently running or wanting to run (KPODS map):";
foreach my $pod (sort {$a cmp $b} keys %podToFullnameMap){
    if (exists $desiredPodToPortMap{$pod} || exists $runningPodToLocalPortMap{$pod}){
        say "$pod -- $podToFullnameMap{$pod}";
    }
}
say "";

say "Pods we are currently running and their local port (RUNNING map):";
foreach my $runningPod (sort {$a cmp $b} keys %runningPodToLocalPortMap){
    say "$runningPod -- $runningPodToLocalPortMap{$runningPod}";
}
say "";

say "Pods we want to have running in the end-state (DESIRED map):";
foreach my $desiredPod (sort {$a cmp $b} keys %desiredPodToPortMap){
    say "$desiredPod -- $desiredPodToPortMap{$desiredPod}";
}
say "";

say "Commands to run:";
my @diffCommandList = ();
my @allCommandList = ();
foreach my $desiredPod (sort {$a cmp $b} keys %desiredPodToPortMap){
    my $port = $desiredPodToPortMap{$desiredPod};
    my $remotePort = "8080";
    if ($port =~ m/^(\d+):(\d+)$/) {
        $port = $1;
        $remotePort = $2;
    }

    my $podFullname = $podToFullnameMap{$desiredPod};
    if (!defined $podFullname){
        die "Unable to find pod $desiredPod via kpods command"
    }

    my $cmd = "kubectl port-forward $podFullname $port:$remotePort &";
    say $cmd;
    push (@allCommandList, $cmd);

    if (exists $runningPodToLocalPortMap{$desiredPod} && $runningPodToLocalPortMap{$desiredPod} == $port) {
        # this pod is already running
        next;
    }

    # say $cmd;
    push (@diffCommandList, $cmd);
}
say "";

if ((@diffCommandList == 0) && ((keys %desiredPodToPortMap) == (keys %runningPodToLocalPortMap))) {
    say "The running commands seem to be the same as desired commands - so not doing anything.";
    say "If you want to re-run them anyways, do `$exeName --killall` and then run this command again.";
    exit(0);
}

# print "run these kubectl commands[y/n]? ";
print "kill all current running, and run these commands? [y/n]? ";
my $input = <STDIN>;

if ($input =~ /^y/i){
    # foreach my $cmd (@diffCommandList){
    #     system($cmd);
    # }
    $promptForKill = 0;
    killAllRunning();
    sleep(2);
    foreach my $cmd (@allCommandList){
        system($cmd);
    }
} else {
    say "Doing nothing";
    exit(0);
}
