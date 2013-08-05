#!/usr/bin/perl

################################################################################
# Migeon Cyril                                                                                                                         #
# 2013/08/03						                                                                     #
#                                                                                                                                            #
# Mail alerter for http://www.leboncoin.fr when the price is lower than the one specified in the       #
# search. When a match is found a mail is sent from a gmail account.			                 #
################################################################################

use strict;
use Getopt::Std;
use Scalar::Util qw(looks_like_number);
use warnings;
use WWW::Curl::Easy;
use Email::Send;
use Email::Send::Gmail;
use Email::Simple::Creator;

sub usage()
{
  print STDERR <<EOF;
Mail alerter for http://www.leboncoin.fr when the price is lower than the one specified in the search. When a match is found a mail is sent from a gmail account.

usage: $0 [-h] [-r region] [-s search] [-P price] [-m mail] [-p password] [-S smtp]
  -h	      : this (help) message
  -r region   : region (mandatory)
  -s search   : your search, object you are looking for (mandatory)
  -P price    :  price line (mandatory)
  -m mail     : address mail alert (mandatory)
  -g gmail    : gmail address (mandatory)
  -p gmailPassword : mail password for the smtp connection (mandatory)
EOF
    exit;
}

my %options=();
getopts("r:s:P:m:p:g:h", \%options);

usage() if $options{h} || !defined($options{r}) || !defined($options{s})  || !defined($options{P})  || !defined($options{m})  || !defined($options{p})	|| !defined($options{g});

my $url = 'http://www.leboncoin.fr/telephonie/offres/';
my $region =$options{r};
my $mandatory = '/?f=a&th=1&q=';
my $search = $options{s};
my $price = $options{P};
my $mail = $options{m};
my $password = $options{p};
my $gmail = $options{g};
my $stmpAddress = 'smtp.gmail.com';

# Check parameters
unless($mail=~m/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,4}/i && $gmail=~m/[A-Z0-9._%+-]+\@gmail\.com/i && looks_like_number($price))
{
    usage();
}

# Search substitution
$search =~ s/ /+/g;

# Get all results
 my $curl = WWW::Curl::Easy->new;
 my $response_body;

$curl->setopt(CURLOPT_HEADER,1);
$curl->setopt(CURLOPT_URL, $url.$region.$mandatory.$search);
$curl->setopt(CURLOPT_WRITEDATA,\$response_body);
my $retcode = $curl->perform;

unless($retcode == 0)
{
    die("An error happened: $retcode ".$curl->strerror($retcode)." ".$curl->errbuf."\n");
}

my @resultsList = split(/class="lbc">/, $response_body);
foreach(@resultsList)
{
    $_ =~ s/\R//g;
    if( $_=~m/class="price"\>(.*)&nbsp;&euro/)
    {
        my $priceResult = $1;
        $priceResult =~ s/\R//g;
        $priceResult =~ s/^\s+|\s+$//g;
        if($priceResult < $price)
        {
            # Get the url of the description
            if( $_=~m/class="title"\>(.*)\<\/div\>.*\<div class="category"/)
            {
                my $title = $1;
                $title =~ s/^\s+|\s+$//g;
                if($response_body=~m/href="(.*)" title="\Q$title"/)
                {
                    my $descriptionUrl = $1;
                    my $description_body = '';
                    my $vendor = '';
                    my $city = '';
                    my $zipcode = '';
                    my $descriptionContent = '';
                    my $mailContent = '';

                    $curl->setopt(CURLOPT_URL, $descriptionUrl);
                    $curl->setopt(CURLOPT_WRITEDATA,\$description_body);
                    $retcode = $curl->perform;

                    unless($retcode == 0)
                    {
                        die("An error happened: $retcode ".$curl->strerror($retcode)." ".$curl->errbuf."\n");
                    }

                    $description_body =~ s/\R//g;

                    if($description_body =~ m/margin-right: 5px;"\>(.*)&nbsp;:/)
                    {
                        $vendor = $1;
                    }

                    if($description_body =~ m/Ville :\<\/th\>.*\<td\>(.*)\<\/td.*Code/)
                    {
                        $city = $1;
                    }

                    if($description_body =~ m/Code postal :\<\/th\>.*\<td\>(.*)\<\/td\>/)
                    {
                        $zipcode = $1;
                    }

                    if($description_body =~ m/Description :.*content"\>(.*)\<\/div\>\<\/div\>.*\<\/div\>\<div class="clear"/)
                    {
                        $descriptionContent = $1;
                        $descriptionContent =~ s/^\s+|\s+$//g;
                        $descriptionContent =~ s/\R//g;
                        $descriptionContent =~ s/\<br\>/\\n/g;
                    }

                    $mailContent = "Vendeur : $vendor\n";
                    $mailContent .= "Prix : $priceResult\n";
                    $mailContent .= "Ville : $city\n";
                    $mailContent .= "Code postal : $zipcode\n";
                    $mailContent .= "Description : $descriptionContent\n";
                    $mailContent .= "Url de l'annonce :  $descriptionUrl\n";

                    my $email = Email::Simple->create(
                        header => [
                              From    => $gmail,
                              To      => $mail,
                              Subject => '[Alert-LeBonCoin] '.$title,
                          ],
                        body => $mailContent,
                      );

                      my $sender = Email::Send->new(
                          {   mailer      => 'Gmail',
                              mailer_args => [
                                  username => $gmail,
                                  password => $password,
                              ]
                          }
                      );
                    eval { $sender->send($email) };
                    die "Error sending email: $@" if $@;
                }
            }
        }
    }
}
