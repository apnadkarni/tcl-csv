package require Tk
package require snit

namespace eval tclcsv {}

snit::widget tclcsv::labelledcombo {
    hulltype ttk::frame

    component _label
    delegate option -text to _label
    
    component _combo
    delegate option -textvariable to _combo
    delegate option -values to _combo
    delegate option -state to _combo
    delegate method set to _combo
    delegate method get to _combo
    
    constructor {args} {
        $hull configure -borderwidth 0

        install _label using ttk::label $win.l
        install _combo using ttk::combobox $win.cb

        $self configurelist $args

        pack $win.l $win.cb -side left
    }

    method label {} {return $win.l}
    method combobox {} {return $win.cb}
}

snit::widget tclcsv::columnproperties {
    hulltype ttk::frame

    constructor {args} {
        $hull configure -borderwidth 0

        ttk::label $win.l_title -text Title
        ttk::entry $win.e_title -textvariable [myvar _title]
        tclcsv::labelledcombo $win.lc_type -values {integer real string}
        $win.lc_type set string
        ttk::label $win.l_row0
        ttk::label $win.l_row1
    }
}

snit::widget tclcsv::configurator {
    hulltype ttk::frame

    option -chan -default ""

    option -encoding -default utf-8 -readonly 1 -configuremethod SetOptEncoding

    option -delimiter -default \t -configuremethod SetOptDelimiter -readonly 1
    option -comment -default "" -configuremethod SetOptChar -readonly 1
    option -escape -default "" -configuremethod SetOptChar -readonly 1
    option -quote -default \" -configuremethod SetOptChar -readonly 1
    
    variable _optf;            # Option frame
    
    variable _hdrpresent 0
    variable _skipblanklines 1
    variable _skipleadingspace 0
    variable _doublequote 1
    
    variable _other;   # Contents of "Other" entry boxes indexed by option

    constructor {chan args} {
        $hull configure -borderwidth 0

        set _optf [ttk::frame $win.optf]

        tclcsv::labelledcombo $_optf.cb_enc -text Encoding -textvariable [myvar options(-encoding)] -values [lsort [encoding names]] -state readonly
        bind [$_optf.cb_enc combobox] <<ComboboxSelected>> [mymethod redisplay]
        foreach {v text} {
            _hdrpresent {Header present}
            _skipblanklines {Skip blank lines}
            _skipleadingspace {Skip leading spaces}
            _doublequote {Double quotes}
        } {
            ttk::checkbutton $_optf.cb$v -variable [myvar $v] -text $text -command [mymethod redisplay]
        }

        # Delimiter selection
        ttk::labelframe $win.f-delimiter -text Delimiter
        ttk::radiobutton $win.f-delimiter.rb-tab -text Tab -value \t -variable [myvar options(-delimiter)] -command [mymethod redisplay]
        ttk::radiobutton $win.f-delimiter.rb-space -text Space -value " " -variable [myvar options(-delimiter)] -command [mymethod redisplay]
        ttk::radiobutton $win.f-delimiter.rb-comma -text Comma -value "," -variable [myvar options(-delimiter)] -command [mymethod redisplay]
        ttk::radiobutton $win.f-delimiter.rb-semi -text Semicolon -value ";" -variable [myvar options(-delimiter)] -command [mymethod redisplay]
        ttk::radiobutton $win.f-delimiter.rb-other -text Other -value "other" -variable [myvar options(-delimiter)] -command [mymethod redisplay]
        $self MakeOtherEntry -delimiter \t
        grid $win.f-delimiter.rb-tab - -sticky nw
        grid $win.f-delimiter.rb-space - -sticky nw
        grid $win.f-delimiter.rb-comma - -sticky nw
        grid $win.f-delimiter.rb-semi - -sticky nw
        grid $win.f-delimiter.rb-other $win.f-delimiter.e-other -sticky nw

        # Comment char
        ttk::labelframe $win.f-comment -text "Comment character"
        ttk::radiobutton $win.f-comment.rb-none -text None -value "" -variable [myvar options(-comment)] -command [mymethod redisplay]
        ttk::radiobutton $win.f-comment.rb-hash -text "Hash (#)" -value "#" -variable [myvar options(-comment)] -command [mymethod redisplay]
        ttk::radiobutton $win.f-comment.rb-other -text Other -value "other" -variable [myvar options(-comment)] -command [mymethod redisplay]
        $self MakeOtherEntry -comment
        grid $win.f-comment.rb-none - -sticky nw
        grid $win.f-comment.rb-hash - -sticky nw
        grid $win.f-comment.rb-other $win.f-comment.e-other -sticky nw

        # Escape char
        ttk::labelframe $win.f-escape -text "Escape character"
        ttk::radiobutton $win.f-escape.rb-none -text None -value "" -variable [myvar options(-escape)] -command [mymethod redisplay]
        ttk::radiobutton $win.f-escape.rb-hash -text "Backslash (\\)" -value "\\" -variable [myvar options(-escape)] -command [mymethod redisplay]
        ttk::radiobutton $win.f-escape.rb-other -text Other -value "other" -variable [myvar options(-escape)] -command [mymethod redisplay]
        $self MakeOtherEntry -escape
        grid $win.f-escape.rb-none - -sticky nw
        grid $win.f-escape.rb-hash - -sticky nw
        grid $win.f-escape.rb-other $win.f-escape.e-other -sticky nw

        # Quote char
        ttk::labelframe $win.f-quote -text "Quote character"
        ttk::radiobutton $win.f-quote.rb-none -text None -value "" -variable [myvar options(-quote)] -command [mymethod redisplay]
        ttk::radiobutton $win.f-quote.rb-dquote -text "Double quote (\")" -value \" -variable [myvar options(-quote)] -command [mymethod redisplay]
        ttk::radiobutton $win.f-quote.rb-squote -text "Single quote (')" -value "'" -variable [myvar options(-quote)] -command [mymethod redisplay]
        ttk::radiobutton $win.f-quote.rb-other -text Other -value "other" -variable [myvar options(-quote)] -command [mymethod redisplay]
        $self MakeOtherEntry -quote
        grid $win.f-quote.rb-none - -sticky nw
        grid $win.f-quote.rb-dquote - -sticky nw
        grid $win.f-quote.rb-squote - -sticky nw
        grid $win.f-quote.rb-other $win.f-quote.e-other -sticky nw

        grid $_optf.cb_enc - -sticky news
        grid $_optf.cb_hdrpresent $_optf.cb_doublequote $_optf.cb_skipblanklines $_optf.cb_skipleadingspace -sticky news

        pack $_optf -fill both -expand y
        pack $win.f-delimiter -fill both -expand y -side left -padx 2 -pady 2
        pack $win.f-comment -fill both -expand y -side left -padx 2 -pady 2
        pack $win.f-quote -fill both -expand y -side left -padx 2 -pady 2
        pack $win.f-escape -fill both -expand y -side left -padx 2 -pady 2
        
        $self configurelist $args
    }

    method SetOptEncoding {opt val} {
        if {$val ni [encoding names]} {
            error "Unknown encoding \"$val\"."
        }
        set options($opt) $val
        $_optf.cb_enc set $options(-encoding)
    }
    
    method SetOptDelimiter {opt val} {
        if {[string length $val] != 1} {
            error "Invalid value for option $opt. Must be a single character."
        }
        if {$val in [list \t { } "," ";"]} {
            set options($opt) $val
        } else {
            set _other($opt) $val
            set options($opt) "other"
        }
    }
    
    method SetOptChar {opt val} {
        if {[string length $val] > 1} {
            error "Invalid value for option $opt. Must be a single character or the empty string."
        }
        set predefs [dict create \
                         -comment [list # ""] \
                         -quote [list \" ' ""] \
                         -escape [list \\ ""]]
        if {$val in [dict get $predefs $opt]} {
            set options($opt) $val
        } else {
            set _other($opt) $val
            set options($opt) "other"
        }
    }

    # Creates a "Other" entry widget $e that enforces max one character
    # and is tied to a set of radio buttons
    # $opt is the associated option.
    method MakeOtherEntry {opt {default_rb_value {}}} {
        set e $win.f${opt}.e-other
        ttk::entry $e -textvariable [myvar _other($opt)] -width 2 -validate all -validatecommand [mymethod ValidateOtherEntry %d $opt %s %P $default_rb_value]
        return $e
    }
    
    # Validation callback for the "Other" entry fields. Ensures no more
    # than one char and also configures radio buttons based on content
    method ValidateOtherEntry {validation_type opt old new {default_rb_value {}}} {
        puts validation_type=$validation_type
        if {$validation_type == -1} {
            # Revalidation
        } else {
            # Prevalidation
            # Don't allow more than one char in field
            if {[string length $new] > 1} {
                return 0
            }
        }
        if {[string length $new] == 0} {
            if {$options($opt) eq "other"} {
                # "Other" radio selected and empty field, reset radio button
                set options($opt) $default_rb_value 
            }
        } else {
            set options($opt) "other"
        }
        return 1
    }

    method redisplay {} {
       puts redisplay 
    }
}
