;; Step 5: annotate constants in an ALREADY BUILT numeric AST, without affine
;; canonization/reduction (Step 6). Load contin-spec/stepper first.
;; Shape: (mkRep (mkKbMap (mkDscMp entries)) annotatedTree).
;; A knob leaf is (mkTree (mkCTK spec startIndex) ()).
;; Owners are canonical NodeId paths: root (), children 1,2,... recursively.
;; All fields are append-only in depth-first, left-to-right constant order.
;;   $owner: stable NodeId assigned to a constant; $offset: current trit offset;
;;   $depth: number of trits allocated. Returns raw-map entries for the remaining slice.
(= (continRawSlice $owner $offset $depth)
   (if (== $offset $depth) ()
       (cons ((mkDiscSpec 3) (mkContinTritField $owner $offset))
             (continRawSlice $owner (+ $offset 1) $depth))))

;; Explicit callback bridges the mutually recursive tree/children walkers.
;;   $fun: selected walker; $tree/$path: subtree and owner path; $start: next
;;   flat-map index; $step/$exp/$depth: per-knob decoding parameters.
;;   Returns the callback result (built subtree, fields, next index, or error).
(= (continBuildCall $fun $tree $path $start $step $exp $depth)
   ($fun $tree $path $start $step $exp $depth))
;;   $children: sibling subtrees; $path: parent path; $childIndex: next child
;;   number; remaining arguments carry the flat index and knob parameters.
;;   Returns ordered built children/fields and the first unused index.
(= (continBuildChildren $children $path $childIndex $start $step $exp $depth)
   (case $children
     ((() (mkContinBuild () () $start))
      ((cons $child $rest)
       (case (continBuildCall continBuildTree $child (continAppend $path ($childIndex)) $start $step $exp $depth)
         (((mkCEvalError $reason) (mkCEvalError $reason))
          ((mkContinBuild $tree $fields $next)
           (case (continBuildChildren $rest $path (+ $childIndex 1) $next $step $exp $depth)
             (((mkCEvalError $failure) (mkCEvalError $failure))
              ((mkContinBuild $trees $moreFields $end)
               (mkContinBuild (cons $tree $trees) (continAppend $fields $moreFields) $end))))))))
      ($bad (mkCEvalError "InvalidTree")))))
;;   $tree: subtree to annotate; $path: current node path; $start: next flat
;;   index; $step/$exp/$depth: geometric trit-decoding parameters.
;;   Returns the annotated subtree, its raw map fields, and next index.
(= (continBuildTree $tree $path $start $step $exp $depth)
   (case $tree
     (((mkTree (mkNode $value) $children)
       (if (== (get-type $value) Number)
           (if (and (== $children ()) (continFiniteNumber $value))
               (mkContinBuild (mkTree (mkCTK (mkContinSpec $value $step $exp $depth) $start) ())
                 (continRawSlice (mkNodeId $path) 0 $depth) (+ $start $depth))
               (mkCEvalError "InvalidConstant"))
           (case (continBuildChildren $children $path 1 $start $step $exp $depth)
             (((mkCEvalError $reason) (mkCEvalError $reason))
              ((mkContinBuild $built $fields $end)
               (mkContinBuild (mkTree (mkNode $value) $built) $fields $end))))))
      ($bad (mkCEvalError "InvalidTree")))))
;;   $tree: numeric AST; $step: initial move size; $exp: same-direction step
;;   expansion; $depth: trit count per constant. Returns a complete mkRep or error.
(= (buildContinRepresentation $tree $step $exp $depth)
   (if (continSpecValid (mkContinSpec 0 $step $exp $depth))
       (case (continBuildTree $tree () 0 $step $exp $depth)
         (((mkCEvalError $reason) (mkCEvalError $reason))
          ((mkContinBuild $built $fields $end) (mkRep (mkKbMap (mkDscMp $fields)) $built))))
       (mkCEvalError "InvalidContinSpec")))
;;   $tree: numeric AST. Returns a representation using defaults 1.0, 2.0, and 5.
(= (defaultContinRepresentation $tree) (buildContinRepresentation $tree 1.0 2.0 5))
