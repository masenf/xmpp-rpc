xmpp-rpc
========

XMPP irssi RPC server: XiRPC. Relay irc messages to/from xmpp -- 
never miss an important message.

Usage
=====

* copy script to $HOME/.irssi/scripts
* load script into irssi: /load xmpp-rpc.pl
* see detailed usage in irssi: /xirpc

Bug Reports
===========

Please report issues on the project github page
http://github.com/masenf/xmpp-rpc

Features
========
* notify when your name is highlighted in a channel
* notify when you receive private messages
* notify someone on your notify list joins or quits
* monitor specified channels for mentions
* monitor specified channels for a timeout period after interaction
* relay messages from xmpp to the appropriate channel or user

External dependencies
=====================

* AnyEvent (http://software.schmorp.de/pkg/AnyEvent.html)
* AnyEvent::XMPP (http://www.ta-sa.org/net_xmpp2)

Debian / Ubuntu
---------------

* libanyevent-perl
* libanyevent-xmpp-perl

Arch linux
----------

* perl-anyevent (AUR)
* perl-anyevent-xmpp (AUR)

License
=======

This script is the result of several derivations of similar scripts that have 
been created over the years, each one builds on the previous.

* growl.pl script from Growl.info by Nelson Elhage and Toby Peterson
* growl-net.pl script by Alex Mason, Jason Adams
* jabber-notify.pl by Peter Krenesky

As far as I can tell, the above mentioned scripts are licensed BSD, so I've
chosen to license this script under the BSD 3 clause license (see LICENSE).
