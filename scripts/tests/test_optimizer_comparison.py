from pathlib import Path
import sys
import unittest
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from optimizer_comparison import (analyze_boolean, boolean_predict, model_diagnostics,
                                  paired_delta, comparison_summary, algorithm_settings,
                                  linkage_score, analyze_linkage, run_process)


class ComparisonTests(unittest.TestCase):
    def test_process_timeout_is_bounded(self):
        start = time.perf_counter()
        code, output, timed_out = run_process(
            [sys.executable, '-c', 'import time; time.sleep(5)'], Path.cwd(), 0.2)
        self.assertTrue(timed_out)
        self.assertNotEqual(code, 0)
        self.assertLess(time.perf_counter() - start, 10)

    def test_arms(self):
        self.assertEqual(algorithm_settings({}, 'hc'), {'optAlgo': 'hc'})
        self.assertEqual(algorithm_settings({'algorithm_parameters': {'off': {
            'optAlgo': 'hboa', 'hboaLearnDependencies': False}}}, 'off'),
            {'optAlgo': 'hboa', 'hboaLearnDependencies': False})

    def test_linkage_objectives(self):
        self.assertEqual(linkage_score([0]*12, 'trap12'), 8)
        self.assertEqual(linkage_score([1]*12, 'trap12'), 12)
        self.assertEqual(linkage_score([1, 1, 0]*4, 'trap12'), 0)
        self.assertEqual(linkage_score([0, 1]*4, 'hiff8'), 8)
        self.assertEqual(linkage_score([0]*8, 'hiff8'), 32)
        self.assertEqual(linkage_score([1]*8, 'hiff8'), 32)
        self.assertEqual(linkage_score([0]*4+[1]*4, 'hiff8'), 24)

    def test_linkage_accounting(self):
        trace = '(LinkageEvaluation (scorerCallIndex 1) (elapsed 0.1) (bits (0 0 0 0 0 0 0 0)) (raw 32))\n'
        result = ('(LinkageResult (actualEvaluations 1) (stop stopTargetReached) (proposals 1) '
                  '(cacheHits 0) (invalids 0) (rows (((0 0 0 0 0 0 0 0) 32))))')
        self.assertTrue(analyze_linkage(trace+result, {'name': 'hiff8', 'target': 32}, {'maxEvals': 256})['success'])
        with self.assertRaises(ValueError):
            analyze_linkage(trace+result.replace('actualEvaluations 1', 'actualEvaluations 2'),
                            {'name': 'hiff8', 'target': 32}, {'maxEvals': 256})
        with self.assertRaises(ValueError):
            analyze_linkage(trace.replace('(raw 32)', '(raw 31)')+result,
                            {'name': 'hiff8', 'target': 32}, {'maxEvals': 256})

    def test_boolean_evaluation(self):
        self.assertTrue(boolean_predict(['AND'], {}))
        self.assertFalse(boolean_predict(['OR'], {}))
        self.assertTrue(boolean_predict(['OR', 'X1', ['NOT', 'X2']], {'X1': False, 'X2': False}))
        for case, program, raw in [('disjunction3', '(OR X1 X2 X3)', 0), ('parity3', 'X1', -4)]:
            result = analyze_boolean(f'(FinalResult (({program} {raw})))', {'name': case}, {'maxEvals': 10})
            self.assertEqual(result['raw_champion']['raw'], raw)
        with self.assertRaises(ValueError):
            analyze_boolean('(FinalResult ((X1 0)))', {'name': 'parity3'}, {'maxEvals': 10})

    def test_diagnostics_and_empty(self):
        self.assertEqual(model_diagnostics('')['model_fitting_seconds'], 0)
        result = model_diagnostics('(ModelFitDiagnostics (algorithm boa) (seconds 0.25) (learnedEdges 2) '
            '(parameters 5) (localFits 10) (scoreCacheHits 3) (stop fitConverged))\n'
            '(PopulationDiagnostics (unretainedProposals 4))')
        self.assertEqual(result['model_fitting_seconds'], 0.25)
        self.assertEqual(result['max_learned_edges'], 2)
        self.assertEqual(result['unretained_proposals'], 4)

    def test_pairs_exclude_failures_not_zero_fill(self):
        a = [{'seed': 1, 'calls': 3}, {'seed': 2, 'calls': 20, 'failure': 'timeout'}, {'seed': 3}]
        b = [{'seed': 1, 'calls': 5}, {'seed': 2, 'calls': 4}, {'seed': 3, 'calls': 4}]
        result = paired_delta(a, b, 'calls')
        self.assertEqual(result['paired_runs'], 3)
        self.assertEqual(result['usable_pairs'], 1)
        self.assertEqual(result['delta']['median'], -2)
        self.assertEqual(result['median_delta_bootstrap_95'], [-2, -2])

    def test_summary_censors_targets(self):
        rows = [{'case': 'x', 'algorithm': 'boa', 'seed': 1, 'success': True, 'actual_evaluations': 3,
                 'process_wall_seconds': 1, 'raw_champion': None,
                 'targets': {'0': {'evaluations': 3, 'search_elapsed_seconds': 0.5}}},
                {'case': 'x', 'algorithm': 'boa', 'seed': 2, 'failure': 'timeout', 'process_wall_seconds': 120}]
        group = comparison_summary(rows, ['boa'])['groups']['x']['boa']
        self.assertEqual(group['targets']['0']['reached'], 1)
        self.assertEqual(group['targets']['0']['total'], 2)
        self.assertEqual(group['failed_processes_or_reports'], 1)


if __name__ == '__main__':
    unittest.main()
