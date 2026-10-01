;; DAG utilities. Graph rows are parent lists, indexed by child. Mandatory
;; activation edges and learned edges are kept separate but checked together.
;; Extracts the fixed structural activation dependencies from schema fields.
;;   $fields: List of schema fields describing coordinates and activation rules.
;;   Returns: A graph as a list of parent lists indexed by coordinate index.
(= (boaFixedGraph $fields) (map-atom $fields $f (fieldActivationParents $f)))

;; Merges fixed structural activation edges with learned probabilistic edges.
;;   $fixed: List of parent lists for fixed activation constraints.
;;   $learned: List of parent lists for learned dependencies.
;;   Returns: Combined graph with unified parent lists for each coordinate.
(= (boaCombined $fixed $learned)
   (List.zipWith boaUnion $fixed $learned))

;; Computes set union of two parent lists, maintaining uniqueness and order.
;;   $a: Base list of parent coordinate indices.
;;   $b: List of parent coordinate indices to merge into $a.
;;   Returns: Merged list containing all unique elements of $a and $b.
(= (boaUnion $a $b)
   (foldl-atom $b $a $out $v (if (continContains $v $out) $out (List.insert $v $out))))

;; Tests whether $target is reachable as an ancestor of $from in $graph.
;;   $graph: Graph represented as list of parent lists per node index.
;;   $from: Starting child coordinate index.
;;   $target: Candidate ancestor coordinate index to search for.
;;   $seen: List of already visited coordinate indices.
;;   Returns: True if a directed path from $from to $target exists, False otherwise.
(= (boaAncestorsReach $graph $from $target $seen)
   (boaWalkAncestors $graph ($from) $target $seen))

;; Recursive DFS traversal over parent edges to detect directed reachability.
;;   $graph: Graph represented as list of parent lists per node index.
;;   $pending: Frontier list of coordinate indices awaiting expansion.
;;   $target: Target ancestor coordinate index to detect.
;;   $seen: List of coordinate indices visited so far.
;;   Returns: True if $target is found in the ancestor graph, False otherwise.
(= (boaWalkAncestors $graph $pending $target $seen)
   (case $pending
     ((() False)
      ((cons $from $rest)
       (if (== $from $target) True
         (if (continContains $from $seen) 
            (boaWalkAncestors $graph $rest $target $seen)
            (boaWalkAncestors $graph (List.concat (List.getByIdx $graph $from) $rest)
             $target (cons $from $seen))))))))

;; Checks whether adding directed edge $parent -> $child is legal.
;;   $fixed: Fixed activation graph.
;;   $learned: Current learned dependency graph.
;;   $parent: Proposed parent coordinate index.
;;   $child: Target child coordinate index.
;;   Returns: True if the edge is not redundant and introduces no cycle, False otherwise.
(= (boaEdgeLegal $fixed $learned $parent $child)
   (and (not (continContains $parent (List.getByIdx $learned $child)))
     (not (boaAncestorsReach (boaCombined $fixed $learned) $parent $child ()))))

;; Helper for Kahn's topological sort: iteratively extracts nodes whose parents are all in $done.
;;   $graph: Graph represented as list of parent lists per node index.
;;   $remaining: List of coordinate indices not yet placed in topological order.
;;   $done: List of coordinate indices already scheduled in valid order.
;;   Returns: Completed topological ordering or Error if a cycle is encountered.
(= (boaTopoRest $graph $remaining $done)
   (if (== $remaining ()) $done
     (let $ready (filter-atom $remaining $i
                  (all (map-atom (List.getByIdx $graph $i) $p (continContains $p $done))))
       (if (== $ready ()) (Error $graph "Cyclic BOA graph")
         (let $next (car-atom $ready)
           (boaTopoRest $graph (filter-atom $remaining $i (not (== $i $next)))
             (List.append $next $done)))))))

;; Computes a valid topological ordering of coordinates for conditional sampling.
;;   $graph: Combined graph (fixed activation + learned dependencies).
;;   Returns: List of coordinate indices sorted so parents precede children.
(= (boaTopological $graph)
   (boaTopoRest $graph (fieldPriorIndices 0 (List.length $graph)) ()))
