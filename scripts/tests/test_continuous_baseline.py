import math
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from continuous_baseline import (parse_sexpr, predict, metrics, complexity,
                                 affine_coefficients, summarize, analyze)


class BaselineReportTests(unittest.TestCase):
    def test_empty_final_result_is_not_a_search_observation(self):
        output = ('(FinalResult ())\n'
                  '(ContinuousInitialization (actualEvaluations 0) (retainedSeeds 0))\n')
        manifest = {'parameters': {'maxEvals': 500, 'continComplexityRatio': 0},
                    'training_error_targets': [1, 0.1], 'evaluation_checkpoints': [1, 10],
                    'acceptance_error': 1e-8}
        with self.assertRaisesRegex(ValueError, 'no scored programs'):
            analyze(output, {'name': 'linear', 'loss': 'squared_error'}, manifest)

    def test_parser_never_executes(self):
        self.assertEqual(parse_sexpr('(c_add 1.0 (c_mul 2.0 "x"))'), ['c_add', 1.0, ['c_mul', 2.0, 'x']])
        self.assertEqual(parse_sexpr('(danger "hello world")'), ['danger', 'hello world'])
        for text in ('(c_add 1', ')', '(x) extra'):
            with self.subTest(text=text), self.assertRaises(ValueError):
                parse_sexpr(text)

    def test_prediction_metrics_and_coefficients(self):
        tree = ['c_add', 1.0, ['c_mul', 2.0, 'x'], ['c_mul', -1.0, 'z']]
        table = (['x', 'z', 'y'], [[0.0, 1.0], [0.0, 1.0], [1.0, 2.0]])
        self.assertEqual(metrics(tree, table, 'squared_error')['sse'], 0)
        self.assertEqual(metrics(tree, table, 'abs_error')['sae'], 0)
        self.assertEqual(affine_coefficients(tree, ['x', 'z']), {'bias': 1, 'x': 2, 'z': -1})
        self.assertEqual(complexity(tree), 5)

    def test_strict_evaluation_order(self):
        self.assertEqual(predict(['c_mul', 0.0, 'missing'], {}), 0)
        with self.assertRaises(KeyError):
            predict(['c_mul', 'missing', 0.0], {})
        with self.assertRaises(ValueError):
            predict(['c_mul', 1e308, 2.0], {})
        with self.assertRaises(ValueError):
            predict(['c_log', -1.0], {})

    def test_nonlinear_prediction_and_complexity(self):
        self.assertEqual(predict(['c_add', 'x', ['c_mul', 'x', 'x']], {'x': 2}), 6)
        self.assertEqual(predict(['c_div', 'x', ['c_add', 1, ['c_mul', 'x', 'x']]], {'x': 2}), 0.4)
        self.assertEqual(predict(['c_sin', 0], {}), 0)
        self.assertEqual(predict(['c_log', 1], {}), 0)
        self.assertEqual(predict(['c_exp', 0], {}), 1)
        self.assertEqual(predict(['c_div', 0, ['c_log', -1]], {}), 0)
        self.assertEqual(predict(['c_mul', 0, ['c_exp', 1000]], {}), 0)
        self.assertEqual(predict(['c_add'], {}), 0)
        self.assertEqual(predict(['c_mul'], {}), 1)
        self.assertEqual(complexity(['c_div', 'x', ['c_sin', 'x']]), 4)
        self.assertEqual(complexity(['c_mul', 0, ['c_exp', 'x']]), 0)
        for tree in (['c_div', 1, 0], ['c_div', 1], ['c_sin', 0, 1],
                     ['c_cos', 0], ['c_log', 0], ['c_exp', 1000],
                     ['c_log', ['c_exp', 1000]]):
            with self.subTest(tree=tree), self.assertRaises((ValueError, OverflowError)):
                predict(tree, {})

    def test_summary_keeps_failures(self):
        summary = summarize([{'case': 'x', 'success': True, 'held_out_success': True,
                              'actual_evaluations': 2, 'process_wall_seconds': 1, 'raw_champion': None},
                             {'case': 'x', 'failure': 'timeout', 'process_wall_seconds': 120}])['x']
        self.assertEqual(summary['runs'], 2)
        self.assertEqual(summary['successful_runs'], 1)
        self.assertEqual(summary['failed_processes_or_reports'], 1)
        self.assertEqual(summary['process_wall_seconds']['max'], 120)


if __name__ == '__main__':
    unittest.main()
