#!/bin/bash

#ALTER BASE BRANCH AS NEEDED
BASE_BRANCH="dev"

OUTPUT_PARENT_DIR="branches"
mkdir -p "$OUTPUT_PARENT_DIR"

MERGE_COMMITS=$(git log $BASE_BRANCH --merges --pretty=format:"%H")

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



for MERGE_COMMIT_SHA in $MERGE_COMMITS; do
    echo "🔄 Processing merge commit: $MERGE_COMMIT_SHA"

    # Step 1: Get the parents of the merge commit
    PARENTS=($(git log -1 --pretty=%P $MERGE_COMMIT_SHA))
    BASE_COMMIT=${PARENTS[0]}
    BRANCH_TIP=${PARENTS[1]}

    # Determine direction of merge: was it into $BASE_BRANCH?
    if ! git merge-base --is-ancestor "$BASE_COMMIT" "$MERGE_COMMIT_SHA"; then
        echo "⏭️ Skipping $MERGE_COMMIT_SHA: not a merge INTO $BASE_BRANCH"
        continue
    fi


    if [ -z "$BRANCH_TIP" ]; then
        echo "❌ Error: Could not determine branch tip (second parent) from merge commit."
        continue
    fi

    echo "✅ Using commit $BRANCH_TIP as tip of the (possibly deleted) branch."

    # Step 2: Find merge base
    MERGE_BASE=$(git merge-base $BASE_COMMIT $BRANCH_TIP)
    
    EXT_FILTER=()
    for ext_list in "${LIZARD_LANG_EXT[@]}"; do
        for ext in $ext_list; do
            EXT_FILTER+=( "*.$ext" )
        done
    done

    #check only files that have extensions supported by lizard
    CHANGED_FILES=$(git diff --name-only "$MERGE_BASE" "$BRANCH_TIP" -- "${EXT_FILTER[@]}")
    
    if [ -z "$CHANGED_FILES" ]; then
        echo "ℹ️ No Rust files changed between base and branch tip."
        continue
    fi

    # Step 4: Setup temp dir
    BRANCH_DIR="$OUTPUT_PARENT_DIR/branch_$MERGE_COMMIT_SHA"
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

        # From merge base
        if git ls-tree -r --name-only "$MERGE_BASE" | grep -q "^$file$"; then
            git show "$MERGE_BASE:$file" > "$base_out"
        fi

        # Check if the file exists in the commit
        if git ls-tree -r --name-only "$BRANCH_TIP" | grep -q "^$file$"; then
            git show "$BRANCH_TIP:$file" > "$tip_out"
        fi
    done

    # Save blame output for each changed file at the TIP commit
    for file in $CHANGED_FILES; do
        # Get the changed line ranges for this file in the tip commit
        # Extract only the 'after' line numbers (lines added or modified)
        # git diff output header lines look like: @@ -start,count +start,count @@
        changed_lines=$(git diff -U0 $BASE_COMMIT $BRANCH_TIP -- "$file" | \
            grep '^@@' | \
            sed -E 's/^@@ -[0-9]+(,[0-9]+)? \+([0-9]+)(,([0-9]+))? @@.*/\2 \4/' | \
            awk '{start=$1; count=($2 == "" ? 1 : $2); for(i=start; i<start+count; i++) print i}')
        
        # Prepare a temp file for blame output of only changed lines
        output_file="$BLAME_DIR/${file//\//_}.blame"
        
        # We'll collect blame for each changed line using -L
        > "$output_file"  # clear output file
        
        for line in $changed_lines; do
            git blame -L $line,$line --line-porcelain $BRANCH_TIP -- "$file" >> "$output_file"
        done
    done


    # Step 6: Run Lizard
    echo "🔹 BASE VERSION" >> $LIZARD_OUTPUT
    lizard  "$BASE_DIR" >> $LIZARD_OUTPUT
    lizard  -X json "$BASE_DIR" > "$BASE_LIZARD_JSON"

    echo "🔹 BRANCH TIP VERSION" >> $LIZARD_OUTPUT
    lizard  "$TIP_DIR" >> $LIZARD_OUTPUT
    lizard -X json "$TIP_DIR" > "$TIP_LIZARD_JSON"


    #Store branch name(if it exists) and number of commits 
    BRANCH_NAME=$(git log -1 --pretty=%B $MERGE_COMMIT_SHA | grep -iE "Merge branch" | sed -E "s/.*Merge branch '([^']+)'.*/\1/" | sed 's/[^a-zA-Z0-9_-]/_/g')
    COMMIT_COUNT=$(git rev-list --count $BASE_COMMIT..$BRANCH_TIP)

    echo "Branch Name: $BRANCH_NAME" > "$BRANCH_DIR/metadata.txt"
    echo "Number of Commits: $COMMIT_COUNT" >> "$BRANCH_DIR/metadata.txt"

    # Step 7: Cleanup
    rm -rf $TEMP_DIR

    echo "✅ Analysis complete. Output saved to $LIZARD_OUTPUT"
done