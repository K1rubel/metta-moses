;; Step 5. Load contin-representation first. Derived metadata, never a second
;; authoritative copy of CTK specs. Schema rows:
;; (mkField index cardinality default owner kind offset start spec)
;; kind = continuous | discrete; discrete fields use offset=0,start=index,spec=().
;; The accessors below each take one mkField row and return the named component.
;;   $field: Schema row; the result is respectively its index, cardinality,
;;           default, owner, kind, within-knob offset, slice start, or spec.
;;   $field in fieldDepth/fieldActivation/fieldActivationParents: one mkField;
;;   $field in fieldDepth returns CTK depth (1 for discrete), while activation
;;   helpers return its activation rule and the indices that gate it.
;;   $fields in schemaFields: mkField list; returns that stored list.
(= (fieldIndex (mkField $i $card $def $owner $kind $offset $start $spec)) $i)
(= (fieldCardinality (mkField $i $card $def $owner $kind $offset $start $spec)) $card)
(= (fieldDefault (mkField $i $card $def $owner $kind $offset $start $spec)) $def)
(= (fieldOwner (mkField $i $card $def $owner $kind $offset $start $spec)) $owner)
(= (fieldKind (mkField $i $card $def $owner $kind $offset $start $spec)) $kind)
(= (fieldOffset (mkField $i $card $def $owner $kind $offset $start $spec)) $offset)
(= (fieldStart (mkField $i $card $def $owner $kind $offset $start $spec)) $start)
(= (fieldSpec (mkField $i $card $def $owner $kind $offset $start $spec)) $spec)
;;   $field: Schema row.
;;   fieldDepth returns its knob depth, or 1 for an ordinary discrete coordinate.
(= (fieldDepth $field) (if (== (fieldKind $field) continuous) (continSpecDepth (fieldSpec $field)) 1))
;;   $field: Schema row. Returns alwaysActive for a slice root, otherwise the
;;   afterNonStop rule naming the earlier raw fields that gate this coordinate.
(= (fieldActivation $field)
   (if (== (fieldOffset $field) 0) alwaysActive (afterNonStop (fieldStart $field) (fieldIndex $field))))
;;   $start: first index; $end: exclusive upper bound. Returns [start,end).
(= (fieldPriorIndices $start $end)
   (if (== $start $end) () (cons $start (fieldPriorIndices (+ $start 1) $end))))
;;   $field: schema row. Returns the indices whose non-STOP values activate it.
(= (fieldActivationParents $field)
   (fieldPriorIndices (fieldStart $field) (fieldIndex $field)))
;;   $fields: ordered field rows. Returns the list stored in the schema record.
(= (schemaFields (mkFieldSchema $fields)) $fields)

;;   $owner: knob identity; $spec: knob geometry; $start: first flat index;
;;   $offset: current offset. Returns the remaining contiguous ternary rows.
(= (continFieldSlice $owner $spec $start $offset)
   (if (== $offset (continSpecDepth $spec)) ()
       (cons (mkField (+ $start $offset) 3 0 $owner continuous $offset $start $spec)
             (continFieldSlice $owner $spec $start (+ $offset 1)))))

;; Collect CTKs and their real tree paths; an owner cannot be forged by editing
;; the raw map. Wrong starts/overlaps/missing/extra/reordered fields all fail.
;;   $fun: Walker callback; $tree: subtree; $path: current child-index path.
;;   Returns: Callback result for that subtree and path.
(= (continOwnerCall $fun $tree $path) ($fun $tree $path))
;;   $children: ordered child trees; $path: parent path; $index: next child index.
;;   Returns: collected continuous owners, or a tree-validation error.
(= (continCollectChildren $children $path $index)
   (case $children
     ((() (mkContinOwners ()))
      ((cons $child $rest)
       (case (continOwnerCall continCollectOwners $child (continAppend $path ($index)))
         (((mkCEvalError $reason) (mkCEvalError $reason))
          ((mkContinOwners $owners)
           (case (continCollectChildren $rest $path (+ $index 1))
             (((mkCEvalError $failure) (mkCEvalError $failure))
              ((mkContinOwners $more) (mkContinOwners (continAppend $owners $more)))))))))
      ($bad (mkCEvalError "InvalidTree")))))
;;   $tree: annotated representation AST; $path: its root-to-node child indices.
;;   Returns ordered continuous owner records, or a malformed tree/spec error.
(= (continCollectOwners $tree $path)
   (case $tree
     (((mkTree (mkCTK $spec $start) ())
       (if (and (continSpecValid $spec) (continNatural $start))
           (mkContinOwners ((mkContinOwner (mkNodeId $path) $spec $start)))
           (mkCEvalError "InvalidContinSpec")))
      ((mkTree (mkNode $value) $children) (continCollectChildren $children $path 1))
      ($bad (mkCEvalError "InvalidTree")))))
;;   $owners: ordered (owner,spec,start) records; $next: required next raw index.
;;   Returns contiguous expanded schema slices or InvalidFieldSlices.
(= (continOwnersSchema $owners $next)
   (case $owners
     ((() (mkFieldSchema ()))
      ((cons (mkContinOwner $owner $spec $start) $rest)
       (if (== $start $next)
           (case (continOwnersSchema $rest (+ $next (continSpecDepth $spec)))
             (((mkCEvalError $reason) (mkCEvalError $reason))
              ((mkFieldSchema $more)
               (mkFieldSchema (continAppend (continFieldSlice $owner $spec $start 0) $more)))))
           (mkCEvalError "InvalidFieldSlices"))))))
;;   $fields: expanded continuous field rows. Returns equivalent raw map entries.
(= (continSchemaRaw $fields)
   (case $fields
     ((() ())
      ((cons $field $rest)
       (cons ((mkDiscSpec 3) (mkContinTritField (fieldOwner $field) (fieldOffset $field)))
             (continSchemaRaw $rest))))))
;;   $rep: representation with annotated tree and raw knob map. Returns the
;;   derived schema only if raw map entries exactly match its tree owners/slices.
(= (continFieldSchema $rep)
   (case $rep
     (((mkRep (mkKbMap (mkDscMp $raw)) $tree)
       (case (continCollectOwners $tree ())
         (((mkCEvalError $reason) (mkCEvalError $reason))
          ((mkContinOwners $owners)
           (case (continOwnersSchema $owners 0)
             (((mkCEvalError $failure) (mkCEvalError $failure))
              ((mkFieldSchema $fields)
               (if (== $raw (continSchemaRaw $fields)) (mkFieldSchema $fields)
                   (mkCEvalError "InvalidRawFieldMap")))))))))
      ($bad (mkCEvalError "InvalidContinuousRepresentation")))))

;; Generic schema validation allows heterogeneous independent discrete fields
;; alongside whole continuous slices; population algorithms need not assume 3.
;;   $card: category count; $def: default category index.
;;   Returns: True when the finite discrete coordinate has a legal default.
(= (fieldDiscreteValid $card $def)
   (if (and (continInteger $card) (continNatural $def))
       (and (> $card 0) (< $def $card)) False))
;;   $fields: unconsumed field rows; $index: expected index; $seen: owners used.
;;   Returns: whether all rows satisfy ordering, slice, cardinality and ownership invariants.
(= (fieldRowsValid $fields $index $seen)
   (case $fields
     ((() True)
      ((cons (mkField $i $card $def $owner $kind $offset $start $spec) $rest)
       (if (and (== $i $index) (and (== $offset 0) (and (== $start $index) (not (continContains $owner $seen)))))
           (case $kind
             ((continuous
               (if (continSpecValid $spec)
                   (let $depth (continSpecDepth $spec)
                     (if (>= (continListLength $fields) $depth)
                         (if (== (continTake $fields $depth) (continFieldSlice $owner $spec $index 0))
                             (fieldRowsValid (continDrop $fields $depth) (+ $index $depth) (cons $owner $seen)) False)
                         False)) False))
              (discrete (if (and (== $spec ()) (fieldDiscreteValid $card $def))
                            (fieldRowsValid $rest (+ $index 1) (cons $owner $seen)) False))
              ($badKind False))) False))
      ($badRows False))))
;;   $schema: candidate schema record; returns whether its entire field list is valid.
(= (fieldSchemaValid $schema)
   (case $schema (((mkFieldSchema $fields) (fieldRowsValid $fields 0 ())) ($bad False))))

;; Adapter for existing discrete maps. Obtain effective cardinality and default
;; from knob accessors, verifying the raw key agrees. No Boolean/action edits.
;;   $rows: raw discrete-map entries; $index: index assigned to the next row.
;;   Returns: a validated mkFieldSchema or mkCEvalError.
(= (discreteSchemaRows $rows $index)
   (case $rows
     ((() (mkFieldSchema ()))
      ((cons ((mkDiscSpec $card) $knob) $rest)
       (case (collapse ((getKnobMultip $knob) (getKnobDefault $knob)
                        (getRawKnobMultip $knob) (getDisallowedSpecs $knob)))
         (((((mkMultip $effective) (mkDiscSpec $actualDefault) (mkMultip $rawCard) $disallowed))
           (let $def (if (== $disallowed ()) $actualDefault 0)
           (if (and (== $card $effective) (and (fieldDiscreteValid $rawCard $actualDefault) (fieldDiscreteValid $card $def)))
               (case (discreteSchemaRows $rest (+ $index 1))
                 (((mkCEvalError $reason) (mkCEvalError $reason))
                  ((mkFieldSchema $fields)
                   (mkFieldSchema (cons (mkField $index $card $def (mkDiscreteOwner $index) discrete 0 $index ()) $fields)))))
               (mkCEvalError "InvalidDiscreteField"))))
          ($badKnob (mkCEvalError "InvalidDiscreteField")))))
      ($badRows (mkCEvalError "InvalidDiscreteField")))))
;;   $map: mkDscMp raw map; returns the corresponding validated field schema.
(= (discreteFieldSchema $map)
   (case $map (((mkDscMp $rows) (discreteSchemaRows $rows 0)) ($bad (mkCEvalError "InvalidRawFieldMap")))))

;;   $fields/$values: parallel schema rows and candidate categories.
;;   Returns true only for equal-length lists of in-range natural category indices.
(= (fieldValuesValid $fields $values)
   (case ($fields $values)
     (((() ()) True)
      (((cons $field $more) (cons $value $rest))
       (if (continNatural $value)
           (if (< $value (fieldCardinality $field)) (fieldValuesValid $more $rest) False) False))
      ($bad False))))
;;   $fields/$values: parallel schema and genotype lists; returns whether lengths
;;   match and every value is a natural category index below its field cardinality.
(= (fieldCanonicalValues $fields $values $active)
   (case ($fields $values)
     (((() ()) ())
      (((cons $field $more) (cons $value $rest))
       (let $now (if (== (fieldOffset $field) 0) True $active)
         (cons (if $now $value 0)
               (fieldCanonicalValues $more $rest (and $now (not (== $value 0))))))))))
;;   $fields/$values: parallel rows and raw values; $active: current prefix liveness.
;;   Returns canonical values, forcing every inactive descendant to category 0.
(= (canonicalizeInstance $schema $instance)
   (if (fieldSchemaValid $schema)
       (case $instance
         (((mkInst $values)
           (if (fieldValuesValid (schemaFields $schema) $values)
               (mkInst (fieldCanonicalValues (schemaFields $schema) $values True))
               (mkCEvalError "InvalidInstance")))
          ($bad (mkCEvalError "InvalidInstance"))))
       (mkCEvalError "InvalidFieldSchema")))
;;   $fields: ordered schema rows; returns one declared default per coordinate.
(= (fieldDefaults $fields)
   (case $fields ((() ()) ((cons $field $rest) (cons (fieldDefault $field) (fieldDefaults $rest))))))
;;   $schema: candidate field schema. Returns a default mkInst or validation error.
(= (schemaDefaultInstance $schema)
   (if (fieldSchemaValid $schema) (mkInst (fieldDefaults (schemaFields $schema))) (mkCEvalError "InvalidFieldSchema")))

;; Model observations distinguish active STOP from deterministic inactive zero.
;; Inactive observations must be masked as CHILDREN, but remain an explicit
;; category when used as PARENTS by later BOA/hBOA model code.
;;   $fields/$values: parallel schema and raw-coordinate lists; $active: whether
;;   the current prefix is live. Returns one active/inactive observation per field.
(= (fieldObservationRows $fields $values $active)
   (case ($fields $values)
     (((() ()) ())
      (((cons $field $more) (cons $value $rest))
       (let $now (if (== (fieldOffset $field) 0) True $active)
         (cons (if $now (mkActiveField (fieldIndex $field) $value) (mkInactiveField (fieldIndex $field)))
               (fieldObservationRows $more $rest (and $now (not (== $value 0))))))))))
;;   $schema: schema for the genotype; $instance: raw mkInst. Returns model rows
;;   with inactive descendant coordinates masked instead of learned as choices.
(= (instanceModelView $schema $instance)
   (case (canonicalizeInstance $schema $instance)
     (((mkCEvalError $reason) (mkCEvalError $reason))
      ((mkInst $values) (fieldObservationRows (schemaFields $schema) $values True)))))

;; Raw materialization of validated, canonical instances (useful for decoder
;; tests). Step 6's finalizeContinCandidate reduces before cache/scorer lookup.
;; No Boolean reducer is used. Decoding failures propagate to the shared service.
;;   $children: child subtrees; $values: canonical raw trit vector.
;;   Returns: materialized children or the first decoding error.
(= (continMaterializeChildren $children $values)
   (case $children
     ((() (mkContinChildren ()))
      ((cons $child $rest)
       (case (continCall2 continMaterializeTree $child $values)
         (((mkCEvalError $reason) (mkCEvalError $reason))
          ($tree (case (continMaterializeChildren $rest $values)
                   (((mkCEvalError $failure) (mkCEvalError $failure))
                    ((mkContinChildren $trees) (mkContinChildren (cons $tree $trees))))))))))))
;;   $tree: CTK-annotated AST; $values: canonical flat genotype; returns the
;;   equivalent AST with each knob leaf replaced by its decoded numeric value.
(= (continMaterializeTree $tree $values)
   (case $tree
     (((mkTree (mkCTK $spec $start) ())
       (case (decodeContinSlice $spec (continTake (continDrop $values $start) (continSpecDepth $spec)))
         (((mkCEvalError $reason) (mkCEvalError $reason))
          ((mkCEvalOk $value) (mkTree (mkNode $value) ())))))
      ((mkTree (mkNode $op) $children)
       (case (continMaterializeChildren $children $values)
         (((mkCEvalError $failure) (mkCEvalError $failure))
          ((mkContinChildren $trees) (mkTree (mkNode $op) $trees))))))))
;;   $rep: representation; $instance: candidate genotype. Returns its numeric
;;   materialized representation, or a structured schema/decode error.
(= (materializeContinCandidate $rep $instance)
   (case (continFieldSchema $rep)
     (((mkCEvalError $reason) (mkCEvalError $reason))
      ($schema
       (case (canonicalizeInstance $schema $instance)
         (((mkCEvalError $failure) (mkCEvalError $failure))
          ((mkInst $values)
           (let (mkRep $map $tree) $rep (continMaterializeTree $tree $values)))))))))

;; The default shared batch stores canonical genotypes as well as canonical
;; decoded trees. Invalid vectors remain unchanged so the counted decode-failure
;; path can report/cache them. Explicit callback callers own their input policy.
;;   $schema: validated continuous schema; $rows: evaluated-candidate rows.
;;   Returns: rows with valid genotype instances canonicalized.
(= (continCanonicalRows $schema $rows)
   (case $rows
     ((() ())
      ((cons (mkEvaluatedCandidate $inst $tree $score $status) $rest)
       (let $canonical (case (canonicalizeInstance $schema $inst)
                         (((mkCEvalError $reason) $inst) ($valid $valid)))
         (cons (mkEvaluatedCandidate $canonical $tree $score $status)
               (continCanonicalRows $schema $rest)))))))
;;   $rep: representation supplying schema/owners; $rows: candidate rows to normalize.
;;   Returns canonicalized rows, or leaves them unchanged if schema creation fails.
(= (canonicalizeContinCandidateRows $rep $rows)
   (case (continFieldSchema $rep)
     (((mkCEvalError $reason) $rows)
      ($schema (continCanonicalRows $schema $rows)))))
