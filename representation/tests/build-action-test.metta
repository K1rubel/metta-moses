!(import! &self ../../utilities/general-helpers)
!(import! &self ../../utilities/list-methods)
!(import! &self ../../utilities/ordered-multimap)
!(import! &self ../../utilities/lazy-random-selector)
!(import! &self ../../utilities/nodeId)
!(import! &self ../../utilities/tree)

!(import! &self ../../scoring/bscore)

!(import! &self ../../representation/knob-representation)
!(import! &self ../../representation/lsk)
!(import! &self ../../representation/logical-probe)
!(import! &self ../../representation/sample-logical-perms)
!(import! &self ../../representation/add-logical-knobs)
!(import! &self ../../representation/build-logical)
!(import! &self ../../representation/build-knobs)
!(import! &self ../../representation/build-action)


!(py-call (random.seed 42))

;; ===========================================================================
;; isActionOperator
;; ===========================================================================
!(assertEqual (isActionOperator and_seq) True)
!(assertEqual (isActionOperator action_bool_if) True)
;; Newly added structural operators
!(assertEqual (isActionOperator or_seq) True)
!(assertEqual (isActionOperator seq_exec) True)

;; Domain actions must NOT be considered action operators
!(assertEqual (isActionOperator move_forward) False)
!(assertEqual (isActionOperator turn_left) False)

;; ===========================================================================
;; isBuiltinAction
;; ===========================================================================
!(assertEqual (isBuiltinAction move_forward) True)
!(assertEqual (isBuiltinAction turn_left) True)
!(assertEqual (isBuiltinAction and_seq) False)
!(assertEqual (isBuiltinAction action_bool_if) False)

;; ===========================================================================
;; sampleActionPerms — returns all actions plus random pairs
;; ===========================================================================
!(assertEqual
  (let $perms (sampleActionPerms (move_forward turn_left) (A B))
    (and (is-member move_forward $perms)
         (is-member turn_left $perms)))
  True)

;; ===========================================================================
;; addActionKnobsAt — creates ASK and inserts into MMap
;; ===========================================================================
!(assertEqual
  (let ($tree $mmp) (addActionKnobsAt (mkTree (mkNode and_seq) ()) (mkNodeId (0)) (mkNodeId (0)) True () (move_forward turn_left) (A B))
    (> (MultiMap.length $mmp) 0))
  True)

;; ===========================================================================
;; addSimpleActionKnobsAt — creates ASK for existing child
;; ===========================================================================
!(assertEqual
  (let ($tree $mmp) (addSimpleActionKnobsAt (mkTree (mkNode and_seq) (cons (mkTree (mkNode move_forward) ()) ())) (mkNodeId (0)) (mkNodeId (1)) True () (move_forward turn_left) (A B))
    (> (MultiMap.length $mmp) 0))
  True)

;; ===========================================================================
;; actionProbe — empty perms returns knobs and tree unchanged
;; ===========================================================================
!(assertEqual
  (let $r (actionProbe (mkTree (mkNode and_seq) ()) (mkNodeId (0)) () True ())
    (== $r (() (mkTree (mkNode and_seq) ()))))
  True)

;; ===========================================================================
;; actionProbe — single perm → tree gains a null_vex child
;; ===========================================================================
!(assertEqual
  (let* (($tree (mkTree (mkNode and_seq) ()))
         (($knobs $updatedTree) (actionProbe $tree (mkNodeId (0)) ((mkTree (mkNode move_forward) ())) True ())))
    (getChildren (getNodeById $updatedTree (mkNodeId (0)))))
  (cons (mkNullVex ()) ()))

;; ===========================================================================
;; actionProbe — single perm → exactly one knob returned
;; ===========================================================================
!(assertEqual
  (let* (($tree (mkTree (mkNode and_seq) ()))
         (($knobs $updatedTree) (actionProbe $tree (mkNodeId (0)) ((mkTree (mkNode move_forward) ())) True ())))
    (length $knobs))
  1)

;; ===========================================================================
;; actionProbe — single perm → ASK multiplicity = len(perms)+1 = 2
;; ===========================================================================
!(assertEqual
  (let* (($tree (mkTree (mkNode and_seq) ()))
         (($knobs $updatedTree) (actionProbe $tree (mkNodeId (0)) ((mkTree (mkNode move_forward) ())) True ()))
         ($ask (car-atom $knobs)))
    (getRawKnobMultip $ask))
  (mkMultip 2))

;; ===========================================================================
;; actionProbe — two perms → ASK multiplicity = 3
;; ===========================================================================
!(assertEqual
  (let* (($tree (mkTree (mkNode and_seq) ()))
         (($knobs $updatedTree) (actionProbe $tree (mkNodeId (0)) ((mkTree (mkNode move_forward) ()) (mkTree (mkNode turn_left) ())) True ()))
         ($ask (car-atom $knobs)))
    (getRawKnobMultip $ask))
  (mkMultip 3))

;; ===========================================================================
;; actionProbe — ASK default is 0 (absent)
;; ===========================================================================
!(assertEqual
  (let* (($tree (mkTree (mkNode and_seq) ()))
         (($knobs $updatedTree) (actionProbe $tree (mkNodeId (0)) ((mkTree (mkNode move_forward) ())) True ()))
         ($ask (car-atom $knobs)))
    (getKnobDefault $ask))
  (mkDiscSpec 0))

;; ===========================================================================
;; buildAction — integration: simple and_seq tree produces knobs
;; ===========================================================================
!(assertEqual
  (let* (($origTree (mkTree (mkNode and_seq) (cons (mkTree (mkNode move_forward) ()) ())))
         (($updatedTree $mmp) (buildAction $origTree (mkNodeId (0)) () (move_forward turn_left) (A B)))
         ($hasKnobs (> (MultiMap.length $mmp) 0)))
    $hasKnobs)
  True)

;; ===========================================================================
;; buildAction — action_bool_if tree produces knobs
;; ===========================================================================
!(assertEqual
  (let* (($origTree (mkTree (mkNode action_bool_if)
                     (cons (mkTree (mkNode A) ())
                     (cons (mkTree (mkNode move_forward) ())
                     (cons (mkTree (mkNode turn_left) ()) ())))))
         (($updatedTree $mmp) (buildAction $origTree (mkNodeId (0)) () (move_forward turn_left) (A B))))
    (> (MultiMap.length $mmp) 0))
  True)

;; ===========================================================================
;; buildAction — empty and_seq produces knobs
;; ===========================================================================
!(assertEqual
  (let* (($origTree (mkTree (mkNode and_seq) ()))
         (($updatedTree $mmp) (buildAction $origTree (mkNodeId (0)) () (move_forward turn_left) (A B))))
    (> (MultiMap.length $mmp) 0))
  True)

;; ===========================================================================
;; buildKnobs 5-arity — action path produces knobs for and_seq tree
;;
;; Named bindings avoid PeTTa parser ambiguity with consecutive () ()
;; inside let* call expressions (see strategy test comment below).
;; ===========================================================================
!(assertEqual
  (let* (
    ($mmp ())
    ($argLabels ())
    ($acts (move_forward turn_left))
    ($percs (A B))
    ($tree (mkTree (mkNode and_seq)
                   (cons (mkTree (mkNode move_forward) ()) ())))
    (($updatedTree $MMap) (buildKnobs $tree $mmp $argLabels $acts $percs))
  )
    (> (MultiMap.length $MMap) 0))
  True)

;; ===========================================================================
;; buildKnobs 5-arity — action path produces knobs for action_bool_if tree
;; ===========================================================================
!(assertEqual
  (let* (
    ($mmp ())
    ($argLabels ())
    ($acts (move_forward turn_left))
    ($percs (ahead_blocked A B))
    ($tree (mkTree (mkNode action_bool_if)
                   (cons (mkTree (mkNode ahead_blocked) ())
                   (cons (mkTree (mkNode move_forward) ())
                   (cons (mkTree (mkNode turn_left) ()) ())))))
    (($updatedTree $MMap) (buildKnobs $tree $mmp $argLabels $acts $percs))
  )
    (> (MultiMap.length $MMap) 0))
  True)

;; ===========================================================================
;; buildKnobs 5-arity — logical fallback still works when actions/perceptions
;; are empty (tree is a boolean OR node)
;; ===========================================================================
!(assertEqual
  (let* (
    ($mmp ())
    ($argLabels (A B))
    ($acts ())
    ($percs ())
    ($tree (mkTree (mkNode OR)
                   (cons (mkTree (mkNode A) ()) ())))
    (($updatedTree $MMap) (buildKnobs $tree $mmp $argLabels $acts $percs))
  )
    (> (MultiMap.length $MMap) 0))
  True)

;; ===========================================================================
;; buildKnobs 5-arity — strategy fallback still works
;; Uses named bindings for empty actions/perceptions to avoid PeTTa parser
;; ambiguity with consecutive () () inside let* call expressions.
;; ===========================================================================
!(assertEqual
  (let* (
    ($acts ())
    ($percs ())
    ($tree (mkTree (mkNode PRIORITIZED-OR)
                   (cons (mkTree (mkNode playcenter) ())
                   (cons (mkTree (mkNode playcorner) ()) ()))))
    (($updatedTree $MMap) (buildKnobs $tree () (playcenter playcorner) $acts $percs))
  )
    (> (MultiMap.length $MMap) 0))
  True)

;; ===========================================================================
;; actionCanonize — returns same tree if root is and_seq
;; ===========================================================================
!(assertEqual
  (let $tree (mkTree (mkNode and_seq) (cons (mkTree (mkNode move_forward) ()) ()))
    (actionCanonize $tree))
  (mkTree (mkNode and_seq) (cons (mkTree (mkNode move_forward) ()) ())))

;; ===========================================================================
;; actionCanonize — wraps tree in and_seq if root is not and_seq
;; ===========================================================================
!(assertEqual
  (let $tree (mkTree (mkNode move_forward) ())
    (actionCanonize $tree))
  (mkTree (mkNode and_seq) (cons (mkTree (mkNode move_forward) ()) ())))

;; ===========================================================================
;; buildKnobs 4-arity — action path delegation to 5-arity (no infinite loop)
;; ===========================================================================
!(assertEqual
  (let* (
    ($tree (mkTree (mkNode and_seq) (cons (mkTree (mkNode move_forward) ()) ())))
    (($updatedTree $MMap) (buildKnobs $tree () () True))
  )
    (== $MMap ()))
  True)
;; ===========================================================================
;; actionCleanup — removes empty action structural nodes
;; ===========================================================================
!(assertEqual
  (actionCleanup (mkTree (mkNode and_seq) ()))
  (mkNullVex ()))

!(assertEqual
  (actionCleanup (mkTree (mkNode or_seq) ()))
  (mkNullVex ()))

!(assertEqual
  (actionCleanup (mkTree (mkNode seq_exec) ()))
  (mkNullVex ()))

!(assertEqual
  (actionCleanup (mkTree (mkNode and_seq) (cons (mkTree (mkNode move_forward) ()) ())))
  (mkTree (mkNode and_seq) (cons (mkTree (mkNode move_forward) ()) ())))

;; Recursive cleanup: inner and_seq is empty, gets reduced to nullVertex, causing outer and_seq to be empty
!(assertEqual
  (actionCleanup (mkTree (mkNode and_seq) (cons (mkTree (mkNode and_seq) ()) ())))
  (mkNullVex ()))
