;; ==============================================================================
;; Module: representation/contin-spec.metta
;; Purpose: Continuous Knob Specification and Raw Trit Field Definitions
;;
;; Records frozen in Step 1; production validation/decoding/schema in Step 5.
;;
;; Reference (commit f88ccd3279f3dd853e8c23103be5376a0e7eafc1):
;;   - moses/moses/representation/field_set.h
;;       struct contin_spec  (L180-231) — mean, step_size, expansion, depth
;;       struct contin_stepper (L233-275) — left/right state machine
;;   - moses/moses/representation/knobs.h — knob attachment
;;   - moses/moses/main/problem-params.cc — production defaults
;;
;; CONCEPTS:
;; ---------
;; 1. What is a Continuous Knob?
;;    In MOSES, a program candidate is a tree. Continuous constants in that tree
;;    (e.g. the weight 2.5 in "2.5 * x + 1.0") are searched by replacing each
;;    constant with a variable-length SEQUENCE of discrete ternary choices (trits).
;;    This lets the same generic hill-climbing and EDA machinery that handles
;;    Boolean knobs also handle continuous coefficients — no specialised optimizer
;;    is needed at the inner loop level.
;;
;; 2. Trit encoding:
;;    Each trit position takes one of three integer values:
;;      0 = STOP — stop decoding; all subsequent trits in the same knob are dead tail
;;      1 = LEFT — move in the negative direction
;;      2 = RIGHT — move in the positive direction
;;    The stepper state machine converts the trit sequence into a real number.
;;    The full stepper is implemented in representation/contin-stepper.metta (Phase 2).
;;
;; 3. Why a flat discrete map?
;;    Continuous knobs contribute D raw trit fields each (where D = depth) to the
;;    shared flat discrete map (mkDscMp).  This preserves full compatibility with
;;    existing hill-climbing neighbourhood generation, crossover, and mutation:
;;    they see an ordinary map of discrete 3-valued fields, not special-cased
;;    continuous coordinates.
;;
;; 4. Production defaults (from problem-params.cc / representation.cc):
;;      step_size = 1.0   (initial step taken from the mean)
;;      expansion = 2.0   (step multiplier on same-direction moves)
;;      depth     = 5     (number of raw trit fields per knob)
;;    The constructor-level defaults differ; the production overrides win.
;; ==============================================================================

;; ------------------------------------------------------------------------------
;; Continuous Knob Specification: mkContinSpec
;; ------------------------------------------------------------------------------
;; Records the geometric search-space parameters of one continuous constant.
;;
;; Fields:
;;   $mean      : Number — anchor value; all-STOP instance decodes to exactly $mean
;;   $step      : Number — initial step size (production default: 1.0)
;;   $expansion : Number — step multiplier while moving in a single direction (default: 2.0)
;;   $depth     : Number — number of raw trit fields allocated (production default: 5)
;;
;; Example: (mkContinSpec 0.0 1.0 2.0 5)
(: ContinSpec Type)
(: mkContinSpec (-> Number Number Number Number ContinSpec))

;; Fixed production defaults; configured builders take explicit CLI values.
;;   $mean: Anchor value decoded by an all-STOP trit sequence.
;;   Returns: A specification with production step, expansion, and depth defaults.
(= (defaultContinSpec $mean) (mkContinSpec $mean 1.0 2.0 5))

;; Accessors expose one stored parameter without changing the specification.
;;   Argument: one mkContinSpec record. Results: continSpecMean returns $mean,
;;   continSpecStep returns $step, continSpecExpansion returns $exp, and
;;   continSpecDepth returns $depth.
(= (continSpecMean     (mkContinSpec $mean $step $exp $depth)) $mean)
(= (continSpecStep     (mkContinSpec $mean $step $exp $depth)) $step)
(= (continSpecExpansion (mkContinSpec $mean $step $exp $depth)) $exp)
(= (continSpecDepth    (mkContinSpec $mean $step $exp $depth)) $depth)

;; ------------------------------------------------------------------------------
;; Continuous Tree Knob Annotation: mkCTK
;; ------------------------------------------------------------------------------
;; Attached to numeric constant leaf nodes in the AST during representation
;; construction.  Associates a knob's spec with its starting index in the flat
;; raw discrete map, so the stepper knows which trit slice to read.
;;
;; Fields:
;;   $spec     : ContinSpec — search-space parameters for this constant
;;   $startIdx : Number     — 0-based index of the first trit field owned by this knob
;;
;; Invariant: a knob with depth D owns indices [$startIdx, $startIdx + D - 1]
;;            in the flat raw map.  Slices across knobs must not overlap.
;;
;; Example: (mkCTK (mkContinSpec 0.0 1.0 2.0 5) 0)
;;          This knob owns raw indices 0..4.
(: ContinTreeKnob Type)
(: mkCTK (-> ContinSpec Number ContinTreeKnob))

;;   Argument: one mkCTK record. ctkSpec returns its search specification;
;;   ctkStartIdx returns the first flat-field index owned by the knob.
(= (ctkSpec     (mkCTK $spec $startIdx)) $spec)
(= (ctkStartIdx (mkCTK $spec $startIdx)) $startIdx)

;; ------------------------------------------------------------------------------
;; Raw Continuous Trit Field: mkContinTritField
;; ------------------------------------------------------------------------------
;; Represents a single coordinate in the flat discrete map (mkDscMp).
;; A continuous knob of depth D produces exactly D of these, at consecutive offsets.
;;
;; Fields:
;;   $ownerId : Atom   — identifier of the owning knob (e.g. a NodeId)
;;   $offset  : Number — 0-based position within the knob's slice (0 <= offset < depth)
;;
;; Example for a bias knob at depth 5:
;;   (mkContinTritField bias 0) ... (mkContinTritField bias 4)
(: ContinTritField Type)
(: mkContinTritField (-> Atom Number ContinTritField))

;;   Argument: one mkContinTritField. continFieldOwner returns the owning
;;   knob/node identity; continFieldOffset returns this trit's local position.
(= (continFieldOwner  (mkContinTritField $owner $offset)) $owner)
(= (continFieldOffset (mkContinTritField $owner $offset)) $offset)

;; ------------------------------------------------------------------------------
;; Discrete map interface — getKnobMultip / getKnobDefault
;; ------------------------------------------------------------------------------
;; The generic representation layer (knob-representation.metta) queries any knob
;; through `getKnobMultip` and `getKnobDefault`.  Adding clauses here for
;; `mkContinTritField` supplies the multiplicity/default interface. Step 5's
;; contin-stepper, contin-representation and field-schema modules implement
;; decoding, activation and validation. End-to-end optimizer routing is Step 7;
;; these accessors alone do not make continuous runs production-ready.

;; Multiplicity is always 3: a trit takes values 0 (STOP), 1 (LEFT), 2 (RIGHT).
;;   $knob: continuous trit field; returns mkMultip 3.
(= (getKnobMultip (mkContinTritField $owner $offset))
   (mkMultip 3))

;; Default is 0 (STOP).
;; Consequence: the all-default instance decodes every knob to its exact mean.
;;   $knob: continuous trit field; returns its STOP default as mkDiscSpec 0.
(= (getKnobDefault (mkContinTritField $owner $offset))
   (mkDiscSpec 0))

;; Raw map key stores the field cardinality, not the default trit.
;;   $knob: continuous trit field; returns raw-map cardinality mkDiscSpec 3.
(= (getKnobSpec (mkContinTritField $owner $offset)) (mkDiscSpec 3))
