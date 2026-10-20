#!/usr/bin/env python3
"""
Read an MRSN MinION/PromethION run sheet and write the
sample sheet CSV that Autopolish validates with nf-schema (assets/schema_input.json).

Only the run header and the sample table (Well, MRSN #, Description, Organism, Barcode,
Library Prep, Corresponding Illumina Run) are read.

    read_run_sheet.py <run_sheet.xlsx> <samplesheet.csv>
"""

import csv
import datetime
import re
import sys

import openpyxl

# Genera routed as fungi. Anything else is treated as bacteria.
FUNGAL_GENERA = {
    "aspergillus", "candida", "candidozyma", "clavispora", "cryptococcus", "debaryomyces",
    "fusarium", "kluyveromyces", "meyerozyma", "nakaseomyces", "pichia", "rhodotorula",
    "saccharomyces", "trichosporon", "wickerhamomyces",
}

# Run header labels (lower case, without ':') -> output column
HEADER_FIELDS = {
    "run name": "run_name",
    "run start date/time": "run_date",
    "barcoding kit": "kit",
    "flow cell type": "flow_cell_type",
    "flow cell number": "flow_cell_id",
}

# Sample table columns (lower case) -> output column.
TABLE_COLUMNS = {
    "well": "well",
    "mrsn #": "mrsn",
    "description": "description",
    "organism": "organism_raw",
    "barcode": "barcode",
    "library prep": "library_prep",
    "corresponding illumina run": "illumina_run",
}
REQUIRED_COLUMNS = ["well", "mrsn #", "organism", "barcode"]

OUTPUT_COLUMNS = [
    "sample", "barcode", "type", "organism", "organism_group", "organism_raw", "run", "well",
    "kit", "flow_cell_type", "flow_cell_id", "run_date", "library_prep", "illumina_run",
    "description",
]


def die(msg):
    sys.exit(f"ERROR: {msg}")


def text(value):
    """Cell value as a trimmed string. Blank cells and Excel errors (#N/A) become ''."""
    if value is None:
        return ""
    if isinstance(value, float) and value.is_integer():
        value = int(value)
    if isinstance(value, (datetime.datetime, datetime.date)):
        return value.strftime("%Y-%m-%d")
    value = " ".join(str(value).split())
    return "" if value.startswith("#") and value.endswith(("N/A", "!", "?")) else value


def label(value):
    return text(value).rstrip(":").strip().lower()


def find_sample_table(workbook):
    """First sheet with a row holding both 'Well' and 'Barcode' (so a renamed tab still works)."""
    for ws in workbook.worksheets:
        rows = list(ws.iter_rows(values_only=True))
        for i, row in enumerate(rows):
            labels = [label(c) for c in row]
            if "well" in labels and "barcode" in labels:
                return ws.title, rows[:i], labels, rows[i + 1:]
    die("no sheet has a sample table with 'Well' and 'Barcode' columns")


def normalise_barcode(value):
    # NB01, BC01, barcode1, 1 -> barcode01
    m = re.fullmatch(r"(?i)(?:nb|bc|barcode)?0*(\d+)", value)
    if not m or not 1 <= int(m.group(1)) <= 96:
        return None
    return f"barcode{int(m.group(1)):02d}"


def normalise_kit(value):
    # SQK-NBD114.96 / sqk nbd114 96 -> SQK-NBD114-96
    return re.sub(r"[\s._]+", "-", value.strip()).upper()


def safe_name(value):
    return re.sub(r"[^A-Za-z0-9.-]+", "_", value).strip("_")


def parse_date(value):
    for fmt in ("%m/%d/%Y", "%m/%d/%y", "%Y-%m-%d", "%m/%d/%Y %H:%M", "%m/%d/%Y %I:%M %p"):
        try:
            return datetime.datetime.strptime(value, fmt).strftime("%Y-%m-%d")
        except ValueError:
            pass
    return value


def normalise_organism(raw, genera):
    """'K. pneumoniae' -> 'Klebsiella pneumoniae', using full genus names seen on the same sheet."""
    words = raw.replace("_", " ").split()
    if not words:
        return ""
    genus = words[0]
    if re.fullmatch(r"[A-Za-z]\.", genus):
        matches = sorted(g for g in genera if g[0].lower() == genus[0].lower())
        if len(matches) == 1:
            genus = matches[0]
    words = [genus.capitalize()] + [w.lower() for w in words[1:]]
    return " ".join(words)


def sample_type(mrsn, organism):
    joined = f"{mrsn} {organism}".lower()
    if "blank" in joined or "negative" in joined or "ntc" in joined.split():
        return "negative_control"
    if "control" in joined or "positive" in joined:
        return "positive_control"
    return "test_sample"


def main(xlsx, out_csv):
    workbook = openpyxl.load_workbook(xlsx, read_only=True, data_only=True)
    sheet, header_rows, columns, table = find_sample_table(workbook)

    missing = [c for c in REQUIRED_COLUMNS if c not in columns]
    if missing:
        die(f"sheet '{sheet}' is missing column(s): {', '.join(missing)}")
    index = {out: columns.index(col) for col, out in TABLE_COLUMNS.items() if col in columns}

    # Run header: 'Label:' in one cell, the value in the next filled cell of the row
    run = {}
    for row in header_rows:
        cells = [c for c in row if text(c)]
        if cells and label(cells[0]) in HEADER_FIELDS:
            run[HEADER_FIELDS[label(cells[0])]] = text(cells[1]) if len(cells) > 1 else ""
    if not run.get("run_name"):
        die(f"sheet '{sheet}' has no 'Run Name:' in its header")
    run["run"] = safe_name(run.pop("run_name"))
    run["kit"] = normalise_kit(run.get("kit", ""))
    run["run_date"] = parse_date(run.get("run_date", ""))

    rows = []
    for n, row in enumerate(table, start=len(header_rows) + 2):
        cell = {out: text(row[i]) if i < len(row) else "" for out, i in index.items()}
        if not cell["mrsn"] and not cell["barcode"]:
            continue  # empty well or trailing rows
        if not cell["mrsn"] or not cell["barcode"]:
            die(f"sheet '{sheet}' row {n}: needs both 'MRSN #' and 'Barcode' (well {cell.get('well') or '?'})")
        barcode = normalise_barcode(cell["barcode"])
        if not barcode:
            die(f"sheet '{sheet}' row {n}: can't read barcode '{cell['barcode']}'")
        mrsn = cell["mrsn"]
        if re.fullmatch(r"\d+", mrsn):
            sample = f"MRSN{mrsn}"
        elif re.fullmatch(r"(?i)mrsn\s*\d+", mrsn):
            sample = "MRSN" + re.sub(r"\D", "", mrsn)
        else:
            # Blanks and controls: keep the name, add the well so repeats stay unique
            sample = safe_name(f"{mrsn}_{cell.get('well', '')}")
        rows.append(dict(cell, sample=sample, barcode=barcode, row=n))

    if not rows:
        die(f"sheet '{sheet}' has no samples")

    for key in ("sample", "barcode"):
        seen = {}
        for r in rows:
            if r[key] in seen:
                die(f"{r[key]} is on rows {seen[r[key]]} and {r['row']}; each MRSN and barcode can appear once per run")
            seen[r[key]] = r["row"]

    genera = {r["organism_raw"].split()[0] for r in rows
              if r["organism_raw"] and not r["organism_raw"].split()[0].endswith(".")}
    with open(out_csv, "w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=OUTPUT_COLUMNS, extrasaction="ignore")
        writer.writeheader()
        for r in rows:
            r["organism"] = normalise_organism(r["organism_raw"], genera)
            genus = r["organism"].split()[0].lower() if r["organism"] else ""
            r["organism_group"] = "fungi" if genus in FUNGAL_GENERA else "bacteria"
            r["type"] = sample_type(r["mrsn"], r["organism_raw"])
            writer.writerow({**{c: "" for c in OUTPUT_COLUMNS}, **run, **r})

    groups = {}
    for r in rows:
        groups[r["organism_group"]] = groups.get(r["organism_group"], 0) + 1
    print(f"{xlsx}: sheet '{sheet}', run {run['run']}, {len(rows)} samples "
          f"({', '.join(f'{v} {k}' for k, v in sorted(groups.items()))})")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
