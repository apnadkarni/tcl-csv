package require tcltest 2.2

# Test configuration options that may be set are:
# (currently none)

tcltest::configure -testdir [file dirname [file normalize [info script]]]
if {[info exists env(TEMP)]} {
    tcltest::configure -tmpdir $::env(TEMP)/tclcsv-test/[clock seconds]
} else {
    if {[file exists /tmp] && [file isdirectory /tmp]} {
	tcltest::configure -tmpdir /tmp/tclcsv-test/[clock seconds]
    } else {
	error "Unable to figure out TEMP directory. Please set the TEMP env var"
    }
}

eval tcltest::configure $argv
tcltest::runAllTests
puts "All done."
