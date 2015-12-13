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
    
    variable _optf;            # Option frame
    variable _charf;           # Character option frame
    
    variable _encoding
    
    variable _hdrpresent 0
    variable _skipblanklines 1
    variable _skipleadingspace 0
    variable _doublequote 1
    
    variable _delimiter
    variable _quotechar
    variable _escchar
    variable _commentchar
    
    constructor {args} {
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

        set _charf [ttk::frame $win.charf]
        foreach {v text} {
            _delimiter {Delimiter}
            _quotechar {Quote character}
            _escchar   {Escape character}
            _commentchar {Comment character}
        } {
            ttk::label $_charf.l$v -text $text
            ttk::entry $_charf.e$v -textvariable [myvar $v] -width 1
        }

        grid $_optf.cb_enc - -sticky news
        grid $_optf.cb_hdrpresent $_optf.cb_doublequote -sticky news
        grid $_optf.cb_skipblanklines $_optf.cb_skipleadingspace -sticky news

        grid $_charf.l_delimiter $_charf.e_delimiter $_charf.l_quotechar $_charf.e_quotechar -sticky news
        grid $_charf.l_escchar $_charf.e_escchar $_charf.l_commentchar $_charf.e_commentchar -sticky news
        

        pack $_optf -fill both -expand y
        pack $_charf -fill both -expand y
        
    }
        
    method redisplay {} {
        puts redisplay
    }
}
