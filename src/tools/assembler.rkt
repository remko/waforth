#lang racket

(define (asm-symbol? x)
  (and (symbol? x) (eq? (string-ref (symbol->string x) 0) #\!)))

(define (preprocess x)
  (cond ((list? x) 
         (cond ((null? x) '())
               ((and (list? (car x)) (asm-symbol? (caar x)))
                (append (eval (car x)) (preprocess (cdr x))))
               (else 
                (cons (preprocess (car x)) (preprocess (cdr x))))))
        ((asm-symbol? x)
         (eval x))
        (else x)))

(define (byte->hex byte)
  (define digits "0123456789ABCDEF")
  (string (string-ref digits (quotient byte 16))
          (string-ref digits (remainder byte 16))))

(define (byte->string byte)
  (cond ((> byte 255) (raise "Illegal byte"))
        ((and (> byte 32) (< byte 127) (not (or (eqv? byte 34) (eqv? byte 92))))
         (string (integer->char byte)))
        (else (string-append "\\" (byte->hex byte))))) 

(define (string-escape s)
  (string-join (map byte->string (map char->integer (string->list s))) ""))

(define (serialize x)
  (cond ((list? x)
         (string-append "(" (string-join (map serialize x) " ") ")"))
        ((string? x)
         (string-append "\"" (string-escape x) "\""))
        ((symbol? x)
         (symbol->string x))
        ((number? x)
         (number->string x))
        ((bytes? x)
         (string-append 
           "\"" 
           (string-join (map byte->string (bytes->list x)) "")
           "\""))
        (else (raise (list "Unexpected type" x)))))

(define (priority x)
  (cond ((eq? x 'module) 0)
        ((and (list? x) (eq? (car x) 'import)) 1000000)
        ((and (list? x) (eq? (car x) 'table))  2000000)
        ((and (list? x) (eq? (car x) 'memory)) 2000000)
        ((and (list? x) (eq? (car x) 'global)) 3000000)
        ((and (list? x) (eq? (car x) 'elem))   (+ 4000000 (car (cdr (car (cdr x))))))
        ((and (list? x) (eq? (car x) 'data))   (+ 5000000 (car (cdr (car (cdr x))))))
        (else 100000000)))

(define (wasm-assemble module)
  (display 
    (serialize
      (sort (preprocess module)
            (lambda (x y) (< (priority x) (priority y)))))))

(define-syntax module
  (syntax-rules ()
    ((_ arg ...)
     (wasm-assemble '(module arg ...)))))

(provide module)
