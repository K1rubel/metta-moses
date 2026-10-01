# Step 11: bounded hBOA-style conditional trees and RTR

Select `--optAlgo=hboa`; HC remains the default. hBOA changes sampling within
the current deme, not its representation, evaluator, or outer MOSES loop.
It does not enable nonlinear terms or silently refine offspring with HC.

```powershell
..\PeTTa\run.bat moses.metta -s --problem=linear --optAlgo=hboa --continDepth=2 --maxGen=10 --maxEvals=1000 --diagnostics=True
```

## Learning and sampling

Implementation is MeTTa under `optimization/hboa/`: `local-structure.metta`
contains conditional trees/counts, `structure-learning.metta` fits them, and
`hboa.metta` samples them and implements the shared optimizer adapter. It reuses
BOA's graph utilities and the clean Step 9 population engine, not the legacy
univariate optimizer. This is a bounded greedy hBOA-style implementation, not a
claim to reproduce every operator in a particular reference hBOA package.

1. Select evaluated valid population rows using the shared seeded tournament.
   Repeated selected rows retain their multiplicity. Start fresh each generation.
2. Build one root distribution per raw field. Only active-child observations
   count. Active STOP is `0`; an inactive parent is the distinct category `-1`.
3. Each leaf holds categorical counts. Consider a binary test `parent == value`
   at each eligible leaf, with a yes and a no branch. Categories come from the
   schema, including inactivity where possible. Both branches need minimum
   support, so impossible/unobserved contexts do not create empty branches.
4. Check learned-parent bounds and cycles in the union of learned edges and
   mandatory continuous activation edges. A parent already used elsewhere in
   the tree can be tested again, without consuming another parent slot.
5. Score the split by its change in BIC. For child cardinality `r` and total
   active-child count `N`,

   ```text
   gain = LL(yes counts) + LL(no counts) - LL(old leaf counts)
          - 0.5 * (r - 1) * ln(N)
   LL(counts) = sum n_v * ln(n_v / sum(counts)), with zero terms omitted
   ```

   Counts are unsmoothed when learning. A split adds `r-1` free probabilities;
   total local free parameters are `leaves*(r-1)`. `N` is not the leaf support.
   No `ln(0)` is evaluated. This model penalty is separate from program complexity.
6. Commit the best positive legal split, requiring a gain over `1e-10`.
   Ties keep child index, leaf DFS (yes first), parent index, category order.
   Repeat under the bounds. A partially scanned final iteration may commit its
   best fully scored split. Candidate statistics are recomputed, not cached;
   diagnostics therefore report zero score-cache hits.
7. Sample fields in stable topological order of the combined graph. Follow each
   active child's tree using already sampled parent observations, then draw from
   `count + edaPseudocount`. No-data roots are uniform. An unobserved combination
   of parent values routes to an existing supported leaf. Inactive children
   emit zero without an RNG draw. The legal-prior exploration mixture is shared.
8. Evaluate canonical offspring through the shared counted scorer/cache, then
   apply RTR and refit on the next selected population. Models never cross demes.

For example, with independent binary `A,B` and `Y=A AND B`, a learned tree for
`Y` can test `A=0`: yes predicts zero; no tests `B=0`. This has three leaves and
three free probabilities, compared with four contexts in a full two-parent CPT.
The direct fixture pins that exact learned tree; this is learned context-specific
structure, not merely STOP activation logic.

Greedy positive single splits can miss pure XOR interactions whose first split
has no gain. Small selected samples and fit bounds can prevent learning useful
dependencies. This implementation does not merge leaves or do lookahead search.
Learning relationships between trits does not itself establish causal feature
relationships, better generalization, or faster search.

## Replacement and controls

`edaReplacement=auto` means RTR for hBOA and elitist replacement for BOA and
univariate. Set it explicitly to `rtr` or `elitist` to compare matched policies.
`edaRTRWindow=8` is the default.

For each offspring, draw a window of distinct population indices without
replacement, capped at population size. Find the incumbent with the smallest
Hamming distance over canonical raw vectors; inactive padding is zero, not a
separate distance category. Distance ties keep the first randomly drawn index.
Replace only for a higher penalized score, or equal score and lower complexity.
Exact score/complexity ties retain the incumbent. Process offspring sequentially.
The population is ranked again after replacement; its cap is unchanged.

The archive retains every valid evaluated genotype, including rejected offspring
and both raw and penalized champions. As with earlier EDA modes, the deme-wide
seen set suppresses repeated genotypes, including prior RTR rejects: they are not
reintroduced later. This finite-space/no-reconsideration policy differs from
unrestricted textbook resampling and is held fixed across the ablation arms.
Refill attempts are bounded. All replacement RNG draws are explicitly threaded.

- `--optAlgo=hc`: default optimizer; no learned dependency model.
- `--optAlgo=hboa`: learned trees plus RTR.
- `--optAlgo=hboa --hboaLearnDependencies=False`: no learned dependencies,
  with the same initialization, masking, alpha, exploration, selection and RTR.
  Its model sampling is exactly the shared univariate distribution/RNG stream.
- `--optAlgo=univariate --edaReplacement=rtr`: independent implementation control.
- `--optAlgo=boa --edaReplacement=rtr`: CPT model with matched replacement.
- `--optAlgo=hboa --edaReplacement=elitist`: tree model without RTR.

## Bounds and diagnostics

| Setting | Default | Scope |
| --- | ---: | --- |
| `hboaMaxParents` | 3 | Distinct learned parents per child |
| `hboaMaxDepth` | 3 | Tests along each root-to-leaf path |
| `hboaMaxLeaves` | 8 | Leaves per child |
| `hboaMinSupport` | 2 | Selected observations in each new branch |
| `hboaMaxIterations` | 16 | Committed splits per fit |
| `hboaMaxScoreCalls` | 256 | Candidate split/support checks, excluding roots |
| `hboaFitTimeLimitSec` | 10 | Cooperative per-fit time allowance |
| `hboaLearnDependencies` | True | Explicit dependency-learning switch |

Counts are integers; parents/depth/iterations/score calls may be zero, leaves
and support must be positive. Fit seconds are finite/nonnegative. Zero fit time
still builds roots but learns no splits. Deadlines use the earlier fit/optimizer
deadline and are checked between split evaluations. Root fitting, candidate-list
construction, one split, topology, and replacement are bounded operations but
can overrun a timestamp; this is not a hard real-time interrupt.

`ModelFitDiagnostics` reports time including roots/search/topology, learned edges,
free parameters, tree nodes/leaves, committed splits, local fits (roots plus
candidate checks), and stop reason. `modelSize` is the maximum free-parameter
count fitted in that deme (same unit as BOA), not the tree-node count.
`ReplacementDiagnostics` reports RTR offspring/acceptances/effective window.
Model fitting and replacement consume wall time, not scorer-call allowance.

```powershell
..\PeTTa\run.bat optimization/hboa/tests/hboa-test.metta -s
..\PeTTa\run.bat moses/tests/hboa-pipeline-test.metta -s
python -m unittest discover -s scripts/tests -v
```

The [Step 11 comparison](benchmarks/continuous-hboa-comparison.md) separates
affine held-out quality from fixed-deme trap/HIFF diagnostics. Equal-time,
nonlinear, noisy/generalization, and larger-scale qualification remain Step 14.
