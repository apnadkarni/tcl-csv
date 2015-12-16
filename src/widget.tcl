package require Tk
package require snit

namespace eval tclcsv {}



namespace eval tclcsv::sframe {
    # sframe.tcl - from http://wiki.tcl.tk/9223
    # Paul Walton
    # Create a ttk-compatible, scrollable frame widget.
    #   Usage:
    #       sframe new <path> ?-toplevel true?  ?-anchor nsew?
    #       -> <path>
    #
    #       sframe content <path>
    #       -> <path of child frame where the content should go>

    namespace ensemble create
    namespace export *
    
    # Create a scrollable frame or window.
    proc new {path args} {
        # Use the ttk theme's background for the canvas and toplevel
        set bg [ttk::style lookup TFrame -background]
        if { [ttk::style theme use] eq "aqua" } {
            # Use a specific color on the aqua theme as 'ttk::style lookup' is not accurate.
            set bg "#e9e9e9"
        }
        
        # Create the main frame or toplevel.
        if { [dict exists $args -toplevel]  &&  [dict get $args -toplevel] } {
            toplevel $path  -bg $bg
        } else {
            ttk::frame $path
        }
        
        # Create a scrollable canvas with scrollbars which will always be the same size as the main frame.
        set canvas [canvas $path.canvas -bg $bg -bd 0 -highlightthickness 0 -yscrollcommand [list $path.scrolly set] -xscrollcommand [list $path.scrollx set]]
        ttk::scrollbar $path.scrolly -orient vertical   -command [list $canvas yview]
        ttk::scrollbar $path.scrollx -orient horizontal -command [list $canvas xview]
        
        # Create a container frame which will always be the same size as the canvas or content, whichever is greater. 
        # This allows the child content frame to be properly packed and also is a surefire way to use the proper ttk background.
        set container [ttk::frame $canvas.container]
        pack propagate $container 0
        
        # Create the content frame. Its size will be determined by its contents. This is useful for determining if the 
        # scrollbars need to be shown.
        set content [ttk::frame $container.content]
        
        # Pack the content frame and place the container as a canvas item.
        set anchor "n"
        if { [dict exists $args -anchor] } {
            set anchor [dict get $args -anchor]
        }
        pack $content -anchor $anchor
        $canvas create window 0 0 -window $container -anchor nw
        
        # Grid the scrollable canvas sans scrollbars within the main frame.
        grid $canvas   -row 0 -column 0 -sticky nsew
        grid rowconfigure    $path 0 -weight 1
        grid columnconfigure $path 0 -weight 1
        
        # Make adjustments when the sframe is resized or the contents change size.
        bind $path.canvas <Expose> [list [namespace current]::resize $path]
        
        # Mousewheel bindings for scrolling.
        bind [winfo toplevel $path] <MouseWheel>       [list +[namespace current] scroll $path yview %W %D]
        bind [winfo toplevel $path] <Shift-MouseWheel> [list +[namespace current] scroll $path xview %W %D]
        
        return $path
    }
    
    
    # Given the toplevel path of an sframe widget, return the path of the child frame suitable for content.
    proc content {path} {
        return $path.canvas.container.content
    }
    
    
    # Make adjustments when the the sframe is resized or the contents change size.
    proc resize {path} {
        set canvas    $path.canvas
        set container $canvas.container
        set content   $container.content
        
        # Set the size of the container. At a minimum use the same width & height as the canvas.
        set width  [winfo width $canvas]
        set height [winfo height $canvas]
        
        # If the requested width or height of the content frame is greater then use that width or height.
        if { [winfo reqwidth $content] > $width } {
            set width [winfo reqwidth $content]
        }
        if { [winfo reqheight $content] > $height } {
            set height [winfo reqheight $content]
        }
        $container configure  -width $width  -height $height
        
        # Configure the canvas's scroll region to match the height and width of the container.
        $canvas configure -scrollregion [list 0 0 $width $height]
        
        # Show or hide the scrollbars as necessary.
        # Horizontal scrolling.
        if { [winfo reqwidth $content] > [winfo width $canvas] } {
            grid $path.scrollx  -row 1 -column 0 -sticky ew
        } else {
            grid forget $path.scrollx
        }
        # Vertical scrolling.
        if { [winfo reqheight $content] > [winfo height $canvas] } {
            grid $path.scrolly  -row 0 -column 1 -sticky ns
        } else {
            grid forget $path.scrolly
        }
        return
    }
    
    
    # Handle mousewheel scrolling.    
    proc scroll {path view W D} {
        if { [winfo exists $path.canvas]  &&  [string match $path.canvas* $W] } {
            $path.canvas $view scroll [expr {-$D}] units
        }
        return
    }
}

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

#------------------------------------------------------------------------------
# Copied from Csaba Nemethi's tablelist package
# tablelist::strRange
#
# Gets the largest initial (for alignment = left or center) or final (for
# alignment = right) range of characters from str whose width, when displayed
# in the given font, is no greater than pixels decremented by the width of
# snipStr.  Returns a string obtained from this substring by appending (for
# alignment = left or center) or prepending (for alignment = right) (part of)
# snipStr to it.
#------------------------------------------------------------------------------
proc tclcsv::fit_text {win str font pixels alignment snipStr} {
    if {$pixels < 0} {
        return ""
    }

    set width [font measure $font -displayof $win $str]
    if {$width <= $pixels} {
        return $str
    }

    set snipWidth [font measure $font -displayof $win $snipStr]
    if {$pixels <= $snipWidth} {
        set str $snipStr
        set snipStr ""
    } else {
        incr pixels -$snipWidth
    }

    if {[string compare $alignment "right"] == 0} {
        set idx [expr {[string length $str]*($width - $pixels)/$width}]
        set subStr [string range $str $idx end]
        set width [font measure $font -displayof $win $subStr]
        if {$width < $pixels} {
            while 1 {
                incr idx -1
                set subStr [string range $str $idx end]
                set width [font measure $font -displayof $win $subStr]
                if {$width > $pixels} {
                    incr idx
                    set subStr [string range $str $idx end]
                    return $snipStr$subStr
                } elseif {$width == $pixels} {
                    return $snipStr$subStr
                }
            }
        } elseif {$width == $pixels} {
            return $snipStr$subStr
        } else {
            while 1 {
                incr idx
                set subStr [string range $str $idx end]
                set width [font measure $font -displayof $win $subStr]
                if {$width <= $pixels} {
                    return $snipStr$subStr
                }
            }
        }

    } else {
        set idx [expr {[string length $str]*$pixels/$width - 1}]
        set subStr [string range $str 0 $idx]
        set width [font measure $font -displayof $win $subStr]
        if {$width < $pixels} {
            while 1 {
                incr idx
                set subStr [string range $str 0 $idx]
                set width [font measure $font -displayof $win $subStr]
                if {$width > $pixels} {
                    incr idx -1
                    set subStr [string range $str 0 $idx]
                    return $subStr$snipStr
                } elseif {$width == $pixels} {
                    return $subStr$snipStr
                }
            }
        } elseif {$width == $pixels} {
            return $subStr$snipStr
        } else {
            while 1 {
                incr idx -1
                set subStr [string range $str 0 $idx]
                set width [font measure $font -displayof $win $subStr]
                if {$width <= $pixels} {
                    return $subStr$snipStr
                }
            }
        }
    }
}

proc tclcsv::truncated_label {win text {align left} {font TkDefaultFont}} {
    # Window has not been mapped yet. 
    set nchars [string length $text]
    if {$nchars > 10} {
        set nchars 10
        set width [font measure $font -displayof $win [string repeat a $nchars]]
        set text [fit_text $win $text $font $width $align \u2026]; # Ellipsis 
    }
    $win configure -text $text
}

snit::widget tclcsv::configurator {
    hulltype ttk::frame

    option -encoding -default utf-8 -readonly 1 -configuremethod SetOptEncoding

    option -delimiter -default \t -configuremethod SetOptDelimiter -readonly 1
    option -comment -default "" -configuremethod SetOptCharPicker -readonly 1
    option -escape -default "" -configuremethod SetOptCharPicker -readonly 1
    option -quote -default \" -configuremethod SetOptCharPicker -readonly 1
    
    option -headerpresent -default 0 -readonly 1
    option -skipblanklines -default 1 -readonly 1
    option -skipleadingspace -default 0 -readonly 1
    option -doublequote -default 1 -readonly 1
    
    # If true, show the widgets to set column titles, types etc.
    option -enablecolumnnames -default 0 -readonly 1
    
    variable _optf;            # Option frame
    variable _charf;           # Character picker frame
    variable _dataf;           # Data frame
    
    variable _other;   # Contents of "Other" entry boxes indexed by option

    # Stores information whether a column is included or not,
    # column titles and types
    # Arrays indexed by column number
    variable _included_columns
    variable _column_types
    variable _column_names
    variable _column_titles
    
    # Store state information about the channel we are reading from
    # name - channel name
    # original_position - original seek position
    # original_encoding - encoding to be restored
    variable _channel

    variable _max_data_lines 6; # How many sample lines to read
    variable _num_data_lines;    # Number actually read
    variable _data_grid_first_data_row; # First row that contains actual values
    variable _data_grid_first_data_col; # First col that contains actual values
    
    constructor {chan args} {
        $hull configure -borderwidth 0

        array set _included_columns {}
        
        $self ChanInit $chan

        set _optf [ttk::frame $win.f-opt -padding 4]
        set _charf [ttk::frame $win.f-char]
        set _dataf [tclcsv::sframe new $win.f-data -anchor w]
        
        tclcsv::labelledcombo $_optf.cb-encoding -text Encoding -textvariable [myvar options(-encoding)] -values [lsort [encoding names]] -state readonly
        bind [$_optf.cb-encoding combobox] <<ComboboxSelected>> [mymethod Redisplay]
        foreach {opt text} {
            -headerpresent {First line contains a header}
            -skipblanklines {Skip lines that are empty}
            -skipleadingspace {Ignore leading spaces in fields}
            -doublequote {Quotes are represented by doubling}
        } {
            ttk::checkbutton $_optf.cb$opt -variable [myvar options($opt)] -text $text -command [mymethod Redisplay]
        }

        # Delimiter selection
        set delimiterf [$self MakeCharPickerFrame -delimiter Delimiter \
                            [list Tab \t Space { } Comma , Semicolon ";"] \
                            \t]
        
        # Comment char
        set commentf [$self MakeCharPickerFrame -comment "Comment character" \
                          [list None "" "Hash (#)" "#"]]

        # Escape char
        set escapef [$self MakeCharPickerFrame -escape "Escape character" \
                          [list None "" "Backslash (\\)" "\\"]]

        # Quote char
        set quotef [$self MakeCharPickerFrame -quote "Quote character" \
                          [list None "" "Double quote (\")" "\"" "Single quote (')" "'"] \"]

        grid $_optf.cb-encoding - -sticky ew
        grid $_optf.cb-headerpresent $_optf.cb-skipblanklines -sticky ew
        grid $_optf.cb-doublequote $_optf.cb-skipleadingspace -sticky ew
        grid columnconfigure $_optf all -weight 1
        

        pack $_optf -fill both -expand y -pady 4
        pack $delimiterf -fill both -expand y -side left -padx 2 -pady 2
        pack $commentf -fill both -expand y -side left -padx 2 -pady 2
        pack $quotef -fill both -expand y -side left -padx 2 -pady 2
        pack $escapef -fill both -expand y -side left -padx 2 -pady 2
        pack $_charf -fill both -expand y -pady 4
        pack [ttk::separator $win.sep] -fill x -expand y -pady 4
        pack $_dataf -fill both -expand y -anchor nw

        $self configurelist $args
        $self Redisplay
    }

    destructor {
        if {[info exists _channel(name)]} {
            chan configure $_channel(name) -encoding $_channel(original_encoding)
            chan seek $_channel(name) $_channel(original_position)
        }
    }
    
    method SetOptEncoding {opt val} {
        if {$val ni [encoding names]} {
            error "Unknown encoding \"$val\"."
        }
        set options($opt) $val
        $_optf.cb-encoding set $options(-encoding)
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
    
    method SetOptCharPicker {opt val} {
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
    method MakeCharPickerEntry {opt {default_rb_value {}}} {
        set e $_charf.f${opt}.e-other
        ttk::entry $e -textvariable [myvar _other($opt)] -width 2 -validate all -validatecommand [mymethod ValidateCharPickerEntry %d $opt %s %P $default_rb_value]
        return $e
    }
    
    # Validation callback for the "Other" entry fields. Ensures no more
    # than one char and also configures radio buttons based on content
    method ValidateCharPickerEntry {validation_type opt old new {default_rb_value {}}} {
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
                # We used to reset to the default button but that does not work
                # well when changing the content of the Other entry field
                if {0} {
                    set options($opt) $default_rb_value 
                }
            }
        } else {
            set options($opt) "other"
        }
        after idle after 0 [mymethod Redisplay]
        return 1
    }

    # Make a labelled frame containing the radiobuttons for selecting
    # characters used for special purposes.
    method MakeCharPickerFrame {opt title rblist {default_rb_value {}}} {
        set f [ttk::labelframe $_charf.f$opt -text $title]
        set rbi -1
        foreach {label value} $rblist {
            set w [ttk::radiobutton $f.rb[incr rbi] -text $label -value $value -variable [myvar options($opt)] -command [mymethod Redisplay]]
            grid $w - -sticky ew
        }
        set w [ttk::radiobutton $f.rb-other -text Other -value "other" -variable [myvar options($opt)] -command [mymethod Redisplay]]
        set e [$self MakeCharPickerEntry $opt $default_rb_value]
        grid $w $e -sticky ew
        return $f
    }

    # Called when entire display has to be redone, for example when the
    # delimiter is changed
    method Redisplay {} {
        if {$options(-delimiter) eq "other" &&
            (![info exists _other(-delimiter)] || $_other(-delimiter) eq "")} {
            focus $_charf.f-delimiter.e-other
            return
        }
            
        set rows [$self ChanRead]
        set nrows [llength $rows]
        set ncols [llength [lindex $rows 0]]
        set f [tclcsv::sframe content $_dataf]
        destroy {*}[winfo children $f]
        array unset _included_columns *
        array unset _column_types *
        
        if {$nrows == 0 || $ncols == 0} {
            grid [ttk::label $_dataf.l-nodata -text "No data to display"] -sticky nw
            return
        }

        if {$options(-enablecolumnnames)} {
            set _data_grid_first_data_row 5
            set _data_grid_first_data_col 1
            grid [ttk::label $f.l-colname -text "Name:"] -sticky ew -padx 1 -row 1 -column 0
            grid [ttk::label $f.l-title -text "Title:"] -sticky ew -padx 1 -row 2 -column 0
            grid [ttk::label $f.l-coltype -text "Type:"] -sticky ew -padx 1 -row 3 -column 0
            grid [ttk::separator $f.sep-0 -orient horizontal] -sticky ew -padx 1 -row 4 -column 0
        } else {
            set _data_grid_first_data_row 1
            set _data_grid_first_data_col 0
        }
        set grid_col $_data_grid_first_data_col
        for {set j 0} {$j < $ncols} {incr j; incr grid_col} {
            # Widget for whether to include the column when reading data
            set _included_columns($j) 1
            set cb [ttk::checkbutton $f.cb-colinc-$j -text Include -variable [myvar _included_columns($j)] -command [mymethod IncludeColumn $j]]
            grid $cb -sticky ew -padx 1 -row 0 -column $grid_col

            if {$options(-enablecolumnnames)} {
                # Entry boxes for name and title of column
                set e [ttk::entry $f.e-name-$j -textvariable [myvar _column_names($j)]]
                grid $e -sticky ew -padx 1 -row 1 -column $grid_col
                set e [ttk::entry $f.e-title-$j -textvariable [myvar _column_titles($j)]]
                grid $e -sticky ew -padx 1 -row 2 -column $grid_col
                
                # Widget for specifying type of the column (for alignment)
                set _column_types($j) string
                set combo [ttk::combobox $f.cb-type-$j -width 8 -textvariable [myvar _column_types($j)] -values {string int32 int64 double boolean} -state readonly]
                bind $combo <<ComboboxSelected>> [mymethod ChangeColumnType $j]
                grid $combo -sticky ew -padx 1 -row 3 -column $grid_col
                
                # Separate the meta fields from data
                grid [ttk::separator $f.sep-$grid_col -orient horizontal] -sticky ew -padx 5 -row 4 -column 0
            }
        }
        set grid_row $_data_grid_first_data_row
        set grid_col $_data_grid_first_data_col
        set i 0
        if {$options(-headerpresent)} {
            for {set j 0} {$j < $ncols} {incr j; incr grid_col} {
                set l [ttk::label $f.l-$grid_row-$j -font [list {*}[font configure TkDefaultFont] -weight bold]]
                tclcsv::truncated_label $l [lindex $rows $i $j]
                grid $l -row $grid_row -column $grid_col -sticky ew -padx 1
            }
            incr i
            incr grid_row
        }
        for {} {$i < $nrows} {incr i; incr grid_row} {
            set grid_col $_data_grid_first_data_col
            for {set j 0} {$j < $ncols} {incr j; incr grid_col} {
                set l [ttk::label $f.l-$grid_row-$j -background white]
                tclcsv::truncated_label $l [lindex $rows $i $j]
                grid $l -row $grid_row -column $grid_col -sticky ew -padx 1
            }
        }
        after 0 after idle [list tclcsv::sframe resize $_dataf]
        return
    }

    method IncludeColumn {ci} {
        set f [tclcsv::sframe content $_dataf]
        set ri $_data_grid_first_data_row
        set limit [expr {$ri + $_num_data_lines}]
        if {$_included_columns($ci)} {
            while {$ri < $limit} {
                $f.l-$ri-$ci configure -state enabled
                incr ri
            }
        } else {
            while {$ri < $limit} {
                $f.l-$ri-$ci configure -state disabled
                incr ri
            }
        }
        return
    }
       
    method ChangeColumnType {ci} {
        set f [tclcsv::sframe content $_dataf]
        set ri $_data_grid_first_data_row
        set limit [expr {$ri + $_num_data_lines}]
        if {$_column_types($ci) eq "string"} {
            while {$ri < $limit} {
                $f.l-$ri-$ci configure -anchor w
                incr ri
            }
        } else {
            while {$ri < $limit} {
                $f.l-$ri-$ci configure -anchor e
                incr ri
            }
        }
        return
    }

    method ChanInit {chan} {
        set _channel(original_encoding) [chan configure $chan -encoding]
        set _channel(original_position)  [chan tell $chan]
        if {$_channel(original_position) == -1} {
            error "Channel does not support seeking."
        }
        set _channel(name) $chan

        # Guess the format of the CSV
        array set options [tclcsv::sniff $chan]
        if {[llength [tclcsv::sniff_header $chan]] > 1} {
            set options(-headerpresent) 1
        } else {
            set options(-headerpresent) 0
        }
        # Note above setting will be overwritten by options passed by app
        
        return
    }
    
    method ChanRead {} {
        foreach opt {-delimiter -comment -escape -quote -skipleadingspace -skipblanklines -doublequote} {
            if {$options($opt) ne "other"} {
                lappend opts $opt $options($opt)
            } elseif {[info exists _other($opt)]} {
                lappend opts $opt $_other($opt)
            } else {
                lappend opts $opt ""
            }
        }
        lappend opts -nrows $_max_data_lines

        if {[dict get $opts -delimiter] eq ""} {
            error "Delimiter must be specified."
        }
        
        # Rewind the file to where we started from
        chan seek $_channel(name) $_channel(original_position)
        chan configure $_channel(name) -encoding $options(-encoding)

        # Figure out the header if necessary but only overwrite existing
        # headers if number of columns has changed
        if {$options(-enablecolumnnames)} {
            set headers [tclcsv::sniff_header {*}$opts $_channel(name)]
            if {[llength $headers] > 1} {
                set titles [lindex $headers 1]
                if {![info exists _column_titles] ||
                    [array size _column_titles] != [llength $titles]} {
                    array unset _column_titles *
                    for {set i 0} {$i < [llength $titles]} {incr i} {
                        set title [lindex $titles $i]
                        set _column_titles($i) $title
                        set _column_names($i) [regsub {[^[:alnum:]_]} $title _]
                    }
                }
            }
        }
        
        set rows [tclcsv::csv_read {*}$opts $_channel(name)]
        chan seek $_channel(name) $_channel(original_position)
        set _num_data_lines [llength $rows]
        return $rows
    }
}
