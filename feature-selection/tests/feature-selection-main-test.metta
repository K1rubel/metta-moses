!(register-module! ../../../metta-moses)
!(import! &self metta-moses:feature-selection:feature-selection-main)
!(import! &self metta-moses:feature-selection:select-top-features)
!(import! &self metta-moses:feature-selection:similarity-scorers)
!(import! &self metta-moses:feature-selection:smd)
!(import! &self metta-moses:feature-selection:simple)
!(import! &self metta-moses:feature-selection:feature-selection-helpers)
!(import! &self metta-moses:utilities:general-helpers)
!(import! &self metta-moses:utilities:list-methods)
!(import! &self metta-moses:utilities:tree)
!(import! &self metta-moses:scoring:cscore)

!(bind! ttable 
    (mkITable 
        (Cons (Cons False (Cons False (Cons True (Cons True (Cons True Nil)))))
        (Cons (Cons True (Cons False (Cons False (Cons True (Cons True Nil)))))
        (Cons (Cons False (Cons True (Cons False (Cons True (Cons False Nil)))))
        (Cons (Cons False (Cons False (Cons False (Cons True (Cons False Nil))))) Nil))))
        (Cons A (Cons B (Cons C (Cons D (Cons Output Nil)))))))

;; checking treeFtsIndices
; ! (treeFtsIndices (mkTree (mkNode AND) Nil) (Cons A (Cons B (Cons C Nil))))      ;; ()
; ! (treeFtsIndices (mkTree (mkNode AND) (Cons (mkTree (mkNode A) Nil) Nil)) (Cons A (Cons B (Cons C Nil)))) ;; (0)
; ! (treeFtsIndices (mkTree (mkNode AND) (Cons (mkTree (mkNode A) Nil) (Cons (mkTree (mkNode B) Nil) (Cons (mkTree (mkNode B) Nil) Nil)))) (Cons A (Cons B (Cons C Nil))))     ;; (0 1)

; ! (featureSelector 
;                 smd 
;                 ttable 
;                 0.0
;                 (mkTree (mkNode AND) (Cons (mkTree (mkNode B) Nil) Nil)) 
;                 ; 2
;                 2
;                 True ;; bool indicating to/not to use exemplar features as initial features
;                 ()
;                 Flase
;                 ; 2
;                 ; False
;                 ; ja
;                 ; 2
;             )       ;; result ((1.0 (1 2 0)) (0.5 (1 2 3)) (0.5 (1 0 3)))

; ! (featureSelector 
;                 smd 
;                 ttable 
;                 0.0
;                 (mkTree (mkNode AND) (Cons (mkTree (mkNode B) Nil) Nil)) 
;                 ; 2
;                 2
;                 False ;; bool indicating to/not to use exemplar features as initial features
;                 ()
;                 True
;                 ; 2
;                 ; False
;                 ; ja
;                 ; 2
;             )       ;; result ((1.0 (0 1 2))) exemplar features igoned

; ! (featureSelector 
;                 smd 
;                 ttable 
;                 0.0
;                 (mkTree (mkNode AND) (Cons (mkTree (mkNode B) Nil) Nil)) 
;                 ; 2
;                 2
;                 False ;; bool indicating to/not to use exemplar features as initial features
;                 ()
;                 False
;                 ; 2
;                 ; False
;                 ; ja
;                 ; 2
;             )       ;; result ((1.0 (1 0 2)) (1.0 (0 2 3))) exemplar features not ignored
; ! (featureSelector 
;                 smd 
;                 ttable 
;                 0.0
;                 (mkTree (mkNode AND) (Cons (mkTree (mkNode B) Nil) Nil)) 
;                 2
;                 2
;                 False ;; bool indicating to/not to use exemplar features as initial features
;                 ()
;                 False
;                 ; 2
;                 False
;                 ja
;                 2
;             )       ;; result ((1 0 2) (0 2 3)) exemplar features not ignored
; ! (featureSelector 
;                 smd 
;                 ttable 
;                 0.0
;                 (mkTree (mkNode AND) (Cons (mkTree (mkNode B) Nil) Nil)) 
;                 2
;                 2
;                 False ;; bool indicating to/not to use exemplar features as initial features
;                 ()
;                 False
;                 2
;                 False
;                 mi
;                 2
;             )       ;; result ((0 2 1) (0 2 3))

! (featureSelector 
                sim 
                ttable 
                0.0
                (mkTree (mkNode AND) (Cons (mkTree (mkNode B) Nil) Nil)) 
                2
                2
                False ;; bool indicating to/not to use exemplar features as initial features
                ()
                False
                2
                False
                mi
                2
            )       ;; result ((0) (1)). NOTE -- for simple feature selector initial features are not need and should not be provided
            
