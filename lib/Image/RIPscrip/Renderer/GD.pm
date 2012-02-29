package Image::RIPscrip::Renderer::GD;

use Moose;

has 'state' => ( is => 'rw', isa => 'HashRef', lazy => 1, builder => '_build_state' );

use Math::Base36 ();
use GD ();
use GD::Polyline ();

my @fullpal = map {
    [
        ( ( $_ >> 2 ) & 1 ) * 0xaa + ( ( $_ >> 5 ) & 1 ) * 0x55,
        ( ( $_ >> 1 ) & 1 ) * 0xaa + ( ( $_ >> 4 ) & 1 ) * 0x55,
        ( ( $_ >> 0 ) & 1 ) * 0xaa + ( ( $_ >> 3 ) & 1 ) * 0x55,
    ]
} 0 .. 63;

my @defaultpal
    = map { $fullpal[ $_ ] } qw( 0 1 2 3 4 5 20 7 56 57 58 59 60 61 62 63 );

my @dashpat = ();
my @fillpat = ();

my %cmd_map = ( '=' => 'eq', '@' => 'at', '*' => 'star' );

sub _build_state {
    my $self = shift;

    my $canvas = GD::Image->new( 640, 350 );
    $canvas->colorAllocate( @$_ ) for @defaultpal;

    return {
        canvas => $canvas,
        draw_color => 0,
        fill_color => 0,
        thickness  => 1,
        location   => [ 0, 0 ],
    };
}

sub render {
    my( $self, $image, $options ) = @_;

    $self->state( $self->_build_state );

    for my $op ( @{ $image->commands } ) {
        my $method = '_command_' . ( $cmd_map{ $op->{ command } } || $op->{ command } );

        my $code = $self->can( $method );
#        next unless $code;

        if( !$code ) {
            warn $op->{ command };
            next;
        }

        $code->( $self, @{ $op->{ args } } );
    }

    my $output = $options->{ format } || 'png';

    return $self->state->{ canvas } if $output eq 'object';
    return $self->state->{ canvas }->$output;
}

sub _command_star { # reset
    my ( $self, @args ) = @_;
    my $state = $self->state;

    my $canvas = GD::Image->new( 640, 350 );
    $canvas->colorAllocate( @$_ ) for @defaultpal;

    # docs don't say to reset draw/fill colors, etc
    $state->{ canvas } = $canvas;
    $state->{ location } = [ 0, 0 ];
    delete $state->{ clip };
}

sub _command_m {    # move drawing position
    my ( $self, @args ) = @_;
    my $state = $self->state;
    $state->{ location } = [ @args ];
}

sub _command_T {    # text
    my ( $self, @args ) = @_;
    my $state = $self->state;
    # TODO: need to move location after text
    $state->{ canvas }->string( GD::Font->Small, @{ $state->{ location } }, @args, $state->{ draw_color } )
}

sub _command_at {   # text at location
    my ( $self, @args ) = @_;
    my $state = $self->state;
    # TODO: need to move location after text
    $state->{ canvas }->string( GD::Font->Small, @args, $state->{ draw_color } )
}

sub _command_Y {    # set font style
    my ( $self, @args ) = @_;
    my $state = $self->state;
}

sub _command_W {    # set drawing mode
    my ( $self, @args ) = @_;
    my $state = $self->state;
}

sub _command_a {    # set palette entry
    my ( $self, @args ) = @_;
    my $state = $self->state;
    $state->{ canvas }->colorDeallocate( $args[ 0 ] );
    $state->{ canvas }->colorAllocate( @{ $fullpal[ $args[ 1 ] ] } );
}

sub _command_Q {    # new palette
    my ( $self, @args ) = @_;
    my $state = $self->state;
    for ( 0 .. 15 ) {
        $state->{ canvas }->colorDeallocate( $_ );
        $state->{ canvas }->colorAllocate( @{ $fullpal[ $args[ $_ ] ] } );
    }
}

sub _command_S {    # set fill style & color
    my ( $self, @args ) = @_;
    $self->state->{ fill_color } = $args[ 1 ];
}

sub _command_c {    # set draw color
    my ( $self, @args ) = @_;
    $self->state->{ draw_color } = $args[ 0 ];
}

sub _command_eq {   # set line style
    my ( $self, @args ) = @_;
    my $state = $self->state;

    if ( $args[ 0 ] != 4 ) {
        # dash pattern preset
    }
    else {    # custom dash pattern
    }

    $state->{ canvas }->setThickness( $args[ 2 ] );
}

sub _command_s {    # custom fill pattern
    my ( $self, @args ) = @_;
    my $state = $self->state;
}

sub _command_X {    # put pixel
    my ( $self, @args ) = @_;
    my $state = $self->state;
    $state->{ canvas }->setPixel( @args, $state->{ draw_color } );
}

sub _command_L {    # line
    my ( $self, @args ) = @_;
    my $state = $self->state;
    $state->{ canvas }->line( @args, $state->{ draw_color } );
}

sub _command_R {    # rectangle
    my ( $self, @args ) = @_;
    my $state = $self->state;
    $state->{ canvas }->rectangle( @args, $state->{ draw_color } );
}

sub _command_B {    # filled rectangle
    my ( $self, @args ) = @_;
    my $state = $self->state;
    $state->{ canvas }->filledRectangle( @args, $state->{ fill_color } );
}

sub _command_C {    # circle
    my ( $self, @args ) = @_;
    my $state = $self->state;
    my $size = $args[ 2 ] * 2;
    $state->{ canvas }->ellipse( @args[ 0, 1 ], $size, $size, $state->{ draw_color } );
}

sub _command_o {    # filled ellipse
    my ( $self, @args ) = @_;
    my $state = $self->state;
    my $w = $args[ 2 ] * 2;
    my $h = $args[ 3 ] * 2;
    $state->{ canvas }->filledEllipse( @args[ 0, 1 ], $w, $h, $state->{ fill_color } );
    $state->{ canvas }->ellipse( @args[ 0, 1 ], $w, $h, $state->{ draw_color } );
}

sub _command_p {    # filled polygon
    my ( $self, @args ) = @_;
    my $arg_cnt = shift @args;

    my $poly = GD::Polygon->new;
    while( @args ) {
        $poly->addPt( shift @args, shift @args) ;
    }
 
    my $state = $self->state;
    $state->{ canvas }->filledPolygon( $poly, $state->{ fill_color } );
#    $state->{ canvas }->openPolygon( $poly, $state->{ draw_color } );
}

sub _command_P {    # polygon
    my ( $self, @args ) = @_;
    my $arg_cnt = shift @args;

    my $poly = GD::Polygon->new;
    while( @args ) {
        $poly->addPt( shift @args, shift @args );
    }
 
    my $state = $self->state;
    $state->{ canvas }->openPolygon( $poly, $state->{ draw_color } );
}

sub _command_l {    # polyline
    my ( $self, @args ) = @_;
    my $arg_cnt = shift @args;

    my $poly = GD::Polygon->new;
    while( @args ) {
        $poly->addPt( shift @args, shift @args );
    }
 
    my $state = $self->state;
    $state->{ canvas }->unclosedPolygon( $poly, $state->{ draw_color } );
}

sub _command_A {    # circular arc
    my ( $self, @args ) = @_;
    my $state = $self->state;
    my $size = $args[ 4 ] * 2;
    $state->{ canvas }->arc( @args[ 0, 1 ], $size, $size, @args[ 2, 3 ], $state->{ draw_color } );
}

sub _command_O {    # elliptical arc
    my ( $self, @args ) = @_;
    my $state = $self->state;
    my $width = $args[ 4 ] * 2;
    my $height = $args[ 5 ] * 2;
    $state->{ canvas }->arc( @args[ 0, 1 ], $width, $height, @args[ 2, 3 ], $state->{ draw_color } );
}

# i don't see how this is any different than "O", so we'll re-use it.
*_command_V = \&_command_O;    # elliptical arc

sub _command_Z {    # beizer curve
    my ( $self, @args ) = @_;

    my $poly  = GD::Polyline->new;
    $poly->addPt( @args[ 0, 1 ] );
    $poly->addPt( @args[ 2, 3 ] );
    $poly->addPt( @args[ 4, 5 ] );
    $poly->addPt( @args[ 6, 7 ] );

    my $spline = $poly->toSpline();

    my $state = $self->state;
    local $GD::Polygon::bezSegs = $args[ 8 ];
    $state->{ canvas }->polydraw( $spline, $state->{ draw_color } );
}

sub _command_F {    # flood fill
    my ( $self, @args ) = @_;
    my $state = $self->state;
    $state->{ canvas }->fillToBorder( @args, $state->{ fill_color } );
}

sub _command_I {    # pie slice
    my ( $self, @args ) = @_;
    my $size = $args[ 4 ] * 2;
    my $state = $self->state;
    $state->{ canvas }->filledArc( @args[ 0, 1 ], $size, $size, @args[ 2, 3 ], $state->{ fill_color } );
}

sub _command_i {    # oval pie slice
    my ( $self, @args ) = @_;
    my $w = $args[ 4 ] * 2;
    my $h = $args[ 5 ] * 2;
    my $state = $self->state;
    $state->{ canvas }->filledArc( @args[ 0, 1 ], $w, $h, @args[ 2, 3 ], $state->{ fill_color } );
}

sub _command_1C {   # copy to clipboard
    my ( $self, @args ) = @_;

    my $state = $self->state;
    my $w = $args[ 2 ] - $args[ 0 ];
    my $h = $args[ 3 ] - $args[ 1 ];

    return if $w < 0 or $h < 0;

    my $clip = GD::Image->new( $w, $h );
    $clip->copy( $state->{ canvas }, 0, 0, @args[ 0..1 ], $w, $h );

    $state->{ clip } = $clip;
}

sub _command_1P {   # paste from clipboard
    my ( $self, @args ) = @_;
    my $state = $self->state;
    my $clip  = $state->{ clip };
    $state->{ canvas }->copy( $clip, @args[ 0..1 ], 0, 0, $clip->getBounds );
}

sub _command_1K {   # forget mouse regions
    my ( $self, @args ) = @_;
    my $state = $self->state;
}

no Moose;

__PACKAGE__->meta->make_immutable;

1;
