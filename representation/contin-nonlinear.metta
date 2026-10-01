;; Bounded generalized-polynomial scaffold (Steps 12/13).
;; Unlike C++ rec_canonize's unbounded coefficient recursion, degree bounds NEW
;; monomials and levels bounds recursive unary/division argument scaffolding.
;; Existing supported trees are retained, not algebraically distributed.
;; All coefficients use the existing CTK/trit schema. No optimizer-specific tree.
;; Config: (mkNonlinearConfig degree levels operators maxScaffoldNodes).
;; c_add/c_mul are mandatory; div/sin/log/exp are opt-in. Validate BEFORE reducing
;; so an inactive zero gate cannot smuggle a forbidden operator/unknown label.
;;   $ops: allowed operators; $seen: operators already encountered.
;;   Returns true only for a unique list from the supported operator vocabulary.
(= (cnOperatorsValid $ops $seen)
   (case $ops
     ((() True)
      ((cons $op $rest)
       (and (continContains $op (c_add c_mul c_div c_sin c_log c_exp))
            (and (not (continContains $op $seen)) (cnOperatorsValid $rest (cons $op $seen)))))
      ($bad False))))
;;   $config: mkNonlinearConfig(degree, recursive levels, operators, node cap).
;;   Returns whether every bound and mandatory operator is valid.
(= (nonlinearConfigValid $config)
   (case $config
     (((mkNonlinearConfig $degree $levels $ops $cap)
       (if (and (continNatural $degree) (and (continNatural $levels) (continNatural $cap)))
           (and (and (>= $degree 1) (<= $degree 4))
                (and (<= $levels 2) (and (and (>= $cap 1) (<= $cap 100000))
                  (if (cnOperatorsValid $ops ())
                      (and (continContains c_add $ops) (continContains c_mul $ops)) False)))) False))
      ($bad False))))
;;   $children: child ASTs; $labels: permitted variables; $ops: operator vocabulary.
;;   Returns true only if every child is a valid subtree.
(= (cnChildrenValid $children $labels $ops)
   (case $children
     ((() True)
      ((cons $child $rest)
       (and (let $validate cnTreeValid ($validate $child $labels $ops))
            (cnChildrenValid $rest $labels $ops)))
      ($bad False))))
;;   $tree: candidate expression; $labels/$ops: allowed leaves/operators.
;;   Returns whether arities, leaves, and all descendants conform to that vocabulary.
(= (cnTreeValid $tree $labels $ops)
   (case $tree
     (((mkTree (mkNode $value) $children)
       (if (continContains $value (c_add c_mul c_div c_sin c_log c_exp))
           (and (continContains $value $ops)
                (and (case $value
                       ((c_add True) (c_mul True)
                        (c_div (== (continListLength $children) 2))
                        ($unary (== (continListLength $children) 1))))
                     (cnChildrenValid $children $labels $ops)))
           (and (== $children ())
                (if (== (get-type $value) Number) (continFiniteNumber $value)
                    (continContains $value $labels)))))
      ($bad False))))
;;   $tree: expression tree. Returns its total number of AST nodes.
(= (cnNodeCount (mkTree (mkNode $value) $children))
   (+ 1 (foldl-atom $children 0 $total $child (+ $total (let $count cnNodeCount ($count $child))))))
;; Ordered combinations with repetition: x,z, x*x,x*z,z*z,...; no permutation
;; duplicates. Admission bound below is checked before enumerating these lists.
;;   $labels: input vocabulary; $degree: exact product degree.
;;   Returns unique commutative monomial factor lists at that degree.
(= (cnProducts $labels $degree)
   (if (== $degree 0) (())
       (case $labels
         ((() ())
          ((cons $head $tail)
           (continAppend
             (map-atom (cnProducts $labels (- $degree 1)) $suffix (cons (crLeaf $head) $suffix))
             (cnProducts $tail $degree)))))))
;;   $labels: input vocabulary; $degree: maximum degree; $current: degree being emitted.
;;   Returns all non-constant monomial trees from current through maximum degree.
(= (cnMonomials $labels $degree $current)
   (if (> $current $degree) ()
       (continAppend
         (map-atom (cnProducts $labels $current) $factors
           (case $factors ((($one) $one) ($many (mkTree (mkNode c_mul) $many)))))
         (cnMonomials $labels $degree (+ $current 1)))))
;;   $ops: enabled operators; $labels: input vocabulary.
;;   Returns unary-function and label/constant division basis trees.
(= (cnFunctionBases $ops $labels)
   (case $ops
     ((() ())
      ((cons $op $rest)
       (continAppend
         (if (continContains $op (c_add c_mul)) ()
             (map-atom $labels $label
               (if (== $op c_div)
                   (mkTree (mkNode c_div) ((crLeaf $label) (crLeaf 1.0)))
                   (mkTree (mkNode $op) ((crLeaf $label))))))
         (cnFunctionBases $rest $labels))))))
;;   $labels/$degree/$ops: vocabulary, polynomial degree, and enabled operators.
;;   Returns polynomial and optional function bases in deterministic order.
(= (cnBases $labels $degree $ops)
   (continAppend (cnMonomials $labels $degree 1) (cnFunctionBases $ops $labels)))
;; Keep multiplication factor order/grouping. Only function arguments introduce
;; another local scaffold, with strictly decreasing depth; ordinary descendants
;; are traversed without adding redundant wrappers to every leaf.
;;   $tree: operator node to traverse; $labels/$degree/$ops: scaffold vocabulary
;;   and limits; $levels: remaining recursive function-argument depth.
;;   Returns same operator with eligible children scaffolded.
(= (cnInner (mkTree (mkNode $op) $children) $labels $degree $ops $levels)
   (mkTree (mkNode $op)
     (map-atom $children $child
       (if (and (> $levels 0) (continContains $op (c_div c_sin c_log c_exp)))
           (let $scaffold cnScaffold ($scaffold $child $labels $degree $ops (- $levels 1)))
           (let $inner cnInner ($inner $child $labels $degree $ops $levels))))))
;;   $term: candidate summand, possibly scalar-times-basis.
;;   Returns its unweighted basis for duplicate detection.
(= (cnBasis $term)
   (case $term
     (((mkTree (mkNode c_mul) ($coefficient $basis)) (if (crNumber $coefficient) $basis $term))
      ($other $other))))
;;   $coefficient: starting scalar; $basis: expression; other args are the
;;   allowed scaffold vocabulary and recursion limits. Returns weighted scaffold tree.
(= (cnWeighted $coefficient $basis $labels $degree $ops $levels)
   (mkTree (mkNode c_mul)
     ((crLeaf $coefficient) (cnInner $basis $labels $degree $ops $levels))))
;;   $term: existing summand; remaining args configure permitted recursive bases.
;;   Returns the summand preserved in order, with its coefficient separated.
(= (cnExistingTerm $term $labels $degree $ops $levels)
   (if (crNumber $term) $term
       (case $term
         (((mkTree (mkNode c_mul) ($coefficient $basis))
           (if (crNumber $coefficient)
               (cnWeighted (crValue $coefficient) $basis $labels $degree $ops $levels)
               (cnWeighted 1.0 $term $labels $degree $ops $levels)))
          ($other (cnWeighted 1.0 $term $labels $degree $ops $levels))))))
;;   $tree: already validated/reduced expression; $labels/$degree/$ops/$levels:
;;   allowed new bases and recursion bounds. Returns expression plus zero-weight
;;   missing terms, preserving existing summand order.
(= (cnScaffold $tree $labels $degree $ops $levels)
   (let* (($terms (case $tree (((mkTree (mkNode c_add) $children) $children) ($other ($other)))))
          ($seen (map-atom $terms $term (cnBasis $term)))
          ($existing (map-atom $terms $term (cnExistingTerm $term $labels $degree $ops $levels)))
          ($bias (if (foldl-atom $terms False $found $term (or $found (crNumber $term))) () ((crLeaf 0.0))))
          ($missing (filter-atom (cnBases $labels $degree $ops) $basis (not (continContains $basis $seen))))
          ($new (map-atom $missing $basis (cnWeighted 0.0 $basis $labels $degree $ops $levels))))
     (mkTree (mkNode c_add) (continAppend $existing (continAppend $bias $new)))))
;; Conservative node admission bound, deliberately computed BEFORE expansion.
;; Each local scaffold has at most (n+1)^degree monomials and n*|ops| functions.
;; A function has at most two recursively scaffolded arguments. Over-counting
;; permits an inexpensive hard bound even for existing nested expressions.
;;   $n: number of labels; $degree: polynomial degree; $ops: enabled functions;
;;   $levels: recursive function depth. Returns conservative node-growth bound.
(= (cnGrowthBound $n $degree $ops $levels)
   (let* (($monomials (pow-math (+ $n 1) $degree))
          ($functions (* $n (continListLength (filter-atom $ops $op (not (continContains $op (c_add c_mul)))))))
          ($local (+ 4 (+ (* $monomials (+ $degree 3)) (* $functions 5)))))
     (if (== $levels 0) $local
         (+ $local (* (+ 2 (* 2 $functions)) (cnGrowthBound $n $degree $ops (- $levels 1)))))))
;;   $tree: source AST; $labels/$degree/$ops/$levels: configuration dimensions.
;;   Returns conservative total output-node bound, before scaffold allocation.
(= (cnAdmissionBound $tree $labels $degree $ops $levels)
   (if (== (continListLength $ops) 2)
       (+ (* 3 (cnNodeCount $tree)) (cnGrowthBound (continListLength $labels) $degree $ops 0))
       (* (cnNodeCount $tree) (cnGrowthBound (continListLength $labels) $degree $ops $levels))))
;;   $tree: source expression; $labels: allowed variable vocabulary;
;;   $config: bounded nonlinear scaffold settings. Returns scaffold or validation,
;;   vocabulary, or size-limit error.
(= (continNonlinearCanonize $tree $labels $config)
   (if (not (nonlinearConfigValid $config)) (mkCEvalError "InvalidNonlinearConfig")
       (if (not (continValidLabels $labels ())) (mkCEvalError "InvalidNonlinearLabels")
           (let (mkNonlinearConfig $degree $levels $ops $cap) $config
             (if (not (if (continTreeWellFormed $tree) (cnTreeValid $tree $labels $ops) False)) (mkCEvalError "InvalidNonlinearVocabularyOrTree")
                 (if (> (cnAdmissionBound $tree $labels $degree $ops $levels) $cap)
                     (mkCEvalError "NonlinearScaffoldLimit")
                     (let $scaffold (cnScaffold (reduceContinTree $tree) $labels $degree $ops $levels)
                        (if (> (cnNodeCount $scaffold) $cap) (mkCEvalError "NonlinearScaffoldLimit") $scaffold))))))))
