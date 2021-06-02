#!/usr/bin/env perl
use v5.26;
use utf8;
use feature 'signatures';

use Twitter::API;
use YAML ();
use Encode ('encode_utf8');
use Getopt::Long ('GetOptionsFromArray');
use Mojo::UserAgent;

sub main {
    my @args = @_;

    my %opts;
    GetOptionsFromArray(
        \@args,
        \%opts,
        'c=s',
        'y|yes'
    ) or die("Error in arguments, but I'm not telling you what it is.");

    my $msg = build_message();
    maybe_tweet_update(\%opts, $msg);

    return 0;
}

exit(main(@ARGV));

sub build_message {

    my $maxer = ["", -1];
    my $hbars = "";
    my $legend = "";
    for my $it (reservoir_usage_percentage()) {
        if ($maxer->[1] < $it->[1]) {
            $maxer = $it;
        }
        $hbars .= hbar(100 * $it->[1]);
        $legend .= substr($it->[0], 0, 1);
    }

    return $hbars . "\n" . $legend . "\n\n" . $maxer->[0] . ": " . int(100 * $maxer->[1]) . "%";
}

sub hbar($n) {
    return undef unless defined $n;
    my @hbars = split "", "▁▂▃▃▅▅▆▆▇▇"; # 10 chars
    # my @hbars = ('▁','▂','▃','▄','▅','▆','▇','█');
    my $b = int($n / @hbars);
    $b = $#hbars if $b > $#hbars;
    $b = 0 if $b < 0;
    return $hbars[$b];
}

sub reservoir_usage_percentage {
    my $d = usage_percentage();

    my %reservoir_by_name = map { $_->{"ReservoirName"} => $_ } grep { $_->{"ReservoirName"} } values %$d;

    # The names/order taken from: https://ioi.tw/reservoir/
    # my @names = qw(牡丹水庫 阿公店水庫 南化水庫 烏山頭水庫 曾文水庫 白河水庫 仁義潭水庫 蘭潭水庫 湖山水庫 日月潭水庫 霧社水庫 德基水庫 石岡壩 鯉魚潭水庫 明德水庫 永和山水庫 寶山第二水庫 寶山水庫 石門水庫 翡翠水庫 新山水庫);

    # Top 15 by their EffectiveCapacity
    my @names = qw(牡丹水庫 阿公店水庫 南化水庫 烏山頭水庫 曾文水庫  仁義潭水庫 湖山水庫 日月潭水庫 霧社水庫 德基水庫 鯉魚潭水庫 永和山水庫 寶山第二水庫 石門水庫 翡翠水庫 );

    # my @names = grep { /水庫/ } keys %reservoir_by_name;
    # my @top10_south_to_north = qw( 牡丹水庫 南化水庫 烏山頭水庫 曾文水庫 霧社水庫 日月潭水庫 鯉魚潭水庫 德基水庫 石門水庫 翡翠水庫 );

    return map { [ $_, $reservoir_by_name{$_}{"UsagePercentage"} // 0 ] } @names;
}

sub maybe_tweet_update ($opts, $msg) {
    unless ($msg) {
        say "# Message is empty.";
        return;
    }

    my $config;

    if ($opts->{c} && -f $opts->{c}) {
        say "[INFO] Loading config from $opts->{c}";
        $config = YAML::LoadFile( $opts->{c} );
    } elsif ($opts->{'github-secret'} && $ENV{'TWITTER_TOKENS'}) {
        say "[INFO] Loading config from env";
        $config = YAML::Load($ENV{'TWITTER_TOKENS'});
    } else {
        say "[INFO] No config.";
    }

    say "# Message";
    say "-------8<---------";
    say encode_utf8($msg);
    say "------->8---------";

    if ($opts->{y} && $config) {
        say "#=> Tweet for real";
        my $twitter = Twitter::API->new_with_traits(
            traits => "Enchilada",
            consumer_key        => $config->{consumer_key},
            consumer_secret     => $config->{consumer_secret},
            access_token        => $config->{access_token},
            access_token_secret => $config->{access_token_secret},
        );

        my $r = $twitter->update($msg);
        say "https://twitter.com/TWReservoir_bot/status/" . $r->{id_str};
    } else {
        say "#=> Not tweeting";
    }
}

sub basic {
    # 水庫每日營運狀況 https://data.gov.tw/dataset/41568
    my $ua = Mojo::UserAgent->new;
    my $res = $ua->insecure(1)->get('https://data.wra.gov.tw/Service/OpenData.aspx?format=json&id=50C8256D-30C5-4B8D-9B84-2E14D5C6DF71')->result;
    die "Failed to retrieve the daily operational statistics." if $res->is_error;

    my $rows = $res->json->{"DailyOperationalStatisticsOfReservoirs_OPENDATA"};
    my %d = map { $_->{"ReservoirIdentifier"} => $_ } @$rows;
    return \%d;
}

sub current {
    # 水庫水情資料 https://data.gov.tw/dataset/45501
    my $ua = Mojo::UserAgent->new;
    my $res = $ua->insecure(1)->get('https://data.wra.gov.tw/Service/OpenData.aspx?format=json&id=1602CA19-B224-4CC3-AA31-11B1B124530F')->result;
    die "Failed to retrieve the condition data" if $res->is_error;

    my $rows = $res->json->{"ReservoirConditionData_OPENDATA"};
    my %d = map { $_->{"ReservoirIdentifier"} => $_ } @$rows;
    return \%d;
}

sub usage_percentage {
    my $d1 = current();
    my $d2 = basic();

    my $d3 = {};
    for my $id (keys %$d1) {
        my $d = $d3->{$id} = {};
        $d->{$_} = $d2->{$id}{$_} for qw(ReservoirIdentifier ReservoirName EffectiveCapacity RecordTime);
        $d->{$_} = $d1->{$id}{$_} for qw(EffectiveWaterStorageCapacity ObservationTime);

        if ( $d->{"EffectiveCapacity"} && $d->{"EffectiveWaterStorageCapacity"}) {
            $d->{"UsagePercentage"} = $d->{"EffectiveWaterStorageCapacity"} / $d->{"EffectiveCapacity"};
        }
    }

    return $d3;
}
