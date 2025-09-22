#!/bin/bash
set -e
if [ -z "$SPCOMP_PATH" ]; then
    SPCOMP_PATH="./sm_1_12_7177/spcomp"
fi
if [ -z "$SPCOMP_OUT_FOLDER"]; then
    SPCOMP_OUT_FOLDER="plugins"
fi
if [[ "$SPCOMP_FAIL_ON_ERROR" == "1" ]]; then
    echo "Failing on any plugin compilation failure"
    set -e
else
    echo "Continuing on plugin compilation failure"
    set +e # actions sets -e 
fi
# set +e
mkdir -p "$SPCOMP_OUT_FOLDER" || true
for file in scripting/*.sp; do 
    out_filename=$(basename "${file%.*}.smx")
    echo ======= COMPILING $file =============
    $SPCOMP_PATH -v 0 -i scripting/include "$file" -o "$SPCOMP_OUT_FOLDER"/"$out_filename"
    
    echo
    echo
done

if [[ "$SPCOMP_FAIL_ON_ERROR" == "1" ]]; then
    echo Completed with no errors
fi