# MOSES -- Meta-Optimizing Semantic Evolutionary Search

This repository is contains re implementation of the Moses algorithm found in the [asmoses](https://github.com/opencog/asmoses) repository in MeTTaLog. A brief introduction about what the Moses algorithm can be found below.

## Introduction

MOSES is a machine-learning tool; it is an "evolutionary program learner". It is capable of learning short programs that capture patterns in input datasets. For a given data input, the programs will roughly recreate the dataset on which they were trained.

MOSES has been used in several commercial applications, including the analysis of medical physician and patient clinical data, and in several different financial systems. It is also used by OpenCog to learn automated behaviors, movements and actions in response to perceptual stimulus of artificial-life virtual agents (i.e. pet-dog game avatars). Future plans including using it to learn behavioral programs that control real-world robots, via the OpenPsi implementation of Psi-theory and ROS nodes running on the OpenCog AtomSpace.

The term "evolutionary" means that MOSES uses genetic programming techniques to "evolve" new programs. Each program can be thought of as a tree (similar to a "decision tree", but allowing intermediate nodes to be any programming-language construct). Evolution proceeds by selecting one exemplar tree from a collection of reasonably fit individuals, and then making random alterations to the program tree, in an attempt to find an even fitter (more accurate) program.

It is derived from the ideas formulated in Moshe Looks' PhD thesis, "Competent Program Evolution", 2006 (Washington University, Missouri). Moshe is also one of the primary authors of this code.

A short example, from beginning to end, can be found in this Jupyter notebook (courtesy Robert Haas, for the Mevis plot package.)

There is also a considerable amount of information in the OpenCog wiki: <http://wiki.opencog.org/w/Meta-Optimizing_Semantic_Evolutionary_Search>

## Running the code

Install PeTTa first by following the instructions in the
[PeTTa](https://github.com/trueagi-io/PeTTa) repository, then clone this
repo and `cd` into it.

### Quick start

The repo root has a single entry file, `moses.metta`. It wires up every
module the pipeline needs, applies any `--name=value` flags you pass on
the command line, and runs MOSES. You just point PeTTa at it:

```sh
./PeTTa/run.sh moses.metta -s --problem=parity3
```

That's a complete run — solve the 3-bit parity problem with default
settings (50 generations, 1 deme, hill-climbing optimizer, no feature
selection).

### hyperparameters

`--help` prints every registered hyperparameter together with its
current value:

```sh
./PeTTa/run.sh moses.metta -s --help
```

Every value shown by `--help` can be overridden with `--name=value`.
A few common ones:

```sh
./PeTTa/run.sh moses.metta -s \
    --problem=mux3 \           # which problem to solve (parity3, parity4, majority3, majority5, mux3, mux6, disjunction3, …)
    --maxGen=30 \              # max generations
    --nDeme=2 \                # number of demes per expansion
    --fsAlgo=smd \             # feature-selection algorithm (None | smd | sim | inc | rd | mi | hc)
    --optAlgo=hc \             # optimizer (hc | univariate | boa | hboa; hc remains the default)
    --capCoef=80 \             # metapopulation cap coefficient
    --complexityRatio=2.5 \    # complexity/fitness trade-off
    --maxEvals=20000           # total actual new scorer-call budget
```

Flags can appear in any order; unrecognized ones are ignored.
The neutral `maxDist`, `minXoverNeighbors`, `revisit`,
`discardDominated`, and `diagnostics` settings configure the same search
pipeline for Boolean and action problems. `steps` is an evaluator horizon for
stateful action domains and is harmlessly unused by Boolean scorers.

If you run `./PeTTa/run.sh moses.metta -s` with **no** `--problem` (or
without an in-script `(set-param problem …)`), MOSES prints the help and
exits rather than silently running a default problem.

### Continuous affine regression

The explicit linear route uses the same MOSES loop, with HC by default:

```sh
./PeTTa/run.sh moses.metta -s --problem=linear --continDepth=2 --maxGen=2 --maxEvals=100
```

Without custom data, this runs a small in-memory `y = 2*x + 1` example. Load a
finite numeric CSV with an optional named target column:

```sh
./PeTTa/run.sh moses.metta -s --problem=linear --inputFile=data.csv --targetFeature=y
```

The default target is the last column. Headers are preserved exactly as string
labels; non-finite values, missing cells, ragged rows and duplicate/empty headers
are rejected. Boolean CSV parsing is unchanged on the Boolean route.
Alternatively, bind a column-major table in a `--domainFile` module:

```metta
!(set-param continTable (mkITable ((-1.0 0.0 1.0) (-1.0 1.0 3.0)) (x y)))
```

For an in-memory table, the target is the last column; do not also set `inputFile`.
Continuous options include `continStep`,
`continExpansion`, `continDepth`, `continErrorType` (`squared_error` or
`abs_error`), `continComplexityRatio`, and `continImprovementThreshold`.
`bestScore` is the raw-score target (default zero). Seed scoring consumes the
shared `maxEvals` allowance; zero allowance returns an empty result.
Nonlinear `sr` is enabled; BOA and hBOA are available as opt-ins.
See [the continuous contract](docs/continuous-contract.md) for scope and limits.
The [Step 8 HC baseline](docs/benchmarks/continuous-hc-baseline.md) records the
fixtures, explicit search settings, seeds, output quality and resource traces.

Select the new schema-aware population optimizer with `--optAlgo=univariate`:

```powershell
..\PeTTa\run.bat moses.metta -s --problem=linear --optAlgo=univariate --continDepth=2 --maxGen=10 --maxEvals=1000
```

See [the Step 9 optimizer](docs/univariate-optimizer.md) for settings, stopping
rules and tests. It is a clean implementation under `optimization/eda/`; the
legacy `optimization/univariate/` implementation and tests remain untouched.

Select Bayesian-network learning with `--optAlgo=boa`; keep `--optAlgo=hc` for
the default without dependency learning. See [BOA settings and implementation](docs/boa-optimizer.md)
and the [HC/univariate/BOA comparison](docs/benchmarks/continuous-boa-comparison.md).
BOA learns how to sample the current representation; it does not add nonlinear
operators or silently run HC on its offspring.

Select conditional decision trees and restricted tournament replacement with
`--optAlgo=hboa`. Use `--hboaLearnDependencies=False` for the no-dependency
control, or `--edaReplacement=rtr|elitist` to compare replacement policies.
See [hBOA settings and limitations](docs/hboa-optimizer.md) and the
[default-HC/hBOA comparison](docs/benchmarks/continuous-hboa-comparison.md).

### Nonlinear symbolic regression

`sr` uses nonlinear construction and, without a CSV/table, learns `x + x*x`:

```powershell
..\PeTTa\run.bat moses.metta -s --problem=sr --continDepth=2 --maxEvals=500 --optAlgo=hc
..\PeTTa\run.bat moses.metta -s --problem=sr --inputFile=tests/fixtures/continuous/sr-interaction-train.csv --continDepth=2 --maxEvals=500 --optAlgo=hboa
```

All four optimizers share the same scaffold, scoring and counted evaluation
budget. `continPolyDegree` (1–4, default 2) bounds new polynomial terms;
`continScaffoldDepth` (0–2, default 1) bounds recursive argument expansion.
The default vocabulary is polynomial-only. Opt into functions explicitly, e.g.
`"--continOperators=(c_add c_mul c_sin)"`; `c_log`, `c_exp` and `c_div` are also
supported. Division/log are not protected substitutions: invalid candidates fail
scoring. `linear` remains affine-only.

See [nonlinear scope, examples and tests](docs/nonlinear-continuous.md). This is
a bounded C++-inspired scaffold, not full C++ algebraic/search parity. The
[Step 13 exploratory comparison](docs/benchmarks/continuous-nonlinear-smoke.md)
separates harder-regression results from Step 14's full qualification.

### Running the test suite

```sh
python3 scripts/run-tests.py
```

Discovers every `*test.metta` file under the tree and runs them in
parallel via PeTTa.

## Contributing

Before you start contributing to this repository, make sure to read the [CONTRIBUTING.md](https://github.com/iCog-Labs-Dev/metta-moses/tree/main/.github/CONTRIBUTING.md) file from our repository.
