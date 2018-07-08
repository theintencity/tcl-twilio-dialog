#!/usr/bin/env tclsh

lappend auto_path .
package require dialog

Dialog {
  set caller [dict get ${:params:} From]
  set receiver [dict get ${:params:} To]
  
  <<< Welcome to travel planner!
  set loop 1
  while {$loop} {
    <<< Please say one of sports, weather or news.
    >>> "sports" {
      <<< Tune in to channel 47 for sports
      set loop 0 }\
    >>> "weather" {
      <<< What is your ZIP code?
      >>> zipcode
      message to=$caller from=$receiver Check the weather at http://myweather/?$zipcode
      <<< I sent you a message with a link to check weather
      set loop 0 }\
    >>> "news" {
      <<< We are sorry, our news channel is out of service
      set loop 0 }\
    >>> else {
      <<< I did not understand that word }
  }
}
