#!/bin/bash

#ALTER BASE BRANCH AS NEEDED
BASE_BRANCH="dev"

OUTPUT_PARENT_DIR="commits"
mkdir -p "$OUTPUT_PARENT_DIR"

COMMITS=$(git rev-list --reverse "$BASE_BRANCH")
MAX_COMMITS=15  # ⬅️ Change this number to process more or fewer commits
count=0

declare -A LIZARD_LANG_EXT=(
    [c]="c h"
    [cpp]="cpp hpp cxx hxx cc hh"
    [cs]="cs"
    [java]="java"
    [javascript]="js"
    [python]="py"
    [rust]="rs"
    [go]="go"
    [swift]="swift"
    [typescript]="ts"
    [php]="php"
    [kotlin]="kt"
)

 EXT_FILTER=()
    for ext_list in "${LIZARD_LANG_EXT[@]}"; do
        for ext in $ext_list; do
            EXT_FILTER+=( "*.$ext" )
        done
    done


for COMMIT in $COMMITS; do
    
    ((count++))
    
    echo "🔄 [$count] Processing commit: $COMMIT"
   
    PARENT=$(git rev-list --parents -n 1 "$COMMIT" | awk '{print $2}')
    if [ -z "$PARENT" ]; then
        echo "⏭️ Skipping initial commit (no parent): $COMMIT"
        continue
    fi
        # Skip merge commits (those with more than one parent)
    PARENT_COUNT=$(git rev-list --parents -n 1 "$COMMIT" | wc -w)
    if (( PARENT_COUNT > 2 )); then
        echo "⏭️ Skipping merge commit: $COMMIT"
        continue
    fi


    #check only files that have extensions supported by lizard
    CHANGED_FILES=$(git diff --name-only "$PARENT" "$COMMIT" -- "${EXT_FILTER[@]}")
     
    if [ -z "$CHANGED_FILES" ]; then
        echo "ℹ️ No files changed between base and branch tip."
        continue
    fi

    # Step 4: Setup temp dir
    BRANCH_DIR="$OUTPUT_PARENT_DIR/commit_$COMMIT"
    mkdir -p "$BRANCH_DIR"

    BASE_DIR="$BRANCH_DIR/base_code"
    TIP_DIR="$BRANCH_DIR/tip_code"
    BLAME_DIR="$BRANCH_DIR/tip_blame"

    mkdir -p "$BASE_DIR" "$TIP_DIR" "$BLAME_DIR"

    BASE_LIZARD_JSON="$BRANCH_DIR/before.json"
    TIP_LIZARD_JSON="$BRANCH_DIR/after.json"
    LIZARD_OUTPUT="$BRANCH_DIR/complexity_analysis.txt"

    # Step 5: Extract only the changed code
    for file in $CHANGED_FILES; do
        base_out="$BASE_DIR/${file//\//_}"
        tip_out="$TIP_DIR/${file//\//_}"

        git show "$PARENT:$file" 2>/dev/null > "$base_out"
        git show "$COMMIT:$file" 2>/dev/null > "$tip_out"
    done

    # Save blame output for each changed file at the TIP commit
    for file in $CHANGED_FILES; do
        # Get the changed line ranges for this file in the tip commit
        # Extract only the 'after' line numbers (lines added or modified)
        # git diff output header lines look like: @@ -start,count +start,count @@
        changed_lines=$(git diff -U0 "$PARENT" "$COMMIT" -- "$file" | \
            grep '^@@' | \
            sed -E 's/^@@ -[0-9]+(,[0-9]+)? \+([0-9]+)(,([0-9]+))? @@.*/\2 \4/' | \
            awk '{start=$1; count=($2 == "" ? 1 : $2); for(i=start; i<start+count; i++) print i}')
        
        # Prepare a temp file for blame output of only changed lines
        output_file="$BLAME_DIR/${file//\//_}.blame"
        
        # We'll collect blame for each changed line using -L
        > "$output_file"  # clear output file
        
        for line in $changed_lines; do
            git blame -L $line,$line --line-porcelain $BRANCH_TIP -- "$file" 2>/dev/null >> "$output_file"
        done
    done


    # Step 6: Run Lizard
    echo "🔹 BASE VERSION" >> $LIZARD_OUTPUT
    lizard  "$BASE_DIR" >> $LIZARD_OUTPUT
    lizard  -X json "$BASE_DIR" > "$BASE_LIZARD_JSON"

    echo "🔹 COMMIT VERSION" >> $LIZARD_OUTPUT
    lizard  "$TIP_DIR" >> $LIZARD_OUTPUT
    lizard -X json "$TIP_DIR" > "$TIP_LIZARD_JSON"


    #Store branch name(if it exists) and number of commits 
    echo "Commit SHA: $COMMIT" > "$BRANCH_DIR/metadata.txt"
    echo "Parent SHA: $PARENT" >> "$BRANCH_DIR/metadata.txt"
    COMMIT_MSG=$(git log -1 --pretty=%s "$COMMIT")
    echo "Commit Message: $COMMIT_MSG" >> "$BRANCH_DIR/metadata.txt"

    AUTHOR_NAME=$(git log -1 --pretty="%an" "$COMMIT")
    AUTHOR_EMAIL=$(git log -1 --pretty="%ae" "$COMMIT")

    echo "Author Name: $AUTHOR_NAME" >> "$BRANCH_DIR/metadata.txt"
    echo "Author Email: $AUTHOR_EMAIL" >> "$BRANCH_DIR/metadata.txt"

    echo "✅ Analysis complete for commit $COMMIT. Output saved to $LIZARD_OUTPUT"
done