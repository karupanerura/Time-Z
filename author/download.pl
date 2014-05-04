use strict;
use warnings;
use utf8;

use File::Basename qw/dirname/;
use File::Spec::Functions qw/catfile abs2rel/;
use File::Path qw/remove_tree/;
use Archive::Extract;
use Time::OlsonTZ::Download;

my $version  = shift || Time::OlsonTZ::Download->latest_version;
my $data_dir = catfile dirname(__FILE__), sprintf 'olson-%s', $version;
remove_tree($data_dir) if -d $data_dir;


my $download    = Time::OlsonTZ::Download->new($version);
my $tzdata_file = catfile $download->dir, 'tzdata.tar.gz';
Archive::Extract->new(archive => $tzdata_file)->extract(to => $data_dir);
print $data_dir, "\n";
