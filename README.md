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

* [AnyEvent](http://software.schmorp.de/pkg/AnyEvent.html)
* [AnyEvent::XMPP](http://www.ta-sa.org/net_xmpp2)

Debian / Ubuntu
---------------

* [libanyevent-perl](https://packages.debian.org/search?keywords=libanyevent-perl)
* [libanyevent-xmpp-perl](https://packages.debian.org/search?keywords=libanyevent-xmpp-perl)

Arch linux
----------

* [perl-anyevent](https://www.archlinux.org/packages/extra/any/perl-anyevent/)
* [perl-anyevent-xmpp](https://www.archlinux.org/packages/community/any/perl-anyevent-xmpp/)

License
=======

This script is the result of several derivations of similar scripts that have 
been created over the years, each one builds on the previous.

* growl.pl script from Growl.info by Nelson Elhage (Not supported)
* [growl-net.pl](http://random.axman6.com/blog/?page_id=65) script by Alex Mason, Jason Adams
* [jabber-notify.pl](http://blogs.osuosl.org/kreneskyp/2009/06/02/irssi-notifications-via-xmpp/) by Peter Krenesky

As far as I can tell, the above mentioned scripts are licensed BSD, so I've
chosen to license this script under the BSD 2 clause license (see LICENSE).
