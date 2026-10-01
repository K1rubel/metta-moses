The implementations of **BOA (Bayesian Optimization Algorithm)** and **hBOA (hierarchical Bayesian Optimization Algorithm)** in `metta-moses` are built on a shared, modular **Estimation of Distribution Algorithm (EDA)** lifecycle, while maintaining distinct approaches to probabilistic modeling and structure learning.

---

### Architectural Overview

```
                          +----------------------------------------------+
                          |   Optimizer Entry Point                      |
                          |   (boaOptimizer / hboaOptimizer)            |
                          +----------------------------------------------+
                                                 |
                                                 v
                          +----------------------------------------------+
                          |   Shared EDA Framework (edaStart)            |
                          |   - Context & Schema Extraction              |
                          |   - Initial Evaluation & Seed Ingestion      |
                          |   - Uniform Random Refill to Population Size |
                          +----------------------------------------------+
                                                 |
                                                 v
                          +----------------------------------------------+
                          |         GENERATIONAL EVOLUTIONARY LOOP       |
+------------------------>|              (edaGeneration)                 |<-------------------------+
|                         +----------------------------------------------+                          |
|                                                |                                                  |
|                        [Resource / Termination Checks (edaResourceStop)]                          |
|                                                |                                                  |
|                                                v                                                  |
|                         +----------------------------------------------+                          |
|                         |  1. Tournament Selection (edaSelect)         |                          |
|                         +----------------------------------------------+                          |
|                                                |                                                  |
|                                                v                                                  |
|                         +----------------------------------------------+                          |
|                         |  2. Probabilistic Model Fitting              |                          |
|                         |     (edaFitTimed via Fit Callback)           |                          |
|                         +----------------------------------------------+                          |
|                                /                                \                                 |
|                               /                                  \                                |
|        +-----------------------------------+    +------------------------------------+            |
|        | BOA: Tabular CPT Model            |    | hBOA: Decision Tree Model          |            |
|        | - Bounded greedy edge addition    |    | - Decision tree local structures   |            |
|        | - Full context tables (CPTs)      |    | - Context-specific leaf splits     |            |
|        | - Table cell cap & CPT cache      |    | - Minimum support constraints      |            |
|        +-----------------------------------+    +------------------------------------+            |
|                               \                                  /                                |
|                                \                                /                                 |
|                                                v                                                  |
|                         +----------------------------------------------+                          |
|                         |  3. Offspring Generation                     |                          |
|                         |     (edaFill -> Sampling Callback)           |                          |
|                         |     - Topological DAG traversal              |                          |
|                         |     - Inactive coordinate masking            |                          |
|                         |     - Exploration rate injection             |                          |
|                         +----------------------------------------------+                          |
|                                                |                                                  |
|                                                v                                                  |
|                         +----------------------------------------------+                          |
|                         |  4. Candidate Evaluation & Deduplication     |                          |
|                         |     (edaEvaluate -> Scorer)                  |                          |
|                         +----------------------------------------------+                          |
|                                                |                                                  |
|                                                v                                                  |
|                         +----------------------------------------------+                          |
|                         |  5. Population Replacement                   |                          |
|                         |     - Elitist Truncation (BOA default)       |                          |
|                         |     - Restricted Tournament Replacement RTR  |                          |
|                         |       (hBOA default: preserves diversity)    |                          |
|                         +----------------------------------------------+                          |
|                                                |                                                  |
+------------------------------------------------+--------------------------------------------------+
                                                 |
                                    [Termination Triggered]
                                                 |
                                                 v
                          +----------------------------------------------+
                          |   Result Assembly & Deme Packaging           |
                          |   (edaResult)                                |
                          +----------------------------------------------+
```

---

### Stage 1: Entry Point & Initialization

#### 1.1 Dispatch and Validation
The optimizers expose a unified 6-argument signature conforming to the MOSES optimizer contract:
- BOA: [`configuredBOAOptimizer`](file:///C:/Users/KirA/Desktop/iCog/metta-moses/optimization/boa/boa.metta#L22-L25) / [`boaOptimizer`](file:///C:/Users/KirA/Desktop/iCog/metta-moses/optimization/boa/boa.metta#L26-L33)
- hBOA: [`configuredHBOAOptimizer`](file:///C:/Users/KirA/Desktop/iCog/metta-moses/optimization/hboa/hboa.metta#L19-L22) / [`hboaOptimizer`](file:///C:/Users/KirA/Desktop/iCog/metta-moses/optimization/hboa/hboa.metta#L23-L26)

Before execution begins:
1. **Configuration Validation**: Checks parameter types and boundary bounds via [`edaConfigValid`](file:///C:/Users/KirA/Desktop/iCog/metta-moses/optimization/eda/population.metta#L12-L23), [`boaConfigValid`](file:///C:/Users/KirA/Desktop/iCog/metta-moses/optimization/boa/structure-learning.metta#L9-L17), or [`hboaConfigValid`](file:///C:/Users/KirA/Desktop/iCog/metta-moses/optimization/hboa/structure-learning.metta#L9-L17).
2. **Context & Schema Extraction**: [`edaContext`](file:///C:/Users/KirA/Desktop/iCog/metta-moses/optimization/eda/population.metta#L24-L30) unpacks continuous, Boolean, or action scoring contexts, and [`edaSchema`](file:///C:/Users/KirA/Desktop/iCog/metta-moses/optimization/eda/population.metta#L31-L36) builds the field schema detailing knob indexes, cardinalities, continuous slice offsets, and activation relationships.
3. **Table Check (BOA only)**: BOA asserts that no individual knob's cardinality exceeds `boaMaxTableCells`.

#### 1.2 Initial Population Seeding (`edaStart` & `edaFill`)
Inside [`edaStart`](file:///C:/Users/KirA/Desktop/iCog/metta-moses/optimization/eda/population.metta#L244-L269):
1. **Seeding Existing Individuals**: [`edaInitialRows`](file:///C:/Users/KirA/Desktop/iCog/metta-moses/optimization/eda/population.metta#L167-L176) takes the initial exemplar and any incoming deme candidates, runs them through [`canonicalizeInstance`](file:///C:/Users/KirA/Desktop/iCog/metta-moses/optimization/eda/population.metta#L173), and evaluates them with [`edaEvaluate`](file:///C:/Users/KirA/Desktop/iCog/metta-moses/optimization/eda/population.metta#L146-L161).
2. **Population Refill**: If the valid seeded count is smaller than `edaPopulationSize`, [`edaFill`](file:///C:/Users/KirA/Desktop/iCog/metta-moses/optimization/eda/population.metta#L180-L192) samples legal uniform instances via [`sampleLegalInstance`](file:///C:/Users/KirA/Desktop/iCog/metta-moses/optimization/legal-instance-sampling.metta) until the population reaches capacity.
3. **Initial Ranking**: Evaluated candidates are ranked using [`edaBetter`](file:///C:/Users/KirA/Desktop/iCog/metta-moses/optimization/eda/population.metta#L40-L44) (primary: higher penalized score; secondary: lower complexity). The top `edaPopulationSize` individuals form generation 1.

---

### Stage 2: The Evolutionary Loop (`edaGeneration`)

Each generation executes in [`edaGenerationSized`](file:///C:/Users/KirA/Desktop/iCog/metta-moses/optimization/eda/population.metta#L223-L242):

1. **Stop Criteria Check ([`edaResourceStop`](file:///C:/Users/KirA/Desktop/iCog/metta-moses/optimization/eda/population.metta#L126-L132))**:
   - `stopTargetReached`: An archive individual meets/exceeds the optimization target.
   - `stopBudgetExhausted`: Scorer evaluations exceed `maxEvals`.
   - `stopTimeExhausted`: Wall-clock deadline reached.
   - `stopProposalsExhausted`: Proposal counter reached.
   - `stopExhaustedSpace`: All valid genotypes in finite space have been evaluated.
   - `stopGenerationsExhausted`: Generation count reached `limitsMaxGenerations`.
   - `stopStagnation`: Generation count without best-fitness improvement reaches `edaStagnationGenerations`.
2. **Selection ([`edaSelect`](file:///C:/Users/KirA/Desktop/iCog/metta-moses/optimization/eda/population.metta#L102-L106))**:
   - Runs `edaSelectionSize` rounds of tournament selection ([`edaTournament`](file:///C:/Users/KirA/Desktop/iCog/metta-moses/optimization/eda/population.metta#L97-L101)) of size `edaTournamentSize`.
   - Selected individuals serve as the empirical dataset for model building.

---

### Stage 3: Structure Learning and Model Fitting

This is the central algorithmic divergence between BOA and hBOA.

#### 3.1 Common Representational Constraints
Both algorithms work with canonical representation schemas:
- **Active vs. Inactive Coordinates**: MOSES uses hierarchical and variable-length tree representations (e.g. continuous slices). An inactive node is encoded as `-1` in the model view ([`boaObservation`](file:///C:/Users/KirA/Desktop/iCog/metta-moses/optimization/boa/local-model.metta#L5-L7)). Inactive children never contribute observations.
- **Fixed Activation DAG**: If coordinate $A$ determines whether coordinate $B$ is active, an immutable directed edge $A \to B$ exists in [`boaFixedGraph`](file:///C:/Users/KirA/Desktop/iCog/metta-moses/optimization/boa/graph.metta#L3).
- **Acyclicity Check**: Before evaluating an edge $U \to V$, [`boaEdgeLegal`](file:///C:/Users/KirA/Desktop/iCog/metta-moses/optimization/boa/graph.metta#L19-L21) traverses ancestors in the combined fixed + learned graph ([`boaAncestorsReach`](file:///C:/Users/KirA/Desktop/iCog/metta-moses/optimization/boa/graph.metta#L8-L17)) to prevent cycles.

---

#### 3.2 BOA Architecture: Tabular Conditional Probability Tables (CPT)
Implemented in [`optimization/boa/structure-learning.metta`](file:///C:/Users/KirA/Desktop/iCog/metta-moses/optimization/boa/structure-learning.metta) and [`optimization/boa/local-model.metta`](file:///C:/Users/KirA/Desktop/iCog/metta-moses/optimization/boa/local-model.metta).

```
BOA Node Structure:
(mkBOANode $childIndex $parentsList $cptTable $fallbackMarginal $bicScore $parameters $activeCount)
```

1. **Root Models ([`boaFitLocal`](file:///C:/Users/KirA/Desktop/iCog/metta-moses/optimization/boa/local-model.metta#L58-L71))**:
   - Each variable begins with no learned parents ($\text{parents} = ()$).
   - Counts active categorical occurrences and computes base BIC score:
     $$\text{BIC} = \text{LogLikelihood} - 0.5 \cdot (\text{cardinality} - 1) \cdot \ln(N_{\text{active}})$$
2. **Greedy Edge Addition ([`boaSearch`](file:///C:/Users/KirA/Desktop/iCog/metta-moses/optimization/boa/structure-learning.metta#L51-L62) & [`boaScan`](file:///C:/Users/KirA/Desktop/iCog/metta-moses/optimization/boa/structure-learning.metta#L30-L50))**:
   - Iterates through all possible directed candidate edges $\text{parent} \to \text{child}$.
   - **Table Feasibility**: [`boaContexts`](file:///C:/Users/KirA/Desktop/iCog/metta-moses/optimization/boa/local-model.metta#L47-L50) checks if the Cartesian product of parent values exceeds `boaMaxTableCells`. If exceeded, the edge is rejected as `boaTooLarge`.
   - **Local Score Cache**: Candidate local models are cached by `(child, sorted_parents)` in [`boaCachedLocal`](file:///C:/Users/KirA/Desktop/iCog/metta-moses/optimization/boa/structure-learning.metta#L21-L29).
   - **Gain Computation**:
     $$\Delta\text{BIC} = \text{Score}(child \mid parents \cup \{parent\}) - \text{Score}(child \mid parents)$$
3. **Commit**: The legal edge with the highest positive gain exceeding $+10^{-10}$ is committed. The parent list is updated, and the search repeats for up to `boaMaxIterations` iterations or until `boaMaxScoreCalls` is hit.
4. **Topological Order**: [`boaTopological`](file:///C:/Users/KirA/Desktop/iCog/metta-moses/optimization/boa/graph.metta#L30-L31) performs a Kahn-style topological sort over the merged fixed and learned DAG.

---

#### 3.3 hBOA Architecture: Local Decision Trees
Implemented in [`optimization/hboa/structure-learning.metta`](file:///C:/Users/KirA/Desktop/iCog/metta-moses/optimization/hboa/structure-learning.metta) and [`optimization/hboa/local-structure.metta`](file:///C:/Users/KirA/Desktop/iCog/metta-moses/optimization/hboa/local-structure.metta).

Instead of exponential CPTs, hBOA represents the conditional distribution of each coordinate using a **Binary Decision Tree**, enabling context-specific independencies:

```
hBOA Local Structure:
- Leaf:  (mkHLeaf $counts)
- Split: (mkHSplit $parentIndex $categoryValue $yesSubtree $noSubtree)
- Node:  (mkHNode $childIndex $parentsList $decisionTree $activeCount)
```

1. **Root Trees ([`hboaRoot`](file:///C:/Users/KirA/Desktop/iCog/metta-moses/optimization/hboa/local-structure.metta#L28-L31))**:
   - Every variable starts with a single-leaf tree `(mkHLeaf $counts)` storing the unsmoothed active frequency vector.
2. **Candidate Split Generation ([`hboaCandidates`](file:///C:/Users/KirA/Desktop/iCog/metta-moses/optimization/hboa/structure-learning.metta#L24-L38))**:
   - Gathers all leaves in all trees via [`hboaLeaves`](file:///C:/Users/KirA/Desktop/iCog/metta-moses/optimization/hboa/local-structure.metta#L7-L12).
   - A leaf is eligible for splitting only if:
     - Total tree leaves $< \text{hboaMaxLeaves}$
     - Path depth $< \text{hboaMaxDepth}$
     - Leaf sample count $\ge 2 \cdot \text{hboaMinSupport}$
   - Generates candidate queries: testing whether parent variable $P == \text{value}$.
3. **Split Evaluation & BIC Delta ([`hboaSplit`](file:///C:/Users/KirA/Desktop/iCog/metta-moses/optimization/hboa/local-structure.metta#L35-L43))**:
   - Active views arriving at the leaf path are partitioned:
     - `yes`: $\text{observation}(P) == \text{value}$
     - `no`: $\text{observation}(P) \ne \text{value}$
   - If either $|yes| < \text{hboaMinSupport}$ or $|no| < \text{hboaMinSupport}$, the split is discarded.
   - Computes local BIC delta:
     $$\Delta\text{BIC} = \left[\text{LL}(counts_{yes}) + \text{LL}(counts_{no}) - \text{LL}(counts_{leaf})\right] - 0.5 \cdot (\text{cardinality} - 1) \cdot \ln(N_{\text{child\_active}})$$
4. **Committing Splits ([`hboaSearch`](file:///C:/Users/KirA/Desktop/iCog/metta-moses/optimization/hboa/structure-learning.metta#L58-L72))**:
   - The candidate split across all trees that produces the maximal positive $\Delta\text{BIC}$ is selected.
   - [`hboaReplaceLeaf`](file:///C:/Users/KirA/Desktop/iCog/metta-moses/optimization/hboa/local-structure.metta#L16-L22) replaces the leaf in the target tree with `(mkHSplit $p $v (mkHLeaf $yc) (mkHLeaf $nc))`.
   - The parent index is unioned into that node's parent set.
   - Iterates until convergence, score limit, or iteration limit.

---

### Stage 4: Offspring Generation & Conditional Sampling

Once the DAG and local models are fitted, offspring are generated in [`edaFill`](file:///C:/Users/KirA/Desktop/iCog/metta-moses/optimization/eda/population.metta#L180-L192):

1. **Exploration Injection**: With probability `edaExploration`, sampling falls back to uniform [`sampleLegalInstance`](file:///C:/Users/KirA/Desktop/iCog/metta-moses/optimization/legal-instance-sampling.metta), maintaining genetic variance.
2. **Topological Sampling**:
   - Sampling proceeds strictly along the topological ordering ($O_1, O_2, \dots, O_m$).
   - Before sampling coordinate $i$, its activation parents are checked:
     ```metta
     ($active (all (map-atom (fieldActivationParents $field) $p (> (List.getByIdx $values $p) 0))))
     ```
   - If inactive: coordinate is set to default `0` (`-1` in model view).
   - If active:
     - **In BOA ([`boaSampleOrder`](file:///C:/Users/KirA/Desktop/iCog/metta-moses/optimization/boa/boa.metta#L3-L16))**: Extracts parent values context, queries CPT. If the context was never seen in training, falls back to the Dirichlet-smoothed marginal (`fallback`).
     - **In hBOA ([`hboaSampleOrder`](file:///C:/Users/KirA/Desktop/iCog/metta-moses/optimization/hboa/hboa.metta#L2-L13))**: [`hboaWeights`](file:///C:/Users/KirA/Desktop/iCog/metta-moses/optimization/hboa/local-structure.metta#L23-L27) traverses the decision tree testing parent values until hitting a leaf, then adds pseudocount $\alpha$ (`edaPseudocount`) to active counts.
     - Selects the categorical value using roulette-wheel selection via [`edaChooseWeight`](file:///C:/Users/KirA/Desktop/iCog/metta-moses/optimization/eda/univariate-model.metta#L26-L31).
3. **Legal Sample Packaging**: Produces a valid, canonical `mkInst` candidate vector.

---

### Stage 5: Evaluation and Population Replacement

#### 5.1 Evaluation & Deduplication ([`edaEvaluate`](file:///C:/Users/KirA/Desktop/iCog/metta-moses/optimization/eda/population.metta#L146-L161))
- Evaluated genotypes are recorded in the `seen` set.
- Duplicate proposals bypass the objective function without consuming scorer calls (`cacheHits` increments).
- New unique candidates are batch-evaluated via domain scorers, and added to the cumulative `archive`.

#### 5.2 Replacement Policies ([`edaReplacementStep`](file:///C:/Users/KirA/Desktop/iCog/metta-moses/optimization/eda/population.metta#L84-L92))
Controlled by `edaReplacement` parameter:

| Policy | Mechanism | Used In |
|---|---|---|
| **Elitist Truncation** ([`edaReplace`](file:///C:/Users/KirA/Desktop/iCog/metta-moses/optimization/eda/population.metta#L51-L52)) | Merges current population and new offspring, sorts by [`edaBetter`](file:///C:/Users/KirA/Desktop/iCog/metta-moses/optimization/eda/population.metta#L40-L44), keeps top $N$. | Default for BOA (`auto` mode) |
| **Restricted Tournament Replacement (RTR)** ([`edaRTR`](file:///C:/Users/KirA/Desktop/iCog/metta-moses/optimization/eda/population.metta#L71-L81)) | For each offspring: samples a random window of `edaRTRWindow` individuals; finds the closest incumbent by Hamming distance ([`edaHamming`](file:///C:/Users/KirA/Desktop/iCog/metta-moses/optimization/eda/population.metta#L58-L60)); replaces it if and only if the offspring has better fitness. | Default for hBOA (`auto` mode) |

RTR explicitly combats **niching loss and premature diversity collapse**, which is critical when learning complex hierarchical Bayesian structures.

---

### Summary Comparison: BOA vs. hBOA

| Feature | BOA (`optimization/boa/`) | hBOA (`optimization/hboa/`) |
|---|---|---|
| **Local Model** | Tabular Conditional Probability Table (CPT) | Binary Decision Tree per variable |
| **Dependency Form** | Full parent interaction (coarse-grained) | Context-specific splits ($P == v$) |
| **Parameter Growth** | Exponential: $O(C_{\text{child}} \cdot \prod C_{\text{parents}})$ | Linear in number of tree leaves |
| **Safeguards** | `boaMaxTableCells` (discards full edges) | `hboaMinSupport` (prunes branch tests) |
| **Cache Mechanism** | Memoizes CPTs by `(child, parents)` | Replaces individual leaf subtrees directly |
| **Memory Bound** | Hard upper limit on table cells per node | Bounded tree depth (`hboaMaxDepth`) and leaf count (`hboaMaxLeaves`) |
| **Sampling Logic** | Flat CPT lookup with Dirichlet fallback | Decision-tree descent to leaf counts + pseudocount smoothing |
| **Default Replacement** | Elitist Truncation | Restricted Tournament Replacement (RTR) |
