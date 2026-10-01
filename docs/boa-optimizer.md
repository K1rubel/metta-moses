# Step 10: bounded categorical BOA

`--optAlgo=boa` selects Bayesian-network sampling inside each deme. HC remains
the default; `--optAlgo=hc` disables BOA, and `--optAlgo=univariate` is the
population-only control. This is standalone BOA, not an HC hybrid. Step 11 now
adds [hBOA and shared RTR](hboa-optimizer.md); BOA retains elitist replacement by
default, with `--edaReplacement=rtr` available for ablation. Nonlinear work remains
separate: BOA does not introduce new symbolic operators.

```powershell
..\PeTTa\run.bat moses.metta -s --problem=linear --optAlgo=boa --inputFile=tests/fixtures/continuous/linear-train.csv --continDepth=2 --maxGen=10 --maxEvals=1000 --diagnostics=True
```

## Implementation and reference boundary

All learning and sampling is MeTTa under `optimization/boa/`:

- `graph.metta`: combined activation/learned graph, cycle checks, stable topology.
- `local-model.metta`: permitted contexts, sufficient statistics, BIC and CPTs.
- `structure-learning.metta`: bounded add-only greedy search and per-fit cache.
- `boa.metta`: topological sampling and the common optimizer/CLI adapter.

It uses the [Step 9 population engine](univariate-optimizer.md) unchanged in
selection, legal-prior initialization, exploration, elitist replacement,
canonical duplicate handling, scorer/cache accounting and champion retention.
The engine now passes the deadline to BOA and records fitting diagnostics.
The legacy `optimization/univariate/` files remain untouched.

The pinned C++ checkout's `moses/moses/eda/local_structure.h` supplies the
categorical-model/fixed-dependency reference and declares an empty univariate
learner and unfinished BDE learner. This implementation adds actual learned
cross-field edges. It is the plan's BIC-based BOA variant, **not a completed port
of a working C++ BOA learner**, and not hBOA. There are no edge removals/reversals,
warm starts, decision trees, RTR, cross-deme transfer or hidden local refinement.

## One generation, in detail

1. Tournament-select valid evaluated rows from the canonical population, with
   replacement. Intentional selection multiplicity remains in the data.
2. Turn each genotype into a model view. Active STOP is category `0`; inactive
   padding is the distinct parent category `-1`. Only active-child rows enter
   that child's sufficient statistics and local sample count `N_i`.
3. Fit each child's empty-learned-parent distribution. Mandatory preceding-trit
   edges determine activation and constrain the graph, but do not automatically
   condition the distribution on every predecessor's LEFT/RIGHT value.
4. Consider adding each missing parent edge, in child-index then parent-index
   order. Reject self-edges, cycles in the **combined** graph and parent-limit
   violations. A predecessor already required for activation may also become a
   learned parent if conditioning on its value improves BIC.
5. Enumerate feasible learned-parent contexts **conditional on the child being
   active**, including contexts absent from the sample. For a continuous slice,
   a STOP/inactive earlier parent forces all later observed parents inactive;
   adjacent non-STOP parents cannot be followed by an inactive parent, whereas
   a gap can contain an unobserved STOP. The child's own predecessors, when
   selected as parents, must be LEFT/RIGHT. Independent slices are combined.
   Incremental enumeration rejects oversized tables before creating their
   counts. It does not enumerate the entire genotype space.
6. Count child categories in each context and compute the maximum-likelihood
   log likelihood, without pseudocounts. Zero counts contribute zero:

   ```text
   LL_i = sum_context sum_value n(context,value) * ln(n(context,value)/n(context))
   k_i  = (# permitted active-child parent contexts) * (child cardinality - 1)
   BIC_i = LL_i - 0.5 * k_i * ln(N_i), for N_i > 0
   ```

   All permitted contexts count toward `k_i`, including unobserved contexts;
   impossible STOP combinations do not. With `N_i=0`, the score is explicitly
   zero, not `ln(0)`. Such a node supplies prior sampling, not evidence for an
   edge. This model-complexity penalty is unrelated to program complexity.
7. Cache the resulting counts, local score and table-limit rejections by
   `(child, sorted learned parents)` within this fit. Reuse them on later scans.
   Commit the legal edge with largest positive BIC gain. Gains must exceed
   `1e-10`; ties within that tolerance keep the first edge. Repeat until no
   improvement or a limit. A partially completed final scan may commit its best
   fully scored positive edge. Start from roots again next generation.
8. Each observed CPT context samples with `count + edaPseudocount` weights.
   An unobserved context explicitly backs off to the smoothed active-child
   marginal; a child with no active observations has a uniform prior.
9. Topologically order the combined graph, choosing the lowest ready index.
   Sample only active children. Inactive children emit canonical zero and
   consume no RNG draw. Reassemble output in original field-index order. The
   existing `edaExploration` mixture can instead draw from the legal prior.
10. Score offspring through the shared service, stop at the raw target/resource
    boundary, retain the best parents plus offspring, and refit on the next
    selected population. Model fitting never consumes scorer-call allowance,
    but **does** consume wall time.

For example, parents consisting of both trits of one depth-2 coefficient have
seven feasible model contexts: `(0,-1)`, `(1,0)`, `(1,1)`, `(1,2)`, `(2,0)`,
`(2,1)`, `(2,2)`. A separate binary child therefore has seven free parameters,
not nine, sixteen, or merely the number of contexts observed in this generation.

Greedy single-edge addition can miss pure XOR-like dependencies whose first
edge has no positive gain. Small selected samples, truncation selection, noisy
counts and fitting costs can also erase any benefit. Learned trit dependencies
are not evidence of causal feature interactions or improved generalization.

## Limits and diagnostics

| Parameter | Default | Per-fit meaning |
| --- | ---: | --- |
| `boaMaxParents` | 2 | Learned parents per child; fixed activation edges excluded |
| `boaMaxTableCells` | 256 | Permitted contexts × child cardinality, per node |
| `boaMaxIterations` | 16 | Maximum committed edge additions |
| `boaMaxScoreCalls` | 256 | Candidate local fits/table checks, in addition to mandatory roots |
| `boaFitTimeLimitSec` | 10.0 | Finite nonnegative fit-time allowance |

Parent/iteration/score limits allow zero; the cell limit must be positive.
All counts must be integers. Root cardinalities must fit the cell cap or the
adapter returns an error. EDA settings are validated as in Step 9. Fit time is
the earlier of the per-fit deadline and the remaining optimizer deadline.
Deadline checks are **cooperative between edge candidates**, not interrupts:
mandatory root fitting, a single local fit, topology and reporting can overrun
the timestamp. A zero fit allowance still constructs the root model but learns
no edges. A zero *optimizer* allowance performs no scoring/fitting.

`ModelFitDiagnostics` reports inclusive fit seconds, learned edges, free
parameters, CPT cells, additions, local fits (including roots), score-cache hits
and fitting stop reason. Univariate also reports fit seconds for the comparison.
`OptimizerDiagnostics.modelSize` is the maximum BOA free-parameter count fitted
in that deme; it is zero if no fit ran. It is **not an edge count**. HC/univariate
retain their existing zero value; use the explicit per-fit edge statistic when
comparing dependency learning. Population and continuous evaluation traces keep
their Step 9 meanings. No new global RNG or model state is introduced.

## Tests and comparison

```powershell
..\PeTTa\run.bat optimization/boa/tests/boa-test.metta -s
..\PeTTa\run.bat moses/tests/boa-pipeline-test.metta -s
python -m unittest discover -s scripts/tests -v
```

The model/boundary suite has 67 assertions; the pipeline suite has 27. They cover
dependent/independent controls, inactive-parent versus active-STOP counts,
permitted-context penalties, unseen/empty contexts, graph cycles including
activation edges, deterministic topology/sampling, legal vectors, heterogeneous
cardinalities, cached local fits, limits, scorer budgets, replay, explicit affine
winners and held-out errors, Boolean AND, and the action merge path.

See the [Step 10 comparison](benchmarks/continuous-boa-comparison.md) for measured
quality and efficiency. The immutable Step 8 artifacts are not replaced; HC is
rerun with the same source as both population optimizers. Full nonlinear and
equal-time qualification remains later work; see Step 11 for the
initial hBOA/RTR and fixed-representation diagnostic comparison.

The frozen run comprises 540 processes. All 360 affine runs have zero held-out
error, but BOA does not show a general efficiency gain. Fifteen Boolean exports
fail the recorder's prediction-error check because of existing worst-score
conventions for the initial `true` seed/root empty `AND`; the report preserves
and diagnoses these failures. This is not a clean Boolean-export qualification.
