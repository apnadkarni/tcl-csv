namespace eval tclcsv {
    proc version {} {return 2.2.0}
}
# Print version if this file is the main script. Used during builds.
if {[file tail [info script]] eq [file tail [lindex $argv0 0]]} {
    puts [tclcsv::version]
}
return [tclcsv::version]
