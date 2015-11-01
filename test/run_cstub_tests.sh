#!/bin/bash
set -e

C_NONE='\e[m'
C_RED='\e[1;31m'
C_YELLOW='\e[1;33m'
C_GREEN='\e[1;32m'

TOOL_BIN=$(readlink -f ../build)"/dextool-debug"
if [[ $# -eq 1 ]]; then
    TOOL_BIN=$1
fi
TOOL_BIN="$TOOL_BIN ctestdouble"

source ./func_tests.sh

# Test strategy.
# Stage 1. Generation.
#  - Test stub generation of varying difficulty. The principal is a golden file that the result is compared to.
#  - Test compiling generated code with gcc. Generated binary and execute.
# Stage 2. Distributed.
#  - Test stub generation of many files, both including and excluding.
#  Stage 3. Functionality.
#  - Implement tests that uses the generated stubs.

setup_test_env

echo "Stage 1"
ROOT_DIR="testdata/cstub/stage_1"
for IN_SRC in $ROOT_DIR/*.{h,hpp}; do
    inhdr_base=$(basename ${IN_SRC})
    out_hdr="$OUTDIR/test_double.hpp"
    out_impl="$OUTDIR/test_double.cpp"
    out_glob="$OUTDIR/test_double_global.cpp"
    out_gmock="$OUTDIR/test_double_gmock.hpp"

    case "$IN_SRC" in
        *class_func*)
            test_gen_code "$OUTDIR" "$ROOT_DIR/$inhdr_base" "--debug" "" "-xc++ -DAND_A_DEFINE"
            ;;
        *param_main*)
            test_gen_code "$OUTDIR" "$ROOT_DIR/$inhdr_base" "--debug --main=Stub"
            out_hdr="$OUTDIR/stub.hpp"
            out_impl="$OUTDIR/stub.cpp"
            ;;
        *test_include_stdlib*)
            test_gen_code "$OUTDIR" "$ROOT_DIR/$inhdr_base" "--debug" "" "-nostdinc"
            ;;
        *param_gmock*)
            test_gen_code "$OUTDIR" "$ROOT_DIR/$inhdr_base" "--debug --gmock" "" "-nostdinc"
            ;;
        # Test examples
        # *somefile*)
        #     test_gen_code "$OUTDIR" "$IN_SRC" "--debug" "|& grep -i $grepper"
        # ;;
        *)
            test_gen_code "$OUTDIR" "$ROOT_DIR/$inhdr_base" "--debug" ;;
    esac

    test_compare_code "${IN_SRC%.h}.hpp.ref" "$out_hdr" "${IN_SRC%.h}.cpp.ref" "$out_impl" "${IN_SRC%.h}_global.cpp.ref" "$out_glob" "${IN_SRC%.h}_gmock.hpp.ref" "$out_gmock"

    case "$IN_SRC" in
        *param_gmock*)
            test_compile_code "$OUTDIR" "-Itestdata/cstub/stage_1" "$out_impl" main1.cpp "-DTEST_INCLUDE -DTEST_FUNC_PTR -Wpedantic -Werror"
            ;;
        *param_main*)
            test_compile_code "$OUTDIR" "-Itestdata/cstub/stage_1" "$out_impl" main1.cpp "-Wpedantic -Werror"
            ;;
        *variables*)
            test_compile_code "$OUTDIR" "-Itestdata/cstub/stage_1" "$out_impl" main1.cpp "-Wpedantic -Werror"
            ;;
        *const*)
            test_compile_code "$OUTDIR" "-Itestdata/cstub/stage_1" "$out_impl" main1.cpp "-DTEST_INCLUDE -DTEST_CONST -Wpedantic -Werror"
            ;;
        *function_pointers*)
            test_compile_code "$OUTDIR" "-Itestdata/cstub/stage_1" "$out_impl" main1.cpp "-DTEST_INCLUDE -DTEST_FUNC_PTR -Wpedantic -Werror"
            ;;
        *array*)
            test_compile_code "$OUTDIR" "-Itestdata/cstub/stage_1" "$out_impl" main1.cpp "-DTEST_INCLUDE -DTEST_ARRAY -Wpedantic -Werror"
            ;;
        *)
            test_compile_code "$OUTDIR" "-Itestdata/cstub/stage_1" "$out_impl" main1.cpp "-DTEST_INCLUDE -Wpedantic -Werror"
            ;;
    esac

    clean_test_env
done

echo "Stage 2"
INCLUDES="-Itestdata/cstub/stage_2 -Itestdata/cstub/stage_2/include"
ROOT_DIR="testdata/cstub/stage_2"
for IN_SRC in $ROOT_DIR/*.h; do
    inhdr_base=$(basename ${IN_SRC})
    out_hdr="$OUTDIR/test_double.hpp"
    out_impl="$OUTDIR/test_double.cpp"
    out_glob="$OUTDIR/test_double_global.cpp"

    case "$IN_SRC" in
        *param_gen_pre_post_include*)
            test_gen_code "$OUTDIR" "$ROOT_DIR/$inhdr_base" "--debug --gen-pre-incl --gen-post-incl" "" "$INCLUDES"
            ;;
        *no_overwrite*)
            continue
            ;;
        *param_exclude_one_file*)
            test_gen_code "$OUTDIR" "$ROOT_DIR/$inhdr_base" "--debug --file-exclude=.*/$inhdr_base" "" "$INCLUDES"
            ;;
        *param_exclude_many_files*)
            test_gen_code "$OUTDIR" "$ROOT_DIR/$inhdr_base" "--debug --file-exclude=.*/$inhdr_base --file-exclude='.*/include/b\.[h,c]'" "" "$INCLUDES"
            ;;
        *param_exclude_match_all*)
            # the regex must fully match
            test_gen_code "$OUTDIR" "$ROOT_DIR/$inhdr_base" "--debug --file-exclude=.*/param_exclude_match_all. --file-exclude='.*/include/b\.c'" "" "$INCLUDES"
            ;;
        *param_restrict*)
            test_gen_code "$OUTDIR" "$ROOT_DIR/$inhdr_base" "--debug --file-restrict=.*/$inhdr_base --file-restrict=.*/include/b.h" "" "$INCLUDES"
            ;;
        *param_include*)
            test_gen_code "$OUTDIR" "$ROOT_DIR/$inhdr_base" "--debug --td-include=b.h --td-include=stdio.h" "" "$INCLUDES"
            ;;
        *) ;;
    esac

    case "$IN_SRC" in
        *param_gen_pre_post_include*)
            test_compare_code "${IN_SRC%.h}.hpp.ref" "$out_hdr" "$ROOT_DIR/param_gen_pre_includes.hpp.ref" "$OUTDIR/test_double_pre_includes.hpp" "$ROOT_DIR/param_gen_post_includes.hpp.ref" "$OUTDIR/test_double_post_includes.hpp"
            ;;
        *)
            test_compare_code "${IN_SRC%.h}.hpp.ref" "$out_hdr" "${IN_SRC%.h}.cpp.ref" "$out_impl" "${IN_SRC%.h}_global.cpp.ref" "$out_glob"
            ;;
    esac

    test_compile_code "$OUTDIR" "$INCLUDES" "$out_impl" main1.cpp "-DTEST_INCLUDE"

    clean_test_env
done

echo "No overwrite of pre/post includes"
INCLUDES="-Itestdata/cstub/stage_2 -Itestdata/cstub/stage_2/include"
ROOT_DIR="testdata/cstub/stage_2"
inhdr_base="no_overwrite.h"

cp $ROOT_DIR/no_overwrite_pre_includes.hpp $OUTDIR/test_double_pre_includes.hpp
cp $ROOT_DIR/no_overwrite_post_includes.hpp $OUTDIR/test_double_post_includes.hpp
test_gen_code "$OUTDIR" "$ROOT_DIR/$inhdr_base" "--debug --gen-pre-incl --gen-post-incl" "" "$INCLUDES -DPRE_INCLUDES"
test_compare_code "$ROOT_DIR/no_overwrite_pre_includes.hpp" "$OUTDIR/test_double_pre_includes.hpp" "$ROOT_DIR/no_overwrite_post_includes.hpp" "$OUTDIR/test_double_post_includes.hpp"
test_compile_code "$OUTDIR" "$INCLUDES" "$out_impl" main1.cpp "-DTEST_INCLUDE"
clean_test_env

teardown_test_env
exit 0
