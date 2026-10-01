"""Paired, serial optimizer/ablation comparison. Never overwrite a run.

Continuous analysis reuses the independent evaluator and scorer-trace checks
(affine and the Step 12/13 nonlinear vocabulary).
Boolean controls independently check truth tables; their call accounting is
optimizer-reported (the legacy Boolean initial exemplar is not scored).
"""
import argparse
from collections import Counter
from datetime import datetime, timezone
import itertools
import json
from pathlib import Path
import platform
import random
import statistics
import subprocess
import sys
import tempfile
import time

from continuous_baseline import (ROOT, FIXTURES, analyze, fields, records,
                                source_hash, file_hash, runtime_commit, summarize)


def distribution(values):
    values = list(values)
    return ({'median': statistics.median(values), 'min': min(values), 'max': max(values)}
            if values else None)


def boolean_predict(tree, row):
    if tree in ('true', 'True'):
        return True
    if tree in ('false', 'False'):
        return False
    if isinstance(tree, str):
        return row[tree]
    op, *args = tree
    values = [boolean_predict(arg, row) for arg in args]
    if op == 'AND':
        return all(values)
    if op == 'OR':
        return any(values)
    if op == 'NOT' and len(values) == 1:
        return not values[0]
    raise ValueError(f'unsupported Boolean program: {tree}')


def analyze_boolean(stdout, case, params):
    finals = records(stdout, 'FinalResult')
    if len(finals) != 1:
        raise ValueError(f'expected one FinalResult, got {len(finals)}')
    optimizers = [fields(row) for row in records(stdout, 'OptimizerDiagnostics')]
    calls = sum(row['actualEvaluations'] for row in optimizers)
    if calls > params['maxEvals']:
        raise ValueError('evaluation budget exceeded')
    programs = []
    for tree, raw in finals[0][1]:
        errors = 0
        for bits in itertools.product((False, True), repeat=3):
            target = any(bits) if case['name'] == 'disjunction3' else sum(bits) % 2 == 1
            errors += boolean_predict(tree, dict(zip(('X1', 'X2', 'X3'), bits))) != target
        if -errors != raw:
            raise ValueError(f'Boolean raw score disagreement: {tree}: {-errors} != {raw}')
        programs.append({'program': tree, 'raw': raw})
    best = max(programs, key=lambda p: p['raw'], default=None)
    return {'success': best is not None and best['raw'] == 0, 'held_out_success': False,
            'raw_champion': best, 'actual_evaluations': calls,
            'proposals': sum(r['proposals'] for r in optimizers),
            'cache_hits': sum(r['cacheHits'] for r in optimizers),
            'invalid_evaluations': sum(r['invalids'] for r in optimizers),
            'optimizer_trace': optimizers, 'returned_programs': programs}


def model_diagnostics(stdout):
    fits = [fields(r) for r in records(stdout, 'ModelFitDiagnostics')]
    populations = [fields(r) for r in records(stdout, 'PopulationDiagnostics')]
    replacements = [fields(r) for r in records(stdout, 'ReplacementDiagnostics')]
    return {'fit_trace': fits, 'population_trace': populations,
            'replacement_trace': replacements,
            'rtr_accepted': sum(r['accepted'] for r in replacements),
            'rtr_offspring': sum(r['offspring'] for r in replacements),
            'max_tree_nodes': max((r.get('treeNodes', 0) for r in fits), default=0),
            'model_fitting_seconds': sum(r['seconds'] for r in fits),
            'fits': len(fits), 'max_learned_edges': max((r.get('learnedEdges', 0) for r in fits), default=0),
            'max_model_parameters': max((r.get('parameters', 0) for r in fits), default=0),
            'local_fits': sum(r.get('localFits', 0) for r in fits),
            'score_cache_hits': sum(r.get('scoreCacheHits', 0) for r in fits),
            'unretained_proposals': sum(r['unretainedProposals'] for r in populations),
            'fitting_stops': dict(Counter(r.get('stop', 'univariate') for r in fits))}


def paired_delta(left, right, key):
    """Left minus right; do not turn missing/failed observations into zero."""
    a = {r['seed']: r for r in left}
    b = {r['seed']: r for r in right}
    paired = [(a[s], b[s]) for s in sorted(a.keys() & b.keys())]
    values = [x[key] - y[key] for x, y in paired if key in x and key in y
              and not x.get('failure') and not y.get('failure')]
    out = {'paired_runs': len(paired), 'usable_pairs': len(values), 'delta': distribution(values)}
    if values:
        rng = random.Random(10010)
        bootstrap = sorted(statistics.median(rng.choices(values, k=len(values))) for _ in range(2000))
        out['median_delta_bootstrap_95'] = [bootstrap[49], bootstrap[1949]]
        out['left_lower_equal_higher'] = [sum(v < 0 for v in values), sum(v == 0 for v in values),
                                           sum(v > 0 for v in values)]
    return out


def comparison_summary(runs, algorithms):
    groups = {}
    pairs = {}
    for name in sorted({r['case'] for r in runs}):
        groups[name] = {}
        for algo in algorithms:
            rows = [r for r in runs if r['case'] == name and r['algorithm'] == algo]
            if not rows:
                continue
            group = summarize(rows)[name]
            for key in ('model_fitting_seconds', 'max_learned_edges', 'max_model_parameters',
                        'proposals', 'cache_hits', 'invalid_evaluations', 'unretained_proposals'):
                group[key] = distribution(r[key] for r in rows if key in r)
            group['optimizer_stops'] = dict(Counter(o['stop'] for r in rows for o in r.get('optimizer_trace', [])))
            group['fitting_stops'] = dict(sum((Counter(r.get('fitting_stops', {})) for r in rows), Counter()))
            target_keys = sorted({t for r in rows for t in r.get('targets', {})})
            group['targets'] = {}
            for target in target_keys:
                hits = [r['targets'][target] for r in rows if r.get('targets', {}).get(target) is not None]
                group['targets'][target] = {'reached': len(hits), 'total': len(rows),
                    'calls_among_reached': distribution(h['evaluations'] for h in hits),
                    'search_seconds_among_reached': distribution(h['search_elapsed_seconds'] for h in hits)}
            groups[name][algo] = group
        treatment = 'hboa' if 'hboa' in algorithms else 'boa'
        for control in (a for a in algorithms if a != treatment):
            left = [r for r in runs if r['case'] == name and r['algorithm'] == treatment]
            right = [r for r in runs if r['case'] == name and r['algorithm'] == control]
            if left and right:
                pairs[f'{name}:{treatment}-minus-{control}'] = {
                    key: paired_delta(left, right, key)
                    for key in ('actual_evaluations', 'process_wall_seconds', 'model_fitting_seconds')}
    return {'groups': groups, 'paired_differences': pairs,
            'note': 'Call deltas are work consumed, not time-to-success when a run fails. '
                    'Unreached targets stay censored; target medians explicitly condition on reaching.'}


def algorithm_settings(manifest, label):
    """Labels name experimental arms, not necessarily distinct implementations."""
    return {'optAlgo': label, **manifest.get('algorithm_parameters', {}).get(label, {})}


def run_process(command, cwd, timeout):
    """Run without an inheritable output pipe; terminate child trees on timeout."""
    with tempfile.TemporaryFile(mode='w+t', encoding='utf-8', errors='replace') as output:
        process = subprocess.Popen(command, cwd=cwd, stdout=output, stderr=subprocess.STDOUT,
                                   text=True, encoding='utf-8', errors='replace')
        try:
            return_code = process.wait(timeout=timeout)
            timed_out = False
        except subprocess.TimeoutExpired:
            timed_out = True
            if platform.system() == 'Windows':
                subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                               timeout=15, check=False)
            if process.poll() is None:
                process.kill()
            process.wait(timeout=15)
            return_code = process.returncode
        output.seek(0)
        return return_code, output.read(), timed_out


def linkage_score(bits, problem):
    if problem == 'trap12':
        if len(bits) != 12:
            raise ValueError('trap12 requires 12 bits')
        return sum(3 if sum(bits[i:i+3]) == 3 else 2 - sum(bits[i:i+3]) for i in range(0, 12, 3))
    if problem == 'hiff8':
        if len(bits) != 8:
            raise ValueError('hiff8 requires 8 bits')
        return sum(k for k in (1, 2, 4, 8) for i in range(0, 8, k)
                   if len(set(bits[i:i+k])) == 1)
    raise ValueError(f'unknown linkage problem: {problem}')


def analyze_linkage(stdout, case, params):
    finals = records(stdout, 'LinkageResult')
    if len(finals) != 1:
        raise ValueError('expected one fixed-deme result')
    final = fields(finals[0])
    trace = [fields(r) for r in records(stdout, 'LinkageEvaluation')]
    if len(trace) != final['actualEvaluations'] or len(trace) > params['maxEvals']:
        raise ValueError('fixed-deme scorer-call accounting mismatch')
    for i, row in enumerate(trace, 1):
        if (row['scorerCallIndex'] != i or any(b not in (0, 1) for b in row['bits'])
                or linkage_score(row['bits'], case['name']) != row['raw']):
            raise ValueError('fixed-deme trace/score mismatch')
    rows = final['rows']
    for bits, raw in rows:
        if linkage_score(bits, case['name']) != raw:
            raise ValueError('fixed-deme exported score mismatch')
    best = max((r['raw'] for r in trace), default=None)
    if best != max((r[1] for r in rows), default=None):
        raise ValueError('fixed-deme archive lost raw champion')
    target = case['target']
    reached = next((r for r in trace if r['raw'] >= target), None)
    return {'success': reached is not None, 'held_out_success': False,
            'raw_champion': {'raw': best}, 'actual_evaluations': len(trace),
            'proposals': final['proposals'], 'cache_hits': final['cacheHits'],
            'invalid_evaluations': final['invalids'], 'optimizer_trace': [final],
            'returned_vectors': rows, 'evaluation_trace': trace,
            'targets': {str(target): None if reached is None else {
                'evaluations': reached['scorerCallIndex'], 'search_elapsed_seconds': reached['elapsed']}}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--petta-main', type=Path, required=True)
    parser.add_argument('--swipl', default='swipl')
    parser.add_argument('--petta-commit')
    parser.add_argument('--manifest', type=Path, default=FIXTURES / 'step10-manifest.json')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--seeds', help='comma-separated development/exploratory override')
    parser.add_argument('--cases', help='comma-separated case filter')
    parser.add_argument('--timeout', type=float, default=120)
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text(encoding='utf-8'))
    seeds = list(map(int, args.seeds.split(','))) if args.seeds else manifest['seeds']
    requested = set(args.cases.split(',')) if args.cases else {c['name'] for c in manifest['cases']}
    cases = [c for c in manifest['cases'] if c['name'] in requested]
    algorithms = manifest['algorithms']
    if (not seeds or len(set(seeds)) != len(seeds) or not cases
            or requested != {c['name'] for c in cases} or not args.petta_main.is_file()
            or len(set(algorithms)) != len(algorithms)
            or any(algorithm_settings(manifest, a)['optAlgo'] not in ('hc', 'univariate', 'boa', 'hboa') for a in algorithms)):
        parser.error('invalid seeds, cases, algorithms or PeTTa path')
    metadata = {'created_utc': datetime.now(timezone.utc).isoformat(), 'platform': platform.platform(),
        'processor': platform.processor(), 'python': sys.version,
        'swipl': subprocess.check_output([args.swipl, '--version'], text=True).strip(),
        'petta_main': str(args.petta_main.resolve()),
        'petta_commit': args.petta_commit or runtime_commit(args.petta_main),
        'petta_main_sha256': file_hash(args.petta_main), 'manifest': manifest,
        'manifest_sha256': file_hash(args.manifest), 'source_sha256': source_hash(),
        'git_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        'git_status': subprocess.check_output(['git', 'status', '--short'], cwd=ROOT, text=True),
        'seeds': seeds, 'cases': sorted(requested), 'exploratory_override': bool(args.seeds or args.cases),
        'timing': 'serial fresh processes; rotate algorithm order per seed; process time includes imports/CSV; '
                  'continuous trace elapsed starts at cache reset; instrumentation included',
        'dataset_hashes': {p.name: file_hash(p) for p in sorted(FIXTURES.glob('*.csv'))}}
    args.output.mkdir(parents=True, exist_ok=False)
    (args.output / 'metadata.json').write_text(json.dumps(metadata, indent=2), encoding='utf-8')
    runs = []
    for case in cases:
        for seed_index, seed in enumerate(seeds):
            rotation = seed_index % len(algorithms)
            for algo in algorithms[rotation:] + algorithms[:rotation]:
                if algo not in case.get('algorithms', algorithms):
                    continue
                params = {**manifest['parameters'], **case.get('parameters', {}),
                          **algorithm_settings(manifest, algo), 'seed': seed}
                if case.get('kind', 'continuous') == 'continuous':
                    params.update(continErrorType=case['loss'],
                                  inputFile=(FIXTURES / f"{case['name']}-train.csv").relative_to(ROOT).as_posix())
                flags = [f'--{k}={v}' for k, v in params.items()]
                command = [args.swipl, '--stack_limit=8g', '-q', '-s', str(args.petta_main.resolve()),
                           '--', case.get('entrypoint', 'moses.metta'), '-s', *flags]
                start = time.perf_counter()
                record = {'case': case['name'], 'seed': seed, 'algorithm': algo, 'command': command}
                try:
                    return_code, stdout, timed_out = run_process(command, ROOT, args.timeout)
                    record.update(process_wall_seconds=time.perf_counter() - start, exit_code=return_code)
                    if timed_out:
                        record['failure'] = f'process safety timeout after {args.timeout:g}s'
                    elif return_code or 'ERROR:' in stdout or '❌' in stdout:
                        record['failure'] = f'runtime exit/error {return_code}'
                    else:
                        try:
                            if case.get('kind') == 'linkage':
                                record.update(analyze_linkage(stdout, case, params))
                            elif case.get('kind') == 'boolean':
                                record.update(analyze_boolean(stdout, case, params))
                            else:
                                record.update(analyze(stdout, case, {**manifest, 'parameters': params}))
                            record.update(model_diagnostics(stdout))
                        except (ValueError, KeyError, TypeError, OverflowError) as error:
                            record['failure'] = str(error)
                except subprocess.TimeoutExpired as error:
                    stdout = error.stdout or ''
                    if isinstance(stdout, bytes):
                        stdout = stdout.decode('utf-8', errors='replace')
                    record['failure'] = 'process safety timeout (not optimizer time-to-target)'
                record.setdefault('process_wall_seconds', time.perf_counter() - start)
                stem = f"{case['name']}-{seed}-{algo}"
                (args.output / f'{stem}.stdout.txt').write_text(stdout, encoding='utf-8')
                (args.output / f'{stem}.json').write_text(json.dumps(record, indent=2, allow_nan=False), encoding='utf-8')
                runs.append(record)
                print(json.dumps({k: record.get(k) for k in ('case', 'seed', 'algorithm', 'success',
                      'actual_evaluations', 'process_wall_seconds', 'failure')}), flush=True)
    summary = comparison_summary(runs, algorithms)
    summary['source_unchanged'] = source_hash() == metadata['source_sha256']
    (args.output / 'summary.json').write_text(json.dumps(summary, indent=2, allow_nan=False), encoding='utf-8')
    return 1 if any(r.get('failure') for r in runs) or not summary['source_unchanged'] else 0


if __name__ == '__main__':
    raise SystemExit(main())
