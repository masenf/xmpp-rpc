#!/usr/bin/env perl -w
#
# This is an irssi script to test xmpp-rpc.pl
# requires AnyEvent::XMPP::Client
#          AnyEvent::IRC::Client

# use:
# start irssi, connect to public irc server suitable for testing (freenode?)
# /load xmpp-rpc.pl
# do any configuration to get xmpp-rpc.pl connected to xmpp server, etc
# /load xmpp-rpc-test.pl
# /xir-run-tests

# Please report issues on the project github page
# http://github.com/masenf/xmpp-rpc

use strict;
use warnings;
use vars qw($VERSION %IRSSI $IRCClient $XMPPClient $irc_public $irc_private $xmpp_msg $clients_ready $running);
use utf8;
 
use AnyEvent;
use AnyEvent::IRC::Client;
use AnyEvent::XMPP::Client;
use Encode;
use Data::Dumper;
 
$VERSION = '0.0.4dev';
%IRSSI = (
	authors		=>	'Masen Furer, based on jabber-notify.pl script by Peter Krenesky, ' .
                    'Based on growl-net.pl script by Alex Mason, Jason Adams' .
                    'Based on the growl.pl script from Growl.info by Nelson Elhage)',
	contact		=>	'mf@0x26.net, masen on irc.freenode.net',
	name		=>	'XiRPC-test',
	description	=>	'XMPP irssi RPC server test cases',
	license		=>	'BSD',
	url			=>	'http://github.com/masenf/xmpp-rpc'
);

my $opt = { "nick" => "",       # will be dynamically generated during init
            "channel" => "",    # will be dynamically generated during init
            "server" => "",     # will be determined during init
            "port" => 6667,
            "user" => "xmpp-rpc-test",
            "real" => "xmpp-rpc-test.pl",
            "charset" => "utf-8" };
my $results = { "total" => 0,
                "ok" => 0,
                "fail" => 0,
                "registered" => 0 };
my @test_queue = ( );
$clients_ready = 0;
$running = 0;

sub connect_irc {
    my ($irc, $data) = @_;
    my $opt = {};
    for my $key (qw/password nick real user/) {
        next if !defined $data->{$key};
        $opt->{$key} = $data->{$key};
    }
    $irc->connect( $data->{server}, $data->{port}, $opt );
}
sub test_setup {
    if ($running) {
        Irssi:print("Test cases already running, try /xir-stop-tests");
        return;
    }
    $running = 1;
    $clients_ready = 0;

    my $active_server = Irssi::active_server();
    if (!defined $active_server) {
        Irssi:print("ERROR: connect to an IRC server suitable for testing first");
        return
    }

    # get configuration values from environment
    $opt->{nick} = "xmpp-test-" . int(rand(5000));
    $opt->{channel} = "#xmpp-tchan-" . int(rand(5000));
    $opt->{nick_target} = Irssi::active_server()->{nick};
    $opt->{server} = Irssi::active_server()->{address};
    $opt->{port} = Irssi::active_server()->{port};

    $opt->{xmpp_target} = Irssi::settings_get_str('xir_notify_user');
    $opt->{xmpp_user} = Irssi::settings_get_str('xir_notify_recv');
    $opt->{xmpp_serv} = Irssi::settings_get_str('xir_notify_server');
    $opt->{xmpp_port} = Irssi::settings_get_str('xir_notify_port');
    $opt->{xmpp_pass} = Irssi::settings_get_str('xir_test_xmpp_pass');

    if ($opt->{xmpp_target} eq "") {
        Irssi:print("ERROR: please load and configure xmpp-rpc.pl first");
        return;
    }
    if ($opt->{xmpp_pass} eq "") {
        Irssi:print("ERROR: specify a password for " . $opt->{xmpp_user} . " with /SET xir_test_xmpp_pass <password>");
        return;
    }

    # tell irssi to join the channel first
    Irssi::Server::channels_join(Irssi::active_server(), $opt->{channel}, 1);

    $IRCClient = AnyEvent::IRC::Client->new();
    $IRCClient->reg_cb(
        connect => sub {
                my ($irc, $error) = @_;
                if ( defined $error ) {
                    warn "Can't connect: $error";            
                }
        },
        registered => sub {
                Irssi:print("IRC: Registered connection to " . $_[0]->{host});
                $IRCClient->send_srv( JOIN => $opt->{channel} ) if $opt->{channel};
                $clients_ready += 1;
                start_tests();
        },
        publicmsg => sub {
            my ($irc, $channel, $msg) = @_;
            my $comment = decode($opt->{charset}, $msg->{params}->[1]);
            my ($username) = $msg->{prefix} =~ /^(\S+?)!/;
            Irssi:print("DEBUG: received irc public message: $channel $username $comment");
            if (defined $irc_public) {
                &{ $irc_public }($channel, $username, $comment);
            }
        },
        privatemsg => sub {
            my ($irc, $nick, $msg) = @_;
            my $comment = decode($opt->{charset}, $msg->{params}->[1]);
            my $username = "";
            if ($msg->{prefix} =~ /^(\S+?)(!|$)/)
            {
                $username = $1;
            }
            Irssi:print("DEBUG: received irc private message: ($username) $comment");
            if (defined $irc_private) {
                &{ $irc_private }($username, $comment);
            }
        },
        disconnect => sub {
            my ($irc, $msg) = @_;
            Irssi:print("IRC: Disconnected from " . $irc->{host} . ": $msg");
            $clients_ready -= 1;
        },
        error => sub {
            my ($code, $msg, $ircmsg) = @_;
            Irssi:print("ERROR $code: IRC client got error: $msg ($ircmsg)");
        }
    );
    connect_irc($IRCClient, $opt);

    $XMPPClient = AnyEvent::XMPP::Client->new (debug => 0);
    Irssi:print("XMPPUser = ". $opt->{xmpp_user});
    $XMPPClient->add_account($opt->{xmpp_user}, $opt->{xmpp_pass}, $opt->{xmpp_serv}, $opt->{xmpp_port});
    $XMPPClient->reg_cb (
        session_ready => sub {
            my ($cl, $acc) = @_;
            Irssi:print ("XMPP: Logged into server " . $opt->{xmpp_serv} . " as " . $opt->{xmpp_user} . ". Ready.");
            $clients_ready += 1;
            start_tests();
        },
        disconnect => sub {
            my ($cl, $acc, $h, $p, $reas) = @_;
            Irssi:print ("XMPP: Disconnected from ($h:$p): $reas");
            $clients_ready -= 1;
        },
        error => sub {
            my ($cl, $acc, $err) = @_;
            Irssi:print ("ERROR: " . $err->string );
        },
        message => sub {
            my ($cl, $acc, $msg) = @_;
            Irssi:print("DEBUG: received private message: $msg");
            if (defined $xmpp_msg) {
                &{ $xmpp_msg }($msg);
            }
        });
    $XMPPClient->start;
}
##############
### TEST CASES
##############
sub test_priv_msg_notify {
    my $summary = "Receive XMPP notification for private message in irssi";
    my $msgbody = "test privmsg notify";
    my $ownnick = $opt->{nick};
    my $target_nick = $opt->{nick_target};
    my $prev_setting = Irssi::settings_get_bool('xir_show_privmsg');
    Irssi::settings_set_bool('xir_show_privmsg', 1);
    my $testcv = AnyEvent->condvar;
    my $timer = AnyEvent->timer (after => 10, cb => sub {
        $testcv->send(0, "Timed out")
    });
    $testcv->cb (sub {
        undef $timer;
        Irssi::settings_set_bool('xir_show_privmsg', $prev_setting);
        my ($success, $msg) = $_[0]->recv;       # wait for results
        finish_test($success, $msg, $summary);
    });
    $xmpp_msg = sub {
        my $msg = shift;
        if ($msg =~ /\[pm\] < $ownnick> $msgbody/)
        {
            $testcv->send(1, "Message received");
        } else {
            $testcv->send(0, "Message didn't match regex: $msg");
        }
    };
    $IRCClient->send_srv(PRIVMSG => $target_nick, $msgbody);
}
sub test_priv_msg_notify_disabled {
    my $summary = "(Disabled) Receive XMPP notification for private message in irssi";
    my $msgbody = "test privmsg notify disabled";
    my $ownnick = $opt->{nick};
    my $target_nick = $opt->{nick_target};
    my $prev_setting = Irssi::settings_get_bool('xir_show_privmsg');
    Irssi::settings_set_bool('xir_show_privmsg', 0);
    my $testcv = AnyEvent->condvar;
    my $timer = AnyEvent->timer (after => 10, cb => sub {
        $testcv->send(1, "No Message received")
    });
    $testcv->cb (sub {
        undef $timer;
        Irssi::settings_set_bool('xir_show_privmsg', $prev_setting);
        my ($success, $msg) = $_[0]->recv;       # wait for results
        finish_test($success, $msg, $summary);
    });
    $xmpp_msg = sub {
        my $msg = shift;
        if ($msg =~ /\[pm\] < $ownnick> $msgbody/)
        {
            $testcv->send(0, "Message received when setting disabled");
        } else {
            $testcv->send(0, "Message didn't match regex: $msg");
        }
    };
    $IRCClient->send_srv(PRIVMSG => $target_nick, $msgbody);
}
sub test_priv_msg_relay {
    my $summary = "Relay private messages from XMPP to irc user";
    my $msgbody = "test privmsg relay";
    my $ownnick = $opt->{nick};
    my $target_nick = $opt->{nick_target};
    my $target_xmpp = $opt->{xmpp_target};
    my $testcv = AnyEvent->condvar;
    my $timer = AnyEvent->timer (after => 10, cb => sub {
        $testcv->send(0, "Timed out")
    });
    $testcv->cb (sub {
        undef $timer;
        my ($success, $msg) = $_[0]->recv;       # wait for results
        finish_test($success, $msg, $summary);
    });
    $irc_private = sub {
        my ($nick, $msg) = @_;
        if ($nick !~ /^$target_nick$/) {
            $testcv->send(0, "Nick didn't match: $nick != $target_nick");
        } elsif($msg !~ /^$msgbody$/) {
            $testcv->send(0, "Message didn't match regex: \"$msg\" != \"$msgbody\"");
        } else {
            $testcv->send(1, "Message received");
        }
    };
    Irssi:print("DEBUG: sending xmpp message to $target_xmpp");
    $XMPPClient->send_message("/msg $ownnick $msgbody" => $target_xmpp, undef, 'chat');
}
sub test_public_msg_hilight {
    my $summary = "Notify via XMPP on hilighted message";
    my $ownnick = $opt->{nick};
    my $target_nick = $opt->{nick_target};
    my $target_xmpp = $opt->{xmpp_target};
    my $msgbody = "$target_nick: test publicmsg hilight";
    my $prev_setting = Irssi::settings_get_bool('xir_show_hilight');
    Irssi::settings_set_bool('xir_show_hilight', 1);
    my $testcv = AnyEvent->condvar;
    my $timer = AnyEvent->timer (after => 10, cb => sub {
        $testcv->send(0, "Timed out")
    });
    $testcv->cb (sub {
        undef $timer;
        Irssi::settings_set_bool('xir_show_hilight', $prev_setting);
        my ($success, $msg) = $_[0]->recv;       # wait for results
        finish_test($success, $msg, $summary);
    });
    $xmpp_msg = sub {
        my $msg = shift;
        if ($msg =~ /\[$opt->{channel}\] < $ownnick> $msgbody/)
        {
            $testcv->send(1, "Message received");
        } else {
            $testcv->send(0, "Message didn't match regex: $msg");
        }
    };
    my $channel = $opt->{channel};
    $IRCClient->send_chan($channel, PRIVMSG => $channel, $msgbody);
}
sub test_public_msg_hilight_disabled {
    my $summary = "(Disabled) Notify via XMPP on hilighted message";
    my $ownnick = $opt->{nick};
    my $target_nick = $opt->{nick_target};
    my $target_xmpp = $opt->{xmpp_target};
    my $msgbody = "$target_nick: test publicmsg hilight disabled";
    my $prev_setting = Irssi::settings_get_bool('xir_show_hilight');
    Irssi::settings_set_bool('xir_show_hilight', 0);
    my $testcv = AnyEvent->condvar;
    my $timer = AnyEvent->timer (after => 10, cb => sub {
        $testcv->send(1, "No Message Received")
    });
    $testcv->cb (sub {
        undef $timer;
        Irssi::settings_set_bool('xir_show_hilight', $prev_setting);
        my ($success, $msg) = $_[0]->recv;       # wait for results
        finish_test($success, $msg, $summary);
    });
    $xmpp_msg = sub {
        my $msg = shift;
        if ($msg =~ /\[$opt->{channel}\] < $ownnick> $msgbody/)
        {
            $testcv->send(0, "Message received when setting disabled");
        } else {
            $testcv->send(0, "Message didn't match regex: $msg");
        }
    };
    my $channel = $opt->{channel};
    $IRCClient->send_chan($channel, PRIVMSG => $channel, $msgbody);
}

################
### TEST HARNESS
################
sub start_tests {
    if ($clients_ready < 2) {
        Irssi:print("DEBUG: waiting for clients to initialize");
        return;
    }
    Irssi:print("Starting tests");
    make_test_set();
    $results->{registered} = @test_queue;
    $results->{ok} = 0;
    $results->{fail} = 0;
    $results->{total} = 0;
    next_test();
}
sub next_test {
    if ($running && @test_queue) {
        my $next_test = pop(@test_queue);
        # unregister old callbacks before next test
        undef $xmpp_msg;
        undef $irc_private;
        &{$next_test}();
    } else {
        finish_tests();
    }
}
sub finish_test {
    my ($success, $msg, $summary) = @_;
    Irssi:print("$success      $msg      ($summary)");
    $results->{total} += 1;
    if ($success) {
        $results->{ok} += 1;
    } else {
        $results->{fail} += 1;
    }
    next_test();
}
sub finish_tests {
    $running = 0;
    Irssi:print($results->{total} . " / " . $results->{registered} . " tests complete: " . 
                $results->{ok} . " ok, " .
                $results->{fail} . " failed.");
    $IRCClient->disconnect("tests complete");
    $XMPPClient->disconnect("tests complete");
    undef $IRCClient;
    undef $XMPPClient;
}
sub make_test_set {
    @test_queue = ( );
    push(@test_queue, \&test_priv_msg_notify_disabled);
    push(@test_queue, \&test_priv_msg_notify);
    push(@test_queue, \&test_priv_msg_relay);
    push(@test_queue, \&test_public_msg_hilight_disabled);
    push(@test_queue, \&test_public_msg_hilight);
}
sub request_test_stop {
    $running = 0;
    Irssi:print("Waiting for outstanding tests to finish...");
}
Irssi::command_bind('xir-run-tests', 'test_setup');
Irssi::command_bind('xir-stop-tests', 'request_test_stop');
Irssi::settings_add_str($IRSSI{'name'}, 'xir_test_xmpp_pass', 'password');