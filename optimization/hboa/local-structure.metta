;; Context-specific categorical distributions as binary decision trees.
;; A test is parent == category (including -1 = INACTIVE, distinct from STOP).
;; Leaves hold UNSMOOTHED active-child counts. Only sampling adds alpha.

;; Extracts the decision tree local model from an hBOA node.
;;   (mkHNode $child $parents $tree $n): hBOA variable node.
;;   Returns: The binary decision tree $tree.
(= (hboaTree (mkHNode $child $parents $tree $n)) $tree)

;; Extracts the list of learned parent coordinate indices from an hBOA node.
;;   (mkHNode $child $parents $tree $n): hBOA variable node.
;;   Returns: List of parent coordinate indices $parents.
(= (hboaParents (mkHNode $child $parents $tree $n)) $parents)

;; Constructs a dependency graph from a list of hBOA nodes.
;;   $nodes: List of mkHNode records.
;;   Returns: Graph represented as a list of parent lists indexed by child coordinate.
(= (hboaGraph $nodes) (map-atom $nodes $node (hboaParents $node)))

;; Recursively enumerates all leaves in a decision tree together with their split decision paths.
;;   $tree: Binary decision tree (mkHLeaf or mkHSplit).
;;   $path: Accumulated list of split decisions ($parent $value $branch).
;;   Returns: List of tuples ($path $counts) for each leaf in the tree.
(= (hboaLeaves $tree $path)
   (case $tree
     (((mkHLeaf $counts) (($path $counts)))
      ((mkHSplit $parent $value $yes $no)
       (List.concat (hboaLeaves $yes (List.append ($parent $value True) $path))
                    (hboaLeaves $no (List.append ($parent $value False) $path)))))))

;; Tests whether a candidate instance observation view satisfies all split conditions along a path.
;;   $view: Model view for a candidate instance.
;;   $path: Decision path as a list of ($parent $value $branch) conditions.
;;   Returns: True if the candidate matches all branch conditions on the path, False otherwise.
(= (hboaMatches $view $path)
   (all (map-atom $path ($parent $value $branch)
          (== (== (boaObservation $view $parent) $value) $branch))))

;; Replaces a specific leaf in a decision tree identified by its decision path with a new subtree.
;;   $tree: Current decision tree.
;;   $path: Decision path navigating to the target leaf.
;;   $replacement: New subtree (typically a split node with two child leaves).
;;   Returns: Updated decision tree containing the replacement subtree.
(= (hboaReplaceLeaf $tree $path $replacement)
   (case $path
     ((() $replacement)
      ((cons ($parent $value $branch) $rest)
       (let (mkHSplit $p $v $yes $no) $tree
         (if $branch (mkHSplit $p $v (hboaReplaceLeaf $yes $rest $replacement) $no)
                     (mkHSplit $p $v $yes (hboaReplaceLeaf $no $rest $replacement))))))))

;; Evaluates a decision tree for a given observation view and returns Laplace-smoothed categorical weights.
;;   $tree: Binary decision tree model.
;;   $view: Context observation view for candidate coordinates.
;;   $alpha: Pseudocount smoothing parameter.
;;   Returns: Smoothed categorical sampling weights at the destination leaf.
(= (hboaWeights $tree $view $alpha)
   (case $tree
     (((mkHLeaf $counts) (boaWeights $counts $alpha))
      ((mkHSplit $parent $value $yes $no)
       (hboaWeights (if (== (List.getByIdx $view $parent) $value) $yes $no) $view $alpha)))))

;; Initializes an hBOA node as an independent root tree with a single leaf holding marginal counts.
;;   $fields: Full list of schema fields.
;;   $views: Selected candidate model views.
;;   $child: Target child coordinate index.
;;   Returns: mkHNode with empty parents and single mkHLeaf root.
(= (hboaRoot $fields $views $child)
   (let* (($values (filter-atom (map-atom $views $v (boaObservation $v $child)) $x (>= $x 0)))
          ($counts (boaCounts $values (fieldCardinality (List.getByIdx $fields $child)))))
     (mkHNode $child () (mkHLeaf $counts) (List.length $values))))

;; BIC delta uses the number of ACTIVE observations for this child, not the
;; branch sample size: one split adds (cardinality - 1) free probabilities.
;; Both branches must have support; impossible/empty contexts are never split.
;; Evaluates a candidate binary split (parent == value) on a leaf and calculates the BIC gain.
;;   $views: Active population model views matching the leaf path.
;;   $child: Child coordinate index.
;;   $parent: Candidate parent coordinate index to test.
;;   $value: Category value of parent being tested.
;;   $card: Cardinality of the child coordinate.
;;   $n: Total active observation count for the child across all contexts.
;;   $counts: Unsmoothed category counts at the current leaf.
;;   $minimum: Minimum sample support required in both yes and no branches.
;;   Returns: Tuple ($splitNode $gain) if split is viable and supported, or () if discarded.
(= (hboaSplit $views $child $parent $value $card $n $counts $minimum)
   (let* (($yes (filter-atom $views $v (== (boaObservation $v $parent) $value)))
          ($no (filter-atom $views $v (not (== (boaObservation $v $parent) $value)))))
     (if (or (< (List.length $yes) $minimum) (< (List.length $no) $minimum)) ()
       (let* (($yc (boaCounts (map-atom $yes $v (boaObservation $v $child)) $card))
              ($nc (boaCounts (map-atom $no $v (boaObservation $v $child)) $card))
              ($gain (- (- (+ (boaLogLikelihood $yc) (boaLogLikelihood $nc)) (boaLogLikelihood $counts))
                        (* 0.5 (* (- $card 1) (log-math 2.718281828459045 $n))))))
         ((mkHSplit $parent $value (mkHLeaf $yc) (mkHLeaf $nc)) $gain)))))
