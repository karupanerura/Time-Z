use strict;
use warnings;
use utf8;
use 5.18.1;

use constant VERBOSE => $ENV{VERBOSE} ? 1 : 0;

use JSON 2 -no_export;

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

my $MONTH_NAME_REGEXP = qr/
    (?:J(?:u(?:ly?|ne?)|an(?:uary)?)|A(?:ug(?:ust)?|pr(?:il)?)|Ma(?:r(?:ch)?|y)|Sep(?:tember)?|Dec(?:ember)?|Feb(?:ruary)?|Nov(?:ember)?|Oct(?:ober)?)
/xo;
my $WEEK_NAME_REGEXP = qr/
    (?:T(?:hu(?:rsday)?|ue(?:sday)?)|S(?:at(?:urday)?|un(?:day)?)|Wed(?:nesday)?|Fri(?:day)?|Mon(?:day)?)
/xo;

exit main(@ARGV) || 0;
sub main {
    my $data_dir = shift;

    my %olson;
    for my $category (@CATEGORIES) {
        warn "[VERBOSE] category: $category" if VERBOSE;
        $olson{$category} = parse_file("$data_dir/$category");
    }

    print JSON->new->ascii(1)->pretty(1)->encode(\%olson);
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
    state $rule_format_rx = qr!
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

    my %rule;
    if (@rule{qw/name from to type in on at save letter/} = /^Rule\s+${rule_format_rx}\s*$/o) {
        return \%rule
    }
    else {
        die "invalid rule format: $_";
    }
}

sub parse_zone {
    state $zone_format_rx = qr!
         (-?[0-9]{1,2}(?::[0-9]{1,2}){0,2}[wsugz]?)\s+      # gmtoff
         (-|[0-9]{1,2}(?::[0-9]{1,2}){0,2}|[-_a-zA-Z]+)\s+  # rules
         ([-+/A-Za-z0-9]+|[-+/A-Za-z0-9]*%s[-+/A-Za-z0-9]*) # format
         (?:\s+                                             # until(splited)
             ([0-9]{4})                                     #   year
             (?:
                 \s+($MONTH_NAME_REGEXP)\s+                 #   month
                 (?:
                                                            #   day
                     ([0-9]{1,2}|last${WEEK_NAME_REGEXP}|${WEEK_NAME_REGEXP}[><]=[0-9]+)
                                                            #   time
                     (?:\s+([0-9]{1,2}(?::[0-9]{1,2}){0,2}[wsugz]?))?
                 )?
             )?
         )?!x;

    my %zone;
    if (@zone{qw/name gmtoff rules format year month day time/} = /^Zone\s+(\S+)\s+${zone_format_rx}\s*$/o) {
        my $name = delete $zone{name};
        die "invalid zone context. current: $CURRENT_ZONE_CONTEXT, name: $name" if $CURRENT_ZONE_CONTEXT ne $name;
        return \%zone
    }
    elsif (@zone{qw/gmtoff rules format year month day time/} = /^\s+${zone_format_rx}$/o) {
        return \%zone
    }
    else {
        die "invalid zone format: $_";
    }
}
