;; Fresh, bounded, best-positive-split BIC search each generation.
;; Deterministic ties: child, leaf DFS (yes first), parent, category ascending.
;; Bounds apply per child (parents/depth/leaves/support) and per fit (scores,
;; committed splits/time). Counts include rejected support tests, not roots.
;; Constructs an hBOA configuration record from global parameters.
;;   Returns: mkHConfig containing tree depth, leaf limits, support, iterations, and timeout.
(= (hboaConfigured)
   (mkHConfig (param hboaMaxParents) (param hboaMaxDepth) (param hboaMaxLeaves)
     (param hboaMinSupport) (param hboaMaxIterations) (param hboaMaxScoreCalls)
     (param hboaFitTimeLimitSec) (param hboaLearnDependencies)))

;; Validates that hBOA configuration parameters conform to type and range bounds.
;;   $cfg: Candidate mkHConfig record.
;;   Returns: True if all fields are valid natural/positive numbers and booleans, False otherwise.
(= (hboaConfigValid $cfg)
   (case $cfg
     (((mkHConfig $parents $depth $leaves $support $iterations $scores $seconds $learn)
       (if (all ((continNatural $parents) (continNatural $depth) (edaPositiveInt $leaves)
                 (edaPositiveInt $support) (continNatural $iterations) (continNatural $scores)
                 (optimizerFiniteNumber $seconds) (or (== $learn True) (== $learn False))))
         (>= $seconds 0) 
         False)) 
     ($bad False))))

;; Checks whether adding a parent to an hBOA node obeys the max-parents limit and maintains DAG acyclicity.
;;   $fixed: Fixed structural activation graph.
;;   $graph: Current learned hBOA dependency graph.
;;   $parent: Proposed parent coordinate index.
;;   $child: Target child coordinate index.
;;   $maxParents: Maximum allowed parents per node.
;;   Returns: True if adding the parent is legal, False otherwise.
(= (hboaEdgeLegal $fixed $graph $parent $child $maxParents)
   (if (continContains $parent (List.getByIdx $graph $child)) True
     (and (< (List.length (List.getByIdx $graph $child)) $maxParents)
          (boaEdgeLegal $fixed $graph $parent $child))))

;; Candidate descriptors only; sufficient statistics are computed lazily under
;; the fit budget. Categories are schema-defined, never inferred cardinalities.
;; Generates candidate split descriptors across all variable decision trees.
;;   $fields: Full list of schema fields.
;;   $fixed: Fixed activation graph.
;;   $nodes: Current list of hBOA variable nodes.
;;   $cfg: hBOA configuration parameters.
;;   Returns: List of mkHCandidate records specifying child, path, counts, parent, and value.
(= (hboaCandidates $fields $fixed $nodes $cfg)
   (let* (((mkHConfig $maxParents $depth $leaves $support $iterations $scores $seconds $learn) $cfg)
          ($graph (hboaGraph $nodes)))
     (foldl-atom $nodes () $out (mkHNode $child $parents $tree $n)
       (let $paths (hboaLeaves $tree ())
         (if (or (>= (List.length $paths) $leaves) (< $n (* 2 $support))) $out
           (List.concat $out
             (foldl-atom $paths () $local ($path $counts)
               (if (or (>= (List.length $path) $depth) (< (List.sum $counts) (* 2 $support))) $local
                 (List.concat $local
                   (foldl-atom $fields () $tests $field
                     (if (hboaEdgeLegal $fixed $graph (fieldIndex $field) $child $maxParents)
                       (List.concat $tests
                         (map-atom (boaAllowedParentValues $field (List.getByIdx $fields $child)) $value
                           (mkHCandidate $child $path $counts (fieldIndex $field) $value))) $tests)))))))))))

;; Scans candidate splits, evaluating BIC gains lazily under the evaluation and time budget.
;;   $todo: List of remaining candidate split descriptors.
;;   $fields: Full list of schema fields.
;;   $views: Selected candidate model views.
;;   $nodes: Current list of hBOA variable nodes.
;;   $cfg: hBOA configuration parameters.
;;   $deadline: Cutoff timestamp for fitting.
;;   $calls: Cumulative score evaluations performed in scan.
;;   $best: Best candidate split with positive gain found so far.
;;   Returns: Tuple ($best $calls $reason).
(= (hboaScan $todo $fields $views $nodes $cfg $deadline $calls $best)
   (let (mkHConfig $parents $depth $leaves $support $iterations $maxScores $seconds $learn) $cfg
     (if (candidateDeadlineReached $deadline) ($best $calls fitTime)
       (case $todo
         ((() ($best $calls fitConverged))
          ((cons (mkHCandidate $child $path $counts $parent $value) $rest)
           (if (>= $calls $maxScores) ($best $calls fitScoreLimit)
             (let* (((mkHNode $i $ps $tree $n) (List.getByIdx $nodes $child))
                    ($active (filter-atom $views $v
                               (and (>= (boaObservation $v $child) 0) (hboaMatches $v $path))))
                    ($split (hboaSplit $active $child $parent $value
                              (fieldCardinality (List.getByIdx $fields $child)) $n $counts $support))
                    ($next (case $split
                      ((() $best)
                       (($replacement $gain)
                        (let $bestGain (case $best ((() 0.0) ((mkHChange $c $p $t $g) $g)))
                          (if (> $gain (+ $bestGain 0.0000000001))
                            (mkHChange $child $parent (hboaReplaceLeaf $tree $path $replacement) $gain) $best)))))))
               (hboaScan $rest $fields $views $nodes $cfg $deadline (+ $calls 1) $next)))))))))

;; Iteratively selects and commits the best positive BIC split across all trees.
;;   $fields: Full list of schema fields.
;;   $views: Selected candidate model views.
;;   $fixed: Fixed activation graph.
;;   $nodes: Current list of hBOA variable nodes.
;;   $cfg: hBOA configuration parameters.
;;   $deadline: Cutoff timestamp for fitting.
;;   $iterations: Completed split iteration count.
;;   $calls: Cumulative score evaluations.
;;   Returns: Tuple ($nodes $iterations $calls $reason).
(= (hboaSearch $fields $views $fixed $nodes $cfg $deadline $iterations $calls)
   (let (mkHConfig $parents $depth $leaves $support $maxIterations $scores $seconds $learn) $cfg
     (if (not $learn) ($nodes $iterations $calls fitDependenciesDisabled)
       (if (>= $iterations $maxIterations) ($nodes $iterations $calls fitIterationLimit)
         (let ($best $nextCalls $reason)
              (hboaScan (hboaCandidates $fields $fixed $nodes $cfg) $fields $views $nodes $cfg $deadline $calls ())
           (case $best
             ((() ($nodes $iterations $nextCalls $reason))
              ((mkHChange $child $parent $tree $gain)
               (let* (((mkHNode $i $ps $oldTree $n) (List.getByIdx $nodes $child))
                      ($next (List.replaceAt $nodes $child
                               (mkHNode $child (boaUnion $ps ($parent)) $tree $n))))
                 (if (== $reason fitConverged)
                   (hboaSearch $fields $views $fixed $next $cfg $deadline (+ $iterations 1) $nextCalls)
                   ($next (+ $iterations 1) $nextCalls $reason)))))))))))

;; Fits an hBOA model (decision trees and topological order) to selected population individuals.
;;   $schema: Field schema of the problem representation.
;;   $selected: List of selected candidate rows.
;;   $alpha: Dirichlet pseudocount for smoothing.
;;   $cfg: hBOA configuration parameters.
;;   $outerDeadline: Optimizer global time deadline.
;;   Returns: mkHBOAModel containing learned nodes, topological order, alpha, and fit statistics.
(= (hboaFit $schema $selected $alpha $cfg $outerDeadline)
   (let* (($started (candidateNow))
          ((mkHConfig $parents $depth $leaves $support $iterations $scores $seconds $learn) $cfg)
          ($deadline (boaDeadline $outerDeadline $seconds))
          ($fields (schemaFields $schema))
          ($views (map-atom $selected $row (instanceModelView $schema (candidateInstance $row))))
          ($fixed (boaFixedGraph $fields))
          ($roots (map-atom $fields $f (hboaRoot $fields $views (fieldIndex $f))))
          (($nodes $splits $calls $reason) (hboaSearch $fields $views $fixed $roots $cfg $deadline 0 0))
          ($order (boaTopological (boaCombined $fixed (hboaGraph $nodes))))
          ($leafCounts (map-atom $nodes $node (List.length (hboaLeaves (hboaTree $node) ()))))
          ($parameters (List.sum (List.zipWith hboaParameters $fields $leafCounts)))
          ($edges (List.sum (map-atom $nodes $node (List.length (hboaParents $node)))))
          ($totalLeaves (List.sum $leafCounts)))
     (mkHBOAModel $nodes $order $alpha
       (mkHFitStats (- (candidateNow) $started) $edges $parameters
         (- (* 2 $totalLeaves) (List.length $fields)) $totalLeaves $splits
         (+ (List.length $fields) $calls) $reason))))

;; Computes the number of free probability parameters contributed by a node's decision tree.
;;   $field: Field specification of the coordinate.
;;   $leaves: Number of leaves in the node's decision tree.
;;   Returns: Total free parameters: (cardinality - 1) * leaves.
(= (hboaParameters $field $leaves) (* (- (fieldCardinality $field) 1) $leaves))
