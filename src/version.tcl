namespace eval tclcsv {
    proc version {} {return 2.2.0}
    # Print version if this file is the main script. Used during builds.
    # If sourced inside a safe interp argv0 will not exist so check for that
    # as well.
    if {[info exists ::argv0] &&
        [file tail [info script]] eq [file tail [lindex $::argv0 0]]} {
        puts [version]
    }
}
return [tclcsv::version]
