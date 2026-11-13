import csv
import math
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import csv_helper


class ContinuousCSVTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / "input.csv"

    def load_text(self, text, target=""):
        self.path.write_text(text, encoding="utf-8")
        return csv_helper.load_continuous_table(self.path, target)

    def test_column_major_and_binary64(self):
        self.assertEqual(self.load_text("x,y\n-1,2\n.5,+3e1\n"),
                         '(mkITable ((-1.0 0.5) (2.0 30.0)) ("x" "y"))')

    def test_reorder_named_target(self):
        self.assertEqual(self.load_text("y,x,z\n3,1,2\n5,2,4\n", "y"),
                         '(mkITable ((1.0 2.0) (2.0 4.0) (3.0 5.0)) ("x" "z" "y"))')

    def test_exact_string_headers(self):
        labels = [' x ', 'c_add', '123', '$x', '(danger)', 'a"b', 'a\\b', 'ሀ', 'out']
        with self.path.open("w", encoding="utf-8", newline="") as stream:
            writer = csv.writer(stream)
            writer.writerow(labels)
            writer.writerow(range(len(labels)))
        actual_labels, columns = csv_helper.read_continuous_table(self.path)
        self.assertEqual(actual_labels, labels)
        self.assertEqual(columns, [[float(i)] for i in range(len(labels))])
        rendered = csv_helper.load_continuous_table(self.path)
        self.assertIn('" x "', rendered)
        self.assertIn('"a\\"b"', rendered)
        self.assertIn('"ሀ"', rendered)

    def test_target_only_and_bom(self):
        self.assertEqual(self.load_text('\ufefftarget\n-0\n1e-300\n'),
                         '(mkITable ((-0.0 1e-300)) ("target"))')
        _, columns = csv_helper.read_continuous_table(self.path)
        self.assertEqual(math.copysign(1, columns[0][0]), -1)

    def test_bad_cells_have_coordinates(self):
        for cell in ("", "NaN", "Inf", "-Infinity", "1e309", "True", "yes", "1_000", "0x10"):
            with self.subTest(cell=cell), self.assertRaisesRegex(ValueError, r"row 2, column 2 \('y'\)"):
                self.load_text(f"x,y\n0,{cell}\n")

    def test_shape_and_header_errors(self):
        cases = [('', 'empty CSV'), ('x,y\n', 'header only'),
                 ('x,x\n1,2\n', 'duplicate header'), ('x, \n1,2\n', 'empty header'),
                 ('x,y\n1\n', 'row 2'), ('x,y\n1,2,3\n', 'row 2'),
                 ('x,y\n\n', 'row 2')]
        for text, message in cases:
            with self.subTest(text=text), self.assertRaisesRegex(ValueError, message):
                self.load_text(text)

    def test_target_is_exact(self):
        self.assertIn('("x" " y ")', self.load_text(' y ,x\n2,1\n', ' y '))
        with self.assertRaisesRegex(ValueError, 'target feature'):
            self.load_text(' y ,x\n2,1\n', 'y')

    def test_malformed_csv(self):
        with self.assertRaisesRegex(csv.Error, 'row 2'):
            self.load_text('x,y\n"unterminated,2\n')

    def test_unsupported_header_controls_are_not_silently_changed(self):
        for char in ('\b', '\f', '\x00'):
            with self.subTest(char=char), self.assertRaisesRegex(ValueError, 'control character'):
                self.load_text(f'a{char}b,y\n1,2\n')

    def test_bridge_tags_errors(self):
        result = csv_helper.load_continuous_table_result(self.path)
        self.assertTrue(result.startswith('(mkCEvalError "'))
        self.path.write_text('x,y\n1,NaN\n', encoding='utf-8')
        self.assertIn('row 2, column 2', csv_helper.load_continuous_table_result(self.path))

    def test_boolean_behavior_unchanged(self):
        self.path.write_text(' x ,y\nYES,0\nf,True\n', encoding='utf-8')
        self.assertEqual(csv_helper.load_boolean_table(self.path),
                         '(mkITable ((True False) (False True)) (x y))')
        self.path.write_text('x,y\n0.5,1\n', encoding='utf-8')
        with self.assertRaisesRegex(ValueError, 'as boolean'):
            csv_helper.load_boolean_table(self.path)



class GeneralisedTableTests(unittest.TestCase):
    """Tests for the generalised load_table / load_table_result functions.

    The generalised loader performs two passes over the CSV:
      Pass 1 - infer per-column types (BOOLEAN < CONTIN < ENUM widening).
      Pass 2 - convert cells to MeTTa literals and build the column-major table.

    Output format matches load_boolean_table / load_continuous_table:
        (mkITable (<col0-vals> <col1-vals> ...) ("lbl0" "lbl1" ...))
    with the target column last.
    """

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / "input.csv"

    def _write(self, text):
        self.path.write_text(text, encoding="utf-8")

    def _load(self, text, target=""):
        self._write(text)
        return csv_helper.load_table(self.path, target)

    # ------------------------------------------------------------------
    # Type-inference and serialisation
    # ------------------------------------------------------------------

    def test_boolean_only_column_major(self):
        """Pure-boolean CSV produces column-major True/False literals."""
        result = self._load("x,y\n1,0\nt,f\n")
        # column 0 (x): True True  |  column 1 (y, target by default): False False
        self.assertEqual(result,
                         '(mkITable ((True True) (False False)) ("x" "y"))')

    def test_continuous_only_column_major(self):
        """Pure-float CSV produces column-major repr(float) literals."""
        result = self._load("a,b\n1,2\n3,4\n")
        # 0/1 columns widen to CONTIN once they mix — but here they're ambiguous.
        # 1,2,3,4 are all parseable as CONTIN once type widening promotes 1/0
        # Actually 1,3 are BOOLEAN tokens (single digit 0/1), so column a stays
        # BOOLEAN and column b stays BOOLEAN here.
        # Let's use unambiguous floats:
        result2 = self._load("a,b\n1.5,2.0\n3.0,4.5\n")
        self.assertEqual(result2,
                         '(mkITable ((1.5 3.0) (2.0 4.5)) ("a" "b"))')

    def test_mixed_bool_widens_to_contin(self):
        """A column that starts 0/1 then sees a float widens to CONTIN."""
        result = self._load("x,y\n1,0\n0.5,1\n")
        # col x: 1 -> BOOLEAN, then 0.5 -> CONTIN; widen to CONTIN
        # col y: 0 -> BOOLEAN, then 1 -> BOOLEAN; stays BOOLEAN (default target)
        self.assertEqual(result,
                         '(mkITable ((1.0 0.5) (False True)) ("x" "y"))')

    def test_enum_column(self):
        """String-valued column is preserved as bare MeTTa atoms."""
        result = self._load("label,score\nspam,1\nham,0\n")
        # label: alphabetic -> ENUM  |  score: 0/1 -> BOOLEAN
        self.assertEqual(result,
                         '(mkITable ((spam ham) (True False)) ("label" "score"))')

    def test_enum_values_as_target(self):
        """Enum column can be the named target; it moves to last position."""
        result = self._load("score,label\n1,spam\n0,ham\n", target="label")
        self.assertEqual(result,
                         '(mkITable ((True False) (spam ham)) ("score" "label"))')

    # ------------------------------------------------------------------
    # Target-column reordering
    # ------------------------------------------------------------------

    def test_target_last_by_default(self):
        """With no target specified, the last column stays last."""
        result = self._load("x,y,z\n1,0,1\n0,1,0\n")
        self.assertEqual(result,
                         '(mkITable ((True False) (False True) (True False)) ("x" "y" "z"))')

    def test_target_reorder_named(self):
        """Named target column is moved to last position in both data and labels."""
        result = self._load("out,a,b\n1,0,1\n0,1,0\n", target="out")
        # out moves last; a and b keep their relative order
        self.assertEqual(result,
                         '(mkITable ((False True) (True False) (True False)) ("a" "b" "out"))')

    def test_target_already_last(self):
        """Naming the last column explicitly still produces correct output."""
        result = self._load("x,y\n1,0\n0,1\n", target="y")
        self.assertEqual(result,
                         '(mkITable ((True False) (False True)) ("x" "y"))')

    # ------------------------------------------------------------------
    # Comment-line skipping
    # ------------------------------------------------------------------

    def test_comment_hash_skipped(self):
        """Lines starting with # are ignored (C++ get_data_line behaviour)."""
        result = self._load("x,y\n# this is a comment\n1,0\n0,1\n")
        self.assertEqual(result,
                         '(mkITable ((True False) (False True)) ("x" "y"))')

    def test_comment_semicolon_skipped(self):
        result = self._load("x,y\n; comment\n1,0\n")
        self.assertEqual(result,
                         '(mkITable ((True) (False)) ("x" "y"))')

    def test_comment_bang_skipped(self):
        result = self._load("x,y\n! comment\n0,1\n")
        self.assertEqual(result,
                         '(mkITable ((False) (True)) ("x" "y"))')

    # ------------------------------------------------------------------
    # UTF-8 BOM
    # ------------------------------------------------------------------

    def test_bom_stripped(self):
        """A leading UTF-8 BOM does not appear in the first column label."""
        self.path.write_bytes(b"\xef\xbb\xbfx,y\r\n1,0\r\n")
        result = csv_helper.load_table(self.path)
        self.assertIn('"x"', result)
        self.assertNotIn("\ufeff", result)

    # ------------------------------------------------------------------
    # Error handling
    # ------------------------------------------------------------------

    def test_empty_file_raises(self):
        with self.assertRaisesRegex(ValueError, "empty CSV"):
            self._load("")

    def test_header_only_raises(self):
        with self.assertRaisesRegex(ValueError, "header only"):
            self._load("x,y\n")

    def test_ragged_row_raises(self):
        with self.assertRaisesRegex(ValueError, "row 3"):
            self._load("x,y\n1,0\n1\n")

    def test_unknown_target_raises(self):
        with self.assertRaisesRegex(ValueError, "target feature"):
            self._load("x,y\n1,0\n", target="z")

    def test_duplicate_header_raises(self):
        with self.assertRaisesRegex(ValueError, "duplicate header"):
            self._load("x,x\n1,0\n")

    def test_empty_header_cell_raises(self):
        with self.assertRaisesRegex(ValueError, "empty header"):
            self._load("x, \n1,0\n")

    # ------------------------------------------------------------------
    # Error bridge
    # ------------------------------------------------------------------

    def test_bridge_missing_file(self):
        result = csv_helper.load_table_result(self.path)   # file not written
        self.assertTrue(result.startswith("(mkCEvalError "))

    def test_bridge_bad_file(self):
        result = csv_helper.load_table_result(self.path)
        self.assertIn("mkCEvalError", result)

    def test_bridge_on_success(self):
        self._write("x,y\n1,0\n")
        result = csv_helper.load_table_result(self.path)
        self.assertTrue(result.startswith("(mkITable "))

    # ------------------------------------------------------------------
    # Consistency with the specialised loaders
    # ------------------------------------------------------------------

    def test_pure_boolean_consistent_with_load_boolean_table(self):
        """For a pure-boolean CSV, load_table and load_boolean_table agree
        on data values and label ordering (though label quoting differs:
        load_boolean_table uses bare symbols, load_table uses JSON strings).
        """
        self._write("x,y\n1,0\nt,f\nT,F\n")
        gen = csv_helper.load_table(self.path)
        # Verify the data payload is the same (extract inner lists).
        import re
        data_gen = re.search(r"mkITable (\(.*?\)) \(", gen).group(1)
        # load_boolean_table result for reference
        bool_ref = csv_helper.load_boolean_table(self.path)
        data_ref = re.search(r"mkITable (\(.*?\)) \(", bool_ref).group(1)
        self.assertEqual(data_gen, data_ref)

    def test_pure_continuous_consistent_with_load_continuous_table(self):
        """For a pure-float CSV, load_table and load_continuous_table agree
        on data values (both use repr(float)) and JSON-quoted labels.
        """
        self._write("x,y\n1.5,2.0\n3.0,4.5\n")
        self.assertEqual(
            csv_helper.load_table(self.path),
            csv_helper.load_continuous_table(self.path),
        )


if __name__ == "__main__":
    unittest.main()
