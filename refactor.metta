; Function to get the guardSet and children from an expression.
(: getGsetAndChildren (-> Expression Expression))
(= (getGsetAndChildren $expr)
     (getGsetAndChildrenHelper $expr () ()))  ; Initial call with empty tuples for guardSets and children.

; Helper function to recursively find guardSets and children.
(: getGsetAndChildrenHelper (-> Expression Expression Expression Expression))
(= (getGsetAndChildrenHelper $expr $literals $nonLiterals)
    (if (== $expr ())
        ($literals $nonLiterals)  ; Return guardSets and children as a tuple when the expression is empty.
        (let*(
            ($head (car-atom $expr))  ; Get the head of the expression.
            ($tail (cdr-atom $expr))   ; Get the tail of the expression.
            ($isLiteral (or (== (get-metatype $head) Symbol) (unify $head (NOT $_) True False)))  ; Check if head is a literal.
        )(if (or (== $head AND) (== $head OR))
            (getGsetAndChildrenHelper $tail $literals $nonLiterals)  ; Skip adding AND/OR to either tuple and continue with tail.
            (if $isLiteral
                (getGsetAndChildrenHelper $tail (concatTuple $literals ($head)) $nonLiterals)  ; Add literals to guardSets.
                (getGsetAndChildrenHelper $tail $literals (concatTuple $nonLiterals ($head)))  ; Add other expressions to children.
            )
        ))
    )
)
; Test cases for getGsetAndChildren function.

; Test case 1: Simple AND expression
; Input: (AND A B (OR A B) C)
; Expected Output: ((A B C) ((OR A B)))
(= (testGetGsetAndChildrenCase1)
    (let* 
        (
            ($expr (AND A B (OR A B) C))
            ($expectedGuardSets (A B C))
            ($expectedChildren ((OR A B)))
            ($result (getGsetAndChildren $expr))
        )
        (if (== $result ($expectedGuardSets $expectedChildren))
            "Test Case 1 Passed"
            (str "Test Case 1 Failed: Expected " ($expectedGuardSets $expectedChildren) " but got " $result)
        )
    )
)

; Test case 2: Simple OR expression
; Input: (OR A B (AND A B) C)
; Expected Output: ((A B C) ((AND A B)))
(= (testGetGsetAndChildrenCase2)
    (let* 
        (
            ($expr (OR A B (AND A B) C))
            ($expectedGuardSets (A B C))
            ($expectedChildren ((AND A B)))
            ($result (getGsetAndChildren $expr))
        )
        (if (== $result ($expectedGuardSets $expectedChildren))
            "Test Case 2 Passed"
            (str "Test Case 2 Failed: Expected " ($expectedGuardSets $expectedChildren) " but got " $result)
        )
    )
)