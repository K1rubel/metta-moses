import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from continuous_baseline import FIXTURES, metrics, predict
from csv_helper import read_continuous_table


class NonlinearFixturesTests(unittest.TestCase):
    def test_source_derived_numerical_goldens(self):
        fixtures = json.loads((FIXTURES / 'nonlinear-reference.json').read_text())
        for case in fixtures['cases']:
            with self.subTest(case=case['name']):
                if 'error' in case:
                    with self.assertRaises((ValueError, OverflowError)):
                        predict(case['tree'], case.get('environment', {}))
                else:
                    self.assertAlmostEqual(predict(case['tree'], case.get('environment', {})),
                                           case['value'], delta=1e-12)

    def test_declared_targets_fit_all_splits(self):
        manifest = json.loads((FIXTURES / 'step13-manifest.json').read_text())
        self.assertEqual(len(manifest['cases']), 8)
        for case in manifest['cases']:
            inputs = []
            for split in ('train', 'validation', 'test'):
                with self.subTest(case=case['name'], split=split):
                    table = read_continuous_table(FIXTURES / f"{case['name']}-{split}.csv")
                    self.assertLess(metrics(case['target_program'], table, case['loss'])['sse'], 1e-24)
                    inputs.append(set(zip(*table[1][:-1])))
            self.assertFalse(inputs[0] & inputs[1])
            self.assertFalse(inputs[0] & inputs[2])
            self.assertFalse(inputs[1] & inputs[2])


if __name__ == '__main__':
    unittest.main()
