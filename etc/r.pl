use strict;
use warnings;
use lib '../lib';
use Image::RIPscrip;

my $r = Image::RIPscrip->new;
$r->read( shift );
$r->render( shift );
