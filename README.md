## wmsbigmap.pl - load a large map from a Web Map Service (WMS)  

**Description**  
wmsbigmap.pl is a command line utility written in Perl.
It can be used on all operating systems where a Perl interpreter is available (eg. Linux, OSX, Windows).
It's purpose is to retrieve tiles from a web map serive (WMS) and montage a large map from them.
This program also works if you are behind an internet proxy server (see ini file).

**Precondition**  
Please make sure that you have read and understood the WMS usage policy and license.

**Requirements**  
This program requires a proper installation of the GDAL utility gdaltransform (only necessary if the spatial reference system isn't EPSG:4326).
You probably also have to install some non-standard perl modules (eg. the grafic module GD).

**Usage**  
```
wmsbigmap.pl, 0.2.0-2015/10/27, Big map from WMS (web map service)

Usage:
perl wmsbigmap.pl -inifile=name -resultfile=name <-action=string>

Examples:
perl wmsbigmap.pl -inifile=muenster-dtk10.ini -resultfile=dtk10.xml -action=GetCapabilities
perl wmsbigmap.pl -inifile=muenster-dtk10.ini -resultfile=muenster-dtk10.png

Parameters:
-inifile    = wms and map settings file
-resultfile = resulting xml or image file

Options:
-action     = GetCapabilities, GetMap (default)

Requirements:
The GDAL utility gdaltransform must be locally installed.
Only necessary if the spatial ref system isn't EPSG:4326.
```

**Ini file**  
Create an ini file for each WMS service you want to use.
The ini file describes all WMS and map settings.
See the sample ini file which contains a lot of comments.  

**Seven steps to fetch a map**  
In order to use a web map service you have to:  
1. figure out the base url of the service  
2. create a new ini file, fill in the url  
3. run the GetCapabilities action request  
4. study the GetCapabilities xml response  
5. amend the ini file with the capabilities  
6. test the configuration with a small map  
7. on success ... fetch your map  

**Usage policy**  
The usage of a lot of WMS services is "free".
Please read and respect the usage policies.
This utility tries to use the service in a moderate way.
It pauses for 2 seconds between requests.

**Attributation / copyright**  
A web map service typically demands the attributation of it's source (eg. copyright notice).
Please set this value in the ini file in order to fullfill this important requirement.

**History**  
Release 0.2.0 (2015/10/27):  
gdaltransform only necessary if the spatial reference system isn't EPSG:4326.  

Release 0.1.0 (2015/10/25):  
Initial version.  

