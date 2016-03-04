#!/usr/bin/perl
#
#  UniFi Miner 1.3.0
#
#  (C) Grigory Prigodin 2015-2016
#  Contact e-mail: zbx.sadman@gmail.com
# 
#
use strict;
use warnings;
use LWP ();
use POSIX ();
use JSON::XS ();
use Data::Dumper;
use Time::HiRes ('clock_gettime');

# uncomment for fix 'SSL23_GET_SERVER_HELLO:unknown' error
#use IO::Socket::SSL ();
#IO::Socket::SSL::set_default_context(new IO::Socket::SSL::SSL_Context(SSL_version => 'tlsv1', SSL_verify_mode => 0));

use constant {
     TOOL_HOMEPAGE => 'https://github.com/zbx-sadman/unifi_miner',
     TOOL_NAME => 'UniFi Miner',
     TOOL_VERSION => '1.3.1',

     # *** Actions ***
     ACT_MEDIAN => 'median',
     ACT_AMEAN => 'amean',
     ACT_GET => 'get',
     ACT_MAX => 'max',
     ACT_MIN => 'min',
     ACT_COUNT => 'count',
     ACT_DISCOVERY => 'discovery',
     ACT_PCOUNT => 'pcount',
     ACT_PSUM => 'psum',
     ACT_SUM => 'sum',

     # *** Controller versions ***
     CONTROLLER_VERSION_2 => 'v2',
     CONTROLLER_VERSION_3 => 'v3',
     CONTROLLER_VERSION_4 => 'v4',

     # *** Managed objects ***
     OBJ_HEALTH => 'health',
     OBJ_SYSINFO => 'sysinfo',
     OBJ_SETTING => 'setting',
     OBJ_NETWORK => 'network',
     OBJ_SITE => 'site',
     OBJ_UAP => 'uap',
     OBJ_UAP_VAP_TABLE => 'uap_vap_table',
     OBJ_UPH => 'uph',
     OBJ_EXTENSION => 'extension',
     OBJ_NUMBER => 'number',
     OBJ_USG => 'usg',
     OBJ_USER => 'user',
     OBJ_USERGROUP => 'usergroup',
     # Don't use object alluser with LLD - JSON may be broken due result size > 65535b (Max Zabbix buffer)
     OBJ_ALLUSER => 'alluser',
     OBJ_USW => 'usw',
     OBJ_USW_PORT_TABLE => 'usw_port_table',
     OBJ_WLAN => 'wlan',
     OBJ_WLANGROUP => 'wlangroup',

     # *** Debug levels ***
     DEBUG_LOW => 1,
     DEBUG_MID => 2,
     DEBUG_HIGH => 3,

     # *** other ***
     # Sitename which replaced {'sitename'} if '-s' option not used
     SITENAME_DEFAULT => 'default',

     MAX_BUFFER_LEN => 65536,
     MAX_REQUEST_LEN => 256,
     KEY_ITEMS_NUM => 'items_num',
     KEY_ANY => '*',
     TRUE => 1,
     FALSE => 0,
     BY_CMD => 1,
     BY_GET => 2,
     FETCH_NO_ERROR => 0,
     FETCH_OTHER_ERROR => 1,
     FETCH_LOGIN_ERROR => 2,
     TYPE_STRING => 1,
     TYPE_NUMBER => 2,
     TYPE_BOOLEAN => 3,

     ROUND_NUMBER => 2,
     ST_SAVE => 1,
     ST_REST => 2,

};

sub addToLLD;
sub fetchData;
sub fetchDataFromController;
sub getMetric;
sub logMessage;
sub isInArray;
sub writeStat;


#########################################################################################################################################
#
#  Default values for global scope
#
#########################################################################################################################################
my $configDefs = {
   # Where are store cache file. Better place is RAM-disk
   'cachedir'                 => ['', TYPE_STRING, '/dev/shm'],
   # How much time live cache data. Use 0 for disabling cache processes
   'cachemaxage'              => ['c', TYPE_NUMBER, 60],
   # Debug level 
   'debuglevel'               => ['d', TYPE_NUMBER, FALSE],

   # Default action for objects metric
   'action'                   => ['a', TYPE_STRING, ACT_DISCOVERY],
   # Operation object. wlan is exist in any case
   'objecttype'               => ['o', TYPE_STRING, OBJ_WLAN],
   # Name of your site. Used 'default' if defined as empty and -s option not used
   'sitename'                 => ['s', TYPE_STRING, 'default'],
   # Where are controller answer. See value of 'unifi.https.port' in /opt/unifi/data/system.properties
   'unifilocation'            => ['', TYPE_STRING, 'https://127.0.0.1:8443'],
   # UniFi controller version
   'unifiversion'             => ['v', TYPE_STRING, CONTROLLER_VERSION_4],
   # Who can read data with API
   'unifiuser'                => ['u', TYPE_STRING, 'stat'],
   # His pass
   'unifipass'                => ['p', TYPE_STRING, 'stat'],
   # LWP timeout
   'unifitimeout'             => ['', TYPE_NUMBER, 60],

   'nullchar'                 => ['n', TYPE_STRING, ''],
   'key'                      => ['k', TYPE_STRING, ''],
   'mac'                      => ['m', TYPE_STRING, ''],
   'id'                       => ['i', TYPE_STRING, '']
};

my $globalConfig = {
   # Where to store statistic data
   'stat_file' => './stat.txt',
   # Write statistic to _statfile_ or not
   'write_stat' => FALSE,

   #####################################################################################################
   ###
   ###  Service keys here. Do not change.
   ###
   #####################################################################################################
   # HiRes time of Miner internal processing start (not include Module Init stage)
   'start_time' => 0,
   # HiRes time of Miner internal processing stop
   'stop_time' => 0,
   # Data is downloaded instead readed from file
   'downloaded' => FALSE,
   # LWP::UserAgent object, which must be saved between fetchData() calls
   'ua' => undef,
   # JSON::XS object
   'jsonxs' => JSON::XS->new->utf8,
   # -s option used flag
   'sitename_given' => FALSE, 
  },

my $options;

for (@ARGV) {
    # try to take key from $_
    if ( m/^[-](.+)/) {
       # key is '--version' ? Set flag && do nothing inside loop
       $options->{'version'} = TRUE, next if ($1 eq '-version');
       # key is --help - do the same
       $options->{'help'}    = TRUE, next if ($1 eq '-help');
       # key is just found? Init hash item
       $options->{$1} = '';
    } else {
       # key not found - store value to hash item with $1 id.
       # $1 stay store old valued while next matching will not success
       $options->{$1} = $_ if (defined $1);
    }
}


# print the version & help with --versin & --help
if ($options->{'version'}) {
   print "\n",TOOL_NAME," v", TOOL_VERSION ,"\n\n";
   exit 0;
}
  
if ($options->{'help'}) {
   print "\n",TOOL_NAME," v", TOOL_VERSION, "\n\nusage: $0 [-C /path/to/config/file] [-D]\n",
          "\t-C\tpath to config file\n\t-D\trun in daemon mode\n\nAll other help on ", TOOL_HOMEPAGE, "\n\n";
   exit 0;
}

# clock_gettime(1)=> clock_gettime(CLOCK_MONOLITIC)
$globalConfig->{'start_time'}     = clock_gettime(1) if ($globalConfig->{'write_stat'});

# copy values that readed from command line arguments to global config and cast its if need    
for (keys $configDefs) {
   # take cli key that linked to config item
   my $optkey = $configDefs->{$_}[0];
   if (defined $options->{$optkey}) {
       if (TYPE_BOOLEAN  == $configDefs->{$_}[1]) {
          # Boolean var is TRUE when switch arg is just given
          $globalConfig->{$_} = defined $options->{$optkey} ? TRUE : FALSE;
       } elsif (TYPE_NUMBER == $configDefs->{$_}[1]) {
          # Numeric var is cast from string by 0+ operation
          $globalConfig->{$_} = 0 + $options->{$optkey};
       } else {
          # All other types (string) values just copy to config
          $globalConfig->{$_} = $options->{$optkey};
       }
   } else {
       # if no arg given with cli - set to default value
       $globalConfig->{$_} = $configDefs->{$_}[2];
   }
}

# 'sitename' need to special handling
$globalConfig->{'sitename'}          = SITENAME_DEFAULT if (!$globalConfig->{'sitename'});
$globalConfig->{'sitename_given'}    = $options->{$configDefs->{'sitename'}[0]} ? TRUE : FALSE;

$globalConfig->{'cnttailvals'}    = (isInArray($globalConfig->{'action'}, (ACT_PCOUNT, ACT_PSUM))) ? TRUE : FALSE;

# 'id' / 'mac' need to special handling too
if ($globalConfig->{'id'}) {
   if ( $globalConfig->{'id'} =~ m/^(?:[0-9a-z]{2}[:-]){5}(:?[0-9a-z]{2})$/ ) {
      $globalConfig->{'mac'} = $globalConfig->{'id'},
      $globalConfig->{'id'} = '';
   } else {
      $globalConfig->{'id'} = $globalConfig->{'id'},
      $globalConfig->{'mac'} = '';
   }
}

$globalConfig->{'api_path'}       = "$globalConfig->{'unifilocation'}/api";
$globalConfig->{'login_path'}     = "$globalConfig->{'unifilocation'}/login";
$globalConfig->{'logout_path'}    = "$globalConfig->{'unifilocation'}/logout";
$globalConfig->{'login_data'}     = "username=$globalConfig->{'unifiuser'}&password=$globalConfig->{'unifipass'}&login=login";
$globalConfig->{'content_type'}     = 'x-www-form-urlencoded';
# Set controller version specific data
if (CONTROLLER_VERSION_4 eq $globalConfig->{'unifiversion'}) {
   $globalConfig->{'login_path'}  = "$globalConfig->{'unifilocation'}/api/login";
   $globalConfig->{'login_data'}  = "{\"username\":\"$globalConfig->{'unifiuser'}\",\"password\":\"$globalConfig->{'unifipass'}\"}",
   $globalConfig->{'content_type'}  = 'application/json;charset=UTF-8',
   # Data fetch rules.
   # BY_GET mean that data fetched by HTTP GET from .../api/[s/<site>/]{'path'} operation.
   #    [s/<site>/] must be excluded from path if {'excl_sitename'} is defined
   # BY_CMD say that data fetched by HTTP POST {'cmd'} to .../api/[s/<site>/]{'path'}
   #
   $globalConfig->{'fetch_rules'} = {
      OBJ_SITE       , {'method' => BY_GET, 'path' => 'self/sites', 'excl_sitename' => TRUE},
      OBJ_UAP        , {'method' => BY_GET, 'path' => 'stat/device', 'short_way' => TRUE},
      OBJ_UPH        , {'method' => BY_GET, 'path' => 'stat/device', 'short_way' => TRUE},
      OBJ_USG        , {'method' => BY_GET, 'path' => 'stat/device', 'short_way' => TRUE},
      OBJ_USW        , {'method' => BY_GET, 'path' => 'stat/device', 'short_way' => TRUE},
      OBJ_SYSINFO    , {'method' => BY_GET, 'path' => 'stat/sysinfo'},
      OBJ_USER       , {'method' => BY_GET, 'path' => 'stat/sta'},
      OBJ_ALLUSER    , {'method' => BY_GET, 'path' => 'stat/alluser'},
      OBJ_HEALTH     , {'method' => BY_GET, 'path' => 'stat/health'},
      OBJ_NETWORK    , {'method' => BY_GET, 'path' => 'list/networkconf'},
      OBJ_EXTENSION  , {'method' => BY_GET, 'path' => 'list/extension'},
      OBJ_NUMBER     , {'method' => BY_GET, 'path' => 'list/number'},
      OBJ_USERGROUP  , {'method' => BY_GET, 'path' => 'list/usergroup'},
      OBJ_WLAN       , {'method' => BY_GET, 'path' => 'list/wlanconf'},
      OBJ_WLANGROUP  , {'method' => BY_GET, 'path' => 'list/wlangroup'},
      OBJ_SETTING    , {'method' => BY_GET, 'path' => 'get/setting'},
      OBJ_USW_PORT_TABLE , {'parent' => OBJ_USW},
      OBJ_UAP_VAP_TABLE  , {'parent' => OBJ_UAP}
   };
} elsif (CONTROLLER_VERSION_3 eq $globalConfig->{'unifiversion'}) {
       $globalConfig->{'fetch_rules'} = {
          OBJ_SITE       , {'method' => BY_CMD, 'path' => 'cmd/sitemgr', 'cmd' => '{"cmd":"get-sites"}'},
          OBJ_UAP        , {'method' => BY_GET, 'path' => 'stat/device'},
          OBJ_SYSINFO    , {'method' => BY_GET, 'path' => 'stat/sysinfo'},
          OBJ_USER       , {'method' => BY_GET, 'path' => 'stat/sta'},
          OBJ_ALLUSER    , {'method' => BY_GET, 'path' => 'stat/alluser'},
          OBJ_USERGROUP  , {'method' => BY_GET, 'path' => 'list/usergroup'},
          OBJ_WLAN       , {'method' => BY_GET, 'path' => 'list/wlanconf'},
          OBJ_WLANGROUP  , {'method' => BY_GET, 'path' => 'list/wlangroup'},
          OBJ_SETTING    , {'method' => BY_GET, 'path' => 'get/setting'}
       };
} elsif (CONTROLLER_VERSION_2 eq $globalConfig->{'unifiversion'}) {
       $globalConfig->{'fetch_rules'} = {
          OBJ_UAP       , {'method' => BY_GET, 'path' => 'stat/device', 'excl_sitename' => TRUE},
          OBJ_WLAN      , {'method' => BY_GET, 'path' => 'list/wlanconf', 'excl_sitename' => TRUE},
          OBJ_USER      , {'method' => BY_GET, 'path' => 'stat/sta', 'excl_sitename' => TRUE}
       };
} else {
   die "[!] Version of controller is unknown: '$globalConfig->{'unifiversion'}', stop\n";
}

logMessage(DEBUG_MID, "[.] globalConfig:\n", $globalConfig);

################################################## Main action ##################################################
# made fake site list, cuz fetchData(v2) just ignore sitename
my $buffer, my $buferLength, my $objList, my $lldPiece, my $bytes, my $parentObj, my $objListSize;
my $siteList = [{'name' => $globalConfig->{'sitename'}}];
my $selectingResult = {'total' => 0, 'data' => []};

unless ($globalConfig->{'fetch_rules'}->{$globalConfig->{'objecttype'}}) {
   logMessage(DEBUG_LOW, "[!] No object type '$globalConfig->{'objecttype'}' supported");
} else {
   # if OBJ_SITE exists in fetch_rules - siteList could be obtained for 'discovery' action or in case with undefuned sitename
   if ($globalConfig->{'fetch_rules'}->{OBJ_SITE()} && (ACT_DISCOVERY eq $globalConfig->{'action'} || !$globalConfig->{'sitename_given'}))  {
      # Clear array, because fetchData() will push data to its
      $siteList = [];
      # Get site list. v3 need {'sitename'} to use into 'cmd' URI
      fetchData($globalConfig, $globalConfig->{'sitename'}, OBJ_SITE, '', $siteList);
   }

   logMessage(DEBUG_MID, "[.]\t\t Going over all sites");
   foreach my $siteObj (@{$siteList}) {
      # skip hidden site 'super'
      next if (defined($siteObj->{'attr_hidden'}));
      # skip site, if '-s' option used and current site other, that given
      next if ($globalConfig->{'sitename_given'} && ($globalConfig->{'sitename'} ne $siteObj->{'name'}));

      logMessage(DEBUG_MID, "[.]\t\t Handle site: '$siteObj->{'name'}'");
      $objList = [];
      # parentObject used for transfer site (or device) info to LLD. That data used for "parent"-related macro (like {#SITENAME}, {#UAPID})
      # user ask info for 'site' object. Data already loaded to $siteObj.
      if (OBJ_SITE eq $globalConfig->{'objecttype'}) {
         # Just make array from site object (which is hash) and take null for parenObj - no parent for 'site' exists
         $objList = [$siteObj], $parentObj = {'type' => ''};
      } else {
         # Take objects from foreach'ed site
         # Take parent of virtual object, if 'parent' property detected. Or use real object type, if not.
         my $wrkObjType = ($globalConfig->{'fetch_rules'}->{$globalConfig->{'objecttype'}}->{'parent'}) // $globalConfig->{'objecttype'};
         # Fetch object from site
         unless (fetchData($globalConfig, $siteObj->{'name'}, $wrkObjType, $globalConfig->{'id'}, $objList)) {
           logMessage(DEBUG_MID, "[!] No data found for object $globalConfig->{'objecttype'} (may be wrong site name)"), next;
         }
         # siteObj is parent for each site item: device/user/etc
         $parentObj = {'type' => OBJ_SITE, 'data' => $siteObj};
      }

      # Test "-k" option
      if (! $globalConfig->{'key'}) {
         # No key given - user need to discovery objects?
         if (ACT_DISCOVERY eq $globalConfig->{'action'}) {
            logMessage(DEBUG_MID, "[.]\t\t Discovering w/o key: add part of LLD");
            addToLLD($globalConfig, $parentObj, $objList, $selectingResult->{'data'}) if ($objList);
         } else {
            logMessage(DEBUG_MID, "[.]\t\t Action '$globalConfig->{'action'}' w/o key not allowed");
         }
      } else {
         # key is defined - any action could be processed
         logMessage(DEBUG_LOW, "[*]\t\t Key given: $globalConfig->{'key'}");
         # every object in site must be processeed separately to make right parentObject for key-based LLD
         if (ACT_DISCOVERY eq $globalConfig->{'action'}) {
            my $wrkSelectingResult;
            # Take every site's object
            foreach (@{$objList}) {
               # [re-]init temporary var
               $wrkSelectingResult = {'total' => 0, 'data' => []};
               # prepare parent object
               $parentObj = { 'type' => $globalConfig->{'fetch_rules'}->{$globalConfig->{'objecttype'}}->{'parent'}, 'data' => $_};
               # select all elements which linked with key (key must be point to array)
               getMetric($globalConfig, $_, $globalConfig->{'key'}, $wrkSelectingResult);
               # Add some properties to LLD array
               addToLLD($globalConfig, $parentObj, $wrkSelectingResult->{'data'}, $selectingResult->{'data'}) if (@{$wrkSelectingResult->{'data'}} > 0);
            }
         } else {
            getMetric($globalConfig, $objList, $globalConfig->{'key'}, $selectingResult);
            # 'get' - just get data from first site's first object  in objectList and jump out from loop
            last if (ACT_GET eq $globalConfig->{'action'});
          }
     } # if (! $globalConfig->{'key'}) ...else...
   } #foreach sites

   ################################################## Final stage of main loop  ##################################################

   # Form JSON from result for 'discovery' action
    if (ACT_DISCOVERY eq $globalConfig->{'action'}) {
       logMessage(DEBUG_MID, "[.] Make LLD JSON");
       # make JSON
       delete $selectingResult->{'total'};
       $buffer = $globalConfig->{'jsonxs'}->encode($selectingResult);
    } else {
       # User want no discovery action
       my $totalKeysProcesseed = @{$selectingResult->{'data'}};
       if ($totalKeysProcesseed) {
          my $result = @{$selectingResult->{'data'}}[0];
          if (ACT_GET eq $globalConfig->{'action'}) { 
             $buffer = $result;
          } else {
             if (ACT_SUM eq $globalConfig->{'action'} || ACT_PSUM eq $globalConfig->{'action'} || ACT_AMEAN eq $globalConfig->{'action'}) {
                $result = 0;
                for (my $i = 0; $i < $totalKeysProcesseed; $i++) { $result += @{$selectingResult->{'data'}}[$i]; }
                if (ACT_PSUM eq $globalConfig->{'action'}) {
                   $result = (0 == $selectingResult->{'total'}) ? '0' : $result/($selectingResult->{'total'}/100);

                } elsif (ACT_AMEAN eq $globalConfig->{'action'}) { 
                   $result = (0 == $totalKeysProcesseed) ? '0' : $result/$totalKeysProcesseed;
                }

             } elsif (ACT_MAX eq $globalConfig->{'action'}) {
                for (my $i = 0; $i < $totalKeysProcesseed; $i++) { $result = @{$selectingResult->{'data'}}[$i] if ($result < @{$selectingResult->{'data'}}[$i]); }
   
             } elsif (ACT_MIN eq $globalConfig->{'action'}) {
                for (my $i = 0; $i < $totalKeysProcesseed; $i++) { $result = @{$selectingResult->{'data'}}[$i] if ($result > @{$selectingResult->{'data'}}[$i]); }

             } elsif (ACT_COUNT eq $globalConfig->{'action'}) {
                $result = $totalKeysProcesseed;

             } elsif (ACT_PCOUNT eq $globalConfig->{'action'}) {
                $result = (0 == $selectingResult->{'total'}) ? '0' : $totalKeysProcesseed/($selectingResult->{'total'}/100);

             } elsif (ACT_MEDIAN eq $globalConfig->{'action'}) {
                @{$selectingResult->{'data'}} = sort {$a <=> $b} @{$selectingResult->{'data'}};
                my $middle = int($totalKeysProcesseed/2);
                #odd?
                if($totalKeysProcesseed % 2) {
                   $result = $selectingResult->{'data'}[$middle];
                } else {
                   #even
                   $result = ($selectingResult->{'data'}[$middle-1] + $selectingResult->{'data'}[$middle])/2;
                }
            }
            # round to .xxx only if action is ACT_AMEAN || ACT_PCOUNT || ACT_PSUM || ACT_MEDIAN
            $buffer = sprintf("%.".(isInArray($globalConfig->{'action'}, (ACT_AMEAN, ACT_PCOUNT, ACT_PSUM, ACT_MEDIAN)) ? ROUND_NUMBER : 0)."f", $result); 
         } # if (ACT_GET eq $globalConfig->{'action'}) ...else...
      } # if ($totalKeysProcesseed)
   } # if (ACT_DISCOVERY eq $globalConfig->{'action'}) ...else...
} # unless ($globalConfig->{'fetch_rules'}->{$globalConfig->{'objecttype'}}) ...else...


# Value could be null-type (undef in Perl). If need to replace null to other char - {'nullchar'} must be defined. On default $globalConfig->{'nullchar'} is ''
$buffer = $globalConfig->{'nullchar'} unless defined($buffer);
$buferLength = length($buffer);
# MAX_BUFFER_LEN - Zabbix buffer length. Sending more bytes have no sense.
if ( MAX_BUFFER_LEN <= $buferLength) {
    $buferLength = MAX_BUFFER_LEN-1, 
    $buffer = substr($buffer, 0, $buferLength);
}

# Logout need if logging in before (in fetchData() sub) completed
logMessage(DEBUG_LOW, "[*] Logout from UniFi controller"), $globalConfig->{'ua'}->get($globalConfig->{'logout_path'}) if (defined($globalConfig->{'ua'}));

# Push result of work to stdout
$buffer .= "\n", $buferLength++, print $buffer;


# Write stat to file if need
if ($globalConfig->{'write_stat'}) {
   # clock_gettime(1)=> clock_gettime(CLOCK_MONOLITIC)
   $globalConfig->{'stop_time'} = clock_gettime(1);
   writeStat($globalConfig);
}

##################################################################################################################################
#
#  Subroutines
#
##################################################################################################################################
sub logMessage
  {
    return unless ($globalConfig->{'debuglevel'} >= $_[0]);
    print "[$$] ", POSIX::strftime("%Y-%m-%d %H:%M:%S", localtime(time())), " ";
    for (my $i = 1; $i < @_; $i++) {
        print (('ARRAY' eq ref($_[$i]) || ('HASH' eq ref($_[$i]))) ? Data::Dumper::Dumper $_[$i] : $_[$i]);
    }
    print "\n";
  }

sub isInArray {
    for (my $i = 1; $i < @_; $i++) {
        return 1 if ($_[0] eq $_[$i]);
    }
    return 0;
}

#####################################################################################################################################
#
#  Write statistic to file. Fields separated by commas.
#
#####################################################################################################################################
sub writeStat {
    # $_[0] - GlobalConfig
    open (my $fh, ">>", $_[0]->{'stat_file'}) or die "Could not open $_[0]->{'stat_file'} for storing statistic info, stop.";
    # chmod 0666, $fh;
    print $fh "$_[0]->{'start_time'},$_[0]->{'stop_time'},$_[0]->{'unifiversion'},$_[0]->{'sitename'},$_[0]->{'objecttype'},$_[0]->{'id'},$_[0]->{'mac'},$_[0]->{'key'},$_[0]->{action},$_[0]->{'downloaded'},$_[0]->{'debuglevel'}\n";
    close $fh;
}

#*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/
#
#  Go through the JSON tree and take/form value of metric
#
#*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/
sub getMetric {
    my $currentRoot = $_[1], my $state = ST_SAVE, my $stack, my $arrIdx, my $arrSize, my $keyPos = -1, my $nFilters = 0, my $stackPos = -1, my $allValues = 0,
    my $keepKeyPos = FALSE, my $filterPassed = 0, my $isLastFilter = FALSE, my $actCurrentValue, my $i, my $processedKeysNum = 0;
  
    logMessage(DEBUG_LOW, "[+] getMetric() started");
    logMessage(DEBUG_LOW, "[>]\t args: key: '$_[2]', action: '$_[0]->{'action'}'");
    logMessage(DEBUG_HIGH, "[>]\t incoming object info:'\n\t", $_[1]);
    
    # split key to parts for analyze
    my @keyParts = split (/[.]/, $_[2]);
    #print Dumper @keyParts;

    # do analyzing, put subkeys to array, processing filter expressions
    # keyParts array:
    # {'l'} = & for AND 
    #         | for OR
    #         undef for non-logic expression
    # {'e'} - expression array if {'l'} defined
    #       {'k'} - key
    #       {'s'} - equation sign
    #       {'v'} - value
    # {'e'} - JSON-key name if {'l'} is undef
    for ($i = 0; $i < @keyParts; $i++) {
        my $swap = $keyParts[$i];
        undef $keyParts[$i];
        # check for [filterkey=value&filterkey=value&...] construction in keyPart. If that exist - key filter feature will enabled
        if ( $swap =~ m/^\[(.+)\]/) {
           # filterString is exist.
           # What type of logic is used - '&' or '|' ?
           $keyParts[$i]->{'l'} = (index($1, '|') >= 0 ) ? '|' : '&';
           # split filter-key by detected logic type separator 
           my @fStrings = split(/[$keyParts[$i]->{'l'}]/, $1);
           $keyParts[$i]->{'e'} = [];
           # After splitting split again - for get keys, values and equation sign. Store it for future
           for (my $k = 0; $k < @fStrings; $k++) {
              push(@{$keyParts[$i]->{'e'}}, {'k'=>$1, 's' => $2, 'v'=> $3}) if ($fStrings[$k] =~ /^([^=<>]+)(=|<>|<|>|>=|<=)([^=<>]+)$/);
           }
           # count the number of filter expressions
           $nFilters++;
        } else {
           # If no filter-key detected - just store taked key and set its 'logic' to undef for 'no filter used' case
           $keyParts[$i] = {'e' => $swap, 'l' => undef};
        }
    }
    # Some special actions is processed

   ###########################################     Main loop    ###########################################################
   while (TRUE) {

        ########  Save/Restore block #######

        # Command is "Save position". Need to create new restore point.
        if (ST_SAVE == $state) {
           # Increase restore points stack array
           $stackPos++;
           # Use next subkey
           # When point to 'something as array item' is saved - need to use current subkey again.
           $keyPos++ unless $keepKeyPos;
           # Take array size, if current root point to 'ARRAY' object. Otherwise (point to 'HASH' or other) - size is -1
           $arrSize = 'ARRAY' eq ref($currentRoot) ? @{$currentRoot} : -1;
           # -1 - $arrIdx, will be corrected later by routine
           @{$stack}[$stackPos] = [$currentRoot, -1, $arrSize, $keyPos, $filterPassed];
           $state = FALSE; $keepKeyPos = FALSE;
        }

        # Command is "Restore position". Need to get data from stack to restoring an some state
        if (ST_REST == $state ) {
           # delete current (work) stack's item with return points
           undef @{$stack}[$stackPos];
           # move to prev stack position (go closer to root of JSON-tree)
           $stackPos--;
           # if stack is empty - exit from loop
           last if (0 > $stackPos);
           # Restore previous state:
           #     - current root of JSON-representing structure,
           #     - array index (used to walking thru subarrays)
           #     - array size (if stack item point to root of array structure)
           #     - key position (restore key for analyzing from the begin)
           ($currentRoot,$arrIdx,$arrSize,$keyPos,$filterPassed) = @{@{$stack}[$stackPos]};
           # Repeat restoring while root point to array afer restoring (array as array item).
           next unless ('ARRAY' eq ref($currentRoot));
           $state = FALSE;
        }
        ########    End of Save/Restore block #######

        ######## Data analyzing block #######

        # Current root point to 'ARRAY' structure
        if ('ARRAY' eq ref($currentRoot)) {
           # increase array index (walk thru its)
           @{@{$stack}[$stackPos]}[1]++; $arrIdx = @{@{$stack}[$stackPos]}[1];
           # if end of array reached - rolling to previous restore point
           $state = ST_REST, next if ($arrIdx >= $arrSize);
           # (657) end of array is not reached - going inside array item via root changing
           $currentRoot = @{$currentRoot}[$arrIdx];
           # Need to make restore point
           $state = ST_SAVE;
           # But without changing subkey
           $keepKeyPos =1;
           next;
        }

        # current root point to 'HASH' structure.
        if ('HASH' eq ref($currentRoot)) {
           # if user want to know how much items contained in subarray - just read array size from stack's item and return immediatly
           if (KEY_ITEMS_NUM eq $keyParts[$keyPos]->{'e'}) {
              # [$stackPos-1] when key is '...json_hash.items_num'
              $_ = @{@{$stack}[$stackPos-1]}[2], $_[3]->{'total'} += $_, push(@{$_[3]->{'data'}}, $_), last;
           }

           # Do filter tests with this item
           if (defined($keyParts[$keyPos]->{'l'})) {
              my $fData = $keyParts[$keyPos]->{'e'}, my $matchCount=0;
              # run trought flter list
              for ($i = 0; $i < @{$fData}; $i++ ) {
                  # if key (from filter) in object is defined.
                  if (defined($currentRoot->{@{$fData}[$i]->{'k'}})) {
                     # '&' logic need to use
                     if ('&' eq $keyParts[$keyPos]->{'l'}) {
                        # JSON key value equal / not equal (depend of equation sign) to value of filter - increase counter
                        $matchCount++ if ('='  eq @{$fData}[$i]->{'s'} && ($currentRoot->{@{$fData}[$i]->{'k'}} eq @{$fData}[$i]->{'v'}));
                        $matchCount++ if ('<>' eq @{$fData}[$i]->{'s'} && ($currentRoot->{@{$fData}[$i]->{'k'}} ne @{$fData}[$i]->{'v'}));
                        $matchCount++ if ('>'  eq @{$fData}[$i]->{'s'} && ($currentRoot->{@{$fData}[$i]->{'k'}} >  @{$fData}[$i]->{'v'}));
                        $matchCount++ if ('<'  eq @{$fData}[$i]->{'s'} && ($currentRoot->{@{$fData}[$i]->{'k'}} <  @{$fData}[$i]->{'v'}));
                        $matchCount++ if ('<=' eq @{$fData}[$i]->{'s'} && ($currentRoot->{@{$fData}[$i]->{'k'}} <= @{$fData}[$i]->{'v'}));
                        $matchCount++ if ('>=' eq @{$fData}[$i]->{'s'} && ($currentRoot->{@{$fData}[$i]->{'k'}} >= @{$fData}[$i]->{'v'}));
                     # '|' logic need to use
                     } elsif ('|' eq $keyParts[$keyPos]->{'l'}) {
                        # JSON key value equal / not equal (depend of equation sign) to value of filter - all filters is passed, leave local loop
                        $matchCount = @{$fData}, last if ('='  eq @{$fData}[$i]->{'s'} && ($currentRoot->{@{$fData}[$i]->{'k'}} eq @{$fData}[$i]->{'v'}));
                        $matchCount = @{$fData}, last if ('<>' eq @{$fData}[$i]->{'s'} && ($currentRoot->{@{$fData}[$i]->{'k'}} ne @{$fData}[$i]->{'v'}));
                        $matchCount = @{$fData}, last if ('>'  eq @{$fData}[$i]->{'s'} && ($currentRoot->{@{$fData}[$i]->{'k'}} >  @{$fData}[$i]->{'v'}));
                        $matchCount = @{$fData}, last if ('<'  eq @{$fData}[$i]->{'s'} && ($currentRoot->{@{$fData}[$i]->{'k'}} <  @{$fData}[$i]->{'v'}));
                        $matchCount = @{$fData}, last if ('<=' eq @{$fData}[$i]->{'s'} && ($currentRoot->{@{$fData}[$i]->{'k'}} <= @{$fData}[$i]->{'v'}));
                        $matchCount = @{$fData}, last if ('>=' eq @{$fData}[$i]->{'s'} && ($currentRoot->{@{$fData}[$i]->{'k'}} >= @{$fData}[$i]->{'v'}));
                     }
                  }
              }

              # part of key was filter expression and object is matched
              if ($matchCount == @{$fData}) {
                 # Object is good - just skip filter expression and work
                 $filterPassed++;
              } else {
                 # Object is bad
                 # is last key-filter ?
                 # $isLastFilter = ($nFilters == ($filterPassed+1)) ? TRUE : FALSE;
                 $isLastFilter = (($nFilters - $filterPassed) == 1) ? TRUE : FALSE;
                 # If P* actions is used - need to count all values that full matched by filters or unmatched only bt last filter (count tails)
                 # So, need restore stack position when detected 'bad object' due analyzed:
                 # 1) not last filter 
                 # OR
                 # 2) last filter, but not in P* action (not count tails)
                 #
                 # i.e. (NOT $isLastFilter) OR ($isLastFilter AND (NOT $_[0]->{'cnttailvals'})) => 
                 #      (!$isLastFilter || ($isLastFilter & !$_[0]->{'cnttailvals'})) =>
                 #      (!$isLastFilter || !$_[0]->{'cnttailvals'})
                 # (!a & b) v !b => (!a v !b) & (b v !b) => !a || !b
                 $state = ST_REST, next if (!$_[0]->{'cnttailvals'} || !$isLastFilter)
              }
              # just skip key-filter after analyze
              $keyPos++, next;
           }
           # end of filter work part

           # hash with name equal key part is reached from current root with one hop?
           # ToDo: (... ||  KEY_ANY eq $keyParts[$keyPos]->{'e'}) for 'part.subpart.[filter].*' keys
           if (exists($currentRoot->{$keyParts[$keyPos]->{'e'}})) {
              # Yes, hash item found
              # Key is point to final subkey or we can dive more?
              if (!defined($keyParts[$keyPos+1])) {
                 # Searched item is found, take it's value
                 # all filters is passed? ($nFilters - $filterPassed) must be 0 if true
                 # current value allowed to action when all filters passed
                 $actCurrentValue  = (($nFilters - $filterPassed) == 0) ? TRUE : FALSE;
                 # do action
                 if ('ARRAY' eq ref($currentRoot->{$keyParts[$keyPos]->{'e'}})) {
                    # sub pointed to ARRAY. Push it as array of hashes to result with 'discovery' action
                    push(@{$_[3]->{'data'}}, @{$currentRoot->{$keyParts[$keyPos]->{'e'}}}) if ($actCurrentValue && (ACT_DISCOVERY eq $_[0]->{'action'}));
                 } elsif ('HASH' eq ref($currentRoot->{$keyParts[$keyPos]->{'e'}})) {
                    # sub pointed to HASH. Push it as single hash to result with 'discovery' action
                    push(@{$_[3]->{'data'}}, $currentRoot->{$keyParts[$keyPos]->{'e'}})    if ($actCurrentValue && (ACT_DISCOVERY eq $_[0]->{'action'}));
                 } else {
                    # sub pointed to property. Its can be counted or summed without programm exception
                    push(@{$_[3]->{'data'}}, $currentRoot->{$keyParts[$keyPos]->{'e'}})    if ($actCurrentValue && (ACT_DISCOVERY ne $_[0]->{'action'}));
                    # just exit from search loop
                    last if ($actCurrentValue && ACT_GET eq $_[0]->{'action'});
                    # all values must be counted while PER* actions proceseed 
                    if (ACT_PSUM eq $_[0]->{'action'})    {
                       # SUM values
                       $_[3]->{'total'} += $currentRoot->{$keyParts[$keyPos]->{'e'}};
                    } else {
                       # COUNT all values (matched and not matched)
                       $_[3]->{'total'}++;
                    }
                 }
                 # Final subkey detected. Go closer to JSON root.
                 $state = ST_REST; next;
              } else {
                # Not final subkey - go deeper to JSON structure by root changing
                $currentRoot = $currentRoot->{$keyParts[$keyPos]->{'e'}};
                $state = ST_SAVE; next;
              } # if ($ll)
           } else {
             # No item found, Go closer to JSON root.
             $state = ST_REST;
           }
     } # if (ref($currentRoot) eq 'HASH')
 }
    ###########################################    End of main loop    ###########################################################

 logMessage(DEBUG_HIGH, "[<]\t result:'\n\t", $_[3]);
 logMessage(DEBUG_LOW, "[-] getMetric() finished ");
 return TRUE;

}

#*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/
#
#  Fetch data from cache or call fetching from controller. Renew cache files.
#
#*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/
sub fetchData {
   # $_[0] - $GlobalConfig
   # $_[1] - sitename
   # $_[2] - object type
   # $_[3] - obj id
   # $_[4] - jsonData object ref
   logMessage(DEBUG_LOW, "[+] fetchData() started");
   logMessage(DEBUG_MID, "[>]\t args: object type: '$_[2]'");
   logMessage(DEBUG_MID, "[>]\t id: '$_[3]'") if ($_[3]);
   logMessage(DEBUG_MID, "[>]\t mac: '$_[0]->{'mac'}'") if ($_[0]->{'mac'});
   my $fh, my $jsonData, my $objPath, my $useShortWay = FALSE,
   my $needReadCache = TRUE;

   $objPath  = $_[0]->{'api_path'} . ($_[0]->{'fetch_rules'}->{$_[2]}->{'excl_sitename'} ? '' : "/s/$_[1]") . "/$_[0]->{'fetch_rules'}->{$_[2]}->{'path'}";
   # if MAC is given with command-line option -  RapidWay for Controller v4 is allowed, short_way is tested for non-device objects workaround
   if ($_[0]->{'fetch_rules'}->{$_[2]}->{'short_way'} && $_[0]->{'mac'}) {
      $objPath .= "/$_[0]->{'mac'}", $useShortWay = TRUE;
   }
   logMessage(DEBUG_MID, "[.]\t\t Object path: '$objPath'");

   ################################################## Take JSON  ##################################################

   # If CacheMaxAge = 0 - do not try to read/update cache - fetch data from controller
   if (0 == $_[0]->{'cachemaxage'}) {
      logMessage(DEBUG_MID, "[.]\t\t No read/update cache because CacheMaxAge = 0");
      fetchDataFromController($_[0], $_[2], $objPath, $jsonData, $useShortWay) or logMessage(DEBUG_LOW, "[!] Can't fetch data from controller"), return FALSE;
   } else {
      # Change all [:/.] to _ to make correct filename
      my $cacheFileName;
      ($cacheFileName = $objPath) =~ tr/\/\:\./_/, 
      $cacheFileName = $_[0]->{'cachedir'} .'/'. $cacheFileName;
      my $cacheFileMTime = (stat($cacheFileName))[9];
      # cache file unexist (mtime is undef) or regular?
      ($cacheFileMTime && (!-f $cacheFileName)) and logMessage(DEBUG_LOW, "[!] Can't handle '$cacheFileName' through its not regular file"), return FALSE;
      # cache is expired if: unexist (mtime is undefined) OR (file exist (mtime is defined) AND its have old age) 
      #                                                   OR have Zero size (opened, but not filled or closed with error)
      my $cacheExpire=(((! defined($cacheFileMTime)) || defined($cacheFileMTime) && (($cacheFileMTime+$_[0]->{'cachemaxage'}) < time())) ||  -z $cacheFileName) ;

      if ($cacheExpire) {
         # Cache expire - need to update
         logMessage(DEBUG_MID, "[.]\t\t Cache expire or not found. Renew...");
         my $tmpCacheFileName = $cacheFileName . ".tmp";
         # Temporary cache filename point to non regular file? If so - die to avoid problem with write or link/unlink operations
         # $_ not work
         ((-e $tmpCacheFileName) && (!-f $tmpCacheFileName)) and logMessage(DEBUG_LOW, "[!] Can't handle '$tmpCacheFileName' through its not regular file"), return FALSE;
         logMessage(DEBUG_MID, "[.]\t\t Temporary cache file='$tmpCacheFileName'");
         open ($fh, ">", $tmpCacheFileName) or logMessage(DEBUG_LOW, "[!] Can't open '$tmpCacheFileName' ($!)"), return FALSE;
         # try to lock temporary cache file and no wait for able locking.
         # LOCK_EX | LOCK_NB
         if (flock ($fh, 2 | 4)) {
            # if Proxy could lock temporary file, it...
            chmod (0666, $fh);
            # ...fetch new data from controller...
            fetchDataFromController($_[0], $_[2], $objPath, $jsonData, $useShortWay) or logMessage(DEBUG_LOW, "[!] Can't fetch data from controller"), close ($fh), return FALSE;
            # unbuffered write it to temp file..
            syswrite ($fh, $_[0]->{'jsonxs'}->encode($jsonData));
            # Now unlink old cache filedata from cache filename 
            # All processes, who already read data - do not stop and successfully completed reading
            unlink ($cacheFileName);
            # Link name of cache file to temp file. File will be have two link - to cache and to temporary cache filenames. 
            # New run down processes can get access to data by cache filename
            link($tmpCacheFileName, $cacheFileName) or logMessage(DEBUG_LOW, "[!] Presumably no rights to unlink '$cacheFileName' file ($!). Try to delete it "), return FALSE;
            # Unlink temp filename from file. 
            # Process, that open temporary cache file can do something with filedata while file not closed
            unlink($tmpCacheFileName) or logMessage(DEBUG_LOW, "[!] '$tmpCacheFileName' unlink error ($!)"), return FALSE;
            # Close temporary file. close() unlock filehandle.
            #close($fh) or logMessage(DEBUG_LOW, "[!] Can't close locked temporary cache file '$tmpCacheFileName' ($!)"), return FALSE; 
            # No cache read from file need
           $needReadCache=FALSE;
        } 
        close ($fh) or logMessage(DEBUG_LOW, "[!] Can't close temporary cache file '$tmpCacheFileName' ($!)"), return FALSE;
      } # if ($cacheExpire)

      # if need load data from cache file
      if ($needReadCache) {
       # open file
       open($fh, "<:mmap", $cacheFileName) or logMessage(DEBUG_LOW, "[!] Can't open '$cacheFileName' ($!)"), return FALSE;
       # read data from file
       $jsonData=$_[0]->{'jsonxs'}->decode(<$fh>);
       # close cache
       close($fh) or logMessage(DEBUG_LOW, "[!] Can't close cache file ($!)"), return FALSE;
    }
  } # if (0 == $_[0]->{'cachemaxage'})

  ################################################## JSON processing ##################################################
  # push() to $_[4] or delete() from $jsonData? If delete() just clean refs - no memory will reserved to new array.
  # UBNT Phones store ID into 'device_id' key (?)
  my $idKey = ($_[2] eq OBJ_UPH) ? 'device_id' : '_id'; 

  # Walk trought JSON array
  for (my $i = 0; $i < @{$jsonData}; $i++) {
     # Object have ID...
     if ($_[3]) {
       #  ...and its required object? If so push - object to global @objJSON and jump out from the loop.
       $_[4][0] = @{$jsonData}[$i], last if (@{$jsonData}[$i]->{$idKey} eq $_[3]);
     } else {
       # otherwise
       push (@{$_[4]}, @{$jsonData}[$i]) if (!exists(@{$jsonData}[$i]->{'type'}) || (@{$jsonData}[$i]->{'type'} eq $_[2]));
     }
   } # for each jsonData

   logMessage(DEBUG_HIGH, "[<]\t Fetched data:\n\t", $_[4]);
   logMessage(DEBUG_LOW, "[-] fetchData() finished");
   return TRUE;
}

#*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/
#
#  Fetch data from from controller.
#
#*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/
sub fetchDataFromController {
   # $_[0] - GlobalConfig
   # $_[1] - object type
   # $_[2] - object path
   # $_[3] - jsonData object ref
   # $_[4] - used "short way" request

   my $response, my $fetchType = $_[0]->{'fetch_rules'}->{$_[1]}->{'method'}, my $fetchCmd = $_[0]->{'fetch_rules'}->{$_[1]}->{'cmd'}, my $errorCode;

   logMessage(DEBUG_LOW, "[+] fetchDataFromController() started");
   logMessage(DEBUG_LOW, "[>]\t args: object path: '$_[2]'");

   # HTTP UserAgent init
   # Set SSL_verify_mode=off to login without certificate manipulation
   $_[0]->{'ua'} = LWP::UserAgent-> new('cookie_jar' => {}, 'agent' => TOOL_NAME."/".TOOL_VERSION." (perl engine)",
                                        'timeout' => $_[0]->{'unifitimeout'}, 'ssl_opts' => {'verify_hostname' => 0}) unless ($_[0]->{'ua'});
   ################################################## Logging in  ##################################################
   # Check to 'still logged' state
   # ->head() not work
   $response = $_[0]->{'ua'}->get("$_[0]->{'api_path'}/self");
   # FETCH_OTHER_ERROR = is_error == TRUE (1), FETCH_NO_ERROR = is_error == FALSE (0)
   # FETCH_OTHER_ERROR stop work if get() haven't success && no error 401 (login required). For example - error 500 (connect refused)
   $errorCode = $response->is_error;
   # not logged?
   if ('401' eq $response->code) {
        # logging in
        logMessage(DEBUG_LOW, "[.]\t\tTry to log in into controller...");
        $response = $_[0]->{'ua'}->post($_[0]->{'login_path'}, 'Content_type' => $_[0]->{'content_type'}, 'Content' => $_[0]->{'login_data'});
        logMessage(DEBUG_HIGH, "[>>]\t\t HTTP respose:\n\t", $response);
        $errorCode = $response->is_error;
        if (CONTROLLER_VERSION_4 eq $_[0]->{'unifiversion'}) {
           # v4 return 'Bad request' (code 400) on wrong auth
           # v4 return 'OK' (code 200) on success login
           ('400' eq $response->code) and $errorCode = FETCH_LOGIN_ERROR;
        } elsif ( CONTROLLER_VERSION_3 eq ($_[0]->{'unifiversion'}) || (CONTROLLER_VERSION_2 eq $_[0]->{'unifiversion'})) {
           # v3 return 'OK' (code 200) on wrong auth
           ('200' eq $response->code) and $errorCode = FETCH_LOGIN_ERROR;
           # v3 return 'Redirect' (code 302) on success login and must die only if code<>302
           ('302' eq $response->code) and $errorCode = FETCH_NO_ERROR;
        }
    }

    (FETCH_LOGIN_ERROR == $errorCode) and logMessage(DEBUG_LOW, "[!] Login error - wrong auth data"), return FALSE;
    (FETCH_OTHER_ERROR == $errorCode) and logMessage(DEBUG_LOW, "[!] Comminication error: '", ($response->status_line), "'\n"), return FALSE;

    logMessage(DEBUG_LOW, "[.]\t\tLogin successfull");

   ################################################## Fetch data from controller  ##################################################

   if (BY_CMD == $fetchType) {
      logMessage(DEBUG_MID, "[.]\t\t Fetch data with CMD method: '$fetchCmd'");
      $response = $_[0]->{'ua'}->post($_[2], 'Content_type' => $_[0]->{'content_type'}, 'Content' => $fetchCmd);
   } else { #(BY_GET == $fetchType)
      logMessage(DEBUG_MID, "[.]\t\t Fetch data with GET method from: '$_[1]'");
      $response = $_[0]->{'ua'}->get($_[2]);
   }

   # '400 Bad Request' is returned with 'no device' case & v4's "short way" request used
   if (('400' eq $response->code) && $_[4]) {
      logMessage(DEBUG_MID, "[.] Comminication error while fetch data from v4 controller via shortway. No specified device exist in this site");
   } else {
     ($response->is_error == FETCH_OTHER_ERROR) and logMessage(DEBUG_LOW, "[!] Comminication error while fetch data from controller: '", $response->status_line ,"'\n"), return FALSE;
   }

   logMessage(DEBUG_HIGH, "[>>]\t\t Fetched data:\n\t", $response->decoded_content);
   $_[3] = $_[0]->{'jsonxs'}->decode(${$response->content_ref()});


   # server answer is ok ?
   (($_[3]->{'meta'}->{'rc'} ne 'ok') && (defined($_[3]->{'meta'}->{'msg'}))) and logMessage(DEBUG_LOW, "[!] UniFi controller reply is not OK: '$_[3]->{'meta'}->{'msg'}'");
   $_[3] = $_[3]->{'data'};
   logMessage(DEBUG_HIGH, "[<]\t decoded data:\n\t", $_[3]);
   $_[0]->{'downloaded'}=TRUE;
   return TRUE;
}

#*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/
#
#  Add a piece to exists LLD-like JSON 
#
#*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/
sub addToLLD {
    # $_[0] - $globalConfig
    # $_[1] - Parent object
    # $_[2] - Incoming objects list
    # $_[3] - Outgoing objects list

    # remap object type: add key to type for right select and add macroses
    my $givenObjType  = $_[0]->{'objecttype'}.($_[0]->{'key'} ? "_$_[0]->{'key'}" : ''),
    my $parentObjType = $_[1]->{'type'}, my $parentObjData;
    $parentObjData = $_[1]->{'data'} if (defined($_[1]));

    logMessage(DEBUG_LOW, "[+] addToLLD() started"), logMessage(DEBUG_MID, "[>]\t args: object type: '$_[0]->{'objecttype'}'"); 
    logMessage(DEBUG_MID, "[>]\t Site name: '$_[1]->{'name'}'") if ($_[1]->{'name'});
    # $o - outgoing object's array element pointer, init as length of that array to append elements to the end
    my $o = $_[3] ? @{$_[3]} : 0;
    for (@{$_[2]}) {
      # skip hidden 'super' site with OBJ_SITE
      next if ($_->{'attr_hidden'});
      # $_[1] contain parent's data and its may be undefined if script uses with v2 controller or while generating LLD for OBJ_SITE  
      # if defined $_[0]->{'key'})  - discovery for subtable must be maded
      if (defined($_[1])) {
         # analyze parent & add some fields
         if (OBJ_SITE eq $parentObjType) {
            $_[3][$o]->{'{#SITEID}'}    = "$parentObjData->{'_id'}",
            $_[3][$o]->{'{#SITENAME}'}  = "$parentObjData->{'name'}";
            # In v3 'desc' key is not exist, and site desc == name
            $_[3][$o]->{'{#SITEDESC}'}  = $parentObjData->{'desc'} ? "$parentObjData->{'desc'}" : "$parentObjData->{'name'}";
         } elsif (OBJ_USW eq $parentObjType) {
            $_[3][$o]->{'{#USWID}'}     = "$parentObjData->{'_id'}",
            $_[3][$o]->{'{#USWNAME}'}   = "$parentObjData->{'name'}",
            $_[3][$o]->{'{#USWMAC}'}    = "$parentObjData->{'mac'}";
         } elsif (OBJ_UAP eq $parentObjType) {
            $_[3][$o]->{'{#UAPID}'}     = "$parentObjData->{'_id'}",
            $_[3][$o]->{'{#UAPNAME}'}   = "$parentObjData->{'name'}",
            $_[3][$o]->{'{#UAPMAC}'}    = "$parentObjData->{'mac'}";
         }
      }

      #  add common fields
      $_[3][$o]->{'{#NAME}'}         = "$_->{'name'}"     if (exists($_->{'name'}));
      $_[3][$o]->{'{#ID}'}           = "$_->{'_id'}"      if (exists($_->{'_id'}));
      $_[3][$o]->{'{#IP}'}           = "$_->{'ip'}"       if (exists($_->{'ip'}));
      $_[3][$o]->{'{#MAC}'}          = "$_->{'mac'}"      if (exists($_->{'mac'}));
      $_[3][$o]->{'{#STATE}'}        = "$_->{'state'}"    if (exists($_->{'state'}));
      $_[3][$o]->{'{#ADOPTED}'}      = "$_->{'adopted'}"  if (exists($_->{'adopted'}));

      # add object specific fields
      if      (OBJ_WLAN eq $givenObjType ) {
         # is_guest key could be not exist with 'user' network on v3 
         $_[3][$o]->{'{#ISGUEST}'}   = "$_->{'is_guest'}" if (exists($_->{'is_guest'}));
      } elsif (OBJ_USER eq $givenObjType || OBJ_ALLUSER eq $givenObjType) {
         # sometime {hostname} may be null. UniFi controller replace that hostnames by {'mac'}
         $_[3][$o]->{'{#NAME}'}      = $_->{'hostname'} ? "$_->{'hostname'}" : "$_->{'mac'}",
         $_[3][$o]->{'{#OUI}'}       = "$_->{'oui'}";
      } elsif (OBJ_UPH eq $givenObjType) {
         $_[3][$o]->{'{#ID}'}        = "$_->{'device_id'}";
      } elsif (OBJ_SITE eq $givenObjType) {
         # In v3 'desc' key is not exist, and site desc == name
         $_[3][$o]->{'{#DESC}'} = $_->{'desc'} ? "$_->{'desc'}" : "$_->{'name'}";
      } elsif (OBJ_UAP_VAP_TABLE eq $givenObjType) {
         $_[3][$o]->{'{#UP}'}        = "$_->{'up'}",
         $_[3][$o]->{'{#USAGE}'}     = "$_->{'usage'}",
         $_[3][$o]->{'{#RADIO}'}     = "$_->{'radio'}",
         $_[3][$o]->{'{#ISWEP}'}     = "$_->{'is_wep'}",
         $_[3][$o]->{'{#ISGUEST}'}   = "$_->{'is_guest'}";
      } elsif (OBJ_USW_PORT_TABLE eq $givenObjType) {
         $_[3][$o]->{'{#PORTIDX}'}   = "$_->{'port_idx'}",
         $_[3][$o]->{'{#MEDIA}'}     = "$_->{'media'}",
         $_[3][$o]->{'{#UP}'}        = "$_->{'up'}",
         $_[3][$o]->{'{#PORTPOE}'}   = "$_->{'port_poe'}";
      } elsif (OBJ_HEALTH eq $givenObjType) {
         $_[3][$o]->{'{#SUBSYSTEM}'} = $_->{'subsystem'},
         $_[3][$o]->{'{#STATUS}'}    = $_->{'status'};
      } elsif (OBJ_NETWORK eq $givenObjType) {
         $_[3][$o]->{'{#PURPOSE}'} = $_->{'purpose'},
         $_[3][$o]->{'{#NETWORKGROUP}'} = $_->{'networkgroup'};
      } elsif (OBJ_EXTENSION eq $givenObjType) {
         $_[3][$o]->{'{#EXTENSION}'} = $_->{'extension'};
#         $_[3][$o]->{'{#TARGET}'} = $_->{'target'};
#         ;
#      } elsif ($givenObjType eq OBJ_USERGROUP) {
#         ;
#      } elsif (OBJ_UAP eq $givenObjType) {
#         ;
#      } elsif ($givenObjType eq OBJ_USG || $givenObjType eq OBJ_USW) {
#        ;
      }

      if (OBJ_ALLUSER eq $givenObjType) {
          delete $_[3][$o]->{'{#SITEID}'},
          delete $_[3][$o]->{'{#SITENAME}'},
          delete $_[3][$o]->{'{#SITEDESC}'},
          delete $_[3][$o]->{'{#MAC}'},
          delete $_[3][$o]->{'{#OUI}'},
          delete $_[3][$o]->{'{#NAME}'};
      }
     $o++;
    }
    logMessage(DEBUG_HIGH, "[<]\t Generated LLD piece:\n\t", $_[3]);
    logMessage(DEBUG_LOW, "[-] addToLLD() finished");
    return TRUE;
}
