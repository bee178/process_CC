#!/bin/bash

#ALTER BASE BRANCH AS NEEDED
BASE_BRANCH="dev"
OUTPUT_PARENT_DIR="commits"
mkdir -p "$OUTPUT_PARENT_DIR"

COMMITS=$(git rev-list --reverse "$BASE_BRANCH")
MAX_COMMITS=20  # ⬅️ Change this number to process more or fewer commits
count=0


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


    CHANGED_FILES=$(
    {
        git diff --name-only "$PARENT" "$COMMIT" -- '*.svelte'
        git diff --name-only "$PARENT" "$COMMIT" -- '*.ts'
        git diff --name-only "$PARENT" "$COMMIT" -- '*.js'
        git diff --name-only "$PARENT" "$COMMIT" -- '*.html'
    } | sort -u
    )

    if [ -z "$CHANGED_FILES" ]; then
        echo "ℹ️ No TypeScript or Svelte files changed between base and branch tip."
        continue
    fi

    BRANCH_DIR="$OUTPUT_PARENT_DIR/commit_$COMMIT"
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

        git show "$PARENT:$file" 2>/dev/null > "$base_out"
        git show "$COMMIT:$file" 2>/dev/null > "$tip_out"

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
            changed_lines=$(git diff -U0 $PARENT $COMMIT -- "$file" | \
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
                    git blame -L "$orig_lineno","$orig_lineno" --line-porcelain $COMMIT -- "$file" >> "$BLAME_OUT"
                fi
            done
        elif [[ "$file" == *.ts || "$file" == *.js ]]; then

            changed_lines=$(git diff -U0 $PARENT $COMMIT -- "$file" | \
                grep '^@@' | \
                sed -E 's/^@@ -[0-9]+(,[0-9]+)? \+([0-9]+)(,([0-9]+))? @@.*/\2 \4/' | \
                awk '{start=$1; count=($2 == "" ? 1 : $2); for(i=start; i<start+count; i++) print i}')

            > "$BLAME_OUT"

            for line in $changed_lines; do
                git blame -L $line,$line --line-porcelain $COMMIT -- "$file" >> "$BLAME_OUT"
            done
        fi
    done

    echo "🔹 BASE VERSION" >> $LIZARD_OUTPUT
    find "$BASE_DIR" -type f \( -name '*.ts' -o -name '*.js' -o -name '*.svelte.ts' \) -print0 | xargs -0 -r lizard -l javascript >> "$LIZARD_OUTPUT"
    find "$BASE_DIR" -type f \( -name '*.ts' -o -name '*.js' -o -name '*.svelte.ts' \) -print0 | xargs -0 -r lizard -l javascript -X json > "$BASE_LIZARD_JSON"

    echo "🔹 COMMIT VERSION" >> $LIZARD_OUTPUT
    find "$TIP_DIR" -type f \( -name '*.ts' -o -name '*.js' -o -name '*.svelte.ts' \) -print0 | xargs -0 -r lizard -l javascript >> "$LIZARD_OUTPUT"
    find "$TIP_DIR" -type f \( -name '*.ts' -o -name '*.js' -o -name '*.svelte.ts' \) -print0 | xargs -0 -r lizard -l javascript -X json > "$TIP_LIZARD_JSON"

    #author can be extracted by commit
  

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
