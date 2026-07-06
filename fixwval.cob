      *> ============================================================================
      *> fixwval — FIX Wire Validator (COBOL / GnuCOBOL)
      *> ----------------------------------------------------------------------------
      *> Part of the Cognis Neural Suite. Single-purpose, JSON-out, CI-tested.
      *>
      *> Validates FIX (Financial Information eXchange) protocol messages: field
      *> structure, mandatory header order, BodyLength (tag 9), CheckSum (tag 10),
      *> MsgType (tag 35) recognition, per-MsgType required fields, enum values,
      *> and basic data-type checks. Supports FIX.4.2 / FIX.4.4 / FIXT.1.1 (5.0).
      *>
      *> A FIX message is a series of tag=value fields delimited by SOH (0x01).
      *> For human-readable fixtures the delimiter may be a pipe '|' (--soh PIPE).
      *> The tool auto-detects real SOH vs pipe when --soh is not given.
      *>
      *> Usage:
      *>   fixwval <file> [--soh PIPE|SOH|AUTO] [--json]
      *>     <file>        file of FIX messages, one per line
      *>     --soh PIPE    field delimiter is '|' (human-readable fixtures)
      *>     --soh SOH     field delimiter is ASCII 0x01 (wire capture)
      *>     --soh AUTO    detect per line (default)
      *>     --json        machine-readable JSON only (suppress human report)
      *>
      *> Output: per-message human report + JSON summary object on stdout.
      *> Exit:   2 if any message FAILS, 0 if all PASS, 1 on usage/IO error.
      *>
      *> Legacy fixed-width numeric-field mode is retained; see fwmode.cob.
      *> ============================================================================
       IDENTIFICATION DIVISION.
       PROGRAM-ID. fixwval.

       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT IN-FILE ASSIGN TO DYNAMIC WS-PATH
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS WS-FS.

       DATA DIVISION.
       FILE SECTION.
       FD IN-FILE.
       01 IN-REC                      PIC X(8192).

       WORKING-STORAGE SECTION.
      *> ---- CLI / IO ----
       01 WS-PATH                     PIC X(1024) VALUE SPACES.
       01 WS-ARG                      PIC X(1024).
       01 WS-FS                       PIC XX.
       01 WS-EOF                      PIC X VALUE 'N'.
       01 WS-SOH-MODE                 PIC X(4) VALUE 'AUTO'.
       01 WS-JSON-ONLY                PIC X VALUE 'N'.
       01 WS-DELIM                    PIC X.
       01 SOH-CHAR                    PIC X.
       01 PIPE-CHAR                   PIC X VALUE '|'.

      *> ---- line buffer ----
       01 WS-LINE                     PIC X(8192).
       01 WS-LINE-LEN                 PIC 9(5) VALUE 0.

      *> ---- parsed field table ----
       01 WS-MAX-FIELDS               PIC 9(4) VALUE 512.
       01 FIELD-TABLE.
          05 FLD OCCURS 512 TIMES INDEXED BY FX.
             10 FLD-TAG               PIC X(16).
             10 FLD-TAGNUM           PIC 9(6).
             10 FLD-TAGNUM-OK        PIC X.
             10 FLD-VAL               PIC X(1024).
             10 FLD-VLEN              PIC 9(5).
       01 WS-NFIELDS                  PIC 9(4) VALUE 0.

      *> ---- parse scratch ----
       01 WS-I                        PIC 9(5).
       01 WS-J                        PIC 9(5).
       01 WS-K                        PIC 9(5).
       01 WS-CH                       PIC X.
       01 WS-CHV                      PIC 9(3).
       01 WS-TOK                      PIC X(1200).
       01 WS-TOK-LEN                  PIC 9(5).
       01 WS-EQ-POS                   PIC 9(5).
       01 WS-FOUND                    PIC X.
      *> dedicated parse-loop vars (never touched by sub-paragraphs)
       01 WS-P                        PIC 9(5).
       01 WS-TS                       PIC 9(5).
       01 WS-PTOK                     PIC X(1200).
       01 WS-PTLEN                    PIC 9(5).
       01 WS-PEQ                      PIC 9(5).
       01 WS-PN                       PIC 9(5).
       01 WS-TN-I                     PIC 9(5).
       01 WS-TN-LEN                   PIC 9(5).
       01 WS-TN-CH                    PIC X.

      *> ---- checksum / bodylength ----
       01 WS-SUM                      PIC 9(12) VALUE 0.
       01 WS-CALC-CS                  PIC 9(3).
       01 WS-CALC-CS-DISP            PIC 999.
       01 WS-DECL-CS                  PIC X(8).
       01 WS-BODYLEN-CALC            PIC 9(6) VALUE 0.
       01 WS-BODYLEN-DECL            PIC 9(9) VALUE 0.
       01 WS-BODYLEN-DECL-RAW        PIC X(16).
       01 WS-CS-START                 PIC 9(5).
       01 WS-BL-START                 PIC 9(5).
       01 WS-BL-END                   PIC 9(5).
       01 WS-AT-TAG10                 PIC X.

      *> ---- header / version state ----
       01 WS-BEGINSTR                 PIC X(16) VALUE SPACES.
       01 WS-MSGTYPE                  PIC X(8) VALUE SPACES.
       01 WS-VERSION                  PIC X(8) VALUE SPACES.

      *> ---- per-message result ----
       01 WS-MSG-OK                   PIC X.
       01 WS-VIOL-COUNT               PIC 9(4) VALUE 0.
       01 WS-MSG-INDEX                PIC 9(9) VALUE 0.

      *> ---- violation buffer for JSON ----
       01 VIOL-TABLE.
          05 VIOL OCCURS 128 TIMES INDEXED BY VZ.
             10 V-CODE                PIC X(24).
             10 V-DETAIL              PIC X(160).
       01 WS-NVIOL                    PIC 9(4) VALUE 0.

      *> ---- summary counters ----
       01 CNT-TOTAL                   PIC 9(9) VALUE 0.
       01 CNT-PASS                    PIC 9(9) VALUE 0.
       01 CNT-FAIL                    PIC 9(9) VALUE 0.

      *> ---- display scratch ----
       01 WS-DISP                     PIC Z(8)9.
       01 WS-FIRST-VIOL               PIC X.
       01 WS-FIRST-MSG                PIC X VALUE 'Y'.

      *> ---- MsgType descriptor table (name lookup) ----
       01 MT-TABLE.
          05 FILLER PIC X(20) VALUE '0   Heartbeat'.
          05 FILLER PIC X(20) VALUE '1   TestRequest'.
          05 FILLER PIC X(20) VALUE '2   ResendRequest'.
          05 FILLER PIC X(20) VALUE '3   Reject'.
          05 FILLER PIC X(20) VALUE '4   SequenceReset'.
          05 FILLER PIC X(20) VALUE '5   Logout'.
          05 FILLER PIC X(20) VALUE 'A   Logon'.
          05 FILLER PIC X(20) VALUE 'D   NewOrderSingle'.
          05 FILLER PIC X(20) VALUE '8   ExecutionRpt'.
          05 FILLER PIC X(20) VALUE '9   OrderCxlReject'.
          05 FILLER PIC X(20) VALUE 'F   OrderCxlReq'.
          05 FILLER PIC X(20) VALUE 'G   OrderCxlRepl'.
          05 FILLER PIC X(20) VALUE 'V   MktDataReq'.
          05 FILLER PIC X(20) VALUE 'j   BizMsgReject'.
       01 MT-TABLE-R REDEFINES MT-TABLE.
          05 MT-ENTRY OCCURS 14 TIMES INDEXED BY MTX.
             10 MT-CODE               PIC X(4).
             10 MT-NAME               PIC X(16).
       01 MT-COUNT                    PIC 9(3) VALUE 14.
       01 WS-MT-NAME                  PIC X(16) VALUE SPACES.
       01 WS-MT-KNOWN                 PIC X.
       01 WS-MT-SESSION               PIC X.

      *> ---- Required-field rules: msgtype -> required tag ----
      *> Common (all app+session need 8/9/35/49/56/34/52 minimally).
       01 REQ-TABLE.
          05 FILLER PIC X(12) VALUE 'A   98'.
          05 FILLER PIC X(12) VALUE 'A   108'.
          05 FILLER PIC X(12) VALUE 'D   11'.
          05 FILLER PIC X(12) VALUE 'D   55'.
          05 FILLER PIC X(12) VALUE 'D   54'.
          05 FILLER PIC X(12) VALUE 'D   60'.
          05 FILLER PIC X(12) VALUE 'D   40'.
          05 FILLER PIC X(12) VALUE 'D   38'.
          05 FILLER PIC X(12) VALUE '8   37'.
          05 FILLER PIC X(12) VALUE '8   17'.
          05 FILLER PIC X(12) VALUE '8   150'.
          05 FILLER PIC X(12) VALUE '8   39'.
          05 FILLER PIC X(12) VALUE '8   55'.
          05 FILLER PIC X(12) VALUE '8   54'.
          05 FILLER PIC X(12) VALUE 'F   41'.
          05 FILLER PIC X(12) VALUE 'F   11'.
          05 FILLER PIC X(12) VALUE 'F   55'.
          05 FILLER PIC X(12) VALUE 'F   54'.
          05 FILLER PIC X(12) VALUE 'G   41'.
          05 FILLER PIC X(12) VALUE 'G   11'.
          05 FILLER PIC X(12) VALUE 'G   55'.
          05 FILLER PIC X(12) VALUE 'G   54'.
          05 FILLER PIC X(12) VALUE 'G   38'.
          05 FILLER PIC X(12) VALUE 'G   40'.
          05 FILLER PIC X(12) VALUE '3   45'.
          05 FILLER PIC X(12) VALUE '1   112'.
       01 REQ-TABLE-R REDEFINES REQ-TABLE.
          05 REQ-ENTRY OCCURS 26 TIMES INDEXED BY RQX.
             10 REQ-MT                PIC X(4).
             10 REQ-TAG               PIC X(8).
       01 REQ-COUNT                   PIC 9(3) VALUE 26.

      *> ---- Session-level required present on every message ----
      *> 49 SenderCompID, 56 TargetCompID, 34 MsgSeqNum, 52 SendingTime
       01 SESS-TABLE.
          05 FILLER PIC X(4) VALUE '49'.
          05 FILLER PIC X(4) VALUE '56'.
          05 FILLER PIC X(4) VALUE '34'.
          05 FILLER PIC X(4) VALUE '52'.
       01 SESS-TABLE-R REDEFINES SESS-TABLE.
          05 SESS-TAG OCCURS 4 TIMES INDEXED BY SSX PIC X(4).
       01 SESS-COUNT                  PIC 9(3) VALUE 4.

      *> ---- Enum rules: tag -> allowed value ----
       01 ENUM-TABLE.
      *> 54 Side
          05 FILLER PIC X(10) VALUE '54  1'.
          05 FILLER PIC X(10) VALUE '54  2'.
          05 FILLER PIC X(10) VALUE '54  3'.
          05 FILLER PIC X(10) VALUE '54  4'.
          05 FILLER PIC X(10) VALUE '54  5'.
          05 FILLER PIC X(10) VALUE '54  6'.
          05 FILLER PIC X(10) VALUE '54  7'.
          05 FILLER PIC X(10) VALUE '54  8'.
          05 FILLER PIC X(10) VALUE '54  9'.
      *> 40 OrdType
          05 FILLER PIC X(10) VALUE '40  1'.
          05 FILLER PIC X(10) VALUE '40  2'.
          05 FILLER PIC X(10) VALUE '40  3'.
          05 FILLER PIC X(10) VALUE '40  4'.
          05 FILLER PIC X(10) VALUE '40  5'.
          05 FILLER PIC X(10) VALUE '40  6'.
          05 FILLER PIC X(10) VALUE '40  7'.
          05 FILLER PIC X(10) VALUE '40  8'.
          05 FILLER PIC X(10) VALUE '40  9'.
          05 FILLER PIC X(10) VALUE '40  D'.
      *> 59 TimeInForce
          05 FILLER PIC X(10) VALUE '59  0'.
          05 FILLER PIC X(10) VALUE '59  1'.
          05 FILLER PIC X(10) VALUE '59  2'.
          05 FILLER PIC X(10) VALUE '59  3'.
          05 FILLER PIC X(10) VALUE '59  4'.
          05 FILLER PIC X(10) VALUE '59  5'.
          05 FILLER PIC X(10) VALUE '59  6'.
          05 FILLER PIC X(10) VALUE '59  7'.
      *> 39 OrdStatus
          05 FILLER PIC X(10) VALUE '39  0'.
          05 FILLER PIC X(10) VALUE '39  1'.
          05 FILLER PIC X(10) VALUE '39  2'.
          05 FILLER PIC X(10) VALUE '39  3'.
          05 FILLER PIC X(10) VALUE '39  4'.
          05 FILLER PIC X(10) VALUE '39  5'.
          05 FILLER PIC X(10) VALUE '39  6'.
          05 FILLER PIC X(10) VALUE '39  7'.
          05 FILLER PIC X(10) VALUE '39  8'.
          05 FILLER PIC X(10) VALUE '39  9'.
          05 FILLER PIC X(10) VALUE '39  A'.
          05 FILLER PIC X(10) VALUE '39  B'.
          05 FILLER PIC X(10) VALUE '39  C'.
          05 FILLER PIC X(10) VALUE '39  D'.
          05 FILLER PIC X(10) VALUE '39  E'.
      *> 150 ExecType
          05 FILLER PIC X(10) VALUE '150 0'.
          05 FILLER PIC X(10) VALUE '150 1'.
          05 FILLER PIC X(10) VALUE '150 2'.
          05 FILLER PIC X(10) VALUE '150 3'.
          05 FILLER PIC X(10) VALUE '150 4'.
          05 FILLER PIC X(10) VALUE '150 5'.
          05 FILLER PIC X(10) VALUE '150 6'.
          05 FILLER PIC X(10) VALUE '150 7'.
          05 FILLER PIC X(10) VALUE '150 8'.
          05 FILLER PIC X(10) VALUE '150 9'.
          05 FILLER PIC X(10) VALUE '150 A'.
          05 FILLER PIC X(10) VALUE '150 B'.
          05 FILLER PIC X(10) VALUE '150 C'.
          05 FILLER PIC X(10) VALUE '150 D'.
          05 FILLER PIC X(10) VALUE '150 E'.
          05 FILLER PIC X(10) VALUE '150 F'.
          05 FILLER PIC X(10) VALUE '150 G'.
          05 FILLER PIC X(10) VALUE '150 H'.
          05 FILLER PIC X(10) VALUE '150 I'.
      *> 98 EncryptMethod
          05 FILLER PIC X(10) VALUE '98  0'.
          05 FILLER PIC X(10) VALUE '98  1'.
          05 FILLER PIC X(10) VALUE '98  2'.
          05 FILLER PIC X(10) VALUE '98  3'.
          05 FILLER PIC X(10) VALUE '98  4'.
          05 FILLER PIC X(10) VALUE '98  5'.
          05 FILLER PIC X(10) VALUE '98  6'.
       01 ENUM-TABLE-R REDEFINES ENUM-TABLE.
          05 ENUM-ENTRY OCCURS 82 TIMES INDEXED BY ENX.
             10 ENUM-TAG              PIC X(4).
             10 ENUM-VAL              PIC X(6).
       01 ENUM-COUNT                  PIC 9(4) VALUE 82.

      *> ---- tags that carry an enum we can check ----
       01 ENUM-TAGS.
          05 FILLER PIC X(4) VALUE '54'.
          05 FILLER PIC X(4) VALUE '40'.
          05 FILLER PIC X(4) VALUE '59'.
          05 FILLER PIC X(4) VALUE '39'.
          05 FILLER PIC X(4) VALUE '150'.
          05 FILLER PIC X(4) VALUE '98'.
       01 ENUM-TAGS-R REDEFINES ENUM-TAGS.
          05 ENUM-TAG-CHK OCCURS 6 TIMES INDEXED BY ETX PIC X(4).
       01 ENUM-TAGS-COUNT             PIC 9(3) VALUE 6.

      *> ---- integer-typed tags (value must be all digits) ----
       01 INT-TAGS.
          05 FILLER PIC X(4) VALUE '9'.
          05 FILLER PIC X(4) VALUE '34'.
          05 FILLER PIC X(4) VALUE '98'.
          05 FILLER PIC X(4) VALUE '108'.
       01 INT-TAGS-R REDEFINES INT-TAGS.
          05 INT-TAG OCCURS 4 TIMES INDEXED BY ITX PIC X(4).
       01 INT-TAGS-COUNT              PIC 9(3) VALUE 4.

      *> ---- UTCTimestamp tags (52, 60) ----
       01 WS-TS-OK                    PIC X.
       01 WS-TS-VAL                   PIC X(32).

       PROCEDURE DIVISION.

      *> ============================ MAIN ============================
       MAIN-PARA.
           PERFORM PARSE-ARGS
           IF WS-PATH = SPACES
               DISPLAY
               "usage: fixwval <file> [--soh PIPE|SOH|AUTO] [--json]"
                   UPON SYSERR
               MOVE 1 TO RETURN-CODE
               STOP RUN
           END-IF

           MOVE FUNCTION CHAR(2) TO SOH-CHAR

           OPEN INPUT IN-FILE
           IF WS-FS NOT = "00"
               DISPLAY "fixwval: cannot open input file: "
                   FUNCTION TRIM(WS-PATH) UPON SYSERR
               MOVE 1 TO RETURN-CODE
               STOP RUN
           END-IF

           IF WS-JSON-ONLY = 'N'
               DISPLAY "fixwval — FIX Wire Validator"
               DISPLAY "file: " FUNCTION TRIM(WS-PATH)
               DISPLAY "----------------------------------------"
           END-IF

           MOVE 'N' TO WS-EOF
           PERFORM UNTIL WS-EOF = 'Y'
               READ IN-FILE
                   AT END MOVE 'Y' TO WS-EOF
                   NOT AT END PERFORM HANDLE-LINE
               END-READ
           END-PERFORM
           CLOSE IN-FILE

           PERFORM EMIT-SUMMARY

           IF CNT-FAIL > 0
               MOVE 2 TO RETURN-CODE
           ELSE
               MOVE 0 TO RETURN-CODE
           END-IF
           STOP RUN.

      *> ---------------------------- ARGS ----------------------------
       PARSE-ARGS.
           MOVE SPACES TO WS-PATH
           MOVE 'N' TO WS-EOF
           PERFORM UNTIL WS-EOF = 'Y'
               MOVE SPACES TO WS-ARG
               ACCEPT WS-ARG FROM ARGUMENT-VALUE
                   ON EXCEPTION MOVE 'Y' TO WS-EOF
               END-ACCEPT
               IF WS-EOF = 'Y' OR WS-ARG = SPACES
                   MOVE 'Y' TO WS-EOF
                   EXIT PERFORM
               END-IF
               EVALUATE FUNCTION TRIM(WS-ARG)
                   WHEN "--soh"
                       ACCEPT WS-ARG FROM ARGUMENT-VALUE
                       MOVE FUNCTION UPPER-CASE(FUNCTION TRIM(WS-ARG))
                           TO WS-SOH-MODE
                   WHEN "--json"
                       MOVE 'Y' TO WS-JSON-ONLY
                   WHEN OTHER
                       IF WS-PATH = SPACES
                           MOVE WS-ARG TO WS-PATH
                       END-IF
               END-EVALUATE
           END-PERFORM.

      *> -------------------------- PER LINE --------------------------
       HANDLE-LINE.
           MOVE FUNCTION TRIM(IN-REC TRAILING) TO WS-LINE
           MOVE FUNCTION LENGTH(FUNCTION TRIM(IN-REC TRAILING))
               TO WS-LINE-LEN
      *>   skip blank lines and comment lines (# ...)
           IF WS-LINE-LEN = 0
               EXIT PARAGRAPH
           END-IF
           IF WS-LINE(1:1) = '#'
               EXIT PARAGRAPH
           END-IF

           ADD 1 TO CNT-TOTAL
           ADD 1 TO WS-MSG-INDEX
           MOVE 'Y' TO WS-MSG-OK
           MOVE 0 TO WS-NVIOL

           PERFORM PICK-DELIM
           PERFORM PARSE-FIELDS
           PERFORM VALIDATE-MESSAGE

           IF WS-MSG-OK = 'Y'
               ADD 1 TO CNT-PASS
           ELSE
               ADD 1 TO CNT-FAIL
           END-IF

           PERFORM REPORT-MESSAGE.

      *> Choose the delimiter for this line (per --soh mode / auto-detect)
       PICK-DELIM.
           EVALUATE WS-SOH-MODE
               WHEN "PIPE"
                   MOVE PIPE-CHAR TO WS-DELIM
               WHEN "SOH"
                   MOVE SOH-CHAR TO WS-DELIM
               WHEN OTHER
      *>           AUTO: prefer real SOH if present, else pipe
                   MOVE 'N' TO WS-FOUND
                   PERFORM VARYING WS-P FROM 1 BY 1
                       UNTIL WS-P > WS-LINE-LEN
                       IF WS-LINE(WS-P:1) = SOH-CHAR
                           MOVE 'Y' TO WS-FOUND
                       END-IF
                   END-PERFORM
                   IF WS-FOUND = 'Y'
                       MOVE SOH-CHAR TO WS-DELIM
                   ELSE
                       MOVE PIPE-CHAR TO WS-DELIM
                   END-IF
           END-EVALUATE.

      *> ------------------------ PARSE FIELDS ------------------------
      *> Split WS-LINE on WS-DELIM into FLD entries; split each on first '='.
       PARSE-FIELDS.
           MOVE 0 TO WS-NFIELDS
           MOVE 1 TO WS-TS
           PERFORM VARYING WS-P FROM 1 BY 1 UNTIL WS-P > WS-LINE-LEN
               IF WS-LINE(WS-P:1) = WS-DELIM
                   COMPUTE WS-PTLEN = WS-P - WS-TS
                   PERFORM STORE-TOKEN
                   COMPUTE WS-TS = WS-P + 1
               END-IF
           END-PERFORM
      *>   trailing token if line doesn't end with delimiter
           IF WS-TS <= WS-LINE-LEN
               COMPUTE WS-PTLEN = WS-LINE-LEN - WS-TS + 1
               PERFORM STORE-TOKEN
           END-IF.

      *> Store token WS-LINE(WS-TS:WS-PTLEN) as the next field.
      *> Uses only private vars (WS-P/WS-TS/WS-PTOK/WS-PTLEN/WS-PEQ/WS-PN).
       STORE-TOKEN.
           IF WS-PTLEN <= 0
               EXIT PARAGRAPH
           END-IF
           IF WS-NFIELDS >= WS-MAX-FIELDS
               EXIT PARAGRAPH
           END-IF
           MOVE SPACES TO WS-PTOK
           MOVE WS-LINE(WS-TS:WS-PTLEN) TO WS-PTOK
           ADD 1 TO WS-NFIELDS
           SET FX TO WS-NFIELDS
      *>   locate first '='
           MOVE 0 TO WS-PEQ
           PERFORM VARYING WS-PN FROM 1 BY 1 UNTIL WS-PN > WS-PTLEN
               IF WS-PEQ = 0 AND WS-PTOK(WS-PN:1) = '='
                   MOVE WS-PN TO WS-PEQ
               END-IF
           END-PERFORM
           MOVE SPACES TO FLD-TAG(FX)
           MOVE SPACES TO FLD-VAL(FX)
           MOVE 0 TO FLD-TAGNUM(FX)
           MOVE 'N' TO FLD-TAGNUM-OK(FX)
           MOVE 0 TO FLD-VLEN(FX)
           IF WS-PEQ = 0
      *>       malformed field: no '='
               MOVE WS-PTOK(1:WS-PTLEN) TO FLD-TAG(FX)
               EXIT PARAGRAPH
           END-IF
           IF WS-PEQ > 1
               MOVE WS-PTOK(1:WS-PEQ - 1) TO FLD-TAG(FX)
           END-IF
           COMPUTE WS-PN = WS-PTLEN - WS-PEQ
           IF WS-PN > 0
               MOVE WS-PTOK(WS-PEQ + 1:WS-PN) TO FLD-VAL(FX)
               MOVE WS-PN TO FLD-VLEN(FX)
           END-IF
      *>   is tag all-digits?
           PERFORM CHECK-TAG-NUMERIC.

      *> Uses private vars WS-TN-* so it never disturbs a caller's loop.
       CHECK-TAG-NUMERIC.
           MOVE 'Y' TO FLD-TAGNUM-OK(FX)
           MOVE FUNCTION TRIM(FLD-TAG(FX)) TO WS-PTOK
           MOVE FUNCTION LENGTH(FUNCTION TRIM(FLD-TAG(FX))) TO WS-TN-LEN
           IF WS-TN-LEN = 0
               MOVE 'N' TO FLD-TAGNUM-OK(FX)
               EXIT PARAGRAPH
           END-IF
           PERFORM VARYING WS-TN-I FROM 1 BY 1 UNTIL WS-TN-I > WS-TN-LEN
               MOVE WS-PTOK(WS-TN-I:1) TO WS-TN-CH
               IF WS-TN-CH < '0' OR WS-TN-CH > '9'
                   MOVE 'N' TO FLD-TAGNUM-OK(FX)
               END-IF
           END-PERFORM
           IF FLD-TAGNUM-OK(FX) = 'Y'
               MOVE FUNCTION NUMVAL(FLD-TAG(FX)) TO FLD-TAGNUM(FX)
           END-IF.

      *> ---------------------- VALIDATE MESSAGE ----------------------
       VALIDATE-MESSAGE.
           IF WS-NFIELDS = 0
               PERFORM ADD-VIOL-EMPTY
               EXIT PARAGRAPH
           END-IF
           PERFORM CHECK-MALFORMED-FIELDS
           PERFORM CHECK-HEADER-ORDER
           PERFORM SET-VERSION-AND-MSGTYPE
           PERFORM CHECK-BODYLENGTH
           PERFORM CHECK-CHECKSUM
           PERFORM CHECK-MSGTYPE-KNOWN
           PERFORM CHECK-SESSION-REQUIRED
           PERFORM CHECK-REQUIRED-FIELDS
           PERFORM CHECK-ENUMS
           PERFORM CHECK-INT-TYPES
           PERFORM CHECK-TIMESTAMPS.

       ADD-VIOL-EMPTY.
           MOVE "EMPTY_MESSAGE" TO WS-TOK
           MOVE "message has no parseable fields" TO WS-ARG
           PERFORM ADD-VIOL.

      *> every field must be tag=value with numeric tag
       CHECK-MALFORMED-FIELDS.
           PERFORM VARYING FX FROM 1 BY 1 UNTIL FX > WS-NFIELDS
               IF FLD-TAGNUM-OK(FX) = 'N'
                   MOVE "MALFORMED_FIELD" TO WS-TOK
                   MOVE SPACES TO WS-ARG
                   STRING "field #" DELIMITED BY SIZE
                       FUNCTION TRIM(FLD-TAG(FX)) DELIMITED BY SIZE
                       " is not a numeric tag=value pair"
                       DELIMITED BY SIZE
                       INTO WS-ARG
                   END-STRING
                   PERFORM ADD-VIOL
               END-IF
           END-PERFORM.

      *> header: 8 first, 9 second, 35 third; 10 last
       CHECK-HEADER-ORDER.
           SET FX TO 1
           IF FLD-TAGNUM(1) NOT = 8
               MOVE "HEADER_ORDER" TO WS-TOK
               MOVE "tag 8 (BeginString) must be the first field"
                   TO WS-ARG
               PERFORM ADD-VIOL
           END-IF
           IF WS-NFIELDS >= 2
               IF FLD-TAGNUM(2) NOT = 9
                   MOVE "HEADER_ORDER" TO WS-TOK
                   MOVE "tag 9 (BodyLength) must be the second field"
                       TO WS-ARG
                   PERFORM ADD-VIOL
               END-IF
           END-IF
           IF WS-NFIELDS >= 3
               IF FLD-TAGNUM(3) NOT = 35
                   MOVE "HEADER_ORDER" TO WS-TOK
                   MOVE "tag 35 (MsgType) must be the third field"
                       TO WS-ARG
                   PERFORM ADD-VIOL
               END-IF
           END-IF
           SET FX TO WS-NFIELDS
           IF FLD-TAGNUM(WS-NFIELDS) NOT = 10
               MOVE "TRAILER_ORDER" TO WS-TOK
               MOVE "tag 10 (CheckSum) must be the last field"
                   TO WS-ARG
               PERFORM ADD-VIOL
           END-IF.

       SET-VERSION-AND-MSGTYPE.
           MOVE SPACES TO WS-BEGINSTR
           MOVE SPACES TO WS-MSGTYPE
           PERFORM VARYING FX FROM 1 BY 1 UNTIL FX > WS-NFIELDS
               IF FLD-TAGNUM(FX) = 8
                   MOVE FLD-VAL(FX) TO WS-BEGINSTR
               END-IF
               IF FLD-TAGNUM(FX) = 35
                   MOVE FLD-VAL(FX) TO WS-MSGTYPE
               END-IF
           END-PERFORM
           MOVE FUNCTION TRIM(WS-BEGINSTR) TO WS-VERSION.

      *> BodyLength: bytes from char after 9's delimiter up to and
      *> including the delimiter before tag 10.
       CHECK-BODYLENGTH.
      *>   need declared value from tag 9
           MOVE SPACES TO WS-BODYLEN-DECL-RAW
           MOVE 0 TO WS-BODYLEN-DECL
           PERFORM VARYING FX FROM 1 BY 1 UNTIL FX > WS-NFIELDS
               IF FLD-TAGNUM(FX) = 9
                   MOVE FLD-VAL(FX) TO WS-BODYLEN-DECL-RAW
               END-IF
           END-PERFORM
           IF WS-BODYLEN-DECL-RAW = SPACES
               EXIT PARAGRAPH
           END-IF
      *>   compute the char index just after "9=<val><delim>"
      *>   locate start-of-body and start-of-tag10 in WS-LINE
           PERFORM FIND-BODYLEN-BOUNDS
           IF WS-BL-START = 0 OR WS-BL-END = 0
               EXIT PARAGRAPH
           END-IF
           COMPUTE WS-BODYLEN-CALC = WS-BL-END - WS-BL-START + 1
           MOVE FUNCTION NUMVAL(WS-BODYLEN-DECL-RAW)
               TO WS-BODYLEN-DECL
           IF WS-BODYLEN-CALC NOT = WS-BODYLEN-DECL
               MOVE "BAD_BODYLENGTH" TO WS-TOK
               MOVE SPACES TO WS-ARG
               MOVE WS-BODYLEN-DECL TO WS-DISP
               STRING "tag 9 declared=" DELIMITED BY SIZE
                   FUNCTION TRIM(WS-DISP) DELIMITED BY SIZE
                   " actual=" DELIMITED BY SIZE
                   INTO WS-ARG
               END-STRING
               MOVE WS-BODYLEN-CALC TO WS-DISP
               STRING FUNCTION TRIM(WS-ARG) DELIMITED BY SIZE
                   FUNCTION TRIM(WS-DISP) DELIMITED BY SIZE
                   INTO WS-ARG
               END-STRING
               PERFORM ADD-VIOL
           END-IF.

      *> Find, in WS-LINE (with WS-DELIM as the real SOH equivalent),
      *> the byte index of the first body char and the last body char.
      *> Body begins right after the delimiter that terminates 9=<val>.
      *> Body ends at the delimiter immediately before "10=".
      *> We compute lengths using the canonical SOH byte (1 byte each),
      *> which equals the pipe count too, so index math is consistent.
       FIND-BODYLEN-BOUNDS.
           MOVE 0 TO WS-BL-START
           MOVE 0 TO WS-BL-END
      *>   position of end of "9=<val>" field terminator:
      *>   walk fields; when we pass tag 9, body starts at next field's
      *>   first char. Reconstruct offsets from field lengths.
           PERFORM COMPUTE-FIELD-OFFSETS.

      *> Rebuild per-field start offsets in a canonical SOH stream so
      *> body length is delimiter-agnostic (pipe and SOH are both 1 byte).
       COMPUTE-FIELD-OFFSETS.
      *>   canonical stream: tag=val + 1 delim byte per field.
      *>   offset of field i start (1-based) = sum(len(field j)+1) for j<i +1
           MOVE 0 TO WS-K
           MOVE 0 TO WS-BL-START
           MOVE 0 TO WS-BL-END
           MOVE 0 TO WS-I
      *>   WS-I accumulates running byte position (0-based end of prior)
           PERFORM VARYING FX FROM 1 BY 1 UNTIL FX > WS-NFIELDS
      *>       field text length = len(tag)+1(=)+vlen ; +1 delimiter
               COMPUTE WS-J =
                   FUNCTION LENGTH(FUNCTION TRIM(FLD-TAG(FX)))
                   + 1 + FLD-VLEN(FX)
               IF FLD-TAGNUM(FX) = 9
      *>           body starts at char after this field's delimiter
                   COMPUTE WS-BL-START = WS-I + WS-J + 1 + 1
               END-IF
               IF FLD-TAGNUM(FX) = 10
      *>           body ends at delimiter just before this field:
      *>           that is the byte at position WS-I (the prior delim)
                   MOVE WS-I TO WS-BL-END
               END-IF
               COMPUTE WS-I = WS-I + WS-J + 1
           END-PERFORM.

      *> CheckSum: sum of all bytes up to & including the delimiter
      *> before tag 10, mod 256, 3-digit zero-padded.
       CHECK-CHECKSUM.
           MOVE SPACES TO WS-DECL-CS
           MOVE 'N' TO WS-AT-TAG10
           PERFORM VARYING FX FROM 1 BY 1 UNTIL FX > WS-NFIELDS
               IF FLD-TAGNUM(FX) = 10
                   MOVE FLD-VAL(FX) TO WS-DECL-CS
               END-IF
           END-PERFORM
           IF WS-DECL-CS = SPACES
               EXIT PARAGRAPH
           END-IF
      *>   sum bytes of the canonical stream up to & incl delim before 10
           MOVE 0 TO WS-SUM
           PERFORM VARYING FX FROM 1 BY 1 UNTIL FX > WS-NFIELDS
               IF FLD-TAGNUM(FX) = 10
                   EXIT PERFORM
               END-IF
               PERFORM SUM-ONE-FIELD
           END-PERFORM
           COMPUTE WS-CALC-CS = FUNCTION MOD(WS-SUM, 256)
           MOVE WS-CALC-CS TO WS-CALC-CS-DISP
      *>   declared must be exactly 3 digits
           IF FUNCTION LENGTH(FUNCTION TRIM(WS-DECL-CS)) NOT = 3
               MOVE "BAD_CHECKSUM_FMT" TO WS-TOK
               MOVE SPACES TO WS-ARG
               STRING "tag 10 must be 3 digits, got '" DELIMITED BY SIZE
                   FUNCTION TRIM(WS-DECL-CS) DELIMITED BY SIZE
                   "'" DELIMITED BY SIZE
                   INTO WS-ARG
               END-STRING
               PERFORM ADD-VIOL
           END-IF
           IF FUNCTION TRIM(WS-DECL-CS) NOT = WS-CALC-CS-DISP
               MOVE "BAD_CHECKSUM" TO WS-TOK
               MOVE SPACES TO WS-ARG
               STRING "tag 10 declared=" DELIMITED BY SIZE
                   FUNCTION TRIM(WS-DECL-CS) DELIMITED BY SIZE
                   " expected=" DELIMITED BY SIZE
                   WS-CALC-CS-DISP DELIMITED BY SIZE
                   INTO WS-ARG
               END-STRING
               PERFORM ADD-VIOL
           END-IF.

      *> Add byte-sum of "tag=val" + 1 delimiter (canonical SOH=0x01)
       SUM-ONE-FIELD.
      *>   tag chars
           MOVE FUNCTION TRIM(FLD-TAG(FX)) TO WS-TOK
           MOVE FUNCTION LENGTH(FUNCTION TRIM(FLD-TAG(FX))) TO WS-K
           PERFORM VARYING WS-I FROM 1 BY 1 UNTIL WS-I > WS-K
               COMPUTE WS-CHV = FUNCTION ORD(WS-TOK(WS-I:1)) - 1
               ADD WS-CHV TO WS-SUM
           END-PERFORM
      *>   '=' byte (0x3D = 61)
           ADD 61 TO WS-SUM
      *>   value chars
           IF FLD-VLEN(FX) > 0
               PERFORM VARYING WS-I FROM 1 BY 1
                   UNTIL WS-I > FLD-VLEN(FX)
                   COMPUTE WS-CHV =
                       FUNCTION ORD(FLD-VAL(FX)(WS-I:1)) - 1
                   ADD WS-CHV TO WS-SUM
               END-PERFORM
           END-IF
      *>   trailing delimiter is canonical SOH (0x01 = 1)
           ADD 1 TO WS-SUM.

       CHECK-MSGTYPE-KNOWN.
           IF WS-MSGTYPE = SPACES
               EXIT PARAGRAPH
           END-IF
           MOVE 'N' TO WS-MT-KNOWN
           MOVE SPACES TO WS-MT-NAME
           PERFORM VARYING MTX FROM 1 BY 1 UNTIL MTX > MT-COUNT
               IF FUNCTION TRIM(MT-CODE(MTX)) = FUNCTION TRIM(WS-MSGTYPE)
                   MOVE 'Y' TO WS-MT-KNOWN
                   MOVE MT-NAME(MTX) TO WS-MT-NAME
               END-IF
           END-PERFORM
           IF WS-MT-KNOWN = 'N'
               MOVE "UNKNOWN_MSGTYPE" TO WS-TOK
               MOVE SPACES TO WS-ARG
               STRING "tag 35 MsgType '" DELIMITED BY SIZE
                   FUNCTION TRIM(WS-MSGTYPE) DELIMITED BY SIZE
                   "' not recognized" DELIMITED BY SIZE
                   INTO WS-ARG
               END-STRING
               PERFORM ADD-VIOL
           END-IF.

       CHECK-SESSION-REQUIRED.
           PERFORM VARYING SSX FROM 1 BY 1 UNTIL SSX > SESS-COUNT
               MOVE FUNCTION TRIM(SESS-TAG(SSX)) TO WS-TOK
               PERFORM FIND-TAG
               IF WS-FOUND = 'N'
                   MOVE "MISSING_REQUIRED" TO WS-TOK
                   MOVE SPACES TO WS-ARG
                   STRING "session-required tag " DELIMITED BY SIZE
                       FUNCTION TRIM(SESS-TAG(SSX)) DELIMITED BY SIZE
                       " is missing" DELIMITED BY SIZE
                       INTO WS-ARG
                   END-STRING
                   PERFORM ADD-VIOL
               END-IF
           END-PERFORM.

       CHECK-REQUIRED-FIELDS.
           IF WS-MSGTYPE = SPACES
               EXIT PARAGRAPH
           END-IF
           PERFORM VARYING RQX FROM 1 BY 1 UNTIL RQX > REQ-COUNT
               IF FUNCTION TRIM(REQ-MT(RQX)) =
                  FUNCTION TRIM(WS-MSGTYPE)
                   MOVE FUNCTION TRIM(REQ-TAG(RQX)) TO WS-TOK
                   PERFORM FIND-TAG
                   IF WS-FOUND = 'N'
                       MOVE "MISSING_REQUIRED" TO WS-TOK
                       MOVE SPACES TO WS-ARG
                       STRING "msgtype " DELIMITED BY SIZE
                           FUNCTION TRIM(WS-MSGTYPE) DELIMITED BY SIZE
                           " requires tag " DELIMITED BY SIZE
                           FUNCTION TRIM(REQ-TAG(RQX)) DELIMITED BY SIZE
                           INTO WS-ARG
                       END-STRING
                       PERFORM ADD-VIOL
                   END-IF
               END-IF
           END-PERFORM.

      *> WS-TOK holds tag string to search; sets WS-FOUND Y/N.
       FIND-TAG.
           MOVE 'N' TO WS-FOUND
           PERFORM VARYING FX FROM 1 BY 1 UNTIL FX > WS-NFIELDS
               IF FUNCTION TRIM(FLD-TAG(FX)) = FUNCTION TRIM(WS-TOK)
                   MOVE 'Y' TO WS-FOUND
               END-IF
           END-PERFORM.

       CHECK-ENUMS.
           PERFORM VARYING FX FROM 1 BY 1 UNTIL FX > WS-NFIELDS
               IF FLD-TAGNUM-OK(FX) = 'Y'
                   PERFORM CHECK-ONE-ENUM
               END-IF
           END-PERFORM.

       CHECK-ONE-ENUM.
      *>   is this tag one we enum-check?
           MOVE 'N' TO WS-FOUND
           PERFORM VARYING ETX FROM 1 BY 1 UNTIL ETX > ENUM-TAGS-COUNT
               IF FUNCTION TRIM(ENUM-TAG-CHK(ETX)) =
                  FUNCTION TRIM(FLD-TAG(FX))
                   MOVE 'Y' TO WS-FOUND
               END-IF
           END-PERFORM
           IF WS-FOUND = 'N'
               EXIT PARAGRAPH
           END-IF
      *>   value must be in the allowed set for this tag
           MOVE 'N' TO WS-FOUND
           PERFORM VARYING ENX FROM 1 BY 1 UNTIL ENX > ENUM-COUNT
               IF FUNCTION TRIM(ENUM-TAG(ENX)) =
                  FUNCTION TRIM(FLD-TAG(FX)) AND
                  FUNCTION TRIM(ENUM-VAL(ENX)) =
                  FUNCTION TRIM(FLD-VAL(FX))
                   MOVE 'Y' TO WS-FOUND
               END-IF
           END-PERFORM
           IF WS-FOUND = 'N'
               MOVE "BAD_ENUM" TO WS-TOK
               MOVE SPACES TO WS-ARG
               STRING "tag " DELIMITED BY SIZE
                   FUNCTION TRIM(FLD-TAG(FX)) DELIMITED BY SIZE
                   " value '" DELIMITED BY SIZE
                   FUNCTION TRIM(FLD-VAL(FX)) DELIMITED BY SIZE
                   "' not a valid enum" DELIMITED BY SIZE
                   INTO WS-ARG
               END-STRING
               PERFORM ADD-VIOL
           END-IF.

       CHECK-INT-TYPES.
           PERFORM VARYING FX FROM 1 BY 1 UNTIL FX > WS-NFIELDS
               IF FLD-TAGNUM-OK(FX) = 'Y'
                   PERFORM CHECK-ONE-INT
               END-IF
           END-PERFORM.

       CHECK-ONE-INT.
           MOVE 'N' TO WS-FOUND
           PERFORM VARYING ITX FROM 1 BY 1 UNTIL ITX > INT-TAGS-COUNT
               IF FUNCTION TRIM(INT-TAG(ITX)) =
                  FUNCTION TRIM(FLD-TAG(FX))
                   MOVE 'Y' TO WS-FOUND
               END-IF
           END-PERFORM
           IF WS-FOUND = 'N'
               EXIT PARAGRAPH
           END-IF
           IF FLD-VLEN(FX) = 0
               EXIT PARAGRAPH
           END-IF
           MOVE 'Y' TO WS-TS-OK
           PERFORM VARYING WS-I FROM 1 BY 1 UNTIL WS-I > FLD-VLEN(FX)
               MOVE FLD-VAL(FX)(WS-I:1) TO WS-CH
               IF WS-CH < '0' OR WS-CH > '9'
                   MOVE 'N' TO WS-TS-OK
               END-IF
           END-PERFORM
           IF WS-TS-OK = 'N'
               MOVE "BAD_INT" TO WS-TOK
               MOVE SPACES TO WS-ARG
               STRING "tag " DELIMITED BY SIZE
                   FUNCTION TRIM(FLD-TAG(FX)) DELIMITED BY SIZE
                   " must be integer, got '" DELIMITED BY SIZE
                   FUNCTION TRIM(FLD-VAL(FX)) DELIMITED BY SIZE
                   "'" DELIMITED BY SIZE
                   INTO WS-ARG
               END-STRING
               PERFORM ADD-VIOL
           END-IF.

      *> UTCTimestamp tags 52 & 60: YYYYMMDD-HH:MM:SS[.sss]
       CHECK-TIMESTAMPS.
           PERFORM VARYING FX FROM 1 BY 1 UNTIL FX > WS-NFIELDS
               IF FLD-TAGNUM(FX) = 52 OR FLD-TAGNUM(FX) = 60
                   PERFORM CHECK-ONE-TS
               END-IF
           END-PERFORM.

       CHECK-ONE-TS.
           MOVE FUNCTION TRIM(FLD-VAL(FX)) TO WS-TS-VAL
           MOVE FUNCTION LENGTH(FUNCTION TRIM(FLD-VAL(FX))) TO WS-K
           MOVE 'Y' TO WS-TS-OK
      *>   minimum length 17: YYYYMMDD-HH:MM:SS
           IF WS-K < 17
               MOVE 'N' TO WS-TS-OK
           ELSE
               IF WS-TS-VAL(9:1) NOT = '-'
                   MOVE 'N' TO WS-TS-OK
               END-IF
               IF WS-TS-VAL(12:1) NOT = ':'
                   MOVE 'N' TO WS-TS-OK
               END-IF
               IF WS-TS-VAL(15:1) NOT = ':'
                   MOVE 'N' TO WS-TS-OK
               END-IF
      *>       digit positions 1-8 (date) and 10-11,13-14,16-17
               PERFORM CHECK-TS-DIGITS
           END-IF
           IF WS-TS-OK = 'N'
               MOVE "BAD_TIMESTAMP" TO WS-TOK
               MOVE SPACES TO WS-ARG
               STRING "tag " DELIMITED BY SIZE
                   FUNCTION TRIM(FLD-TAG(FX)) DELIMITED BY SIZE
                   " bad UTCTimestamp '" DELIMITED BY SIZE
                   FUNCTION TRIM(FLD-VAL(FX)) DELIMITED BY SIZE
                   "' (want YYYYMMDD-HH:MM:SS)" DELIMITED BY SIZE
                   INTO WS-ARG
               END-STRING
               PERFORM ADD-VIOL
           END-IF.

       CHECK-TS-DIGITS.
           PERFORM VARYING WS-I FROM 1 BY 1 UNTIL WS-I > 8
               MOVE WS-TS-VAL(WS-I:1) TO WS-CH
               IF WS-CH < '0' OR WS-CH > '9'
                   MOVE 'N' TO WS-TS-OK
               END-IF
           END-PERFORM
           PERFORM CHECK-TS-PAIR-10
           PERFORM CHECK-TS-PAIR-13
           PERFORM CHECK-TS-PAIR-16.
       CHECK-TS-PAIR-10.
           IF WS-TS-VAL(10:1) < '0' OR WS-TS-VAL(10:1) > '9'
               MOVE 'N' TO WS-TS-OK
           END-IF
           IF WS-TS-VAL(11:1) < '0' OR WS-TS-VAL(11:1) > '9'
               MOVE 'N' TO WS-TS-OK
           END-IF.
       CHECK-TS-PAIR-13.
           IF WS-TS-VAL(13:1) < '0' OR WS-TS-VAL(13:1) > '9'
               MOVE 'N' TO WS-TS-OK
           END-IF
           IF WS-TS-VAL(14:1) < '0' OR WS-TS-VAL(14:1) > '9'
               MOVE 'N' TO WS-TS-OK
           END-IF.
       CHECK-TS-PAIR-16.
           IF WS-TS-VAL(16:1) < '0' OR WS-TS-VAL(16:1) > '9'
               MOVE 'N' TO WS-TS-OK
           END-IF
           IF WS-TS-VAL(17:1) < '0' OR WS-TS-VAL(17:1) > '9'
               MOVE 'N' TO WS-TS-OK
           END-IF.

      *> ------------------------ VIOLATIONS -------------------------
      *> WS-TOK = code, WS-ARG = detail
       ADD-VIOL.
           MOVE 'N' TO WS-MSG-OK
           IF WS-NVIOL < 128
               ADD 1 TO WS-NVIOL
               SET VZ TO WS-NVIOL
               MOVE FUNCTION TRIM(WS-TOK) TO V-CODE(VZ)
               MOVE FUNCTION TRIM(WS-ARG) TO V-DETAIL(VZ)
           END-IF.

      *> ------------------------- REPORTING -------------------------
       REPORT-MESSAGE.
           MOVE WS-MSG-INDEX TO WS-DISP
           IF WS-JSON-ONLY = 'Y'
               PERFORM REPORT-MESSAGE-JSON
               EXIT PARAGRAPH
           END-IF
           IF WS-MSG-OK = 'Y'
               DISPLAY "msg " FUNCTION TRIM(WS-DISP)
                   " PASS  35=" FUNCTION TRIM(WS-MSGTYPE)
                   " (" FUNCTION TRIM(WS-MT-NAME) ")"
                   "  " FUNCTION TRIM(WS-VERSION)
           ELSE
               DISPLAY "msg " FUNCTION TRIM(WS-DISP)
                   " FAIL  35=" FUNCTION TRIM(WS-MSGTYPE)
                   "  " FUNCTION TRIM(WS-VERSION)
               PERFORM VARYING VZ FROM 1 BY 1 UNTIL VZ > WS-NVIOL
                   DISPLAY "    - [" FUNCTION TRIM(V-CODE(VZ)) "] "
                       FUNCTION TRIM(V-DETAIL(VZ))
               END-PERFORM
           END-IF.

      *> One JSON object per message on its own line (JSONL).
       REPORT-MESSAGE-JSON.
           DISPLAY '{"msg":' FUNCTION TRIM(WS-DISP)
               WITH NO ADVANCING
           DISPLAY ',"msgtype":"' FUNCTION TRIM(WS-MSGTYPE) '"'
               WITH NO ADVANCING
           DISPLAY ',"version":"' FUNCTION TRIM(WS-VERSION) '"'
               WITH NO ADVANCING
           IF WS-MSG-OK = 'Y'
               DISPLAY ',"status":"PASS","violations":[]}'
           ELSE
               DISPLAY ',"status":"FAIL","violations":['
                   WITH NO ADVANCING
               PERFORM VARYING VZ FROM 1 BY 1 UNTIL VZ > WS-NVIOL
                   IF VZ > 1
                       DISPLAY ',' WITH NO ADVANCING
                   END-IF
                   DISPLAY '{"code":"' FUNCTION TRIM(V-CODE(VZ))
                       '","detail":"' WITH NO ADVANCING
                   PERFORM EMIT-VIOL-DETAIL
                   DISPLAY '"}' WITH NO ADVANCING
               END-PERFORM
               DISPLAY ']}'
           END-IF.

      *> Emit V-DETAIL with '"' and backslash escaped for valid JSON.
       EMIT-VIOL-DETAIL.
           MOVE FUNCTION TRIM(V-DETAIL(VZ)) TO WS-PTOK
           MOVE FUNCTION LENGTH(FUNCTION TRIM(V-DETAIL(VZ)))
               TO WS-PTLEN
           PERFORM VARYING WS-P FROM 1 BY 1 UNTIL WS-P > WS-PTLEN
               MOVE WS-PTOK(WS-P:1) TO WS-CH
               IF WS-CH = '"' OR WS-CH = '\'
                   DISPLAY '\' WITH NO ADVANCING
               END-IF
               DISPLAY WS-CH WITH NO ADVANCING
           END-PERFORM.

       EMIT-SUMMARY.
           IF WS-JSON-ONLY = 'N'
               DISPLAY "----------------------------------------"
           END-IF
           DISPLAY '{"tool":"fixwval","messages":' WITH NO ADVANCING
           MOVE CNT-TOTAL TO WS-DISP
           DISPLAY FUNCTION TRIM(WS-DISP) WITH NO ADVANCING
           DISPLAY ',"pass":' WITH NO ADVANCING
           MOVE CNT-PASS TO WS-DISP
           DISPLAY FUNCTION TRIM(WS-DISP) WITH NO ADVANCING
           DISPLAY ',"fail":' WITH NO ADVANCING
           MOVE CNT-FAIL TO WS-DISP
           DISPLAY FUNCTION TRIM(WS-DISP) WITH NO ADVANCING
           DISPLAY '}'.
