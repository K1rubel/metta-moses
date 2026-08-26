!(import! &self ../../utilities/general-helpers)
!(import! &self ../../utilities/list-methods)
!(import! &self ../../utilities/tree)
!(import! &self ../fitness)

;; ==========================================================================
;; penalizedFitness tests
;;
;; Scoring convention (matches C++ MOSES):
;;   rowFitness  =  0 if correct, -1 if wrong (or undefined variable)
;;   fitness     =  sum of rowFitness over all rows  (range [-N, 0])
;;   penalized   =  fitness - lambda * treeComplexity
;;
;; treeComplexity counts variable leaves (AND/OR/NOT = 0, each arg = 1).
;; ==========================================================================

;; Test 1: AND with nested OR — all rows correct
;; treeComplexity(AND(A, OR(B,C))) = 3  (leaves A,B,C)
;; fitness = 0, penalized = 0 - 0.1*3 = -0.3
!(assertEqual
   (isApproxEq
     (penalizedFitness
       (AND A (OR B C))
        ((True (A True) (B True) (C False))
         (False (A False) (B True) (C True)))
       0.1)
     -0.3)
   True)

;; Test 2: Nested OR — all rows correct
;; treeComplexity(OR(AND(A,B),C)) = 3  (leaves A,B,C)
;; fitness = 0, penalized = 0 - 0.1*3 = -0.3
!(assertEqual
   (isApproxEq
     (penalizedFitness
       (OR (AND A B) C)
       ((True (A True) (B False) (C True))
        (True (A True) (B True) (C False))
        (False (A False) (B False) (C False)))
       0.1)
     -0.3)
   True)

;; Test 3: Complex nested — all rows correct
;; treeComplexity(OR(AND(A,NOT(B)), AND(C,D))) = 4  (leaves A,B,C,D)
;; fitness = 0, penalized = 0 - 0.1*4 = -0.4
!(assertEqual
   (isApproxEq
     (penalizedFitness
       (OR (AND A (NOT B)) (AND C D))
       ((True (A True) (B False) (C True) (D True))
        (False (A False) (B True) (C False) (D False))
        (True (A True) (B False) (C False) (D True)))
       0.1)
     -0.4)
   True)

;; Test 4: Binary AND truth table — perfect, lambda=0
;; treeComplexity(AND(A,B)) = 2  (leaves A,B)
;; fitness = 0, penalized = 0 - 0*2 = 0.0
!(assertEqual
   (penalizedFitness
       (AND A B)
       ((True (A True) (B True))
        (False (A False) (B True))
        (False (A True) (B False))
        (False (A False) (B False)))
       0.0)
   0.0)

;; Test 5: Binary OR — two wrong rows (row 1: OR(T,T)=T≠F, row 2: OR(T,F)=T≠F)
;; treeComplexity(OR(A,B)) = 2  (leaves A,B)
;; fitness = -2, penalized = -2 - 0*2 = -2.0
!(assertEqual
   (penalizedFitness
       (OR A B)
       ((True (A True) (B True))
        (False (A False) (B True))
        (False (A True) (B False))
        (False (A False) (B False)))
       0.0)
   -2.0)

;; Test 6: Undefined variable X — all 3 rows wrong (X not in data)
;; treeComplexity(OR(AND(X,B),C)) = 3  (leaves X,B,C)
;; fitness = -3, penalized = -3 - 0.1*3 = -3.3
!(assertEqual
   (isApproxEq
     (penalizedFitness
       (OR (AND X B) C)
       ((True (A True) (B False) (C True))
        (True (A True) (B True) (C False))
        (False (A False) (B False) (C False)))
       0.1)
     -3.3)
   True)

;; Test 7: All variables undefined (P,Q,R,S,T,U not in data)
;; treeComplexity(OR(AND(P,NOT(Q)), AND(R,S), AND(T,U))) = 6
;; fitness = -3, penalized = -3 - 0.1*6 = -3.6
!(assertEqual
   (isApproxEq
     (penalizedFitness
       (OR (AND P (NOT Q)) (AND R S) (AND T U))
       ((True (A True) (B False) (C True) (D True))
        (False (A False) (B True) (C False) (D False))
        (True (A True) (B False) (C False) (D True)))
       0.1)
     -3.6)
   True)

;; Test 8: Wrapped single symbol (A) — all rows correct
;; treeComplexity(A) = 1  (single leaf)
;; fitness = 0, penalized = 0 - 0.1*1 = -0.1
!(assertEqual
   (isApproxEq
     (penalizedFitness
       (A)
       ((True (A True))
        (False (A False)))
       0.1)
     -0.1)
   True)

;; Test 9: Wrapped single symbol — one wrong
;; fitness = -1, penalized = -1 - 0.1*1 = -1.1
!(assertEqual
   (isApproxEq
     (penalizedFitness
       (A)
       ((False (A True))
        (False (A False)))
       0.1)
     -1.1)
   True)

;; Test 10: Wrapped single symbol, more data — all correct
;; fitness = 0, penalized = 0 - 0.1*1 = -0.1
!(assertEqual
   (isApproxEq
     (penalizedFitness
       (A)
      ((True (A True) (B False) (C True) (D True))
        (False (A False) (B True) (C False) (D False))
        (True (A True) (B False) (C False) (D True)))
       0.1)
     -0.1)
   True)

;; Test 11: NOT expression — all rows correct
;; treeComplexity(NOT(A)) = 1  (single leaf A; NOT costs 0)
;; fitness = 0, penalized = 0 - 0.1*1 = -0.1
!(assertEqual
   (isApproxEq
     (penalizedFitness
       (NOT A)
       ((False (A True))
        (True (A False)))
       0.1)
     -0.1)
   True)

;; Test 12: Bare symbol A — data has A defined
;; treeComplexity(A) = 1
;; fitness = 0, penalized = 0 - 0.1*1 = -0.1
!(assertEqual
   (isApproxEq
     (penalizedFitness
       A
       ((True (A True)))
       0.1)
     -0.1)
   True)

;; Test 13: Bare symbol A — A undefined in data (P supplied instead)
;; evaluate ERROR != True → wrong row
;; fitness = -1, penalized = -1 - 0.1*1 = -1.1
!(assertEqual
   (isApproxEq
     (penalizedFitness
       A
       ((True (P True)))
       0.1)
     -1.1)
   True)
