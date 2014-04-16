#!/usr/bin/env perl -w
#
# This is an irssi script to send out notifications over the network using
# AnyEvent::XMPP::Client, formerly Net::XMPP2. 
# Usage:
# copy script to $HOME/.irssi/scripts
# load script into irssi: /load xmpp-rpc.pl
# see detailed usage in irssi: /xirpc

# Please report issues on the project github page
# http://github.com/masenf/xmpp-rpc

# Currently: 
#   sends notifications when your name is highlighted
#   when you receive private messages
#   when someone on your notify list joins or quits
#   monitor specified channels for mentions
#   monitor specified channels for a timeout period after interaction
#   relay messages from xmpp to the appropriate channel or user

# External dependencies:
#   AnyEvent (http://software.schmorp.de/pkg/AnyEvent.html)
#   AnyEvent::XMPP (http://www.ta-sa.org/net_xmpp2)
# debian / ubuntu (probably derivatives too):
#   libanyevent-perl
#   libanyevent-xmpp-perl
# arch:
#   perl-anyevent (AUR)
#   perl-anyevent-xmpp (AUR)

use strict;
use vars qw($VERSION %IRSSI $AppName $muted
            $XMPPUser $XMPPPass $XMPPServ $XMPPPort $XMPPRecv 
            $Client $connected $last_cli_interaction $DEBUG $j);

use Irssi;
use AnyEvent;
use AnyEvent::XMPP::Client;
use Storable     qw( freeze thaw );
use MIME::Base64;

#######################################
###     GLOBALS                     ###
#######################################
$VERSION = '0.02';
%IRSSI = (
	authors		=>	'Masen Furer, based on jabber-notify.pl script by Peter Krenesky, ' .
                    'Based on growl-net.pl script by Alex Mason, Jason Adams' .
                    'Based on the growl.pl script from Growl.info by Nelson Elhage and Toby Peterson)',
	contact		=>	'mf@0x26.net, masen on irc.freenode.net',
	name		=>	'XiRPC',
	description	=>	'XMPP irssi RPC server - control irssi via xmpp',
	license		=>	'BSD',
	url			=>	'http://github.com/masenf/xmpp-rpc'
);
$connected = 0;

# delayed globals come from irssi settings
sub load_settings {
    $DEBUG  	= Irssi::settings_get_bool('xir_debug');
    $XMPPUser 	= Irssi::settings_get_str('xir_notify_user');
    $XMPPPass 	= Irssi::settings_get_str('xir_notify_pass');
    $XMPPServ 	= Irssi::settings_get_str('xir_notify_server');
    $XMPPPort   = Irssi::settings_get_int('xir_notify_port');
    $XMPPRecv 	= Irssi::settings_get_str('xir_notify_recv');
    $AppName	= "irssi $XMPPServ";
    $last_cli_interaction = 0;
    $muted = -1;

    $Client = AnyEvent::XMPP::Client->new (debug => 0);
    $Client->add_account($XMPPUser, $XMPPPass, $XMPPServ, $XMPPPort);
    $Client->reg_cb (
        session_ready => sub {
            my ($cl, $acc) = @_;
            $connected = 1;
            Irssi:print ("Logged into server $XMPPServ  as $XMPPUser. Ready.");
        },
        disconnect => sub {
            my ($cl, $acc, $h, $p, $reas) = @_;
            $connected = 0;
            Irssi:print ("disconnect ($h:$p): $reas");
        },
        error => sub {
            my ($cl, $acc, $err) = @_;
            Irssi:print ("ERROR: " . $err->string );
        },
        message => sub {
            my ($cl, $acc, $msg) = @_;
            evt_incoming_xmpp($msg);
        });
}

# monitored_channels stores state information about channels to notify the user about
my %monitored_channels = { };
my $usage = <<USAGE;
accepted commands:
#channel msg - send message to monitored channel
/msg user msg - send private message to user
/monitor #channel timeout - start monitoring #channel
/unmonitor #channel
/mute [timeout] - don't receive any messages
/unmute - start receiving messages again
USAGE
# Nick lookup functionality
# nick cache correlates users and servers
my %nick_cache = { };
# whocv will be signaled when there is new whois information
my %whocvs = { };

#######################################
###     ONETIME SETUP              ###
#######################################
sub create_settings {
    Irssi::settings_add_bool($IRSSI{'name'}, 'xir_show_privmsg', 1);
    Irssi::settings_add_bool($IRSSI{'name'}, 'xir_show_hilight', 1);
    Irssi::settings_add_bool($IRSSI{'name'}, 'xir_show_notify', 1);
    Irssi::settings_add_bool($IRSSI{'name'}, 'xir_debug', 0);
    Irssi::settings_add_str($IRSSI{'name'}, 'xir_notify_pass', 'password');
    Irssi::settings_add_str($IRSSI{'name'}, 'xir_notify_server', 'localhost');
    Irssi::settings_add_int($IRSSI{'name'}, 'xir_notify_port', 5223);
    Irssi::settings_add_str($IRSSI{'name'}, 'xir_notify_user', 'irssi');
    Irssi::settings_add_str($IRSSI{'name'}, 'xir_notify_recv', 'noone');
    Irssi::settings_add_int($IRSSI{'name'}, 'xir_notify_delay', 0);
    Irssi::settings_add_str($IRSSI{'name'}, 'xir_monitored_channels', '');
}
sub freeze_monitored_channels {
    my $frozen_mc = encode_base64(freeze(\%monitored_channels));
    Irssi::settings_set_str('xir_monitored_channels', $frozen_mc);
    if ($DEBUG) {
        Irssi:print("Froze changes as: ".($frozen_mc));
    }
}
sub thaw_monitored_channels {
    # attempt to reset monitored channels
    my $frozen_mc = Irssi::settings_get_str('xir_monitored_channels');
    if ($frozen_mc) {
        my $thawed_mc = thaw(decode_base64($frozen_mc));
        if ($thawed_mc) {
            %monitored_channels = %{$thawed_mc};
            if ($DEBUG) {
                Irssi:print("Restored monitored_channels from deep freeze");
            }
        } else {
            Irssi:print("Thawed hashref is undefined $frozen_mc");
        }
    }
}

#######################################
###     SHARED COMMANDS             ###
#######################################
# These functions all return a tuple of (success, message)
sub shared_xir_monitor
{
    my ($channel, $notify_timeout) = @_;

    # validate input
    if ($channel ne "") {
        my $ch = Irssi::channel_find($channel);
        if (!$ch) {
            return (0, "Not joined to channel " . $channel);
        }
    } else {
        return (0, "Unspecified channel");
    }
    if (!$notify_timeout and $monitored_channels{$channel}) {
        $notify_timeout = $monitored_channels{$channel};
    }
    if ($notify_timeout <= 0)
    {
        return (0, "Notify timeout must be greater than 0");
    }
    if (!$monitored_channels{$channel}) {
        # create the channel control block
        my %ccb = { };
        $ccb{notify_timeout} = $notify_timeout;
        $ccb{last_interaction} = 0;
        # update global hash table and freeze to settings
        $monitored_channels{$channel} = \%ccb;
    } else {
        $monitored_channels{$channel}{notify_timeout} = $notify_timeout;
        $monitored_channels{$channel}{last_interaction} = time;
    }
    freeze_monitored_channels();
    return (1, "Now monitoring $channel, Notify_timeout = $notify_timeout secs");
}
sub shared_xir_unmonitor ($) 
{
    my ($channel) = @_;
    if (delete $monitored_channels{$channel}) {
        freeze_monitored_channels();
        return (1, "No longer monitoring $channel");
    } else {
        return (1, "Wasn't even monitoring $channel");
    }
}
sub shared_xir_mute ($)
{
    my ($timeout) = @_;
    if ($timeout && $timeout > 0) {
        $muted = time + $timeout;
        if ($DEBUG) {
            Irssi:print("shared_xir_mute: XMPP notifications muted until $muted");
        }
    } else {
        $muted = 0;
        if ($DEBUG) {
            Irssi:print("shared_xir_mute: XMPP notifications muted indefinitely");
        }
    }
}
#######################################
###     IRSSI COMMANDS              ###
#######################################
sub cmd_xirpc {
	Irssi::print('%G>>%n XiRPC can be configured with these settings:');
	Irssi::print('%G>>%n xir_show_privmsg : Notify about private messages.');
	Irssi::print('%G>>%n xir_show_hilight : Notify when your name is hilighted.');
	Irssi::print('%G>>%n xir_show_notify : Notify when someone on your away list joins or leaves.');
	Irssi::print('%G>>%n xir_notify_user : Set to xmpp account to send from.');
	Irssi::print('%G>>%n xir_notify_recv : Set to xmpp account to receive message.');;
	Irssi::print('%G>>%n xir_notify_server : Set to the xmpp server host name');
    Irssi::print('%G>>%n xir_notify_port : Set to xmpp server port');
	Irssi::print('%G>>%n xir_notify_pass : Set to the sending accounts jabber password');
    Irssi::print('%G>>%n xir_notify_delay : Wait x seconds since last console interaction before notifying via xmpp');
	Irssi::print('%G>>%n xir_debug : Display verbose debugging messages');
	Irssi::print('%G>>%n The following commands expose xmpp-rpc functionality:');
    Irssi::print('%G>>%n /xir-monitor [<chan>] <notify_timeout> : start monitoring <chan>');
    Irssi::print('%G>>%n /xir-unmonitor [<chan>] : stop monitoring <chan>');
    Irssi::print('%G>>%n /xir-status : show current connections and settings');
    Irssi::print('%G>>%n /xir-reload : pull in new settings and reconnect');
    Irssi::print('%G>>%n /xir-disconnect');
    Irssi::print('%G>>%n /xir-connect');
    Irssi::print('%G>>%n /xir-reconnect');
}
sub cmd_xir_notify_test {
    $last_cli_interaction = 0;
    send_xmpp("XiRPC notify test");
} 
sub cmd_xir_disconnect {
    if ($connected) {
        $Client->disconnect("user terminated connection");
    }
}
sub cmd_xir_connect {
    if (!$connected) {
        $Client->start;
    }
}
sub cmd_xir_reconnect {
    cmd_xir_disconnect();
    cmd_xir_connect();
}
sub cmb_xir_mute {
    my ($data, $server, $witem) = @_;
    shared_xir_mute($data);
}
sub cmd_xir_unmute {
    $muted = -1;
}
sub cmd_xir_status {
    Irssi:print("xir_debug = " . $DEBUG);
    Irssi:print("xir_notify_user = " . $XMPPUser);
    Irssi:print("xir_notify_server = " . $XMPPServ);
    Irssi:print("xir_notify_port = " . $XMPPPort);
    Irssi:print("xir_notify_recv = " . $XMPPRecv);
    Irssi:print("xir_show_hilight = " . Irssi::settings_get_bool('xir_show_hilight'));
    Irssi:print("xir_show_privmsg = " . Irssi::settings_get_bool('xir_show_privmsg'));
    Irssi:print("xir_show_notify = " . Irssi::settings_get_bool('xir_show_notify'));
    Irssi:print("monitored channels: ");
    foreach (keys %monitored_channels) {
        Irssi:print("  $_ " . $monitored_channels{$_}{'notify_timeout'});
    }
    if ($muted == 0 or $muted > time) {
        Irssi:print("%R -- MUTED -- %n");
    }
    my (@accounts) = $Client->get_accounts();
    for my $acct (@accounts)
    {
        my $ct_str = "%RDisconnected%n";
        if ($acct->is_connected()) {
            $ct_str = "%GCONNECTED%n";
        }
        Irssi:print("%G>>%n " . $acct->jid() . " $ct_str");
    }
}
sub cmd_xir_reload {
    if ($connected) {
        cmd_xir_disconnect();
    }
    load_settings();
    cmd_xir_connect();
}
sub cmd_xir_monitor {
    my ($data, $server, $witem) = @_;
    my $channel = "";
    my $notify_timeout = 0;

    if ($witem && $witem->{type} eq "CHANNEL") {
        $channel = $witem->{name};
    }
    if ($DEBUG) {
        Irssi:print("xir-monitor data=" . $data);
    }
    if ($data) {
        my @data_items = split(" ", $data);
        if ($#data_items == 1) {
            $channel = $data_items[0];
            $notify_timeout = $data_items[1];
        } elsif ($#data_items == 0) {
            $notify_timeout = $data_items[0];
        }
    }
    if ($channel ne "" and $notify_timeout > 0) {
        my ($success, $msg) = shared_xir_monitor($channel, $notify_timeout);
        Irssi::print("%G>>%n $msg");
    } else {
        Irssi::print("Usage: /xir-monitor [<chan>] <notify_timeout>");        
    }
}
sub cmd_xir_unmonitor {
    my ($data, $server, $witem) = @_;
    my $channel = "";

    if ($witem && $witem->{type} eq "CHANNEL") {
        $channel = $witem->{name};
    }
    if ($DEBUG) {
        Irssi:print("xir-unmonitor data=" . $data);
    }
    if ($data) {
        $channel = $data;
    }
    if ($channel ne "") {
        my ($success, $msg) = shared_xir_unmonitor($channel);
        Irssi::print("%G>>%n $msg");
    }
}

#######################################
###     XMPP IN/OUT                 ###
#######################################
sub send_xmpp {
    my ($msg, $rcpt) = @_;
    return if ($muted == 0 or $muted > time);
    return if (time - $last_cli_interaction < Irssi::settings_get_int('xir_notify_delay'));

    if (!$connected) {
        Irssi:print("%G>>%n Not connected to XMPP server, try /xmpp-connect");
        return 0;
    }

    if (!$rcpt) {
        $rcpt = $XMPPRecv;
    }
    if (!$msg) {
        $msg = "";
    }
    if ($DEBUG) {
        Irssi:print("OUT >$rcpt> $msg");
    }
    $Client->send_message($msg => $rcpt, undef, 'chat');

    return 1;
}

sub evt_incoming_xmpp ($) {
    my ($msg) = @_;
    if ($DEBUG) {
        Irssi:print("IN  <" . $msg->from . "> " . $msg->any_body);
    }
    my ($user, $loc) = split("/", $msg->from);
    if ($user ne $XMPPRecv)
    {
        Irssi:print "Err: received command from $user, ignoring";
        return;
    }
    my $success = 1;
    my $outmsg = "";
    my $body = $msg->any_body;
    if ($body =~ /^(#\S+)\s(.*)$/i) {
        my $channel = $1;
        my $inmsg = $2;
        ($success, $outmsg) = evt_xmpp_channel_message($channel, $inmsg);
    } elsif ($body =~ /^\/msg\s(\S+)\s(.*)$/i) {
        my $to = $1;
        my $inmsg = $2;
        ($success, $outmsg) = evt_xmpp_private_message($to, $inmsg);
    } elsif ($body =~ /^\/?help/i) {
        send_xmpp($usage, $msg->from);
    } elsif ($body =~ /\/mute\s([0-9]+)?/i) {
        shared_xir_mute($1);
    } elsif ($body =~ /\/unmute/i) {
        cmd_xir_unmute();
    } elsif ($body =~ /\/monitor\s(\S+)\s([0-9]+)?$/i) {
        ($success, $outmsg) = shared_xir_monitor($1, $2);
    } elsif ($body =~ /\/unmonitor\s(\S+)$/i) {
        shared_xir_unmonitor($1);
    } else {
        $success = 0;
        $outmsg = "command is not recognized";
    }
    # send a response if one was generated
    if ($outmsg ne "")
    {
        send_xmpp($outmsg, $msg->from);
    }
}
sub evt_xmpp_channel_message ($$) {
    my ($channel, $inmsg) = @_;
    if (exists $monitored_channels{$channel})
    {
        # deliver the message
        my $fchan = Irssi::channel_find($channel);
        if ($fchan) {
            my $server = $fchan->{server};
            $server->send_message($channel, $inmsg, 0);
            $monitored_channels{$channel}{'last_interaction'} = time;
            return (1, "");
        } else {
            return (0, "not joined to $channel");
        }
    } else {
        return (0, "requested channel is not monitored: $channel");
    }

}
sub evt_xmpp_private_message ($$) {
    my ($to, $inmsg) = @_;

    my $cb = sub {
        if ($_->[0]) {
            my ($status, $n, $server) = @_;
            $server->send_message($to, $inmsg, 1);
        } else {
            send_xmpp($_->[1]);
        }
    };

    my $server = $nick_cache{$to};
    if (!$server) {
        # do a whois on each connected server to find the user
        find_nick($to, $cb);
    } else {
        # activate the callback with the cached server
        $cb->(1, $to, $server);
    }
    return (1, "");
}
sub find_nick ($$) {
    my ($nick, $cb) = @_;
    if ($whocvs{$nick})
    {
        $whocvs{$nick}{cv}->cb ($cb);
        return;
    }
    my %wwait = { };
    $wwait{cv} = AnyEvent->condvar;
    $wwait{wc} = 0;
    $whocvs{$nick} = \%wwait;
    my $timer = AnyEvent->timer (after => 5, cb => sub {
        $wwait{cv}->send(0, "timed out waiting for servers")
    });
    $wwait{cv}->cb (sub {
        undef $timer;
        my @info = shift->recv;;
        $cb->(@info);
        delete $whocvs{$nick};
    });
    foreach (Irssi::servers()) {
        $wwait{wc}++;
        $_->command("WHOIS $nick");
    }
}

#######################################
###     IRSSI SIGNALS               ###
#######################################
sub sig_message_public ($$$$$) {
    my ($server, $data, $nick, $address, $target) = @_;
    return unless (exists $monitored_channels{$target});

    my $ownnick = $server->{nick};
    my $interact_interval = 0;
    if ($data =~ /$ownnick/) {
        # this message mentions us
        $monitored_channels{$target}{'last_interaction'} = time;
        if ($DEBUG) {
            Irssi:print("DEBUG: we got mentioned in $target");
        }
    } else {
        $interact_interval = time - $monitored_channels{$target}{'last_interaction'};
    }
    my $notify_timeout = $monitored_channels{$target}{'notify_timeout'};
    if ($interact_interval < $notify_timeout) {
        send_xmpp("[$target] < $nick> $data");
    } else {
        if ($DEBUG) {
            Irssi:print("DEBUG: skipping message in $target because notify_timeout ($notify_timeout) has been exceeded: $interact_interval");
        }
    }
}

sub sig_message_private ($$$$) {
	return unless Irssi::settings_get_bool('xir_show_privmsg');
	my ($server, $data, $nick, $address) = @_;
    $nick_cache{$nick} = $server;
    send_xmpp("[pm] < $nick> $data");
}

sub sig_print_text ($$$) {
	return unless Irssi::settings_get_bool('xir_show_hilight');

	my ($dest, $text, $stripped) = @_;
	
	if ($dest->{level} & MSGLEVEL_HILIGHT) {	
        my $body = '['.$dest->{target}.'] '.$stripped;
        send_xmpp($body);
	}
}

sub sig_notify_joined ($$$$$$) {
	return unless Irssi::settings_get_bool('xir_show_notify');
	
	my ($server, $nick, $user, $host, $realname, $away) = @_;
	
    my $body = "<$nick!$user\@$host>\nHas joined $server->{chatnet}";
    send_xmpp($body);
}

sub sig_notify_left ($$$$$$) {
	return unless Irssi::settings_get_bool('xir_show_notify');
	
	my ($server, $nick, $user, $host, $realname, $away) = @_;
	
    my $body = "<$nick!$user\@$host>\nHas left $server->{chatnet}";
    send_xmpp($body);
}
sub sig_gui_key_pressed ($) {
    $last_cli_interaction = time;
}
sub sig_whois_response ($$$) {
    my ($server, $data, $server_name) = @_;
    my ($me, $n, $u, $h) = split(" ", $data);
    if ($DEBUG) {
        Irssi:print("sig_whois_response: $me, $n, $u, $h, " . $server->{tag});
    }

    $nick_cache{$n} = $server;
    if ($whocvs{$n}) {
        $whocvs{$n}->{cv}->send(1, ($n, $server));
    }
}
sub sig_whois_unknown ($$) {
    my ($server, $data) = @_;
    my ($me, $n, $ss) = split(" ", $data);
    if ($DEBUG) {
        Irssi:print("sig_whois_unknown: $n, " . $server->{tag});
    }

    if ($whocvs{$n}) {
        $whocvs{$n}->{wc}--;
        if ($whocvs{$n}->{wc} <= 0)
        {
            $whocvs{$n}->{cv}->send(0, "no such nick found");
        }
    }
}
sub sig_whois_end ($$) {
    my ($server, $data) = @_;
    my ($me, $n, $ss) = split(" ", $data);
    if ($nick_cache{$n}->{tag} eq $server->{tag}) {
        # nick was found and cached, we good
        return;
    } else {
        sig_whois_unknown($server, $data);
    }
}

#######################################
###     INITIALIZATION              ###
#######################################
Irssi::command_bind('xir-test', 'cmd_xir_notify_test');
Irssi::command_bind('xirpc', 'cmd_xirpc');
Irssi::command_bind('xir-connect', 'cmd_xir_connect');
Irssi::command_bind('xir-disconnect', 'cmd_xir_disconnect');
Irssi::command_bind('xir-reconnect', 'cmd_xir_reconnect');
Irssi::command_bind('xir-status', 'cmd_xir_status');
Irssi::command_bind('xir-reload', 'cmd_xir_reload');
Irssi::command_bind('xir-monitor', 'cmd_xir_monitor');
Irssi::command_bind('xir-unmonitor', 'cmd_xir_unmonitor');

Irssi::signal_add_last('message public', \&sig_message_public);
Irssi::signal_add_last('message private', \&sig_message_private);
Irssi::signal_add_last('print text', \&sig_print_text);
Irssi::signal_add_last('notifylist joined', \&sig_notify_joined);
Irssi::signal_add_last('notifylist left', \&sig_notify_left);
Irssi::signal_add_last('gui key pressed', \&sig_gui_key_pressed);
Irssi::signal_add('event 311', \&sig_whois_response);
Irssi::signal_add('event 401', \&sig_whois_unknown);
Irssi::signal_add('event 318', \&sig_whois_end);

create_settings();
load_settings();
thaw_monitored_channels();
$Client->start;

Irssi::print('%G>>%n '.$IRSSI{name}.' '.$VERSION.' loaded (/xirpc for help. /xir-test to test.)');