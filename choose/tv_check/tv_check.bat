REM $Id
REM
REM TV_CHECK.BAT
REM
REM This batch file will typically be used with the windows executable users 
REM as a simple way to run the script on a regular basis.
REM
REM It is meant as a template, tweak as necessary
REM
REM Note:  You must first run tv_grab_na.exe --configure to build a grabber config file
REM        If you're not using myrelaytv.com, you'll need to run tv_check.exe --configure too
REM
REM
REM Run without parameters, tv_grab_na is run.
REM Run with a parameter of C, --configure mode is run.
REM

REM
REM set default directory
REM
C:
cd \xmltv\test

REM
REM check for config file
REM
if exist tv_grab_na goto L27
echo ***ERROR***
echo tv_grab_na config file doesn't exist
echo please run "tv_grab_na.exe --configure"
goto end

:L27
REM
REM run tv_grab_na?
REM
if not "%1%"=="" goto L38

        tv_grab_na.exe --listings guide.xml
        if not errorlevel 0 goto end

:L38
REM
REM check for guide file
REM
if exist guide.xml goto L46
echo ***ERROR***
echo guide data doesn't exist
echo please run "tv_grab_na.exe --listings guide.xml"
goto end

:L46
REM
REM check for configure mode
REM
if not "%1%"=="C" goto L58
:L57
        tv_check.exe --configure
        if not errorlevel 0 goto end
  	goto L64      
:L58
if "%1%"=="c" goto L57
:L64
REM
REM run tv_check scan
REM
         tv_check.exe --scan --html --out=tv_check.html
REM      tv_check.exe --scan --html --out=tv_check.html --myreplay=1,user,pass
         if not errorlevel 0 goto end

start tv_check.html

:END
