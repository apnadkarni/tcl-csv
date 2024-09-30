/*
 * Copyright (c) 2015-2023, Ashok P. Nadkarni
 * All rights reserved.
 *
 * See the file license.terms for license
 */

#include <tcl.h>
#include "csv.h"

typedef struct {
    Tcl_Command cmd;	/* Command associated with this instance. */
    int eof;		/* EOF flag. */
    parser_t *parser;	/* CSV parser pointer. */
} CSVParser;

typedef struct {
    int counter;	/* For creating instance names. */
} CSVClass;

static void
CSVParserRelease(ClientData clientData)
{
    CSVParser *csvPtr = (CSVParser *) clientData;

    if (csvPtr->parser != NULL) {
	parser_free(csvPtr->parser);
	csvPtr->parser = NULL;
    }
    csvPtr->eof = 1;
    ckfree((char *) csvPtr);
}

static void
CSVClassRelease(ClientData clientData)
{
    CSVClass *clsPtr = (CSVClass *) clientData;

    ckfree((char *) clsPtr);
}

static int
CSVParserNext(CSVParser *csvPtr, Tcl_Interp *interp,
	      int objc, Tcl_Obj* const* objv)
{
    Tcl_Size nrows, nread;
    parser_t *parser = csvPtr->parser;

    if (objc > 3) {
	Tcl_WrongNumArgs(interp, 2, objv, "?COUNT?");
	return TCL_ERROR;
    }
    nrows = 1;
    if (objc == 3) {
	if (Tcl_GetSizeIntFromObj(interp, objv[2], &nrows) != TCL_OK) {
	    return TCL_ERROR;
	}
	if (nrows <= 0) {
	    Tcl_SetResult(interp, "Invalid row count specified. "
			  "Must be a positive integer.", TCL_STATIC);
	    return TCL_ERROR;
	}
    }

    if (tokenize_nrows(parser, nrows) != 0 || parser->rowsObj == NULL) {
	if (parser->errorObj) {
	    Tcl_SetObjResult(interp, parser->errorObj);
	} else {
	    Tcl_SetResult(interp, "Error parsing CSV", TCL_STATIC);
	}
	return TCL_ERROR;
    }

    CSV_NOFAIL(Tcl_ListObjLength(interp, parser->rowsObj, &nread), TCL_OK);
    if (nread == 0) {
	csvPtr->eof = 1;
	return TCL_OK; /* Empty result */
    }
    if (objc == 2) {
	/* Return a single row */
	Tcl_Obj *rowObj;

	CSV_NOFAIL(Tcl_ListObjIndex(interp, parser->rowsObj, 0, &rowObj),
		   TCL_OK);
	CSV_ASSERT(rowObj != NULL);
	Tcl_SetObjResult(interp, rowObj);
	CSV_ASSERT(!Tcl_IsShared(parser->rowsObj));
	Tcl_ListObjReplace(interp, parser->rowsObj, 0, 1, 0, NULL);
    } else {
	/* Return nrows rows where nrows might even be 1 */
	if (nread <= nrows) {
	    /* Return the whole list as is */
	    Tcl_SetObjResult(interp, parser->rowsObj);
	    Tcl_DecrRefCount(parser->rowsObj);
	    parser->rowsObj = Tcl_NewListObj(0, NULL);
	    Tcl_IncrRefCount(parser->rowsObj);
	} else {
	    Tcl_Obj **elems;

	    Tcl_ListObjGetElements(interp, parser->rowsObj, &nread, &elems);
	    Tcl_SetObjResult(interp, Tcl_NewListObj(nrows, elems));
	    CSV_ASSERT(! Tcl_IsShared(parser->rowsObj));
	    Tcl_ListObjReplace(interp, parser->rowsObj, 0, nrows, 0, NULL);
	}
    }
    return TCL_OK;
}

static int
CSVInstanceCmd(ClientData clientData, Tcl_Interp *interp,
	       int objc, Tcl_Obj* const* objv)
{
    CSVParser *csvPtr = (CSVParser *) clientData;
    static const char *cmdNames[] = {
	"destroy", "eof", "methods", "next"
    };
    enum cmds {
	CMD_destroy, CMD_eof, CMD_methods, CMD_next
    };
    int cmd;

    if (objc < 2) {
	Tcl_WrongNumArgs(interp, objc, objv, "option ?arg arg ...?");
	return TCL_ERROR;
    }
    if (Tcl_GetIndexFromObj(interp, objv [1], cmdNames, "option", 0, &cmd)
	!= TCL_OK) {
	return TCL_ERROR;
    }
    switch ((enum cmds) cmd) {
    case CMD_destroy: {
	Tcl_Command tcmd;

	if (objc != 2) {
	    Tcl_WrongNumArgs(interp, 2, objv, NULL);
	    return TCL_ERROR;
	}
	tcmd = csvPtr->cmd;
	csvPtr->cmd = NULL;
	Tcl_DeleteCommandFromToken(interp, tcmd);
	return TCL_OK;
    }
    case CMD_eof: {
	if (objc != 2) {
	    Tcl_WrongNumArgs(interp, 2, objv, NULL);
	    return TCL_ERROR;
	}
	Tcl_SetObjResult(interp, Tcl_NewIntObj(csvPtr->eof));
	return TCL_OK;
    }
    case CMD_methods: {
	Tcl_Obj *str[4];

	if (objc != 2) {
	    Tcl_WrongNumArgs(interp, 2, objv, NULL);
	    return TCL_ERROR;
	}
	str[0] = Tcl_NewStringObj(cmdNames[0], -1);
	str[1] = Tcl_NewStringObj(cmdNames[1], -1);
	str[2] = Tcl_NewStringObj(cmdNames[2], -1);
	str[3] = Tcl_NewStringObj(cmdNames[3], -1);
	Tcl_SetObjResult(interp, Tcl_NewListObj(4, str));
	return TCL_OK;
    }
    case CMD_next:
	return CSVParserNext(csvPtr, interp, objc, objv);
    }
    return TCL_ERROR;
}

static int
CSVParserNew(const char *name, Tcl_Interp *interp,
	     int objc, Tcl_Obj* const* objv)
{
    CSVParser *csvPtr;
    Tcl_Obj *fqn;
    Tcl_CmdInfo ci;

    /*
     * Compute the fully qualified command name to use, putting
     * the command into the current namespace if necessary.
     */

    if (!Tcl_StringMatch (name, "::*")) {
	/* Relative name. Prefix with current namespace. */

	Tcl_Eval(interp, "namespace current");
	fqn = Tcl_GetObjResult(interp);
	fqn = Tcl_DuplicateObj(fqn);
	Tcl_IncrRefCount(fqn);
	if (!Tcl_StringMatch(Tcl_GetString (fqn), "::")) {
	    Tcl_AppendToObj(fqn, "::", -1);
	}
	Tcl_AppendToObj(fqn, name, -1);
    } else {
	fqn = Tcl_NewStringObj(name, -1);
	Tcl_IncrRefCount(fqn);
    }
    Tcl_ResetResult(interp);

    /*
     * Check if the commands exists already, and bail out if so.
     * We will not overwrite an existing command.
     */

    if (Tcl_GetCommandInfo(interp, Tcl_GetString(fqn), &ci)) {
	Tcl_Obj* err;

	err = Tcl_NewObj();
	Tcl_AppendToObj(err, "command \"", -1);
	Tcl_AppendObjToObj(err, fqn);
	Tcl_AppendToObj(err, "\" already exists, unable to create ::tclcsv::reader instance", -1);
	Tcl_DecrRefCount(fqn);
	Tcl_SetObjResult(interp, err);
	return TCL_ERROR;
    }

    /*
     * Construct instance data and command.
     */

    csvPtr = (CSVParser *) ckalloc(sizeof(CSVParser));
    csvPtr->eof = 0;
    csvPtr->parser = parser_create(interp, objc, objv, NULL);
    if (csvPtr->parser == NULL) {
	ckfree((char *) csvPtr);
	Tcl_DecrRefCount(fqn);
	return TCL_ERROR;
    }
    csvPtr->cmd = Tcl_CreateObjCommand(interp, Tcl_GetString(fqn),
				       CSVInstanceCmd,
				       (ClientData) csvPtr,
				       CSVParserRelease);
    Tcl_SetObjResult(interp, fqn);
    Tcl_DecrRefCount(fqn);
    return TCL_OK;
}

static int
CSVClassCmd(ClientData clientData, Tcl_Interp *interp,
	    int objc, Tcl_Obj* const* objv)
{
    CSVClass *clsPtr = (CSVClass *) clientData;
    static const char *cmdNames[] = {
	"create", "methods", "new"
    };
    enum cmds {
	CMD_create, CMD_methods, CMD_new
    };
    int cmd;

    if (objc < 2) {
	Tcl_WrongNumArgs(interp, objc, objv, "option ?arg ...?");
	return TCL_ERROR;
    }
    if (Tcl_GetIndexFromObj(interp, objv [1], cmdNames, "option", 0, &cmd)
	!= TCL_OK) {
	return TCL_ERROR;
    }
    switch ((enum cmds) cmd) {
    case CMD_create: {
	char *name;

	if (objc < 3) {
	    Tcl_WrongNumArgs(interp, 1, objv, "name ?arg ...?");
	    return TCL_ERROR;
	}
	name = Tcl_GetString(objv[2]);
	return CSVParserNew(name, interp, objc - 3, objv + 3);
    }
    case CMD_methods: {
	Tcl_Obj *str[3];

	if (objc != 2) {
	    Tcl_WrongNumArgs(interp, 2, objv, NULL);
	    return TCL_ERROR;
	}
	str[0] = Tcl_NewStringObj(cmdNames[0], -1);
	str[1] = Tcl_NewStringObj(cmdNames[1], -1);
	str[2] = Tcl_NewStringObj(cmdNames[2], -1);
	Tcl_SetObjResult(interp, Tcl_NewListObj(3, str));
	return TCL_OK;
    }
    case CMD_new: {
	char buffer[128];

	clsPtr->counter++;
	sprintf(buffer, "::tclcsv::reader%d", clsPtr->counter);
	return CSVParserNew(buffer, interp, objc - 2, objv + 2);
    }
    }
    return TCL_ERROR;
}

int
Tclcsv_Init(Tcl_Interp *interp)
{
    CSVClass *clsPtr;

#ifdef USE_TCL_STUBS
    if (Tcl_InitStubs(interp,TCL_VERSION, 0) == NULL) {
	return TCL_ERROR;
    }
#else
    if (Tcl_PkgRequire(interp, "Tcl", "8.6", 0) == NULL) {
	return TCL_ERROR;
    }
#endif
    clsPtr = (CSVClass *) ckalloc(sizeof (CSVClass));
    clsPtr->counter = 0;
    Tcl_CreateObjCommand(interp, "::tclcsv::csv_read", csv_read_cmd,
			 NULL, NULL);
    Tcl_CreateObjCommand(interp, "::tclcsv::csv_write", csv_write_cmd,
			 NULL, NULL);
    Tcl_CreateObjCommand(interp, "::tclcsv::reader", CSVClassCmd,
			 (ClientData) clsPtr, CSVClassRelease);
    Tcl_PkgProvide(interp, PACKAGE_NAME, PACKAGE_VERSION);
    return TCL_OK;
}

/*
 * Local Variables:
 * mode: c
 * c-basic-offset: 4
 * fill-column: 78
 * tab-width: 8
 * End:
 */
