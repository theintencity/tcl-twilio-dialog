#!/usr/bin/env tclsh

lappend auto_path .
package require dialog

Dialog {
  <<< Where do you want to travel to?
  >>> "Edinburgh | New York | London | Paris | Stockholm" {
    set city ${:input:}
    <<< How many are traveling to ${city}?
    }\
  >>> "1 | 2 | 3 | 4 | 5" {
    set cities [list Edinburgh New\ York London Paris Stockholm]
    set city [lindex $cities [expr ${:input:} - 1]]
    <<< How many people will go to $city?
    }\
  >>> else {
    if {[regexp {^\d+$} ${:input:}]} {
      <<< Your number was out of range
    } else {
    <<< We do not have route to ${:input:}
    }
    }
}
