#!/bin/bash

#ALTER BASE BRANCH AS NEEDED
BASE_BRANCH="dev"
OUTPUT_PARENT_DIR="branches"
mkdir -p "$OUTPUT_PARENT_DIR"

MERGE_COMMITS=$(git log $BASE_BRANCH --merges --pretty=format:"%H")

for MERGE_COMMIT_SHA in $MERGE_COMMITS; do


    echo "🔄 Processing merge commit: $MERGE_COMMIT_SHA"

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

    MERGE_BASE=$(git merge-base $BASE_COMMIT $BRANCH_TIP)

    CHANGED_FILES=$(
    {
        git diff --name-only "$MERGE_BASE" "$BRANCH_TIP" -- '*.svelte'
        git diff --name-only "$MERGE_BASE" "$BRANCH_TIP" -- '*.ts'
        git diff --name-only "$MERGE_BASE" "$BRANCH_TIP" -- '*.js'
        git diff --name-only "$MERGE_BASE" "$BRANCH_TIP" -- '*.html'
    } | sort -u
    )

    if [ -z "$CHANGED_FILES" ]; then
        echo "ℹ️ No TypeScript or Svelte files changed between base and branch tip."
        continue
    fi


    BRANCH_DIR="$OUTPUT_PARENT_DIR/branch_$MERGE_COMMIT_SHA"
    mkdir -p "$BRANCH_DIR"

    BASE_DIR="$BRANCH_DIR/base_code"
    TIP_DIR="$BRANCH_DIR/tip_code"
    BLAME_DIR="$BRANCH_DIR/tip_blame"

    mkdir -p "$BASE_DIR" "$TIP_DIR" "$BLAME_DIR"

    BASE_LIZARD_JSON="$BRANCH_DIR/before.json"
    TIP_LIZARD_JSON="$BRANCH_DIR/after.json"
    LIZARD_OUTPUT="$BRANCH_DIR/complexity_analysis.txt"

    for file in $CHANGED_FILES; do
        base_out="$BASE_DIR/${file//\//_}"
        tip_out="$TIP_DIR/${file//\//_}"

        if git ls-tree -r --name-only "$MERGE_BASE" | grep -q "^$file$"; then
            git show "$MERGE_BASE:$file" > "$base_out"
        fi

        if git ls-tree -r --name-only "$BRANCH_TIP" | grep -q "^$file$"; then
            git show "$BRANCH_TIP:$file" > "$tip_out"
        fi

        if [[ "$file" == *.svelte || "$file" == *.html ]]; then
            SCRIPT_OUT="$TIP_DIR/${file//\//_}.ts"
            MAPPING_FILE="$TIP_DIR/${file//\//_}.linemap"

            awk '
            BEGIN {in_script=0; lineno=0;}
            {
                lineno++;
                if ($0 ~ /<script[^>]*>/) { in_script=1; next; }
                if ($0 ~ /<\/script>/) { in_script=0; next; }
                if (in_script) {
                    print > "'"$SCRIPT_OUT"'";
                    print lineno > "'"$MAPPING_FILE"'";
                }
            }' "$tip_out"
        fi
    done

    for file in $CHANGED_FILES; do
        tip_out="$TIP_DIR/${file//\//_}"
        SCRIPT_OUT="$TIP_DIR/${file//\//_}.ts"
        MAPPING_FILE="$TIP_DIR/${file//\//_}.linemap"
        BLAME_OUT="$BLAME_DIR/${file//\//_}.blame"

        if [[ "$file" == *.svelte || "$file" == *.html ]]; then
            changed_lines=$(git diff -U0 $BASE_COMMIT $BRANCH_TIP -- "$file" | \
                grep '^@@' | \
                sed -E 's/^@@ -[0-9]+(,[0-9]+)? \+([0-9]+)(,([0-9]+))? @@.*/\2 \4/' | \
                awk '{start=$1; count=($2 == "" ? 1 : $2); for(i=start; i<start+count; i++) print i}')

            if [[ -f "$MAPPING_FILE" ]]; then
            mapfile -t line_map < "$MAPPING_FILE"
            fi
            > "$BLAME_OUT"

            for i in "${!line_map[@]}"; do
                orig_lineno="${line_map[$i]}"
                if echo "$changed_lines" | grep -q "^$orig_lineno$"; then
                    git blame -L "$orig_lineno","$orig_lineno" --line-porcelain $BRANCH_TIP -- "$file" >> "$BLAME_OUT"
                fi
            done
        elif [[ "$file" == *.ts || "$file" == *.js ]]; then

            changed_lines=$(git diff -U0 $BASE_COMMIT $BRANCH_TIP -- "$file" | \
                grep '^@@' | \
                sed -E 's/^@@ -[0-9]+(,[0-9]+)? \+([0-9]+)(,([0-9]+))? @@.*/\2 \4/' | \
                awk '{start=$1; count=($2 == "" ? 1 : $2); for(i=start; i<start+count; i++) print i}')

            > "$BLAME_OUT"

            for line in $changed_lines; do
                git blame -L $line,$line --line-porcelain $BRANCH_TIP -- "$file" >> "$BLAME_OUT"
            done
        fi
    done

    echo "🔹 BASE VERSION" >> $LIZARD_OUTPUT
    find "$BASE_DIR" -type f \( -name '*.ts' -o -name '*.js' -o -name '*.svelte.ts' \) -print0 | xargs -0 -r lizard -l javascript >> "$LIZARD_OUTPUT"
    find "$BASE_DIR" -type f \( -name '*.ts' -o -name '*.js' -o -name '*.svelte.ts' \) -print0 | xargs -0 -r lizard -l javascript -X json > "$BASE_LIZARD_JSON"

    echo "🔹 BRANCH TIP VERSION" >> $LIZARD_OUTPUT
    find "$TIP_DIR" -type f \( -name '*.ts' -o -name '*.js' -o -name '*.svelte.ts' \) -print0 | xargs -0 -r lizard -l javascript >> "$LIZARD_OUTPUT"
    find "$TIP_DIR" -type f \( -name '*.ts' -o -name '*.js' -o -name '*.svelte.ts' \) -print0 | xargs -0 -r lizard -l javascript -X json > "$TIP_LIZARD_JSON"

    BRANCH_NAME=$(git log -1 --pretty=%B $MERGE_COMMIT_SHA | grep -iE "Merge branch" | sed -E "s/.*Merge branch '([^']+)'.*/\1/" | sed 's/[^a-zA-Z0-9_-]/_/g')
    COMMIT_COUNT=$(git rev-list --count $BASE_COMMIT..$BRANCH_TIP)

    echo "Branch Name: $BRANCH_NAME" > "$BRANCH_DIR/metadata.txt"
    echo "Number of Commits: $COMMIT_COUNT" >> "$BRANCH_DIR/metadata.txt"

    echo "✅ Analysis complete. Output saved to $LIZARD_OUTPUT"
done
