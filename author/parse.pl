use strict;
use warnings;
use utf8;
use 5.18.1;

use constant VERBOSE => $ENV{VERBOSE} ? 1 : 0;

use JSON 2 -no_export;
use Regexp::Assemble::Compressed;
use Scalar::Util qw/looks_like_number/;

my @CATEGORIES = qw/
  africa
  antarctica
  asia
  australasia
  backward
  etcetera
  europe
  northamerica
  pacificnew
  southamerica
  systemv
/;

my %MONTH_NAME2DIGIT = (
    Jan       => 1,
    January   => 1,
    Feb       => 2,
    February  => 2,
    Mar       => 3,
    March     => 3,
    Apr       => 4,
    April     => 4,
    May       => 5,
    May       => 5,
    Jun       => 6,
    June      => 6,
    Jul       => 7,
    July      => 7,
    Aug       => 8,
    August    => 8,
    Sep       => 9,
    September => 9,
    Oct       => 10,
    October   => 10,
    Nov       => 11,
    November  => 11,
    Dec       => 12,
    December  => 12,
);

my %WEEK_NAME2DIGIT = (
    Mon       => 1,
    Monday    => 1,
    Tue       => 2,
    Tuesday   => 2,
    Wed       => 3,
    Wednesday => 3,
    Thu       => 4,
    Thursday  => 4,
    Fri       => 5,
    Friday    => 5,
    Sat       => 6,
    Saturday  => 6,
    Sun       => 7,
    Sunday    => 7,
);

my %TIMEZONE_MAP = (
    w => 'wall',
    s => 'local',
    u => 'utc',
    g => 'utc',
    z => 'utc',
);

my $MONTH_NAME_REGEXP = do {
    my $r = Regexp::Assemble::Compressed->new;
    $r->add($_) for keys %MONTH_NAME2DIGIT;
    $r->re;
};
my $WEEK_NAME_REGEXP = do {
    my $r = Regexp::Assemble::Compressed->new;
    $r->add($_) for keys %WEEK_NAME2DIGIT;
    $r->re;
};

my $ZONE_FORMAT_RX = qr!
    (-?[0-9]{1,2}(?::[0-9]{1,2}){0,2}[wsugz]?)\s+      # gmtoff
    (-|[0-9]{1,2}(?::[0-9]{1,2}){0,2}|[-_a-zA-Z]+)\s+  # rules
    ([-+/A-Za-z0-9]+|[-+/A-Za-z0-9]*%s[-+/A-Za-z0-9]*) # format
    (?:\s+                                             # until(splited)
        ([0-9]{4})                                     #   year
        (?:
            \s+($MONTH_NAME_REGEXP)\s+                 #   month
            (?:
                (
                    [0-9]{1,2}|
                    last${WEEK_NAME_REGEXP}|
                    ${WEEK_NAME_REGEXP}[><]=[0-9]+     #   day
                )
                (?:\s+
                    ([0-9]{1,2}(?::[0-9]{1,2}){0,2})   #   time
                    ([wsugz]?)                         #   timezone
                )?
            )?
        )?
    )?!ox;

my $RULE_FORMAT_RX = qr!
    ([-_a-zA-Z]+)\s+                                                   # name
    ([0-9]+|max(?:imum)?|min(?:imum)?)\s+                              # from
    ([0-9]+|max(?:imum)?|min(?:imum)?|only)\s+                         # to
    (-|even|odd|uspres|nonpres|nonuspres)\s+                           # type
    ($MONTH_NAME_REGEXP)\s+                                            # in
    ([0-9]+|last${WEEK_NAME_REGEXP}|${WEEK_NAME_REGEXP}[><]=[0-9]+)\s+ # on
    (-|[0-9]{1,2}(?::[0-9]{1,2}){0,2}[wsugz]?)\s+                      # at
    (-|[0-9]{1,2}(?::[0-9]{1,2}){0,2})\s+                              # save
    (-|[A-Za-z]+)                                                      # letter
!ox;

exit main(@ARGV) || 0;
sub main {
    my $data_dir = shift;

    my %olson;
    for my $category (@CATEGORIES) {
        warn "[VERBOSE] category: $category" if VERBOSE;
        $olson{$category} = parse_file("$data_dir/$category");
    }

    print JSON->new->canonical(1)->utf8(1)->pretty(1)->encode(\%olson);
}

our $CURRENT_ZONE_CONTEXT;
sub parse_file {
    my $file = shift;

    local $CURRENT_ZONE_CONTEXT;

    my %rules;
    my %zones;
    my %link;

    open my $fh, '<', $file or die $!;
    while (<$fh>) {
        if (/^#/) {
            # SKIP
        }
        else {
            s/\s*#.+$//o;
            if (/^Rule/) {
                if (defined $CURRENT_ZONE_CONTEXT) {
                    warn "[VERBOSE] release context: $CURRENT_ZONE_CONTEXT" if VERBOSE;
                    undef $CURRENT_ZONE_CONTEXT;
                }

                my $rule = parse_rule();
                push @{ $rules{$rule->{name}} } => $rule;
            }
            elsif (/^Link\s+(\S+)\s+(\S+)$/) {
                if (defined $CURRENT_ZONE_CONTEXT) {
                    warn "[VERBOSE] release context: $CURRENT_ZONE_CONTEXT" if VERBOSE;
                    undef $CURRENT_ZONE_CONTEXT;
                }
                $link{$1} = $2;
            }
            elsif (/^Zone\s+(\S+)/) {
                if (defined $CURRENT_ZONE_CONTEXT) {
                    warn "[VERBOSE] release context: $CURRENT_ZONE_CONTEXT" if VERBOSE;
                    undef $CURRENT_ZONE_CONTEXT;
                }
                $CURRENT_ZONE_CONTEXT = $1;
                warn "[VERBOSE] set     context: $CURRENT_ZONE_CONTEXT" if VERBOSE;

                my $zone = parse_zone();
                push @{ $zones{$CURRENT_ZONE_CONTEXT} } => $zone;
            }
            elsif ($CURRENT_ZONE_CONTEXT && /\S/) {
                my $zone = parse_zone();
                push @{ $zones{$CURRENT_ZONE_CONTEXT} } => $zone;
            }
            else {
                # skip!!
            }
        }
    }
    close $fh or die $!;

    return {
        rules => \%rules,
        zones => \%zones,
        link  => \%link,
    };
}

sub parse_rule {
    my %rule;
    if (@rule{qw/name from to type in on at save letter/} = /^Rule\s+${RULE_FORMAT_RX}\s*$/o) {
        return finalize_rule(\%rule);
    }
    else {
        die "invalid rule format: $_";
    }
}

sub parse_zone {
    my %zone;
    if (@zone{qw/name gmtoff rules format year month day time timezone/} = /^Zone\s+(\S+)\s+${ZONE_FORMAT_RX}\s*$/o) {
        die "invalid zone context. current: $CURRENT_ZONE_CONTEXT, name: $zone{name}" if $CURRENT_ZONE_CONTEXT ne $zone{name};
        return finalize_zone(\%zone);
    }
    elsif (@zone{qw/gmtoff rules format year month day time timezone/} = /^\s+${ZONE_FORMAT_RX}$/o) {
        return finalize_zone(\%zone);
    }
    else {
        die "invalid zone format: $_";
    }
}

sub finalize_rule {
    my $rule = shift;
    $rule->{at} = do {
        my $at = {
            hour     => 0,
            minute   => 0,
            second   => 0,
            timezone => normalize_timezone('w'),
        };
        if (my $at_str = delete $rule->{at}) {
            my ($timezone) = $at_str =~ m/([wsugz])$/;
            $timezone = normalize_timezone($timezone || 'w');

            $at_str =~ s/[wsugz]$//;
            my ($hour, $minute, $second) = split /:/, $at_str;
            $at->{hour}     = $hour   if defined $hour;
            $at->{minute}   = $minute if defined $minute;
            $at->{second}   = $second if defined $second;
            $at->{timezone} = $timezone;
        }

        normalize_number($at);
    };
    $rule->{save} = do {
        my $save = {
            hour     => 0,
            minute   => 0,
            second   => 0,
        };
        if (my $save_str = delete $rule->{save}) {
            my ($hour, $minute, $second) = split /:/, $save_str;
            $save->{hour}     = $hour   if defined $hour;
            $save->{minute}   = $minute if defined $minute;
            $save->{second}   = $second if defined $second;
        }

        normalize_number($save);
    };
    $rule->{in} = normalize_month($rule->{in}) if defined $rule->{in};
    return normalize_number($rule);
}

sub finalize_zone {
    my $zone = shift;
    delete $zone->{name} if exists $zone->{name};
    $zone->{month} = normalize_month($zone->{month}) if defined $zone->{month};
    $zone = normalize_until($zone);
    return normalize_number($zone);
}

sub normalize_month {
    my $month = shift;
    return $MONTH_NAME2DIGIT{$month} or die "invalid month: $month";
}

sub normalize_timezone {
    my $timezone = shift;
    return $TIMEZONE_MAP{$timezone} or die "invalid timezone: $timezone";
}

sub normalize_number {
    my $hash = shift;
    $hash->{$_} = 0+$hash->{$_} for grep { looks_like_number($hash->{$_}) } keys %$hash;
    return $hash;
}

sub normalize_until {
    my $zone = shift;
       $zone = +{ %$zone }; ## shallow clone

    my $until = +{
        year     => delete $zone->{year}  || undef,
        month    => delete $zone->{month} || undef,
        day      => delete $zone->{day}   || undef,
        hour     => 0,
        minute   => 0,
        second   => 0,
        timezone => normalize_timezone(delete $zone->{timezone} || 'w'),
    };

    if (my $time = delete $zone->{time}) {
        my ($hour, $minute, $second) = split /:/, $time;
        $until->{hour}   = $hour   if defined $hour;
        $until->{minute} = $minute if defined $minute;
        $until->{second} = $second if defined $second;
    }

    $zone->{until} = normalize_number($until);
    return $zone;
}
