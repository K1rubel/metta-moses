;; =============================================================================
;; build-action.metta
;;
;; Port of the action knob-building section of C++ build_knobs.cc (lines 1096–1239).
;; All functions here operate on the action / PetBrain sub-domain.
;;
;; Structural action operators handled (mirrors full id::action enum):
;;   and_seq (sequential_and)   — recursed by buildAction
;;   action_bool_if              — recursed by buildAction
;;   or_seq, seq_exec, action_not, bool_action_if, contin_action_if,
;;   action_action_if, action_success, action_failure, action_while,
;;   bool_while, return_success, repeat_n  — leaf ops (pass-through)
;;
;; Extracted from build-logical.metta to keep boolean and action logic separate.
;; =============================================================================

;; -----------------------------------------------------------------
;; randElement — pick a uniformly random element from a list
;; -----------------------------------------------------------------
(= (randElement $list)
   (if (== $list ())
       ()
       (let* (($len (length $list))
              ($idx (py-call (random.randint 0 (- $len 1)))))
         (List.getByIdx $list $idx))))

;; -----------------------------------------------------------------
;; randint — random integer in [0, $max] inclusive
;; -----------------------------------------------------------------
(= (randint $max) (py-call (random.randint 0 $max)))

;; -----------------------------------------------------------------
;; sampleActionPerms — port of C++ build_knobs::sample_action_perms
;;
;; Creates perms from all $actions plus up to $n random action_bool_if combos
;; using $perceptions for the condition. The action pairs are sampled without
;; replacement from the C++ ordered-pair index space n*(n-1).
;; -----------------------------------------------------------------
(= (sampleActionPerms $actions $perceptions)
   (sampleActionPerms $actions $perceptions (length $actions)))

(= (sampleActionPerms $actions $perceptions $n)
   (let $actionCount (length $actions)
     (if (or (== $n 0) (== $perceptions ()) (< $actionCount 2))
         $actions
         (let*
           (
             ($pairCount (* $actionCount (- $actionCount 1)))
             ($sampleCount (if (> $n $pairCount) $pairCount $n))
             ($pairIdxs (lazyRandomSelector 0 (- $pairCount 1) $sampleCount))
             ($pairs (actionPairsFromIndexes $pairIdxs $perceptions $actions $actionCount))
           )
           (concatT $actions $pairs)))))

;; actionPairFromIndex — map C++ lazy_random_selector index to an ordered pair.
(= (actionPairFromIndex $perceptions $actions $actionCount $pairIdx)
   (let*
     (
       ($width (- $actionCount 1))
       ($aIdx (int (/ $pairIdx $width)))
       ($bRaw (- $pairIdx (* $aIdx $width)))
       ($bIdx (if (== $bRaw $aIdx) (- $actionCount 1) $bRaw))
       ($perception (randElement $perceptions))
       ($actA (List.getByIdx $actions $aIdx))
       ($actB (List.getByIdx $actions $bIdx))
     )
     (action_bool_if $perception $actA $actB)))

(= (actionPairsFromIndexes () $perceptions $actions $actionCount) ())
(= (actionPairsFromIndexes (cons $pairIdx $rest) $perceptions $actions $actionCount)
   (cons (actionPairFromIndex $perceptions $actions $actionCount $pairIdx)
         (actionPairsFromIndexes $rest $perceptions $actions $actionCount)))

;; -----------------------------------------------------------------
;; addActionKnobsAt — port of C++ build_knobs::add_action_knobs
;;
;; Samples action perms, creates a single ASK containing all perms,
;; probes it, and inserts into the MMap.
;; -----------------------------------------------------------------
(= (addActionKnobsAt $tree $probeRootId (mkNodeId $tgtId) $addIfInExemplar $MMap $actions $perceptions)
   (let*
     (
       ($perms     (sampleActionPerms $actions $perceptions))
       ($treePerms (map-atom $perms $perm (buildTree $perm)))
       (($knobs $updatedTree) (actionProbe $tree (mkNodeId $tgtId) $treePerms $addIfInExemplar ()))
       ($pairs     (pairKnobWithSpec $knobs))
       ($mmp       (expToMMap $pairs $MMap discSpec<))
     )
     ($updatedTree $mmp)))

;; -----------------------------------------------------------------
;; addSimpleActionKnobsAt — port of C++ build_knobs::add_simple_action_knobs
;;
;; Creates an ASK over the existing subtree at $tgtId. Unlike actionProbe,
;; this does not append a placeholder; default/current are present.
;; -----------------------------------------------------------------
(= (addSimpleActionKnobsAt $tree $probeRootId (mkNodeId $tgtId) $addIfInExemplar $MMap $actions $perceptions)
   (let*
     (
       ($subtree   (getNodeById $tree (mkNodeId $tgtId)))
       (($knobs $updatedTree) (simpleActionProbe $tree (mkNodeId $tgtId) $subtree $addIfInExemplar ()))
       ($pairs     (pairKnobWithSpec $knobs))
       ($mmp       (expToMMap $pairs $MMap discSpec<))
     )
     ($updatedTree $mmp)))

;; -----------------------------------------------------------------
;; processActionChildAt — process one child of a sequential_and node
;;
;; Port of the inner loop in C++ build_action for and_seq (line 1126–1139).
;;   • builtin action  → with prob (100-p)% add simple knob,
;;                       else wrap in and_seq and add action knobs
;;   • action_bool_if  → with prob (100-p)% add simple knob, then recurse;
;;                       always recurse (mirrors C++ unconditional build_action)
;;   • other           → unchanged
;; -----------------------------------------------------------------
(= (processActionChildAt $tree (mkNodeId $parentId) (mkNodeId $childId) $child $MMap $actions $perceptions $p)
   (let (mkTree (mkNode $childOp) $_) $child
      (if (isBuiltinAction $childOp $actions)
          (if (> (randint 99) $p)
              (addSimpleActionKnobsAt $tree $parentId (mkNodeId $childId) True $MMap $actions $perceptions)
              (let $wrappedTree (insertNodeAtPosition $tree (mkNodeId $childId) (mkNode and_seq))
                 (addActionKnobsAt $wrappedTree $parentId (mkNodeId $childId) False $MMap $actions $perceptions)))
          (if (== $childOp action_bool_if)
              (if (>= (randint 99) $p)
                  (let ($t1 $m1) (addSimpleActionKnobsAt $tree $parentId (mkNodeId $childId) True $MMap $actions $perceptions)
                      (buildAction $t1 (mkNodeId $childId) $m1 $actions $perceptions))
                  (buildAction $tree (mkNodeId $childId) $MMap $actions $perceptions))
              ($tree $MMap)))))

;; -----------------------------------------------------------------
;; processActionChildren — iterate over all children of and_seq
;; -----------------------------------------------------------------
(= (processActionChildren $tree (mkNodeId $parentId) () $childIdx $MMap $actions $perceptions $p)
   ($tree $MMap))

(= (processActionChildren $tree (mkNodeId $parentId) (cons $child $rest) $childIdx $MMap $actions $perceptions $p)
   (let*
     (
       ($childId (if (== $parentId (0)) ($childIdx) (concatT $parentId ($childIdx))))
       (($t1 $m1) (processActionChildAt $tree (mkNodeId $parentId) (mkNodeId $childId) $child $MMap $actions $perceptions $p))
     )
     (processActionChildren $t1 (mkNodeId $parentId) $rest (+ $childIdx 1) $m1 $actions $perceptions $p)))

;; -----------------------------------------------------------------
;; processActionBoolIfChildAt — process one child of action_bool_if
;;
;; Port of the inner loop in C++ build_action for action_boolean_if
;; (line 1145–1152). Skips the first child (perception index 1).
;; For remaining children:
;;   • builtin action  → wrap in and_seq and add action knobs
;;   • and_seq         → recurse via buildAction
;;   • other           → unchanged
;; -----------------------------------------------------------------
(= (processActionBoolIfChildAt $tree (mkNodeId $parentId) (mkNodeId $childId) $child $MMap $actions $perceptions)
   (let (mkTree (mkNode $childOp) $_) $child
      (if (isBuiltinAction $childOp $actions)
          (let
            $wrappedTree (insertNodeAtPosition $tree (mkNodeId $childId) (mkNode and_seq))
            (addActionKnobsAt $wrappedTree $parentId (mkNodeId $childId) False $MMap $actions $perceptions))
          (if (== $childOp and_seq)
              (buildAction $tree (mkNodeId $childId) $MMap $actions $perceptions)
              ($tree $MMap)))))

;; -----------------------------------------------------------------
;; processActionBoolIfChildren — iterate over children of action_bool_if
;; starting from child index 2 (skip perception at index 1).
;; -----------------------------------------------------------------
(= (processActionBoolIfChildren $tree (mkNodeId $parentId) () $childIdx $MMap $actions $perceptions)
   ($tree $MMap))

(= (processActionBoolIfChildren $tree (mkNodeId $parentId) (cons $child $rest) $childIdx $MMap $actions $perceptions)
   (if (== $childIdx 1)
       (processActionBoolIfChildren $tree (mkNodeId $parentId) $rest (+ $childIdx 1) $MMap $actions $perceptions)
       (let*
         (
           ($childId (if (== $parentId (0)) ($childIdx) (concatT $parentId ($childIdx))))
           (($t1 $m1) (processActionBoolIfChildAt $tree (mkNodeId $parentId) (mkNodeId $childId) $child $MMap $actions $perceptions))
         )
         (processActionBoolIfChildren $t1 (mkNodeId $parentId) $rest (+ $childIdx 1) $m1 $actions $perceptions))))

;; -----------------------------------------------------------------
;; buildActionAndSeq — handle sequential_and nodes
;;
;; Port of C++ build_action for id::sequential_and (lines 1121–1143).
;;   1. Maybe add action knobs at this node (if childless or random < p)
;;   2. Process children
;;   3. Maybe append a new and_seq child with knobs
;; -----------------------------------------------------------------
(= (buildActionAndSeq $tree (mkNodeId $nodeId) $children $MMap $actions $perceptions)
   (let $p 80
    (if (or (== $children ()) (< (randint 99) $p))
        (let*
          (
            (($t1 $m1) (addActionKnobsAt $tree (mkNodeId $nodeId) (mkNodeId $nodeId) True $MMap $actions $perceptions))
            (($t2 $m2) (processActionChildren $t1 (mkNodeId $nodeId) $children 1 $m1 $actions $perceptions $p))
          )
          (if (>= (randint 99) $p)
              (let*
                (
                  ($builtTree  (buildTree (and_seq)))
                  (($t3 $newId) (appendChild $t2 (mkNodeId $nodeId) $builtTree))
                )
                (addActionKnobsAt $t3 (mkNodeId $nodeId) $newId False $m2 $actions $perceptions))
              ($t2 $m2)))
        (let ($t1 $m1) (processActionChildren $tree (mkNodeId $nodeId) $children 1 $MMap $actions $perceptions $p)
          (if (>= (randint 99) $p)
              (let*
                (
                  ($builtTree  (buildTree (and_seq)))
                  (($t2 $newId) (appendChild $t1 (mkNodeId $nodeId) $builtTree))
                )
                (addActionKnobsAt $t2 (mkNodeId $nodeId) $newId False $m1 $actions $perceptions))
              ($t1 $m1))))))

;; -----------------------------------------------------------------
;; buildActionBoolIf — handle action_bool_if nodes
;;
;; Port of C++ build_action for id::action_boolean_if (line 1145–1152).
;; Processes children after the first (perception).
;; -----------------------------------------------------------------
(= (buildActionBoolIf $tree (mkNodeId $nodeId) $children $MMap $actions $perceptions)
   (processActionBoolIfChildren $tree (mkNodeId $nodeId) $children 1 $MMap $actions $perceptions))

;; -----------------------------------------------------------------
;; buildAction — port of C++ build_knobs::build_action (lines 1116–1153)
;;
;; Dispatch on node type:
;;   and_seq           → buildActionAndSeq
;;   action_bool_if    → buildActionBoolIf
;;   other             → unchanged
;; -----------------------------------------------------------------
(= (buildAction $tree (mkNodeId $nodeId) $MMap $actions $perceptions)
  (let $subtree (getNodeById $tree (mkNodeId $nodeId))
    (if (isNullVertex $subtree)
        ($tree $MMap)
        (let (mkTree (mkNode $op) $_) $subtree
          (if (== $op and_seq)
              (let $children (getChildren $subtree)
                (buildActionAndSeq $tree (mkNodeId $nodeId) $children $MMap $actions $perceptions))
              (if (== $op action_bool_if)
                  (let $children (getChildren $subtree)
                    (buildActionBoolIf $tree (mkNodeId $nodeId) $children $MMap $actions $perceptions))
                  ($tree $MMap)))))))

;; -----------------------------------------------------------------
;; actionCleanup — remove childless sequential_and / sequential_or /
;;                   sequential_exec nodes
;;
;; Port of C++ build_knobs::action_cleanup (lines 1229–1239).
;;   if ((*it == sequential_and || *it == sequential_or || *it == sequential_exec)
;;       && it.is_childless())
;;     erase(it);
;;
;; Post-build pass that removes empty action operator nodes (bottom-up).
;; C++ uses post_order_iterator which naturally processes leaves first;
;; the recursive descent here is equivalent.
;;
;; NOTE: C++ also resets the root to sequential_and if the tree becomes
;; empty — we return mkNullVex here and the caller (buildKnobs) handles
;; this edge case by keeping the original exemplar.
;; -----------------------------------------------------------------
(= (isCleanupActionOperator $op)
   (is-member $op (and_seq or_seq seq_exec)))

(= (actionCleanup $tree)
   (let ($cleaned $keep) (actionCleanupNode $tree)
     (if $keep $cleaned (mkNullVex ()))))

(= (actionCleanupNode (mkNullVex $children))
   ((mkNullVex $children) True))

(= (actionCleanupNode (mkTree (mkNode $rootOp) $children))
   (let $cleanedChildren (actionCleanupChildren $children)
     (if (and (== $cleanedChildren ()) (isCleanupActionOperator $rootOp))
         ((mkNullVex ()) False)
         ((mkTree (mkNode $rootOp) $cleanedChildren) True))))

(= (actionCleanupChildren ()) ())
(= (actionCleanupChildren (cons $child $rest))
   (let*
     (
       (($cleanedChild $keep) (actionCleanupNode $child))
       ($cleanedRest (actionCleanupChildren $rest))
     )
     (if $keep
         (cons $cleanedChild $cleanedRest)
         $cleanedRest)))

;; -----------------------------------------------------------------
;; actionCanonize — canonizes an action tree.
;;
;; Mirrors build_knobs::action_canonize (build_knobs.cc:1099-1113).
;; If the root of the tree is not 'and_seq', inserts 'and_seq' above it.
;; -----------------------------------------------------------------
(= (actionCanonize $tree)
   (let (mkTree (mkNode $rootOp) $children) $tree
     (if (== $rootOp and_seq)
         $tree
         (insertNodeAtPosition $tree (mkNodeId (0)) (mkNode and_seq)))))
