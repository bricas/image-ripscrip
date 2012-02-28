use strict;
use warnings;

use lib 'lib';

use Image::RIPscrip;
use Image::RIPscrip::Renderer::GD;

my $i = Image::RIPscrip->new;
$i->read( shift );

#use Data::Dump;
#dd( $i );
#exit;

my $r = Image::RIPscrip::Renderer::GD->new;
print $r->render( $i );
