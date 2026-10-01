"""Reproducible Step 8 HC baseline, with counted/time traces and held-out checks.

Runs the real CLI in fresh processes, serially. No fitting library or surrogate
optimizer is used. Data splits/parameters/seeds come from the versioned manifest.
JSON artifacts and raw stdout are written only to a NEW output directory.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import platform
import re
import statistics
import subprocess
import sys
import time

from csv_helper import read_continuous_table

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "tests/fixtures/continuous"


def parse_sexpr(source):
    """Read data, never eval program text. Supports continuous CLI ASTs."""
    tokens = re.findall(r'"(?:\\.|[^"\\])*"|[()]|[^\s()]+', source)
    index = 0

    def read():
        nonlocal index
        if index >= len(tokens):
            raise ValueError("truncated S-expression")
        token = tokens[index]
        index += 1
        if token == '(':
            result = []
            while index < len(tokens) and tokens[index] != ')':
                result.append(read())
            if index == len(tokens):
                raise ValueError("missing closing parenthesis")
            index += 1
            return result
        if token == ')':
            raise ValueError("unexpected closing parenthesis")
        if token.startswith('"'):
            return json.loads(token)
        try:
            return int(token)
        except ValueError:
            try:
                number = float(token)
                if not math.isfinite(number):
                    raise ValueError("non-finite numeric output")
                return number
            except ValueError:
                return token

    result = read()
    if index != len(tokens):
        raise ValueError("trailing S-expression data")
    return result


def finite(value):
    if not math.isfinite(value):
        raise ValueError("non-finite prediction/error")
    return value


def predict(tree, environment):
    """Independent continuous output check, including failure/short-circuit order."""
    if isinstance(tree, (int, float)):
        return finite(float(tree))
    if isinstance(tree, str):
        return finite(environment[tree])
    if not isinstance(tree, list) or not tree:
        raise ValueError(f"not a supported continuous output: {tree!r}")
    op, *args = tree
    if op == 'c_div' and len(args) == 2:
        numerator = predict(args[0], environment)
        if numerator == 0:
            return 0.0
        denominator = predict(args[1], environment)
        if denominator == 0:
            raise ValueError('division by zero')
        return finite(numerator / denominator)
    if op in ('c_sin', 'c_log', 'c_exp') and len(args) == 1:
        return finite({'c_sin': math.sin, 'c_log': math.log, 'c_exp': math.exp}[op](
            predict(args[0], environment)))
    if op not in ('c_add', 'c_mul'):
        raise ValueError(f"unsupported operator/arity: {tree!r}")
    value = 0.0 if tree[0] == 'c_add' else 1.0
    for child in tree[1:]:
        if tree[0] == 'c_mul' and value == 0:
            break
        operand = predict(child, environment)
        value = finite(value + operand if tree[0] == 'c_add' else value * operand)
    return value


def complexity(tree):
    if not isinstance(tree, list):
        return 1
    if (tree[0] == 'c_mul' and len(tree) > 1
            and isinstance(tree[1], (int, float)) and tree[1] == 0):
        return 0
    return (int(tree[0] in ('c_div', 'c_sin', 'c_log', 'c_exp'))
            + sum(complexity(child) for child in tree[1:]))


def metrics(tree, table, loss):
    labels, columns = table
    errors = []
    for row in zip(*columns):
        errors.append(finite(predict(tree, dict(zip(labels[:-1], row[:-1]))) - row[-1]))
    sse = sae = 0.0
    for error in errors:
        sse = finite(sse + finite(error * error))
        sae = finite(sae + abs(error))
    return {"sse": sse, "sae": sae, "rmse": math.sqrt(sse / len(errors)),
            "mae": sae / len(errors), "raw": -(sse if loss == 'squared_error' else sae),
            "rows": len(errors), "valid_rows": len(errors)}


def affine_coefficients(tree, labels):
    """Report coefficient recovery only for manifest-designated affine cases."""
    origin = {label: 0.0 for label in labels}
    bias = predict(tree, origin)
    return {"bias": bias, **{label: predict(tree, {**origin, label: 1.0}) - bias for label in labels}}


def records(stdout, tag):
    return [parse_sexpr(line) for line in stdout.splitlines() if line.startswith('(' + tag + ' ')]


def fields(record):
    return {entry[0]: entry[1] for entry in record[1:]}


def analyze(stdout, case, manifest):
    finals = records(stdout, 'FinalResult')
    if len(finals) != 1:
        raise ValueError(f"expected one FinalResult, got {len(finals)}")
    evaluations = [fields(row) for row in records(stdout, 'ContinuousEvaluation')]
    if [r['scorerCallIndex'] for r in evaluations] != list(range(1, len(evaluations) + 1)):
        raise ValueError("non-contiguous scorer trace")
    initialization = [fields(row) for row in records(stdout, 'ContinuousInitialization')]
    optimizers = [fields(row) for row in records(stdout, 'OptimizerDiagnostics')]
    if len(initialization) != 1 or initialization[0]['actualEvaluations'] + sum(
            row['actualEvaluations'] for row in optimizers) != len(evaluations):
        raise ValueError("trace does not agree with generic evaluator accounting")
    if len(evaluations) > manifest['parameters']['maxEvals']:
        raise ValueError("evaluation budget exceeded")
    tables = {split: read_continuous_table(FIXTURES / f"{case['name']}-{split}.csv")
              for split in ('train', 'validation', 'test')}
    programs = []
    for tree, raw in finals[0][1]:
        # Evaluate every retained final program, but never use held-out data
        # to select the reported champions or feed back into search.
        measured = metrics(tree, tables['train'], case['loss'])
        if not math.isclose(measured['raw'], raw, rel_tol=1e-12, abs_tol=1e-12):
            raise ValueError("exported program's raw score disagrees with independent evaluation")
        programs.append({"program": tree, "raw": raw, "complexity": complexity(tree),
                         "penalized": raw - manifest['parameters']['continComplexityRatio'] * complexity(tree),
                         "train": measured})
    raw_best = max(programs, key=lambda p: (p['raw'], -p['complexity']), default=None)
    penalized_best = max(programs, key=lambda p: (p['penalized'], -p['complexity']), default=None)
    if raw_best is None:
        raise ValueError("FinalResult contains no scored programs")
    if raw_best is None:
        raise ValueError("FinalResult contains no scored programs")
    for champion in (raw_best, penalized_best):
        if champion is None:
            continue
        for split in ('validation', 'test'):
            try:
                champion[split] = metrics(champion['program'], tables[split], case['loss'])
            except (ValueError, KeyError, OverflowError) as error:
                champion[split] = {"failure": str(error), "rows": len(tables[split][1][-1]), "valid_rows": 0}
        if case.get('identifiable', False) and case.get('family', 'affine') == 'affine':
            champion['coefficients'] = affine_coefficients(champion['program'], tables['train'][0][:-1])
            champion['max_coefficient_error'] = max(abs(champion['coefficients'][k] - v)
                                                     for k, v in case['coefficients'].items())
    valid_events = [r for r in evaluations if r['status'] == 'candidateValid']
    targets = {}
    for tolerance in manifest['training_error_targets']:
        hit = next((r for r in valid_events if r['raw'] >= -tolerance), None)
        targets[str(tolerance)] = None if hit is None else {
            "evaluations": hit['scorerCallIndex'], "search_elapsed_seconds": hit['elapsed']}
    curve = []
    for budget in manifest['evaluation_checkpoints']:
        observed = [r['raw'] for r in valid_events if r['scorerCallIndex'] <= budget]
        curve.append({"evaluation_budget": budget, "best_raw": max(observed) if observed else None,
                      "run_already_ended": budget > len(evaluations)})
    tolerance = manifest['acceptance_error']
    success = raw_best is not None and raw_best['raw'] >= -tolerance
    held_out_success = bool(success and raw_best['test'].get('raw', -math.inf) >= -tolerance)
    return {"success": success, "held_out_success": held_out_success,
            "actual_evaluations": len(evaluations), "invalid_evaluations": len(evaluations) - len(valid_events),
            "proposals": sum(r['proposals'] for r in optimizers),
            "cache_hits": sum(r['cacheHits'] for r in optimizers),
            "raw_champion": raw_best, "penalized_champion": penalized_best,
            "returned_programs": programs, "targets": targets, "evaluation_curve": curve,
            "evaluation_trace": evaluations, "optimizer_trace": optimizers,
            "generation_trace": [fields(r) for r in records(stdout, 'GenerationDiagnostics')]}


def file_hash(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_hash():
    paths = sorted(list(ROOT.rglob('*.metta')) + list((ROOT / 'scripts').rglob('*.py')))
    digest = hashlib.sha256()
    for path in paths:
        if any(part in ('.venv', 'venv', '.git') for part in path.relative_to(ROOT).parts):
            continue
        digest.update(path.relative_to(ROOT).as_posix().encode())
        digest.update(path.read_bytes())
    return digest.hexdigest()


def runtime_commit(main_file):
    result = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=main_file.resolve().parents[1],
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    # A read-only runtime checkout may have different ownership. Do not change
    # global Git trust settings or prevent benchmarking over optional metadata.
    return result.stdout.strip() if result.returncode == 0 else None


def summarize(runs):
    summary = {}
    for name in sorted({r['case'] for r in runs}):
        group = [r for r in runs if r['case'] == name]
        valid = [r for r in group if 'actual_evaluations' in r]
        summary[name] = {"runs": len(group), "successful_runs": sum(r.get('success', False) for r in group),
                         "held_out_successes": sum(r.get('held_out_success', False) for r in group),
                         "failed_processes_or_reports": len(group) - len(valid)}
        n = len(group)
        proportion = summary[name]['successful_runs'] / n
        z = 1.959963984540054
        center = (proportion + z*z/(2*n)) / (1 + z*z/n)
        radius = z * math.sqrt(proportion*(1-proportion)/n + z*z/(4*n*n)) / (1 + z*z/n)
        summary[name]['success_rate_wilson_95'] = [max(0.0, center-radius), min(1.0, center+radius)]
        for key in ('actual_evaluations', 'process_wall_seconds'):
            values = [r[key] for r in group if key in r]
            summary[name][key] = {"median": statistics.median(values), "min": min(values), "max": max(values)} if values else None
        coefficients = [r['raw_champion'].get('max_coefficient_error') for r in valid if r['raw_champion']]
        coefficients = [v for v in coefficients if v is not None]
        summary[name]['max_coefficient_error'] = max(coefficients) if coefficients else None
    return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--petta-main', type=Path, required=True)
    parser.add_argument('--swipl', default='swipl')
    parser.add_argument('--petta-commit', help='runtime revision, if Git cannot inspect the read-only runtime checkout')
    parser.add_argument('--manifest', type=Path, default=FIXTURES / 'baseline-manifest.json')
    parser.add_argument('--output', type=Path, required=True, help='new directory; existing paths are never overwritten')
    parser.add_argument('--seeds', help='comma-separated exploratory override; default is the recorded 30 seeds')
    parser.add_argument('--cases', help='comma-separated case names; default is all four')
    parser.add_argument('--timeout', type=float, default=120, help='per-process safety timeout, recorded as failure')
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text(encoding='utf-8'))
    if manifest['parameters']['optAlgo'] != 'hc':
        parser.error('this Step 8 runner qualifies HC only; extend after optimizer implementation')
    seeds = list(map(int, args.seeds.split(','))) if args.seeds else manifest['seeds']
    requested = set(args.cases.split(',')) if args.cases else {c['name'] for c in manifest['cases']}
    cases = [c for c in manifest['cases'] if c['name'] in requested]
    if not cases or requested != {c['name'] for c in cases} or not args.petta_main.is_file():
        parser.error('unknown/empty case selection or missing PeTTa main.pl')
    runtime_version = subprocess.check_output([args.swipl, '--version'], text=True).strip()
    metadata = {"created_utc": datetime.now(timezone.utc).isoformat(), "platform": platform.platform(),
                "processor": platform.processor(), "python": sys.version, "swipl": runtime_version,
                "petta_main": str(args.petta_main.resolve()), "manifest": manifest,
                "petta_commit": args.petta_commit or runtime_commit(args.petta_main),
                "petta_main_sha256": file_hash(args.petta_main),
                "manifest_sha256": file_hash(args.manifest), "source_sha256": source_hash(),
                "git_commit": subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
                "git_status": subprocess.check_output(['git', 'status', '--short'], cwd=ROOT, text=True),
                "seeds": seeds, "exploratory_override": bool(args.seeds or args.cases),
                "timing": "serial fresh processes; process time includes imports/CSV; trace elapsed starts at run cache reset; trace overhead included",
                "dataset_hashes": {p.name: file_hash(p) for p in sorted(FIXTURES.glob('*.csv'))}}
    args.output.mkdir(parents=True, exist_ok=False)
    (args.output / 'metadata.json').write_text(json.dumps(metadata, indent=2), encoding='utf-8')
    runs = []
    for case in cases:
        for seed in seeds:
            params = {**manifest['parameters'], 'seed': seed, 'continErrorType': case['loss'],
                      'inputFile': (FIXTURES / f"{case['name']}-train.csv").relative_to(ROOT).as_posix()}
            flags = [f"--{k}={str(v) if not isinstance(v, bool) else ('True' if v else 'False')}" for k, v in params.items()]
            command = [args.swipl, '--stack_limit=8g', '-q', '-s', str(args.petta_main.resolve()), '--', 'moses.metta', '-s', *flags]
            start = time.perf_counter()
            record = {"case": case['name'], "seed": seed, "command": command}
            try:
                process = subprocess.run(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                         text=True, encoding='utf-8', errors='replace', timeout=args.timeout)
                record['process_wall_seconds'] = time.perf_counter() - start
                stdout = process.stdout
                record['exit_code'] = process.returncode
                if process.returncode:
                    record['failure'] = f"runtime exit {process.returncode}"
                else:
                    try:
                        record.update(analyze(stdout, case, manifest))
                    except (ValueError, KeyError, TypeError, OverflowError) as error:
                        record['failure'] = str(error)
            except subprocess.TimeoutExpired as error:
                stdout = error.stdout or ''
                if isinstance(stdout, bytes):
                    stdout = stdout.decode('utf-8', errors='replace')
                record['failure'] = 'process safety timeout (not optimizer time-to-target)'
            record.setdefault('process_wall_seconds', time.perf_counter() - start)
            stem = f"{case['name']}-{seed}"
            (args.output / f'{stem}.stdout.txt').write_text(stdout, encoding='utf-8')
            (args.output / f'{stem}.json').write_text(json.dumps(record, indent=2, allow_nan=False), encoding='utf-8')
            runs.append(record)
            print(json.dumps({k: record.get(k) for k in ('case', 'seed', 'success', 'actual_evaluations', 'process_wall_seconds', 'failure')}), flush=True)
    (args.output / 'summary.json').write_text(json.dumps(summarize(runs), indent=2, allow_nan=False), encoding='utf-8')
    return 1 if any(r.get('failure') or not r.get('success') for r in runs) else 0


if __name__ == '__main__':
    raise SystemExit(main())
