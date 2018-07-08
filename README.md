# Writing coherent dialogs using Twilio

This article shows the complexity of writing a multistep interactive voice
dialog for cloud telephony. It presents our `dialog` package to create such a dialog as a
single and simple coherent script in Tcl. The script performs programmed interactive voice or
messaging interaction using the popular cloud telephony platform, Twilio.

It should also work, after trivial modifications,
with other similar systems such as Restcomm or Somleng
that use TwiML or similar markups.
The package can further be extended to support other
popular dialog languages such as VoiceXML. The core idea can be re-implemented
using other scripting languages such as Python.

A multistep dialog is illustrated below. It is in pseudo-code. It uses
indentation to determine the scope of a code block. The example is very easy to understand,
and quite coherent.

**Exhibit 1**
```
<<< Hello and welcome to our customer service phone line.
<<< Please say sales or support, or press 1 for sales, and press 2 for support.
>>> sales | 1
  <<< Let me connect you to sales
  dial +12121234567
>>> support | 2
  <<< Would you like to connect via video call?
  >>> yes | 1
    message Click here [... some video call link ...]
    <<< I sent you a link to join. Good bye!
  >>> anything else
    <<< Let me connect you to support.
      dial +14151234567
      if failed
        <<< Our agents are assisting other customers.
        <<< Would you like to leave a voice message instead?
        >>> yes | 1
          record for up to 2 minutes
          store the recorded file at the server
          <<< Your voice message has been recorded. We will get back to you shortly.
        >>> anything else
          <<< Please enter your four digit PIN
          >>> store digits in input
          <<< Let me put you on hold for the next available agent
          enqueue the call to queue name based on input
```
This article describes how to create such dialogs that
 1. are coherent (and linearly specified) and can be placed in a single file;
 2. can include voice and messaging interactions as well as call control functions;
 3. have the full arsenal of scripting language libraries and tools.

<br/>Our project contains a domain specific language package in Tcl for writing interactive
voice and messaging dialogs. The software presented with this article is available
at [http://github.com/theintencity/tcl-twilio-dialog](http://github.com/theintencity/tcl-twilio-dialog).

### Motivation

#### How are VoiceXML and TwiML different?

Both W3C's VoiceXML and Twilio's TwiML aim to facilitate interactive voice
dialogs. However, there are fundamental differences:

| Property | VoiceXML | TwiML |
|-----|-----|-----|
| Logic in XML vs. server side script | Application logic can reside in the XML page. Control can flow within the single coherent page containing multiple user inputs, several prompts, and bunch of processing scripts. | Server driven business logic spits out small chunks of XML (TwiML) at each step. The state of the dialog remains at the server. It often requires carefully crafted control flow from one script to another. |
| Call control | Requires external system, e.g., CCXML, to enable call control features.| Some are built into XML, and others can be invoked from server side scripts. |
| Programming language | Needs good understanding of VoiceXML, ECMAScript and peculiarities of VoiceXML to be able to program. | Simple XML of TwiML, supported by SDKs and libraries in several popular programming languages. Easier to program by web developers. |

A single coherent dialog file is possible and desirable in a VoiceXML application.
However, many practical applications regularly need server side scripts to interface with domain
specific services. On the TwiML side, right orchestration of control flow from one server script
to another is not trivial. Tools such as Twilio Studio can mitigate the problem for
non-programmers, but take away the flexibility and leverage of a full scripting language.

#### How complex is this dialog implementation in TwiML?

To illustrate the complexity let us try to implement the dialog of exhibit 1 using Twilio and TwiML.
For that, we will need several steps in our dialog orchestration, and roughly one TwiML
page per step.

 > If you are familiar with TwiML, or can already imagine the different TwiML pages
 > needed to implement the above dialog example, you may skip this section.
 

<br/>When the caller calls, the first TwiML for initial greetings is shown below.
This may be a static XML file, or dynamically generated via a script; it does not matter.
```XML
<Response>
  <Say>Hello and welcome to our new customer service line.</Say>
  <Gather maxDigits="1" input="dtmf speech" hints="sales, support" action="second">
    <Say>Please say sales or support, or press 1 for sales,
    and press 2 for support.</Say>
  </Gather>
</Response>
```
When the caller presses 1, the `second` script generates the following TwiML.
```XML
<Response>
  <Say>Let me connect you to sales.</Say>
  <Dial>
    <Number>+12121234567</Number>
  </Dial>
</Response>
```
And if the caller presses 2 instead, the `second` script generates this,
```XML
<Response>
  <Gather maxDigits="1" input="dtmf speech" hints="yes" action="third">
    <Say>Would you like to connect via video call?</Say>
  </Gather>
</Response>
```
If the caller now says "yes", the `third` script gets a click-to-join URL with
video support using some backend service, informs the support person using
some out-of-band or third-party video call system, and finally, generates the following TwiML.
```XML
<Response>
  <Message>Click here https://some-tiny-url</Message>
  <Say>I sent you a link to join. Good bye!</Say>
</Response>
```
This sends the clickable link as SMS to the caller, and terminates the call after informing her
about it.

On the other hand, if the caller says "no" or something else, the `third` script
generates the following TwiML.
```XML
<Response>
  <Say>Let me connect you to support.</Say>
  <Dial><Number>+14151234567</Number></Dial>
</Response>
```
At this time, if the call to the support number times out or fails for some reason,
the caller is presented with a response containing the following TwiML.
```XML
<Response>
  <Say>Our agents are assisting other customers.</Say>
  <Gather numDigits="1" input="dtmf speech" hints="yes, no" action="fourth">
    <Say>Would you like to leave a voice message instead?</Say>
  </Gather>
</Response>
```
After this, the caller can press 1 for voice mail, in which case, the following TwiML records a
voice message.
```XML
<Response>
  <Record action="fifth" />
</Response>
```
When the recording is complete, the `fifth` script uses a custom program to
send the message with the recorded file's clickable link to the support team,
generates the following TwiML, and terminates the call.
```XML
<Response>
  <Say>Your voice message has been recorded. We will get back to you shortly.</Say>
</Response>
```
On the other hand, if the caller prefers to wait, and presses 2, then
the `fourth` script spits out the following response.
```XML
<Response>
  <Gather action="sixth">
    <Say>Please enter your four digit PIN</Say>
  </Gather>
</Response>
```
Once the user enters the numbers, e.g., `1234`, the following TwiML is generated, to
put her on hold for the next agent.
```XML
<Response>
  <Say>Let me put you on hold for the next available agent</Say>
  <Enqueue>customer-1234</Enqueue>
</Response>
```
A number of attributes and parameters are skipped in the above TwiML based flow for simplicity.
For example, what happens on timeout or failure. To incorporate such corner cases,
the TwiML code in the examples above will become more involved.

The various server side scripts to handle the dialog flow can be combined
in practice in a single script file with software state machine. However, that has
significant overhead of state maintenance and state-based processing to be able to generate
up to ten different TwiML pages for the caller.

The previous example shows the complexity of implementing such an interactive dialog,
and requires carefully crafted control flow as state moves from one script to another.
Although, with VoiceXML, the number of pages
generated are fewer, the complexity persists to a large extent. This is due to
the requirement to integrate with custom services, e.g., for getting video call link,
or storing recorded voice message.

#### How easy is it with the dialog package?

Now consider the following interactive dialog script, representing the previous example.

**Exhibit 2**
```Tcl
Dialog {
  <<< Hello and welcome to our new customer service phone line.
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
          send_message $file
          <<< Your voice message has been recorded. We will get back to you shortly. }\
        >>> else {
          <<< Please enter your four digit PIN
          >>> input
          <<< Let me put you on hold for the next available agent
          enqueue "customer-$input" }\
      }
    }
  }
}
```


There is a glaring similarity between the pseudo-code of exhibit 1 and the real-code of exhibit 2.
The script presented in exhibit 2 is an easy read. 

 > Exhibit 2 is actually a working Tcl script using our `dialog` package
 > described in this article.

<br/>
Note the clarity and coherence of the dialog in exhibit 2. Now
imagine if programmers could write dialogs in that format, instead of having to
deal with the complex orchestration of control flow described earlier.

#### How does it relate to TwiML?

Our Tcl `dialog` package allows you to write such coherent linear dialog in a single file.
However, you may choose to use multiple files if you like. It contains bunch of commands
to allow creating TwiML at various steps.

Note that `<<<` and `>>>` are
special commands to perform output or input with the user, similar to the `<Say>` and `<Gather>` TwiML
elements. Moreover, all the other TwiML verbs and nouns have
corresponding commands, e.g., `message` command for `<Message>` verb, `dial` command for `<Dial>`
verb, and so on.

Most of the commands can generally accept a list of attributes and/or a nested
body, allowing you to map one-to-one between the desired TwiML element and a Tcl command at
each step. Thus, a developer who understands TwiML, and is familiar with Tcl,
will intuitively know the commands of the `dialog` package.

#### Why is it written in Tcl?

Finally, since the dialog is written in Tcl, the developer gets the full benefit and flexibility of
a complete scripting language. For example, one could invoke external tools and libraries
as needed, or program the business logic and control flow (i.e., if-elseif-else, while-do, etc)
using the scripting language.

On the other hand if a separate interpreter is built to parse the the pseudo-code of exhibit 1
and generate the corresponding TwiML, then we end up with yet another way to represent
VoiceXML-like dialogs. And that comes with its limitations, in what it could do.
But if the dialog
specification is done in the target developer's language itself, then it gets the full benefit
of the language. And with powerful scripting languages like Tcl and Python, that is
a huge benefit.

#### What are the goals of this project?

The `dialog` package makes it easy to write complex multistep
interactive dialogs. Currently it supports TwiML, but we plan to allow VoiceXML in the future.

The target developers are those web developers who are comfortable with
scripting languages, and understand (or can learn) TwiML. The initial code is written in Tcl, and
is available for writing dialogs in Tcl scripts. We want to implement on other
popular scripting languages, such as Python. We want to exploit the
benefit of dialog readability in the target language.

The project covers both voice and messaging dialogs. It includes user
input via speech, dtmf as well as text messages. The Tcl commands in the package
are choosen to make it language neutral, so that it can be easily extended to
other XML-based dialog languages such as VoiceXML.

The dialog scripts written using our package can be tested locally in a command line
mode, or via locally running and included CGI-enabled web server. This allows
extensive testing before deploying the script on the real web server.
Local development enables rapid prototyping and a short develop-test-fix cycle.

So how does it work? And how can you start using this?
Read on to learn more about what it takes to write
complex multistep interactive dialogs in a single coherent script file.

### Background

This section describes how the various components of the software interact?
And why certain design decisions were made?

 > You can skip this section if you are not interested in the internal
 > design of the software. It will not affect your ability to write dialogs
 > using the included `dialog` package.

<br/>
Developers write dialog script similar to exhibit 2. The script is run
as a server-side script by a web server.
The cloud telephony system (e.g., Twilio) is configured to request the web server,
for next TwiML code of interactive dialog step, when an incoming call or message is received
or an outgoing call is initiated.

Web servers often use CGI (Common Gateway Interface) to launch external scripts,
get the result from the script, and use that to respond to the web request, from
a web client. In this case, the web client is the telephony system, Twilio, itself.
One problem is that the Twilio system will demand new TwiML at each step from the web server, whereas the dialog
script is intended to be long running multistep script.

Thus, we treat the dialog script as a **coroutine** - a program that supports
non-preemptive multitasking by
allowing multiple entry points for suspending and resuming execution at certain
locations. At the end of each step, the script generates a response (e.g., TwiML), and suspends
execution. When more input or event is received from the web client belonging to
the same session, it resumes execution.

The web server identifies related web requests to belong to the same session,
so that they can be delivered to the same coroutine script instance.
This session identifier uses developer account identifier, and call identifier for voice,
or combination of source and destination phone numbers for messaging.

The web server can invoke the dialog script as a coroutine. It supplies subsequent
related web requests to the same script instance. The script responds with
subsequent TwiML responses at each step in the dialog. However, this makes the
web server dependent on the programming language of the server side script,
so that it can understand and interface with the coroutine. 
Unfortunately, if the language is Tcl, such a web server does not exist.

Alternatively, one could write a master server side CGI script, which interfaces
between the web server request/response and the dialog coroutine script. If the
master script is in Tcl, it can understand the coroutines of the Tcl dialog script.
Unfortunately, built-in coroutines in Tcl are within a process, and do not
live across new invocations of the script.

To solve this, the dialog script could save the execution state in a file before suspend,
and restore it on resume, as instructed by the master script. In that case, the dialog script
process is killed after saving the state on suspend, and a new process is started on
resume to pickup the dialog execution state from the saved content.
Tcl allows saving most of the state of a running program, and restoring
it by reloading new Tcl program that sets
the state. Unfortunately, it does not allow starting the new script at an arbitrary point, especially
when the dialog script becomes more involved with nested blocks and procedures.

An alternative is to suspend (think, ctrl-Z) the dialog script process at the process level,
and resume it, as instructed by the master script. Although this is doable in theory, it is
cumbersome in practice with Tcl. The existing Tcl interpreters that are preloaded on
popular systems are thread enabled. And a Tcl program that uses multi-processing or
inter-process-communication (e.g., using Tclx package) does not play nice with a multi-threaded
Tcl interpreter. One could recompile and redistribute a different single-threaded
interpreter for such an approach to work. But we chose not to.

After some research, we decided to use a long running process for the dialog script
that interacts with the master script over named pipes. Named pipes are available on
Unix as `fifo`, and also on Windows using Tcl. Instead of named pipes, bi-directional
sockets may be used by another implementation.
In our case, named pipes are created for each dialog session, i.e., a
running instance of the dialog coroutine script. And are terminated when the coroutine
script terminates. Thus, the dialog session corresponds to a running instance of the
dialog coroutine script.

A session identifier is created by the master CGI script, and consists of the
`AccountSid`, `CallSid` and the dialog script path to uniquely identify
a running instance of a voice dialog script. A message dialog script, on the other hand,
lacks `CallSid`. In that case, we use the `AccountSid`, `From` and `To` parameters,
along with the dialog script path, to create the session identifier.
This may not return the right instance in all cases, e.g., if the phone numbers
are overloaded for multiple purposes. However, the approach is similar to the recommended
way to maintain messaging session using cookies in the Twilio messaging apps.

If the session instance does not exist, it creates the named pipes for the two direction of
data exchange, and spawns the dialog script as a new process, thus creating a new
session instance. It then uses the
downstream direction pipe to send the web request parameters to the dialog script, and the upstream
direction pipe to receive the TwiML responses from the dialog script.

Any stale dialog sessions are terminated after some inactive time. This
frees up system resources, e.g., unused processes and open file descriptors for
named pipes.
The inactive timeout for voice session can be short, corresponding to maximum duration
a single TwiML should be allowed to run. On the other hand, for a messaging session the
timeout can be longer, e.g., four hours, similar to cookies timeout used by the
Twilio system for messaging TwiMLs.
The dialog script may also check the status of the call using Twilio REST APIs to
determine whether it is safe to terminate this process associated with that call.

Once the master and dialog scripts are setup correctly, the dialog script can then use
libraries such as our `dialog` package to generate TwiML at each step of the coroutine.
Among the TwiML verbs, only `Gather`, `Record` and `Dial` are currently
treated as blocking operations in the dialog script. This may change in the future.
The Tcl commands corresponding to these blocking verbs are blocking
commands. These commands temporarily suspend the coroutine dialog script, to wait for
the next web request. However, to make it work correctly in failure cases as well, the
`Redirect` verb is also often used before the coroutine is suspended.

Read on to learn about
how to get started using the `dialog` package, and how to apply these concepts in your
dialog script.


### Getting Started

This software should work on Unix and OS X systems. It may also work on Windows. It needs
Tcl version 8.5 or higher.
```Shell
$ echo 'puts $tcl_version;exit 0' | tclsh
8.5
```

This section guides you through several steps of incremental testing. As mentioned before,
running and testing the script locally saves time and improves the speed of software development.

#### Run as command line terminal program

Start with one of the included sample dialog script on command line as a terminal
program. We have provided several sample scripts.
```Shell
$ tclsh examples/sample1.tcl
```
This will present you with prompts, and ask for input. Type input on the terminal
when prompted. For certain commands such as `dial` or `record`, it will ask if the
request should succeed (Y) or fail (n), and based on that it will continue the dialog.

An example interaction using the command line invocation is shown below.
```
$ tclsh examples/sample1.tcl 
<<< Hello and welcome to our new customer service line.
<<< Please say sales or support, or press 1 for sales, and press 2 for support.
>>> sales
<<< Let me connect you to sales.
... dial +12121234567 [Y/n]? Y
```

#### Run as command line CGI program

Next, test the dialog script as a locally running CGI script. The master CGI script
is named `dialog.cgi`, which invokes the actual dialog script supplied using the
`Dialog` parameter. 
```
$ tclsh dialog.cgi AccountSid=1\&CallSid=2\&Dialog=examples/sample1.tcl
```
Remember to escape the `&` character in the list of parameters to avoid shell interpretation.
Alternatively, you can separate the parameters with spaces.
```
$ tclsh dialog.cgi AccountSid=1 CallSid=2 Dialog=examples/sample1.tcl
```
This will print out the generated TwiML at this step of the coroutine. For first invocation,
it will print the initial page like this.
```
$ tclsh dialog.cgi AccountSid=1 CallSid=2 Dialog=examples/sample1.tcl
Content-Type: text/xml

<?xml version="1.0" encoding="UTF-8"?>
<Response><Say>Hello and welcome to our new customer service line.</Say>
<Gather input="dtmf speech" hints="sales,support" numDigits="1"
action="dialog.cgi?Dialog=examples/dialog1.tcl"><Say>Please say sales or
support, or press 1 for sales, and press 2 for support.</Say></Gather>
<Redirect>dialog.cgi?Dialog=examples/dialog1.tcl</Redirect></Response>
```
The actual `Response` element is on one line, but is shown above with line wrapping
for readability.

After generating the first TwiML, the dialog script blocks at the `>>>` command,
to wait for the user input. The blocking behavior of certain commands is similar to
what you see when testing as a terminal program.

The next time the command is invoked, it continues the dialog script to the
next step and returns the next TwiML as follows.
```
$ tclsh dialog.cgi AccountSid=1 CallSid=2 Dialog=examples/sample1.tcl Digits=1
...
<Response><Say>Let me connect you to sales.</Say>
<Dial action="dialog.cgi?Dialog=examples/dialog1.tcl">
<Number>+12121234567</Number></Dial></Response>
```
Note that the `Digits` parameter was supplied in the previous command, to
mimic the user input on the telephone keypad. Alternatively, you could
supply `SpeechResult=sales` to achieve the same behavior in this example.

At this time the dialog script is blocked at the `dial` command to wait for the
result of this blocking command. The next time it expects the result of the `Dial` verb, using the
`DialCallStatus` as follows.
```
$ tclsh dialog.cgi AccountSid=1 CallSid=2 Dialog=examples/sample1.tcl DialCallStatus=completed
...
<Response><Hangup/></Response>
```
At this point the dialog coroutine script and the session terminates.

If you check the process after each step, you
will see the long running  script process after the first two steps, but not after the
last.
```
$ ps -eaf | grep tclsh
```

If the right user input is not supplied at a step, then the corresponding
blocking coroutine procedure (`>>>`, `dial` or `record`) will generate an exception.
If the dialog script does not catch the exception, a default exception handler is used
to generate a TwiML that shows the error.

For example, if after the first TwiML is printed, the second invocation does not supply
the `Digits` parameter, then it returns the following second TwiML instead, and the dialog script
terminates. This is similar to how the terminal invocation behaves if the user enters no input after the
first prompt.
```
$ tclsh dialog.cgi AccountSid=1 CallSid=2 Dialog=examples/sample1.tcl
...
<Response><Say>There was an error in generating the page.</Say>
<Say>timeout</Say>
<Hangup/><Log><![CDATA[timeout
    while executing
"gets stdin input"]]></Log></Response>
```
This TwiML with error message is more verbose, including the stack track of what went wrong.
Note that the `Log` element is not valid in TwiML. However, the Twilio system should ignore it,
besides logging a warning. If you want to disable the exceptions logging, you can disable the logger
in `dialog.cgi` and `dialog1.0/dialog.tcl` files as follows.
```
set _dialog(logger) 0; # disable the logger
```
We will learn more about exception handling for blocking commands later in this document.

#### Test with the supplied web server

A very simple Tcl-based web server with CGI capability is included in the project.
It runs by default on port 8000, which can be changed by supplying the port number as
the first argument.
```
$ tclsh webserver.tcl
```

Open the URL `http://localhost:8000/dialog.cgi?AccountSid=1&CallSid=2&Dialog=examples/sample1.tcl`
in your browser. Alternatively, on Unix and OS X systems, you can use `curl` to
test the web request and response on the command line.
```
$ curl -XPOST http://localhost:8000/dialog.cgi -d AccountSid=1 -d CallSid=2 \
  -d Dialog=examples/sample1.tcl
<?xml version="1.0" encoding="UTF-8"?>
<Response><Say>Let me connect you to sales.</Say>
<Dial action="dialog.cgi?Dialog=examples/sample1.tcl">
<Number>+12121234567</Number></Dial></Response>
```
For subsequent responses in the same dialog session, supply the additional parameters
like `Digits=1`, `SpeechResult=sales` or
`DialCallStatus=completed` as needed. Note that one difference between
accessing from the browser versus `curl` is that - from the browser it always uses the `GET`
request, whereas with `curl` you can specify `GET` or `POST`. Fortunately, the dialog CGI
script can handle the parameters correctly in both the cases.

#### Test using localtunnel, supplied web server and Twilio

Install local tunnel software, e.g., from https://localtunnel.me. Pick some
sub-domain, e.g., `myproject`, for your project, and run it locally as
```
$ lt -s myproject -p 8000
Your url is: https://myproject.localtunnel.me
```
If the sub-domain is unavailable, pick something else.

Assuming that your local instance of the `webserver.tcl` program is running on the same machine,
you can now reach the server from the Internet.

Edit your voice URL on Twilio console for an existing or new number to point to
`https://myproject.localtunnel.me/dialog.cgi?Dialog=examples/sample1.tcl`

Note that other required parameters such as `AccountSid` and `CallSid` are automatically
sent by the Twilio system when it sends a web request to your web server.

Now it is time to try out the real phone call to your Twilio number, and see
the dialog script running.

Do not keep local tunnel running for longer duration when you are not actively testing.
The simple web server used in this step is not secure, and exposing it for longer duration
opens up your local machine for network attacks.

#### Install on your public web server

Once everything is tested, and working as expected in the previous steps,
you can now copy the project files
along with dialog scripts to your external website, which must have CGI enabled. Depending
on which web server you use, there are different configurations to enable CGI, and
different directory locations under which the CGI files should reside.

Make sure that your server machine has Tcl 8.5 or later installed.

Although you can use the same `webserver.tcl` on your external machine for testing, it is
strongly discouraged due to security issues in that simple web server. 

#### In case of any error

You can see the error logs in `/tmp/dialogs` directory. A separate sub-directory is
created for each dialog instance, and the sub-directory name contains the session
identifier, i.e.,
`AccountSid`, `CallSid` and the dialog script path. Under this sub-directory, there are
files for named pipes, which are active while the dialog script is running; a
file for process ID of the dialog script instance; and finally a file for output log
of the dialog script.

If the dialog script instances cleans up correctly, the named pipes and the process ID
file are removed. The log file persists, but may be empty, so that you can check the
logs later. Any output generated by the dialog script, bypassing the modified
`puts` command, is written out to the log file. It also stores any exceptions
caught in running the dialog script.

If the dialog script instance is terminated, but the named pipes did not get removed,
then you can manually remove those files or even the sub-directory. This will help
get a clean slate, especially during testing, when you are likely to use a fixed
value for `AccountSid` and `CallSid`. Hence, an unclean previous instance of the
dialog script will interfere with the new instance. In the real deployment, the session
identifier value
will change for every call, hence the cleanup problem is not likely to manifest.
Moreover, the blocking commands have a timeout of about four hours, after which they
return with a timeout error.
However, if the files keep leaking and processes do not terminate cleanly, you will soon
run out of system resources, especially in your local testing.

### Dialog Script

This section describes the various commands of the `dialog` package, and guides you
on how to write the dialog script.

#### Structure of the file

The general structure of a dialog script looks like this,
```
lappend auto_path .
package require dialog
...
Dialog {
  ...
}
```
However, it is just a Tcl script. If your dialog package is not installed in the
current directory, then put the right search path. If you plan to organize your
dialog into multiple dialogs, you can have more than one `Dialog` blocks.
Tcl code can appear outside or inside the `Dialog` block. When inside, certain
commands such as `puts` and `gets` are modified to reflect the dialog script behavior.

Note that Tcl does not have a concept of "block", and the code inside `{...}` above
is actually the first argument to the `Dialog` command. However, we use the term
`Dialog` block to refer to this code, which contains your interactive dialog script.

#### List of commands

The list of commands available within the `Dialog` block are summarized below.

These commands generate the corresponding XML elements: `dial`, `record`, `message`, `play`,
`pause`, `reject`, `leave`, `hangup`, `enqueue`, `redirect`, `client`, `conference`,
`queue`, `sim`, `sip`, `body`, `media`. For example a `redirect` generates the `<Redirect>`
element.

The `puts` and `gets` commands are used for generating `<Say>` and `<Gather>` elements.
The `<<<` and `>>>` commands are aliases to `puts` and `gets`, with some differences.
The `gather_attrs` command is useful in changing the attributes of the subsequent `gets` or `>>>`
command as described later. Similarly, the `say_attrs` command is useful in changing the
attributes of the subsequent `puts` or `<<<` command.

Finally, a new `logger` command is defined to put a `<Log>` element in the
XML, if logger is enabled.

#### Command attribute vs. body

Many of these commands can be invoked in the following form.
```
cmdname attr1=value1 attr2=value2 ... cmdbody
```
In turn it generates the corresponding XML element in the TwiML response. Here the
`cmdname` forms the element name, the list of zero or more name-value pair of attributes
form the attributes of the XML element, and the final `cmdbody`
becomes the nested text node of the element.

For example, the command
```Tcl
sip username=bob password=my\ pass sip:alice@home.com
```
becomes the XML element
```XML
<Sip username="bob" password="my pass">sip:alice@home.com</Sip>
```


The relationship shown above between a command and its XML element is generally followed
for many included command, such as `play`, `pause`, `reject`, `leave`, `hangup`, `enqueue`,
`redirect`, `client`, `conference`, `queue`, `sim`, `sip`, `body` and `media`.

The nesting rules for the commands follow the nesting rules of the corresponding XML
elements, e.g., since `<Sip>` can be nested only inside a `<Dial>` element, the
command `sip` should only appear in the body of command `dial`.

There are some exceptions to the above pattern. For example, the `dial` command
or the `message` command include a nested `<Number>` or `<Body>` element, respectively,
to wrap the `cmdbody` item. For example, the command
```Tcl
dial +12121234567
```
becomes the XML element
```XML
<Dial><Number>+12121234567</Number></Dial>
```
and the command
```Tcl
message to=+12121234567 "What's up?"
```
becomes XML
```XML
<Message to="+12121234567"><Body>What's up</Body></Message>
```

However, for these commands, since the body can have more than one elements, a special
`-body` argument is allowed, which treats the next argument as list of commands to include
in the nested body. For example, the command
```Tcl
dial timeout=10 -body {
  number +18589876453
  client joey
  client charlie
}
```
becomes the XML element
```XML
<Dial timeout="10">
  <Number>+18589876453</Number>
  <Client>joey</Client>
  <Client>charlie</Client>
</Dial>
```

Similarly, the command
```Tcl
message -body {
  body "What's up?"
  media http://some-path-to-media
}
```
becomes XML
```XML
<Message>
  <Body>What's up?</Body>
  <Media>http://some-path-to-media</Media>
</Message>
```

#### Input and output

By default, a Tcl's `puts` and `gets` commands are used for input and output, e.g., on an
interactive terminal. However, the `dialog` package replaces these commands within the
`Dialog` block with a different behavior - to generate the XML elements as needed for
input and output with the caller.

Generally, one or more `puts` commands will generate one or more `<Say>` elements.
```Tcl
puts "Hello there"
puts "How are you today?"
```
```
<Say>Hello there</Say>
<Say>How are you today?</Say>
```

Similarly, a `gets` command will generate one `<Gather>` element. The following two
variants will generate the same element.
```Tcl
gets stdin input
set input [gets stdin]
```

A `puts` followed by a `gets` command will cause the `<Say>` element to be nested inside the
`<Gather>` element. It assumes that a prompt immediately preceding an user input command
is a prompt for that user input.
```Tcl
puts "Please enter your four digit PIN"
gets stdin input
```
```
<Gather action="...">
  <Say>Please enter your four digit PIN</Say>
</Gather>
```

Note that `<<<` is an alias of `puts`, except that it concatenates all its arguments with spaces.
Thus the following two are equivalent. Hence you do not need to quote the text argument of `<<<`.
```
puts "How are you today?"
<<< How are you today?
```

Also note that `>>>` is an alias of `gets` with some special consideration (more later).
The following two are equivalent.
```
gets stdin input
>>> input
```

Many times, a user input is followed by if-elseif-else control flow based on the user input, e.g.,
```
puts "Press 1 for sales or 2 for support"
gets stdin input
if {$input eq "1"} {
  ...
} else if {$input eq "2"} {
  ...
}
```

The `>>>` command provides a convenient shortcut to achieve such behavior in a single command.
Consider the following code, which is similar to the previous one.
```Tcl
<<< Press 1 for sales or 2 for support
>>> "1" { ... } "2" { ... }
```

For better readability, especially if the internal blocks have multiple lines, you can
rearrage the same code as follows.
```
<<< Press 1 for sales or 2 for support
>>> "1" {
    ... }\
>>> "2" {
    ... }
```
Note that the single Tcl command `>>>` above is split across multiple lines,
and the second `>>>` is actually
an argument of the first `>>>` command. The second and subsequent `>>>` are just syntactic sugar,
and are ignored.

Furthermore, the conditional expression collected from that command is automatically
populated as various attributes of the generated `<Gather>` element. For example, if the
condition only includes one digit numbers, then a `numDigits=1` attribute is added.
Similarly, if the condition only includes digits, then `input=dtmf` is added. On the other
hand if the condition includes only non-digits, then `input=speech` is added, and all the
words from the conditions are used to create the `hints=...` attribute. If the condition includes
both digits and non-digits, then `input=dtmf speech` is added. 

The above example generates the following as the first TwiML to receive user input.
```
<Gather action="dtmf" numDigits="1" action="...">
  <Say>Press 1 for sales or 2 for support</Say>
</Gather>
```

If an `else` keyword
is used in place of a condition, then that must appear as the last condition, and is followed
when all else fail.
Consider the following intuitive example, which uses the Tcl `while` loop
to repeat the prompt if user enters unexpected input.
```
set looping 1
while {$looping} {
  <<< Please say sales or support, or press 1 for sales, or 2 for support.
  >>> "sales | 1" {
    ...
    set looping 0 }\
  >>> "support | 2" {
    ...
    set looping 0 }\
  >>> else {
    <<< You said ${:input:} but it was not recognized. }
}
```

Note that the `>>>` command implicitly stores the user input in the `:input:` variable, as
shown in the previous example.

If you prefer to use `puts` and `gets` instead of `<<<` and `>>>` then you supply these
attribute attributes to the `<Gather>` element using the `gather_attrs` command, e.g.,
```
puts "Please say sales or support, or press 1 for sales, or 2 for support.
gather_attrs hints=sales,support numDigits=1 input=dtmf\ speech
```
Note that the attributes supplied in the `gather_attrs` command affect all the subsequent
`gets` command, until modified again by a `gather_attrs` or `>>>` command. On the other hand
the `>>>` command constructs its `<Gather>` attributes on each instance.

Similarly, the `<Say>` element attributes can be changed using the `say_attrs` command,
e.g.,
```
say_attrs voice=woman language=en-gb
puts "Would you like a hamburger?"
puts "And how about a drink?"
```
```
<Say voice="woman" language="en-gb">Would you like a hamburger?</Say>
<Say voice="woman" language="en-gb">And how about a drink?</Say>
```
The attributes set in this way are applied to all the subsequent invocations of the `puts`
and `<<<` commands, until changed again by another `say_attrs`.

Furthermore, you can mix and match the two variants, `puts` and `gets` vs. `<<<` and `>>>`, e.g.,
```
puts "Hello there"
<<< Please say sales or support, or press 1 for sales, or 2 for support.
>>> "sales | 1" {...}\
>>> "support | 2" {...}\
>>> input
if {[string is integer $input]} {
  ... # entered some digit
}
```
In the previous example, the last `>>> input` is optional and was used to store the
user input in that variable. You do not need to store the user input unless it is needed
beyond conditional processing. Moreover, the `:input:` variable already contains the user
input in any case, but only within the `>>>` command block.

There is one other difference between `>>>` vs. `gets` followed by conditional matching.
The `>>>` command automatically applies case insensitive matching for the conditions, e.g.,
even if the speech is detected as "Sales" it will match the "sales" condition. On the
other hand, with `gets`, the condition statement must perform its own case conversion
before comparison, e.g.,
```
gets stdin input
if {[string tolower $input] eq "sales" || $input eq "1"} { ... }
```
Moreover, the conditions in `>>>` command can use `glob`-style pattern matching.
This will be described later.

#### Blocking step

Only the `dial`, `record`, `gets` (and hence `>>>`) commands are blocking. They cause the dialog
coroutine script to return an intermediate TwiML. Generally, these commands
return the intermediate result of the operations leading up to that command.
The command typically involves returning an intermediate
XML, and waiting for the next web request in this dialog coroutine script. This new web
request typically causes the command to return a value or throw an exception in the coroutine.

Thus, a blocking command implicitly includes the next action attributes when applicable,
to point back to the same script, to continue the coroutine. For example, a `dial`
command will actually map to
```XML
<Dial action="dialog.cgi?Dialog=...path of dialog script">...</Dial>
```
Similarly, a `gets` command will map to
```XML
<Gather ... action="dialog.cgi?Dialog=... path of dialog script">...</Gather>
<Redirect>dialog.cgi?Dialog=... path of dialog script</Redirect>
```

Note that both `gets` and `record` commands generate a trailing `redirect`, so that
if the user input or call recording process times out or fails, then the coroutine script can still
continue, albeit with no user input or recording file. This in turn causes the
command to throw an exception.

A blocking command may fail, or may return a result. On the other hand, a non-blocking
command just creates the XML element in the response, and will typically not fail.
Thus, to avoid unexpected behavior, the dialog should specify what happens on exception,
everytime a blocking command is invoked.

The following example shows what do to on timeout, waiting for user input.
```
if {[catch {gets stdin input}]} {
  puts "I am sorry I did not catch that. Let me transfer you to an agent."
  ...
}
```

The `dial` command throws an exception if the dialed call was not answered or did not complete.
```
if {[catch {dial +12121234567} err]} {
  puts "Your call failed with reason $err"
}
```

The `record` command throws an exception if the recording fails for any reason.
On success, the command returns the URL string of the recorded file.
```
catch {set file [record maxLength=120]}
```

#### Retrieve unmangled puts

As mentioned earlier the definition of `gets` and `puts` within a `Dialog` block are changed to
say a prompt or wait for user input via TwiML. The original definitions are moved to
`gets_old` and `puts_old`. In most cases, you do not need to worry about this, as described
in this section.

However, if you want, you can revert back to the original
definitions of these procedures temporarily using the `(raw)` procedure. This is useful
if you wish to invoke some third-party library procedure for which there already exists
`puts` instances within the third-party code,
but those should not cause a `<Say>` element in the generated TwiML. An example follows.
Here the debug-trace usages of `puts` invoke
the original unmodified `puts`, and the output goes to the `log` file of this dialog session.
```
proc next_response args {
  puts "input is $args"
  ...
  puts "result is $result"
  return result
}
Dialog {
  puts "What do you need?"
  gets stdin input
  (raw) {
    puts "calling next_response $input"
    set response [next_response $input]
  }
  puts $response
}
```

Moreover, even without using the `(raw)` keyword, the modified `puts` invokes the
original procedure if it is used to write to a file. For example,
```
Dialog {
  puts stdout "Dialog invoked"; # this invokes original
  set f [open somefile.txt w]
  puts $f "Log to a file";      # and this too...
  puts "Hello there";           # but this invokes modified puts to '<Say>'
}
puts "Not in dialog";           # outside Dialog, uses unmodified again
```

Similarly, for `gets`, if a file name other than `stdin` is supplied as the
first argument, then it invokes the original procedure.
```
Dialog {
  set f [open somefile.txt]
  gets $f input;                # this invokes original
}
```

#### Web request parameters

The parameters received in the web request from the Twilio system are available in the
implicit `:params:` variable as a Tcl `dict`. When the `Dialog` is entered, the
value is based on the first request. As more blocking commands such as `dial` or `gets`
are invoked, the value is updated with the parameters of the last received web request.

```
Dialog {
  logger "parameters are ${:params:}
  puts "Say something"
  gets stdin input
  logger "parameters now are ${:params:}
}
```

#### Messaging dialog script

Majority of the dialog description in this article is about voice dialog script. Here we
learn about the differences with message dialog script, in this section.

Previously we mentioned that the `<<<` and `>>>` commands are aliases, with
some modifications, of `puts` and `gets` respectively. This is true for both
voice and message dialog scripts. We also mentioned previously
that the `puts` command generates `<Say>` element, and the `gets` command generates
a `<Gather>` element. This is true only for voice dialog scripts.

For a message dialog script, the `puts` command behaves similar to the `message` command,
but without any attributes,
and generates the `<Message>` element. And the `gets` command waits for next message
in the same session, instead of the next digit or spoken voice from the caller.

The `MessageSid` and `CallSid` parameters are
used to determine whether the dialog script is for voice or
message. The `CallSid` parameter can determine the context of the dialog script
coroutine for a voice dialog. However, there is no unique identifier for a message dialog.
One could use cookies in the first TwiML response, so that the Twilio system
supplies the same cookie in subsequent messages from the same phone number.
However, we decided to implement our own coroutine session identifier based on the
`To` and `From` numbers of the message, along with `AccountSid` and path of the dialog
script. 

Consider the following messaging dialog script.
```Tcl
<<< How can I help you? Type SALES or SUPPORT or something else
>>> sales {
  <<< Visit http://my-sales-site }\
>>> support {
  <<< Which product? (PC, laptop, tablet)
  >>> input
  <<< Visit http://my-support-site/$input/page }\
>>> else {
  <<< Visit our FAQ page http://my-faq-site }
```

In addition to the exact match on the conditional expressions of the `>>>` command,
it also supports `glob`-style matches, e.g.,
```
>>> *sales* {... }\
>>> *support* {...}\
>>> *car*insurance* {...}
```
The matching is done sequentially, e.g., if the user typed "car insurance support", then
it will match the second condition for `*support*`, and will skip the remaining condition,
including the last one, which might have been a better match in this example.

Although `glob`-style match, is available for voice as well as message dialogs, it
is particularly useful for message dialogs, where user responses may not be the exact
word used in the conditions.

Some developers might be tempted to reuse the same dialog script for voice as well
as messaging. It is possible for simple dialogs, with only input-output elements.
However, that is not recommended. Given that the dialog scripts are short,
it is quite easy to create separate voice vs. messaging dialog scripts.

Nevertheless, you can check whether the dialog script is invoked for voice or message
by testing the presence of `MessageSid` or `CallSid` in the `:params:` variable.
```
if {[dict exists ${:params:} MessageSid]} { ... } else { ... }
```

### Closing Thoughts

Writing event driven programs is difficult because it is harder to comprehend
non-linear behavior. Luckily, there are tools and techniques to make them easier
to write, e.g., using multi-threading, cooperative multi-tasking (i.e., coroutine), or
deferred (or promise) abstractions. The current knowledge and practice of creating
interactive dialogs using Twilio largely deals with multitude of server side scripts, TwiMLs
and state, and with transfer of the dialog state from one program to another.

This article and associated project aims to simplify the event driven programming of
Twilio interactive dialogs using the coroutine concept. The developer can thus create
simple and single coherent file containing the interactive dialog. And the system
takes care of maintaining state, and generating multiple TwiML output as needed,
as returned from the coroutine dialog script.

The current implementation is limited to Tcl programming language, and only Twilio system.
As mentioned earlier, in the future,
the project will try to cover another programming language, most likely
Python, and another dialog language, most likely VoiceXML.

There are several other improvements easily achievable on top of the current implementation.
An unsorted list of ideas follows: ability to deal with server caching; allow
specifying inline linked (or screening) dialog steps of the dialed call which can be played as
prompt before the dialed party is connected; ability to restrict commands that can be
invoked in a context similar to which TwiML verbs and nouns can be nested in another.

The idea of using coroutine based CGI scripts can further be extended to
web servers, using an extension to CGI. This will remove the need for a
master script. And this will allow the web server to exploit coroutine
feature available in several popular programming languages. However, such a
web server will often need to run the script in it own server process space, since
coroutines are typically implemented for threads. Several other rejected ideas mentioned in the
background section earlier may be applicable and useful to other sets of web server and programming
language combinations.

Finally, the current system is designed for a two party interaction - a person on one side and a
machine on the other. Defining interactive dialogs among multiple participants,
e.g., multiple users, and/or multiple machines or their combination, is in itself a challenge.
Doing so using a coroutine dialog script is even more difficult.
That remains our research problem for the future.

Much of the existing work on interactive dialog description revolves around
natural language systems. They incorporate user interfaces or SDKs to program such dialogs, extract
entities, and use those in subsequent control flows. Our project is orthogonal to such
user interface based design systems, but can be used with modifications
in such natural language based dialog flows. This was partly demonstrated by the integration of
Twilio's speech recognition, and received text messages `glob`-style string matching in our `>>>`
command to accept user input.

### References

 1. [Differences between VoiceXML and TwiML](https://stackoverflow.com/questions/28801353/what-are-the-differences-between-voicexml-and-twiml-plivoxml)
 1. [TwiML for programmable voice](https://www.twilio.com/docs/voice/twiml) and [SMS](https://www.twilio.com/docs/sms/twiml)
 1. [TwiML interpreters similar to Twilio](https://www.quora.com/Is-there-a-need-for-an-open-source-version-of-a-platform-like-Twilio-or-Tropo):
    [Restcomm](https://www.restcomm.com/), [Somleng](https://github.com/somleng/somleng-project)
 1. [What are Dialog systems](https://en.wikipedia.org/wiki/Dialogue_system)
 1. [Tcl quick start guide](https://learnxinyminutes.com/docs/tcl/)
 1. [Writing CGI in Tcl](http://expect.sourceforge.net/cgi.tcl/ref.txt)
 1. [Scripting VoiceXML and TwiML using Tcl](http://blog.kundansingh.com/2018/06/scripting-voicexml-and-twiml-using-tcl.html)
 1. [Playing CGI in Tcl](http://wiki.tcl.tk/16867)
 1. [Dumping interpreter state in Tcl](https://wiki.tcl.tk/4470)
 1. [Coroutine in Tcl](https://www.tcl.tk/man/tcl/TclCmd/coroutine.htm) and [here](https://wiki.tcl.tk/13232) and [also here](http://jacqkl.perso.chez-alice.fr/tclpage/)
 1. [Using fork in thread-enabled Tcl](https://groups.google.com/forum/#!topic/comp.lang.tcl/YjcKpcZLbO0)
 1. **[Source code of this project](http://github.com/theintencity/tcl-twilio-dialog)**


