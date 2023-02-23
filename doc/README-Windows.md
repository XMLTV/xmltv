# XMLTV 1.2.1 Windows Release

## Table of Contents

- [XMLTV](#xmltv)
  * [Description](#description)
  * [64-bit and 32-bit Builds](#64-bit-and-32-bit-builds)
  * [Changes](#changes)
  * [Installation](#installation)
  * [General Notes](#general-notes)
  * [Known Issues](#known-issues)
  + [Proxy Servers](#proxy-servers)
  * [License](#license)
  * [Authors](#authors)
  * [Resources](#resources)

## Description

The XMLTV project provides a suite of software to gather television listings, process listings data, and help organize your TV viewing.

XMLTV listings use a mature XML file format for storing TV listings, which is defined and documented in the [XMLTV DTD](xmltv.dtd).

In addition to the many "grabbers" that provide listings for large parts of the world, there are also several tools to process and filter these listings.

Please see our [QuickStart](doc/QuickStart) documentation for details on what each program does.

This is a release of the software as a single Windows binary (xmltv.exe), generated from the Perl source code linked from <https://github.com/XMLTV/xmltv>.

## 64-bit and 32-bit Builds

Please keep an eye on our [releases page](https://github.com/XMLTV/xmltv/releases) for 64-bit and 32-bit builds of our current releases when available.

All current releases of XMLTV for Windows are built for 64-bit Windows by default. The latest 32-bit version of XMLTV is currently [XMLTV v0.6.1.](https://github.com/XMLTV/xmltv/releases/download/v0.6.1/xmltv-v0.6.1-win32.exe) *This version is not recommended.* 32-bit versions of new releases may appear on the release page.

To build and run a current version yourself you will need to run Cygwin, or Strawberry Perl. [Some instructions are available in the XMLTV Wiki](http://wiki.xmltv.org/index.php/XMLTVWindowsBuild)

## Changes

Major Changes in this release

| Grabber                  | Change    |
| ----------               | --------- |
| tv_grab_ar               | **disable grabber** |
| tv_grab_tr               | **disable grabber** |
| tv_grab_fi               | improvements to handle upstream changes |
| tv_grab_fi_sv            | update UserAgent to work with upstream changes |
| tv_grab_fr               | improvements to channel name handling and upstream changes |
| tv_grab_na_dd            | add some debug info |
| tv_grab_uk_tvguide       | minor bug fixes & improvements |
| tv_grab_zz_sdjson        | support Schedules Direct redirection response |
| tv_grab_zz_sdjson_sqlite | improve rating agency data validation and update documentation |

Please see the git log for full details of changes in this release.

## Installation

There is no installer - unpack the zipfile into a directory such as C:\xmltv.  If you are reading this you've probably already done that.

All the different programs are combined into a single executable.  For example, instead of running 'tv_grab_na --days 2 >na.xml' you would run

```bash
c:\xmltv\xmltv.exe tv_grab_na_dd --days 2 --output a.xml
```

Apart from the extra 'xmltv.exe' at the front of each command line, the usage should be the same as the Unix version.  Some programs make use of a "share" directory.  That directory is assumed be named "share" at the same location as the exe.  If you just keep everything where you unzipped it, everything should be fine.  If you must move xmltv.exe, you may need to specify a --share option with some programs.

xmltv.exe will try and guess a timezone.  This usually works fine. If it doesn't, you can set a TZ variable just like on Unix.

## General Notes

Spaces in filenames may cause problems with some programs.  Directories with spaces (i.e. C:\program files\xmltv) are not recommended. C:\xmltv is better.

Some of the programs allow you pass a date format on the command line. This uses % followed by a letter to specify a component of a date, for example %Y gives a four digit year.  This can cause problems on windows since % is used as a shell escape character.

To get around this, use %% to pass a % to the application. (ex. %%Y%%M )

If you *DO* want to insert a shell variable, you can do so by surrounding it with percents. (ex %HOME% )

## Known Issues

The first time xmltv.exe is run, it can take a while... up to 5 minutes as it prepares some files in %TEMP%.  This is normal.  Subsequent runs are fast.

Due to prerequisite problems, EXE support is not currently available for tv_grab_is and tv_grab_it_dvb, If you need one of those you'll need to install Perl and the necessary modules and use the full distribution.

## Proxy Servers

Proxy server support is provided by the LWP modules.

You can define a proxy server via the HTTP_PROXY environment variable:

```bash
http_proxy=http://somehost.somedomain:port
```

For more information, see the [LWP::UserAgent documentation](https://metacpan.org/pod/LWP::UserAgent#PROXY-ATTRIBUTES)

## License

XMLTV is free software, distributed under the GNU General Public License, version 2. Please see [COPYING](COPYING) for more details.

## Authors

There have been many contributors to XMLTV. Where possible they are credited in individual source files and in the [authors](authors.txt) mapping file.

## Resources

### GitHub

Our [GitHub project](https://github.com/XMLTV/xmltv) contains all source code, issues and Pull Requests.

### Project Wiki

We have a project [web page and wiki](http://www.xmltv.org)

### Mailing Lists

We run the following mailing lists:

- [xmltv-users](https://sourceforge.net/projects/xmltv/lists/xmltv-users): for users to ask questions and report problems with XMLTV software

- [xmltv-devel](https://sourceforge.net/projects/xmltv/lists/xmltv-devel): for development discussion and support

- [xmltv-announce](https://sourceforge.net/projects/xmltv/lists/xmltv-announce): announcements of new XMLTV releases

-- Nick Morrott, knowledgejunkie@gmail.com, 2023-02-23
