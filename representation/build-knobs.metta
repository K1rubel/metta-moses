;; isActionOperator — True if $op is a structural action operator symbol.
;;
;; Mirrors the full C++ id::action enum (comboreduct/combo/action.h:37-51):
;;   sequential_and    → and_seq
;;   sequential_or     → or_seq
;;   sequential_exec   → seq_exec
;;   action_not        → action_not
;;   action_boolean_if → action_bool_if  (also aliased as action_if)
;;   boolean_action_if → bool_action_if
;;   contin_action_if  → contin_action_if
;;   action_action_if  → action_action_if
;;   action_success    → action_success
;;   action_failure    → action_failure
;;   action_while      → action_while
;;   boolean_while     → bool_while
;;   return_success    → return_success
;;   repeat_n          → repeat_n
;;
;; NOTE: build_action() only recurses into and_seq and action_bool_if;
;; the remaining operators are leaves (pass-through in buildAction).
;; However all of them must be excluded from isBuiltinAction so they are
;; never mistaken for user-defined domain actions.
(= (isActionOperator $op)
   (is-member $op (and_seq or_seq seq_exec action_not action_bool_if
                   bool_action_if contin_action_if action_action_if
                   action_success action_failure
                   action_while bool_while return_success repeat_n)))

;; isBuiltinAction — True for user-defined (domain) action symbols.
;; The two-argument form mirrors C++'s typed builtin_action check in MeTTa's
;; untyped setting: only symbols explicitly supplied in $actions are actions.
(= (isBuiltinAction $op) (not (isActionOperator $op)))
(= (isBuiltinAction $op $actions) (is-member $op $actions))

;;; =============================================================================
;; buildKnobs — entry point for representation knob building
;;
;; Port of C++ build_knobs constructor dispatch (build_knobs.cc:84-131):
;;   boolean_type       → logical_canonize → build_logical
;;   action_result_type → action_canonize  → build_action
;;
;; Dispatch based on root operator:
;;   PRIORITIZED-OR                    → strategy path (buildStrategy)
;;   any isActionOperator root         → action path (buildAction) [5-arity only]
;;   otherwise                         → logical path (logicalCanonize + buildLogical)
;;
;; Arity legend:
;;   3-arity — logical default (discprobe disabled)
;;   4-arity — logical / strategy with explicit discprobe control
;;             GUARD: raises error if the exemplar root is an action operator,
;;             because the action path requires actions+perceptions (5-arity).
;;   5-arity — action + perceptions pass-through, plus strategy/logical fallback
;; =============================================================================

;; 3-arity: delegates to 4-arity with discprobe enabled
(= (buildKnobs $exemplar $mmp $argLabels)
    (buildKnobs $exemplar $mmp $argLabels True))

;; 4-arity: Logical and Strategy domains (no actions/perceptions available)
(= (buildKnobs (mkTree (mkNode $op) $children) $mmp $argLabels $disableDiscprobe)
    (if (isActionOperator $op)
        (Error "buildKnobs 4-arity cannot be called with action operator root")
        (if (== $op PRIORITIZED-OR)
            (buildStrategy (mkTree (mkNode PRIORITIZED-OR) $children) (mkNodeId (0)) $mmp $argLabels)
            (let $canonized (logicalCanonize (mkTree (mkNode $op) $children))
                (buildLogical $canonized (mkNodeId (0)) $mmp $argLabels $disableDiscprobe)))))

;; 5-arity: Action domain with fallback to Logical and Strategy
(= (buildKnobs (mkTree (mkNode $op) $children) $mmp $argLabels $actions $perceptions)
    (if (== $op PRIORITIZED-OR)
        (buildStrategy (mkTree (mkNode PRIORITIZED-OR) $children) (mkNodeId (0)) $mmp $argLabels)
        (if (or (isActionOperator $op) (is-member $op $actions))
            (let* (($canonized (actionCanonize (mkTree (mkNode $op) $children)))
                   (($t1 $m1) (buildAction $canonized (mkNodeId (0)) $mmp $actions $perceptions))
                   ($t2 (actionCleanup $t1))
                   ($t3 (if (isNullVertex $t2) (mkTree (mkNode and_seq) ()) $t2)))
                ($t3 $m1))
            (let $canonized (logicalCanonize (mkTree (mkNode $op) $children))
                (buildLogical $canonized (mkNodeId (0)) $mmp $argLabels True)))))

