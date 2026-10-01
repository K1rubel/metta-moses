;; Local sufficient statistics + BIC. -1 is an INACTIVE PARENT category only;
;; active STOP is 0. Inactive children never contribute observations.
;; Node: child, sorted learned parents, CPT(context, unsmoothed counts),
;;       smoothed marginal fallback, BIC, free parameters, active sample count.
;; Extracts the observed value for a coordinate from an individual's model view.
;;   $view: List of model-view fields for a candidate instance.
;;   $index: Coordinate index to look up.
;;   Returns: The categorical value if active, or -1 if inactive.
(= (boaObservation $view $index)
   (case (List.getByIdx $view $index)
     (((mkActiveField $i $v) $v) ((mkInactiveField $i) -1))))

;; Extracts the parent observation tuple for a given set of parent coordinates.
;;   $view: List of model-view fields for a candidate instance.
;;   $parents: List of parent coordinate indices.
;;   Returns: List of parent observations matching the parent indices.
(= (boaContext $view $parents) (map-atom $parents $p (boaObservation $view $p)))

;; Checks whether two fields belong to the same continuous polynomial slice.
;;   $a: First field specification.
;;   $b: Second field specification.
;;   Returns: True if both are continuous and share fieldStart, False otherwise.
(= (boaSameSlice $a $b)
   (and (== (fieldKind $a) continuous)
     (and (== (fieldKind $b) continuous) (== (fieldStart $a) (fieldStart $b)))))

;; Parents are sorted. Adjacent/nonadjacent sampled coordinates in one slice
;; must admit at least one legal completion of the unobserved intervening trits.
;; Checks whether an earlier coordinate value and later coordinate value form a valid prefix.
;;   $earlier: Field specification of earlier coordinate.
;;   $ev: Value of earlier coordinate.
;;   $later: Field specification of later coordinate.
;;   $lv: Value of later coordinate.
;;   Returns: True if the combination admits a legal completion, False otherwise.
(= (boaPairPermitted $earlier $ev $later $lv)
   (if (boaSameSlice $earlier $later)
     (if (<= $ev 0) (== $lv -1)
       (if (== (fieldIndex $later) (+ 1 (fieldIndex $earlier))) (>= $lv 0) True)) True))

;; A separate recursion avoids a variadic zip helper.
;; Recursively verifies that a candidate value is compatible with all prefix coordinate values.
;;   $fields: List of prefix field specifications.
;;   $values: List of assigned prefix coordinate values.
;;   $field: Field specification of the new coordinate to append.
;;   $value: Proposed value for the new coordinate.
;;   Returns: True if compatible with all prefix fields, False otherwise.
(= (boaTruePair $fields $values $field $value)
   (case ($fields $values)
     (((() ()) True)
      (((cons $f $fs) (cons $v $vs))
       (and (boaPairPermitted $f $v $field $value) (boaTruePair $fs $vs $field $value))))))

;; Generates the allowed discrete categories for a parent coordinate conditioning a child.
;;   $field: Parent field specification.
;;   $child: Child field specification.
;;   Returns: List of allowed category values (e.g. including -1 for inactive if applicable).
(= (boaAllowedParentValues $field $child)
   (if (and (boaSameSlice $field $child) (< (fieldIndex $field) (fieldIndex $child)))
     (1 2)
     (fieldPriorIndices (if (> (fieldOffset $field) 0) -1 0) (fieldCardinality $field))))

;; Enumerate only permitted ACTIVE-child contexts, including unobserved ones.
;; At each extension every surviving prefix admits a completion, so early cap
;; rejection cannot discard a smaller final table. No full genotype enumeration.
;; Extends an existing list of context tuples with values for the next parent coordinate.
;;   $contexts: Accumulated list of valid prefix context tuples.
;;   $values: Allowed values for the new parent field.
;;   $prefixFields: List of field specifications for coordinates in prefix.
;;   $field: Field specification of the parent coordinate being added.
;;   $cap: Maximum allowable context count threshold.
;;   $out: Accumulator for extended context tuples.
;;   Returns: Extended list of context tuples, or boaTooLarge if cap is exceeded.
(= (boaExtendContexts $contexts $values $prefixFields $field $cap $out)
   (case $contexts
     ((() $out)
      ((cons $ctx $rest)
       (let* (($legal (filter-atom $values $v (boaTruePair $prefixFields $ctx $field $v)))
              ($more (map-atom $legal $v (List.append $v $ctx))))
         (if (> (+ (List.length $out) (List.length $more)) $cap) boaTooLarge
           (boaExtendContexts $rest $values $prefixFields $field $cap (List.concat $out $more))))))))

;; Recursively enumerates joint parent contexts across remaining parent coordinates.
;;   $fields: Full list of schema fields.
;;   $child: Child field specification.
;;   $parents: Remaining parent coordinate indices to process.
;;   $prefix: Accumulated list of parent field specifications already processed.
;;   $contexts: Current list of valid partial context tuples.
;;   $cap: Maximum allowable context count threshold.
;;   Returns: Complete list of legal parent context tuples, or boaTooLarge.
(= (boaContextsRest $fields $child $parents $prefix $contexts $cap)
   (case $parents
     ((() $contexts)
      ((cons $p $rest)
       (let* (($field (List.getByIdx $fields $p))
              ($next (boaExtendContexts $contexts (boaAllowedParentValues $field $child) $prefix $field $cap ())))
         (if (== $next boaTooLarge) boaTooLarge
           (boaContextsRest $fields $child $rest (List.append $field $prefix) $next $cap)))))))

;; Builds the complete list of valid parent context tuples for a child under a cell budget.
;;   $fields: Full list of schema fields.
;;   $child: Child field specification.
;;   $parents: List of parent coordinate indices.
;;   $maxCells: Upper limit on total table cells (cardinality * num_contexts).
;;   Returns: List of permitted parent contexts, or boaTooLarge if budget exceeded.
(= (boaContexts $fields $child $parents $maxCells)
   (if (> (fieldCardinality $child) $maxCells) boaTooLarge
     (if (any (map-atom $parents $p (> (fieldCardinality (List.getByIdx $fields $p)) $maxCells))) boaTooLarge
       (boaContextsRest $fields $child $parents () (()) (floor-math (/ $maxCells (fieldCardinality $child)))))))

;; Counts the occurrences of each discrete category among active observations.
;;   $values: List of observed integer category values.
;;   $card: Total cardinality (number of categories) for the field.
;;   Returns: List of counts indexed from category 0 to $card - 1.
(= (boaCounts $values $card) (edaCategoryWeights $values $card 0 0))

;; Adds pseudocount alpha to unnormalized counts for Laplace smoothing.
;;   $counts: List of empirical category counts.
;;   $alpha: Positive pseudocount smoothing parameter.
;;   Returns: List of smoothed positive weights for sampling.
(= (boaWeights $counts $alpha) (map-atom $counts $n (+ $n $alpha)))

;; Computes empirical log-likelihood for a categorical frequency distribution.
;;   $counts: List of category counts.
;;   Returns: Floating-point log-likelihood value.
(= (boaLogLikelihood $counts)
   (let $total (List.sum $counts)
     (if (== $total 0) 0.0
       (foldl-atom $counts 0.0 $ll $n
         (if (== $n 0) $ll (+ $ll (* $n (log-math 2.718281828459045 (/ $n $total)))))))))

;; Fits a local conditional probability table (CPT) and computes its BIC score.
;;   $fields: Full list of schema fields.
;;   $views: Population model views for selected candidates.
;;   $childIndex: Target child coordinate index.
;;   $parents: List of parent coordinate indices.
;;   $alpha: Dirichlet pseudocount for smoothing.
;;   $contexts: List of legal parent context tuples.
;;   Returns: mkBOANode containing child, parents, CPT table, fallback, BIC score, parameters, and count.
(= (boaFitLocal $fields $views $childIndex $parents $alpha $contexts)
   (let* (($child (List.getByIdx $fields $childIndex))
          ($card (fieldCardinality $child))
          ($active (filter-atom $views $v (>= (boaObservation $v $childIndex) 0)))
          ($n (List.length $active))
          ($rows (map-atom $active $v ((boaContext $v $parents) (boaObservation $v $childIndex))))
          ($table (map-atom $contexts $ctx
                    ($ctx (boaCounts (map-atom (filter-atom $rows ($key $value) (== $key $ctx))
                                      ($key $value) $value) $card))))
          ($fallback (boaWeights (boaCounts (map-atom $active $v (boaObservation $v $childIndex)) $card) $alpha))
          ($parameters (* (- $card 1) (List.length $contexts)))
          ($ll (foldl-atom $table 0.0 $sum ($ctx $counts) (+ $sum (boaLogLikelihood $counts))))
          ($score (if (== $n 0) 0.0 (- $ll (* 0.5 (* $parameters (log-math 2.718281828459045 $n)))))))
     (mkBOANode $childIndex $parents $table $fallback $score $parameters $n)))

;; Extracts parent coordinate indices from a BOA local node.
;;   (mkBOANode $i $ps $t $f $s $k $n): BOA local node.
;;   Returns: List of parent indices $ps.
(= (boaNodeParents (mkBOANode $i $ps $t $f $s $k $n)) $ps)

;; Extracts BIC score from a BOA local node.
;;   (mkBOANode $i $ps $t $f $s $k $n): BOA local node.
;;   Returns: BIC score $s.
(= (boaNodeScore (mkBOANode $i $ps $t $f $s $k $n)) $s)

;; Extracts number of free parameters from a BOA local node.
;;   (mkBOANode $i $ps $t $f $s $k $n): BOA local node.
;;   Returns: Parameter count $k.
(= (boaNodeParameters (mkBOANode $i $ps $t $f $s $k $n)) $k)

;; Computes total table cell count for a BOA local node.
;;   (mkBOANode $i $ps $t $f $s $k $n): BOA local node.
;;   Returns: Integer product of context count and child cardinality.
(= (boaNodeCells (mkBOANode $i $ps $t $f $s $k $n)) (* (List.length $t) (List.length $f)))

;; Unseen context backs off to the smoothed active-child marginal. For N=0,
;; this is the symmetric Dirichlet prior; no log(0) or fabricated evidence.
;; Retrieves the smoothed categorical weight vector for a child given observed parent context.
;;   (mkBOANode $i $ps $table $fallback $score $k $n): BOA local node.
;;   $context: Observed values of parent coordinates.
;;   $alpha: Pseudocount smoothing parameter.
;;   Returns: Smoothed conditional categorical weights, backing off to $fallback if unseen.
(= (boaConditionalWeights (mkBOANode $i $ps $table $fallback $score $k $n) $context $alpha)
   (case (filter-atom $table ($key $counts) (== $key $context))
     (((($key $counts)) (if (== (List.sum $counts) 0) $fallback (boaWeights $counts $alpha)))
      ($missing $fallback))))
