#!/usr/bin/env tclsh
##################################################
#
# webserver.tcl - Simple insecure webserver with CGI..
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


# see http://wiki.tcl.tk/11017, http://wiki.tcl.tk/4333, http://wiki.tcl.tk/16867 and http://wiki.tcl.tk/15244

set port 8000
if {$argc > 0} { set port [lindex $argv 0]}
 
proc bgerror msg {puts stdout "bgerror: $msg\n$::errorInfo"}

proc answer {sock ip port} {
    fconfigure $sock -translation lf -buffering line
    set line [string trim [gets $sock]]
    if {$line eq ""} { return }
    regexp {(\w+)\s(/[^ ?]*)(\?[^ ]*)?} $line -> method path query
    if {![info exists method] || ![info exists path]} { error "Missing method or path: $line"}
    if {[string match */ $path]} {append path index.html}
    set filename [string map {%20 " "} ".$path"]

    set headers {}
    set length 0
    set content_type ""
    
    for {set c 0} {[gets $sock temp]>=0 && $temp ne "\r" && $temp ne ""} {incr c} {
        regexp {^([^:]+)\s*:\s*([^\r\n]+)$} [string trim $temp] -- name value
        lappend headers [list $name $value]
        if {[string tolower $name] eq "content-length"} { set length $value}
        if {[string tolower $name] eq "content-type"} { set content_type $value}
        if {$c == 100} { error "Too many lines from $ip" }
    }
    
    if {$length > 0} { set body [read $sock $length] } else { set body "" }
    
    if {[file readable $filename] && [file isfile $filename]} {
        set ext [file extension $filename]
        if {($ext eq ".cgi" || $ext eq ".tcl") || $method eq "GET"} {
            set type "text/plain"
            if {($ext eq ".cgi" || $ext eq ".tcl")} {
                set ::env(REQUEST_METHOD) $method
                set ::env(QUERY_STRING) [string range $query 1 end]
    			set ::env(SCRIPT_NAME) $filename
                set ::env(REMOTE_ADDR) $ip
    
                set filename [list |tclsh $filename]
                if {$method eq "POST" && $body ne ""} {
                    if {$content_type ne ""} {
                        set ::env(CONTENT_TYPE) $content_type
                    }
                    set ::env(CONTENT_LENGTH) [string bytelength $body]
                    set fin [open $filename r+]
                    puts -nonewline $fin $body
                    flush $fin
                } else {
                    set ::env(CONTENT_LENGTH) 0
                    set fin [open $filename r+]
                }
                set response [read $fin]
                regexp {^Content-Type:\s*([^\r\n]+)\r?\n\r?\n(.*)$} $response -- type response
            } else {
                set fin [open $filename]
                set response [read $fin]
            }
            close $fin
            
            set response_length [string bytelength $response]
            puts $sock "HTTP/1.0 200 OK"
            puts $sock "Content-Type: $type"
            puts $sock "Content-Length: $response_length\n"
            puts -nonewline $sock $response
            
            puts "$method $path$query -- 200 - $content_type [string length $body] $type $response_length"
            if {$length > 0} {
                puts "Request: $body"
            }
            if {$response_length > 0} {
                puts "Response: $response"
            }
        } else {
            puts $sock "HTTP/1.0 405 Method not allowed\n"
            puts "$method $path$query -- 405 Method not allowed"
        }
    } else {
        puts $sock "HTTP/1.0 404 Not found\n"
        puts "$method $path$query -- 404 Not found"
    }
    close $sock
}

socket -server answer $port
puts "server on port $port"
vwait forever

