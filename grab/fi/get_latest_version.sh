#/bin/sh
set -e

# Fetch tarball from sourceforge CVS web viewer
echo "Fetching latest tv_grab_fi code..."
wget --quiet --clobber -O tv_grab_fi.tgz \
	'http://xmltv.cvs.sourceforge.net/viewvc/xmltv/xmltv/grab/fi/?view=tar'

# Unpack
echo "Unpacking tarball..."
rm -rf fi tv_grab_fi
tar xfz tv_grab_fi.tgz

# Generate tv_grab_fi
perl fi/merge.PL tv_grab_fi
rm -rf fi
ls -l tv_grab_fi*

echo "DONE."
