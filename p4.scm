; Programming Project, Part 4
; Ryan Rose, rtr29 | Ben Moore, bcm45 | Aaron Magid, ahm64

; Load the class parser
(load "classParser.scm")

(require racket/format)

; ------------------------------------------------------------------------------
; test
; ------------------------------------------------------------------------------
(define testPrograms '(("Test1.txt" "A" 15)("Test2.txt" "A" 12)("Test3.txt" "A" 125)("Test4.txt" "A" 36)("Test5.txt" "A" 54)("Test6.txt" "A" 110)("Test7.txt" "C" 26)("Test8.txt" "Square" 117)("Test9.txt" "Square" 32)("Test10.txt" "List" 15)("Test11.txt" "List" 123456)("Test12.txt" "List" 5285)("Test13.txt" "C" -716)))

(define testInterpreter
  (lambda (testPrograms passed failed)
    (cond
      ((null? testPrograms) (display-all "Passed: " passed " - " "Failed: " failed))
      (else 
       (display (caar testPrograms))
       (display " - ")
       (let ((result (interpret (caar testPrograms) (cadar testPrograms))))
         (display (if (eqv? result (caddar testPrograms)) "PASSED" "FAILED"))
         (newline)
         (if (eqv? result (cadar testPrograms)) (testInterpreter (cdr testPrograms) (+ passed 1) failed) (testInterpreter (cdr testPrograms) passed (+ failed 1))))))))

; Shorthand for testing
(define test
  (lambda ()
    (testInterpreter testPrograms 0 0)))

(define (display-all . vs)
  (for-each display vs))

; ------------------------------------------------------------------------------
; interpret - the primary call to interpret a file
; inputs:
;  fd - file name of code to be interpreted
; outputs:
;  The evaluation of the code
; ------------------------------------------------------------------------------
(define interpret
  (lambda (fd className)
    (selectReturn
     (call/cc
      (lambda (finalReturn)
        (let ((state
               (extractState
                (call/cc
                 (lambda (return)
                   (interpreter (parser fd) '((() ())) return continueError breakError throwError))))))
          ((getProperty (string->symbol className) 'main state) (cons (getVal (string->symbol className) state) '()) state)))))))

(define selectReturn
  (lambda (returnVals)
    (cond
      ((null? (extractValue returnVals)) (extractState returnVals))
      (else (boolHandle (extractValue returnVals))))))

(define boolHandle
  (lambda (val)
    (cond
      ((number? val) val)
      (else
       (if val
           'true
           'false) ))))
(define continueError
  (lambda (s)
    (error "CONTINUATION ERROR: Continue outside of loop!")))

(define breakError
  (lambda (s)
    (error "BREAK ERROR: Break outside of loop!")))

(define throwError
  (lambda (s e)
    (error (buildError "UNCAUGHT EXCEPTION: " e)) ))

(define buildError
  (lambda (s e)
    (string-append s (~a e) "\n") ))      

; ------------------------------------------------------------------------------
; interpreter
; inputs:
;  pt - parse tree
;  s - state
;  [continuations]
; outputs:
;  The return value of the code and a state
; ------------------------------------------------------------------------------
; ------------------------------------------------------------------------------
; ABSTRACTIONS
; ------------------------------------------------------------------------------
(define getRemainingStatements (lambda (pt) (cdr pt)))
(define getFirstOperation (lambda (pt) (caar pt)))
(define getOperands (lambda (pt) (cdar pt)))
(define getFirstOperand (lambda (pt) (cadar pt)))
(define getSecondPlusOperands (lambda (pt) (cddar pt)))
(define getThirdPlusOperands (lambda (pt) (cdddar pt)))
(define getThirdOperand (lambda (pt) (car (getThirdPlusOperands pt))))
(define getSecondOperand (lambda (pt) (caddar pt)))
(define getFirstLayer (lambda (pt) (car pt)))
(define findObject (lambda (pt) (cadadr (car pt))))

; Continuations: Break, Continue, Return, Throw
(define interpreter
  (lambda (pt s return cont_c cont_b cont_t)
    (cond
      ((null? pt) (valState '() s))
      ((null? (getFirstOperation pt)) (interpreter (getRemainingStatements pt) s return cont_c cont_b cont_t))
      ((eqv? (getFirstOperation pt) 'var) (interpreter (getRemainingStatements pt) (decVal (getFirstOperand pt) (car (m_eval (if (null? (getSecondPlusOperands pt)) (getSecondPlusOperands pt) (getSecondOperand pt)) s cont_t)) (cdr (m_eval (if (null? (getSecondPlusOperands pt)) (getSecondPlusOperands pt) (getSecondOperand pt)) s cont_t))) return cont_c cont_b cont_t)) 
      ((eqv? (getFirstOperation pt) '=) (interpreter (getRemainingStatements pt) (m_assign (getOperands pt) s cont_t) return cont_c cont_b cont_t))  ; if "="
      ((eqv? (getFirstOperation pt) 'return) (let ((finalState (m_eval (getFirstOperand pt) s cont_t))) (return finalState))) ; if "return"
      ((eqv? (getFirstOperation pt) 'if) (interpreter (getRemainingStatements pt) (m_if (getFirstOperand pt) (getSecondOperand pt) (if (null? (getThirdPlusOperands pt)) '() (getThirdOperand pt)) s return cont_c cont_b cont_t) return cont_c cont_b cont_t))  ; if "if"
      ((eqv? (getFirstOperation pt) 'while) (interpreter (getRemainingStatements pt) (call/cc (lambda (breakFunc) (m_while (getFirstOperand pt) (getSecondOperand pt) s return breakFunc cont_t))) return cont_c cont_b cont_t))  ; if "while"
      ((eqv? (getFirstOperation pt) 'begin) (interpreter (getRemainingStatements pt) (m_block (getOperands pt) s return cont_c cont_b cont_t) return cont_c cont_b cont_t)) ; if "begin"
      ((eqv? (getFirstOperation pt) 'continue) (cont_c s))
      ((eqv? (getFirstOperation pt) 'break) (cont_b s))
      ((eqv? (getFirstOperation pt) 'try) (interpreter (getRemainingStatements pt) (m_try (getFirstOperand pt) (getSecondOperand pt) (getThirdOperand pt) s return cont_c cont_b cont_t) return cont_c cont_b cont_t))
      ((eqv? (getFirstOperation pt) 'throw) (cont_t s (getFirstOperand pt)))
      ((eqv? (getFirstOperation pt) 'function) (interpreter (getRemainingStatements pt) (defineFunc (getFirstOperand pt) (cons 'this (getSecondOperand pt)) (getThirdOperand pt) s cont_t) return cont_c cont_b cont_t))
      ((eqv? (getFirstOperation pt) 'funcall) (interpreter (getRemainingStatements pt) (extractState           (if (procedure? (getFirstOperand pt)) ((getFirstOperand pt) (cons (findObject pt) (resolveArgs (getSecondPlusOperands pt) s cont_t)) s) ((car (m_eval (getFirstOperand pt) s cont_t)) (cons (findObject pt) (resolveArgs (getSecondPlusOperands pt) s cont_t)) s))          ) return cont_c cont_b cont_t)) ; TODO I think I passed an incorrect throw continuation in the return arg of this interpreter call -Ryan
      ((eqv? (getFirstOperation pt) 'class) (interpreter (getRemainingStatements pt) (defineClass (getFirstOperand pt) (getSecondOperand pt) (extractState (interpreter (getThirdOperand pt) (addLayer s) return cont_c cont_b cont_t))) return cont_c cont_b cont_t))
      ((eqv? (getFirstOperation pt) 'static-var) (interpreter (getRemainingStatements pt) (decVal (cons (getFirstOperand pt) '()) (car (m_eval (if (null? (getSecondPlusOperands pt)) (getSecondPlusOperands pt) (getSecondOperand pt)) s cont_t)) (cdr (m_eval (if (null? (getSecondPlusOperands pt)) (getSecondPlusOperands pt) (getSecondOperand pt)) s cont_t))) return cont_c cont_b cont_t)) 
      ((eqv? (getFirstOperation pt) 'static-function) (interpreter (getRemainingStatements pt) (defineFunc (cons (getFirstOperand pt) '()) (cons 'this (getSecondOperand pt)) (getThirdOperand pt) s cont_t) return cont_c cont_b cont_t))
      (else (cont_t s (buildError "INTERPRETER ERROR: Invalid statement: " (getFirstOperation pt)))))))

; ------------------------------------------------------------------------------
; m_eval - evaluates an expression
; inputs:
;  st - statement
;  s - state
; outputs:
;  Returns the value of the expression as well as an updated state
; ------------------------------------------------------------------------------
; ------------------------------------------------------------------------------
; ABSTRACTIONS
; ------------------------------------------------------------------------------
(define getStOperator (lambda (st) (car st)))
(define getStFirstOperand (lambda (st) (cadr st)))
(define getStSecondOperand (lambda (st) (caddr st)))
(define getStRemainingOperands (lambda (st) (cddr st)))

(define m_eval
  (lambda (st s cont_t)
    (cond
      ((null? st) (cons '() s))
      ((eqv? st 'true) (cons #t s))
      ((eqv? st 'false) (cons #f s))
      ((atom? st) (if (or (eqv? (getVal st s) 'NULL) (null? (getVal st s))) (cont_t s (buildError "VAR ERROR: Variable used before declaration or assignment: " st)) (cons (getVal st s) s)))
      ((eqv? (getStOperator st) '+) (cons (+ (car (m_eval (getStFirstOperand st) s cont_t)) (car (m_eval (getStSecondOperand st) (cdr (m_eval (getStFirstOperand st) s cont_t)) cont_t))) (cdr (m_eval (getStSecondOperand st) (cdr (m_eval (getStFirstOperand st) s cont_t)) cont_t))))
      ((eqv? (getStOperator st) '-) (if (null? (getStRemainingOperands st)) (cons (- (car (m_eval (getStFirstOperand st) s cont_t))) (cdr (m_eval (getStFirstOperand st) s cont_t))) (cons (- (car (m_eval (getStFirstOperand st) s cont_t)) (car (m_eval (getStSecondOperand st) (cdr (m_eval (getStFirstOperand st) s cont_t)) cont_t))) (cdr (m_eval (getStSecondOperand st) (cdr (m_eval (getStFirstOperand st) s cont_t)) cont_t)))))
      ((eqv? (getStOperator st) '*) (cons (* (car (m_eval (getStFirstOperand st) s cont_t)) (car (m_eval (getStSecondOperand st) (cdr (m_eval (getStFirstOperand st) s cont_t)) cont_t))) (cdr (m_eval (getStSecondOperand st) (cdr (m_eval (getStFirstOperand st) s cont_t)) cont_t))))
      ((eqv? (getStOperator st) '/) (cons (floor (/ (car (m_eval (getStFirstOperand st) s cont_t)) (car (m_eval (getStSecondOperand st) (cdr (m_eval (getStFirstOperand st) s cont_t)) cont_t)))) (cdr (m_eval (getStSecondOperand st) (cdr (m_eval (getStFirstOperand st) s cont_t)) cont_t))))
      ((eqv? (getStOperator st) '%) (cons (modulo (car (m_eval (getStFirstOperand st) s cont_t)) (car (m_eval (getStSecondOperand st) (cdr (m_eval (getStFirstOperand st) s cont_t)) cont_t))) (cdr (m_eval (getStSecondOperand st) (cdr (m_eval (getStFirstOperand st) s cont_t)) cont_t))))
      ((eqv? (getStOperator st) '==) (cons (eqv? (car (m_eval (getStFirstOperand st) s cont_t))  (car (m_eval (getStSecondOperand st) (cdr (m_eval (getStFirstOperand st) s cont_t)) cont_t))) (cdr (m_eval (getStSecondOperand st) (cdr (m_eval (getStFirstOperand st) s cont_t)) cont_t))))
      ((eqv? (getStOperator st) '!=) (cons (not (eqv? (car (m_eval (getStFirstOperand st) s cont_t))  (car (m_eval (getStSecondOperand st) (cdr (m_eval (getStFirstOperand st) s cont_t)) cont_t)))) (cdr (m_eval (getStSecondOperand st) (cdr (m_eval (getStFirstOperand st) s cont_t)) cont_t))))
      ((eqv? (getStOperator st) '>) (cons (> (car (m_eval (getStFirstOperand st) s cont_t))  (car (m_eval (getStSecondOperand st) (cdr (m_eval (getStFirstOperand st) s cont_t)) cont_t))) (cdr (m_eval (getStSecondOperand st) (cdr (m_eval (getStFirstOperand st) s cont_t)) cont_t))))
      ((eqv? (getStOperator st) '>=) (cons (>= (car (m_eval (getStFirstOperand st) s cont_t))  (car (m_eval (getStSecondOperand st) (cdr (m_eval (getStFirstOperand st) s cont_t)) cont_t))) (cdr (m_eval (getStSecondOperand st) (cdr (m_eval (getStFirstOperand st) s cont_t)) cont_t))))
      ((eqv? (getStOperator st) '<) (cons (< (car (m_eval (getStFirstOperand st) s cont_t))  (car (m_eval (getStSecondOperand st) (cdr (m_eval (getStFirstOperand st) s cont_t)) cont_t))) (cdr (m_eval (getStSecondOperand st) (cdr (m_eval (getStFirstOperand st) s cont_t)) cont_t))))
      ((eqv? (getStOperator st) '<=) (cons (<= (car (m_eval (getStFirstOperand st) s cont_t))  (car (m_eval (getStSecondOperand st) (cdr (m_eval (getStFirstOperand st) s cont_t)) cont_t))) (cdr (m_eval (getStSecondOperand st) (cdr (m_eval (getStFirstOperand st) s cont_t)) cont_t))))
      ((eqv? (getStOperator st) '!) (cons (not (car (m_eval (getStFirstOperand st) s cont_t))) (cdr (m_eval (getStFirstOperand st) s cont_t))))
      ((eqv? (getStOperator st) '&&) (cons (and (car (m_eval (getStFirstOperand st) s cont_t))  (car (m_eval (getStSecondOperand st) (cdr (m_eval (getStFirstOperand st) s cont_t)) cont_t))) (cdr (m_eval (getStSecondOperand st) (cdr (m_eval (getStFirstOperand st) s cont_t)) cont_t))))
      ((eqv? (getStOperator st) '||) (cons (or (car (m_eval (getStFirstOperand st) s cont_t))  (car (m_eval (getStSecondOperand st) (cdr (m_eval (getStFirstOperand st) s cont_t)) cont_t))) (cdr (m_eval (getStSecondOperand st) (cdr (m_eval (getStFirstOperand st) s cont_t)) cont_t))))
      ((eqv? (getStOperator st) 'funcall) (let ((func (if (list? (getStFirstOperand st)) (extractValue (m_eval (getStFirstOperand st) s cont_t)) (getVal (getStFirstOperand st) s)))) (func (cons (cadadr st) (resolveArgs (getStRemainingOperands st) s cont_t)) s)))
      ((eqv? (getStOperator st) 'new) (cons ((getConstructor (getVal (getStFirstOperand st) s))) s))
      ((eqv? (getStOperator st) 'dot) (cons (getProperty (getStFirstOperand st) (getStSecondOperand st) s) s))
      (else (cont_t s (buildError "ERROR: Unknown operator/statement: " st))) )))

; ------------------------------------------------------------------------------
; m_assign - handles an assigment statement
; inputs:
;  st - statement
;  s - state
; outputs:
;  The updated state
; ------------------------------------------------------------------------------
; ------------------------------------------------------------------------------
; ABSTRACTIONS
; ------------------------------------------------------------------------------
(define getVar (lambda (st) (car st)))

(define m_assign
  (lambda (st s cont_t)
    (setVal (getVar st) (car (m_eval (getStFirstOperand st) s cont_t)) (cdr (m_eval (getStFirstOperand st) s cont_t))) ))

; ------------------------------------------------------------------------------
; m_if - handles a conditional block
; inputs:
;  condition - The condition on which to run the block
;  ifblock - The block to run if condition is true
;  elseblock - The block to run if condition is false (optional)
;  state - The state before the condition is evaluated
; outputs:
;  The final state after evaluating the condition and, if applicable, running the block
; ------------------------------------------------------------------------------
(define m_if
  (lambda (condition ifblock elseblock state return cont_c cont_b cont_t)
    (cond
      ((null? condition) (cont_t (buildError "CONDITION ERROR: Condition cannot be null." "")))
      ((null? ifblock) (cont_t (buildError "CONDITION ERROR: Block cannot be null." "")))
      ((null? state) (cont_t (buildError "CONDITION ERROR: State cannot be null." "")))
      ((car (m_eval condition state cont_t)) (extractState (interpreter (cons ifblock '()) (cdr (m_eval condition state cont_t)) return cont_c cont_b cont_t)))
      (else (if (null? elseblock) (cdr (m_eval condition state cont_t)) (extractState (interpreter (cons elseblock '()) (cdr (m_eval condition state cont_t)) return cont_c cont_b cont_t)))))))
      
; ------------------------------------------------------------------------------
; decVal - declares and initializes a variable
; inputs:
;  name - variable name
;  value - variable value
;  state - the current state
; outputs:
;  The updated state
;
; NOTES:
;  We implemented decVal to allow a local variable to have the same name as a
;  variable in a different layer. It throws an error if you attept to declare
;  the same variable twice in the same layer.
; ------------------------------------------------------------------------------
(define decVal 
  (lambda (name value state)
    (cond
      ; if name is null, error
      ((null? name) (cont_t (buildError "DECVAL ERROR: Failed adding variable to state." "")))
      ; if the var name already exists, error
      ((not (nameAvailable name (caar state))) (cont_t (buildError "DECVAL NAMESPACE ERROR: Namespace for var already occupied: " name)))
      (else
       ; add name and value to state
       (cons (cons (cons name (caar state)) (cons (cons value (cadar state)) '())) (cdr state))))))

; Check to see if this variable is already defined on this layer of the state. That would be illegal. However, if the variable is declared on a previous layer,
; it can legally be redeclared on this layer.
(define nameAvailable
  (lambda (name varsLayer)
    (cond
      ((null? varsLayer) #t)
      ((eqv? (car varsLayer) name) #f)
      (else (nameAvailable name (cdr varsLayer))))))

; ------------------------------------------------------------------------------
; setVal - sets the value of an initialized variable
; inputs:
;  name - variable name
;  value - variable value
;  state - the current state
; outputs:
;  The updated state
; ------------------------------------------------------------------------------

(define setVal
  (lambda (name value state)
    (cond
      ((null? state) (cont_t state (buildError "SETVAL ERROR: Variable not found: " name)))
      ((and (list? name) (eqv? (car name) 'dot)) (setVal (cadr name) (setProperty (car (m_eval (cadr name) state throwError)) (caddr name) value) state))
      ((list? name) state)
      ((eqv? #f (call/cc (lambda (cont) (cont (setVal* name value (car state) cont))))) (cons (car state) (setVal name value (cdr state))))
      (else (cons (setVal* name value (car state) (lambda (v) (error v))) (cdr state))))))

(define setVal*
  (lambda (name value state exit)
    (cond
      ; if the names or values of states are null, error
      ((and (null? (car state)) (null? (cadr state))) (exit #f))
      ; if it finds the var, set var 
      ((eqv? name (caar state)) (cons (car state) (cons (cons value (cdadr state)) '())))    
      ; else recurse on the next state value 
      (else (cons (cons (caar state) (car (setValRec name value state exit))) (cons (cons (caadr state) (cadr (setValRec name value state exit))) '()))) )))

; helper to shorten recursive line
(define setValRec
  (lambda (name value state exit)
    (setVal* name value (cons (cdar state) (cons (cdadr state) '())) exit) ))

; ------------------------------------------------------------------------------
; getVal - wrapper method for getValInner to check for implicit 'this' which is a wrapper for getVal* to deconstruct state variable as necessary
; inputs:
;  name - the name of the variable to find
;  state - the state to look in
; outputs:
;  See return values for getVal*
; ------------------------------------------------------------------------------
(define getVal
  (lambda (name state)
    (let ((result (getValInner name state))) (if (eqv? result 'NULL) (getValInner (getAttributes (getValInner 'this state)) state) result))))



    
(define getValInner
  (lambda (name state)
    (cond
      ((null? name) (throwError state (buildError "GETVAL ERROR: Name cannot be null." "")))
      ((null? state) 'NULL)
      ((list? name) (if (eqv? (car name) 'new) ((getConstructor (getValInner (cadr name) state))) name))
      ((eqv? name 'super) (getSuper (getValInner 'this state) state))
      ((or (integer? name) (boolean? name)) name)
      ((or (eqv? name 'true) (eqv? name 'false)) name)
      (else
       (if (eqv? (getVal* name (caar state) (cadar state)) 'NULL) (getValInner name (cdr state)) (getVal* name (caar state) (cadar state)))))))

; ------------------------------------------------------------------------------
; getVal* - gets the value of a given variable
; inputs:
;  name - the name of the variable to find
;  vars - the list of variable names from the current state
;  vals - the list of values in the current state
; outputs:
;  Value of variable, if initialized
;  '() if defined but not initialized
;  NULL if not defined
; ------------------------------------------------------------------------------
(define getVal*
  (lambda (name vars vals)
    (cond
      ((and (null? vars) (null? vals)) 'NULL)
      ((and (not (null? vars)) (not (null? vals)))
       (if (eqv? name (car vars)) (car vals) (getVal* name (cdr vars) (cdr vals))))
      (else (cont_t (buildError "STATE MISMATCH ERROR: Different number of Variables and Values." ""))))))

; ------------------------------------------------------------------------------
; m_while - handles a WHILE loop
; inputs:
;  condition - The condition on which to run the block
;  block - The block to run if condition is true
;  state - The state before the condition is evaluated
; outputs:
;  The final state after the condition evaluates to false
; ------------------------------------------------------------------------------
(define m_while
  (lambda (condition block state return cont_b cont_t)
    (cond
      ((null? condition) (cont_t (buildError "LOOP ERROR: Condition cannot be null." "")))
      ((null? block) (cont_t (buildError "LOOP ERROR: Block cannot be null." "")))
      ((null? state) (cont_t (buildError "LOOP ERROR: State cannot be null." "")))
      ((car (m_eval condition state cont_t)) (m_while condition block (call/cc (lambda (cont_c) (extractState (interpreter (cons block '()) (cdr (m_eval condition state cont_t)) return (lambda (s) (cont_c (popLayer s))) (lambda (s) (cont_b (popLayer s))) cont_t)))) return cont_b cont_t) )
      (else (cont_b (cdr (m_eval condition state cont_t)))))))

; ------------------------------------------------------------------------------
; m_block - handles a block
; inputs:
;  block - The block to run
;  state - The state before the block is evaluated
; outputs:
;  The final state after the condition evaluates to false
; ------------------------------------------------------------------------------
(define m_block
  (lambda (block state return cont_c cont_b cont_t)
    (popLayer (extractState (interpreter block (addLayer state) return cont_c cont_b (lambda (s e) (cont_t (popLayer s) e))))) ))

; ------------------------------------------------------------------------------
; m_block_args - handles a block where arguments are passed in
; inputs:
;  block - The block to run
;  state - The state before the block is evaluated
; outputs:
;  The final state after the condition evaluates to false
; ------------------------------------------------------------------------------
(define m_block_args
  (lambda (block state return cont_c cont_b cont_t)
    (popLayer (extractState (interpreter block state return cont_c cont_b (lambda (s e) (cont_t (popLayer s) e))))) ))


; ------------------------------------------------------------------------------
; ABSTRACTIONS
; ------------------------------------------------------------------------------
(define addLayer (lambda (s) (cons '(() ()) s)))
(define popLayer (lambda (s) (cdr s)))


; ------------------------------------------------------------------------------
; m_try - handles a TRY block
; inputs:
;  block - The block to try
;  catch - The associated CATCH code
;  finally - The associated FINALLY code
;  s - The initial state
;  return - The continuation for RETURN statements
;  cont_c - The continuation for CONTINUE statements
;  cont_b - The continuation for BREAK statements
;  cont_t - The previous continuation for THROW statements
;  
; outputs:
;  The final state after the TRY, CATCH and FINALLY blocks execute.
; ------------------------------------------------------------------------------
(define m_try
  (lambda (block catch finally s return cont_c cont_b cont_t)
    (m_finally finally (call/cc
                        (lambda (exit)
                          (exit (m_block block s return cont_c cont_b (lambda (tryState e)
                                                                           (exit (m_catch catch e tryState return cont_c cont_b cont_t))))))) return cont_c cont_b cont_t)) )

; ------------------------------------------------------------------------------
; m_catch - handles a caught exception
; inputs:
;  catch - The associated CATCH code
;  e - exception thrown
;  s - The state when exception was thrown
;  return - The continuation for RETURN statements
;  cont_c - The continuation for CONTINUE statements
;  cont_b - The continuation for BREAK statements
;  cont_t - The previous continuation for THROW statements
;  
; outputs:
;  The final state after the CATCH block executes.
; ------------------------------------------------------------------------------
(define m_catch
  (lambda (catch e s return cont_c cont_b cont_t)
    (cond
      ((null? catch) s)
      (else (m_block_args (caddr catch) (decVal (caadr catch) e (addLayer s)) return cont_c cont_b cont_t)) )))


; ------------------------------------------------------------------------------
; m_finally - handles a finally block
; inputs:
;  finally - The associated FINALLY code
;  s - The state after try/catch was thrown
;  return - The continuation for RETURN statements
;  cont_c - The continuation for CONTINUE statements
;  cont_b - The continuation for BREAK statements
;  cont_t - The previous continuation for THROW statements
;  
; outputs:
;  The final state after the finally block executes.
; ------------------------------------------------------------------------------
(define m_finally
  (lambda (finally s return cont_c cont_b cont_t)
    (cond
      ((null? finally) s)
      (else (m_block (cadr finally) s return cont_c cont_b cont_t)) )))

; ------------------------------------------------------------------------------
; defineFunc - Defines a function and adds it to the state
; inputs:
;   name - The name of the function
;   args - A list of arguments for the function
;   block - The code in the body of the function
;   s - The state at the time of the definition
;
; outputs:
;   The final state with this function added on
; ------------------------------------------------------------------------------
(define defineFunc
  (lambda (name args block s cont_t)
    (decVal name
            (lambda (argList state)
;              (car (m_eval (findObject pt) s cont_t))
                   (let ((newState (updateThis name (car argList) state (m_func block
                           (addArgs args (applyThis argList state) (reduceState state (if (eqv? (listLength state) 1) 0 (+ 1 (- (listLength state) (listLength s)))))) cont_t)))) (valState (extractValue newState) (if (> (- (listLength state) (listLength (extractState newState))) -1)
                                                                                                                                                                                            (restoreState state (extractState newState) (- (listLength state) (listLength (extractState newState))))
                                                                                                                                                                                            (popLayer (extractState newState)))
                                                                                                                                                                                            ))) s)))
(define applyThis
  (lambda (argList state)
    (cons (getVal (car argList) state) (cdr argList))))

(define updateThis
  (lambda (name newThis oldState newState)
    (if (and (list? name) (eqv? (car name) 'main)) newState
    (cons (extractValue newState) (setVal newThis (getVal 'this (extractState newState)) (cons (car oldState) (reduceState (extractState newState) (+ 1 (- (listLength (extractState newState)) (listLength oldState))))))))))


(define reduceState
  (lambda (state removeLayers)
    (cond
      ((zero? removeLayers) state)
      (else (reduceState (cdr state) (- removeLayers 1))))))

(define listLength
  (lambda (list)
    (cond
      ((null? list) 0)
      ((atom? (car list)) (listLength (cdr list)))
      (else (+ 1 (listLength (cdr list)))))))

(define restoreState
  (lambda (original new addLayers)
    (cond
      ((zero? addLayers) new)
      (else (cons (car original) (restoreState (cdr original) new (- addLayers 1)))))))

; ------------------------------------------------------------------------------
; addArgs - Adds the arguments to a function onto a new state layer (DYNAMIC SCOPING + CALL BY VALUE)
; inputs:
;   argNames - The names of the arguments
;   argValues - The values of the arguments
;   state - The state prior to adding the arguments
;
; outputs:
;   The updated state with arguments on a new layer
; ------------------------------------------------------------------------------
(define addArgs
  (lambda (argNames argValues state)
    (cons (cons argNames (cons argValues '())) state)))

; ------------------------------------------------------------------------------
; resolveArgs - Resolves the argument list to a list of values
; inputs:
;   argList - The list of arguments to resolve
;   state - The state prior to adding the arguments
;
; outputs:
;   The updated state with arguments on a new layer
; ------------------------------------------------------------------------------
(define resolveArgs
  (lambda (argList state cont_t)
    (cond
      ((null? argList) '())
      ((and (list? (car argList)) (and (not (eqv? (caar argList) 'object)) (not (eqv? (caar argList) 'class)))) (cons (extractValue (m_eval (car argList) state cont_t)) (resolveArgs (cdr argList) state cont_t)))
      ((and (list? (car argList)) (or (eqv? (caar argList) 'object)) (eqv? (caar argList) 'class)) (cons (car argList) (resolveArgs (cdr argList) state cont_t)))
      (else (cons (getVal (car argList) state) (resolveArgs (cdr argList) state cont_t))))))

; ------------------------------------------------------------------------------
; m_func - Runs a function
; inputs:
;   block - The internal block of the function
;   s - The state at the time of the function call, with arguments applied
;   cont_t - The throw continuation from the point of the function call
;
; outputs:
;   The final state after this function has run
; ------------------------------------------------------------------------------
(define m_func
  (lambda (block s cont_t)
    (call/cc
     (lambda (return)
       (interpreter block s return continueError breakError cont_t)))))

(define clearFunctionState
  (lambda (returnVals)
    (cons (extractValue returnVals) (popLayer (extractState returnVals)))))

(define valState
  (lambda (value state)
    (cons value state)))

(define extractValue
  (lambda (returnVals)
    (car returnVals)))

(define extractState
  (lambda (returnVals)
    (cdr returnVals)))


; ------------------------------------------------------------------------------
; defineClass
; Add a new class onto the state and return new state.
; Class definitions are always on root layer, so the state
; here will always have 2 layers: other Classes + defs for this class
;
; inputs:
;   name - The name of the class
;   extends - (extends <classname>) or ()
;   state - The state ((<root_state_layer>) ((definitions_for_this_class>))
;
; ouptuts:
;   A new state with this class definition added to it
; ------------------------------------------------------------------------------

(define defineClass
  (lambda (name extends state)
    (decVal name (separateVars (car (getFirstLayer state)) (cadr (getFirstLayer state)) (lambda (staticVars staticVals nonStaticVars nonStaticVals)
                          (cons 'class (cons (if (null? extends) '() (cadr extends)) (cons      (cons (cons staticVars (cons staticVals '())) '())       (cons (lambda ()
                                                                                                                                           (cons 'object (cons name (cons (cons (cons nonStaticVars (cons nonStaticVals '()))   (if (null? extends) '() (cons (getAttributes ((getConstructor (getVal (cadr extends) state)))) '()))) '())))) '())))))) (popLayer state))))


(define separateVars
  (lambda (vars vals return)
    (cond
      ((null? vars) (return '() '() '() '()))
      ((list? (car vars)) (separateVars (cdr vars) (cdr vals) (lambda (sVars sVals nsVars nsVals)
                                                                (return (cons (caar vars) sVars) (cons (car vals) sVals) nsVars nsVals))))
      (else (separateVars (cdr vars) (cdr vals) (lambda (sVars sVals nsVars nsVals)
                                                  (return sVars sVals (cons (car vars) nsVars) (cons (car vals) nsVals))))))))
(define getClassParent (lambda (obj) (cadr obj)))
(define getAttributes (lambda (obj) (caddr obj)))
(define getConstructor (lambda (class) (cadddr class)))
(define isInstance? (lambda (obj) (eqv? (getObjectType obj) 'object)))
(define getObjectType (lambda (obj) (car obj)))
    
(define getProperty
  (lambda (object property state)
    (let ((attrs (getAttributes (getVal object state)))) (if (eqv? 'NULL (getVal property attrs)) (if (null? (getClassParent object)) 'NULL (getProperty (getClassParent object) property state)) (getVal property attrs)))))

(define setProperty
  (lambda (object property value)
    (cons (car object) (cons (cadr object) (cons (setVal property value (caddr object)) '())))))

(define getSuper
  (lambda (object state)
    (cond
      ((eqv? (car object) 'object) (cons 'object (cons (getClassParent (getVal (getClassParent object) state)) (popLayer (getAttributes object)))))
      ((eqv? (car object) 'class) (getVal (getClassParent object) state)))))

                                                 
; ------------------------------------------------------------------------------
; atom?
; ------------------------------------------------------------------------------
(define atom?
  (lambda (x)
    (and (not (pair? x)) (not (null? x))) ))