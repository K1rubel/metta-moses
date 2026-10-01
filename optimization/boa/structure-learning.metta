;; Bounded, add-only greedy BIC search, freshly initialized each generation.
;; Ties within 1e-10 keep the first candidate (child ascending, then parent).
;; Fixed activation edges constrain cycles/order but incur no learned-parent
;; slots or free probabilities: activation itself is deterministic.
;; Constructs a BOA configuration record from global parameters.
;;   Returns: mkBOAConfig containing parent limits, table cell limits, iterations, score calls, and timeout.
(= (boaConfigured)
   (mkBOAConfig (param boaMaxParents) (param boaMaxTableCells)
     (param boaMaxIterations) (param boaMaxScoreCalls) (param boaFitTimeLimitSec)))

;; Validates that BOA configuration arguments satisfy domain and type bounds.
;;   $cfg: Candidate mkBOAConfig record.
;;   Returns: True if all fields are valid nonnegative/positive values, False otherwise.
(= (boaConfigValid $cfg)
   (case $cfg
     (((mkBOAConfig $parents $cells $iterations $scores $seconds)
       (if (all ((continNatural $parents) (edaPositiveInt $cells)
                 (continNatural $iterations) (continNatural $scores) (optimizerFiniteNumber $seconds)))
         (>= $seconds 0) False)) ($bad False))))

;; Calculates the effective timestamp deadline for model fitting.
;;   $outer: Outer optimizer deadline (-1 if none).
;;   $seconds: Maximum seconds allocated to local model fitting.
;;   Returns: Minimum timestamp of outer and local deadlines.
(= (boaDeadline $outer $seconds)
   (let $local (+ (candidateNow) $seconds) (if (< $outer 0) $local (min $outer $local))))

;; Extracts the learned parent lists from the current collection of local nodes.
;;   $nodes: List of mkBOANode records.
;;   Returns: Graph represented as a list of parent lists indexed by child coordinate.
(= (boaLearnedGraph $nodes) (map-atom $nodes $node (boaNodeParents $node)))

;; Searches the local model cache for an existing CPT fit for a child and parent set.
;;   $entries: List of mkBOACached entries.
;;   $child: Target child coordinate index.
;;   $parents: Sorted parent coordinate indices.
;;   Returns: Matching cached entries list.
(= (boaCacheLookup $entries $child $parents)
   (filter-atom $entries (mkBOACached $i $ps $node) (and (== $i $child) (== $ps $parents))))

;; Cache includes sufficient statistics/CPT and BIC, and table-limit rejections.
;; Candidate score calls are bounded separately from the mandatory root fit.
;; Evaluates or retrieves from cache a local conditional distribution and its BIC score.
;;   $fields: Full list of schema fields.
;;   $views: Population model views for selected candidates.
;;   $child: Child coordinate index.
;;   $parents: Sorted list of proposed parent coordinate indices.
;;   $alpha: Smoothing pseudocount.
;;   $maxCells: Upper threshold on CPT table size.
;;   (mkBOACache $entries $calls $hits): Model fit memoization cache.
;;   Returns: Tuple ($node $nextCache) with updated cache stats.
(= (boaCachedLocal $fields $views $child $parents $alpha $maxCells
                    (mkBOACache $entries $calls $hits))
   (case (boaCacheLookup $entries $child $parents)
     ((((mkBOACached $i $ps $node)) ($node (mkBOACache $entries $calls (+ $hits 1))))
      ($miss
       (let* (($contexts (boaContexts $fields (List.getByIdx $fields $child) $parents $maxCells))
              ($node (if (== $contexts boaTooLarge) boaTooLarge
                       (boaFitLocal $fields $views $child $parents $alpha $contexts))))
         ($node (mkBOACache (cons (mkBOACached $child $parents $node) $entries) (+ $calls 1) $hits)))))))

;; Scans all legal child-parent edge additions in deterministic lexicographical order.
;;   $fields: Full list of schema fields.
;;   $views: Selected candidate model views.
;;   $fixed: Fixed activation dependency graph.
;;   $nodes: Current list of local model nodes.
;;   $alpha: Dirichlet pseudocount.
;;   $cfg: BOA configuration parameters.
;;   $deadline: Cutoff timestamp for fitting.
;;   $child: Current child coordinate index in traversal.
;;   $parent: Current parent coordinate index in traversal.
;;   $cache: Current local model memoization cache.
;;   $best: Best positive BIC edge change found so far.
;;   Returns: Tuple ($best $cache $reason).
(= (boaScan $fields $views $fixed $nodes $alpha $cfg $deadline $child $parent $cache $best)
   (let* (((mkBOAConfig $maxParents $maxCells $maxIterations $maxScores $seconds) $cfg)
          ((mkBOACache $entries $calls $hits) $cache)
          ($size (List.length $fields)))
     (if (candidateDeadlineReached $deadline) ($best $cache fitTime)
       (if (>= $child $size) ($best $cache fitConverged)
         (if (>= $calls $maxScores) ($best $cache fitScoreLimit)
           (if (>= $parent $size)
             (boaScan $fields $views $fixed $nodes $alpha $cfg $deadline (+ $child 1) 0 $cache $best)
             (let* (($old (List.getByIdx $nodes $child)) ($parents (boaNodeParents $old))
                    ($legal (and (< (List.length $parents) $maxParents)
                              (boaEdgeLegal $fixed (boaLearnedGraph $nodes) $parent $child))))
               (if (not $legal)
                 (boaScan $fields $views $fixed $nodes $alpha $cfg $deadline $child (+ $parent 1) $cache $best)
                 (let* ((($node $nextCache) (boaCachedLocal $fields $views $child (List.insert $parent $parents)
                                              $alpha $maxCells $cache))
                        ($nextBest (if (== $node boaTooLarge) $best
                           (let* (($gain (- (boaNodeScore $node) (boaNodeScore $old)))
                                  ($bestGain (case $best ((() 0.0) ((mkBOAEdge $c $p $n $g) $g)))))
                             (if (> $gain (+ $bestGain 0.0000000001)) (mkBOAEdge $child $parent $node $gain) $best)))))
                   (boaScan $fields $views $fixed $nodes $alpha $cfg $deadline $child (+ $parent 1) $nextCache $nextBest))))))))))

;; Iteratively adds the best legal directed edge with positive BIC gain until convergence or bounds.
;;   $fields: Full list of schema fields.
;;   $views: Selected candidate model views.
;;   $fixed: Fixed activation graph.
;;   $nodes: Current list of local model nodes.
;;   $alpha: Dirichlet pseudocount.
;;   $cfg: BOA configuration parameters.
;;   $deadline: Cutoff timestamp for fitting.
;;   $iterations: Completed iteration count.
;;   $cache: Current local model memoization cache.
;;   Returns: Tuple ($nodes $cache $iterations $reason).
(= (boaSearch $fields $views $fixed $nodes $alpha $cfg $deadline $iterations $cache)
   (let (mkBOAConfig $maxParents $maxCells $maxIterations $maxScores $seconds) $cfg
     (if (>= $iterations $maxIterations) ($nodes $cache $iterations fitIterationLimit)
       (let ($best $nextCache $reason)
            (boaScan $fields $views $fixed $nodes $alpha $cfg $deadline 0 0 $cache ())
         (case $best
           ((() ($nodes $nextCache $iterations $reason))
            ((mkBOAEdge $child $parent $node $gain)
             (let $nextNodes (List.replaceAt $nodes $child $node)
               (if (== $reason fitConverged)
                 (boaSearch $fields $views $fixed $nextNodes $alpha $cfg $deadline (+ $iterations 1) $nextCache)
                 ($nextNodes $nextCache (+ $iterations 1) $reason))))))))))

;; Fits a complete Bayesian network (DAG + CPTs) to selected population instances.
;;   $schema: Field schema of the problem representation.
;;   $selected: List of selected candidate rows.
;;   $alpha: Dirichlet pseudocount for smoothing.
;;   $cfg: BOA configuration parameters.
;;   $outerDeadline: Optimizer global time deadline.
;;   Returns: mkBOAModel containing learned nodes, topological order, alpha, and fit statistics.
(= (boaFit $schema $selected $alpha $cfg $outerDeadline)
   (let* (($started (candidateNow))
          ((mkBOAConfig $maxParents $maxCells $maxIterations $maxScores $seconds) $cfg)
          ($deadline (boaDeadline $outerDeadline $seconds))
          ($fields (schemaFields $schema))
          ($views (map-atom $selected $row (instanceModelView $schema (candidateInstance $row))))
          ($fixed (boaFixedGraph $fields))
          ($roots (map-atom $fields $field (boaFitLocal $fields $views (fieldIndex $field) () $alpha (()))))
          ($cache (mkBOACache (map-atom $roots $node (mkBOACached
                    (let (mkBOANode $i $ps $t $f $s $k $n) $node $i) () $node)) 0 0))
          (($nodes (mkBOACache $entries $calls $hits) $iterations $reason)
            (boaSearch $fields $views $fixed $roots $alpha $cfg $deadline 0 $cache))
          ($order (boaTopological (boaCombined $fixed (boaLearnedGraph $nodes))))
          ($elapsed (- (candidateNow) $started))
          ($edges (List.sum (map-atom $nodes $node (List.length (boaNodeParents $node)))))
          ($parameters (List.sum (map-atom $nodes $node (boaNodeParameters $node))))
          ($cells (List.sum (map-atom $nodes $node (boaNodeCells $node)))))
     (mkBOAModel $nodes $order $alpha
       (mkBOAFitStats $elapsed $edges $parameters $cells $iterations (+ (List.length $fields) $calls) $hits $reason))))
