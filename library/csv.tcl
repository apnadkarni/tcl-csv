#
# Copyright (c) 2015, Ashok P. Nadkarni
# All rights reserved.
#
# See the file license.terms for license
#

namespace eval tclcsv {
    variable script_dir
    set script_dir [file dirname [info script]]
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
            set findex 0
            set doublequotecount 0
            set singlequotecount 0
            foreach field $row {
                # Check for quotes
                if {[regexp {^\s*".*"$} $field]} {
                    incr doublequotecount
                } elseif {[regexp {^\s*'.*'$} $field]} {
                    incr singlequotecount
                }
                # Keep track of leading spaces per column
                if {[string index $field 0] eq " "} {
                    incr nspaces($findex)
                }
                incr findex
            }
            if {$singlequotecount > $doublequotecount} {
                set quotechar '
            } else {
                # Note even though double quote is the default do not
                # explicitly mark as such unless we have actually seen it
                if {$doublequotecount > 0} {
                    set quotechar \"
                }
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
                if {[regexp "\\s*${ch}\[^${ch}\]*${ch}${ch}" $field]} {
                    incr doublequote
                } elseif {[regexp "\\s*${ch}\[^${ch}\]*(\[^\[:alnum:\]\])${ch}" $field -> esc]} {
                    incr esc_chars($esc)
                }
            }
            if {(![info exists doublequote]) && [info exists esc_chars]} {
                set esc_list [lsort -decreasing -integer -stride 2 -index 1 [array get esc_chars]]
                set escape [lindex $esc_list 0]
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
            foreach {ch count} [array get comment] {
                if {[expr {double($count)/$nshort}] > 0.8} {
                    set commentchar $ch
                    break
                }
            }
        }

        # TBD - perhaps long lines can also be used since long lines
        # can result from delimiters embedded within quotes

    } finally {
        chan seek $chan $seek_pos
    }

    set dialect [list -delimiter $delimiter]
    if {[info exists skipleadingspace]} {
        lappend dialect -skipleadingspace $skipleadingspace
    }
    if {[info exists quotechar]} {
        lappend dialect -quote $quotechar
    }
    if {[info exists commentchar]} {
        lappend dialect -comment $commentchar
    }
    if {[info exists doublequote]} {
        lappend dialect -doublequote 1
    } else {
        if {[info exists escape]} {
            lappend dialect -escape $escape
        }
    }


    return $dialect
}

proc tclcsv::sniff_header {args} {
    if {[llength $args] == 0} {
        error "wrong # args: should be \"sniff_header ?options? channel\""
    }
    set chan [lindex $args end]

    set seek_pos [chan tell $chan]
    if {$seek_pos == -1} {
        error "Channel is not seekable"
    }

    try {
        set rows [csv_read {*}[lrange $args 0 end-1] -nrows 100 $chan]
        if {[llength $rows] < 2} {
            error "Insufficient rows in CSV data to sniff headers."
        }
        set width [llength [lindex $rows 0]]
        set types {}
        for {set findex 0} {$findex < $width} {incr findex} {
            dict set types $findex type unknown
            dict set types $findex length [string length [lindex $rows 1 $findex]]
        }
        foreach row [lrange $rows 1 end] {
            if {[llength $row] != $width} continue
            for {set findex 0} {$findex < $width} {incr findex} {
                set val [lindex $row $findex]
                if {[string length $val] != [dict get $types $findex length]} {
                    dict set types $findex length -1
                }
                set field_type [dict get $types $findex type]
                if {$field_type eq "string"} continue
                # Note values starting with 0 treated as strings (eg. zip codes)
                # Exceptions are 0 and 0.something
                if {[string index $val 0] eq "0" &&
                    [string length $val] > 1 &&
                    [string index $val 1] ne "."} {
                    dict set types $findex type string
                    continue
                }
                if {$field_type eq "real"} {
                    if {![string is double -strict $val]} {
                        dict set types $findex type string
                    }
                    continue
                }
                # field_type is integer or unknown. Our check for
                # integer is not [string is wide] because we want to
                # treat as decimal numbers and not parse as octals or hex
                if {[regexp {^\d+$} $val]} {
                    dict set types $findex type integer
                } elseif {[string is double -strict $val]} {
                    dict set types $findex type real
                } else {
                    dict set types $findex type string
                }
            }
        }
    } finally {
        chan seek $chan $seek_pos
    }

    # If we could determine that any one column was a non-string type
    # (integer or real) but the header field for that column is not
    # of that type, we immediately conclude the first row is a header.
    # In addition, in the case of columns that are of fixed width,
    # we take a vote, where every time the field in first row of the
    # fixed width column is of a different width we raise the probability
    # of header existence and if of the same width, we lower the probability.
    set probably_header 0
    set row [lindex $rows 0]
    for {set findex 0} {$findex < $width} {incr findex} {
        set field [lindex $row $findex]
        set type [dict get $types $findex type]
        if {($type eq "integer" && ![string is wide -strict $field]) ||
            ($type eq "real" && ![string is double -strict $field])
        } {
            # The type of the first row field is different. Assume header
            set probably_header 1
            break
        }
        set len [dict get $types $findex length]
        if {$len >= 0} {
            if {$len == [string length $field]} {
                incr probably_header -1
            } else {
                incr probably_header 1
            }
        }
    }

    set field_types {}
    for {set findex 0} {$findex < $width} {incr findex} {
        set type [dict get $types $findex type]
        # $type can be unknown if the loop above did a continue right
        # at the top for every line
        if {$type eq "unknown"} {
            set type string
        }
        lappend field_types $type
    }

    if {$probably_header > 0} {
        return [list $field_types $row]
    } else {
        return [list $field_types]
    }
}

proc tclcsv::dialect {dialect {direction read}} {
    variable dialects
    set dialects [dict create]
    dict set dialects excel [list \
                                 -delimiter , \
                                 -quote \" \
                                 -doublequote 1 \
                                 -skipleadingspace 0]
    dict set dialects excel-tab [dict merge [dict get $dialects excel] [list -delimiter \t]]
    proc [namespace current]::dialect {dialect {direction read}} {
        variable dialects
        set opts [dict get $dialects $dialect]
        if {$direction eq "write"} {
            # Remove options not understood by writes
            dict unset opts -skipleadingspace
        }
        return $opts
    }
    return [dialect $dialect $direction]
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

proc tclcsv::dialectpicker args {
    variable script_dir
    uplevel #0 {package require Tk; package require snit}
    uplevel #0 [list source [file join $script_dir widgets.tcl]]
    uplevel 1 tclcsv::dialectpicker $args
}

namespace eval tclcsv {
    namespace export csv_read csv_write sniff sniff_header dialect
}
