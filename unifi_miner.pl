#!/usr/bin/perl
#
#  (C) Grigory Prigodin 2015-2016
#  Contact e-mail: zbx.sadman@gmail.com
#  tanx to Jakob Borg (https://github.com/calmh/unifi-api) for some methods and ideas 
# 
#
use strict;
use warnings;
use LWP ();
use POSIX ();
use JSON::XS ();
use Data::Dumper ();
use Time::HiRes ('clock_gettime');

# uncomment for fix 'SSL23_GET_SERVER_HELLO:unknown' error
#use IO::Socket::SSL ();
#IO::Socket::SSL::set_default_context(new IO::Socket::SSL::SSL_Context(SSL_version => 'tlsv1', SSL_verify_mode => 0));

use constant {
     TOOL_HOMEPAGE => 'https://github.com/zbx-sadman/unifi_miner',
     TOOL_NAME => 'UniFi Miner',
     TOOL_VERSION => '1.1.0',

     # *** Actions ***
     ACT_GET => 'get',
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

     # *** Debug levels ***
     DEBUG_LOW => 1,
     DEBUG_MID => 2,
     DEBUG_HIGH => 3,

     # *** other ***
     MAX_BUFFER_LEN => 65536,
     MAX_REQUEST_LEN => 256,
     KEY_ITEMS_NUM => 'items_num',
     TRUE => 1,
     FALSE => 0,
     BY_CMD => 1,
     BY_GET => 2,
     FETCH_NO_ERROR => 0,
     FETCH_OTHER_ERROR => 1,
     FETCH_LOGIN_ERROR => 2,
     TYPE_STRING => 1,
     TYPE_NUMBER => 2,
     ROUND_NUMBER => 2,
     ST_SAVE => 1,
     ST_REST => 2,

};

sub addToLLD;
sub fetchData;
sub fetchDataFromController;
sub getMetric;
sub logMessage;
sub writeStat;


#########################################################################################################################################
#
#  Default values for global scope
#
#########################################################################################################################################
my $globalConfig = {

   # Where are store cache file. Better place is RAM-disk
   'cachedir' => '/run/shm', 
   # How much time live cache data. Use 0 for disabling cache processes
   'cachemaxage' => 60,
   # Debug level 
   'debuglevel' => FALSE,

   # Default action for objects metric
   'action' => ACT_DISCOVERY,
   # Operation object. wlan is exist in any case
   'objecttype' => OBJ_WLAN, 
   # ID of object (usually defined thru -i option)
   # Name of your site. Used 'default' if defined as empty and -s option not used
   'sitename' => 'default', 
   # Where are controller answer. See value of 'unifi.https.port' in /opt/unifi/data/system.properties
   'unifilocation' => 'https://127.0.0.1:8443', 
   # UniFi controller version
   'unifiversion' => CONTROLLER_VERSION_4,
   # who can read data with API
   'unifiuser' => 'stat',
   # His pass
   'unifipass' => 'stat',
   # LWP timeout
   'unifitimeout' => 60,
   #
   'nullchar' => '',
   #id => '',
   # key for count/get/sum acions
   #key => 'name',
   # MAC of object (usually defined thru -m option)
   #mac => '',
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
   # Sitename which replaced {'sitename'} if '-s' option not used
   'default_sitename' => 'default', 
   # -s option used sign
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
       $options->{$1} = $_ if (defined ($1));
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

# Rewrite default values by command line arguments
$globalConfig->{'objecttype'}     = $options->{'o'} if defined ($options->{'o'});

$globalConfig->{'action'}         = $options->{'a'} if defined ($options->{'a'});
$globalConfig->{'ispact'}         = (ACT_PSUM eq $globalConfig->{'action'} || ACT_PCOUNT eq $globalConfig->{'action'}) ? TRUE : FALSE;
$globalConfig->{'key'}            = $options->{'k'} if defined ($options->{'k'});
# option -s not '' -> use given sitename. Otherwise use 'default'
$globalConfig->{'sitename'}       = $options->{'s'}, $globalConfig->{'sitename_given'} = TRUE if (defined ($options->{'s'}));
$globalConfig->{'cachemaxage'}    = 0+$options->{'c'} if defined ($options->{'c'});
$globalConfig->{'unifiversion'}   = $options->{'v'} if defined ($options->{'v'});
$globalConfig->{'unifiuser'}      = $options->{'u'} if defined ($options->{'u'});
$globalConfig->{'unifipass'}      = $options->{'p'} if defined ($options->{'p'});
$globalConfig->{'unifilocation'}  = $options->{'l'} if defined ($options->{'l'});
$globalConfig->{'debuglevel'}     = $options->{'d'} if defined ($options->{'d'});
$globalConfig->{'nullchar'}       = $options->{'n'} if defined ($options->{'n'});
$globalConfig->{'key'}            = $options->{'k'} if defined ($options->{'k'});
$globalConfig->{'mac'}            = $options->{'m'} if defined ($options->{'m'});
if (defined($options->{'i'})) {
   if ( uc($options->{'i'}) =~ m/^(?:[0-9A-Z]{2}[:-]){5}(:?[0-9A-Z]{2})$/ ) {
      $globalConfig->{'mac'} = $options->{'i'};
   } else {
      $globalConfig->{'id'} = $options->{'i'};
      $globalConfig->{'mac'} = '';
   }
}

$globalConfig->{'api_path'}       = "$globalConfig->{'unifilocation'}/api";
$globalConfig->{'login_path'}     = "$globalConfig->{'unifilocation'}/login";
$globalConfig->{'logout_path'}    = "$globalConfig->{'unifilocation'}/logout";
$globalConfig->{'login_data'}     = "username=$globalConfig->{'unifiuser'}&password=$globalConfig->{'unifipass'}&login=login";
$globalConfig->{'login_type'}     = 'x-www-form-urlencoded';
# Set controller version specific data
if (CONTROLLER_VERSION_4 eq $globalConfig->{'unifiversion'}) {
   $globalConfig->{'login_path'}  = "$globalConfig->{'unifilocation'}/api/login";
   $globalConfig->{'login_data'}  = "{\"username\":\"$globalConfig->{'unifiuser'}\",\"password\":\"$globalConfig->{'unifipass'}\"}",
   $globalConfig->{'login_type'}  = 'json',
   # Data fetch rules.
   # BY_GET mean that data fetched by HTTP GET from .../api/[s/<site>/]{'path'} operation.
   #    [s/<site>/] must be excluded from path if {'excl_sitename'} is defined
   # BY_CMD say that data fetched by HTTP POST {'cmd'} to .../api/[s/<site>/]{'path'}
   #
   $globalConfig->{'fetch_rules'} = {
      OBJ_SITE      , {'method' => BY_GET, 'path' => 'self/sites', 'excl_sitename' => TRUE},
      OBJ_UAP       , {'method' => BY_GET, 'path' => 'stat/device', 'short_way' => TRUE},
      OBJ_UPH       , {'method' => BY_GET, 'path' => 'stat/device', 'short_way' => TRUE},
      OBJ_USG       , {'method' => BY_GET, 'path' => 'stat/device', 'short_way' => TRUE},
      OBJ_USW       , {'method' => BY_GET, 'path' => 'stat/device', 'short_way' => TRUE},
      OBJ_SYSINFO   , {'method' => BY_GET, 'path' => 'stat/sysinfo'},
      OBJ_USER      , {'method' => BY_GET, 'path' => 'stat/sta'},
      OBJ_ALLUSER   , {'method' => BY_GET, 'path' => 'stat/alluser'},
      OBJ_HEALTH    , {'method' => BY_GET, 'path' => 'stat/health'},
      OBJ_NETWORK   , {'method' => BY_GET, 'path' => 'list/networkconf'},
      OBJ_EXTENSION , {'method' => BY_GET, 'path' => 'list/extension'},
      OBJ_NUMBER    , {'method' => BY_GET, 'path' => 'list/number'},
      OBJ_USERGROUP , {'method' => BY_GET, 'path' => 'list/usergroup'},
      OBJ_SETTING   , {'method' => BY_GET, 'path' => 'get/setting'},
      OBJ_WLAN      , {'method' => BY_GET, 'path' => 'list/wlanconf'},
      OBJ_USW_PORT_TABLE , {'method' => BY_GET, 'path' => 'stat/device', 'short_way' => TRUE},
      OBJ_UAP_VAP_TABLE  , {'method' => BY_GET, 'path' => 'stat/device', 'short_way' => TRUE},
   };
} elsif (CONTROLLER_VERSION_3 eq $globalConfig->{'unifiversion'}) {
       $globalConfig->{'fetch_rules'} = {
          OBJ_SITE      , {'method' => BY_CMD, 'path' => 'cmd/sitemgr', 'cmd' => '{"cmd":"get-sites"}'},
          #OBJ_SYSINFO   , {'method' => BY_GET, 'path' => 'stat/sysinfo'},
          OBJ_UAP       , {'method' => BY_GET, 'path' => 'stat/device'},
          OBJ_USER      , {'method' => BY_GET, 'path' => 'stat/sta'},
          OBJ_WLAN      , {'method' => BY_GET, 'path' => 'list/wlanconf'}
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

logMessage("[.] globalConfig:\n".(Data::Dumper::Dumper $globalConfig), DEBUG_MID) if ($globalConfig->{'debuglevel'} >= DEBUG_MID);

################################################## Main action ##################################################
# made fake site list, cuz fetchData(v2) just ignore sitename
my $buffer, my $buferLength, my $objList, my $lldPiece, my $bytes, my $parentObj, my $objListSize;
my $siteList = [{'name' => $globalConfig->{'sitename'}}];

if ($globalConfig->{'fetch_rules'}->{$globalConfig->{'objecttype'}}) {

   # if OBJ_SITE exists in fetch_rules - siteList could be obtained for 'discovery' action or in case with undefuned sitename
   if ($globalConfig->{'fetch_rules'}->{OBJ_SITE()} && (ACT_DISCOVERY eq $globalConfig->{'action'} || !$globalConfig->{'sitename_given'}))  {
      # Clear array, because fetchData() will push data to its
      undef $siteList;
      # Get site list. v3 need {'sitename'} to use into 'cmd' URI
      fetchData($globalConfig, $globalConfig->{'sitename'}, OBJ_SITE, '', $siteList);
   }

   logMessage("[.]\t\t Going over all sites", DEBUG_MID);
   foreach my $siteObj (@{$siteList}) {
      # parentObject used for transfer site (or device) info to LLD. That data used for "parent"-related macro (like {#SITENAME}, {#UAPID})
      $parentObj = {};
      # skip hidden site 'super'
      next if (defined($siteObj->{'attr_hidden'}));
      # skip site, if '-s' option used and current site other, that given
      next if ($globalConfig->{'sitename_given'} && ($globalConfig->{'sitename'} ne $siteObj->{'name'}));

      logMessage("[.]\t\t Handle site: '$siteObj->{'name'}'", DEBUG_MID);
      undef $objList;
      # make parent object from siteObj for made right macroses in addToLLD() sub
      $parentObj = {'type' => OBJ_SITE, 'data' => $siteObj};
      # user ask info for 'site' object. Data already loaded to $siteObj.
      if (OBJ_SITE eq $globalConfig->{'objecttype'}) {
         # Just make array from site object (which is hash) and take null for parenObj - no parent for 'site' exists
         $objList = [$siteObj], $parentObj = {'type' => ''};
      } else {
         # Take objects from foreach'ed site
         fetchData($globalConfig, $siteObj->{'name'}, $globalConfig->{'objecttype'}, $globalConfig->{'id'}, $objList) or $buffer = "[!] No data fetched from site '$siteObj->{'name'}', stop", logMessage($buffer, DEBUG_MID), last;
      }

      logMessage("[.]\t\t Objects list:\n\t".(Data::Dumper::Dumper $objList), DEBUG_HIGH) if ($globalConfig->{'debuglevel'} >= DEBUG_HIGH);
      # check requested key
      if (! $globalConfig->{'key'}) {
         # No key given - user need to discovery objects. 
         logMessage("[.]\t\t Discovering w/o key: add part of LLD", DEBUG_MID);
         addToLLD($globalConfig, $parentObj, $objList, $lldPiece) if ($objList);
      } else {
         # key is defined - any action could be processed
         logMessage("[*]\t\t Key given: $globalConfig->{'key'}", DEBUG_LOW);
         # How much objects into list?
         $objListSize = defined(@{$objList}) ? @{$objList} : 0;
         logMessage("[.]\t\t Objects list size: $objListSize", DEBUG_MID);
         # need 'discovery' action?
         if (ACT_DISCOVERY eq $globalConfig->{'action'}) {
            logMessage("[.]\t\t Discovery with key $globalConfig->{'key'}", DEBUG_MID);
            # Going over all object, because user can ask for key-based LLD
            for (my $i = 0; $i < $objListSize; $i++) {
                $_ = @{$objList}[$i];
                logMessage("[.]\t\t Key is '$_[0]->{'key'}', check its existiense in JSON", DEBUG_MID);
                # Given key have corresponding JSON-key?
                if (exists($_->{$globalConfig->{'key'}})) {
                   logMessage("[.]\t\t Corresponding JSON-key is found", DEBUG_MID);
                   # prepare parent object
                   $parentObj = { 'type' => $globalConfig->{'objecttype'}, 'data' => $_};
                   # test JSON-key type
                   if ('ARRAY' eq ref($_->{$globalConfig->{'key'}})) {
                      # Array: use this nested array instead object
                      $_ = $_->{$globalConfig->{'key'}};
                      logMessage("[.]\t\t JSON-key refer to ARRAY", DEBUG_MID);
                   } elsif ('HASH' eq ref($_->{$globalConfig->{'key'}})) {
                      # Hash: make one-elementh array from hash
                      $_ = [$_->{$globalConfig->{'key'}}];
                      logMessage("[.]\t\t JSON-key refer to HASH", DEBUG_MID);
                   } else {
                      # Other types can't be processed with LLD, force skip adding data to LLD
                      undef $_;
                   } # if 'ARRAY' eq ref...
                } else {
                   # No JSON-key exists, force skip adding data to LLD
                   undef $_;
                } # if exists($_->..{'key'})
                # Add data to LLD-response if its exists 
                addToLLD($globalConfig, $parentObj, $_, $lldPiece) if ($_);
            } #  for (... $i < $objListSize...)
         }  else {  # if ACT_DISCOVERY 
            # Other than 'discovery' action need - use getMetric() sub and store result to temporary variable
            getMetric($globalConfig, $objList, $globalConfig->{'key'}, $_);
            # 'get' - just get data from first site's first object  in objectList and jump out from loop
            $buffer = $_, last if (ACT_GET eq $globalConfig->{'action'});
            # with other actions sum result & go to next iteration
            $buffer += $_;
         } # if ACT_DISCOVERY ... else 

     } # if (! $globalConfig->{'key'}) ...else...
   } #foreach sites
} else {
   $buffer="[!] No object type $globalConfig->{'objecttype'} supported";
   logMessage($buffer, DEBUG_LOW);
}
 ################################################## Final stage of main loop  ##################################################
    # Made rounded number from result of 'percent-count', 'percent-sum' actions
    $buffer = sprintf("%.".ROUND_NUMBER."f", ((0 == @{$siteList}) ? 0 : ($buffer/@{$siteList}))) if ($globalConfig->{'ispact'});

    # Form JSON from result for 'discovery' action
    if (ACT_DISCOVERY eq $globalConfig->{'action'}) {
       logMessage("[.] Make LLD JSON", DEBUG_MID);
       defined($lldPiece) or logMessage("[!] No data found for object $globalConfig->{'objecttype'} (may be wrong site name), stop", DEBUG_MID), return FALSE;
       # link LLD to {'data'} key
       undef $buffer,
       $buffer->{'data'} = $lldPiece,
       # make JSON
       $buffer = $globalConfig->{'jsonxs'}->encode($buffer);
    }

    # Value could be null-type (undef in Perl). If need to replace null to other char - {'null_char'} must be defined. On default $globalConfig->{'null_char'} is ''
    $buffer = $globalConfig->{'null_char'} unless defined($buffer);
    $buferLength = length($buffer);
    # MAX_BUFFER_LEN - Zabbix buffer length. Sending more bytes have no sense.
    if ( MAX_BUFFER_LEN <= $buferLength) {
        $buferLength = MAX_BUFFER_LEN-1, 
        $buffer = substr($buffer, 0, $buferLength);
    }
    # Push buffer to socket with \n and buffer lenght + 1
    $buffer .= "\n", $buferLength++, print $buffer;
  

  # Logout need if logging in before (in fetchData() sub) completed
  logMessage("[*]\t Logout from UniFi controller", DEBUG_LOW);
  $globalConfig->{'ua'}->get($globalConfig->{'logout_path'}) if (defined($globalConfig->{'ua'}));
#  logMessage("[-] handleConnection() finished", DEBUG_LOW);

# Push result of work to stdout

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
    return unless ($globalConfig->{'debuglevel'} >= $_[1]);
    print "[$$] ", POSIX::strftime("%Y-%m-%d %H:%M:%S", localtime(time())), " $_[0]\n";
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
    my $keepKeyPos = FALSE, my $filterPassed = 0, my $isLastFilter = FALSE, my $actCurrentValue, my $i;

    logMessage("[+] getMetric() started", DEBUG_LOW);
    logMessage("[>]\t args: key: '$_[2]', action: '$_[0]->{'action'}'", DEBUG_LOW);
    logMessage("[>]\t incoming object info:'\n\t".(Data::Dumper::Dumper $_[1]), DEBUG_HIGH) if ($globalConfig->{'debuglevel'} >= DEBUG_HIGH);

    # split key to parts for analyze
    my @keyParts = split (/[.]/, $_[2]);
    #print Dumper @keyParts;

    # do analyzing, put subkeys to array, processing filter expressions
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
              push($keyParts[$i]->{'e'}, {'k'=>$1, 's' => $2, 'v'=> $3}) if ($fStrings[$k] =~ /^(.+)(=|<>)(.+)$/);
           }
           # count the number of filter expressions
           $nFilters++;
        } else {
           # If no filter-key detected - just store taked key and set its 'logic' to undef for 'no filter used' case
           $keyParts[$i] = {'e' => $swap, 'l' => undef};
        }
    }
    #print Dumper @keyParts;

    # If user want numeric values of result (SUM, COUNT, etc) - init variable as numeric
    $_[3] = (ACT_GET eq $_[0]->{'action'}) ? '' : 0;
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
              $_[3] = @{@{$stack}[$stackPos-1]}[2]; last;
           }

           # Do filter tests with this item
           if (defined($keyParts[$keyPos]->{'l'})) {
              my $fData = $keyParts[$keyPos]->{'e'}, my $matchCount=0;
              # run trought flter list
              for ($i = 0; $i < @{$fData}; $i++ ) {
#                  # if key (from filter) in object is defined.
                  if (defined($currentRoot->{@{$fData}[$i]->{'k'}})) {
                     # '&' logic need to use
                     if ('&' eq $keyParts[$keyPos]->{'l'}) {
                        # JSON key value equal / not equal (depend of equation sign) to value of filter - increase counter
                        $matchCount++ if ('='  eq @{$fData}[$i]->{'s'} && ($currentRoot->{@{$fData}[$i]->{'k'}} eq @{$fData}[$i]->{'v'}));
                        $matchCount++ if ('<>' eq @{$fData}[$i]->{'s'} && ($currentRoot->{@{$fData}[$i]->{'k'}} ne @{$fData}[$i]->{'v'}));
                     # '|' logic need to use
                     } elsif ('|' eq $keyParts[$keyPos]->{'l'}) {
                        # JSON key value equal / not equal (depend of equation sign) to value of filter - all filters is passed, leave local loop
                        $matchCount = @{$fData}, last if ('='  eq @{$fData}[$i]->{'s'} && ($currentRoot->{@{$fData}[$i]->{'k'}} eq @{$fData}[$i]->{'v'}));
                        $matchCount = @{$fData}, last if ('<>' eq @{$fData}[$i]->{'s'} && ($currentRoot->{@{$fData}[$i]->{'k'}} ne @{$fData}[$i]->{'v'}));
                     }
                  }
              }

              # is last key-filter ?
              $isLastFilter = ($keyPos == $nFilters) ? TRUE : FALSE;
              # part of key was filter expression and object is matched
              if (defined($keyParts[$keyPos]->{'l'}) && $matchCount == @{$fData}) {
                 # Object is good - just skip filter expression and work
                 $filterPassed++;
              } else {
                # Object is bad
                # If P* actions is used - need to count all values that matched to all key-filters or unmatched only last key-filter
                $state = ST_REST, next if (!$_[0]->{'ispact'} && $isLastFilter);
              }
              # just skip key-filter after analyze
              $keyPos++;
              # and do not jump to next loop if analyzed last key-filter
              next if (!$isLastFilter);
           }
           # end of filter work part

           # hash with name equal key part is reached from current root with one hop?
           if (exists($currentRoot->{$keyParts[$keyPos]->{'e'}})) {
              # Yes, hash item found
              # Key is point to final subkey or we can dive more?
              if (!defined($keyParts[$keyPos+1])) {
                 # Searched item is found, take it's value
                 # all filters is passed? ($nFilters - $filterPassed) must be 0 if true
                 # current value allowed to action when all filters passed
                 $actCurrentValue  = (($nFilters - $filterPassed) == 0) ? TRUE : FALSE;
                 # do action
                 if (ACT_GET eq $_[0]->{'action'}) {
                    # GET value and exit from search loop
                    $_[3] = $currentRoot->{$keyParts[$keyPos]->{'e'}}, last if ($actCurrentValue);
                 } elsif (ACT_COUNT eq $_[0]->{'action'} || ACT_PCOUNT eq $_[0]->{'action'})  {
                    # COUNT values
                    $allValues++ if ($_[0]->{'ispact'});
                    $_[3]++      if ($actCurrentValue);
                 } elsif (ACT_SUM eq $_[0]->{'action'} || ACT_PSUM eq $_[0]->{'action'}) {
                    # SUM values
                    $allValues += $currentRoot->{$keyParts[$keyPos]->{'e'}} if ($_[0]->{'ispact'});
                    $_[3] += $currentRoot->{$keyParts[$keyPos]->{'e'}}      if ($actCurrentValue);
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

 # User want to get percent of matched items: all processed values is 100%.
 # Proceseed values placed into item, that full matched to filter-key or unmatched _only_ with last filter expression.
 if ($_[0]->{'ispact'}) { $_[3] = (0 == $allValues) ? '0' : sprintf("%.".ROUND_NUMBER."f", $_[3]/($allValues/100)); }

 logMessage("[<] result: ($_[3])", DEBUG_LOW) if (defined($_[3]));
 logMessage("[-] getMetric() finished ", DEBUG_LOW);
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
   logMessage("[+] fetchData() started", DEBUG_LOW);
   logMessage("[>]\t args: object type: '$_[0]->{'objecttype'}'", DEBUG_MID);
   logMessage("[>]\t id: '$_[3]'", DEBUG_MID) if ($_[3]);
   logMessage("[>]\t mac: '$_[0]->{'mac'}'", DEBUG_MID) if ($_[0]->{'mac'});
   my ($fh, $jsonData, $objPath),
   my $needReadCache = TRUE;

   $objPath  = $_[0]->{'api_path'} . ($_[0]->{'fetch_rules'}->{$_[2]}->{'excl_sitename'} ? '' : "/s/$_[1]") . "/$_[0]->{'fetch_rules'}->{$_[2]}->{'path'}";
   # if MAC is given with command-line option -  RapidWay for Controller v4 is allowed, short_way is tested for non-device objects workaround
   $objPath .= "/$_[0]->{'mac'}" if ($_[0]->{'fetch_rules'}->{$_[2]}->{'short_way'} && $_[0]->{'mac'});
   logMessage("[.]\t\t Object path: '$objPath'", DEBUG_MID);

   ################################################## Take JSON  ##################################################

   # If CacheMaxAge = 0 - do not try to read/update cache - fetch data from controller
   if (0 == $_[0]->{'cachemaxage'}) {
      logMessage("[.]\t\t No read/update cache because CacheMaxAge = 0", DEBUG_MID);
      fetchDataFromController($_[0], $objPath, $jsonData) or logMessage("[!] Can't fetch data from controller, stop", DEBUG_LOW), return FALSE;
   } else {
      # Change all [:/.] to _ to make correct filename
      my $cacheFileName;
      ($cacheFileName = $objPath) =~ tr/\/\:\./_/, 
      $cacheFileName = $_[0]->{'cachedir'} .'/'. $cacheFileName;
      my $cacheFileMTime = (stat($cacheFileName))[9];
      # cache file unexist (mtime is undef) or regular?
      ($cacheFileMTime && (!-f $cacheFileName)) and logMessage("[!] Can't handle '$cacheFileName' through its not regular file, stop.", DEBUG_LOW), return FALSE;
      # cache is expired if: unexist (mtime is undefined) OR (file exist (mtime is defined) AND its have old age) 
      #                                                   OR have Zero size (opened, but not filled or closed with error)
      my $cacheExpire=(((! defined($cacheFileMTime)) || defined($cacheFileMTime) && (($cacheFileMTime+$_[0]->{'cachemaxage'}) < time())) ||  -z $cacheFileName) ;

      if ($cacheExpire) {
         # Cache expire - need to update
         logMessage("[.]\t\t Cache expire or not found. Renew...", DEBUG_MID);
         my $tmpCacheFileName = $cacheFileName . ".tmp";
         # Temporary cache filename point to non regular file? If so - die to avoid problem with write or link/unlink operations
         # $_ not work
         ((-e $tmpCacheFileName) && (!-f $tmpCacheFileName)) and logMessage("[!] Can't handle '$tmpCacheFileName' through its not regular file, stop.", DEBUG_LOW), return FALSE;
         logMessage("[.]\t\t Temporary cache file='$tmpCacheFileName'", DEBUG_MID);
         open ($fh, ">", $tmpCacheFileName) or logMessage("[!] Can't open '$tmpCacheFileName' ($!), stop.", DEBUG_LOW), return FALSE;
         # try to lock temporary cache file and no wait for able locking.
         # LOCK_EX | LOCK_NB
         if (flock ($fh, 2 | 4)) {
            # if Proxy could lock temporary file, it...
            chmod (0666, $fh);
            # ...fetch new data from controller...
            fetchDataFromController($_[0], $objPath, $jsonData) or logMessage("[!] Can't fetch data from controller, stop", DEBUG_LOW), close ($fh), return FALSE;
            # unbuffered write it to temp file..
            syswrite ($fh, $_[0]->{'jsonxs'}->encode($jsonData));
            # Now unlink old cache filedata from cache filename 
            # All processes, who already read data - do not stop and successfully completed reading
            unlink ($cacheFileName);
            # Link name of cache file to temp file. File will be have two link - to cache and to temporary cache filenames. 
            # New run down processes can get access to data by cache filename
            link($tmpCacheFileName, $cacheFileName) or logMessage("[!] Presumably no rights to unlink '$cacheFileName' file ($!). Try to delete it ", DEBUG_LOW), return FALSE;
            # Unlink temp filename from file. 
            # Process, that open temporary cache file can do something with filedata while file not closed
            unlink($tmpCacheFileName) or logMessage("[!] '$tmpCacheFileName' unlink error ($!), stop", DEBUG_LOW), return FALSE;
            # Close temporary file. close() unlock filehandle.
            #close($fh) or logMessage("[!] Can't close locked temporary cache file '$tmpCacheFileName' ($!), stop", DEBUG_LOW), return FALSE; 
            # No cache read from file need
           $needReadCache=FALSE;
        } 
        close ($fh) or logMessage("[!] Can't close temporary cache file '$tmpCacheFileName' ($!), stop", DEBUG_LOW), return FALSE;
      } # if ($cacheExpire)

      # if need load data from cache file
      if ($needReadCache) {
       # open file
       open($fh, "<:mmap", $cacheFileName) or logMessage("[!] Can't open '$cacheFileName' ($!), stop.", DEBUG_LOW), return FALSE;
       # read data from file
       $jsonData=$_[0]->{'jsonxs'}->decode(<$fh>);
       # close cache
       close($fh) or logMessage( "[!] Can't close cache file ($!), stop.", DEBUG_LOW), return FALSE;
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
#       print "id: @{$jsonData}[$i]->{$idKey} \n";
       $_[4][0] = @{$jsonData}[$i], last if (@{$jsonData}[$i]->{$idKey} eq $_[3]);
     } else {
       # otherwise
       push (@{$_[4]}, @{$jsonData}[$i]) if (!exists(@{$jsonData}[$i]->{'type'}) || (@{$jsonData}[$i]->{'type'} eq $_[2]));
     }
   } # for each jsonData

   logMessage("[<]\t Fetched data:\n\t".(Data::Dumper::Dumper $_[4]), DEBUG_HIGH) if ($globalConfig->{'debuglevel'} >= DEBUG_HIGH);
   logMessage("[-] fetchData() finished", DEBUG_LOW);
   return TRUE;
}

#*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/
#
#  Fetch data from from controller.
#
#*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/
sub fetchDataFromController {
   # $_[0] - GlobalConfig
   # $_[1] - object path
   # $_[2] - jsonData object ref
   my $response, my $fetchType = $_[0]->{'fetch_rules'}->{$_[0]->{'objecttype'}}->{'method'},
   my $fetchCmd = $_[0]->{'fetch_rules'}->{$_[0]->{'objecttype'}}->{'cmd'}, my $errorCode;

   logMessage("[+] fetchDataFromController() started", DEBUG_LOW);
   logMessage("[>]\t args: object path: '$_[1]'", DEBUG_LOW);

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
   if ($response->code eq '401') {
        # logging in
        logMessage("[.]\t\tTry to log in into controller...", DEBUG_LOW);
        $response = $_[0]->{'ua'}->post($_[0]->{'login_path'}, 'Content_type' => "application/$_[0]->{'login_type'}",'Content' => $_[0]->{'login_data'});
        logMessage("[>>]\t\t HTTP respose:\n\t".(Data::Dumper::Dumper $response), DEBUG_HIGH) if ($globalConfig->{'debuglevel'} >= DEBUG_HIGH);
        $errorCode = $response->is_error;
        if ($_[0]->{'unifiversion'} eq CONTROLLER_VERSION_4) {
           # v4 return 'Bad request' (code 400) on wrong auth
           # v4 return 'OK' (code 200) on success login
           ($response->code eq '400') and $errorCode=FETCH_LOGIN_ERROR;
        } elsif (($_[0]->{'unifiversion'} eq CONTROLLER_VERSION_3) || ($_[0]->{'unifiversion'} eq CONTROLLER_VERSION_2)) {
           # v3 return 'OK' (code 200) on wrong auth
           ($response->code eq '200') and $errorCode=FETCH_LOGIN_ERROR;
           # v3 return 'Redirect' (code 302) on success login and must die only if code<>302
           ($response->code eq '302') and $errorCode=FETCH_NO_ERROR;
        }
    }
    ($errorCode == FETCH_LOGIN_ERROR) and logMessage("[!] Login error - wrong auth data, stop", DEBUG_LOW), return FALSE;
    ($errorCode == FETCH_OTHER_ERROR) and logMessage("[!] Comminication error: '".($response->status_line)."', stop.\n", DEBUG_LOW), return FALSE;

    logMessage("[.]\t\tLogin successfull", DEBUG_LOW);

   ################################################## Fetch data from controller  ##################################################

   if (BY_CMD == $fetchType) {
      logMessage("[.]\t\t Fetch data with CMD method: '$fetchCmd'", DEBUG_MID);
      $response = $_[0]->{'ua'}->post($_[1], 'Content_type' => 'application/json', 'Content' => $fetchCmd);
   } else { #(BY_GET == $fetchType)
      logMessage("[.]\t\t Fetch data with GET method from: '$_[1]'", DEBUG_MID);
      $response = $_[0]->{'ua'}->get($_[1]);
   }

   ($response->is_error == FETCH_OTHER_ERROR) and logMessage("[!] Comminication error while fetch data from controller: '".($response->status_line)."', stop.\n", DEBUG_LOW), return FALSE;
   
   logMessage("[>>]\t\t Fetched data:\n\t".(Data::Dumper::Dumper $response->decoded_content), DEBUG_HIGH) if ($globalConfig->{'debuglevel'} >= DEBUG_HIGH);;
   $_[2] = $_[0]->{'jsonxs'}->decode(${$response->content_ref()});


   # server answer is ok ?
   (($_[2]->{'meta'}->{'rc'} ne 'ok') && (defined($_[2]->{'meta'}->{'msg'}))) and  logMessage("[!] UniFi controller reply is not OK: '$_[2]->{'meta'}->{'msg'}', stop.", DEBUG_LOW);
   $_[2] = $_[2]->{'data'};
   logMessage("[<]\t decoded data:\n\t".(Data::Dumper::Dumper $_[2]), DEBUG_HIGH) if ($globalConfig->{'debuglevel'} >= DEBUG_HIGH);
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
    my $givenObjType  = $_[0]->{'objecttype'}.($_[0]->{'key'} ? "_$_[0]->{'key'}" : '');
    my $parentObjType = $_[1]->{'type'}, my $parentObjData;
    $parentObjData = $_[1]->{'data'} if (defined($_[1]));

    logMessage("[+] addToLLD() started", DEBUG_LOW); logMessage("[>]\t args: object type: '$_[0]->{'objecttype'}'", DEBUG_MID); 
    logMessage("[>]\t Site name: '$_[1]->{'name'}'", DEBUG_MID) if ($_[1]->{'name'});
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
            $_[3][$o]->{'{#SITEID}'}    = "$parentObjData->{'_id'}";
            $_[3][$o]->{'{#SITENAME}'}  = "$parentObjData->{'name'}";
            # In v3 'desc' key is not exist, and site desc == name
            $_[3][$o]->{'{#SITEDESC}'}  = $parentObjData->{'desc'} ? "$parentObjData->{'desc'}" : "$parentObjData->{'name'}";
         } elsif (OBJ_USW eq $parentObjType) {
            $_[3][$o]->{'{#USWID}'}     = "$parentObjData->{'_id'}";
            $_[3][$o]->{'{#USWNAME}'}   = "$parentObjData->{'name'}";
            $_[3][$o]->{'{#USWMAC}'}    = "$parentObjData->{'mac'}";
         } elsif (OBJ_UAP eq $parentObjType) {
            $_[3][$o]->{'{#UAPID}'}     = "$parentObjData->{'_id'}";
            $_[3][$o]->{'{#UAPNAME}'}   = "$parentObjData->{'name'}";
            $_[3][$o]->{'{#UAPMAC}'}    = "$parentObjData->{'mac'}";
         }
      }

      #  add common fields
      $_[3][$o]->{'{#NAME}'}         = "$_->{'name'}"     if (exists($_->{'name'}));
      $_[3][$o]->{'{#ID}'}           = "$_->{'_id'}"      if (exists($_->{'_id'}));
      $_[3][$o]->{'{#IP}'}           = "$_->{'ip'}"       if (exists($_->{'ip'}));
      $_[3][$o]->{'{#MAC}'}          = "$_->{'mac'}"      if (exists($_->{'mac'}));
      # state of object: 0 - off, 1 - on
      $_[3][$o]->{'{#STATE}'}        = "$_->{'state'}"    if (exists($_->{'state'}));
      $_[3][$o]->{'{#ADOPTED}'}      = "$_->{'adopted'}"  if (exists($_->{'adopted'}));

      # add object specific fields
      if      (OBJ_WLAN eq $givenObjType ) {
         # is_guest key could be not exist with 'user' network on v3 
         $_[3][$o]->{'{#ISGUEST}'}   = "$_->{'is_guest'}" if (exists($_->{'is_guest'}));
      } elsif (OBJ_USER eq $givenObjType || OBJ_ALLUSER eq $givenObjType) {
         # sometime {hostname} may be null. UniFi controller replace that hostnames by {'mac'}
         $_[3][$o]->{'{#NAME}'}      = $_->{'hostname'} ? "$_->{'hostname'}" : "$_->{'mac'}";
         $_[3][$o]->{'{#OUI}'}       = "$_->{'oui'}";
      } elsif (OBJ_UPH eq $givenObjType) {
         $_[3][$o]->{'{#ID}'}        = "$_->{'device_id'}";
      } elsif (OBJ_SITE eq $givenObjType) {
         # In v3 'desc' key is not exist, and site desc == name
         $_[3][$o]->{'{#DESC}'} = $_->{'desc'} ? "$_->{'desc'}" : "$_->{'name'}";
      } elsif (OBJ_UAP_VAP_TABLE eq $givenObjType) {
         $_[3][$o]->{'{#UP}'}        = "$_->{'up'}";
         $_[3][$o]->{'{#USAGE}'}     = "$_->{'usage'}";
         $_[3][$o]->{'{#RADIO}'}     = "$_->{'radio'}";
         $_[3][$o]->{'{#ISWEP}'}     = "$_->{'is_wep'}";
         $_[3][$o]->{'{#ISGUEST}'}   = "$_->{'is_guest'}";
      } elsif (OBJ_USW_PORT_TABLE eq $givenObjType) {
         $_[3][$o]->{'{#PORTIDX}'}   = "$_->{'port_idx'}";
         $_[3][$o]->{'{#MEDIA}'}     = "$_->{'media'}";
         $_[3][$o]->{'{#UP}'}        = "$_->{'up'}";
         $_[3][$o]->{'{#PORTPOE}'}   = "$_->{'port_poe'}";
      } elsif (OBJ_HEALTH eq $givenObjType) {
         $_[3][$o]->{'{#SUBSYSTEM}'} = $_->{'subsystem'};
         $_[3][$o]->{'{#STATUS}'}    = $_->{'status'};
      } elsif (OBJ_NETWORK eq $givenObjType) {
         $_[3][$o]->{'{#PURPOSE}'} = $_->{'purpose'};
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
          delete $_[3][$o]->{'{#SITEID}'};
          delete $_[3][$o]->{'{#SITENAME}'};
          delete $_[3][$o]->{'{#SITEDESC}'};
          delete $_[3][$o]->{'{#MAC}'};
          delete $_[3][$o]->{'{#OUI}'};
          delete $_[3][$o]->{'{#NAME}'};
      }
     $o++;
    }
    logMessage("[<]\t Generated LLD piece:\n\t".(Data::Dumper::Dumper $_[3]), DEBUG_HIGH) if ($globalConfig->{'debuglevel'} >= DEBUG_HIGH);
    logMessage("[-] addToLLD() finished", DEBUG_LOW);
    return TRUE;
}
