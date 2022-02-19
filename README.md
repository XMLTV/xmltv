<p align="center">
  <a href="https://github.com/XMLTV/xmltv">
    <img src="https://raw.github.com/XMLTV/xmltv/master/xmltv_logo.png?raw=true" style="margin: 0 auto;">
  </a>
</p>

# XMLTV 1.1.1

## Table of Contents

- [XMLTV](#xmltv)
  * [Description](#description)
  * [Changes](#changes)
  * [Installation (Package)](#installation-package)
    + [Linux](#linux)
    + [Windows](#windows)
    + [MacOS](#macos)
  * [Installation (Source)](#installation-source)
    + [Getting Source Code](#getting-source-code)
    + [Building](#building)
    + [Required distributions/modules](#required-distributionsmodules)
    + [Recommended distributions/modules](#recommended-distributionsmodules)
    + [JSON libraries](#json-libraries)
    + [CPAN](#cpan)
    + [Proxy servers](#proxy-servers)
  * [Known issues](#known-issues)
  * [License](#license)
  * [Authors](#authors)
  * [Resources](#resources)

## Description

The XMLTV project provides a suite of software to gather television listings, process listings data, and help organize your TV viewing.

XMLTV listings use a mature XML file format for storing TV listings, which is defined and documented in the [XMLTV DTD](xmltv.dtd).

In addition to the many "grabbers" that provide listings for large parts of the world, there are also several tools to process and filter these listings.

Please see our [QuickStart](doc/QuickStart) documentation for details on what each program does.

## Changes

To see what has changed in the current XMLTV release please check the [Changes](Changes) file.

## Installation (Package)

### Linux

XMLTV is packaged for most major Linux distributions and FreeBSD. It is recommended that users install XMLTV using their preferred package manager.

#### Debian/Ubuntu

```bash
% sudo apt install xmltv
```

#### Fedora/CentOS (via RPM Fusion)

```bash
% dnf install xmltv
```

### Windows

Windows users are strongly advised to use the [pre-built binary](http://alpha-exe.xmltv.org/) as installing all prerequisites is non-trivial. Please also check the Github release page for a pre-built release binary.

For those who want to give it a go, please read the [EXE build instructions](doc/exe_build.html). The instructions can be used for both building xmltv.exe as well as a local install.

### MacOS

XMLTV is packaged for MacOS in the [Fink Project](http://pdb.finkproject.org/pdb/package.php/xmltv)

## Installation (Source)

### Getting Source Code

#### Tarball/Zipfile

The source code for the current release can be downloaded as a tarball (or zipfile) from [GitHub](https://github.com/XMLTV/xmltv/releases/latest) and extracted to a preferred location.

#### Git

The source code for all previous, current and future releases is available in our GitHub repository:

```bash
% git clone https://github.com/XMLTV/xmltv.git
```

### Building

To build from source please ensure all required modules are available (see below). Change to the directory containing the XMLTV source:

```bash
% perl Makefile.PL
% make
% make test
% make install
```

To install to a custom directory, update the first line to provide a suitable `PREFIX` location:

```
% perl Makefile.PL PREFIX=/opt/xmltv/
```

The system requirements are Perl 5.8.3 or later, and a few Perl modules. You will be asked about some optional components; if you choose not to install them then there are fewer dependencies.

Please note that in addition to the specific modules listed below, the
`tv_grab_zz_sdjson_sqlite` grabber requires Perl 5.16 to be installed.

### Required distributions/modules

Required distributions/modules for XMLTV's core libraries are:

```perl
Date::Manip 5.42a
File::Slurp
JSON (see note below)
HTTP::Request
HTTP::Response
LWP 5.65
LWP::UserAgent
LWP::Protocol::https
Term::ReadKey
URI
XML::LibXML
XML::Parser 2.34
XML::TreePP
XML::Twig 3.28
XML::Writer 0.6.0
```

Required modules for grabbers/utilities are:

```
Archive::Zip                  (tv_grab_eu_epgdata, tv_grab_uk_bleb)
CGI                           (tv_pick_cgi, core module until 5.20.3, part of CGI)
CGI::Carp                     (tv_pick_cgi, core module until 5.20.3, part of CGI)
Compress::Zlib                (for some of the grabbers, core module since 5.9.3, part of IO::Compress)
Data::Dump                    (for tv_grab_it_dvb)
Date::Format                  (for some of the grabbers, part of TimeDate)
Date::Language                (tv_grab_ar, part of TimeDate)
DateTime                      (for several of the grabbers)
DateTime::Format::ISO8601     (tv_grab_zz_sdjson_sqlite)
DateTime::Format::SQLite      (tv_grab_zz_sdjson_sqlite)
DateTime::Format::Strptime    (tv_grab_eu_epgdata)
DateTime::TimeZone            (tv_grab_fr)
DBD::SQLite                   (tv_grab_zz_sdjson_sqlite)
DBI                           (tv_grab_zz_sdjson_sqlite)
Digest::SHA                   (tv_grab_zz_sdjson{,_sqlite}, core module since 5.9.3)
File::HomeDir                 (tv_grab_zz_sdjson_sqlite)
File::Which                   (tv_grab_zz_sdjson_sqlite)
HTML::Entities 1.27           (for several of the grabbers, part of HTML::Parser 3.34)
HTML::Parser 3.34             (tv_grab_it, tv_grab_it_dvb, part of HTML::Parser 3.34)
HTML::Tree                    (for many of the grabbers, part of HTML::Tree)
HTML::TreeBuilder             (for many of the grabbers, part of HTML::Tree)
HTTP::Cache::Transparent 1.0  (for several of the grabbers)
HTTP::Cookies                 (for several of the grabbers)
HTTP::Request::Common         (tv_grab_eu_epgdata, part of HTTP::Message)
IO::Scalar                    (for some of the grabbers, part of IO::Stringy)
List::MoreUtils               (tv_grab_zz_sdjson_sqlite)
LWP::Protocol::https          (tv_grab_fi, tv_grab_huro, tv_grab_zz_sdjson)
LWP::UserAgent::Determined    (tv_grab_zz_sdjson_sqlite)
SOAP::Lite 0.67               (tv_grab_na_dd)
Time::Piece                   (tv_grab_huro, core module since 5.9.5)
Time::Seconds                 (tv_grab_huro, core module since 5.9.5)
Tk                            (tv_check)
Tk::TableMatrix               (tv_check)
URI                           (for some of the grabbers, part of URI)
URI::Encode                   (tv_grab_pt_vodafone)
URI::Escape                   (for some of the grabbers, part of URI)
XML::DOM                      (tv_grab_is)
XML::LibXSLT                  (tv_grab_is)
```

When building XMLTV, any missing modules that are required for the selected grabbers/utilities will be reported.

### Recommended distributions/modules

The following modules are recommended but XMLTV works without them installed:

```
File::chdir                      (testing grabbers)
JSON::XS                         (faster JSON handling, see note below)
Lingua::Preferred 0.2.4          (helps with multilingual listings)
Log::TraceMessages               (useful for debugging, not needed for normal use)
PerlIO::gzip                     (can make tv_imdb a bit faster)
Term::ProgressBar                (displays pretty progress bars)
Unicode::String                  (improved character handling in tv_to_latex)
URI::Escape::XS                  (faster URI handling)
```

### JSON libraries

By default, libraries and grabbers that need to handle JSON data should specify the JSON module. This module is a wrapper for JSON::XS-compatible modules and supports the following JSON modules:

```
JSON::XS
JSON::PP
Cpanel::JSON::XS
```

JSON will use JSON::XS if available, falling back to JSON::PP (a core module since 5.14.0) if JSON::XS is not available. Cpanel::JSON::XS can be used as an explicit alternative by setting the PERL_JSON_BACKEND environment variable
(please refer to the JSON module's documentation for details).

### CPAN

All required modules can be quickly installed from CPAN using the `cpanm` utility. For example:

```bash
% cpanm XML::Twig
```

Please note that you may find it easier to search for packaged versions of required modules, as sources which distribute a packaged version of XMLTV also provide packaged versions of required modules.

### Proxy servers

Proxy server support is provide by the LWP modules. You can define a proxy server via the HTTP_PROXY environment variable.

```bash
% HTTP_PROXY=http://somehost.somedomain:port
```

For more information, see this [article](http://search.cpan.org/~gaas/libwww-perl-5.803/lib/LWP/UserAgent.pm#$ua->env_proxy)

## Known issues

If a full HTTP URL to the XMLTV.dtd is provided in the DOCTYPE declaration of an XMLTV document, please be aware that it is possible for the link to instead redirect to a page for accepting cookies. Such cookie-acceptance pages are more common in Europe, and can result in applications being unable to parse the file.

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

### IRC

Finally, we run an IRC channel #xmltv on Libera Chat. Please join us!


-- Nick Morrott, knowledgejunkie@gmail.com, 2022-02-19
