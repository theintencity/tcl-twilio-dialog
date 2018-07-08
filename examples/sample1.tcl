#!/usr/bin/env tclsh

lappend auto_path .
package require dialog

proc get_videocall {} {
  return https://some-tiny-url
}
proc send_message msg {
  
}

Dialog {
  <<< Hello and welcome to our new customer service line.
  <<< Please say sales or support, or press 1 for sales, and press 2 for support.
  >>> "sales | 1" {
    <<< Let me connect you to sales.
    dial +12121234567 }\
  >>> "support | 2" {
    <<< Would you like to connect via video call?
    >>> "yes | 1" {
      set url [get_videocall]
      message "Click here $url"
      <<< I sent you a link to join. Good bye! }\
    >>> else {
      <<< Let me connect you to support.
      
      if {[catch {dial +14151234567}]} {
        <<< Our agents are assisting other customers.
        <<< Would you like to leave a voice message instead?
        >>> "yes | 1" {
          set file [record maxLength=120]
          send_message "New voice message at $file"
          <<< Your voice message has been recorded. We will get back to you shortly. }\
        >>> else {
          <<< Please enter your 4 digit PIN
          >>> input
          <<< Let me put you on hold for the next available agent
          enqueue "customer-$input"
        }
      }
    }
  }  
}
