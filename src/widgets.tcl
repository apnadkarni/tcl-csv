#
# Copyright (c) 2015, Ashok P. Nadkarni
# All rights reserved.
#
# See the file license.terms for license
#

# Workaround for critcl sourcing of all Tcl files:
#
# critcl will automatically source all files listed through tsources.
# We don't however want to load Tk and snit unless the application actually
# uses these widgets. Thus we check for the presence of these packages
# and simply return if they are not loaded. The dialectpicker proc
# in csv.tcl loads these and then sources this file again so they
# are only loaded when the app actually invokes them.

if {![llength [info commands snit::widget]] ||
    ![llength [info commands winfo]]} {
    return
}
    
package require msgcat

namespace eval tclcsv {
    namespace import ::msgcat::*
    mcmset "" {
        encoding_l     "Character encoding"

        header_line_l  "First line contains a header"
        skip_empty_l   "Skip lines that are empty"
        quote_doubled_l "Quotes are represented by doubling"
        ignore_leading_space_l "Ignore leading space in fields"
        
        delimiter_char_l Delimiter
        comment_char_l "Comment character"
        quote_char_l   "Quote character"
        escape_char_l  "Escape character"
        
        none_l         None
        space_l        Space
        tab_l          Tab
        hash_l         "Hash (#)"
        semicolon_l    "Semicolon (;)"
        comma_l        Comma
        dquote_l       "Double quote (\")"
        squote_l       "Single quote (')"
        backslash_l    "Backslash (\)"
        other_l        Other
        
        include_l      Include
        heading_l      Heading
        type_l         Type
    }
}

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

#
# And finally, my own code

# format text in a label, truncating and adding ellipsis as necessary.
# Also show "" as <empty> for better visual display
proc tclcsv::format_label {win text {align left} {font TkDefaultFont}} {
    # Window has not been mapped yet. 
    if {$text eq ""} {
        set text <empty>
    }
    set nchars [string length $text]
    if {$nchars > 10} {
        set nchars 10
        set width [font measure $font -displayof $win [string repeat a $nchars]]
        set text [fit_text $win $text $font $width $align \u2026]; # Ellipsis 
    }
    $win configure -text $text
}

# A megawidget to permit various options for parsing CSV to be configured
snit::widget tclcsv::dialectpicker {
    hulltype ttk::frame

    # 
    # Options related to parsing the CSV. These can be specified by the
    # caller to initialize the settings for reading CSV data. They can
    # then be changed interactively by the user through the various
    # displayed widgets which are attached to them via -textvariable or
    # -variable

    # File encoding
    option -encoding -default utf-8 -readonly 1 -configuremethod SetOptEncoding

    # Special character settings
    option -delimiter -default \t -configuremethod SetOptDelimiter -readonly 1
    option -comment -default "" -configuremethod SetOptCharPicker -readonly 1
    option -escape -default "" -configuremethod SetOptCharPicker -readonly 1
    option -quote -default \" -configuremethod SetOptCharPicker -readonly 1
    # Holds the "Other" entry content for specifying special characters
    # Array indexed by option
    variable _other;   # Array contents of "Other" entry boxes indexed by option
    
    option -skipblanklines -default 1 -readonly 1
    option -skipleadingspace -default 0 -readonly 1
    option -doublequote -default 1 -readonly 1
    option -headerpresent -default 0 -readonly 1

    #
    # The three main data frames containing the options, the special
    # character configuration and the sample data
    variable _optf;            # Option frame
    variable _charf;           # Character picker frame
    variable _dataf;           # Data frame
    

    # If specified, the column metadata widgets are displayed
    # (name, type etc.). The value must be a dictionary keyed by a
    # data type token, with nested keys align and display (both optional)
    option -columntypes -default "" -readonly 1 -configuremethod SetOptColumnTypes
    # Array mapping display strings to column type tokens
    variable _column_type_display_to_token

    # Stores display strings of column types. Array indexed by col number
    variable _column_type_display_strings
    
    # Stores information whether a column is included or not and column heading,
    # Only used if caller specified the -columntypes option
    # Arrays indexed by column number
    variable _included_columns
    variable _column_headings
    
    # Store state information about the channel we are reading from
    # path - path to file - ONLY PRESENT IF PASSED IN PATH INSTEAD OF CHANNEL
    # name - channel name
    # original_position - original seek position
    # original_encoding - encoding to be restored
    variable _channel

    variable _max_data_lines 6; # How many sample lines to read
    variable _num_data_lines;    # Number actually read
    variable _data_grid_first_data_row; # First row that contains actual values
    variable _data_grid_first_data_col; # First col that contains actual values
    
    constructor {args} {
        if {[llength $args] == 0} {
            error "wrong # args: should be \"dialectpicker ?options? channel\""
        }
        set chan [lindex $args end]
        set args [lrange $args 0 end-1]
        
        $hull configure -borderwidth 0

        array set _included_columns {}
        
        # Init channel and remember original settings for restoring in
        # destructor
        $self ChanInit $chan

        # The three main frames
        set _optf [ttk::frame $win.f-opt -padding 4]
        set _charf [ttk::frame $win.f-char]
        set _dataf [tclcsv::sframe new $win.f-data -anchor w]
        
        # File character encoding
        ttk::frame $_optf.f-encoding
        ttk::label $_optf.f-encoding.l -text [mc encoding_l]
        ttk::combobox $_optf.f-encoding.cb -textvariable [myvar options(-encoding)] -values [lsort [encoding names]] -state readonly
        bind $_optf.f-encoding.cb <<ComboboxSelected>> [mymethod Redisplay]
        pack $_optf.f-encoding.l $_optf.f-encoding.cb -side left -fill both -expand n
        # Data processing objects
        foreach {opt text} {
            -headerpresent header_line_l
            -doublequote quote_doubled_l
            -skipblanklines skip_empty_l
            -skipleadingspace ignore_leading_space_l
        } {
            ttk::checkbutton $_optf.cb$opt -variable [myvar options($opt)] -text [mc $text] -command [mymethod Redisplay]
        }

        # Delimiter selection
        set delimiterf [$self MakeCharPickerFrame -delimiter delimiter_char_l \
                            [list tab_l \t space_l { } comma_l , semicolon_l ";"] \
                            \t]
        
        # Comment char
        set commentf [$self MakeCharPickerFrame -comment comment_char_l  \
                          [list none_l "" hash_l "#"]]

        # Quote char
        set quotef [$self MakeCharPickerFrame -quote quote_char_l \
                          [list none_l "" dquote_l "\"" squote_l "'"] \"]

        # Escape char
        set escapef [$self MakeCharPickerFrame -escape escape_char_l \
                          [list none_l "" backslash_l "\\"]]

        # Start laying out the widgets

        # Options
        grid $_optf.f-encoding - -sticky ew
        grid $_optf.cb-headerpresent $_optf.cb-skipblanklines -sticky ew
        grid $_optf.cb-doublequote $_optf.cb-skipleadingspace -sticky ew
        grid columnconfigure $_optf all -weight 1 -uniform width
        
        pack $_optf -fill none -expand n -pady 4 -anchor w

        # Special characters
        grid $delimiterf $commentf $quotef $escapef -padx 2 -pady 2 -sticky news
        grid columnconfigure $_charf all -uniform width -weight 1
        pack $_charf -fill none -expand n -pady 4 -anchor w

        # Sample data frame
        pack [ttk::separator $win.sep] -fill x -expand n -pady 4
        pack $_dataf -fill both -expand y -anchor nw

        $self configurelist $args

        $self Redisplay
    }

    destructor {
        # Restore channel to its initial state if it is still open
        if {[info exists _channel(name)] &&
            $_channel(name) in [chan names]} {
            if {[info exists _channel(path)]} {
                # We opened the channel ourselves so close it.
                close $_channel(name)
            } else {
                chan configure $_channel(name) -encoding $_channel(original_encoding)
                chan seek $_channel(name) $_channel(original_position)
            }
        }
    }
    
    # -columntypes option handler
    method SetOptColumnTypes {opt val} {
        # Make sure the types returned by sniff_header are included
        if {![dict exists $val string]} {
            dict set val string {display String align left}
        }
        if {![dict exists $val real]} {
            dict set val real {display {Real number} align right}
        }
        if {![dict exists $val integer]} {
            dict set val integer {display Integer align right}
        }
        set options(-columntypes) $val
        
        dict for {tok meta} $options(-columntypes) {
            # Fill in any display strings that are not set
            if {![dict exists $meta display] ||
                [dict get $meta display] eq ""} {
                dict set options(-columntypes) $tok display $tok
            }
            # Likewise, fill in alignment
            if {![dict exists $meta align] ||
                [dict get $meta align] ni {left right center centre}} {
                dict set options(-columntypes) $tok align left
            }

            # Build map of display strings to tokens
            set _column_type_display_to_token([dict get $options(-columntypes) $tok display]) $tok
        }
    }

    # -encoding handler
    method SetOptEncoding {opt val} {
        if {$val ni [encoding names]} {
            error "Unknown encoding \"$val\"."
        }
        set options($opt) $val
        $_optf.cb-encoding set $options(-encoding)
    }

    # -delimiter handler. Unlike other special characters this cannot be ""
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
    
    # Handler for special character related option.
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
        set f [ttk::labelframe $_charf.f$opt -text [mc $title]]
        set rbi -1
        foreach {label value} $rblist {
            set w [ttk::radiobutton $f.rb[incr rbi] -text [mc $label] -value $value -variable [myvar options($opt)] -command [mymethod Redisplay]]
            grid $w - -sticky ew
        }
        set w [ttk::radiobutton $f.rb-other -text Other -value "other" -variable [myvar options($opt)] -command [mymethod Redisplay]]
        set e [$self MakeCharPickerEntry $opt $default_rb_value]
        grid $w $e -sticky w
        grid columnconfigure $f all -uniform width
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
        # Find the max number of columns
        set ncols 0
        foreach row $rows {
            if {[llength $row] > $ncols} {
                set ncols [llength $row]
            }
        }
        set f [tclcsv::sframe content $_dataf]
        destroy {*}[winfo children $f]
        array unset _included_columns *
        
        if {$nrows == 0 || $ncols == 0} {
            grid [ttk::label $f.l-nodata -text "No data to display"] -sticky nw
            return
        }

        if {[dict size $options(-columntypes)]} {
            set _data_grid_first_data_row 4
            set _data_grid_first_data_col 1
            grid [ttk::label $f.l-colname -text [mc heading_l]] -sticky ew -padx 1 -row 1 -column 0
            grid [ttk::label $f.l-coltype -text [mc type_l]] -sticky ew -padx 1 -row 3 -column 0
            grid [ttk::separator $f.sep-0 -orient horizontal] -sticky ew -padx 1 -row 4 -column 0 -pady 4
        } else {
            set _data_grid_first_data_row 2
            set _data_grid_first_data_col 0
        }
        set grid_col $_data_grid_first_data_col
        set type_display_strings [$self ColumnTypeDisplayStrings]
        for {set j 0} {$j < $ncols} {incr j; incr grid_col} {
            # Widget for whether to include the column when reading data
            set _included_columns($j) 1
            set cb [ttk::checkbutton $f.cb-colinc-$j -text [mc include_l] -variable [myvar _included_columns($j)] -command [mymethod IncludeColumn $j]]
            grid $cb -sticky ew -padx 1 -row 0 -column $grid_col

            if {[dict size $options(-columntypes)]} {
                # Entry boxes for column heading
                set e [ttk::entry $f.e-heading-$j -textvariable [myvar _column_headings($j)]]
                grid $e -sticky ew -padx 1 -row 1 -column $grid_col
                
                # Widget for specifying type of the column (for alignment)
                set combo [ttk::combobox $f.cb-type-$j -width 8 -textvariable [myvar _column_type_display_strings($j)] -values $type_display_strings -state readonly]
                bind $combo <<ComboboxSelected>> [mymethod ChangeColumnType $j]
                grid $combo -sticky ew -padx 1 -row 2 -column $grid_col
                
            }
            # Separate the meta fields from data
            grid [ttk::separator $f.sep-$grid_col -orient horizontal] -sticky ew -padx 1 -row [expr {$_data_grid_first_data_row-1}] -column $grid_col -pady 4
        }

        # grid_row tracks the row in the display widget
        # i tracks the data row index
        set grid_row $_data_grid_first_data_row
        set grid_col $_data_grid_first_data_col
        set i 0
        if {$options(-headerpresent)} {
            # If we are displaying the column metadata, the header
            # (or its substitute) is displayed there so won't display it here.
            if {[dict size $options(-columntypes)] == 0} {
                for {set j 0} {$j < $ncols} {incr j; incr grid_col} {
                    set l [ttk::label $f.l-$grid_row-$j -font [list {*}[font configure TkDefaultFont] -weight bold]]
                    tclcsv::format_label $l [lindex $rows $i $j]
                    grid $l -row $grid_row -column $grid_col -sticky ew -padx 1
                }
                incr grid_row
            }
            incr i; # Skip first line of data
        }
        for {} {$i < $nrows} {incr i; incr grid_row} {
            set grid_col $_data_grid_first_data_col
            for {set j 0} {$j < $ncols} {incr j; incr grid_col} {
                if {[$self ColumnAlignment $j] eq "right"} {
                    set anchor e
                } else {
                    set anchor w
                }
                set l [ttk::label $f.l-$grid_row-$j -background white -anchor $anchor]
                tclcsv::format_label $l [lindex $rows $i $j]
                grid $l -row $grid_row -column $grid_col -sticky ew -padx 1
            }
        }
        after 0 after idle [list tclcsv::sframe resize $_dataf]
        return
    }

    method DataGridRowIndexStart {} {
        return $_data_grid_first_data_row
    }

    method DataGridRowIndexLimit {} {
        # The last data grid row depends on whether a header is marked
        # present and if it is displayed as part of column metadata
        # in the "Heading" line
        set first [$self DataGridRowIndexStart]
        set limit [expr {$first + $_num_data_lines}]
        if {[dict size $options(-columntypes)] && $options(-headerpresent)} {
            incr limit -1
        }
        return $limit
    }
    
    # Handler when user clicks on the include column checkboxes
    method IncludeColumn {ci} {
        set f [tclcsv::sframe content $_dataf]
        set ri [$self DataGridRowIndexStart]
        set limit [$self DataGridRowIndexLimit]
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
       
    # Handler for changing a column's type. Changes the sample alignment
    method ChangeColumnType {ci} {
        set f [tclcsv::sframe content $_dataf]
        set ri [$self DataGridRowIndexStart]
        set limit [$self DataGridRowIndexLimit]
        if {[$self ColumnAlignment $ci] eq "right"} {
            set anchor e
        } else {
            set anchor w
        }
        while {$ri < $limit} {
            $f.l-$ri-$ci configure -anchor $anchor
            incr ri
        }
        return
    }

    # Constructs the list of display strings corresponding to column
    # type tokens.
    method ColumnTypeDisplayStrings {} {
        set l {}
        # Note we do not just get the keys from _column_type_display_to_token
        # because that would be in random order
        dict for {key meta} $options(-columntypes) {
            lappend l [dict get $meta display]
        }
        return $l
    }

    # Returns the alignment for a column (left or right)
    method ColumnAlignment {ci} {
        if {[info exists _column_type_display_strings($ci)]} {
            set display $_column_type_display_strings($ci)
            set coltype $_column_type_display_to_token($display)
            return [dict get $options(-columntypes) $coltype align]
        }
        return "left"
    }
    
    # Save the channel settings and initialize it. Sniffs likely
    # CSV format
    method ChanInit {chan} {
        # See if we were passed in a channel or a path
        if {$chan ni [chan names]} {
            # Not a channel. Presume it is a file.
            set _channel(path) $chan
            set chan [open $chan r]
        }
        
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

    # Parse CSV from the channel based on the current option settings.
    # Sets up the header and type by sniffing the channel
    method ChanRead {} {
        set opts [$self CollectCsvOptions]
        if {[dict get $opts -delimiter] eq ""} {
            error "Delimiter must be specified."
        }
        
        lappend opts -nrows $_max_data_lines
        
        # Rewind the file to where we started from
        chan seek $_channel(name) $_channel(original_position)
        chan configure $_channel(name) -encoding $options(-encoding)

        # Figure out the header if necessary but only overwrite existing
        # headers if number of columns has changed
        if {[dict size $options(-columntypes)]} {
            set headers [tclcsv::sniff_header {*}$opts $_channel(name)]
            set types [lindex $headers 0]
            if {![info exists _column_type_display_strings] ||
                [array size _column_type_display_strings] != [llength $types]} {
                array unset _column_type_display_strings *
                for {set i 0} {$i < [llength $types]} {incr i} {
                    set coltype [lindex $types $i]
                    set _column_type_display_strings($i) [dict get $options(-columntypes) $coltype display]
                }
            }
            if {[llength $headers] > 1} {
                set headings [lindex $headers 1]
                if {![info exists _column_headings] ||
                    [array size _column_headings] != [llength $headings]} {
                    array unset _column_headings *
                    for {set i 0} {$i < [llength $headings]} {incr i} {
                        set _column_headings($i) [lindex $headings $i]
                    }
                }
            }
        }
        set rows [tclcsv::csv_read {*}$opts $_channel(name)]
        chan seek $_channel(name) $_channel(original_position)
        set _num_data_lines [llength $rows]
        return $rows
    }

    method CollectCsvOptions {} {
        foreach opt {-delimiter -comment -escape -quote -skipleadingspace -skipblanklines -doublequote} {
            if {$options($opt) ne "other"} {
                lappend opts $opt $options($opt)
            } elseif {[info exists _other($opt)]} {
                lappend opts $opt $_other($opt)
            } else {
                lappend opts $opt ""
            }
        }
        return $opts
    }
    
    # Returns the current setting of -encoding
    method encoding {} {
        # Not part of dialectsettings because that can be passed directly
        # to csv_read
        return $options(-encoding)
    }
    
    # Returns the settings related to the CSV dialect and fields to be
    # included. Can be passed
    # to cvs_read
    method dialect {} {
        set opts [$self CollectCsvOptions]
        if {[dict get $opts -delimiter] eq ""} {
            dict unset opts -delimiter
        }
        if {$options(-headerpresent)} {
            lappend opts -startline 1
        }
        set ncols [array size _included_columns]
        set included {}
        for {set i 0} {$i < $ncols} {incr i} {
            if {[info exists _included_columns($i)] && $_included_columns($i)} {
                lappend included $i
            }
        }
        if {[llength $included] == 0} {
            # Exclude all
            lappend opts -excludefields [lsort -integer [array names _included_columns]]
        } elseif {[llength $included] != $ncols} {
            # Only subset of columns included
            lappend opts -includefields $included
        }
        return $opts
    }

    # Returns the current settings related to column types and names
    method columnsettings {} {
        if {[dict size $options(-columntypes)] == 0} {
            error "Option -columntypes was not specified."
        }
        set ncols [array size _included_columns]
        set header {}
        for {set i 0} {$i < $ncols} {incr i} {
            # Note some rows may have extra fields so always check if
            # corresponding array entry actually exists
            
            if {![info exists _included_columns($i)] ||
                !$_included_columns($i)} {
                continue;       # Skip this columns
            }
            if {[info exists _column_headings($i)] && $_column_headings($i) ne ""} {
                set heading $_column_headings($i)
            } else {
                set heading "Column_$i"
            }
            if {[info exists _column_type_display_strings($i)]} {
                set display $_column_type_display_strings($i)
                set type $_column_type_display_to_token($display)
            } else {
                set type "string"
            }
            lappend header [list heading $heading type $type]
        }
        return $header
    }
}

