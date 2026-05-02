use strict;
use warnings;
use Irssi;
use JSON::PP;

our $VERSION = '0.1';
our %IRSSI = (
    authors     => 'brad',
    name        => 'np',
    description => 'Now-playing /np reading ~/.nowplaying.json (written by npd)',
    license     => 'ISC',
);

my $PATH = "$ENV{HOME}/.nowplaying.json";
my $B    = "\x02";

sub cmd_np {
    my ($data, $server, $witem) = @_;

    unless ($server && $witem) {
        Irssi::print('np: not in a channel or query');
        return;
    }

    my $fh;
    unless (open $fh, '<', $PATH) {
        $witem->print("np: can't read $PATH ($!)");
        return;
    }
    local $/;
    my $raw = <$fh>;
    close $fh;

    my $j = eval { decode_json($raw) };
    if ($@ || ref $j ne 'HASH') {
        $witem->print('np: bad json in ' . $PATH);
        return;
    }

    my $state = $j->{state} // '';
    if ($state ne 'playing' && $state ne 'paused') {
        $witem->print('np: nothing playing');
        return;
    }

    my $title  = $j->{title}  // '?';
    my $artist = $j->{artist} // '?';
    my $album  = $j->{album}  // '?';

    my $msg = sprintf(
        'is listening to %s"%s"%s by %s%s%s from %s%s%s',
        $B, $title,  $B,
        $B, $artist, $B,
        $B, $album,  $B,
    );

    $witem->command("me $msg");
}

Irssi::command_bind('np', \&cmd_np);
Irssi::print('np.pl loaded; /np reads ' . $PATH);
