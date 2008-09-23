use inc::Module::Install 0.77;

if ( -e 'MANIFEST.SKIP' ) {
    system( 'pod2text lib/Image/RIPscrip.pm > README' );
}

perl_version '5.008';

name 'Image-RIPscrip';
all_from 'lib/Image/RIPscip.pm';

requires 'Moose' => '0.51';
requires 'Graphics::Primitive::Driver::Cairo';
requires 'Graphics::Primitive';
requires 'Geometry::Primitive';
requires 'Graphics::Color';
requires 'Math::Base36';

test_requires 'Test::More';

WriteAll;
