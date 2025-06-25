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
branch_name = "some_name"


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

def compute_delta(before_funcs, after_funcs,blames):
    deltas = []
    all_keys = set(before_funcs.keys()) | set(after_funcs.keys())

    branch_data = []


    for key in all_keys:
        before = before_funcs.get(key)
        after = after_funcs.get(key)

        # Get author from the method line
        # if the file does not exist, it was deleted
        line1 = after["line"] if after else -1


        blame_file = blames.get(after["filename"]) if after else None
        author = "unknown"

        # check if file was not removed
        if line1 != -1:
            for key1, value1 in blame_file.items():
                if key1 >= line1:
                    author = value1
                    break

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

        branch_data.append([branch_name, branch_sha, author, delta["delta"], line1])


    return deltas, branch_data


def load_all_blames(dir_path):
    """
    Load blame authors for all blame files in dir_path.
    Returns a dict mapping filename (without extension) to list of authors per line.
    """
    blame_data = {}
    for filename in os.listdir(dir_path):
        if filename.endswith(".blame"):  # adjust this extension to your actual blame file extension
            full_path = os.path.join(dir_path, filename)
            authors = load_blame_authors(full_path)
            # Store by filename without extension
            key = os.path.splitext(filename)[0]
            blame_data[key] = authors
    return blame_data


def load_blame_authors(blame_path):
    authors = {}
    current_author = None
    number = None

    sha_line_pattern = re.compile(r'^[0-9a-f]{40} \d+ \d+ \d+$\n')

    with open(blame_path, 'r', encoding='utf-8', errors='replace') as f:
        for line in f:
            if sha_line_pattern.match(line):
                number = line.split()[2]
            if line.startswith('author '):
                current_author = line[len('author '):].strip()
            elif line.startswith('\t'):
                # Source code line reached — assign author to this line
                authors[int(number)] = current_author
    return authors




def branch(before_path, after_path, blame_path, output_path, tip_path):

    #Load blames, before and after changes
    before = parse_lizard_xml(before_path)
    after = parse_lizard_xml(after_path)
    blames = load_all_blames(blame_path)

    # Extract deltas and branch data
    deltas, branch_data = compute_delta(before, after, blames)

    import json
    with open(output_path, 'w') as out:
        json.dump(deltas, out, indent=2)

    return branch_data

def main():

    # TODO: set location of desired branch file
    root = ''

    all_branches = []

    for dir in os.listdir(root):

        before_path = os.path.join(root, dir, "before.json")
        after_path = os.path.join(root, dir, "after.json")
        blame_path = os.path.join(root, dir, "tip_blame")
        output_path = os.path.join(root, dir, "complexity_results.json")
        metadata_path = os.path.join(root, dir, "metadata.txt")
        tip_path = os.path.join(root, dir, "tip_code")

        global branch_sha
        branch_sha = dir.split("_")[-1]

        global branch_name
        branch_name = "unknown"

        with open(metadata_path, 'r') as f:
            for line in f:
                if line.startswith("Branch Name"):

                    branch_name = line[len("Branch Name: "):].strip()

        branch_data = branch(before_path, after_path, blame_path, output_path, tip_path)
        all_branches.append(branch_data)


    print("i am done")

    # TODO: set csv name
    with open("", "w", newline='', encoding='utf-8', errors='replace') as csvfile:
        writer = csv.writer(csvfile)
        for branch_1 in all_branches:
            for change in branch_1:
                writer.writerow(change)


if __name__ == "__main__":
   main()
