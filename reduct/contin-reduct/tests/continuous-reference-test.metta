;; Steps 12/13 SOURCE-DERIVED C++ goldens; see fixtures/continuous/nonlinear-reference.json.
;; Not a live C++ differential run or full algebraic-normal-form parity claim.
!(import! &self ../../../utilities/general-helpers)
!(import! &self ../../../utilities/list-methods)
!(import! &self ../../../parameters/registry)
!(import! &self ../../../parameters/defaults)
!(import! &self ../../../scoring/cacheSpace)
!(import! &self ../../../scoring/cscore)
!(import! &self ../../../scoring/contin-eval)
!(import! &self ../../../scoring/contin-score)
!(import! &self ../../../representation/knob-representation)
!(import! &self ../../../representation/contin-spec)
!(import! &self ../../../representation/contin-stepper)
!(import! &self ../../../representation/contin-representation)
!(import! &self ../../../representation/field-schema)
!(import! &self ../contin-helpers)
!(import! &self ../reduce-identities)
!(import! &self ../reorder-commutative)
!(import! &self ../reduce-nary)
!(import! &self ../reduce-division)
!(import! &self ../fold-constants)
!(import! &self ../reduce-nonlinear)
!(import! &self ../contin-reduction)
!(import! &self ../../../representation/contin-canonize)
!(import! &self ../../../representation/build-contin)
!(import! &self ../../../optimization/optimizer-contract)
!(import! &self ../../../scoring/candidate-evaluation)

(= (leaf $v) (mkTree (mkNode $v) ()))
(= (node $op $children) (mkTree (mkNode $op) $children))
(= (refNear $result $expected)
 (case $result (((mkCEvalOk $value)
   (<= (abs-math (- $value $expected)) (+ 0.000000000001 (* 0.000000000001 (abs-math $expected))))) ($error False))))

;; sin-zero
!(assertEqual (refNear (continEval (node c_sin ((leaf 0.0))) ()) 0.0) True)
!(assertEqual (refNear (continEval (reduceContinTree (node c_sin ((leaf 0.0)))) ()) 0.0) True)
!(assertEqual (reduceContinTree (node c_sin ((leaf 0.0)))) (leaf 0.0))

;; log-one
!(assertEqual (refNear (continEval (node c_log ((leaf 1.0))) ()) 0.0) True)
!(assertEqual (refNear (continEval (reduceContinTree (node c_log ((leaf 1.0)))) ()) 0.0) True)
!(assertEqual (reduceContinTree (node c_log ((leaf 1.0)))) (leaf 0.0))

;; exp-zero
!(assertEqual (refNear (continEval (node c_exp ((leaf 0.0))) ()) 1.0) True)
!(assertEqual (refNear (continEval (reduceContinTree (node c_exp ((leaf 0.0)))) ()) 1.0) True)
!(assertEqual (reduceContinTree (node c_exp ((leaf 0.0)))) (leaf 1.0))

;; constant-product
!(assertEqual (refNear (continEval (node c_mul ((leaf 2.0) (leaf 3.0))) ()) 6.0) True)
!(assertEqual (refNear (continEval (reduceContinTree (node c_mul ((leaf 2.0) (leaf 3.0)))) ()) 6.0) True)
!(assertEqual (reduceContinTree (node c_mul ((leaf 2.0) (leaf 3.0)))) (leaf 6.0))

;; constant-division
!(assertEqual (refNear (continEval (node c_div ((leaf 6.0) (leaf 3.0))) ()) 2.0) True)
!(assertEqual (refNear (continEval (reduceContinTree (node c_div ((leaf 6.0) (leaf 3.0)))) ()) 2.0) True)
!(assertEqual (reduceContinTree (node c_div ((leaf 6.0) (leaf 3.0)))) (leaf 2.0))

;; gated-invalid-log
!(assertEqual (refNear (continEval (node c_mul ((leaf 0.0) (node c_log ((leaf -1.0))))) ()) 0.0) True)
!(assertEqual (refNear (continEval (reduceContinTree (node c_mul ((leaf 0.0) (node c_log ((leaf -1.0)))))) ()) 0.0) True)
!(assertEqual (reduceContinTree (node c_mul ((leaf 0.0) (node c_log ((leaf -1.0)))))) (leaf 0.0))

;; zero-numerator
!(assertEqual (refNear (continEval (node c_div ((leaf 0.0) (leaf 0.0))) ()) 0.0) True)
!(assertEqual (refNear (continEval (reduceContinTree (node c_div ((leaf 0.0) (leaf 0.0)))) ()) 0.0) True)
!(assertEqual (reduceContinTree (node c_div ((leaf 0.0) (leaf 0.0)))) (leaf 0.0))

;; order-two
!(assertEqual (refNear (continEval (node c_add ((leaf x) (node c_mul ((leaf x) (leaf x))))) ((mkContinBinding x 2.0))) 6.0) True)
!(assertEqual (refNear (continEval (reduceContinTree (node c_add ((leaf x) (node c_mul ((leaf x) (leaf x)))))) ((mkContinBinding x 2.0))) 6.0) True)

;; sin-one
!(assertEqual (refNear (continEval (node c_sin ((leaf x))) ((mkContinBinding x 1.0))) 0.8414709848078965) True)
!(assertEqual (refNear (continEval (reduceContinTree (node c_sin ((leaf x)))) ((mkContinBinding x 1.0))) 0.8414709848078965) True)

;; log-two
!(assertEqual (refNear (continEval (node c_log ((leaf x))) ((mkContinBinding x 2.0))) 0.6931471805599453) True)
!(assertEqual (refNear (continEval (reduceContinTree (node c_log ((leaf x)))) ((mkContinBinding x 2.0))) 0.6931471805599453) True)

;; exp-one
!(assertEqual (refNear (continEval (node c_exp ((leaf x))) ((mkContinBinding x 1.0))) 2.718281828459045) True)
!(assertEqual (refNear (continEval (reduceContinTree (node c_exp ((leaf x)))) ((mkContinBinding x 1.0))) 2.718281828459045) True)

;; rational
!(assertEqual (refNear (continEval (node c_div ((leaf x) (node c_add ((leaf 1.0) (node c_mul ((leaf x) (leaf x))))))) ((mkContinBinding x 2.0))) 0.4) True)
!(assertEqual (refNear (continEval (reduceContinTree (node c_div ((leaf x) (node c_add ((leaf 1.0) (node c_mul ((leaf x) (leaf x)))))))) ((mkContinBinding x 2.0))) 0.4) True)

;; division-zero
!(assertEqual (continEval (node c_div ((leaf 1.0) (leaf 0.0))) ()) (mkCEvalError "DivisionByZero"))
!(assertEqual (continEval (reduceContinTree (node c_div ((leaf 1.0) (leaf 0.0)))) ()) (mkCEvalError "DivisionByZero"))

;; log-negative
!(assertEqual (continEval (node c_log ((leaf -1.0))) ()) (mkCEvalError "LogNonPositive"))
!(assertEqual (continEval (reduceContinTree (node c_log ((leaf -1.0)))) ()) (mkCEvalError "LogNonPositive"))

;; exp-overflow
!(assertEqual (continEval (node c_exp ((leaf 1000.0))) ()) (mkCEvalError "NonFinite"))
!(assertEqual (continEval (reduceContinTree (node c_exp ((leaf 1000.0)))) ()) (mkCEvalError "NonFinite"))

;; ungated-invalid-log
!(assertEqual (continEval (node c_mul ((node c_log ((leaf -1.0))) (leaf 0.0))) ()) (mkCEvalError "LogNonPositive"))
!(assertEqual (continEval (reduceContinTree (node c_mul ((node c_log ((leaf -1.0))) (leaf 0.0)))) ()) (mkCEvalError "LogNonPositive"))

;; Decoded constants, SSE/SAE and complexity penalties use the same C++ contracts.
!(assertEqual (decodeContinSlice (mkContinSpec 2.0 1.0 2.0 3) (2 1 2)) (mkCEvalOk 2.75))
!(assertEqual (decodeContinSlice (mkContinSpec 2.0 1.0 2.0 3) (0 0 0)) (mkCEvalOk 2.0))
(= (refTable) (mkITable ((-2 -1 0 1 2) (2 0 0 2 6)) (x y)))
(= (square) (node c_mul ((leaf x) (leaf x))))
!(assertEqual (continScoreTree (square) (mkContinCtx (refTable) squared_error 0.25 nonlinear 0))
 (mkCscore -10.0 2 0.5 0.0 -10.5))
!(assertEqual (continScoreTree (square) (mkContinCtx (refTable) abs_error 0.25 nonlinear 0))
 (mkCscore -6.0 2 0.5 0.0 -6.5))
!(assertEqual (continTreeComplexity (node c_sin ((square)))) 3)
!(assertEqual (continTreeComplexity (node c_mul ((leaf 0.0) (node c_log ((leaf -1.0)))))) 0)
