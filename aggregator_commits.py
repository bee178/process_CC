import xml.etree.ElementTree as ET
import os
import pandas as pd
import sys
import re
import csv
import chardet
from collections import defaultdict


#variables
branch_sha = "some_sha"
commit_sha = "some_sha"
branch_name = "some_name"
author_name = "some_name"


def parse_lizard_xml(path):
    print(path)
    funcs = {}

    if os.path.getsize(path) == 0:
        return funcs

    tree = ET.parse(path)
    root = tree.getroot()
    # Find all function items
    for measure in root.findall("measure"):
        if measure.attrib.get("type") == "Function":
            for item in measure.findall("item"):
                # item name format: "function_name(...) at filename:line"
                name = item.attrib.get("name", "")
                # Values: Nr., NCSS, CCN (cyclomatic complexity)
                values = item.findall("value")
                if len(values) >= 3:
                    complexity = int(values[2].text)  # CCN is 3rd value
                    # Parse function name and file from item name
                    if " at " in name:
                        func_name, file_line = name.split(" at ")
                        filename_1 = file_line.rsplit(":", 1)[0]
                        line = int(file_line.rsplit(":", 1)[1])
                        filename = filename_1.rsplit("\\", 1)[1]
                    else:
                        func_name = name
                        filename = "unknown"

                    key = f"{filename}::{func_name}"
                    funcs[key] = {
                        "name": func_name,
                        "filename": filename,
                        "cyclomatic_complexity": complexity,
                        "line": line
                    }
    return funcs

def compute_delta(before_funcs, after_funcs):
    deltas = []
    all_keys = set(before_funcs.keys()) | set(after_funcs.keys())

    branch_data = []

    for key in all_keys:
        before = before_funcs.get(key)
        after = after_funcs.get(key)

        #Get author from the method line
        line1 = after["line"] if after else -1

        author = author_name

        #if the functions were added or removed, their complexity is set as zero accordingly
        #if the line is marked as -1, this will be inspected after, it means that the method does not exist in the after version.
        delta = {
            "function": key,
            "complexity_before": before["cyclomatic_complexity"] if before else 0,
            "complexity_after": after["cyclomatic_complexity"] if after else 0,
            "line": line1,
            "author": author
        }
        delta["delta"] = delta["complexity_after"] - delta["complexity_before"]
        deltas.append(delta)

        branch_data.append([commit_sha, author, delta["delta"], delta["function"], line1])


    return deltas, branch_data



def commit(before_path, after_path, blame_path, output_path, tip_path):

    # Load blames, before and after changes
    before = parse_lizard_xml(before_path)
    after = parse_lizard_xml(after_path)

    deltas, commit_data = compute_delta(before, after)

    import json
    with open(output_path, 'w') as out:
        json.dump(deltas, out, indent=2)

    return commit_data

def main():

    # TODO: set location of desired branch file
    root = ''

    all_commits = []

    for dir in os.listdir(root):

        before_path = os.path.join(root, dir, "before.json")
        after_path = os.path.join(root, dir, "after.json")
        blame_path = os.path.join(root, dir, "tip_blame")
        output_path = os.path.join(root, dir, "complexity_results.json")
        metadata_path = os.path.join(root, dir, "metadata.txt")
        tip_path = os.path.join(root, dir, "tip_code")


        #Extract author and commit_sha
        with open(metadata_path, 'r') as f:
            for line in f:
                if line.startswith("Commit SHA"):
                    global commit_sha
                    commit_sha = line[len("Commit SHA: "):].strip()
                if line.startswith("Author Name"):
                    global author_name
                    author_name = line[len("Author Name: "):].strip()

        commit_data = commit(before_path, after_path, blame_path, output_path, tip_path)
        all_commits.append(commit_data)


    print("i am done")

    # TODO: set csv name
    with open("", "w", newline='', encoding='utf-8', errors='replace') as csvfile:
        writer = csv.writer(csvfile)
        for branch_1 in all_commits:
            for change in branch_1:
                writer.writerow(change)


if __name__ == "__main__":
   main()
