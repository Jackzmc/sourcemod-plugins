#!/bin/bash
if [ -z "$SPCOMP_PATH" ]; then
    SPCOMP_PATH="./sm_1_12_7177/spcomp"
fi
if [ -z "$SPCOMP_OUT_FOLDER"]; then
    SPCOMP_OUT_FOLDER="plugins"
fi
mkdir -p "$SPCOMP_OUT_FOLDER" || true
for file in scripting/*.sp; do 
    out_filename=$(basename "${file%.*}.smx")
    $SPCOMP_PATH -i scripting/include "$file" -o "$SPCOMP_OUT_FOLDER"/"$out_filename" 
done
