#!/usr/bin/env perl
use strict;
use warnings;

# KD5FMU ASL3 Saytime Weather TimeFormat
# Uses recorded .gsm sound files from the original Time-Weather-Announce style package.
# Weather data is provided by WeatherAPI.com cache files created by asl3-weatherapi-update.sh.

my $config_file = "/etc/asterisk/local/weatherapi.ini";
my %cfg = read_ini($config_file);

my $arg1 = shift @ARGV;
my $arg2 = shift @ARGV;
my $arg3 = shift @ARGV;
my $arg4 = shift @ARGV;

my $location = $cfg{LOCATION} || "";
my $node     = $cfg{NODE} || "";
my $timefmt  = $cfg{TIME_FORMAT} || "12";
my $silent   = 0;  # 0=play, 1=save time+wx, 2=save weather only, legacy-compatible

# Legacy-friendly calling:
#   saytime.pl NODE
#   saytime.pl LOCATION NODE
#   saytime.pl LOCATION NODE 12|24
#   saytime.pl LOCATION NODE 0|1|2 12|24
if (defined $arg1 && !defined $arg2) {
    $node = $arg1;
} elsif (defined $arg1 && defined $arg2) {
    $location = $arg1;
    $node = $arg2;
    if (defined $arg3) {
        if ($arg3 =~ /^(12|24)$/) { $timefmt = $arg3; }
        elsif ($arg3 =~ /^[012]$/) { $silent = $arg3; }
    }
    if (defined $arg4 && $arg4 =~ /^(12|24)$/) { $timefmt = $arg4; }
}

$node =~ s/[^0-9]//g;
$timefmt = ($timefmt eq "24") ? "24" : "12";

if (!$node || $node eq "YOUR_NODE_NUMBER") {
    die "Node number missing. Add NODE=\"your_node\" in $config_file or run: saytime.pl LOCATION NODE [12|24]\n";
}

my $base      = $cfg{SOUNDS_DIR} || "/usr/local/share/asterisk/sounds/custom";
my $outdir    = "/tmp";
my $outfile   = "$outdir/current-time.gsm";
my $cache_dir = $cfg{CACHE_DIR} || "/var/cache/asl3-saytime-weather";
my $env_file  = "$cache_dir/current.env";

# Refresh WeatherAPI.com cache if missing or older than 20 minutes.
if ($location && (!-f $env_file || (time - (stat($env_file))[9]) > 1200)) {
    system("/usr/local/sbin/asl3-weatherapi-update.sh >/dev/null 2>&1");
}

my %wx = (-f $env_file) ? read_ini($env_file) : ();
my @sounds;

push @sounds, build_time_sounds() unless $silent == 2;

# Add a short real silence between the time and weather so it does not sound like a run-on sentence.
my $pause_file = "$base/pause-350ms.gsm";
push @sounds, $pause_file if %wx && $silent != 2 && -f $pause_file;

push @sounds, build_weather_sounds(\%wx) if %wx;

@sounds = grep { defined $_ && -f $_ } @sounds;
die "No usable .gsm sound files found. Check that sound_files.zip was extracted under $base\n" unless @sounds;

unlink $outfile if -f $outfile;
my $cat = "cat " . join(' ', map { shell_quote($_) } @sounds) . " > " . shell_quote($outfile);
system($cat) == 0 or die "Could not create $outfile\n";
chmod 0644, $outfile;

if ($silent == 0) {
    system('/usr/sbin/asterisk', '-rx', "rpt localplay $node $outdir/current-time");
    sleep 5;
    unlink $outfile;
} elsif ($silent == 1) {
    print "Saved time and weather sound file to $outfile\n";
} elsif ($silent == 2) {
    print "Saved weather sound file to $outfile\n";
}

exit 0;

sub read_ini {
    my ($file) = @_;
    my %h;
    return %h unless -f $file;
    open my $fh, '<', $file or return %h;
    while (my $line = <$fh>) {
        chomp $line;
        $line =~ s/\r$//;
        next if $line =~ /^\s*(#|$)/;
        next unless $line =~ /^\s*([A-Za-z0-9_]+)\s*=\s*(.*?)\s*$/;
        my ($k, $v) = ($1, $2);
        $v =~ s/^"//; $v =~ s/"$//;
        $h{$k} = $v;
    }
    close $fh;
    return %h;
}

sub shell_quote {
    my ($s) = @_;
    $s =~ s/'/'\\''/g;
    return "'$s'";
}

sub sound_candidates {
    my ($name) = @_;
    return () unless defined $name && length $name;
    $name = lc $name;
    $name =~ s/\s+/-/g;
    $name =~ s/[^a-z0-9_\-]//g;
    return (
        "$base/$name.gsm",
        "$base/digits/$name.gsm",
        "$base/wx/$name.gsm",
        "$base/weather/$name.gsm",
        "$base/silence/$name.gsm",
    );
}

sub find_sound {
    my ($name) = @_;
    for my $p (sound_candidates($name)) {
        return $p if -f $p;
    }
    return undef;
}

sub add_sound {
    my ($name) = @_;
    my $p = find_sound($name);
    return defined $p ? ($p) : ();
}

sub add_number {
    my ($num) = @_;
    my @f;
    return @f unless defined $num && $num =~ /^-?\d+$/;
    if ($num < 0) {
        push @f, add_sound('minus');
        $num = abs($num);
    }
    if ($num < 20) {
        push @f, add_sound($num);
    } elsif ($num < 100) {
        my $tens = int($num / 10) * 10;
        my $ones = $num % 10;
        push @f, add_sound($tens);
        push @f, add_sound($ones) if $ones;
    } elsif ($num < 200) {
        push @f, add_sound('1');
        push @f, add_sound('hundred');
        my $rest = $num - 100;
        push @f, add_number($rest) if $rest;
    } else {
        # Fallback: speak each digit if no pre-recorded full number exists.
        push @f, add_sound($_) for split //, $num;
    }
    return @f;
}

sub build_time_sounds {
    my @f;
    my ($sec, $min, $hour) = localtime();

    if ($hour < 12) { push @f, add_sound('good-morning'); }
    elsif ($hour < 18) { push @f, add_sound('good-afternoon'); }
    else { push @f, add_sound('good-evening'); }

    push @f, add_sound('the-time-is');

    if ($timefmt eq '24') {
    # Spoken 24-hour time with leading zero for 01 through 09.
    # Examples:
    #   01:00 = "zero one hundred hours"
    #   09:00 = "zero nine hundred hours"
    #   21:00 = "twenty-one hundred hours"
    #   01:15 = "zero one hours and fifteen minutes"

    if ($min == 0) {
        push @f, add_sound('0') if $hour < 10;
        push @f, add_number($hour);
        push @f, add_sound('hundred');
        push @f, add_sound('hours');
    } else {
        push @f, add_sound('0') if $hour < 10;
        push @f, add_number($hour);
        push @f, add_sound($hour == 1 ? 'hour' : 'hours');
        push @f, add_sound('and');
        push @f, add_number($min);
        push @f, add_sound($min == 1 ? 'minute' : 'minutes');
    }
} else {
        my $ampm = $hour >= 12 ? 'p-m' : 'a-m';
        my $h12 = $hour % 12; $h12 = 12 if $h12 == 0;
        push @f, add_number($h12);
        if ($min == 0) {
            push @f, add_sound('oclock');
        } elsif ($min < 10) {
            push @f, add_sound('oh');
            push @f, add_number($min);
        } else {
            push @f, add_number($min);
        }
        push @f, add_sound($ampm);
    }

    return @f;
}

sub build_weather_sounds {
    my ($wx) = @_;
    my @f;
    my $unit = uc($cfg{TEMP_UNIT} || 'F');
    my $condition = $wx->{CONDITION} || '';
    my $temp = ($unit eq 'C') ? $wx->{TEMP_C} : $wx->{TEMP_F};
    my $feels = ($unit eq 'C') ? $wx->{FEELSLIKE_C} : $wx->{FEELSLIKE_F};

    return @f unless $condition || defined $temp;

    push @f, add_sound('weather');
    push @f, add_sound('conditions');

    # WeatherAPI.com may return multi-word conditions, such as "Partly cloudy".
    # Try a phrase file first, then speak every available word in order.
    push @f, condition_sounds($condition) if $condition;

    if (defined $temp && $temp ne '') {
        push @f, add_sound('temperature');
        push @f, add_number(int($temp));
        push @f, add_sound('degrees');
    }

    if (($cfg{ANNOUNCE_FEELS_LIKE} || 'no') =~ /^y/i && defined $feels && $feels ne '') {
        push @f, add_sound('feels'), add_sound('like');
        push @f, add_number(int($feels));
        push @f, add_sound('degrees');
    }

    if (($cfg{ANNOUNCE_HUMIDITY} || 'no') =~ /^y/i && defined $wx->{HUMIDITY} && $wx->{HUMIDITY} ne '') {
        push @f, add_sound('humidity');
        push @f, add_number(int($wx->{HUMIDITY}));
        push @f, add_sound('percent');
    }

    return @f;
}

sub condition_sounds {
    my ($phrase) = @_;
    my @f;
    $phrase = lc($phrase || '');
    $phrase =~ s/[^a-z0-9\s-]/ /g;
    $phrase =~ s/\s+/ /g;
    $phrase =~ s/^\s+|\s+$//g;
    return @f unless $phrase;

    my $hyphen = $phrase; $hyphen =~ s/\s+/-/g;
    my $under  = $phrase; $under  =~ s/\s+/_/g;
    for my $candidate ($hyphen, $under) {
        my $p = find_sound($candidate);
        if ($p) { push @f, $p; return @f; }
    }

    # Speak each real condition word in order. Do not throw away "partly".
    $phrase =~ s/-/ /g;
    my @words = grep { length $_ } split /\s+/, $phrase;
    for my $w (@words) {
        next if $w =~ /^(with|in|the|and|nearby)$/;
        push @f, add_sound($w);
    }
    return @f;
}

# Formatting refresh
