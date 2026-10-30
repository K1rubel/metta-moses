;; ============================================================================
;; Module: representation/contin-canonize.metta
;; Purpose: Convert a supported affine expression into a complete, stable
;;          scaffold whose bias and feature coefficients can become continuous
;;          knobs.
;;
;; Main function — continAffineCanonize($tree, $labels):
;;   $tree   : source expression tree (mkTree); may contain finite constants,
;;             declared input labels, scalar*label products, and sums of those.
;;   $labels : ordered list of permitted input feature labels.
;;   Returns : an affine c_add tree containing one bias and one coefficient
;;             slot per label, or mkCEvalError(reason) if labels are invalid,
;;             reduction fails, or the expression is not in the supported form.
;;
;; Seed function — continAffineSeed($labels):
;;   $labels : ordered input feature vocabulary.
;;   Returns : the same complete scaffold with zero bias and zero coefficients,
;;             or the validation error returned by continAffineCanonize.
;;
;; The scaffold preserves safe reduced term order and appends missing bias and
;; feature terms as zeros. This gives representation building a stable set of
;; coefficient locations without changing expression grouping unnecessarily.
;; Step 6: AFFINE MVP only, not build_knobs.cc's generalized-polynomial canonizer.
;; Load contin-reduct first. Accepted exemplars: finite constants, input labels,
;; binary scalar*label terms, and flat sums of distinct terms plus one bias.
;; reduceContinTree supplies constant folding, safe left-leveling and identities.
;; Do not distribute products, merge repeated features, or reorder a long sum:
;; those operations can change rounding/overflow even for mathematical affines.
;; Existing reduced term order is preserved; missing bias/features are appended
;; as zeros. Thus rebuilding restores searchable slots without changing grouping.
;; Internal parser arguments are the term/tree and the declared feature labels;
;; parsed-term helpers also carry the seen-label set and whether a bias occurred.
;; Their outputs are affine records/trees or mkCEvalError explaining rejection.
;; caLabelTerm: $label is a feature, $coefficient its weight, and $labels the
;; permitted vocabulary. Returns a parsed affine term or an unknown-label error.
;;   $label: declared input label; $coefficient: its scalar weight;
;;   $labels: permitted input vocabulary. Returns a term or unknown-label error.

(= (caLabelTerm $label $coefficient $labels)
   (if (continContains $label $labels)
       (mkAffineTerm $label $coefficient) (mkCEvalError "UnknownAffineLabel")))
;; caProductTerm: $children are product operands and $labels are permitted
;; features. Returns a scalar-times-label term or UnsupportedAffineForm.
;;   $children: product operands; $labels: permitted input labels.
;;   Returns one scalar-times-label term; rejects other product forms.

(= (caProductTerm $children $labels)
   (case $children
     ((($a $b)
       (if (and (crNumber $a) (crLabel $b))
           (caLabelTerm (crValue $b) (crValue $a) $labels)
           (if (and (crLabel $a) (crNumber $b))
               (caLabelTerm (crValue $a) (crValue $b) $labels)
               (mkCEvalError "UnsupportedAffineForm"))))
      ($other (mkCEvalError "UnsupportedAffineForm")))))

;; caTerm: $tree is one reduced expression term and $labels are allowed
;; features. Returns a parsed bias/feature record or a structured error.
;;   $tree: one reduced term; $labels: permitted inputs.
;;   Returns bias/feature term or an error for unsupported syntax/constants.

(= (caTerm $tree $labels)
   (case $tree
     (((mkTree (mkNode $value) ())
       (if (== (get-type $value) Number)
           (if (continFiniteNumber $value) (mkAffineBias $value) (mkCEvalError "NonFinite"))
           (caLabelTerm $value 1.0 $labels)))
      ((mkTree (mkNode c_mul) $children) (caProductTerm $children $labels))
      ($nonAffine (mkCEvalError "UnsupportedAffineForm")))))

;; caTerms: $trees are expression summands, $labels the allowed features,
;; $seen the features already encountered, and $hasBias whether a bias exists.
;; Returns parsed affine terms or an error for duplicates/unsupported terms.
;;   $trees: terms in preserved order; $labels: allowed inputs; $seen: labels
;;   already used; $hasBias: whether one bias was parsed. Returns parsed terms/error.

(= (caTerms $trees $labels $seen $hasBias)
   (case $trees
     ((() (mkAffineTerms () $seen $hasBias))
      ((cons $tree $rest)
              (case (caTerm $tree $labels)
                  (
                    ((mkCEvalError $reason) (mkCEvalError $reason))
                    ((mkAffineBias $bias)
                          (if $hasBias (mkCEvalError "RepeatedAffineBias")
                            (case (caTerms $rest $labels $seen True)
                                (
                                  ((mkCEvalError $biasError) (mkCEvalError $biasError))
                                  ((mkAffineTerms $tail $owners $flag) (mkAffineTerms (cons (mkAffineBias $bias) $tail) $owners $flag))))))
                    ((mkAffineTerm $label $coefficient)
                        (if (continContains $label $seen)    (mkCEvalError "RepeatedAffineFeature")
                            (case (caTerms $rest $labels (cons $label $seen) $hasBias)
                                (
                                  ((mkCEvalError $termError) (mkCEvalError $termError))
                                  ((mkAffineTerms $more $allOwners $biasFlag) (mkAffineTerms (cons (mkAffineTerm $label $coefficient) $more) $allOwners $biasFlag))))))))))))

;; caMissingTerms: $labels is the complete ordered feature vocabulary and
;; $seen contains represented features. Returns zero-weight terms for missing
;; features, preserving label order.
;;   $labels: full input vocabulary; $seen: features already represented.
;;   Returns zero-weight terms for each missing input, preserving label order.

(= (caMissingTerms $labels $seen)
   (case $labels
     ((() ())
      ((cons $label $rest)
       (if (continContains $label $seen) (caMissingTerms $rest $seen)
           (cons (mkAffineTerm $label 0.0) (caMissingTerms $rest $seen)))))))

;; caTermTrees: $terms is a list of parsed bias/feature terms. Returns the
;; corresponding expression-tree summands.
;;   $terms: parsed affine terms. Returns corresponding expression-tree summands.

(= (caTermTrees $terms)
   (case $terms
     ((() ())
      ((cons (mkAffineBias $bias) $rest) (cons (crLeaf $bias) (caTermTrees $rest)))
      ((cons (mkAffineTerm $label $coefficient) $rest)
       (cons (mkTree (mkNode c_mul) ((crLeaf $coefficient) (crLeaf $label))) (caTermTrees $rest))))))

;; caComplete: $parsed is parsed affine terms or an error, and $labels is the
;; full feature vocabulary. Returns the complete c_add scaffold or that error.
;;   $parsed: successful parsed-term record or error; $labels: full vocabulary.
;;   Returns complete affine sum with explicit zero bias and missing features.

(= (caComplete $parsed $labels)
   (case $parsed
     (((mkCEvalError $reason) (mkCEvalError $reason))
      ((mkAffineTerms $terms $seen $hasBias)
       (let $withBias (if $hasBias $terms (continAppend $terms ((mkAffineBias 0.0))))
         (mkTree (mkNode c_add) (caTermTrees (continAppend $withBias (caMissingTerms $labels $seen)))))))))

;;   $tree: exemplar expression; $labels: permitted input vocabulary.
;;   Returns a stable affine scaffold or a structured validation/reduction error.

(= (continAffineCanonize $tree $labels)
   (if (continValidLabels $labels ())
       (case (reduceContinTree $tree)
         (
          ((mkCEvalError $reason) (mkCEvalError $reason))
          ((mkTree (mkNode c_add) $children) (caComplete (caTerms $children $labels () False) $labels))
          ($term (caComplete (caTerms ($term) $labels () False) $labels))))
       (mkCEvalError "InvalidAffineLabels")))

;;   $labels: permitted input vocabulary; returns its zero-initialized affine scaffold.

(= (continAffineSeed $labels) (continAffineCanonize (crLeaf 0.0) $labels))
