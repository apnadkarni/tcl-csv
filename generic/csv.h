/*

Copyright (c) 2012, Lambda Foundry, Inc., except where noted

Incorporates components of WarrenWeckesser/textreader, licensed under 3-clause
BSD

   Low-level ascii-file processing from pandas. Combines some elements from
   Python's built-in csv module and Warren Weckesser's textreader project on
   GitHub. See Python Software Foundation License and BSD licenses for these.

   Heavily adapted for tclcsv/Tcl
*/

#ifndef _TCLCSV_H
#define _TCLCSV_H

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <errno.h>

#if defined(_MSC_VER)
#include "ms_stdint.h"
#else
#include <stdint.h>
#endif

#include "tcl.h"
#include "khash.h"

#if TCL_MAJOR_VERSION > 8 || (TCL_MAJOR_VERSION == 8 && TCL_MINOR_VERSION > 6)
#define USE_TCL87_API 1
#endif

#ifndef USE_TCL87_API
#undef Tcl_Size
typedef int Tcl_Size;
#define TCL_SIZE_MODIFIER ""
#define Tcl_GetSizeIntFromObj Tcl_GetIntFromObj
#endif

#if CSV_ENABLE_ASSERT
#  if CSV_ENABLE_ASSERT == 1
#    define CSV_ASSERT(bool_) (void)( (bool_) || (Tcl_Panic("Assertion (%s) failed at line %d in file %s.", #bool_, __LINE__, __FILE__), 0) )
#  elif CSV_ENABLE_ASSERT == 2
#    define CSV_ASSERT(bool_) (void)( (bool_) || (DebugOutput("Assertion (" #bool_ ") failed at line " MAKESTRINGLITERAL2(__LINE__) " in file " __FILE__ "\n"), 0) )
#  elif CSV_ENABLE_ASSERT == 3
#    define CSV_ASSERT(bool_) do { if (! (bool_)) { __asm int 3 } } while (0)
#  else
#    error Invalid value for CSV_ENABLE_ASSERT
#  endif
#else
#define CSV_ASSERT(bool_) ((void) 0)
#endif

#if CSV_ENABLE_ASSERT
# define CSV_NOFAIL(expr, val) CSV_ASSERT((expr) == (val))
#else
# define CSV_NOFAIL(expr, val) do { (void) (expr) ; } while (0)
#endif

#define REACHED_EOF 1


/* #define VERBOSE */

#if defined(VERBOSE)
#define TRACE(X) printf X;
#else
#define TRACE(X)
#endif


#define PARSER_OUT_OF_MEMORY -1


/*
 *  XXX Might want to couple count_rows() with read_rows() to avoid duplication
 *      of some file I/O.
 */

typedef enum {
    START_RECORD,
    START_FIELD,
    ESCAPED_CHAR,
    IN_FIELD,
    IN_QUOTED_FIELD,
    ESCAPE_IN_QUOTED_FIELD,
    QUOTE_IN_QUOTED_FIELD,
    EAT_CRNL,
    EAT_CRNL_NOP,
    EAT_WHITESPACE,
    EAT_COMMENT,
    EAT_LINE_COMMENT,
    WHITESPACE_LINE,
    SKIP_LINE,
    FINISHED
} ParserState;

typedef enum {
    QUOTE_MINIMAL, QUOTE_ALL, QUOTE_NONNUMERIC, QUOTE_NONE
} QuoteStyle;


typedef struct parser_t {
    Tcl_Channel chan;

    int chunksize;  // Number of bytes to prepare for each chunk
    Tcl_Obj *dataObj; // Tcl_Obj where data is read from channel
    char *data;     // Points into dataObj (data to be processed)
    Tcl_Size datalen;    // amount of data available
    Tcl_Size datapos;

    // Tcl_Obj containing the read rows
    Tcl_Obj *rowsObj; // List of built rows
    Tcl_Obj *rowObj;  // The row being built
    Tcl_Obj *fieldObj; // The field being built

    Tcl_Size lines;            // Number of (good) lines observed
    Tcl_Size file_lines;       // Number of file lines observed (including bad or skipped)

    /*
     * Caller can specify which fields are to be included / excluded.
     * A field is included if its index appears in included_fields but
     * not in excluded_fields. included_fields and excluded_fields are
     * boolean (char) arrays indexed by field index.
     */
    char *included_fields;      /* If NULL, all included */
    Tcl_Size  num_included_fields;   /* Size of included_fields */
    char *excluded_fields;      /* If NULL, no exclusions */
    Tcl_Size  num_excluded_fields;   /* Size of excluded_fields */
    Tcl_Size  field_index;           /* Index of current field being parsed */


    // Tokenizing stuff
    ParserState state;
    int doublequote;            /* is " represented by ""? */
    char delimiter;             /* field separator */
    int delim_whitespace;       /* delimit by consuming space/tabs instead */
    char quotechar;             /* quote character */
    char escapechar;            /* escape character */
    char lineterminator;
    int skipinitialspace;       /* ignore spaces following delimiter? */
    int quoting;                /* style of quoting to write */

    // krufty, hmm =/
    int numeric_field;

    char commentchar;
    int allow_embedded_newline;
    int strict;                 /* raise exception on bad CSV */

    int expected_fields;
    int error_bad_lines;
    int warn_bad_lines;

    int header; // Boolean: 1: has header, 0: no header
    int header_start; // header row start
    int header_end;   // header row end

    void *skipset;
    int64_t skip_first_N_rows;
    int skip_footer;

    // error handling
    Tcl_Obj *warnObj;
    Tcl_Obj *errorObj;

    int skip_empty_lines;

    /* 
     * We want to avoid calling Tcl_AppendBuf for every
     * char so collect here and call when buffer is full
     */
    char field_buf[200];
    int  field_buf_index;
} parser_t;

#ifdef BUILD_tclcsv
# undef TCL_STORAGE_CLASS
# define TCL_STORAGE_CLASS DLLEXPORT
#endif
EXTERN int Tclcsv_Init(Tcl_Interp *interp);

void debug_print_parser(parser_t *self);

int tokenize_nrows(parser_t *self, size_t nrows);

int tokenize_all_rows(parser_t *self);

parser_t *parser_create(Tcl_Interp *, int objc, Tcl_Obj *const objv[], int *pnrows);
void parser_free(parser_t *self);

int csv_read_cmd(ClientData clientdata, Tcl_Interp *ip,
                 int objc, Tcl_Obj *const objv[]);
int csv_write_cmd(ClientData clientdata, Tcl_Interp *ip,
                 int objc, Tcl_Obj *const objv[]);

#endif /* _TCLCSV_H */
