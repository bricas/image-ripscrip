use inc::Module::Install 1.05;

if ( -e 'MANIFEST.SKIP' ) {
    system( 'pod2text lib/Image/RIPscrip.pm > README' );
}

perl_version '5.008';

name 'Image-RIPscrip';
all_from 'lib/Image/RIPscip.pm';

requires 'Moose' => '0.51';
requires 'GD';
requires 'Math::Base36';

test_requires 'Test::More';

WriteAll;
