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


if __name__ == '__main__':
    unittest.main()
