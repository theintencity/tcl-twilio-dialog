#!/usr/bin/env tclsh
##################################################
#
# dialog.cgi - Master cgi script to interface with dialog coroutine script.
#
# Author: Kundan Singh <theintencity@gmail.com> 2018
#
####### MIT LICENSE ##############################
# Copyright 2018, Kundan Singh <kundan10@gmail.com>
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the "Software"),
# to deal in the Software without restriction, including without limitation
# the rights to use, copy, modify, merge, publish, distribute, sublicense,
# and/or sell copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included
# in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
# OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
# THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR
# OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
# ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
# OTHER DEALINGS IN THE SOFTWARE.
##################################################


lappend auto_path .
package require base64
package require http
package require tls
package require cgi

set _dialog(logger) 1

cgi_eval {
    if {$argc > 0} {
        cgi_input [join $argv "&"]
    } else {
        cgi_input
    }
    
    puts "Content-Type: text/xml\n"
    puts "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
    
    if {[catch {
        if {[catch {cgi_import AccountSid}]} {
            error "missing AccountSid"
        }
        if {![catch {cgi_import CallSid}]} {
            if {[catch {cgi_import Dialog}]} {
                set Dialog examples/sample1.tcl
            }
            set dirname "Call.$AccountSid.$CallSid.[regsub -all {[^a-zA-Z0-9\_\-]} $Dialog - ]"
        } elseif {![catch {cgi_import MessageSid}]} {
            if {[catch {cgi_import Dialog}]} {
                set Dialog examples/sample2.tcl
            }
            cgi_import From
            cgi_import To
            set dirname "Message.$AccountSid.[regsub -all {[^a-zA-Z0-9]} $From {}]-[regsub -all {[^a-zA-Z0-9]} $To {}].[regsub -all {[^a-zA-Z0-9\_\-]} $Dialog - ]"
        } else {
            error "missing MessageSid and CallSid"
        }
        
        set dir "/tmp/dialogs/$dirname"
        if {![file exists $dir]} {
            file mkdir $dir
        }
        if {![file exists "$dir/pid"]} {
            if {![file exists "$dir/in"]} {
                exec mkfifo "$dir/in"
            }
            if {![file exists "$dir/out"]} {
                exec mkfifo "$dir/out"
            }
            set id [exec tclsh "$Dialog" "$dir" >>& "$dir/log" &]
            set fid [open "$dir/pid" w]
            puts $fid $id
        }
        
        set in [open "$dir/in" w]
        global _cgi
        puts $in "$_cgi(input)"
        close $in
        
        set out [open "$dir/out" r]
        set response ""
        while 1 {
            set line [gets $out]
            if {$line ne ""} {
                append response "$line\n"
            }
            if {$line eq "" || [string range $line end-10 end] eq "</Response>"} {
                break
            }
        }
        close $out
        
        set script [regsub -- {^\./} "$::argv0?Dialog=$Dialog" {}]
        # set script "?Dialog=$Dialog"
        set response [regsub -all -- "{{script}}" $response $script]
        puts [string trim $response]
    } err]} {
        global errorInfo _dialog
        if {$_dialog(logger)} {
            set logged "<Log><!\[CDATA\[$errorInfo\]\]</Log>"
        } else {
            set logged ""
        }
        puts "<Response><Say>An error occured in processing your request.</Say><Hangup/>$logged</Response>"
    }
}
