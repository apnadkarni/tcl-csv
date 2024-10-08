/*

  CSV parsing - Heavily adapted for tclcsv

  From:
  Copyright (c) 2012, Lambda Foundry, Inc., except where noted

  Incorporates components of WarrenWeckesser/textreader, licensed under 3-clause
  BSD
   Low-level ascii-file processing from pandas. Combines some elements from
   Python's built-in csv module and Warren Weckesser's textreader project on
   GitHub. See Python Software Foundation License and BSD licenses for these.

  Modifications for tclcsv (c) 2016 by Ashok P. Nadkarni. See license.terms.

*/

#include "csv.h"
#include <ctype.h>

static parser_t* parser_new(void);
static int parser_init(parser_t *self);
static int parser_add_skiprow(parser_t *self, int64_t row);
static int parser_set_skipfirstnrows(parser_t *self, int64_t nrows);
static void parser_set_default_options(parser_t *self);

KHASH_MAP_INIT_INT64(int64, size_t)

#ifdef NOTUSED
static void append_warning(parser_t *self, Tcl_Obj *msgObj)
{
    if (self->warnObj == NULL) {
        self->warnObj = Tcl_NewListObj(0, NULL);
        Tcl_IncrRefCount(self->warnObj);
    }
    Tcl_ListObjAppendElement(NULL, self->warnObj, msgObj);
}
#endif

static void set_error(parser_t *self, Tcl_Obj *msgObj)
{
    Tcl_IncrRefCount(msgObj);
    if (self->errorObj)
        Tcl_DecrRefCount(self->errorObj);
    self->errorObj = msgObj;
}

static void unref_obj_if_not_null(Tcl_Obj **ppobj)
{
    if (*ppobj != NULL) {
        Tcl_DecrRefCount(*ppobj);
        *ppobj = NULL;
    }
}

void parser_set_default_options(parser_t *self)
{
    self->included_fields = NULL;
    self->excluded_fields = NULL;

    self->delimiter = ','; // XXX
    self->delim_whitespace = 0;

    self->doublequote = 1;
    self->quotechar = '"';
    self->escapechar = 0;

    self->lineterminator = '\0'; /* NUL->standard logic */

    self->skipinitialspace = 0;
    self->quoting = QUOTE_MINIMAL;
    self->allow_embedded_newline = 1;
    self->strict = 0;
    self->skip_empty_lines = 1;

    self->expected_fields = -1;
    self->error_bad_lines = 0;
    self->warn_bad_lines = 0;

    self->commentchar = '\0';

    self->skipset = NULL;
    self->skip_first_N_rows = -1;
    self->skip_footer = 0;
}

static int parse_field_indices(Tcl_Obj *o, Tcl_Size *pnindices, char **ppindices)
{
    char *pindices = NULL;
    Tcl_Obj **objs;
    Tcl_Size i, imax, nobjs;

    /*
     * List of indices is unsorted and may contain duplicates.
     * Instead of building a list and searching it every time we are
     * adding a field in end_field, we build an boolean array of size
     * of the max index we encounter. Then just check this array in
     * the end_field function before including/excluding the element
     */

    if (Tcl_ListObjGetElements(NULL, o, &nobjs, &objs) != TCL_OK)
        return TCL_ERROR;

    /* If empty list, treat as unspecified */
    if (nobjs == 0) {
        *pnindices = 0;
        *ppindices = NULL;
        return TCL_OK;
    }

    imax = -1;
    for (i = 0; i < nobjs; ++i) {
        int ix;
        if (Tcl_GetIntFromObj(NULL, objs[i], &ix) != TCL_OK)
            return TCL_ERROR;
        if (ix < 0 || ix >= 1000)
            return TCL_ERROR; /* Limit field count to 1000 */
        if (ix > imax)
            imax = ix;
    }
    pindices = calloc(imax+1, sizeof(*pindices));
    for (i = 0; i < nobjs; ++i) {
        int ix;
        Tcl_GetIntFromObj(NULL, objs[i], &ix); /* No need for status check
                                                  because of above loop */
        pindices[ix] = 1;
    }
    *ppindices = pindices;
    *pnindices = imax+1;
    return TCL_OK;
}

static parser_t* parser_new()
{
    return (parser_t*) calloc(1, sizeof(parser_t));
}

static void parser_cleanup(parser_t *self)
{
    unref_obj_if_not_null(&self->errorObj);
    unref_obj_if_not_null(&self->warnObj);
    unref_obj_if_not_null(&self->dataObj);
    unref_obj_if_not_null(&self->rowsObj);
    unref_obj_if_not_null(&self->rowObj);
    unref_obj_if_not_null(&self->fieldObj);
    if (self->skipset != NULL) {
        kh_destroy_int64((kh_int64_t*) self->skipset);
        self->skipset = NULL;
    }
    if (self->included_fields) {
        free(self->included_fields);
        self->included_fields = NULL;
    }
    if (self->excluded_fields) {
        free(self->excluded_fields);
        self->excluded_fields = NULL;
    }
}

static int parser_init(parser_t *self)
{
    self->errorObj = NULL;
    self->warnObj = NULL;

    self->lines = 0;
    self->file_lines = 0;

    self->field_index = 0;

    /* read bytes buffered */
    self->dataObj = Tcl_NewObj();
    Tcl_IncrRefCount(self->dataObj);
    self->data = Tcl_GetStringFromObj(self->dataObj, &self->datalen);
    self->datapos = 0;

    /* Where we collect the rows */
    self->rowsObj = Tcl_NewListObj(0, NULL);
    Tcl_IncrRefCount(self->rowsObj);
    self->rowObj = Tcl_NewListObj(0, NULL);
    Tcl_IncrRefCount(self->rowObj);
    self->fieldObj = Tcl_NewObj();
    Tcl_IncrRefCount(self->fieldObj);

    self->state = START_RECORD;

    /* Initial index into field buffer */
    self->field_buf_index = 0;

    return 0;
}


void parser_free(parser_t *self)
{
    // opposite of parser_init
    parser_cleanup(self);
    free(self);
}

static int end_field(parser_t *self)
{
    int included;

    /*
     * If there is any data in our output buffer, copy it to
     * the field object
     */
    if (self->field_buf_index != 0) {
        Tcl_AppendToObj(self->fieldObj, self->field_buf, self->field_buf_index);
        self->field_buf_index = 0;
    }

    /*
     * A field is included only if it appears in the include list
     * and not in the exclude list. No include list means all included.
     * No exclude list means no exclusions from the include list.
     */
    included = 1;
    if (self->included_fields != NULL &&
        (self->field_index >= self->num_included_fields ||
         self->included_fields[self->field_index] == 0))
        included = 0;

    /* If included, make sure it is not in the exclude list */
    if (included) {
        if (self->excluded_fields &&
            self->field_index < self->num_excluded_fields &&
            self->excluded_fields[self->field_index])
            included = 0;
    }
    if (included)
        Tcl_ListObjAppendElement(NULL, self->rowObj, self->fieldObj);

    Tcl_DecrRefCount(self->fieldObj);
    self->field_index += 1;
    self->fieldObj = Tcl_NewObj();
    Tcl_IncrRefCount(self->fieldObj);

    return 0;
}


static int end_line(parser_t *self)
{
    Tcl_Size fields;

#ifndef TBD

    /* TBD - don't deal with special cases */
    if (self->state == SKIP_LINE) {
        TRACE(("end_line: Skipping row %d\n", self->file_lines));
        // increment file line count
        self->file_lines++;
        return 0;
    }
    fields = 0;
    Tcl_ListObjLength(NULL, self->rowObj,  &fields);
    Tcl_ListObjAppendElement(NULL, self->rowsObj, self->rowObj);
    Tcl_DecrRefCount(self->rowObj);
    self->rowObj = Tcl_NewListObj(fields, NULL);
    Tcl_IncrRefCount(self->rowObj);

    TRACE(("end_line: Line end, nfields: %d\n", fields));

    self->field_index = 0;
    self->file_lines++;
    self->lines++;
#else // TBD
    int ex_fields = self->expected_fields;
    if (self->lines > 0) {
        if (self->expected_fields >= 0) {
            ex_fields = self->expected_fields;
        } else {
            ex_fields = self->line_fields[self->lines - 1];
        }
    }

    if (self->state == SKIP_LINE) {
        TRACE(("end_line: Skipping row %d\n", self->file_lines));
        // increment file line count
        self->file_lines++;

        // skip the tokens from this bad line
        self->line_start[self->lines] += fields;

        // reset field count
        self->line_fields[self->lines] = 0;
        return 0;
    }
    /* printf("Line: %d, Fields: %d, Ex-fields: %d\n", self->lines, fields, ex_fields); */

    if (!(self->lines <= self->header_end + 1)
        && (self->expected_fields < 0 && fields > ex_fields)) {
        // increment file line count
        self->file_lines++;

        // skip the tokens from this bad line
        self->line_start[self->lines] += fields;

        // reset field count
        self->line_fields[self->lines] = 0;

        // file_lines is now the _actual_ file line number (starting at 1)

        if (self->error_bad_lines) {
            set_error(self,
                      Tcl_ObjPrintf("CSV parse error: expected %d fields in line %d, saw %d\n",
                                    ex_fields, self->file_lines, fields));

            TRACE(("Error at line %d, %d fields\n", self->file_lines, fields));

            return -1;
        } else {
            // simply skip bad lines
            if (self->warn_bad_lines) {
                // pass up error message
                append_warning(self,
                               Tcl_ObjPrintf("Skipping line %d: expected %d fields, saw %d\n",
                                             self->file_lines,
                                             ex_fields,
                                             fields));
            }
        }
    }
    else {
        /* missing trailing delimiters */
        if ((self->lines >= self->header_end + 1) && fields < ex_fields) {

            /* Might overrun the buffer when closing fields */
            if (make_stream_space(self, ex_fields - fields) < 0) {
                set_error(self, Tcl_NewStringObj("out of memory", -1));
                return -1;
            }

            while (fields < ex_fields){
                end_field(self);
                /* printf("Prior word: %s\n", self->words[self->words_len - 2]); */
                fields++;
            }
        }

        // increment both line counts
        self->file_lines++;

        self->lines++;

        /* coliter_t it; */
        /* coliter_setup(&it, self, 5, self->lines - 1); */
        /* printf("word at column 5: %s\n", COLITER_NEXT(it)); */

        // good line, set new start point
        if (self->lines >= self->lines_cap) {
            TRACE(("end_line: ERROR!!! self->lines(%zu) >= self->lines_cap(%zu)\n", self->lines, self->lines_cap));
            set_error(self, Tcl_NewStringObj("Buffer overflow caught - possible malformed input CSV data.\n", -1));
            return PARSER_OUT_OF_MEMORY;                \
        }
        self->line_start[self->lines] = (self->line_start[self->lines - 1] +
                                         fields);

        TRACE(("end_line: new line start: %d\n", self->line_start[self->lines]));

        // new line start with 0 fields
        self->line_fields[self->lines] = 0;
    }
#endif // TBD

    TRACE(("end_line: Finished line, at %d\n", self->lines));

    return 0;
}

int parser_add_skiprow(parser_t *self, int64_t row) {
    khiter_t k;
    kh_int64_t *set;
    int ret = 0;

    if (self->skipset == NULL) {
        self->skipset = (void*) kh_init_int64();
    }

    set = (kh_int64_t*) self->skipset;

    k = kh_put_int64(set, row, &ret);
    set->keys[k] = row;

    return 0;
}

int parser_set_skipfirstnrows(parser_t *self, int64_t nrows)
{
    // self->file_lines is zero based so subtract 1 from nrows
    if (nrows > 0) {
        self->skip_first_N_rows = nrows - 1;
    }

    return 0;
}

static int parser_buffer_bytes(parser_t *self, size_t nbytes)
{
    Tcl_Size chars_read;

    self->datapos = 0;
    if (self->dataObj == NULL)
        self->dataObj = Tcl_NewObj();

    chars_read = Tcl_ReadChars(self->chan, self->dataObj, (Tcl_Size) nbytes, 0);
    if (chars_read > 0) {
        self->data = Tcl_GetStringFromObj(self->dataObj, &self->datalen);
        return 0; /* Success */
    } else if (chars_read == 0) {
        /* Currently treat as EOF as we do not handle non-blocking chans */
        self->datalen = 0;
        return REACHED_EOF;
    } else {
        set_error(self, Tcl_ObjPrintf("Calling read(nbytes) on source failed (Error %d).", Tcl_GetErrno()));
        return -1;
    }
}


/*
  Tokenization macros and state machine code
*/

#define PUSH_CHAR(c)                                                    \
    do {                                                                \
        TRACE(("PUSH_CHAR: Pushing %c\n", c))                           \
        if (self->field_buf_index == sizeof(self->field_buf)) {         \
            Tcl_AppendToObj(self->fieldObj, self->field_buf, self->field_buf_index); \
            self->field_buf_index = 0;                                  \
        }                                                               \
        self->field_buf[self->field_buf_index++] = c;                   \
    } while (0)

/* This is a little bit of a hack but works for now */
#define END_FIELD()                             \
    do {                                        \
        if (end_field(self) < 0) {              \
            goto parsingerror;                  \
        }                                       \
    } while (0)

#define END_LINE_STATE(STATE)                                           \
    do {                                                                \
        if (end_line(self) < 0) {                                       \
            goto parsingerror;                                          \
        }                                                               \
        self->state = STATE;                                            \
        if (line_limit > 0 && self->lines == start_lines + line_limit) { \
            goto linelimit;                                             \
                                                                        \
        }                                                               \
    } while (0)

#define END_LINE_AND_FIELD_STATE(STATE)                                 \
    do {                                                                \
        if (end_line(self) < 0) {                                       \
            goto parsingerror;                                          \
        }                                                               \
        if (end_field(self) < 0) {                                      \
            goto parsingerror;                                          \
        }                                                               \
        self->state = STATE;                                            \
        if (line_limit > 0 && self->lines == start_lines + line_limit) { \
            goto linelimit;                                             \
                                                                        \
        }                                                               \
    } while (0)

#define END_LINE() END_LINE_STATE(START_RECORD)

#define IS_WHITESPACE(c) ((c == ' ' || c == '\t'))

typedef int (*parser_op)(parser_t *self, size_t line_limit);

#define _TOKEN_CLEANUP()                                                \
    do { \
        self->datapos = i;                                              \
        TRACE(("_TOKEN_CLEANUP: datapos: %d, datalen: %d\n", self->datapos, self->datalen)); \
    } while (0)

int skip_this_line(parser_t *self, int64_t linenum) {
    if (self->skipset != NULL) {
        return ( kh_get_int64((kh_int64_t*) self->skipset, self->file_lines) !=
                 ((kh_int64_t*)self->skipset)->n_buckets );
    }
    else {
        return ( linenum <= self->skip_first_N_rows );
    }
}

int tokenize_delimited(parser_t *self, size_t line_limit)
{
    Tcl_Size i, start_lines;
    char c;
    char *buf = self->data + self->datapos;

    start_lines = self->lines;

    TRACE(("%s\n", buf));

    for (i = self->datapos; i < self->datalen; ++i)
    {
        // Next character in file
        c = *buf++;

        TRACE(("tokenize_delimited - Iter: %d Char: 0x%x Line %d, state %d\n",
               i, c, self->file_lines + 1, self->state));

        switch(self->state) {

        case SKIP_LINE:
            TRACE(("tokenize_delimited SKIP_LINE 0x%x, state %d\n", c, self->state));
            if (c == '\n') {
                END_LINE();
            } else if (c == '\r') {
                self->file_lines++;
                self->state = EAT_CRNL_NOP;
            }
            break;

        case START_RECORD:
            // start of record
            if (skip_this_line(self, self->file_lines)) {
                self->state = SKIP_LINE;
                if (c == '\n') {
                    END_LINE();
                }
                break;
            }
            else if (c == '\n') {
                // \n\r possible?
                if (self->skip_empty_lines)
                {
                    self->file_lines++;
                }
                else
                {
                    END_LINE();
                }
                break;
            }
            else if (c == '\r') {
                if (self->skip_empty_lines)
                {
                    self->file_lines++;
                    self->state = EAT_CRNL_NOP;
                }
                else
                    self->state = EAT_CRNL;
                break;
            }
            else if (c == self->commentchar) {
                self->state = EAT_LINE_COMMENT;
                break;
            }
            else if (IS_WHITESPACE(c) && c != self->delimiter && self->skip_empty_lines) {
                self->state = WHITESPACE_LINE;
                break;
            }

            /* normal character - handle as START_FIELD */
            self->state = START_FIELD;
            /* fallthru */

        case START_FIELD:
            /* expecting field */
            if (c == '\n') {
                END_FIELD();
                END_LINE();
            } else if (c == '\r') {
                END_FIELD();
                self->state = EAT_CRNL;
            }
            else if (c == self->quotechar &&
                     self->quoting != QUOTE_NONE) {
                /* start quoted field */
                self->state = IN_QUOTED_FIELD;
            }
            else if (c == self->escapechar) {
                /* possible escaped character */
                self->state = ESCAPED_CHAR;
            }
            else if (c == ' ' && self->skipinitialspace)
                /* ignore space at start of field */
                ;
            else if (c == self->delimiter) {
                /* save empty field */
                END_FIELD();
            }
            else if (c == self->commentchar) {
                END_FIELD();
                self->state = EAT_COMMENT;
            }
            else {
                /* begin new unquoted field */
//                if (self->quoting == QUOTE_NONNUMERIC)
//                    self->numeric_field = 1;

                // TRACE(("pushing %c", c));
                PUSH_CHAR(c);
                self->state = IN_FIELD;
            }
            break;

        case WHITESPACE_LINE: // check if line is whitespace-only
            if (c == '\n') {
                self->file_lines++;
                self->state = START_RECORD; // ignore empty line
            }
            else if (c == '\r') {
                self->file_lines++;
                self->state = EAT_CRNL_NOP;
            }
            else if (IS_WHITESPACE(c) && c != self->delimiter)
                ;
            else { // backtrack
                /* We have to use i + 1 because buf has been incremented but not i */
                do {
                    --buf;
                    --i;
                } while (i + 1 > self->datapos && *buf != '\n');

                if (*buf == '\n') // reached a newline rather than the beginning
                {
                    ++buf; // move pointer to first char after newline
                    ++i;
                }
                self->state = START_FIELD;
            }
            break;

        case ESCAPED_CHAR:
            /* if (c == '\0') */
            /*  c = '\n'; */

            PUSH_CHAR(c);
            self->state = IN_FIELD;
            break;

        case EAT_LINE_COMMENT:
            if (c == '\n') {
                self->file_lines++;
                self->state = START_RECORD;
            } else if (c == '\r') {
                self->file_lines++;
                self->state = EAT_CRNL_NOP;
            }
            break;

        case IN_FIELD:
            /* in unquoted field */
            if (c == '\n') {
                END_FIELD();
                END_LINE();
                /* self->state = START_RECORD; */
            } else if (c == '\r') {
                END_FIELD();
                self->state = EAT_CRNL;
            }
            else if (c == self->escapechar) {
                /* possible escaped character */
                self->state = ESCAPED_CHAR;
            }
            else if (c == self->delimiter) {
                // End of field. End of line not reached yet
                END_FIELD();
                self->state = START_FIELD;
            }
            else if (c == self->commentchar) {
                END_FIELD();
                self->state = EAT_COMMENT;
            }
            else {
                /* normal character - save in field */
                PUSH_CHAR(c);
            }
            break;

        case IN_QUOTED_FIELD:
            /* in quoted field */
            if (c == self->escapechar) {
                /* Possible escape character */
                self->state = ESCAPE_IN_QUOTED_FIELD;
            }
            else if (c == self->quotechar &&
                     self->quoting != QUOTE_NONE) {
                if (self->doublequote) {
                    /* doublequote; " represented by "" */
                    self->state = QUOTE_IN_QUOTED_FIELD;
                }
                else {
                    /* end of quote part of field */
                    self->state = IN_FIELD;
                }
            }
            else {
                /* normal character - save in field */
                PUSH_CHAR(c);
            }
            break;

        case ESCAPE_IN_QUOTED_FIELD:
            /* if (c == '\0') */
            /*  c = '\n'; */

            PUSH_CHAR(c);
            self->state = IN_QUOTED_FIELD;
            break;

        case QUOTE_IN_QUOTED_FIELD:
            /* doublequote - seen a quote in an quoted field */
            if (self->quoting != QUOTE_NONE && c == self->quotechar) {
                /* save "" as " */

                PUSH_CHAR(c);
                self->state = IN_QUOTED_FIELD;
            }
            else if (c == self->delimiter) {
                // End of field. End of line not reached yet

                END_FIELD();
                self->state = START_FIELD;
            }
            else if (c == '\n') {
                END_FIELD();
                END_LINE();
                /* self->state = START_RECORD; */
            }
            else if (c == '\r') {
                END_FIELD();
                self->state = EAT_CRNL;
            }
            else if (!self->strict) {
                PUSH_CHAR(c);
                self->state = IN_FIELD;
            }
            else {
                set_error(self,
                          Tcl_ObjPrintf("CSV parse error: '%c' expected after '%c'",
                                        self->delimiter, self->quotechar));
                goto parsingerror;
            }
            break;

        case EAT_COMMENT:
            if (c == '\n') {
                END_LINE();
            } else if (c == '\r') {
                self->state = EAT_CRNL;
            }
            break;

        case EAT_CRNL:
            if (c == '\n') {
                END_LINE();
                /* self->state = START_RECORD; */
            } else if (c == self->delimiter){
                // Handle \r-delimited files
                END_LINE_AND_FIELD_STATE(START_FIELD);
            } else {
                /* \r line terminator */

                /* UGH. we don't actually want to consume the token. fix this later */
                if (end_line(self) < 0) {
                    goto parsingerror;
                }
                self->state = START_RECORD;

                /* HACK, let's try this one again */
                --i; buf--;
                if (line_limit > 0 && self->lines == start_lines + line_limit) {
                    goto linelimit;
                }

            }
            break;

        case EAT_CRNL_NOP: /* inside an ignored comment line */
            self->state = START_RECORD;
            /* \r line terminator -- parse this character again */
            if (c != '\n' && c != self->delimiter) {
                --i;
                --buf;
            }
            break;
        default:
            break;

        }
    }

    _TOKEN_CLEANUP();

    TRACE(("Finished tokenizing input\n"))

    return 0;

parsingerror:
    i++;
    _TOKEN_CLEANUP();

    return -1;

linelimit:
    i++;
    _TOKEN_CLEANUP();

    return 0;
}

/* custom line terminator */
int tokenize_delim_customterm(parser_t *self, size_t line_limit)
{

    Tcl_Size i, start_lines;
    char c;
    char *buf = self->data + self->datapos;

    start_lines = self->lines;

    TRACE(("%s\n", buf));

    for (i = self->datapos; i < self->datalen; ++i)
    {
        // Next character in file
        c = *buf++;

        TRACE(("tokenize_delim_customterm - Iter: %d Char: %c Line %d field_count %d, state %d\n",
               i, c, self->file_lines + 1, self->state));

        switch(self->state) {

        case SKIP_LINE:
//            TRACE(("tokenize_delim_customterm SKIP_LINE %c, state %d\n", c, self->state));
            if (c == self->lineterminator) {
                END_LINE();
            }
            break;

        case START_RECORD:
            // start of record
            if (skip_this_line(self, self->file_lines)) {
                self->state = SKIP_LINE;
                if (c == self->lineterminator) {
                    END_LINE();
                }
                break;
            }
            else if (c == self->lineterminator) {
                // \n\r possible?
                if (self->skip_empty_lines)
                {
                    self->file_lines++;
                }
                else
                {
                    END_LINE();
                }
                break;
            }
            else if (c == self->commentchar) {
                self->state = EAT_LINE_COMMENT;
                break;
            }
            else if (IS_WHITESPACE(c) && c != self->delimiter && self->skip_empty_lines)
            {
                self->state = WHITESPACE_LINE;
                break;
            }
            /* normal character - handle as START_FIELD */
            self->state = START_FIELD;
            /* fallthru */
        case START_FIELD:
            /* expecting field */
            if (c == self->lineterminator) {
                END_FIELD();
                END_LINE();
                /* self->state = START_RECORD; */
            }
            else if (c == self->quotechar &&
                     self->quoting != QUOTE_NONE) {
                /* start quoted field */
                self->state = IN_QUOTED_FIELD;
            }
            else if (c == self->escapechar) {
                /* possible escaped character */
                self->state = ESCAPED_CHAR;
            }
            else if (c == ' ' && self->skipinitialspace)
                /* ignore space at start of field */
                ;
            else if (c == self->delimiter) {
                /* save empty field */
                END_FIELD();
            }
            else if (c == self->commentchar) {
                END_FIELD();
                self->state = EAT_COMMENT;
            }
            else {
                /* begin new unquoted field */
                if (self->quoting == QUOTE_NONNUMERIC)
                    self->numeric_field = 1;

                // TRACE(("pushing %c", c));
                PUSH_CHAR(c);
                self->state = IN_FIELD;
            }
            break;

        case WHITESPACE_LINE: // check if line is whitespace-only
            if (c == self->lineterminator) {
                self->file_lines++;
                self->state = START_RECORD; // ignore empty line
            }
            else if (IS_WHITESPACE(c) && c != self->delimiter)
                ;
            else { // backtrack
                /* We have to use i + 1 because buf has been incremented but not i */
                do {
                    --buf;
                    --i;
                } while (i + 1 > self->datapos && *buf != self->lineterminator);

                if (*buf == self->lineterminator) // reached a newline rather than the beginning
                {
                    ++buf; // move pointer to first char after newline
                    ++i;
                }
                self->state = START_FIELD;
            }
            break;

        case ESCAPED_CHAR:
            /* if (c == '\0') */
            /*  c = '\n'; */

            PUSH_CHAR(c);
            self->state = IN_FIELD;
            break;

        case IN_FIELD:
            /* in unquoted field */
            if (c == self->lineterminator) {
                END_FIELD();
                END_LINE();
                /* self->state = START_RECORD; */
            }
            else if (c == self->escapechar) {
                /* possible escaped character */
                self->state = ESCAPED_CHAR;
            }
            else if (c == self->delimiter) {
                // End of field. End of line not reached yet
                END_FIELD();
                self->state = START_FIELD;
            }
            else if (c == self->commentchar) {
                END_FIELD();
                self->state = EAT_COMMENT;
            }
            else {
                /* normal character - save in field */
                PUSH_CHAR(c);
            }
            break;

        case IN_QUOTED_FIELD:
            /* in quoted field */
            if (c == self->escapechar) {
                /* Possible escape character */
                self->state = ESCAPE_IN_QUOTED_FIELD;
            }
            else if (c == self->quotechar &&
                     self->quoting != QUOTE_NONE) {
                if (self->doublequote) {
                    /* doublequote; " represented by "" */
                    self->state = QUOTE_IN_QUOTED_FIELD;
                }
                else {
                    /* end of quote part of field */
                    self->state = IN_FIELD;
                }
            }
            else {
                /* normal character - save in field */
                PUSH_CHAR(c);
            }
            break;

        case ESCAPE_IN_QUOTED_FIELD:
            PUSH_CHAR(c);
            self->state = IN_QUOTED_FIELD;
            break;

        case QUOTE_IN_QUOTED_FIELD:
            /* doublequote - seen a quote in an quoted field */
            if (self->quoting != QUOTE_NONE && c == self->quotechar) {
                /* save "" as " */

                PUSH_CHAR(c);
                self->state = IN_QUOTED_FIELD;
            }
            else if (c == self->delimiter) {
                // End of field. End of line not reached yet

                END_FIELD();
                self->state = START_FIELD;
            }
            else if (c == self->lineterminator) {
                END_FIELD();
                END_LINE();
                /* self->state = START_RECORD; */
            }
            else if (!self->strict) {
                PUSH_CHAR(c);
                self->state = IN_FIELD;
            }
            else {
                set_error(self,
                          Tcl_ObjPrintf("CSV parse error: '%c' expected after '%c'",
                                        self->delimiter, self->quotechar));
                goto parsingerror;
            }
            break;

        case EAT_LINE_COMMENT:
            if (c == self->lineterminator) {
                self->file_lines++;
                self->state = START_RECORD;
            }
            break;

        case EAT_COMMENT:
            if (c == self->lineterminator) {
                END_LINE();
            }
            break;

        default:
            break;

        }
    }

    _TOKEN_CLEANUP();

    TRACE(("Finished tokenizing input\n"))

    return 0;

parsingerror:
    i++;
    _TOKEN_CLEANUP();

    return -1;

linelimit:
    i++;
    _TOKEN_CLEANUP();

    return 0;
}

int tokenize_whitespace(parser_t *self, size_t line_limit)
{
    Tcl_Size i, start_lines;
    char c;
    char *buf = self->data + self->datapos;

    start_lines = self->lines;

    TRACE(("%s\n", buf));

    for (i = self->datapos; i < self->datalen; ++i)
    {
        // Next character in file
        c = *buf++;

        TRACE(("tokenize_whitespace - Iter: %d Char: %c Line %d field_count %d, state %d\n",
               i, c, self->file_lines + 1, self->state));

        switch(self->state) {
        case SKIP_LINE:
//            TRACE(("tokenize_whitespace SKIP_LINE %c, state %d\n", c, self->state));
            if (c == '\n') {
                END_LINE();
            } else if (c == '\r') {
                self->file_lines++;
                self->state = EAT_CRNL_NOP;
            }
            break;

        case WHITESPACE_LINE:
            if (c == '\n') {
                self->file_lines++;
                self->state = START_RECORD;
                break;
            }
            else if (c == '\r') {
                self->file_lines++;
                self->state = EAT_CRNL_NOP;
                break;
            }
            // fall through

        case EAT_WHITESPACE:
            if (c == '\n') {
                END_LINE();
                self->state = START_RECORD;
                break;
            } else if (c == '\r') {
                self->state = EAT_CRNL;
                break;
            } else if (!IS_WHITESPACE(c)) {
                // END_FIELD();
                self->state = START_FIELD;
                // Fall through to subsequent state
            } else {
                // if whitespace char, keep slurping
                break;
            }

        case START_RECORD:
            // start of record
            if (skip_this_line(self, self->file_lines)) {
                self->state = SKIP_LINE;
                if (c == '\n') {
                    END_LINE();
                }
                break;
            } else  if (c == '\n') {
                if (self->skip_empty_lines)
                // \n\r possible?
                {
                    self->file_lines++;
                }
                else
                {
                    END_LINE();
                }
                break;
            } else if (c == '\r') {
                if (self->skip_empty_lines)
                {
                    self->file_lines++;
                    self->state = EAT_CRNL_NOP;
                }
                else
                    self->state = EAT_CRNL;
                break;
            } else if (IS_WHITESPACE(c)) {
                /*if (self->skip_empty_lines)
                    self->state = WHITESPACE_LINE;
                    else*/
                    self->state = EAT_WHITESPACE;
                break;
            } else if (c == self->commentchar) {
                self->state = EAT_LINE_COMMENT;
                break;
            } else {
                /* normal character - handle as START_FIELD */
                self->state = START_FIELD;
            }
            /* fallthru */
        case START_FIELD:
            /* expecting field */
            if (c == '\n') {
                END_FIELD();
                END_LINE();
                /* self->state = START_RECORD; */
            } else if (c == '\r') {
                END_FIELD();
                self->state = EAT_CRNL;
            }
            else if (c == self->quotechar &&
                     self->quoting != QUOTE_NONE) {
                /* start quoted field */
                self->state = IN_QUOTED_FIELD;
            }
            else if (c == self->escapechar) {
                /* possible escaped character */
                self->state = ESCAPED_CHAR;
            }
            /* else if (c == ' ' && self->skipinitialspace) */
            /*     /\* ignore space at start of field *\/ */
            /*     ; */
            else if (IS_WHITESPACE(c)) {
                self->state = EAT_WHITESPACE;
            }
            else if (c == self->commentchar) {
                END_FIELD();
                self->state = EAT_COMMENT;
            }
            else {
                /* begin new unquoted field */
                if (self->quoting == QUOTE_NONNUMERIC)
                    self->numeric_field = 1;

                // TRACE(("pushing %c", c));
                PUSH_CHAR(c);
                self->state = IN_FIELD;
            }
            break;

        case EAT_LINE_COMMENT:
            if (c == '\n') {
                self->file_lines++;
                self->state = START_RECORD;
            } else if (c == '\r') {
                self->file_lines++;
                self->state = EAT_CRNL_NOP;
            }
            break;

        case ESCAPED_CHAR:
            /* if (c == '\0') */
            /*  c = '\n'; */

            PUSH_CHAR(c);
            self->state = IN_FIELD;
            break;

        case IN_FIELD:
            /* in unquoted field */
            if (c == '\n') {
                END_FIELD();
                END_LINE();
                /* self->state = START_RECORD; */
            } else if (c == '\r') {
                END_FIELD();
                self->state = EAT_CRNL;
            }
            else if (c == self->escapechar) {
                /* possible escaped character */
                self->state = ESCAPED_CHAR;
            }
            else if (IS_WHITESPACE(c)) {
                // End of field. End of line not reached yet
                END_FIELD();
                self->state = EAT_WHITESPACE;
            }
            else if (c == self->commentchar) {
                END_FIELD();
                self->state = EAT_COMMENT;
            }
            else {
                /* normal character - save in field */
                PUSH_CHAR(c);
            }
            break;

        case IN_QUOTED_FIELD:
            /* in quoted field */
            if (c == self->escapechar) {
                /* Possible escape character */
                self->state = ESCAPE_IN_QUOTED_FIELD;
            }
            else if (c == self->quotechar &&
                     self->quoting != QUOTE_NONE) {
                if (self->doublequote) {
                    /* doublequote; " represented by "" */
                    self->state = QUOTE_IN_QUOTED_FIELD;
                }
                else {
                    /* end of quote part of field */
                    self->state = IN_FIELD;
                }
            }
            else {
                /* normal character - save in field */
                PUSH_CHAR(c);
            }
            break;

        case ESCAPE_IN_QUOTED_FIELD:
            /* if (c == '\0') */
            /*  c = '\n'; */

            PUSH_CHAR(c);
            self->state = IN_QUOTED_FIELD;
            break;

        case QUOTE_IN_QUOTED_FIELD:
            /* doublequote - seen a quote in an quoted field */
            if (self->quoting != QUOTE_NONE && c == self->quotechar) {
                /* save "" as " */

                PUSH_CHAR(c);
                self->state = IN_QUOTED_FIELD;
            }
            else if (IS_WHITESPACE(c)) {
                // End of field. End of line not reached yet

                END_FIELD();
                self->state = EAT_WHITESPACE;
            }
            else if (c == '\n') {
                END_FIELD();
                END_LINE();
                /* self->state = START_RECORD; */
            }
            else if (c == '\r') {
                END_FIELD();
                self->state = EAT_CRNL;
            }
            else if (!self->strict) {
                PUSH_CHAR(c);
                self->state = IN_FIELD;
            }
            else {
                set_error(self,
                          Tcl_ObjPrintf("CSV parse error: '%c' expected after '%c'",
                                        self->delimiter, self->quotechar));
                goto parsingerror;
            }
            break;

        case EAT_CRNL:
            if (c == '\n') {
                END_LINE();
                /* self->state = START_RECORD; */
            } else if (IS_WHITESPACE(c)){
                // Handle \r-delimited files
                END_LINE_STATE(EAT_WHITESPACE);
            } else {
                /* XXX
                 * first character of a new record--need to back up and reread
                 * to handle properly...
                 */
                i--; buf--; /* back up one character (HACK!) */
                END_LINE_STATE(START_RECORD);
            }
            break;

        case EAT_CRNL_NOP: // inside an ignored comment line
            self->state = START_RECORD;
            /* \r line terminator -- parse this character again */
            if (c != '\n' && c != self->delimiter) {
                --i;
                --buf;
            }
            break;

        case EAT_COMMENT:
            if (c == '\n') {
                END_LINE();
            } else if (c == '\r') {
                self->state = EAT_CRNL;
            }
            break;

        default:
            break;


        }

    }

    _TOKEN_CLEANUP();

    TRACE(("Finished tokenizing input\n"))

    return 0;

parsingerror:
    i++;
    _TOKEN_CLEANUP();

    return -1;

linelimit:
    i++;
    _TOKEN_CLEANUP();

    return 0;
}

static int parser_handle_eof(parser_t *self)
{
    TRACE(("handling eof, datalen: %d, pstate: %d\n", self->datalen, self->state))
    if (self->datalen == 0 && (self->state != START_RECORD)) {
        // test cases needed here
        // TODO: empty field at end of line
        TRACE(("handling eof\n"));

        if (self->state == IN_FIELD || self->state == START_FIELD) {
            if (end_field(self) < 0)
                return -1;
        } else if (self->state == QUOTE_IN_QUOTED_FIELD) {
            if (end_field(self) < 0)
                return -1;
        } else if (self->state == IN_QUOTED_FIELD) {
            set_error(self,
                      Tcl_ObjPrintf("CSV parse error: EOF inside string starting at line %" TCL_SIZE_MODIFIER "d",
                                    self->file_lines));
            return -1;
        }

        if (end_line(self) < 0)
            return -1;

        return 0;
    }
    else if (self->datalen == 0 && (self->state == START_RECORD)) {
        return 0;
    }

    return -1;
}

void debug_print_parser(parser_t *self)
{
    int line;

    for (line = 0; line < self->lines; ++line)
    {
        printf("(Parsed) Line %d: ", line);

#ifdef TBD
        for (j = 0; j < self->line_fields[j]; ++j)
        {
            token = self->words[j + self->line_start[line]];
            printf("%s ", token);
        }
        printf("\n");
#endif
    }
}

/*
  nrows : number of rows to tokenize (or until reach EOF)
  all : tokenize all the data vs. certain number of rows
 */

int _tokenize_helper(parser_t *self, size_t nrows, int all)
{
    parser_op tokenize_bytes;

    int status = 0;
    Tcl_Size start_lines = self->lines;

    if (self->delim_whitespace) {
        tokenize_bytes = tokenize_whitespace;
    } else if (self->lineterminator == '\0') {
        tokenize_bytes = tokenize_delimited;
    } else {
        tokenize_bytes = tokenize_delim_customterm;
    }

    if (self->state == FINISHED) {
        return 0;
    }

    TRACE(("_tokenize_helper: Asked to tokenize %d rows, datapos=%d, datalen=%d\n", \
           (int) nrows, self->datapos, self->datalen));

    while (1) {
        if (!all && self->lines - start_lines >= (Tcl_Size)nrows)
            break;

        if (self->datapos == self->datalen) {
            status = parser_buffer_bytes(self, self->chunksize);

            if (status == REACHED_EOF) {
                // close out last line
                status = parser_handle_eof(self);
                self->state = FINISHED;
                break;
            } else if (status != 0) {
                return status;
            }
        }

        TRACE(("_tokenize_helper: Trying to process %d bytes, datalen=%d, datapos= %d\n",
               self->datalen - self->datapos, self->datalen, self->datapos));
        /* TRACE(("sourcetype: %c, status: %d\n", self->sourcetype, status)); */

        status = tokenize_bytes(self, nrows);

        /* debug_print_parser(self); */

        if (status < 0) {
            // XXX
            TRACE(("_tokenize_helper: Status %d returned from tokenize_bytes, breaking\n",
                   status));
            status = -1;
            break;
        }
    }
    TRACE(("leaving tokenize_helper\n"));
    return status;
}

int tokenize_nrows(parser_t *self, size_t nrows)
{
    int status = _tokenize_helper(self, nrows, 0);
    return status;
}

int tokenize_all_rows(parser_t *self)
{
    int status = _tokenize_helper(self, -1, 1);
    return status;
}

parser_t *parser_create(Tcl_Interp *ip, int objc, Tcl_Obj *const objv[], int *pnrows)
{
    parser_t *parser;
    int i, mode, opt, ival, nrows;
    Tcl_Size len;
    char *s;
    int res;
    Tcl_Obj **objs;
    Tcl_Channel chan;
    static const char *switches[] = {
        "-comment", "-delimiter", "-doublequote", "-escape",
        "-excludefields", "-ignoreerrors", "-includefields",
        "-nrows", "-quote", "-quoting",
        "-skipblanklines", "-skipleadingspace", "-skiplines",
        "-startline", "-strict", "-terminator",
        "-chunksize", /* Undocumented */
        NULL
    };
    enum switches_e {
        CSV_COMMENT, CSV_DELIMITER, CSV_DOUBLEQUOTE, CSV_ESCAPE,
        CSV_EXCLUDEFIELDS, CSV_IGNOREERRORS, CSV_INCLUDEFIELDS,
        CSV_NROWS, CSV_QUOTE, CSV_QUOTING,
        CSV_SKIPBLANKLINES, CSV_SKIPLEADINGSPACE, CSV_SKIPLINES,
        CSV_STARTLINE, CSV_STRICT, CSV_TERMINATOR,
        CSV_CHUNKSIZE,
    };
    if (objc < 1) {
        Tcl_SetResult(ip, "Syntax error: CHANNEL argument must be specified.", TCL_STATIC);
	return NULL;
    }

    chan = Tcl_GetChannel(ip, Tcl_GetString(objv[objc-1]), &mode);
    if (chan == NULL)
        return NULL;

    parser = parser_new();
    parser->chunksize = 10*1024; /* TBD - chunksize */
    parser_init(parser);
    parser_set_default_options(parser);
    parser->chan = chan;

    nrows = -1;
    res = TCL_ERROR;
    for (i = 0; i < objc-1; i += 2) {
	if (Tcl_GetIndexFromObj(ip, objv[i], switches, "option", 0, &opt)
            != TCL_OK)
            goto error_handler;
        if ((i+1) >= (objc-1)) {
            Tcl_SetResult(ip, "Missing value for option.", TCL_STATIC);
            goto error_handler;
        }
        s = Tcl_GetStringFromObj(objv[i+1], &len);
        if (opt != CSV_DOUBLEQUOTE && opt != CSV_CHUNKSIZE) {
            s = Tcl_GetStringFromObj(objv[i+1], &len);
            if (len > 0) {
                if ((! isascii(*s)) ||
                    (len > 1 && ! isascii(s[1]))) {
                    Tcl_AppendResult(ip, "Only ASCII characters permitted for option ", Tcl_GetString(objv[i]), ".", NULL);
                    return NULL;
                }
            }
        }

        switch ((enum switches_e) opt) {
        case CSV_COMMENT:
            if (len > 1)
                goto invalid_option_value;
            parser->commentchar = *s; /* '\0' -> No comment char */
            break;
        case CSV_DELIMITER:
            if (len != 1)
                goto invalid_option_value;
            parser->delimiter = *s;
            break;
        case CSV_ESCAPE:
            if (len > 1)
                goto invalid_option_value;
            parser->escapechar = *s; /* \0 -> no escape char */
            break;
        case CSV_NROWS:
            if (pnrows == NULL) {
                Tcl_SetResult(ip, "Option -nrows is not valid in this mode.", TCL_STATIC);
                goto error_handler;
            }
            res = Tcl_GetIntFromObj(ip, objv[i+1], &nrows);
            if (res != TCL_OK)
                goto invalid_option_value;
            break;
        case CSV_QUOTE:
            if (len > 1)
                goto invalid_option_value;
            parser->quotechar = *s;
            break;
        case CSV_QUOTING:
            /*
             * NOTE: this is currently undocumented because for readers,
             * it does not seem to have any effect beyond what is already
             * provided for by the -quote option where -quote "" works
             * similar to QUOTE_NONE. The other options do not have
             * effect on reads.
             */
            if (!strcmp(s, "all"))
                parser->quoting = QUOTE_ALL;
            else if (!strcmp(s, "minimal"))
                parser->quoting = QUOTE_MINIMAL;
            else if (!strcmp(s, "nonnumeric"))
                parser->quoting = QUOTE_NONNUMERIC;
            else if (!strcmp(s, "none"))
                parser->quoting = QUOTE_NONE;
            else
                goto invalid_option_value;
            break;
        case CSV_SKIPLINES:
            res = Tcl_ListObjGetElements(ip, objv[i+1], &len, &objs);
            if (res != TCL_OK)
                goto error_handler;
            else {
                Tcl_Size j;
                Tcl_WideInt wval;
                for (j = 0; j < len; ++j) {
                    res = Tcl_GetWideIntFromObj(ip, objs[j], &wval);
                    if (res != TCL_OK)
                        goto error_handler;
                    if (wval < 0)
                        goto invalid_option_value;
                    parser_add_skiprow(parser, wval);
                }
            }
            break;
        case CSV_STARTLINE:
            res = Tcl_GetIntFromObj(ip, objv[i+1], &ival);
            if (res != TCL_OK)
                goto invalid_option_value;
            parser_set_skipfirstnrows(parser, ival);
            break;
        case CSV_TERMINATOR:
            if (len != 1)
                goto invalid_option_value;
            parser->lineterminator = *s;
            break;
        case CSV_DOUBLEQUOTE:
            if (Tcl_GetBooleanFromObj(ip, objv[i+1], &ival) != TCL_OK)
                goto invalid_option_value;
            parser->doublequote = ival;
            break;
        case CSV_IGNOREERRORS:
            /* TBD - currently not used */
            if (Tcl_GetBooleanFromObj(ip, objv[i+1], &ival) != TCL_OK)
                goto invalid_option_value;
            parser->error_bad_lines = ival;
            break;
        case CSV_SKIPBLANKLINES:
            if (Tcl_GetBooleanFromObj(ip, objv[i+1], &ival) != TCL_OK)
                goto invalid_option_value;
            parser->skip_empty_lines = ival;
            break;
        case CSV_SKIPLEADINGSPACE:
            if (Tcl_GetBooleanFromObj(ip, objv[i+1], &ival) != TCL_OK)
                goto invalid_option_value;
            parser->skipinitialspace = ival;
            break;
        case CSV_STRICT:
            if (Tcl_GetBooleanFromObj(ip, objv[i+1], &ival) != TCL_OK)
                goto invalid_option_value;
            parser->strict = ival;
            break;
        case CSV_INCLUDEFIELDS:
            if (parse_field_indices(objv[i+1],
                                    &parser->num_included_fields,
                                    &parser->included_fields) != TCL_OK)
                goto invalid_option_value;
            break;
        case CSV_EXCLUDEFIELDS:
            if (parse_field_indices(objv[i+1],
                                    &parser->num_excluded_fields,
                                    &parser->excluded_fields) != TCL_OK)
                goto invalid_option_value;
            break;
        case CSV_CHUNKSIZE:
            if (Tcl_GetIntFromObj(ip, objv[i+1], &ival) != TCL_OK)
                goto invalid_option_value;
            if (ival <= 0)
                goto invalid_option_value;
            parser->chunksize = ival;
            break;
        }
    }
    if (pnrows)
        *pnrows = nrows;
    return parser;

invalid_option_value: /* objv[i] should be the invalid option */
    Tcl_SetObjResult(ip, Tcl_ObjPrintf("Invalid value for option %s.", Tcl_GetString(objv[i])));
    /* Fall thru to error return */
error_handler:
    if (parser)
        parser_free(parser);
    return NULL;
}

int csv_read_cmd(ClientData clientdata, Tcl_Interp *ip,
                              int objc, Tcl_Obj *const objv[])
{
    parser_t *parser;
    int nrows, res;

    parser = parser_create(ip, objc-1, objv+1, &nrows);
    if (parser == NULL)
        return TCL_ERROR;

    if (nrows >= 0)
        res = tokenize_nrows(parser, nrows) == 0 ? TCL_OK : TCL_ERROR;
    else
        res = tokenize_all_rows(parser) == 0 ? TCL_OK : TCL_ERROR;

    if (res == TCL_OK)
        Tcl_SetObjResult(ip, parser->rowsObj);
    else {
        if (parser->errorObj)
            Tcl_SetObjResult(ip, parser->errorObj);
        else
            Tcl_SetResult(ip, "Error parsing CSV.", TCL_STATIC);
    }

    parser_free(parser);
    return res;
}

struct csv_write_config {
    char delimiter;      /* Delimiter character */
    char lineterminator1; /* Character to use as line terminator */
    char lineterminator2; /* Character to use as line terminator */
    char escapechar;     /* `\0` or character to use as escape char */
    char quotechar;      /* `\0` or character to use for quoting */
    char quoting;        /* QUOTE_MINIMAL etc. that controls level of quoting */
    char doublequote;    /* Whether quote characters in data should be doubled */
    char specials[6];    /* Used for search for special characters */
};

static void csv_write_config_init (struct csv_write_config *config)
{
    config->delimiter  = ',';
    config->lineterminator1 = '\n';
    config->lineterminator2 = '\0';
    config->escapechar = '\0';
    config->quotechar  = '"';
    config->quoting    = QUOTE_MINIMAL;
    config->doublequote = 1;
    config->specials[0] = '\0'; /* Filled later */
}

/* Return 1 if s is numeric, 0 otherwise. s must be null terminated */
static int csv_numeric(const char *s)
{
    const char *p = s;
    double dval;

    /*
     * TBD - not sure if this is faster than using standard conversion
     * routines but note that numerics include integers and decimals of
     * arbitrary length but not hexadecimals.
     */


    if (*p == '\0')
        return 0;               /* empty string */
    else if (*p == '+' || *p == '-') {
        if (p[1] == '\0')
            return 0; /* Plain +/- is not a number */
        ++p;
    }

    CSV_ASSERT(*p != '\0');

    while (*p) {
        if (! isascii(*p) || !isdigit(*p))
            break;
        ++p;
    }

    if (*p == '\0')
        return 1;               /* Integer of arbitrary length */

    /* Check for decimal or arbitrary length */
    if (*p == '.') {
        ++p;
        while (*p) {
            if (! isascii(*p) || !isdigit(*p))
                break;
            ++p;
        }
        if (*p == '\0')
            return 1;               /* Decimal fraction of arbitrary length */
    }

    /* Finally check floating point formats */
    if (Tcl_GetDouble(NULL, s, &dval) == TCL_OK)
        return 1;
    else
        return 0;
}

static void csv_format_cell(Tcl_DString *ds, Tcl_Obj *cell, struct csv_write_config *config)
{
    char *src, *dst, *p, *end;
    Tcl_Size slen, dlen;
    char lineterminator1, lineterminator2, delimiter, quotechar, escapechar;
    int need_quotes = 0; /* Init just to keep gcc happy */

    src = Tcl_GetStringFromObj(cell, &slen);
    end = src + slen;
    dlen = Tcl_DStringLength(ds);

    /*
     * We do not want to keep checking for destination space so make sure
     * the DString has enough space to begin with. The max length would be
     * length of source string plus possibly two bytes for leading and trailing
     * quotes plus either an escape or doubled quote for each special character
     * which in worst case is entire source string.
     */
    Tcl_DStringSetLength(ds, dlen + 1 + slen + slen + 1);

    /* Get pointer to string AFTER above since DString might be reallocated */
    dst = Tcl_DStringValue(ds);
    dst += dlen;

    /* Get the location of the first special character in source, if any */
    p = strpbrk(src, config->specials);

    /* See if we need to quote */
    switch (config->quoting) {
    case QUOTE_NONE:
        need_quotes = 0;        /* Never quote */
        CSV_ASSERT(config->escapechar);
        break;
    case QUOTE_MINIMAL:
        need_quotes = (p != NULL); /* Quote if special chars present */
        break;
    case QUOTE_NONNUMERIC:
        /* Need quotes unless strictly digits or special chars */
        if (p != NULL || ! csv_numeric(src))
            need_quotes = 1;
        else
            need_quotes = 0;
        break;
    case QUOTE_ALL:
        need_quotes = 1;
        break;
    }

    lineterminator1 = config->lineterminator1;
    lineterminator2 = config->lineterminator2;
    delimiter      = config->delimiter;
    quotechar      = config->quotechar;
    escapechar     = config->escapechar;

    if (need_quotes)
        *dst++ = quotechar;

    if (p == NULL) {
        /* No special chars. Just copy everything over */
        strncpy(dst, src, slen);
        dst += slen;
        if (need_quotes)
            *dst++ = quotechar;
        p = Tcl_DStringValue(ds);
        CSV_ASSERT((dst-p) < Tcl_DStringLength(ds)); /* Assert no buf overflo */
        Tcl_DStringSetLength(ds, (Tcl_Size) (dst - p));
        return;
    }

    /* Copy the characters before the first special char */
    if (p != NULL) {
        ptrdiff_t len = p - src;
        strncpy(dst, src, len);
        dst += len;
        src += len;
    }

    /* Now copy the remaining characters.  */
    if (need_quotes) {
        /*
         * For quoted strings, we only need to take care of quotes in
         * content. Depending on settings they are either doubled up
         * or escaped.
         */
        if (config->doublequote) {
            while (src < end) {
                if (*src == quotechar)
                    *dst++ = quotechar; /* Double the quote */
                *dst++ = *src++;
            }
        } else {
            CSV_ASSERT(escapechar != '\0');
            while (src < end) {
                if (*src == quotechar)
                    *dst++ = escapechar; /* Escape the quote */
                *dst++ = *src++;
            }
        }

        *dst++ = quotechar;     /* Terminating quote */
    } else {
        /* Special characters but no quoting permitted so use escapes */
        CSV_ASSERT(escapechar != '\0');
        while (src < end) {
            if (*src == quotechar ||
                *src == lineterminator1 ||
                *src == lineterminator2 ||
                *src == escapechar ||
                *src == delimiter)
                *dst++ = escapechar;
            *dst++ = *src++;
        }
    }

    p = Tcl_DStringValue(ds);
    CSV_ASSERT((dst-p) < Tcl_DStringLength(ds)); /* Assert no buf overflo */
    Tcl_DStringSetLength(ds, (Tcl_Size) (dst - p));
}

static int csv_write(Tcl_Interp *ip, Tcl_Channel chan, Tcl_Obj *rowObj, struct csv_write_config *config)
{
    Tcl_Obj **rows, **cells;
    Tcl_Size r, c, nrows, ncells, len;
    Tcl_DString ds;

    Tcl_DStringInit(&ds);

    /*
     * Quoting is turned off either via quotechar being empty or
     * quoting policy being QUOTE_NONE.
     */
    if (config->quotechar == '\0')
        config->quoting = QUOTE_NONE;
    else if (config->quoting == QUOTE_NONE)
        config->quotechar = '\0';

    if (config->escapechar == '\0') {
        /* No escape char specified. Must allow quoting then for delimiters */
        if (config->quoting == QUOTE_NONE) {
            Tcl_SetResult(ip, "An escape character must be specified if quoting is disabled.", TCL_STATIC);
            return TCL_ERROR;
        }
        if (! config->doublequote) {
            Tcl_SetResult(ip, "An escape character must be specified if doubling of quotes is disabled.", TCL_STATIC);
            return TCL_ERROR;
        }
    }

    if (Tcl_ListObjGetElements(ip, rowObj, &nrows, &rows) != TCL_OK)
        return TCL_ERROR;

    /*
     * Construct list of characters that are special based on settings.
     * Really used in csv_format_cell but we do it here as to avoid repeating
     * the initialization within the loop.
     */
    r = 0;
    config->specials[r++] = config->delimiter;
    if (config->lineterminator1)
        config->specials[r++] = config->lineterminator1;
    if (config->lineterminator2)
        config->specials[r++] = config->lineterminator2;
    if (config->quotechar)
        config->specials[r++] = config->quotechar;
    if (config->escapechar)
        config->specials[r++] = config->escapechar;
    config->specials[r] = '\0';

    for (r = 0; r < nrows; ++r) {
        if (Tcl_ListObjGetElements(ip, rows[r], &ncells, &cells) != TCL_OK)
            goto error_exit;

        for (c = 0; c < ncells; ++c) {
            csv_format_cell(&ds, cells[c], config);
            /* Append delimiter unless this is the last cell */
            if (c != (ncells-1))
                Tcl_DStringAppend(&ds, &config->delimiter, 1);
        }
        Tcl_DStringAppend(&ds, &config->lineterminator1, 1);
        if (config->lineterminator2)
            Tcl_DStringAppend(&ds, &config->lineterminator2, 1);
        /* Minimize number of I/O but at same time, keep memory reasonable */
        len = Tcl_DStringLength(&ds);
        if (len > 10000) {
            if (Tcl_WriteChars(chan, Tcl_DStringValue(&ds), len) < 0)
                goto io_error;
            Tcl_DStringSetLength(&ds, 0);
        }
    }

    /* Write any remaining bytes */
    len = Tcl_DStringLength(&ds);
    if (len > 0) {
        if (Tcl_WriteChars(chan, Tcl_DStringValue(&ds), len) < 0)
            goto io_error;
    }
    Tcl_DStringFree(&ds);

    return TCL_OK;

io_error: /* ds must have been initialized */
    Tcl_SetResult(ip, "Error writing to channel.", TCL_STATIC);

error_exit: /* ds must have been initialized */
    Tcl_DStringFree(&ds);
    return TCL_ERROR;
}


int csv_write_cmd(ClientData clientdata, Tcl_Interp *ip,
                  int objc, Tcl_Obj *const objv[])
{
    int i, mode, ival;
    static const char *switches[] = {
        "-delimiter", "-doublequote", "-escape",
        "-quote", "-quoting", "-terminator",
        NULL
    };
    enum switches_e {
        CSV_DELIMITER, CSV_DOUBLEQUOTE, CSV_ESCAPE,
        CSV_QUOTE, CSV_QUOTING, CSV_TERMINATOR,
    };
    struct csv_write_config config;
    Tcl_Channel chan;

    if (objc < 3) {
        Tcl_WrongNumArgs(ip, 1, objv, "?options? CHANNEL ROWS");
        return TCL_ERROR;
    }
    chan = Tcl_GetChannel(ip, Tcl_GetString(objv[objc-2]), &mode);
    if (chan == NULL)
        return TCL_ERROR;
    if (!(mode & TCL_WRITABLE)) {
        Tcl_SetResult(ip, "Channel is not open for writing.", TCL_STATIC);
        return TCL_ERROR;
    }

    csv_write_config_init(&config);
    for (i = 1; i < objc-2; i += 2) {
        int opt;
        Tcl_Size len;
        char *s;
	if (Tcl_GetIndexFromObj(ip, objv[i], switches, "option", 0, &opt)
            != TCL_OK)
            return TCL_ERROR;

        if ((i+1) >= (objc-2)) {
            Tcl_SetResult(ip, "Missing value for option.", TCL_STATIC);
            return TCL_ERROR;
        }
        if (opt != CSV_DOUBLEQUOTE) {
            s = Tcl_GetStringFromObj(objv[i+1], &len);
            if (len > 0) {
                if ((! isascii(*s)) ||
                    (len > 1 && ! isascii(s[1]))) {
                    Tcl_AppendResult(ip, "Only ASCII characters permitted for option ", Tcl_GetString(objv[i]), ".", NULL);
                    return TCL_ERROR;
                }
            }
        }
        switch ((enum switches_e) opt) {
        case CSV_DELIMITER:
            if (len != 1)
                goto invalid_option_value;
            config.delimiter = *s;
            break;
        case CSV_ESCAPE:
            if (len > 1)
                goto invalid_option_value;
            config.escapechar = *s; /* \0 -> no escape char */
            break;
        case CSV_QUOTE:
            if (len > 1)
                goto invalid_option_value;
            config.quotechar = *s;
            break;
        case CSV_QUOTING:
            if (!strcmp(s, "all"))
                config.quoting = QUOTE_ALL;
            else if (!strcmp(s, "minimal"))
                config.quoting = QUOTE_MINIMAL;
            else if (!strcmp(s, "nonnumeric"))
                config.quoting = QUOTE_NONNUMERIC;
            else if (!strcmp(s, "none"))
                config.quoting = QUOTE_NONE;
            else
                goto invalid_option_value;
            break;
        case CSV_TERMINATOR:
            if (len != 1 && len != 2)
                goto invalid_option_value;
            config.lineterminator1 = *s;
            config.lineterminator2 = s[1]; /* May be \0 */
            break;
        case CSV_DOUBLEQUOTE:
            if (Tcl_GetBooleanFromObj(ip, objv[i+1], &ival) != TCL_OK)
                goto invalid_option_value;
            config.doublequote = ival;
            break;
        }
    }

    return csv_write(ip, chan, objv[objc-1], &config);

invalid_option_value: /* objv[i] should be the invalid option */
    Tcl_SetObjResult(ip, Tcl_ObjPrintf("Invalid value for option %s.", Tcl_GetString(objv[i])));
    return TCL_ERROR;
}
