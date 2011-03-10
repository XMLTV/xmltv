#!/bin/sh
#
# Based on the tests exsecuted on <http://www.crustynet.org.uk/~xmltv-tester>
#
# Check log file for errors
check_log() {
    local log=$1
    if [ -s "$log" ]; then
	( \
	    echo "Test with log '$log' failed:"; \
	    echo; \
	    cat $log; \
	    echo; \
	) 1>&2
	test_failure=1
    fi
}

# Configuration
set -e
build_dir=$(pwd)
script_dir=${build_dir}/grab/fi
script_file=${script_dir}/tv_grab_fi.pl
test_dir=${build_dir}/test-fi
xmltv_lib=${build_dir}/blib/lib
xmltv_script=${build_dir}/blib/script
export PERL5LIB=${xmltv_lib}

# Command line options
for arg in $*; do
    case $arg in
	debug)
	    debug="$debug --debug"
	    ;;
	merge)
	    merge_script=1
            ;;
	reuse)
	    preserve_directory=1
	    ;;
	
	*)
	    echo 1>&2 "unknown option '$arg"
	    exit 1
	    ;;
    esac
done

# Setup
if [ -n "$merge_script" ]; then
    script_file=${script_dir}/tv_grab_fi
    ${script_dir}/merge.PL ${script_file}
fi
if [ -z "$preserve_directory" ]; then
    echo "Deleting results from last run."
    rm -rf ${test_dir}
fi
mkdir -p ${test_dir}
script_file="${script_file} ${debug}"
cd ${test_dir}
set -x +e

#
# Tests
#
# Original test run with 2 days and using test.conf from repository
#
perl -I ${xmltv_lib} ${script_file} --ahdmegkeja > /dev/null 2>&1
perl -I ${xmltv_lib} ${script_file} --version > /dev/null 2>&1
perl -I ${xmltv_lib} ${script_file} --description > /dev/null 2>&1
perl -I ${xmltv_lib} ${script_file} --config-file ${script_dir}/test.conf --offset 1 --days 2 --cache  t_fi_cache  > t_fi_1_2.xml --quiet 2>t_fi_1.log
${xmltv_script}/tv_cat t_fi_1_2.xml > /dev/null 2>t_fi_6.log
check_log t_fi_6.log
${xmltv_script}/tv_sort --duplicate-error t_fi_1_2.xml > t_fi_1_2.sorted.xml 2>t_fi_1_2.sort.log
check_log t_fi_1_2.sort.log
perl -I ${xmltv_lib} ${script_file} --config-file ${script_dir}/test.conf --offset 1 --days 1 --cache  t_fi_cache  --output t_fi_1_1.xml  2>t_fi_2.log
perl -I ${xmltv_lib} ${script_file} --config-file ${script_dir}/test.conf --offset 2 --days 1 --cache  t_fi_cache  > t_fi_2_1.xml 2>t_fi_3.log
perl -I ${xmltv_lib} ${script_file} --config-file ${script_dir}/test.conf --offset 1 --days 2 --cache  t_fi_cache  --quiet --output t_fi_4.xml 2>t_fi_4.log
${xmltv_script}/tv_cat t_fi_1_1.xml t_fi_2_1.xml > t_fi_1_2-2.xml 2>t_fi_5.log
check_log t_fi_5.log
${xmltv_script}/tv_sort --duplicate-error t_fi_1_2-2.xml > t_fi_1_2-2.sorted.xml 2>t_fi_7.log
check_log t_fi_7.log
diff t_fi_1_2.sorted.xml t_fi_1_2-2.sorted.xml > t_fi__1_2.diff
check_log t_fi__1_2.diff

#
# Modified test run with 9 days and modified test.conf
#
perl -pe 's/^#(channel\s+(?:4|5|6|7|8|9|10|11|12|.+\.yle|.+\.telvis|.+\.mtv3)\..+)/$1/' <${script_dir}/test.conf >${test_dir}/test.conf
perl -I ${xmltv_lib} ${script_file} --config-file ${test_dir}/test.conf --offset 1 --days 9 --cache  t_fi_cache  >t_fi_full_10.xml --quiet 2>t_fi_full.log
for d in $(seq 1 9); do
    perl -I ${xmltv_lib} ${script_file} --config-file ${test_dir}/test.conf --offset $d --days 1 --cache  t_fi_cache  >t_fi_single_$d.xml --quiet 2>>t_fi_single.log
done
${xmltv_script}/tv_cat t_fi_full_10.xml > /dev/null 2>t_fi_output.log
${xmltv_script}/tv_sort --duplicate-error t_fi_full_10.xml > t_fi_full_10.sorted.xml 2>>t_fi_output.log
check_log t_fi_output.log
${xmltv_script}/tv_cat t_fi_single_*.xml >t_fi_full_10-2.xml 2>t_fi_output-2.log
${xmltv_script}/tv_sort --duplicate-error t_fi_full_10-2.xml > t_fi_full_10-2.sorted.xml 2>>t_fi_output-2.log
check_log t_fi_output-2.log
diff t_fi_full_10.sorted.xml t_fi_full_10-2.sorted.xml >t_fi__10.diff
check_log t_fi__10.diff

#
# All tests done
#
set +x
if [ -n "$test_failure" ]; then
    echo "TEST FAILED!"
    exit 1
else
    echo "All tests OK."
    exit 0
fi
