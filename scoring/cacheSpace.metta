!(bind! &treeSpace (new-space))
;; Retained only for signature compatibility: scoreTree still accepts a cache
;; space argument, but scoring is now memoized entirely in &subtreeCache below.
;; &bscoreCache is no longer read or written.
!(bind! &bscoreCache (new-space))
;; Subtree-level (columnar) score cache: (subtree <canonicalExpr> <bool-vector>)
;; entries for operator nodes AND label leaves. Keyed by the symbolic
;; expression, so identical subtrees across candidates share an entry. Every
;; subtree — including each tree's root — is memoized here, making this the
;; sole score memo. Persists for the whole run (a run scores one fixed table);
;; it is NOT cleared per generation, mirroring the old &bscoreCache lifetime.
!(bind! &subtreeCache (new-space))

;; Complete candidate scores are cached separately from Boolean subtree values
;; so actual-evaluation accounting can distinguish a new scorer call from reuse
;; of an already scored program. The scoring context is part of the key because
;; one tree can score differently for another table, horizon, or ratio.
!(bind! &candidateScoreCache (new-space))

;; Scores and evaluation status are cached together, including failed calls.
;; () denotes a miss; it is never inferred from the numeric score.
(= (cachedCandidateEvaluation $context $tree)
   (let $matches
        (collapse
          (match &candidateScoreCache
                 (candidateEvaluation $context $tree $score $status)
                 (mkCandidateScore $score $status)))
     (if (== $matches ()) () (car-atom $matches))))

(= (cacheCandidateEvaluation $context $tree (mkCandidateScore $score $status))
   (if (== (cachedCandidateEvaluation $context $tree) ())
       (add-atom &candidateScoreCache
                 (candidateEvaluation $context $tree $score $status))
       True))

;; Legacy score-only API. Attached scores supplied here are already evaluated.
(= (cachedCandidateScore $context $tree)
   (case (cachedCandidateEvaluation $context $tree)
     ((() ()) ((mkCandidateScore $score $status) $score))))
(= (cacheCandidateScore $context $tree $score)
   (cacheCandidateEvaluation $context $tree (mkCandidateScore $score candidateValid)))

;; No tree exists after a decoding failure. Keep these keys separate from the
;; phenotype cache, scoped by representation identity AND value. Callers supply
;; canonical instances (including continuous STOP-tail normalization).
(= (cachedCandidateDecodeFailure $context $rep $id $inst)
   (let $matches
        (collapse (match &candidateScoreCache
          (candidateDecodeFailure $context $rep $id $inst $reason)
          (candidateInvalid $reason)))
     (if (== $matches ()) () (car-atom $matches))))
(= (cacheCandidateDecodeFailure $context $rep $id $inst $reason)
   (if (== (cachedCandidateDecodeFailure $context $rep $id $inst) ())
       (add-atom &candidateScoreCache
         (candidateDecodeFailure $context $rep $id $inst $reason))
       True))

;; Remove every candidate-cache entry supplied by the reset traversal.
(= (removeCandidateScoreEntries ()) True)
(= (removeCandidateScoreEntries (cons $entry $rest))
   (let $_removed (remove-atom &candidateScoreCache $entry)
     (removeCandidateScoreEntries $rest)))

;; Always return a Boolean, including when the cache is already empty, so this
;; reset can be safely sequenced at the beginning of every shared MOSES run.
(= (resetCandidateScoreCache)
   (let $entries
        (collapse (match &candidateScoreCache $entry $entry))
     (removeCandidateScoreEntries $entries)))

;; Empty the subtree cache. A run scores ONE fixed table, and every entry is
;; valid only for that table -- call this before scoring against a DIFFERENT
;; table in the same process (e.g. a test file exercising two tables).
(= (resetSubtreeCache)
   (let $entries (collapse (match &subtreeCache $e $e))
     (map-atom $entries $e (remove-atom &subtreeCache $e))))
