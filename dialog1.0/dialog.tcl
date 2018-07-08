##################################################
#
# dialog.tcl - Create voice and message dialogs for Twilio.
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

set _dialog(buffer) ""
set _dialog(started) 0
set _dialog(logger) 1

if {$argc >= 1} {
    
    set _dialog(dir) [lindex $argv 0]
    set _dialog(type) [lindex [split [file tail $_dialog(dir)] .] 0]
    
    proc Dialog cmd {
        global _dialog
        
        set _dialog(started) 1
    
        rename puts puts_old
        rename gets gets_old
        
        set _dialog(buffer) ""
        set _dialog(gather_args) ""
        set _dialog(say_args) ""
        set _dialog(params) ""
        
        proc _unquote_input buf {
            set buf [string map -nocase [list + { } "\\" "\\\\" %0d%0a \n] $buf]
            regsub -all -nocase {%([a-f0-9][a-f0-9])} $buf {\\u00\1} buf
            encoding convertfrom "utf-8" [subst -novar -nocommand $buf]
        }
        
        proc _gets_onreadable {in} {
            global _dialog
            if {![eof $in]} {
                append _dialog(input) [gets_old $in]
            }
            set _dialog(readdone) 1
        }
        
        proc _gets_ontimeout {in} {
            global _dialog
            set _dialog(readdone) 1
        }
        
        proc _gets_params {type} {
            global _dialog
            set _dialog(input) ""
            set _dialog(readtype) $type

            if {$type eq "init"} {
                set in [open "$_dialog(dir)/in" r]
                set _dialog(input) [read $in]
            } else {
                set _dialog(readtimeout) 14400000
                set in [open "$_dialog(dir)/in" {RDONLY NONBLOCK}]
                fconfigure $in -blocking 0
                set _dialog(readdone) 0
                fileevent $in readable [list _gets_onreadable $in]
                after $_dialog(readtimeout) [list _gets_ontimeout $in]
                vwait _dialog(readdone)
            }

            close $in
            
            if {$_dialog(input) eq ""} {
                catch {file delete "$_dialog(dir)/pid"}
                catch {file delete "$_dialog(dir)/in"}
                catch {file delete "$_dialog(dir)/out"}
                
                set _dialog(started) 0
                exit
            }
            
            set pairs [split $_dialog(input) &]
            set params [dict create]
            foreach pair $pairs {
                if {0 == [regexp "^(\[^=]*)=(.*)$" $pair dummy varname val]} {
                    set varname anonymous
                    set val $pair
                }
        
                set varname [_unquote_input $varname]
                set val [_unquote_input $val]
                dict set params $varname $val
            }
            
            return $params
        }

        proc _puts_response {} {
            global _dialog
            set response [_stringify $_dialog(buffer)]
            if {$response ne ""} {
                set response "<Response>$response</Response>"
            } else {
                set response "<Response><Hangup/></Response>"
            }
            set out [open "$_dialog(dir)/out" w]
            puts $out $response
            close $out
        }

        
        set _dialog(params) [_gets_params init]
        uplevel 1 [list set :params: $_dialog(params)]

        # see https://stackoverflow.com/questions/43230250/replacing-special-characters-with-html-entities-in-tcl-script
        set _dialog(html_mapping) {{"} &quot; ' &apos; & &amp; < &lt; > &gt;}
    
        proc _stringify {buffer} {
            global _dialog
            if {[llength $buffer] == 0} { return ""}
            set result [list]
            foreach item $buffer {
                set tag [lindex $item 0]
                set attrs [list]
                foreach a [lrange $item 1 end] {
                    if {[regexp "^(\[a-zA-Z0-9_\-]*)=(.*)" $a dummy attr str]} {
                        set str [string map $_dialog(html_mapping) $str]
                        lappend attrs "$attr=\"$str\""
                    }
                }
                set body {}
                if {[llength $item] > 1} {
                    set body [lindex $item end]
                }
                
                if {[regexp "^(\[a-zA-Z0-9_\-]*)=(.*)" $body dummy attr str]} {
                    set body ""
                }
                if {[llength $attrs] > 0} {
                    set attrs " [join $attrs { }]"
                }
            
                if {$body ne ""} {
                    if {$tag eq "Gather" || $tag eq "Message" || $tag eq "Dial"} {
                        set body [_stringify $body]
                    } elseif {[string range $body 0 8] ne {<![CDATA[} } {
                        set body [string map $_dialog(html_mapping) $body]
                    }
                    lappend result "<$tag$attrs>$body</$tag>"
                } else {
                    lappend result "<$tag$attrs/>"
                }
            }
            return [join $result ""]
        }
        
        proc logger msg {
            global _dialog
            uplevel 1 hangup
            if {$_dialog(logger)} {
                lappend _dialog(buffer) [list "Log" "<!\[CDATA\[$msg\]\]>"]
            }
        }
        
        proc _generic_verb {name args} {
            global _dialog
            lappend _dialog(buffer) [list $name {*}$args]
        }
        
        proc message args {
            global _dialog
            set item [list "Message"]
            set lastitem {}
            for {set c 0} {$c < [llength $args]} {incr c} {
                set arg [lindex $args $c]
                if {$arg eq "-body"} {
                    incr c
                    set index [llength $_dialog(buffer)]
                    uplevel 1 [lindex $args $c]
                    set subitem [lrange $_dialog(buffer) $index end]
                    set _dialog(buffer) [lrange $_dialog(buffer) 0 [expr $index - 1]]
                    set lastitem $subitem
                } else {
                    if {[regexp "^(\[a-zA-Z0-9_\-]*)=(.*)" $arg dummy attr str]} {
                        lappend item $arg
                    } else {
                        set lastitem [list [list "Body" $arg]]
                    }
                }
            }
            if {$lastitem ne ""} {
                lappend item $lastitem
            }
            lappend _dialog(buffer) $item
        }
        
        if {$_dialog(type) eq "Message"} {
            proc puts args {
                if {[lindex $args 0] == "-nonewline" && [llength $args] == 2 
                    || [lindex $args 0] != "-nonewline" && [llength $args] == 1} {
                    global _dialog
                    set item [list "Message" [list [list "Body" [lindex $args end]]]]
                    lappend _dialog(buffer) $item
                } else {
                    uplevel 1 "puts_old $args"
                }
            }
            
            proc gets args {
                if {[llength $args] > 0 && [lindex $args 0] == "stdin"} {
                    global _dialog
                    
                    _puts_response
                    
                    set _dialog(buffer) ""
                    set input [_gets_params message]
                    uplevel 1 [list set :params: $input]
                    
                    if {[dict exists $input Body]} {
                        set input [string trim [dict get $input Body]]
                    } else {
                        set input ""
                    }
                    
                    if {[llength $args] > 1} {
                        upvar [lindex $args 1] input_
                        set input_ $input
                        return [string length $input]
                    } else {
                        return $input
                    }
                } else {
                    uplevel 1 "gets_old $args"
                }
            }

            foreach name {Redirect Body Media} {
                proc [string tolower $name] args \
                    _generic_verb\ $name\ {*}\$args
            }
        } else {
            proc puts args {
                if {[lindex $args 0] == "-nonewline" && [llength $args] == 2 
                    || [lindex $args 0] != "-nonewline" && [llength $args] == 1} {
                    global _dialog
                    set params $_dialog(say_args)
                    lappend _dialog(buffer) [list Say {*}$params [lindex $args end]]
                } else {
                    uplevel 1 "puts_old $args"
                }
            }
            
            proc say_attrs args {
                global _dialog
                set _dialog(say_args) $args
            }
            
            proc gather_attrs args {
                global _dialog
                set _dialog(gather_args) $args
            }
            
            proc _append_gather {} {
                global _dialog
                set params $_dialog(gather_args)
                lappend params "action={{script}}"
                if {[llength $_dialog(buffer)] > 0} {
                    set last [lindex $_dialog(buffer) end]
                } else {
                    set last ""
                }
                if {[lindex $last 0] eq "Say"} {
                    set length [llength $_dialog(buffer)]
                    set _dialog(buffer) [lreplace $_dialog(buffer) [expr $length-1] end]
                    lappend _dialog(buffer) [list "Gather" {*}$params [list $last]]
                } else {
                    lappend _dialog(buffer) [list "Gather" {*}$params [list]]
                }
                lappend _dialog(buffer) [list "Redirect" "{{script}}"]
            }
            
            proc gets args {
                if {[llength $args] > 0 && [lindex $args 0] == "stdin"} {
                    global _dialog
                    
                    _append_gather
                    _puts_response
                    
                    set _dialog(buffer) ""
                    set input [_gets_params gather]
                    uplevel 1 [list set :params: $input]
                    
                    if {[dict exists $input Digits]} {
                        set input [string trim [dict get $input Digits]]
                    } elseif {[dict exists $input SpeechResult]} {
                        set input [string trim [dict get $input SpeechResult]]
                    } else {
                        return -code error "timeout"
                    }
                    
                    if {[llength $args] > 1} {
                        upvar [lindex $args 1] digits_
                        set digits_ $input
                        return [string length $input]
                    } else {
                        return $input
                    }
                } else {
                    uplevel 1 "gets_old $args"
                }
            }
            
            proc _append_dial args {
                global _dialog
                set item [list "Dial" "action={{script}}"]
                set lastitem {}
                for {set c 0} {$c < [llength $args]} {incr c} {
                    set arg [lindex $args $c]
                    if {$arg eq "-body"} {
                        incr c
                        set index [llength $_dialog(buffer)]
                        uplevel 1 [lindex $args $c]
                        set subitem [lrange $_dialog(buffer) $index end]
                        set _dialog(buffer) [lrange $_dialog(buffer) 0 [expr $index - 1]]
                        set lastitem $subitem
                    } else {
                        if {[regexp "^(\[a-zA-Z0-9_\-]*)=(.*)" $arg dummy attr str]} {
                            lappend item $arg
                        } else {
                            set lastitem [list [_get_number_value $arg]]
                        }
                    }
                }
                if {$lastitem ne ""} {
                    lappend item $lastitem
                }
                lappend _dialog(buffer) $item
            }
            
            proc dial args {
                global _dialog
    
                _append_dial {*}$args
                _puts_response
                
                set _dialog(buffer) ""
                set input [_gets_params dial]
                uplevel 1 [list set :params: $input]
                
                if {[dict exists $input DialCallStatus]} {
                    set input [string trim [dict get $input DialCallStatus]]
                } else {
                    set input "invalid"
                }
                if {$input eq "completed" || $input eq "answered"} {
                    return 0
                } else {
                    return -code error "$input"
                }
            }
            
            proc _append_record args {
                global _dialog
                lappend _dialog(buffer) [list "Record" "action={{script}}" {*}$args]
                lappend _dialog(buffer) [list "Redirect" "{{script}}"]
            }
            
            proc record args {
                global _dialog
    
                _append_record {*}$args
                _puts_response
                
                set _dialog(buffer) ""
                set input [_gets_params record]
                uplevel 1 [list set :params: $input]
                
                if {[dict exists $input RecordingUrl]} {
                    return [string trim [dict get $input RecordingUrl]]
                } else {
                    return -code error "failed"
                }
            }
            
            proc _get_number_value args {
                if {[llength $args] == 1} {
                    if {[regexp -- {^([\+0-9\-\(\)\s]+)(,[,0-9\*\#]*)$} [lindex $args 0] match base extension]} {
                        puts_old stderr "matched $base $extension"
                        set extension [regsub -all -- {,} $extension w]
                        set args [list sendDigits=$extension $base]
                    }
                }
                return [list Number {*}$args]
            }
            
            proc number args {
                global _dialog
                lappend _dialog(buffer) [_get_number {*}$args]
            }
            
            foreach name {Play Pause Reject Leave Hangup Enqueue Redirect
                          Client Conference Queue Sim Sip Body Media} {
                proc [string tolower $name] args \
                    _generic_verb\ $name\ {*}\$args
            }
        }
        
        _define_aliases
        
        set _dialog(body) $cmd
        
        uplevel 1 {
            if {1==[catch $_dialog(body) errMsg]} {
                puts_old stderr $errorInfo
                
                set _dialog(buffer) ""
                puts "There was an error in generating the page."
                puts "$errMsg"
                logger $errorInfo
            }
        }
      
        rename puts ""
        rename puts_old puts
        rename gets ""
        rename gets_old gets
        
        _puts_response

        catch {after 1000}
        catch {file delete "$_dialog(dir)/pid"}
        catch {file delete "$_dialog(dir)/in"}
        catch {file delete "$_dialog(dir)/out"}
        
        set _dialog(started) 0
        
    }
    
} else {

    proc Dialog cmd {
        global _dialog
        
        set _dialog(started) 1
    
        uplevel 1 [list set :params: [dict create]]
        
        rename puts puts_old
        rename gets gets_old
        
        # see https://rosettacode.org/wiki/Check_input_device_is_a_terminal#Tcl
        proc _is_terminal arg {
            if {[catch {fconfigure $arg -mode}]} {
                return 0
            } else {
                return 1
            }
        }

        proc puts args {
            set term [_is_terminal stdout]
            if {$term && [lindex $args 0] == "-nonewline" && [llength $args] == 2} {
                puts_old -nonewline "<<< [lindex $args end]"
            } elseif {$term && [lindex $args 0] != "-nonewline" && [llength $args] == 1} {
                puts_old "<<< [lindex $args end]"
            } else {
                uplevel 1 "puts_old $args"
            }
        }
        
        proc gets args {
            if {[_is_terminal stdin] && [llength $args] >= 1 && [lindex $args 0] eq "stdin"} {
                puts_old -nonewline ">>> "
                flush stdout
            }
            uplevel 1 "gets_old $args"
        }
        
        proc say_attrs args { }
        
        proc gather_attrs args { }
        
        proc _generic_verb {name args} {
            set _prompt 0
            if {[llength $args] >= 1 && [lindex $args 0] eq "-prompt"} {
                set _prompt 1
                set args [lrange $args 1 end]
            }
            if {$_prompt} {
                puts_old -nonewline "... $name $args \[Y/n\]? "
                flush stdout
                set input [gets_old stdin]
                if {$input eq "" || $input eq "Y"} {
                    return 0
                }
                return -code error "$name failed"
            } else {
                puts_old "... $name $args"
            }
        }
        
        foreach name {Dial Record} {
            set name [string tolower $name]
            proc $name args \
                _generic_verb\ $name\ -prompt\ {*}\$args
        }
        
        foreach name {Message Play Pause Reject Leave Hangup Enqueue
                      Client Conference Number Queue Sim Sip Body Media} {
            set name [string tolower $name]
            proc $name args \
                _generic_verb\ $name\ {*}\$args
        }
        
        _define_aliases
        
        set _dialog(body) $cmd
        
        uplevel 1 {
            if {1==[catch $_dialog(body)]} {
                puts_old stderr $errorInfo
            }
        }
      
        rename puts ""
        rename puts_old puts
        rename gets ""
        rename gets_old gets
        
        set _dialog(started) 0
    }
}

proc _define_aliases {} {
    
    proc <<< args {
        uplevel 1 [list puts [join $args " "]]
    }
    
    proc >>> args {
        global _dialog
        
        variable input
        set varname ""
        set input ""
        set hints ""
        set digits ""
        set code ""
        for {set c 0} {$c < [llength $args]} {incr c} {
            set arg [lindex $args $c]
            if {$arg eq ">>>"} { continue }
            if {$c < [expr [llength $args] - 1]} {
                if {$arg eq "else"} {
                    incr c
                    lappend code " {[lindex $args $c]}"
                } else {
                    set parts [split $arg |]
                    set items {}
                    foreach part $parts {
                        set part [string trim $part]
                        if {$part ne ""} {
                            if {[regexp -- {^\d+$} $part]} {
                                lappend digits $part
                                lappend items "\$input eq \"$part\""
                            } else {
                                if {[regexp {\*} $part]} {
                                    lappend hints [regsub {[\*\?]} $part " "]
                                    lappend items "\[string match -nocase \"$part\" \"\$input\"\]"
                                } else {
                                    lappend hints $part
                                    lappend items "\[string tolower \$input\] eq \[string tolower \"$part\"\]"
                                }
                            }
                        }
                    }
                    incr c
                    lappend code "if {[join $items { || }]} {[lindex $args $c]} else"
                }
            } else {
                set varname $arg
            }
        }
        set code [join $code {}]
        if {$code ne "" && [string range $code end-4 end] eq " else"} {
            set code [string range $code 0 end-5]
        }
        
        if {![info exists _dialog(type)] || $_dialog(type) eq "Call"} {
            if {[llength $digits] > 0 || [llength $hints] > 0} {
                set items {}
                if {[llength $digits] > 0} {
                    lappend input "dtmf"
                    set max 0
                    foreach digit $digits {
                        if {$max < [string length $digit]} {
                            set max [string length $digit]
                        }
                    }
                    if {$max > 0} {
                        lappend items "numDigits=$max"
                    }
                }
                if {[llength $hints] > 0} {
                    lappend input "speech"
                    lappend items "hints=[join $hints ,]"
                }
                set input [join $input " "]
                lappend items "input=$input"
                uplevel 1 [list gather_attrs {*}$items]
            } else {
                uplevel 1 [list gather_attrs]
            }
        }
        
        set input [uplevel 1 [list gets stdin]]
        if {$varname ne ""} {
            upvar 1 $varname _input
            set _input $input
        }
        if {$code ne ""} {
            uplevel 1 [list set {:input:} $input]
            uplevel 1 "$code\n"
            catch {uplevel 1 [list unset {:input:}]}
        }
    }
    
    proc (raw) cmd {
        uplevel 1 {
            rename puts puts_new
            rename gets gets_new
            rename puts_old puts
            rename gets_old gets
        }
        uplevel 1 $cmd
        uplevel 1 {
            rename puts puts_old
            rename gets gets_old
            rename puts_new puts
            rename gets_new gets
        }
    }
}

# TODO:
# use ?r= for GET requests.
# dial with optional screening script [dial number { <<< You are now connected to the caller }
# allow linking outbound calls to Dialog. What about other rest api?
# add voicexml dialog too.
# disable verbs/nouns commands that are not applicable in a context.
