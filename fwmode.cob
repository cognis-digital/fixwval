      *> ============================================================================
      *> fwmode — legacy fixed-width numeric-field validator (COBOL / GnuCOBOL)
      *> ----------------------------------------------------------------------------
      *> The original fixwval capability, retained as a secondary tool. Verifies
      *> that a numeric field at a fixed column range is present and all-digits in
      *> every record of a flat file. Useful for mainframe batch input sanitation
      *> that is NOT FIX-formatted (e.g. positional COBOL copybook records).
      *>
      *> Usage:
      *>   fwmode <datafile> <numStart> <numLen>
      *>     numStart  1-based column where the numeric field begins
      *>     numLen    width of the numeric field
      *>
      *> Output: JSON summary on stdout. RETURN-CODE 2 if any record fails, else 0.
      *> ============================================================================
       IDENTIFICATION DIVISION.
       PROGRAM-ID. fwmode.

       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT IN-FILE ASSIGN TO DYNAMIC WS-PATH
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS WS-FS.

       DATA DIVISION.
       FILE SECTION.
       FD IN-FILE.
       01 IN-REC            PIC X(4096).

       WORKING-STORAGE SECTION.
       01 WS-PATH           PIC X(256).
       01 WS-ARG            PIC X(64).
       01 WS-FS             PIC XX.
       01 WS-NSTART         PIC 9(5) VALUE 0.
       01 WS-NLEN           PIC 9(5) VALUE 0.
       01 WS-NEED           PIC 9(5) VALUE 0.
       01 WS-LEN            PIC 9(5) VALUE 0.
       01 WS-POS            PIC 9(5) VALUE 0.
       01 WS-I              PIC 9(5) VALUE 0.
       01 WS-CH             PIC X.
       01 WS-NUMOK          PIC X VALUE 'Y'.
       01 WS-EOF            PIC X VALUE 'N'.
       01 CNT-TOTAL         PIC 9(9) VALUE 0.
       01 CNT-OK            PIC 9(9) VALUE 0.
       01 CNT-BAD           PIC 9(9) VALUE 0.
       01 WS-DISP           PIC Z(8)9.

       PROCEDURE DIVISION.
       MAIN-PARA.
           ACCEPT WS-PATH FROM ARGUMENT-VALUE
           ACCEPT WS-ARG  FROM ARGUMENT-VALUE
           MOVE FUNCTION NUMVAL(WS-ARG) TO WS-NSTART
           ACCEPT WS-ARG  FROM ARGUMENT-VALUE
           MOVE FUNCTION NUMVAL(WS-ARG) TO WS-NLEN

           IF WS-PATH = SPACES OR WS-NSTART = 0 OR WS-NLEN = 0
               DISPLAY "usage: fwmode <datafile> <numStart> <numLen>"
                   UPON SYSERR
               MOVE 1 TO RETURN-CODE
               STOP RUN
           END-IF

           COMPUTE WS-NEED = WS-NSTART + WS-NLEN - 1

           OPEN INPUT IN-FILE
           IF WS-FS NOT = "00"
               DISPLAY "fwmode: cannot open input file" UPON SYSERR
               MOVE 1 TO RETURN-CODE
               STOP RUN
           END-IF

           PERFORM UNTIL WS-EOF = 'Y'
               READ IN-FILE
                   AT END MOVE 'Y' TO WS-EOF
                   NOT AT END PERFORM CHECK-REC
               END-READ
           END-PERFORM
           CLOSE IN-FILE

           PERFORM EMIT-JSON

           IF CNT-BAD > 0
               MOVE 2 TO RETURN-CODE
           ELSE
               MOVE 0 TO RETURN-CODE
           END-IF
           STOP RUN.

       CHECK-REC.
           ADD 1 TO CNT-TOTAL
           MOVE FUNCTION LENGTH(FUNCTION TRIM(IN-REC TRAILING)) TO WS-LEN
           MOVE 'Y' TO WS-NUMOK
           IF WS-LEN < WS-NEED
               MOVE 'N' TO WS-NUMOK
           ELSE
               PERFORM VARYING WS-I FROM 0 BY 1 UNTIL WS-I >= WS-NLEN
                   COMPUTE WS-POS = WS-NSTART + WS-I
                   MOVE IN-REC(WS-POS:1) TO WS-CH
                   IF WS-CH < '0' OR WS-CH > '9'
                       MOVE 'N' TO WS-NUMOK
                   END-IF
               END-PERFORM
           END-IF
           IF WS-NUMOK = 'Y'
               ADD 1 TO CNT-OK
           ELSE
               ADD 1 TO CNT-BAD
           END-IF.

       EMIT-JSON.
           DISPLAY '{"tool":"fwmode","records":' WITH NO ADVANCING
           MOVE CNT-TOTAL TO WS-DISP
           DISPLAY FUNCTION TRIM(WS-DISP) WITH NO ADVANCING
           DISPLAY ',"ok":' WITH NO ADVANCING
           MOVE CNT-OK TO WS-DISP
           DISPLAY FUNCTION TRIM(WS-DISP) WITH NO ADVANCING
           DISPLAY ',"bad":' WITH NO ADVANCING
           MOVE CNT-BAD TO WS-DISP
           DISPLAY FUNCTION TRIM(WS-DISP) WITH NO ADVANCING
           DISPLAY ',"field_start":' WITH NO ADVANCING
           MOVE WS-NSTART TO WS-DISP
           DISPLAY FUNCTION TRIM(WS-DISP) WITH NO ADVANCING
           DISPLAY ',"field_len":' WITH NO ADVANCING
           MOVE WS-NLEN TO WS-DISP
           DISPLAY FUNCTION TRIM(WS-DISP) WITH NO ADVANCING
           DISPLAY '}'.
