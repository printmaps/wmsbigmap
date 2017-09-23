#!/usr/bin/perl

# -----------------------------------------
# Program : wmsbigmap.pl
# Version : 0.1.0 - 2015/10/25 initial version
#           0.2.0 - 2015/10/27 EPSG:4326 = gdaltransform not required
#
# Copyright (C) 2015 Klaus Tockloth
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# Contact (eMail): <freizeitkarte@googlemail.com>
#
# Test:
# perl wmsbigmap.pl -inifile=muenster-dgk5.ini -resultfile=dgk5.xml -action=GetCapabilities
# perl wmsbigmap.pl -inifile=muenster-dgk5.ini -resultfile=muenster-dgk5.png
# -----------------------------------------

use warnings;
use strict;
use English qw( -no_match_vars );
use 5.010;

use Math::Trig;
use File::Basename;
use Getopt::Long;
use Config::IniFiles;
use LWP::UserAgent;
use GD;

# constants
my $EMPTY     = q{};
my $VERSION   = '0.2.0';
my $TIMESTAMP = '2015/10/27';

# globals
my $wms_response         = $EMPTY;
my $command              = $EMPTY;
my $bbox                 = $EMPTY;
my $gdaltransform_input  = 'gdaltransform.input';
my $gdaltransform_output = 'gdaltransform.output';
my $xtile_increment      = 0.0;
my $ytile_increment      = 0.0;

my $program_name = basename ( $PROGRAM_NAME );
my $program_info = sprintf ( "%s, %s-%s, Big map from WMS (web map service)", $program_name, $VERSION, $TIMESTAMP );

# command line parameters
my $help       = $EMPTY;
my $inifile    = $EMPTY;
my $action     = $EMPTY;
my $resultfile = $EMPTY;

GetOptions ( 'h|?'          => \$help,
             'inifile=s'    => \$inifile,
             'action=s'     => \$action,
             'resultfile=s' => \$resultfile, );

if ( $action eq $EMPTY ) {
    $action = 'GetMap';
}

my $printhelp = 0;
if ( ( $help ) || ( $inifile eq $EMPTY ) || ( $resultfile eq $EMPTY ) ) {
    $printhelp = 1;
}
if ( $printhelp ) {
    printf {*STDERR} ( "\n%s\n\n", $program_info );
    printf {*STDERR} ( "Usage:\n" );
    printf {*STDERR} ( "perl $program_name -inifile=name -resultfile=name <-action=string> \n\n" );
    printf {*STDERR} ( "Examples:\n" );
    printf {*STDERR} ( "perl $program_name -inifile=muenster-dtk10.ini -resultfile=dtk10.xml -action=GetCapabilities \n" );
    printf {*STDERR} ( "perl $program_name -inifile=muenster-dtk10.ini -resultfile=muenster-dtk10.png\n\n" );
    printf {*STDERR} ( "Parameters:\n" );
    printf {*STDERR} ( "-inifile    = wms and map settings file\n" );
    printf {*STDERR} ( "-resultfile = resulting xml or image file\n\n" );
    printf {*STDERR} ( "Options:\n" );
    printf {*STDERR} ( "-action     = GetCapabilities, GetMap (default)\n\n" );
    printf {*STDERR} ( "Requirements:\n" );
    printf {*STDERR} ( "The GDAL utility gdaltransform must be locally installed.\n" );
    printf {*STDERR} ( "Only necessary if the spatial ref system isn't EPSG:4326.\n\n" );
    exit ( 1 );
}

# read configuration settings
my $config_error = 0;
my %config       = ();
tie %config, 'Config::IniFiles', ( -file => $inifile );
foreach my $errormessage ( @Config::IniFiles::errors ) {
    printf {*STDERR} ( "INI-Error = $errormessage\n" );
    $config_error = 1;
}
if ( $config_error ) {
    exit ( 2 );
}
my $proxy   = $config{network}{proxy};
my $timeout = $config{network}{timeout};

# create internet user agent
my $ua = LWP::UserAgent->new;
my $agent = sprintf ( "%s/%s", $program_name, $VERSION );
$ua->agent ( $agent );
if ( $proxy ne $EMPTY ) {
    $ua->proxy ( 'http', $proxy );
}
if ( $timeout ne $EMPTY ) {
    $ua->timeout ( $timeout );
}

printf {*STDOUT} ( "\n%s\n\n",          $program_info );
printf {*STDOUT} ( "inifile    = %s\n", $inifile );
printf {*STDOUT} ( "resultfile = %s\n", $resultfile );
printf {*STDOUT} ( "action     = %s\n", $action );

if ( lc ( $action ) eq 'getcapabilities' ) {
    wms_getcapabilities ();
}
if ( lc ( $action ) eq 'getmap' ) {
    calculate_increments ();
    wms_getmap           ();
}

printf {*STDOUT} ( "\n" );

exit ( 0 );


# -----------------------------------------
# Request WMS capabilities.
# -----------------------------------------
sub wms_getcapabilities {

    printf {*STDOUT} ( "\nRequesting GetCapabilities ...\n" );

    my $wms_request_uri = $config{wms}{url};
    $wms_request_uri = $wms_request_uri . '?REQUEST=GetCapabilities';
    $wms_request_uri = $wms_request_uri . '&SERVICE=WMS';
    $wms_request_uri = $wms_request_uri . '&VERSION=' . $config{wms}{version};
    printf {*STDOUT} ( "Request URI = %s\n", $wms_request_uri );

    my $wms_response = $ua->get ( $wms_request_uri );
    if ( !$wms_response->is_success ) {
        printf {*STDERR} ( "ERROR  : The WMS service request GetCapabilities failed.\n" );
        printf {*STDERR} ( "STATUS : %s\n", $wms_response->status_line );
        exit ( 3 );
    }

    my $wms_content = $wms_response->decoded_content;
    open ( my $OUTFILE, '>', $resultfile ) or die ( "Error opening output file \"$resultfile\": $OS_ERROR\n" );
    printf {$OUTFILE} ( "%s", $wms_content );
    close ( $OUTFILE ) or die ( "Error closing output file \"$resultfile\": $OS_ERROR\n" );

    printf {*STDOUT} ( "\nWMS capabilities written to file <%s>\n", $resultfile );

    return ( 0 );
}


# -----------------------------------------
# Request WMS map tile.
# -----------------------------------------
sub wms_getmap {

    my $number_of_xtiles = $config{map}{xtiles};
    my $number_of_ytiles = $config{map}{ytiles};
    my $total_tiles      = $number_of_xtiles * $number_of_ytiles;

    my $tilesize = $config{getmap}{width_height};
    my $x_pixels = ( $number_of_xtiles * $tilesize );
    my $y_pixels = ( $number_of_ytiles * $tilesize );

    printf {*STDOUT} ( "\nlatitude   = %s (bottom left corner)\n", $config{map}{latitude} );
    printf {*STDOUT} ( "longitude  = %s (bottom left corner)\n",   $config{map}{longitude} );
    printf {*STDOUT} ( "horizontal = %s tiles (x)\n",              $config{map}{xtiles} );
    printf {*STDOUT} ( "vertical   = %s tiles (y)\n",              $config{map}{ytiles} );
    printf {*STDOUT} ( "total      = %d tiles\n",                  $total_tiles );
    printf {*STDOUT} ( "tile size  = %d * %d pixel\n",             $tilesize, $tilesize );
    printf {*STDOUT} ( "image size = %d * %d pixel\n",             $x_pixels, $y_pixels );
    my $real_size_width  = $number_of_xtiles * $config{map}{meters};
    my $real_size_height = $number_of_ytiles * $config{map}{meters};
    printf {*STDOUT} ( "real size  = %d * %d meter\n", $real_size_width, $real_size_height );
    my $print_size_width  = $x_pixels / 300.0 * 25.4;
    my $print_size_height = $y_pixels / 300.0 * 25.4;
    printf {*STDOUT} ( "print size = %d * %d mm (300 ppi)\n", $print_size_width, $print_size_height );
    printf {*STDOUT} ( "Est. time  = %d seconds\n", ( $number_of_xtiles * $number_of_ytiles * 3 ) );

    printf {*STDOUT} ( "\nRequesting map tiles ...\n" );

    my $img = GD::Image->new ( $x_pixels, $y_pixels, 1 );
    my $white = $img->colorAllocate ( 248, 248, 248 );
    $img->filledRectangle ( 0, 0, $x_pixels, $y_pixels, $white );

    my $index = 1;
    for ( my $x = 0 ; $x < $number_of_xtiles ; $x++ ) {
        for ( my $y = 0 ; $y < $number_of_ytiles ; $y++ ) {
            printf {*STDOUT} ( "\nRequesting tile %d / %d ...\n", $index, $total_tiles );
            calculate_bbox ( $x, $y );
            request_tile ( $x, $y );
            $index++;
            sleep ( 2 );
            my $tile = GD::Image->new ( $wms_response->decoded_content );
            $img->copy ( $tile, ( $x * $tilesize ), ( ( $number_of_ytiles - $y - 1 ) * $tilesize ), 0, 0, $tilesize, $tilesize );
        }
    }

    if ( $config{wms}{attribute} ) {
        my $black = $img->colorAllocate ( 0, 0, 0 );
        $img->string ( gdGiantFont, 10, 10, $config{wms}{attribute}, $black );
    }

    open ( my $OUTFILE, '>:raw', $resultfile ) or die ( "Error opening output file \"$resultfile\": $OS_ERROR\n" );
    printf {$OUTFILE} ( "%s", $img->png () );
    close ( $OUTFILE ) or die ( "Error closing output file \"$resultfile\": $OS_ERROR\n" );

    printf {*STDOUT} ( "\nWMS map written to file <%s>\n", $resultfile );

    return ( 0 );
}


# -----------------------------------------
# Request WMS map tile.
# -----------------------------------------
sub request_tile {

    my $xtile = shift;
    my $ytile = shift;

    my $wms_request_uri = $config{wms}{url};
    $wms_request_uri = $wms_request_uri . '?REQUEST=GetMap';
    $wms_request_uri = $wms_request_uri . '&SERVICE=WMS';
    $wms_request_uri = $wms_request_uri . '&VERSION=' . $config{wms}{version};
    $wms_request_uri = $wms_request_uri . '&LAYERS=' . $config{getmap}{layers};
    $wms_request_uri = $wms_request_uri . '&STYLES=' . $config{getmap}{styles};
    if ( $config{wms}{version} eq '1.1.1' ) {
        $wms_request_uri = $wms_request_uri . '&SRS=' . $config{getmap}{ref_sys};
    }
    else {
        $wms_request_uri = $wms_request_uri . '&CRS=' . $config{getmap}{ref_sys};
    }
    $wms_request_uri = $wms_request_uri . '&BBOX=' . $bbox;
    $wms_request_uri = $wms_request_uri . '&WIDTH=' . $config{getmap}{width_height};
    $wms_request_uri = $wms_request_uri . '&HEIGHT=' . $config{getmap}{width_height};
    $wms_request_uri = $wms_request_uri . '&FORMAT=' . $config{getmap}{format};
    if ( $config{getmap}{transparent} ) {
        $wms_request_uri = $wms_request_uri . '&TRANSPARENT=' . $config{getmap}{transparent};
    }
    if ( $config{getmap}{bgcolor} ) {
        $wms_request_uri = $wms_request_uri . '&BGCOLOR=' . $config{getmap}{bgcolor};
    }
    if ( $config{getmap}{exceptions} ) {
        $wms_request_uri = $wms_request_uri . '&EXCEPTIONS=' . $config{getmap}{exceptions};
    }
    if ( $config{getmap}{time} ) {
        $wms_request_uri = $wms_request_uri . '&TIME=' . $config{getmap}{time};
    }
    if ( $config{getmap}{elevation} ) {
        $wms_request_uri = $wms_request_uri . '&ELEVATION=' . $config{getmap}{elevation};
    }
    if ( $config{getmap}{sld} ) {
        $wms_request_uri = $wms_request_uri . '&SLD=' . $config{getmap}{sld};
    }
    if ( $config{getmap}{sld_body} ) {
        $wms_request_uri = $wms_request_uri . '&SLD_BODY=' . $config{getmap}{sld_body};
    }
    if ( $config{getmap}{other} ) {
        $wms_request_uri = $wms_request_uri . $config{getmap}{other};
    }
    printf {*STDOUT} ( "%s\n", $wms_request_uri );

    $wms_response = $ua->get ( $wms_request_uri );
    if ( !$wms_response->is_success ) {
        printf {*STDERR} ( "ERROR  : The WMS service request GetMap failed.\n" );
        printf {*STDERR} ( "STATUS : %s\n", $wms_response->status_line );
        exit ( 4 );
    }

    # for possible error messages only
    my $filename = 'error.txt';
    open ( my $OUTFILE, '>', $filename ) or die ( "Error opening output file \"$filename\": $OS_ERROR\n" );
    printf {$OUTFILE} ( "%s\n", $wms_response->decoded_content );
    close ( $OUTFILE ) or die ( "Error closing output file \"$filename\": $OS_ERROR\n" );

    return ( 0 );
}


# -----------------------------------------
# Calculate the xy increment values.
# Distance between two circles of latitude  : 111.3 km
# Distance between two circles of longitude : 111.3 km * cos (latitude)
# -----------------------------------------
sub calculate_increments {

    $xtile_increment = 0.0;
    $ytile_increment = 0.0;

    my $lower_left_latitude = $config{map}{latitude};
    my $tilesize_in_meters  = $config{map}{meters};

    my $radiant = deg2rad ( $lower_left_latitude );
    $xtile_increment = $tilesize_in_meters / ( ( 111.3 * 1000.0 ) * cos ( $radiant ) );
    $ytile_increment = $tilesize_in_meters / ( 111.3 * 1000.0 );

    return ( 0 );
}


# -----------------------------------------
# Calculate the bbox for one tile.
# 1.1.1: lon/lat ... lon/lat
# 1.3.0: lat/lon ... lat/lon
# -----------------------------------------
sub calculate_bbox {

    my $xtile = shift;
    my $ytile = shift;

    my $lower_left_latitude  = $config{map}{latitude};
    my $lower_left_longitude = $config{map}{longitude};

    if ( $xtile > 0 ) {
        $lower_left_longitude = $lower_left_longitude + ( $xtile * $xtile_increment );
    }
    if ( $ytile > 0 ) {
        $lower_left_latitude = $lower_left_latitude + ( $ytile * $ytile_increment );
    }

    my $upper_right_latitude  = $lower_left_latitude + $ytile_increment;
    my $upper_right_longitude = $lower_left_longitude + $xtile_increment;

    my $filename = $gdaltransform_input;
    open ( my $OUTFILE, '>', $filename ) or die ( "Error opening output file \"$filename\": $OS_ERROR\n" );
    printf {$OUTFILE} ( "%.10f %.10f\n", $lower_left_longitude,  $lower_left_latitude );
    printf {$OUTFILE} ( "%.10f %.10f\n", $upper_right_longitude, $upper_right_latitude );
    close ( $OUTFILE ) or die ( "Error closing output file \"$filename\": $OS_ERROR\n" );

    my $lower_left_longitude_transformed  = $lower_left_longitude;
    my $lower_left_latitude_transformed   = $lower_left_latitude;
    my $upper_right_longitude_transformed = $upper_right_longitude;
    my $upper_right_latitude_transformed  = $upper_right_latitude;

    my $target_ref_sys = uc ( $config{getmap}{ref_sys} );
    if ( $target_ref_sys ne 'EPSG:4326' ) {
        # convert coordinates (according to the spatial reference system)
        $command = 'gdaltransform -s_srs EPSG:4326 -t_srs ' . $target_ref_sys . ' <' . $gdaltransform_input . ' >' . $gdaltransform_output;
        process_command ( $command );

        # prepare BBOX string with transformed coordinate
        $filename = $gdaltransform_output;
        open ( my $INFILE, '<', $filename ) or die ( "Error opening output file \"$filename\": $OS_ERROR\n" );
        my $line1 = <$INFILE>;
        my $line2 = <$INFILE>;
        close ( $INFILE ) or die ( "Error closing output file \"$filename\": $OS_ERROR\n" );

        chomp ( $line1 );
        chomp ( $line2 );
        my $rest = $EMPTY;
        ( $lower_left_longitude_transformed,  $lower_left_latitude_transformed,  $rest ) = split ( / /, $line1 );
        ( $upper_right_longitude_transformed, $upper_right_latitude_transformed, $rest ) = split ( / /, $line2 );
    }

    if ( $config{wms}{version} eq '1.1.1' ) {
        $bbox = sprintf ( "%s,%s,%s,%s",
                          $lower_left_longitude_transformed,  $lower_left_latitude_transformed,
                          $upper_right_longitude_transformed, $upper_right_latitude_transformed );
    }
    else {
        $bbox = sprintf ( "%s,%s,%s,%s",
                          $lower_left_latitude_transformed,  $lower_left_longitude_transformed,
                          $upper_right_latitude_transformed, $upper_right_longitude_transformed );
    }

    return ( 0 );
}


# -----------------------------------------
# Execute system command.
# -----------------------------------------
sub process_command {

    my @args             = ( $command );
    my $systemReturncode = system ( @args );

    # The return value is the exit status of the program as returned by the wait call.
    # To get the actual exit value, shift right by eight (see below).
    if ( $systemReturncode != 0 ) {
        printf {*STDERR} ( "Warning: system($command) failed: $?\n" );
        if ( $systemReturncode == -1 ) {
            printf {*STDERR} ( "Failed to execute: $!\n" );
        }
        elsif ( $systemReturncode & 127 ) {
            printf {*STDERR} ( "Child died with signal %d, %s coredump\n", ( $systemReturncode & 127 ), ( $systemReturncode & 128 ) ? 'with' : 'without' );
        }
        else {
            printf {*STDERR} ( "Child exited with value %d\n", $systemReturncode >> 8 );
        }
        exit ( 5 );
    }

    return ( 0 );
}
