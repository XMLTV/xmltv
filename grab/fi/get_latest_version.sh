#/bin/sh
set -e

# GitHub does not offer tarballs of directories :-(
files=(
    merge.PL
    tv_grab_fi.pl
    fi/common.pm
    fi/day.pm
    fi/programme.pm
    fi/programmeStartOnly.pm
    fi/source/foxtv.pm
    fi/source/iltapulu.pm
    fi/source/telkku.pm
    fi/source/yle.pm
)

# Fetch files from GitHub repository
echo "Fetching latest tv_grab_fi code..."
rm -rf fi
for _f in ${files[@]}; do
    echo "Fetching ${_f}..."
    mkdir -p $(dirname fi/${_f})
    wget --quiet --clobber -O fi/${_f} \
	 "https://raw.githubusercontent.com/XMLTV/xmltv/master/grab/fi/${_f}"
done

# Generate tv_grab_fi
rm -f tv_grab_fi
perl fi/merge.PL tv_grab_fi
rm -rf fi
ls -l tv_grab_fi*

echo "DONE."
