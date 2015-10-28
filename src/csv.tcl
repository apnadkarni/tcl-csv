#
# Copyright (c) 2015, Ashok P. Nadkarni
# All rights reserved.
#
# See the file license.terms for license
#

proc tclcsv::_sniff2 {chan delimiters} {
    set seek_pos [chan tell $chan]
    if {$seek_pos == -1} {
        error "Channel is not seekable"
    }

    # TBD - what if delimiters or quotes is empty?
    # TBD - what if no rows ?
    
    set escapes [list \\ ""]
    set quotes [list \" ']
    set combinations {}
    foreach delimiter $delimiters {
        foreach quote $quotes {
            foreach doublequote {0 1} {
                foreach escape $escapes {
                    unset -nocomplain width_frequencies
                    try {
                        set nrows 0
                        foreach row [csv_read -nrows 100 -delimiter $delimiter -quote $quote -doublequote $doublequote -escape $escape $chan] {
                            set n [llength $row]
                            if {$n == 0} {
                                # Ignore empty lines
                            }
                            incr width_frequencies($n)
                            incr nrows
                        }
                    } finally {
                        chan seek $chan $seek_pos
                    }
                    if {![info exists width_frequencies]} continue
                    set sorted_frequencies [lsort -stride 2 -decreasing -integer -index 1 [array get width_frequencies]]
                    set mode [lindex $sorted_frequencies 0]
                    set mode_frac [expr {[lindex $sorted_frequencies 1] / double($nrows)}]
                    lappend combinations [list [list -delimiter $delimiter -quote $quote -doublequote $doublequote -escape $escape] $mode $mode_frac]
                }
            }
        }
    }
    return $combinations
}

# Like _sniff above but only considers delimiters
proc tclcsv::_sniff {chan delimiters} {
    set seek_pos [chan tell $chan]
    if {$seek_pos == -1} {
        error "Channel is not seekable"
    }

    # TBD - what if delimiters or quotes is empty?
    # TBD - what if no rows ?
    
    set escapes [list \\ ""]
    set quotes [list \" ']
    set combinations {}
    foreach delimiter $delimiters {
        unset -nocomplain width_frequencies
        try {
            set nrows 0
            while {[gets $chan line] >= 0} {
                if {$line eq ""} continue
                set row [split $line $delimiter]
                set n [llength $row]
                incr width_frequencies($n)
                incr nrows
                if {$nrows > 100} break
            }
        } finally {
            chan seek $chan $seek_pos
        }
        if {![info exists width_frequencies]} continue
        set sorted_frequencies [lsort -stride 2 -decreasing -integer -index 1 [array get width_frequencies]]
        set mode [lindex $sorted_frequencies 0]
        # Fraction of the occurences where the mode frequency occurs
        set mode_frac [expr {[lindex $sorted_frequencies 1] / double($nrows)}]
        lappend combinations [list $delimiter $mode $mode_frac]
    }

    # Sort the candidates such that
    #   - those where the mode fraction is higher are preferred under
    #     the assumption that the more lines that have the same number
    #     of occurences of that character, the greater the likelihood
    #     that character is the delimiter
    #   - those where the mode is higher is preferred under the assumption
    #     that greater occurences of a character within a line are
    #     less likely to be by chance
    set comparator {
        {a b} {
            lassign $a adelim amode afrac
            lassign $b bdelim bmode bfrac
            
            #return [expr {(sqrt($amode)*$afrac) > (sqrt($bmode)*$bfrac)}]
            set aweight [expr {(sqrt($amode)*$afrac)}]
            set bweight [expr {(sqrt($bmode)*$bfrac)}]
            if {$aweight > $bweight} {
                return 1
            } elseif {$aweight < $bweight} {
                return -1
            } else {
                return 0
            }
        } 
    }
    set winner [lindex [lsort -decreasing -command [list apply $comparator]  $combinations] 0]
    set delimiter [lindex $winner 0]
    set nfields [lindex $winner 1]
    
    # We have picked a delimiter. Now figure out whether
    # quotes are in use. By default " is assumed to be the quote char
    # If we find sufficient number of fields beginning with and ending
    # with ' then we assume that is the quote character.
    # Along the way we also check if 
    #   - initial spaces are to be skipped
    #   - quotes are doubled
    #   - an escape character is in use
    #   - comment character
    try {
        set nrows 0
        while {[gets $chan line] >= 0} {
            if {$line eq ""} continue
            set row [split $line $delimiter]
            set n [llength $row]
            if {$n == $nfields} {
                lappend good $row
            } elseif {$n < $nfields} {
                lappend short $row
            } else {
                lappend long $row
            }
            incr nrows
            if {$nrows > 100} break
        }
        set ngood [llength $good]
        if {$ngood == 0} {
            error "Failed to find lines with expected number of fields"
        }
        foreach row $good {
            set fi 0
            foreach field $row {
                # Check for quotes
                if {[regexp {^\s*'.*'$} $field]} {
                    set quotechar '
                }
                # Keep track of leading spaces per column
                if {[string index $field 0] eq " "} {
                    incr nspaces($fi)
                }
                incr fi
            }
        }

        # Check if quotes are doubled
        if {[info exists quotechar]} {
            set ch $quotechar
        } else {
            set ch \"; # Default quote char
        }
        foreach row $good {
            foreach field $row {
                # TBD - how to check if quotes are doubled?
            }
        }
        
        # If every column that had a field beginning with a space also
        # had all fields in that column beginning with a space then
        # we assume leading spaces are to be skipped.
        if {[info exists nspaces]} {
            set skipleadingspace 1
            foreach {col space_count} [array get nspaces] {
                if {$space_count != $ngood} {
                    set skipleadingspace 0
                    break
                }
            }
        }
        # If the bulk of short lines begin with the same character,
        # assume it is the comment character
        if {[info exists short]} {
            foreach row $short {
                set line [string trim [join $row $delimiter]]
                incr comment([string index $line 0])
            }
            set nshort [llength $short]
            foreach {ch count} {
                if {[expr {double($count)/$nshort}] > 0.8} {
                    set commentchar $ch
                    break
                }
            }
        }
    } finally {
        chan seek $chan $seek_pos
    }
    
    set dialect [dict create -delimiter $delimiter]
    if {[info exists skipleadingspace]} {
        dict set dialect -skipleadingspace $skipleadingspace
    }
    if {[info exists quotechar]} {
        dict set dialect -quote $quotechar
    }
    if {[info exists commentchar]} {
        dict set dialect -comment $commentchar
    }
    
    return $dialect
}

proc tclcsv::sniff {args} {
    if {[llength $args] == 0} {
        error "wrong # args: should be \"sniff ?options? channel\""
    }
    set chan [lindex $args end]

    array set opts [dict merge [dict create \
                              -delimiters [list "," ";" ":" "\t"] \
                              ] \
                  [lrange $args 0 end-1]]

    return [_sniff $chan $opts(-delimiters)]
}

    
