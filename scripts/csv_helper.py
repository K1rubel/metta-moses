"""
CSV -> MeTTa input-table loaders, with separate Boolean/numeric validation.

Called from MeTTa via:
    (py-call (csv_helper.load_boolean_table <path> <target_feature>))

Returns a STRING containing a valid MeTTa S-expression of the form
    (mkITable <columns-expression-list> <labels-expression-list>)
which the caller `parse`s back into a MeTTa term.

Every cell is type-checked against a small set of boolean literals; any
unparseable cell raises a ValueError with row and column context so
failures are loud and locatable.
"""

import csv
import json
import math
import re

BOOLEAN_LITERALS = {
    "true":  "True",
    "false": "False",
    "1":     "True",
    "0":     "False",
    "yes":   "True",
    "no":    "False",
    "t":     "True",
    "f":     "False",
}


def _to_bool_literal(cell, row_num, col_name):
    s = cell.strip().lower()
    if s in BOOLEAN_LITERALS:
        return BOOLEAN_LITERALS[s]
    raise ValueError(
        "row {row}, column {col!r}: cannot parse {cell!r} as boolean. "
        "Accepted (case-insensitive): True, False, 1, 0, yes, no, t, f."
        .format(row=row_num, col=col_name, cell=cell)
    )


def _expr_list(items):
    """Render items as the expression-list shape MeTTa code consumes."""
    items = list(items)
    if not items:
        return "()"
    return "({})".format(" ".join(items))


def load_boolean_table(path, target_feature=""):
    """Read `path` as CSV, validate every cell as boolean, move the target
    column to the end (MeTTa convention), and return an `(mkITable ...)`
    S-expression string.

    Args:
        path: filesystem path to the CSV (relative paths resolved against the
              current process working directory).
        target_feature: header name of the output column. Empty/None means
              "use the last column as-is".

    Raises:
        FileNotFoundError: if the path doesn't exist.
        ValueError: on empty file, mis-shaped row, unknown target column, or
                    any cell that isn't a recognized boolean literal.
    """
    with open(path) as f:
        rows = list(csv.reader(f))

    if not rows:
        raise ValueError("{!r}: empty CSV".format(path))

    labels = [h.strip() for h in rows[0]]
    body = rows[1:]
    if not body:
        raise ValueError("{!r}: header only, no data rows".format(path))

    if target_feature in ("", None):
        target_idx = len(labels) - 1
        target_name = labels[target_idx]
    else:
        if target_feature not in labels:
            raise ValueError(
                "target feature {tf!r} not found in columns {labels}".format(
                    tf=target_feature, labels=labels
                )
            )
        target_idx = labels.index(target_feature)
        target_name = target_feature

    new_labels = [l for i, l in enumerate(labels) if i != target_idx]
    new_labels.append(target_name)

    # Type-check every cell upfront and build a column-major table.
    num_columns = len(labels)
    validated_columns = [[] for _ in range(num_columns)]

    for r_num, row in enumerate(body, start=2):  # +1 for header, 1-indexed
        if len(row) != len(labels):
            raise ValueError(
                "row {r}: {got} columns, expected {want}".format(
                    r=r_num, got=len(row), want=len(labels)
                )
            )

        bools = [
            _to_bool_literal(row[i], r_num, labels[i])
            for i in range(num_columns)
        ]

        reordered = [b for i, b in enumerate(bools) if i != target_idx]
        reordered.append(bools[target_idx])

        for col_idx, value in enumerate(reordered):
            validated_columns[col_idx].append(value)


    columns_sexpr = _expr_list(_expr_list(col) for col in validated_columns)
    labels_sexpr = _expr_list(new_labels)
    return "(mkITable {rows} {labels})".format( rows=columns_sexpr, labels=labels_sexpr,)


_DECIMAL = re.compile(r"[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?\Z")


def read_continuous_table(path, target_feature=""):
    """Return (exact labels, binary64 columns), with the target moved last.

    Unlike the Boolean loader, headers are preserved verbatim and serialized
    as string labels, never executable MeTTa symbols. Empty/duplicate headers,
    blank or ragged rows, non-decimal cells and non-finite values are rejected.
    UTF-8 (including a leading BOM) and standard CSV quoting are supported.
    A target-only table is valid for intercept-only regression.
    """
    with open(path, encoding="utf-8-sig", newline="") as stream:
        reader = csv.reader(stream, strict=True)
        try:
            rows = list(reader)
        except csv.Error as error:
            raise csv.Error(f"row {reader.line_num}: malformed CSV: {error}") from error
    if not rows:
        raise ValueError(f"{path!r}: empty CSV")
    labels = rows[0]
    if not labels:
        raise ValueError("row 1: missing header columns")
    seen = set()
    for index, label in enumerate(labels, 1):
        if not label.strip():
            raise ValueError(f"row 1, column {index}: empty header")
        if any(ord(char) < 32 and char not in '\t\r\n' for char in label):
            raise ValueError(f"row 1, column {index}: unsupported control character in header")
        if label in seen:
            raise ValueError(f"row 1, column {index}: duplicate header {label!r}")
        seen.add(label)
    if len(rows) == 1:
        raise ValueError(f"{path!r}: header only, no data rows")
    if target_feature in ("", None):
        target_index = len(labels) - 1
    elif target_feature in labels:
        target_index = labels.index(target_feature)
    else:
        raise ValueError(f"target feature {target_feature!r} not found in columns {labels!r}")
    order = [i for i in range(len(labels)) if i != target_index] + [target_index]
    columns = [[] for _ in labels]
    for row_number, row in enumerate(rows[1:], 2):
        if len(row) != len(labels):
            raise ValueError(f"row {row_number}: {len(row)} columns, expected {len(labels)}")
        for output_index, input_index in enumerate(order):
            cell = row[input_index].strip()
            where = f"row {row_number}, column {input_index + 1} ({labels[input_index]!r})"
            if not _DECIMAL.fullmatch(cell):
                raise ValueError(f"{where}: {row[input_index]!r} is not a finite decimal number")
            value = float(cell)
            if not math.isfinite(value):
                raise ValueError(f"{where}: {row[input_index]!r} is not finite in binary64")
            columns[output_index].append(value)
    return [labels[i] for i in order], columns


def load_continuous_table(path, target_feature=""):
    """Render a validated numeric CSV as a column-major MeTTa mkITable.

    repr(float) round-trips binary64 values; JSON string quoting protects exact
    headers containing spaces, punctuation, quotes, numeric text or operators.
    Errors raise with CSV row/column context; Boolean parsing is unchanged.
    """
    labels, columns = read_continuous_table(path, target_feature)
    return "(mkITable {} {})".format(
        _expr_list(_expr_list(repr(value) for value in column) for column in columns),
        _expr_list(json.dumps(label, ensure_ascii=False) for label in labels),
    )


def load_continuous_table_result(path, target_feature=""):
    """MeTTa bridge: return one parseable table or tagged, printable failure."""
    try:
        return load_continuous_table(path, target_feature)
    except (OSError, ValueError, csv.Error) as error:
        return "(mkCEvalError {})".format(json.dumps(str(error), ensure_ascii=False))
