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
check_perl_warnings() {
    local log=$1
    if [ -s "$log" ]; then
	perl <$log >"${log}_warnings" -ne 'print if / at \S+ line \d+\.$/'
	if [ -s "${log}_warnings" ]; then
	    ( \
		echo "Test with log '$log' caused Perl warnings:"; \
		echo; \
		cat "${log}_warnings"; \
		echo; \
	    ) 1>&2
	    test_failure=1
	fi
    fi
}
validate_xml() {
    local xml=$1
    ${xmltv_script}/tv_validate_file $xml
    if [ $? -ne 0 ]; then
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
	norandomize)
	    debug="$debug --no-randomize"
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
script_file="${script_file} ${debug} --test-mode"
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
perl -I ${xmltv_lib} ${script_file} --list-channels --cache  t_fi_cache  > t_fi_channels.xml --quiet 2>t_fi_channels.log
if [ $? -ne 0 ]; then
    check_perl_warnings t_fi_channels.log
    tail -1 t_fi_channels.log
    test_failure=1
fi
perl -I ${xmltv_lib} ${script_file} --config-file ${script_dir}/test.conf --offset 1 --days 2 --cache  t_fi_cache  > t_fi_1_2.xml --quiet 2>t_fi_1.log
check_perl_warnings t_fi_1.log
validate_xml t_fi_1_2.xml
${xmltv_script}/tv_cat t_fi_1_2.xml --output /dev/null 2>t_fi_6.log
check_log t_fi_6.log
${xmltv_script}/tv_sort --duplicate-error t_fi_1_2.xml --output t_fi_1_2.sorted.xml 2>t_fi_1_2.sort.log
check_log t_fi_1_2.sort.log
perl -I ${xmltv_lib} ${script_file} --config-file ${script_dir}/test.conf --offset 1 --days 1 --cache  t_fi_cache  --output t_fi_1_1.xml  2>t_fi_2.log
check_perl_warnings t_fi_2.log
perl -I ${xmltv_lib} ${script_file} --config-file ${script_dir}/test.conf --offset 2 --days 1 --cache  t_fi_cache  > t_fi_2_1.xml 2>t_fi_3.log
check_perl_warnings t_fi_3.log
perl -I ${xmltv_lib} ${script_file} --config-file ${script_dir}/test.conf --offset 1 --days 2 --cache  t_fi_cache  --quiet --output t_fi_4.xml 2>t_fi_4.log
check_perl_warnings t_fi_4.log
${xmltv_script}/tv_cat t_fi_1_1.xml t_fi_2_1.xml --output t_fi_1_2-2.xml 2>t_fi_5.log
check_log t_fi_5.log
${xmltv_script}/tv_sort --duplicate-error t_fi_1_2-2.xml --output t_fi_1_2-2.sorted.xml 2>t_fi_7.log
check_log t_fi_7.log
diff t_fi_1_2.sorted.xml t_fi_1_2-2.sorted.xml > t_fi__1_2.diff
check_log t_fi__1_2.diff

#
# Modified test run with 7 days and modified test.conf
#
perl -pe 's/^#channel\s+/channel /' <${script_dir}/test.conf >${test_dir}/test.conf
perl -I ${xmltv_lib} ${script_file} --config-file ${test_dir}/test.conf --offset 1 --days 7 --cache  t_fi_cache  >t_fi_full_7.xml --quiet 2>t_fi_full.log
check_perl_warnings t_fi_full.log
validate_xml t_fi_full_7.xml
rm -f t_fi_single.log
for d in $(seq 1 7); do
    perl -I ${xmltv_lib} ${script_file} --config-file ${test_dir}/test.conf --offset $d --days 1 --cache  t_fi_cache  >t_fi_single_$d.xml --quiet 2>>t_fi_single.log
done
check_perl_warnings t_fi_single.log
${xmltv_script}/tv_cat t_fi_full_7.xml --output /dev/null 2>t_fi_output.log
${xmltv_script}/tv_sort --duplicate-error t_fi_full_7.xml --output t_fi_full_7.sorted.xml 2>>t_fi_output.log
check_log t_fi_output.log
${xmltv_script}/tv_cat t_fi_single_*.xml --output t_fi_full_7-2.xml 2>t_fi_output-2.log
${xmltv_script}/tv_sort --duplicate-error t_fi_full_7-2.xml --output t_fi_full_7-2.sorted.xml 2>>t_fi_output-2.log
check_log t_fi_output-2.log
diff t_fi_full_7.sorted.xml t_fi_full_7-2.sorted.xml >t_fi__7.diff
check_log t_fi__7.diff

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
