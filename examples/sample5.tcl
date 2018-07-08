#!/usr/bin/env tclsh

lappend auto_path .
package require dialog

Dialog {
  <<< How many people are travelling?
  if {[catch {gets stdin count}]} {
    <<< Please tell me the number of people travelling.
    if {[catch {gets stdin count}]} {
      <<< To book a flight, you must tell me the number of people travelling.
      if {[catch {gets stdin count}]} {
        <<< I cannot continue without your input.
      }
    }
  }
  set numbers [dict create one 1 two 2 three 3 four 4 five 5 six 6 seven 7 eight 8 nine 9 ten 10]
  if {[dict exists $numbers $count]} {
    set count [dict get $numbers $count]
  }
  
  if {[info exists count]} {
    if {![string is integer $count]} {
      <<< Please just say a number.
    } else {
      if {$count > 4} {
        <<< Sorry, I can only book up to four people
      } else {
        <<< Great! Let us get started for $count people travelling.
      }
    }
  } else {
    <<< Good bye!
  }
}
