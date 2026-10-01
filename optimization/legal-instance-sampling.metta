;; Step 5. Load field-schema and optimizer-runtime first.
;; Prior: each continuous owner independently chooses a uniform prefix LENGTH
;; from 0..depth, then fair LEFT/RIGHT within that prefix, then STOP padding.
;; This is NOT uniform over legal vectors or decoded numbers. Discrete fields
;; use their schema cardinality. Every draw threads the shared explicit RNG.
(= (legalSamplingFieldsValid $fields)
   (case $fields
     ((() True)
      ((cons $field $rest)
       (if (and (<= (fieldCardinality $field) 2147483646) (< (fieldDepth $field) 2147483646))
           (legalSamplingFieldsValid $rest) False)))))
(= (legalSamplingRngValid $rng)
   (if (continNatural $rng) (and (> $rng 0) (< $rng 2147483647)) False))
(= (legalDraw $low $high $rng)
   (if (== $low $high) ($low $rng) (optimizerRandomInt $low $high $rng)))
(= (sampleContinPrefix $length $rng)
   (if (== $length 0) (mkSampleValues () $rng)
       (let* ((($value $next) (legalDraw 1 2 $rng))
              ((mkSampleValues $tail $end) (sampleContinPrefix (- $length 1) $next)))
         (mkSampleValues (cons $value $tail) $end))))
(= (sampleLegalFields $fields $rng)
   (case $fields
     ((() (mkSampleValues () $rng))
      ((cons $field $rest)
       (if (== (fieldKind $field) continuous)
           (let* (($depth (fieldDepth $field))
                  (($length $next) (legalDraw 0 $depth $rng))
                  ((mkSampleValues $prefix $afterPrefix) (sampleContinPrefix $length $next))
                  ((mkSampleValues $suffix $end) (sampleLegalFields (continDrop $fields $depth) $afterPrefix)))
             (mkSampleValues (continAppend $prefix (continAppend (continRepeat 0 (- $depth $length)) $suffix)) $end))
           (let* ((($value $nextDiscrete) (legalDraw 0 (- (fieldCardinality $field) 1) $rng))
                  ((mkSampleValues $tail $last) (sampleLegalFields $rest $nextDiscrete)))
             (mkSampleValues (cons $value $tail) $last)))))))
(= (sampleLegalInstance $schema $rng)
   (if (fieldSchemaValid $schema)
       (if (and (legalSamplingFieldsValid (schemaFields $schema)) (legalSamplingRngValid $rng))
           (let (mkSampleValues $values $next) (sampleLegalFields (schemaFields $schema) $rng)
             (mkLegalSample (mkInst $values) $next))
           (mkCEvalError "InvalidSamplingConfiguration"))
       (mkCEvalError "InvalidFieldSchema")))

;; Bounded UNIQUE initialization. Defaults once, then at most maxAttempts fresh
;; draws (duplicates count). No rejection by phenotype/score, no hidden scorer
;; calls. Models/consumers must scope these instances to their representation.
(= (legalPopulationFill $fields $wanted $left $rng $rows $count $proposals)
   (if (>= $count $wanted) (mkLegalPopulation $rows $rng $proposals sampleComplete)
       (if (== $left 0) (mkLegalPopulation $rows $rng $proposals sampleAttemptsExhausted)
           (let* (((mkSampleValues $values $next) (sampleLegalFields $fields $rng))
                  ($inst (mkInst $values))
                  ($duplicate (continContains $inst $rows)))
             (legalPopulationFill $fields $wanted (- $left 1) $next
               (if $duplicate $rows (continAppend $rows ($inst)))
               (if $duplicate $count (+ $count 1)) (+ $proposals 1))))))
(= (sampleLegalPopulation $schema $wanted $maxAttempts $rng)
   (if (fieldSchemaValid $schema)
       (if (and (and (continNatural $wanted) (continNatural $maxAttempts))
                (and (legalSamplingRngValid $rng) (legalSamplingFieldsValid (schemaFields $schema))))
           (if (== $wanted 0) (mkLegalPopulation () $rng 0 sampleComplete)
               (legalPopulationFill (schemaFields $schema) $wanted $maxAttempts $rng
                 ((schemaDefaultInstance $schema)) 1 0))
           (mkCEvalError "InvalidSamplingConfiguration"))
       (mkCEvalError "InvalidFieldSchema")))
(= (legalSampleInstance (mkLegalSample $inst $rng)) $inst)
(= (legalSampleRng (mkLegalSample $inst $rng)) $rng)
(= (legalPopulationInstances (mkLegalPopulation $rows $rng $proposals $reason)) $rows)
(= (legalPopulationRng (mkLegalPopulation $rows $rng $proposals $reason)) $rng)
(= (legalPopulationProposals (mkLegalPopulation $rows $rng $proposals $reason)) $proposals)
(= (legalPopulationReason (mkLegalPopulation $rows $rng $proposals $reason)) $reason)
