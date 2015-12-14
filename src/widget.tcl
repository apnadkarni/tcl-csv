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
    
    variable _optf;            # Option frame
    variable _charf;           # Character option frame
    
    variable _encoding
    
    variable _hdrpresent 0
    variable _skipblanklines 1
    variable _skipleadingspace 0
    variable _doublequote 1
    
    variable _delimiter \t
    variable _delimiter_e "";   # Contents of "Other" entry box
    variable _quotechar \"
    variable _quotechar_e ""
    variable _escchar ""
    variable _escchar_r ""
    variable _commentchar ""
    variable _commentchar_e ""

    constructor {chan args} {
        $hull configure -borderwidth 0

        set _optf [ttk::frame $win.optf]
        tclcsv::labelledcombo $_optf.cb_enc -text Encoding -textvariable [myvar _encoding] -values [lsort [encoding names]] -state readonly
        $_optf.cb_enc set utf-8
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
        ttk::labelframe $win.f-delim -text Delimiter
        ttk::radiobutton $win.f-delim.rb-tab -text Tab -value \t -variable [myvar _delimiter] -command [mymethod redisplay]
        ttk::radiobutton $win.f-delim.rb-space -text Space -value " " -variable [myvar _delimiter] -command [mymethod redisplay]
        ttk::radiobutton $win.f-delim.rb-comma -text Comma -value "," -variable [myvar _delimiter] -command [mymethod redisplay]
        ttk::radiobutton $win.f-delim.rb-semi -text Semicolon -value ";" -variable [myvar _delimiter] -command [mymethod redisplay]
        ttk::radiobutton $win.f-delim.rb-other -text Other -value "other" -variable [myvar _delimiter] -command [mymethod redisplay]
        ttk::entry $win.f-delim.e-other -textvariable [myvar _delimiter_e] -width 1
        grid $win.f-delim.rb-tab - -sticky nw
        grid $win.f-delim.rb-space - -sticky nw
        grid $win.f-delim.rb-comma - -sticky nw
        grid $win.f-delim.rb-semi - -sticky nw
        grid $win.f-delim.rb-other $win.f-delim.e-other -sticky nw

        # Comment char
        ttk::labelframe $win.f-comment -text "Comment character"
        ttk::radiobutton $win.f-comment.rb-none -text None -value "" -variable [myvar _commentchar] -command [mymethod redisplay]
        ttk::radiobutton $win.f-comment.rb-hash -text "Hash (#)" -value "#" -variable [myvar _commentchar] -command [mymethod redisplay]
        ttk::radiobutton $win.f-comment.rb-other -text Other -value "other" -variable [myvar _commentchar] -command [mymethod redisplay]
        ttk::entry $win.f-comment.e-other -textvariable [myvar _commentchar_e] -width 1
        grid $win.f-comment.rb-none - -sticky nw
        grid $win.f-comment.rb-hash - -sticky nw
        grid $win.f-comment.rb-other $win.f-comment.e-other -sticky nw

        # Escape char
        ttk::labelframe $win.f-esc -text "Escape character"
        ttk::radiobutton $win.f-esc.rb-none -text None -value "" -variable [myvar _escchar] -command [mymethod redisplay]
        ttk::radiobutton $win.f-esc.rb-hash -text "Backslash (\\)" -value "\\" -variable [myvar _escchar] -command [mymethod redisplay]
        ttk::radiobutton $win.f-esc.rb-other -text Other -value "other" -variable [myvar _escchar] -command [mymethod redisplay]
        ttk::entry $win.f-esc.e-other -textvariable [myvar _escchar_e] -width 1
        grid $win.f-esc.rb-none - -sticky nw
        grid $win.f-esc.rb-hash - -sticky nw
        grid $win.f-esc.rb-other $win.f-esc.e-other -sticky nw

        # Quote char
        ttk::labelframe $win.f-quote -text "Quote character"
        ttk::radiobutton $win.f-quote.rb-none -text None -value "" -variable [myvar _quotechar] -command [mymethod redisplay]
        ttk::radiobutton $win.f-quote.rb-dquote -text "Double quote (\")" -value \" -variable [myvar _quotechar] -command [mymethod redisplay]
        ttk::radiobutton $win.f-quote.rb-squote -text "Single quote (')" -value \" -variable [myvar _quotechar] -command [mymethod redisplay]
        ttk::radiobutton $win.f-quote.rb-other -text Other -value "other" -variable [myvar _quotechar] -command [mymethod redisplay]
        ttk::entry $win.f-quote.e-other -textvariable [myvar _quotechar_e] -width 1
        grid $win.f-quote.rb-none - -sticky nw
        grid $win.f-quote.rb-dquote - -sticky nw
        grid $win.f-quote.rb-squote - -sticky nw
        grid $win.f-quote.rb-other $win.f-quote.e-other -sticky nw

        grid $_optf.cb_enc - -sticky news
        grid $_optf.cb_hdrpresent $_optf.cb_doublequote $_optf.cb_skipblanklines $_optf.cb_skipleadingspace -sticky news

        pack $_optf -fill both -expand y
        pack $win.f-delim -fill both -expand y -side left
        pack $win.f-comment -fill both -expand y -side left
        pack $win.f-quote -fill both -expand y -side left
        pack $win.f-esc -fill both -expand y -side left
        
    }
        
    method redisplay {} {
        
    }
}
