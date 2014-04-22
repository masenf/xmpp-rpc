xmpp-rpc getting started
========================

Install dependencies
--------------------

Debian:
    sudo apt-get install libanyevent-xmpp-perl
Arch:
    sudo pacman -S perl-anyevent-xmpp

Track development
-----------------

At this point in the project, you'll want to track the active development 
branch by cloning the git repo and creating a symlink in your irssi scripts
directory. 

    git clone github.com:masenf/xmpp-rpc ~/devel/xmpp-rpc
    mkdir -p ~/.irssi/scripts/
    ln -s ~/devel/xmpp-rpc/xmpp-rpc.pl ~/.irssi/scripts/xmpp-rpc.pl

Now when you pull from master, or switch to a different branch, the script that
irssi sees is updated automatically.

Unfortunately, due to how AnyEvent hooks into irssi sometimes you can't "hot-reload"
the script after updating. **It's recommended to quit irssi before updating the 
script**.

A note about naming
-------------------

Although the script is named **xmpp-rpc.pl**, it is referred to as **XiRPC**
within irssi. Hence commands and settings will be prefixed with **xir**.
This will likely be resolved in later versions. (issue #6)


Initial Setup
-------------

The RPC server really should have its own XMPP account. If you only intend to
receive notifications, it is sufficient to use the same account as the recipient.

Currently the script has only been tested with the prosody XMPP server.

Start up irssi and run the following commands:

    /load xmpp-rpc.pl

You will probably see an error about connecting to localhost, **please ignore this**.
Continue to set up your sender and receiver addresses

    /set xir_notify_user irssi@blah.im
    /set xir_notify_pass AlwaysUseALongStrongAndSecurePassword_Xb
    /set xir_notify_server jabber.blah.im
    /set xir_notify_port 5222
    /set xir_notify_recv me@0x26.net

In this configuration, notifications will be sent from irssi@blah.im to me@0x26.net;
relayed messages will come from my personal account (me@0x26.net) to irssi@blah.im.
Obviously, set these values according to your setup!

Additional Settings
-------------------

If you don't wish to receive notifications while you are actively interacting with
irssi, xir_notify_delay will mute notifications for a number of seconds after 
a key is pressed in irssi. I usually keep this around 30 to 60 seconds depending
on how much I'm using IRC.

    /set xir_notify_delay 30

**Choosing what messages to see**

    /set xir_show_hilight <ON|OFF>

Any messages in which text is highlighted will be relayed via XMPP. This
typically includes nick mentions across all channels

    /set xir_show_privmsg <ON|OFF>

Any query messages will be relayed via XMPP. These messages will be prefixed with [pm].

    /set xir_show_notify <ON|OFF>

Receive notifications when someone on your notify list connects or quits IRC. For 
more info see the /NOTIFY command 
(section 8 of the [irssi manual](http://www.irssi.org/documentation/manual))

Monitoring channel activity
---------------------------

Individual channels may be monitored for activity outside of mentions. This makes
it possible to carry out public discussions solely via XMPP. You can monitor a channel
that you are joined to through irssi or via xmpp relay.

Irssi

    /xir_monitor #test098 300

XMPP

    /monitor #test098 300

If you are joined to the channel you want to monitor and typing this command 
in the channel window, you don't have to specify the channel.

The 300 in this case is the **notify timeout**. If you haven't *interacted* with
the channel in the last 300 seconds, then notifications will not be sent. This
is to prevent getting spammed by messages which are not relevant to you.

The last interaction timer is reset when 
* your nick is mentioned in the channel
* you send a message to the channel via XMPP

Setting the notify timeout to 0 will cause one to receive all messages in a
monitored channel.

Relaying messages via XMPP
--------------------------

Often you'll receive a notification from a query message or channel mention that
asks a specific and direct question of you. Instead of rushing back to a computer
to respond, you can now respond directly from the XMPP client. (Note that the
following code snippets are intended to be sent over XMPP to the irssi user.

    /help

Will display all recognized rpc commands and a brief description of their usage.

**Responding to query messages**

    /msg user1 here is my reply

You can also send query messages to any user on a connected server. If messaging
a user for the first time (not replying), the script will perform a WHOIS for the
nick on each connected server. The first to respond in the affirmative is the 
server that is used to send the message.

**Responding to channel messages**

    #test098 this message goes to the channel!

You must be joined to a channel and monitoring that channel to relay a message
to it. This prevents accidental typos.

Avoiding the noise
------------------

Sometimes irc is not the most important thing in your life, for this we have

    /mute

Sending this command over XMPP will stop all notification messages until a 
you send a matching 

    /unmute

or restart irssi.

If you only want to mute for an hour, you can specify a timeout

    /mute 3600

It's also possible to unmonitor a channel entirely via xmpp:

    /unmonitor #test098

You will not receive messages from this channel until explicitly 
monitoring it again.

Reporting Issues
----------------

I wrote this script for my own personal use, but I don't use every feature in it,
so I may miss some bugs. If you encounter an issue, I ask that you please do the
following to improve the chances that it gets fixed.

* turn on debug messages (/set xir-debug ON)
* [submit an issue on github](https://github.com/masenf/xmpp-rpc/issues/new) with
the following information
    * reproduction steps
    * expected behavior / output
    * actual behavior / output
    * version numbers of irssi, perl, anyevent-xmpp, and xmpp-rpc.pl
    * xmpp server and version (if available)
    * relevant debug messages (window 1)
