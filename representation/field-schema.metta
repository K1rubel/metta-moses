;; Step 5. Load contin-representation first. Derived metadata, never a second
;; authoritative copy of CTK specs. Schema rows:
;; (mkField index cardinality default owner kind offset start spec)
;; kind = continuous | discrete; discrete fields use offset=0,start=index,spec=().
;; Returns the flat-vector index assigned to one schema field.
;;   $field: mkField row. Returns its zero-based flat coordinate index.

(= (fieldIndex (mkField $i $card $def $owner $kind $offset $start $spec)) $i)

;; Returns the category count for one schema field.
;;   $field: mkField row. Returns the number of legal values for its coordinate.

(= (fieldCardinality (mkField $i $card $def $owner $kind $offset $start $spec)) $card)

;; Returns the initial/default category for one schema field.
;;   $field: mkField row. Returns the category used to build a default instance.

(= (fieldDefault (mkField $i $card $def $owner $kind $offset $start $spec)) $def)

;; Returns the stable identity shared by all coordinates of a continuous knob.
;;   $field: mkField row. Returns the owning node/path identity.

(= (fieldOwner (mkField $i $card $def $owner $kind $offset $start $spec)) $owner)

;; Identifies whether a schema coordinate is continuous or an ordinary discrete field.
;;   $field: mkField row. Returns continuous or discrete.

(= (fieldKind (mkField $i $card $def $owner $kind $offset $start $spec)) $kind)

;; Returns this coordinate's position within its owner's continuous trit slice.
;;   $field: mkField row. Returns a zero-based offset; discrete fields use 0.

(= (fieldOffset (mkField $i $card $def $owner $kind $offset $start $spec)) $offset)

;; Returns the first flat index belonging to this field's continuous knob.
;;   $field: mkField row. Returns the slice start; a discrete field starts at its own index.

(= (fieldStart (mkField $i $card $def $owner $kind $offset $start $spec)) $start)

;; Returns the continuous decoding specification attached to a field.
;;   $field: mkField row. Returns its ContinSpec, or () for a discrete field.

(= (fieldSpec (mkField $i $card $def $owner $kind $offset $start $spec)) $spec)

;; Returns how many coordinates are governed by this field's knob specification.
;;   $field: mkField row. Returns its trit depth for continuous fields, otherwise 1.

(= (fieldDepth $field) (if (== (fieldKind $field) continuous) (continSpecDepth (fieldSpec $field)) 1))

;; Describes the activation condition for this coordinate in a continuous slice.
;;   $field: mkField row. Returns alwaysActive at the slice root, otherwise an
;;   afterNonStop rule containing this slice's start and the coordinate index.

(= (fieldActivation $field)
   (if (== (fieldOffset $field) 0) alwaysActive (afterNonStop (fieldStart $field) (fieldIndex $field))))

;; Lists flat coordinate indices in an integer interval.
;;   $start: First index to include. $end: Exclusive upper bound.
;;   Returns the ordered list [$start, ..., $end - 1], or () when equal.

(= (fieldPriorIndices $start $end)
   (if (== $start $end) () (cons $start (fieldPriorIndices (+ $start 1) $end))))

;; Returns the earlier coordinates that determine whether a field is active.
;;   $field: mkField row. Returns indices from the owner's slice start up to,
;;   but not including, this field's index. A root field has no activation parents.

(= (fieldActivationParents $field)
   (fieldPriorIndices (fieldStart $field) (fieldIndex $field)))

;; Extracts the ordered fields stored in a schema record.
;;   $schema: mkFieldSchema record. Returns its ordered mkField rows.

(= (schemaFields (mkFieldSchema $fields)) $fields)

;; Builds the schema rows for the remaining positions of one continuous knob.
;;   $owner: Stable identity of the constant represented by the knob.
;;   $spec: ContinSpec providing depth and geometric decoding parameters.
;;   $start: First flat-vector index reserved for this knob.
;;   $offset: Current zero-based position within the knob.
;;   Returns ordered ternary mkField rows from $offset to the end of the slice.

(= (continFieldSlice $owner $spec $start $offset)
   (if (== $offset (continSpecDepth $spec)) ()
       (cons (mkField (+ $start $offset) 3 0 $owner continuous $offset $start $spec)
             (continFieldSlice $owner $spec $start (+ $offset 1)))))

;; Collect CTKs and their real tree paths; an owner cannot be forged by editing
;; the raw map. Wrong starts/overlaps/missing/extra/reordered fields all fail.
;; Invokes the selected owner-collection walker on a subtree.
;;   $fun: Walker callback to invoke.
;;   $tree: Current representation subtree.
;;   $path: Ordered child indices locating the subtree from the root.
;;   Returns the selected callback's result for that subtree and path.

(= (continOwnerCall $fun $tree $path) ($fun $tree $path))

;; Collects continuous-knob owners below a parent's ordered children.
;;   $children: Ordered child subtree list.
;;   $path: Child-index path of the parent.
;;   $index: Index to assign to the next child in that path.
;;   Returns owners in tree order, or InvalidTree/another propagated tree error.

(= (continCollectChildren $children $path $index)
   (case $children
     (
      (() (mkContinOwners ()))
      ((cons $child $rest)
       (case (continOwnerCall continCollectOwners $child (continAppend $path ($index)))
         (
          ((mkCEvalError $reason) (mkCEvalError $reason))
          ((mkContinOwners $owners)
           (case (continCollectChildren $rest $path (+ $index 1))
             (
              ((mkCEvalError $failure) (mkCEvalError $failure))
              ((mkContinOwners $more) (mkContinOwners (continAppend $owners $more)))))))))
      ($bad (mkCEvalError "InvalidTree")))))

;; Validates an annotated subtree while collecting its continuous knob owners.
;;   $tree: Subtree of the annotated representation AST.
;;   $path: Root-to-node child-index path used as the stable knob identity.
;;   Returns ordered (owner, spec, start) records, or InvalidTree/InvalidContinSpec.

(= (continCollectOwners $tree $path)
   (case $tree
     (
      ((mkTree (mkCTK $spec $start) ())
        (if (and (continSpecValid $spec) (continNatural $start))
            (mkContinOwners ((mkContinOwner (mkNodeId $path) $spec $start)))
            (mkCEvalError "InvalidContinSpec")))
      ((mkTree (mkNode $value) $children) (continCollectChildren $children $path 1))
      ($bad (mkCEvalError "InvalidTree")))))

;; Expands tree-ordered knob owners into consecutive continuous schema slices.
;;   $owners: Ordered mkContinOwner records collected from the AST.
;;   $next: Flat-vector index required as the next knob's starting coordinate.
;;   Returns a mkFieldSchema covering contiguous slices or InvalidFieldSlices.

(= (continOwnersSchema $owners $next)
   (case $owners
     (
      (() (mkFieldSchema ()))
      ((cons (mkContinOwner $owner $spec $start) $rest)
       (if (== $start $next)
           (case (continOwnersSchema $rest (+ $next (continSpecDepth $spec)))
             (
              ((mkCEvalError $reason) (mkCEvalError $reason))
              ((mkFieldSchema $more) (mkFieldSchema (continAppend (continFieldSlice $owner $spec $start 0) $more)))))
           (mkCEvalError "InvalidFieldSlices"))))))

;; Reconstructs the raw trit-map entries represented by continuous schema rows.
;;   $fields: Ordered expanded continuous mkField rows.
;;   Returns raw-map entries with ternary cardinality and owner/offset keys.

(= (continSchemaRaw $fields)
   (case $fields
     (
      (() ())
      ((cons $field $rest)
       (cons ((mkDiscSpec 3) (mkContinTritField (fieldOwner $field) (fieldOffset $field)))
             (continSchemaRaw $rest))))))

;; Derives and cross-checks the continuous schema for a representation.
;;   $rep: mkRep containing a raw discrete map and CTK-annotated tree.
;;   Returns the tree-derived schema when its raw map matches exactly; otherwise
;;   returns a structured representation, tree, spec, slice, or map error.

(= (continFieldSchema $rep)
   (case $rep
     (
      ((mkRep (mkKbMap (mkDscMp $raw)) $tree)
            (case (continCollectOwners $tree ())
               (
                ((mkCEvalError $reason) (mkCEvalError $reason))
                ((mkContinOwners $owners)
                  (case (continOwnersSchema $owners 0)
                      (
                        ((mkCEvalError $failure) (mkCEvalError $failure))
                        ((mkFieldSchema $fields)
                            (if (== $raw (continSchemaRaw $fields)) 
                                (mkFieldSchema $fields)
                                (mkCEvalError "InvalidRawFieldMap")))))))))
      ($bad (mkCEvalError "InvalidContinuousRepresentation")))))

;; Generic schema validation allows heterogeneous independent discrete fields
;; alongside whole continuous slices; population algorithms need not assume 3.
;;   $card: category count; $def: default category index.
;;   Returns: True when the finite discrete coordinate has a legal default.

(= (fieldDiscreteValid $card $def)
   (if (and (continInteger $card) (continNatural $def))
       (and (> $card 0) (< $def $card)) False))

;;   $fields: remaining schema rows to validate.
;;   $index: flat coordinate index expected for the first remaining row.
;;   $seen: owner identities already validated, used to reject duplicate slices.
;;   Returns whether ordering, slice layout, cardinalities and owners are valid.

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
;;   $schema: candidate mkFieldSchema record to check.
;;   Returns True only when every field and continuous slice is structurally valid.

(= (fieldSchemaValid $schema)
   (case $schema (((mkFieldSchema $fields) (fieldRowsValid $fields 0 ())) ($bad False))))

;; Adapter for existing discrete maps. Obtain effective cardinality and default
;; from knob accessors, verifying the raw key agrees. No Boolean/action edits.
;;   $rows: raw discrete-map entries; $index: index assigned to the next row.
;;   Returns: a validated mkFieldSchema or mkCEvalError.

(= (discreteSchemaRows $rows $index)
   (case $rows
     (
      (() (mkFieldSchema ()))
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

;;   $map: raw mkDscMp discrete map to adapt.
;;   Returns its validated mkFieldSchema, or InvalidRawFieldMap for the wrong shape.

(= (discreteFieldSchema $map)
   (case $map (((mkDscMp $rows) (discreteSchemaRows $rows 0)) ($bad (mkCEvalError "InvalidRawFieldMap")))))

;;   $fields: ordered schema rows describing the candidate's coordinates.
;;   $values: candidate category indices in the same order as $fields.
;;   Returns True only when lengths match and every value is in range.

(= (fieldValuesValid $fields $values)
   (case ($fields $values)
     (
      ((() ()) True)
      (((cons $field $more) (cons $value $rest))
       (if (continNatural $value)
           (if (< $value (fieldCardinality $field)) (fieldValuesValid $more $rest) False) False))
      ($bad False))))

;;   $fields: ordered schema rows being canonicalized.
;;   $values: raw category values corresponding positionally to $fields.
;;   $active: whether the preceding coordinate in the current continuous slice
;;   was nonzero; slice roots restart as active. 
;;    Returns canonical category values.

(= (fieldCanonicalValues $fields $values $active)
   (case ($fields $values)
     (
      ((() ()) ())
      (((cons $field $more) (cons $value $rest))
       (let $now (if (== (fieldOffset $field) 0) True $active)
         (cons (if $now $value 0)
               (fieldCanonicalValues $more $rest (and $now (not (== $value 0))))))))))

;;   $schema: field schema that defines coordinate order and activation slices.
;;   $instance: raw mkInst candidate whose values will be checked and normalized.
;;   Returns a canonical mkInst, or InvalidFieldSchema/InvalidInstance.

(= (canonicalizeInstance $schema $instance)
   (if (fieldSchemaValid $schema)
       (case $instance
         (((mkInst $values)
           (if (fieldValuesValid (schemaFields $schema) $values)
               (mkInst (fieldCanonicalValues (schemaFields $schema) $values True))
               (mkCEvalError "InvalidInstance")))
          ($bad (mkCEvalError "InvalidInstance"))))
       (mkCEvalError "InvalidFieldSchema")))

;;   $fields: ordered schema rows for which defaults are requested.
;;   Returns a value list containing each row's declared default category.

(= (fieldDefaults $fields)
   (case $fields ((() ()) ((cons $field $rest) (cons (fieldDefault $field) (fieldDefaults $rest))))))

;;   $schema: field schema to validate and initialize.
;;   Returns an mkInst of declared defaults, or InvalidFieldSchema.

(= (schemaDefaultInstance $schema)
   (if (fieldSchemaValid $schema) (mkInst (fieldDefaults (schemaFields $schema))) (mkCEvalError "InvalidFieldSchema")))

;; Model observations distinguish active STOP from deterministic inactive zero.
;; Inactive observations must be masked as CHILDREN, but remain an explicit
;; category when used as PARENTS by later BOA/hBOA model code.
;;   $fields: ordered schema rows whose activation states are being observed.
;;   $values: canonical coordinate values corresponding to $fields.
;;   $active: whether the current continuous prefix is live when this slice begins.
;;   Returns active-value or inactive-mask observation rows for the model.

(= (fieldObservationRows $fields $values $active)
   (case ($fields $values)
     (((() ()) ())
      (((cons $field $more) (cons $value $rest))
       (let $now (if (== (fieldOffset $field) 0) True $active)
         (cons (if $now (mkActiveField (fieldIndex $field) $value) (mkInactiveField (fieldIndex $field)))
               (fieldObservationRows $more $rest (and $now (not (== $value 0))))))))))

;;   $schema: field schema defining the genotype's coordinates and activation.
;;   $instance: raw mkInst candidate to validate and expose to the model.
;;   Returns model rows with inactive descendants masked, or a validation error.

(= (instanceModelView $schema $instance)
   (case (canonicalizeInstance $schema $instance)
     (((mkCEvalError $reason) (mkCEvalError $reason))
      ((mkInst $values) (fieldObservationRows (schemaFields $schema) $values True)))))

;; Raw materialization of validated, canonical instances (useful for decoder
;; tests). Step 6's finalizeContinCandidate reduces before cache/scorer lookup.
;; No Boolean reducer is used. Decoding failures propagate to the shared service.
;;   $children: ordered child subtrees to recursively materialize.
;;   $values: canonical flat trit vector shared by all continuous leaves.
;;   Returns materialized child trees, or the first decoding error encountered.

(= (continMaterializeChildren $children $values)
   (case $children
     ((() (mkContinChildren ()))
      ((cons $child $rest)
       (case (continCall2 continMaterializeTree $child $values)
         (((mkCEvalError $reason) (mkCEvalError $reason))
          ($tree (case (continMaterializeChildren $rest $values)
                   (((mkCEvalError $failure) (mkCEvalError $failure))
                    ((mkContinChildren $trees) (mkContinChildren (cons $tree $trees))))))))))))

;;   $tree: CTK-annotated representation subtree to materialize.
;;   $values: canonical flat genotype containing the trits for its knob leaves.
;;   Returns the equivalent AST with each CTK leaf replaced by its decoded number.

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

;;   $rep: continuous representation containing its raw map and annotated tree.
;;   $instance: candidate mkInst of encoded coordinate values.
;;   Returns the numeric materialized representation, or a schema/decode error.

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
;;   $schema: validated continuous schema used to canonicalize genotypes.
;;   $rows: evaluated-candidate records to normalize before shared batch storage.
;;   Returns rows with valid instances canonicalized; invalid instances stay intact.

(= (continCanonicalRows $schema $rows)
   (case $rows
     ((() ())
      ((cons (mkEvaluatedCandidate $inst $tree $score $status) $rest)
       (let $canonical (case (canonicalizeInstance $schema $inst)
                         (((mkCEvalError $reason) $inst) ($valid $valid)))
         (cons (mkEvaluatedCandidate $canonical $tree $score $status)
               (continCanonicalRows $schema $rest)))))))

;;   $rep: continuous representation from which to derive and validate the schema.
;;   $rows: evaluated-candidate records whose genotypes may need normalization.
;;   Returns canonicalized rows, or unchanged rows if schema construction fails.

(= (canonicalizeContinCandidateRows $rep $rows)
   (case (continFieldSchema $rep)
     (((mkCEvalError $reason) $rows)
      ($schema (continCanonicalRows $schema $rows)))))
