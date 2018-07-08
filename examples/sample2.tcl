#!/usr/bin/env tclsh

lappend auto_path .
package require dialog

proc get_videocall {} {
    return http://some-link
}
Dialog {
  <<< Hello and welcome to our new customer service line.
  <<< Please type sales or support, or something else.
  >>> "*sales*" {
    <<< Let me connect you to sales. }\
  >>> "*support*" {
    <<< Would you like to connect via video call?
    >>> "yes" {
      (raw) {
        puts "this is cool"
      }
      set url [get_videocall]
      <<< Click here $url }\
    >>> else {
      <<< Let me connect you to support. }
    }  
}
