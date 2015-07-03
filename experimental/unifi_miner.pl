#!/usr/bin/perl
#
#  (C) sadman@sfi.komi.com 2015
#  tanx to Jakob Borg (https://github.com/calmh/unifi-api) for some methods and ideas 
#
# 
#
use strict;
use warnings;
use Data::Dumper;
#use Time::HiRes ('clock_gettime');
use Getopt::Std ();
use JSON::XS ();
use LWP ();

# uncomment for fix 'SSL23_GET_SERVER_HELLO:unknown' error
#use IO::Socket::SSL;
#IO::Socket::SSL::set_default_context(new IO::Socket::SSL::SSL_Context(SSL_version => 'tlsv1', SSL_verify_mode => Net::SSLeay::VERIFY_NONE()));

use constant {
     ACT_COUNT => 'count',
     ACT_SUM => 'sum',
     ACT_GET => 'get',
     ACT_DISCOVERY => 'discovery',
     BY_CMD => 1,
     BY_GET => 2,
     CONTROLLER_VERSION_2 => 'v2',
     CONTROLLER_VERSION_3 => 'v3',
     CONTROLLER_VERSION_4 => 'v4',
     DEBUG_LOW => 1,
     DEBUG_MID => 2,
     DEBUG_HIGH => 3,
     KEY_ITEMS_NUM => 'items_num',
     MINER_VERSION => '0.99999',
     MSG_UNKNOWN_CONTROLLER_VERSION => 'Version of controller is unknown: ',
     OBJ_USW => 'usw',
     OBJ_USW_PORT => 'usw_port',
     OBJ_UPH => 'uph',
     OBJ_UAP => 'uap',
     OBJ_USG => 'usg',
     OBJ_WLAN => 'wlan',
     OBJ_USER => 'user',
     OBJ_SITE => 'site',
     OBJ_HEALTH => 'health',
#     OBJ_SYSINFO => 'sysinfo',
     TRUE => 1,
     FALSE => 0,

};

sub fetchData;
sub fetchDataFromController;
sub makeLLD;
sub addToLLD;
sub getMetric;
sub writeStat;
sub VERSION_MESSAGE;


#########################################################################################################################################
#
#  Default values for global scope
#
#########################################################################################################################################
my $globalConfig = {
   # Default action for objects metric
   action => ACT_GET,
   # How much time live cache data. Use 0 for disabling cache processes
   cache_timeout => 10800,
   # Where are store cache file. Better place is RAM-disk
   cache_root=> '/run/shm', 
   # Debug level 
   debug => FALSE,
   # ID of object (usually defined thru -i option)
   id => '',
   # key for count/get/sum acions
   key => '',
   # Where are controller answer. See value of 'unifi.https.port' in /opt/unifi/data/system.properties
   location => 'https://127.0.0.1:8443', 
   # MAC of object (usually defined thru -m option)
   mac => '',
   # Operation object. wlan is exist in any case
   object => OBJ_WLAN, 
   # Name of your site. Used 'default' if defined as empty and -s option not used
   sitename => '', 
   # Where to store statistic data
   stat_file => './stat.txt',
   # who can read data with API
   username => 'stat',
   # His pass
   password => 'stat',
   # UniFi controller version
   version => CONTROLLER_VERSION_4,
   # Write statistic to _statfile_ or not
   write_stat => FALSE,

   #####################################################################################################
   ###
   ###  Service keys here. Do not change.
   ###
   #####################################################################################################
   # HiRes time of Miner internal processing start (not include Module Init stage)
   start_time => 0,
   # HiRes time of Miner internal processing stop
   stop_time => 0,
   # Level of dive (recursive call) for getMetric subroutine
   dive_level => 1,
   # Max level to which getMetric is dived
   max_depth => 0,
   # Data is downloaded instead readed from file
   downloaded => FALSE,
   # LWP::UserAgent object, which must be saved between fetchData() calls
   ua => undef,
   # Already logged sign
   logged_in => FALSE,
   # Sitename which replaced {'sitename'} if '-s' option not used
   default_sitename => 'default', 
   # -s option used sign
   sitename_given => FALSE, 
  },

my @objJSON=(), my %options, my $res;

# print the version & help with --versin & --help
$Getopt::Std::STANDARD_HELP_VERSION=TRUE;

# clock_gettime(1)=> clock_gettime(CLOCK_MONOLITIC)
$globalConfig->{'start_time'}=clock_gettime(1) if ($globalConfig->{'write_stat'});

Getopt::Std::getopts('a:c:d:i:k:l:m:n:o:p:s:u:v:', \%options);

# Rewrite default values by command line arguments
$globalConfig->{'action'}        = $options{a} if defined $options{a};
$globalConfig->{'cache_timeout'} = $options{c} if defined $options{c};
$globalConfig->{'debug'}         = $options{d} if defined $options{d};
$globalConfig->{'id'}            = $options{i} if defined $options{i};
$globalConfig->{'key'}           = $options{k} if defined $options{k};
$globalConfig->{'location'}      = $options{l} if defined $options{l};
$globalConfig->{'mac'}           = $options{m} if defined $options{m};
$globalConfig->{'null_char'}     = $options{n} if defined $options{n};
$globalConfig->{'object'}        = $options{o} if defined $options{o};
$globalConfig->{'password'}      = $options{p} if defined $options{p};
$globalConfig->{'sitename'}      = $options{s} if defined $options{s};
$globalConfig->{'username'}      = $options{u} if defined $options{u};
$globalConfig->{'version'}       = $options{v} if defined $options{v};

# -s option used -> use sitename other, that sitename='default' in *LLD() subs
$globalConfig->{'sitename_given'}= (defined $options{s});
$globalConfig->{'sitename'}      = $globalConfig->{'default_sitename'} unless (defined $options{s} || $globalConfig->{'sitename'});

# Set controller version specific data
if ($globalConfig->{'version'} eq CONTROLLER_VERSION_4) {
   $globalConfig->{'api_path'}="$globalConfig->{'location'}/api",
   $globalConfig->{'login_path'}="$globalConfig->{'location'}/api/login",
   $globalConfig->{'login_data'}="{\"username\":\"$globalConfig->{'username'}\",\"password\":\"$globalConfig->{'password'}\"}",
   $globalConfig->{'login_type'}='json',
   $globalConfig->{'logout_path'}="$globalConfig->{'location'}/logout",
   # Data fetch rules. 
   # BY_GET mean that data fetched by HTTP GET from .../api/[s/<site>/]{'path'} operation.
   #    [s/<site>/] must be excluded from path if {'excl_sitename'} is defined
   # BY_CMD say that data fetched by HTTP POST {'cmd'} to .../api/[s/<site>/]{'path'}
   #
   $globalConfig->{'fetch_rules'}= { 
     # `&` let use value of constant, otherwise we have 'OBJ_UAP' => {...} instead 'uap' => {...}
#     &OBJ_HEALTH => {'method' => BY_GET, 'path' => 'stat/health'},
     &OBJ_SITE     => {'method' => BY_GET, 'path' => 'self/sites', 'excl_sitename' => TRUE},
     &OBJ_UAP      => {'method' => BY_GET, 'path' => 'stat/device'},
     &OBJ_UPH      => {'method' => BY_GET, 'path' => 'stat/device'},
     &OBJ_USG      => {'method' => BY_GET, 'path' => 'stat/device'},
     &OBJ_USW      => {'method' => BY_GET, 'path' => 'stat/device'},
     &OBJ_USW_PORT => {'method' => BY_GET, 'path' => 'stat/device'},
     &OBJ_USER     => {'method' => BY_GET, 'path' => 'stat/sta'},
     &OBJ_WLAN     => {'method' => BY_GET, 'path' => 'list/wlanconf'}
   };
} elsif ($globalConfig->{'version'} eq CONTROLLER_VERSION_3) {
   $globalConfig->{'api_path'}="$globalConfig->{'location'}/api",
   $globalConfig->{'login_path'}="$globalConfig->{'location'}/login",
   $globalConfig->{'login_data'}="username=$globalConfig->{'username'}&password=$globalConfig->{'password'}&login=login";
   $globalConfig->{'login_type'}='x-www-form-urlencoded',
   $globalConfig->{'logout_path'}="$globalConfig->{'location'}/logout",
   $globalConfig->{'fetch_rules'}= { 
     # `&` let use value of constant, otherwise we have 'OBJ_UAP' => {...} instead 'uap' => {...}
     &OBJ_SITE => {'method' => BY_CMD, 'path' => 'cmd/sitemgr', 'cmd' => '{"cmd":"get-sites"}'},
#     &OBJ_SYSINFO => {'method' => BY_GET, 'path' => 'stat/sysinfo'},
     &OBJ_UAP  => {'method' => BY_GET, 'path' => 'stat/device'},
     &OBJ_USER => {'method' => BY_GET, 'path' => 'stat/sta'},
     &OBJ_WLAN => {'method' => BY_GET, 'path' => 'list/wlanconf'}
   };
} elsif ($globalConfig->{'version'} eq CONTROLLER_VERSION_2) {
   $globalConfig->{'api_path'}="$globalConfig->{'location'}/api",
   $globalConfig->{'login_path'}="$globalConfig->{'location'}/login",
   $globalConfig->{'login_data'}="username=$globalConfig->{'username'}&password=$globalConfig->{'password'}&login=login";
   $globalConfig->{'login_type'}='x-www-form-urlencoded',
   $globalConfig->{'logout_path'}="$globalConfig->{'location'}/logout",
   $globalConfig->{'fetch_rules'}= { 
     # `&` let use value of constant, otherwise we have 'OBJ_UAP' => {...} instead 'uap' => {...}
     &OBJ_UAP  => {'method' => BY_GET, 'path' => 'stat/device', 'excl_sitename' => TRUE},
     &OBJ_WLAN => {'method' => BY_GET, 'path' => 'list/wlanconf', 'excl_sitename' => TRUE},
     &OBJ_USER => {'method' => BY_GET, 'path' => 'stat/sta', 'excl_sitename' => TRUE}
   };
} else {
   die MSG_UNKNOWN_CONTROLLER_VERSION, $globalConfig->{'version'}, ", stop.";
}

print "\n[.] globalConfig:'\n\t", Dumper $globalConfig if ($globalConfig->{'debug'} >= DEBUG_MID);
die "[!] Unknown object '$globalConfig->{'object'}' given, stop." unless ($globalConfig->{'fetch_rules'}->{$globalConfig->{'object'}}); 

# First - check for object type. ...but its always defined in 'my $globalConfig {' section
#if ($globalConfig->{'object'}) {
   # load JSON data
   # Ok. Type is defined. How about key?
   if ($globalConfig->{'key'}) {
       # Key is given - need to get metric. 
       # if $globalConfig->{'id'} is exist then metric of this object has returned. 
       # If not - calculate $globalConfig->{'action'} for all items in objects list (all object of type = 'object name', for example - all 'uap'
       fetchData($globalConfig, $globalConfig->{'object'}, \@objJSON);
       getMetric($globalConfig, \@objJSON, $globalConfig->{'key'}, $res);
   } else { 
       # Key is null - going generate LLD-like JSON from loaded data
       makeLLD($globalConfig, $res);
   }
#}

# Logout need if logging in before (in fetchData() sub) completed
print "\n[*] Logout from UniFi controller" if ($globalConfig->{'debug'} >= DEBUG_LOW);
$globalConfig->{'ua'}->get($globalConfig->{'logout_path'}) if ($globalConfig->{'logged_in'});

# Value could be 'null'. If need to replace null to other char - {'null_char'} must be defined
$res = $res ? $res : $globalConfig->{'null_char'} if (defined($globalConfig->{'null_char'}));

print "\n" if  ($globalConfig->{'debug'} >= DEBUG_LOW);

# Push result of work to stdout
print (defined($res) ? "$res\n" : "\n");

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

sub VERSION_MESSAGE
{
 print "UniFi Miner v", MINER_VERSION ," \n";
}

sub HELP_MESSAGE
{
 print "Sorry, but all help on https://github.com/zbx-sadman/unifi_miner\n";
 exit 0;
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
    print $fh "$_[0]->{'start_time'},$_[0]->{'stop_time'},$_[0]->{'version'},$_[0]->{'sitename'},$_[0]->{'object'},$_[0]->{'id'},$_[0]->{'mac'},$_[0]->{'key'},$_[0]->{action},$_[0]->{'max_depth'},$_[0]->{'downloaded'},$_[0]->{'debug'}\n";
    close $fh;
}

#####################################################################################################################################
#
#  Recursively go through the key and take/form value of metric
#
#####################################################################################################################################
sub getMetric {
    # $_[0] - GlobalConfig
    # $_[1] - array/hash with info
    # $_[2] - key
    # $_[3] - result

    # dive to...
    $_[0]->{'dive_level'}++;

    print "\n[+] ($_[0]->{'dive_level'}) getMetric() started" if ($_[0]->{'debug'} >= DEBUG_LOW);
    my $key=$_[2];

    print "\n[>]\t args: key: '$_[2]', action: '$_[0]->{'action'}'" if ($_[0]->{'debug'} >= DEBUG_MID);
    print "\n[>]\t incoming object info:'\n\t", Dumper $_[1] if ($_[0]->{'debug'} >= DEBUG_HIGH);

    # correcting maxDepth for ACT_COUNT operation
    $_[0]->{'max_depth'} = ($_[0]->{'dive_level'} > $_[0]->{'max_depth'}) ? $_[0]->{'dive_level'} : $_[0]->{'max_depth'};
    
    # Checking for type of $_[1]. 
    # if $_[1] is array - need to explore any element
    if (ref($_[1]) eq 'ARRAY') {
       my $paramValue, my $objList=@{$_[1]};
       print "\n[.]\t\t Array with ", $objList, " objects detected" if ($_[0]->{'debug'} >= DEBUG_MID);

       # if metric ask "how much items (AP's for example) in all" - just return array size (previously calculated in $objList) and do nothing more
       if ($key eq KEY_ITEMS_NUM) { 
          $_[3]=$objList; 
       } else {
          $_[3]=0; 
          print ", taking value from all sections" if ($_[0]->{'debug'} >= DEBUG_MID);
          # Take each element of array
          for (my $i=0; $i < $objList; $i++ ) {
            # Init $paramValue for right actions doing
            $paramValue=undef;
            # Do recursively calling getMetric func for each element 
            # that is bad strategy, because sub calling anytime without tesing of key existiense, but that testing can be slower, that sub recalling 
            #                                                                                                                    (if filter-key used)
            getMetric($_[0], $_[1][$i], $key, $paramValue); 
            print "\n[.]\t\t paramValue: '$paramValue'" if ($_[0]->{'debug'} >= DEBUG_HIGH);


            # Otherwise - do something line sum or count
            if (defined($paramValue)) {
               print "\n[.]\t\t act #$_[0]->{'action'} " if ($_[0]->{'debug'} >= DEBUG_MID);

               # With 'get' action jump out from loop with first recieved value
               $_[3]=$paramValue, last if ($_[0]->{'action'} eq ACT_GET);

               # !!! need to fix trying sum of not numeric values
               # With 'sum' - grow $result
               if ($_[0]->{'action'} eq ACT_SUM) { 
                  $_[3]+=$paramValue; 
               } elsif ($_[0]->{'action'} eq ACT_COUNT) {
                  # may be wrong algo :(
                  # workaround for correct counting with deep diving
                  # With 'count' we must count keys in objects, that placed only on last level
                  # in other case $result will be incremented by $paramValue (which is number of key in objects inside last level table)
                  if (($_[0]->{'max_depth'}-$_[0]->{'dive_level'}) < 2 ) {
                     $_[3]++; 
                  } else {
                     $_[3]+=$paramValue; 
                  }
              }
            }
            print "\n[.]\t\t Value: '$paramValue', result: '$_[3]'" if ($_[0]->{'debug'} >= DEBUG_MID);
          } #foreach 
       }
   } else { # if (ref($_[1]) eq 'ARRAY') {
      # it is not array (list of objects) - it's one object (hash)
      print "\n[.]\t\t Just one object detected." if ($_[0]->{'debug'} >= DEBUG_MID);
      my $tableName, my @fData=(), my $matchCount=0;
      ($tableName, $key) = split(/[.]/, $key, 2);

      # if key is not defined after split (no comma in key) that mean no table name exist in incoming key 
      # and key is first and only one part of splitted data
      if (! defined($key)) { 
         $key = $tableName; undef $tableName;
      } else {
         my $fKey, my $fValue, my $fStr;
         # check for [filterkey=value&filterkey=value&...] construction in tableName. If that exist - key filter feature will enabled
         #($fStr) = $tableName =~ m/^\[([\w]+=.+&{0,1})+\]/;
         # regexp matched string placed into $1 and $1 listed as $fStr
         ($fStr) = $tableName =~ m/^\[(.+)\]/;

         if ($fStr) {
            # filterString is exist - need to split its to key=value pairs with '&' separator
            my @fStrings = split('&', $fStr);

            # After splitting split again - for get keys and values. And store it.
            for (my $i=0; $i < @fStrings; $i++) {
                # Split pair with '=' separator
                ($fKey, $fValue) = split('=', $fStrings[$i]);
                # If key/value splitting was correct - store filter data into list of hashes
                push(@fData, {key=>$fKey, val=> $fValue}) if (defined($fKey) && defined($fValue));
             }
             # Flush tableName's value if tableName is represent filter-key
             undef $tableName;
          }
       } # if (! defined($key)) ... else ... 

       # Test current object with filter-keys 
       if (@fData) {
          print "\n[.]\t\t Matching object's keys" if ($_[0]->{'debug'} >= DEBUG_MID);
          # run trought flter list
          for (my $i=0; $i < @fData; $i++ ) {
             # if key (from filter) in object is defined and its value equal to value of filter - increase counter
             $matchCount++ if (defined($_[1]->{$fData[$i]->{'key'}}) && ($_[1]->{$fData[$i]->{'key'}} eq $fData[$i]->{val}))
          }     
        }

       # Subtable could be not exist as 'vap_table' for UAPs which is powered off.
       # In this case $result must stay undefined for properly processed on previous dive level if subroutine is called recursively
       # Pass inside if no filter defined (@fData == $matchCount == 0) or all keys is matched
       if ($matchCount == @fData) {
          print "\n[.]\t\t Object is good" if ($_[0]->{'debug'} >= DEBUG_MID);
          if ($tableName && defined($_[1]->{$tableName})) {
             # if subkey was detected (tablename is given an exist) - do recursively calling getMetric func with subtable and subkey and get value from it
             print "\n[.]\t\t It's object. Go inside" if ($_[0]->{'debug'} >= DEBUG_MID);
             getMetric($_[0], $_[1]->{$tableName}, $key, $_[3]); 
          } elsif (defined($_[1]->{$key})) {
             # Otherwise - just return value for given key
             print "\n[.]\t\t It's key. Take value... '$_[1]->{$key}'" if ($_[0]->{'debug'} >= DEBUG_MID);
             $_[3]=$_[1]->{$key};
          } else {
             print "\n[.]\t\t No key or table exist :(" if ($_[0]->{'debug'} >= DEBUG_MID);
          }
       } # if ($matchCount == @fData)
   } # if (ref($_[1]) eq 'ARRAY') ... else ...

  print "\n[<] ($_[0]->{'dive_level'}) getMetric() finished (" if ($_[0]->{'debug'} >= DEBUG_LOW);
  print $_[3] if ($_[0]->{'debug'} >= DEBUG_LOW && defined($_[3]));
  print ") /$_[0]->{'max_depth'}/ " if ($_[0]->{'debug'} >= DEBUG_LOW);

  #float up...
  $_[0]->{'dive_level'}--;
}

#####################################################################################################################################
#
#  Fetch data from cache or call fetching from controller. Renew cache files.
#
#####################################################################################################################################
sub fetchData {
   # $_[0] - $GlobalConfig
   # $_[1] - object type
   # $_[2] - jsonData object ref
   print "\n[+] fetchData() started" if ($_[0]->{'debug'} >= DEBUG_LOW);
   print "\n[>]\t args: object type: '$_[0]->{'object'}'" if ($_[0]->{'debug'} >= DEBUG_MID);
   print ", id: '$_[0]->{'id'}'" if ($_[0]->{'debug'} >= DEBUG_MID && $_[0]->{'id'});
   print ", mac: '$_[0]->{'mac'}'" if ($_[0]->{'debug'} >= DEBUG_MID && $_[0]->{'mac'});
   my $cacheExpire=FALSE, my $needReadCache=TRUE, my $fh, my $jsonData, my $cacheFileName, my $tmpCacheFileName, my $objID,
   my $objPath, my $objType, my $givenObjType=$_[1];

   $objPath  = $_[0]->{'api_path'} . ($_[0]->{'fetch_rules'}->{$_[1]}->{'excl_sitename'} ? '' : "/s/$_[0]->{'sitename'}") . "/$_[0]->{'fetch_rules'}->{$_[1]}->{'path'}";
   # if MAC is given with command-line option -  RapidWay for Controller v4 is allowed
   $objPath.="/$_[0]->{'mac'}" if (($_[0]->{'version'} eq CONTROLLER_VERSION_4) && ($givenObjType eq OBJ_UAP) && $_[0]->{'mac'});
   print "\n[.]\t\t Object path: '$objPath'" if ($_[0]->{'debug'} >= DEBUG_MID);

   ################################################## Take JSON  ##################################################

   # If cache timeout setted to 0 then no try to read/update cache - fetch data from controller
   if (0 == $_[0]->{'cache_timeout'}) {
      print "\n[.]\t\t No read/update cache because cache timeout = 0" if ($_[0]->{'debug'} >= DEBUG_MID);
      fetchDataFromController($_[0], $objPath, $jsonData);
   } else {
      # Change all [:/.] to _ to make correct filename
      ($cacheFileName = $objPath) =~ tr/\/\:\./_/;
      $cacheFileName = $_[0]->{'cache_root'} .'/'. $cacheFileName;
      # Cache filename point to dir? If so - die to avoid problem with read or link/unlink operations
      die "[!] Can't handle '$tmpCacheFileName' through its dir, stop." if (-d $cacheFileName);
      print "\n[.]\t\t Cache file name: '$cacheFileName'" if ($_[0]->{'debug'} >= DEBUG_MID);
      # Cache file is exist and non-zero size?
      if (-e $cacheFileName && -s $cacheFileName) { 
         # Yes, is exist.
         # If cache is expire...
         my @fileStat=stat($cacheFileName);
         $cacheExpire = TRUE if (($fileStat[9] + $_[0]->{'cache_timeout'}) < time()) 
         # Cache file is not exist => cache is expire => need to create
      } else { 
         $cacheExpire = TRUE; 
      }

      if ($cacheExpire) {
      # Cache expire - need to update
         print "\n[.]\t\t Cache expire or not found. Renew..." if ($_[0]->{'debug'} >= DEBUG_MID);
         $tmpCacheFileName=$cacheFileName . ".tmp";
         # Temporary cache filename point to dir? If so - die to avoid problem with write or link/unlink operations
         die "[!] Can't handle '$tmpCacheFileName' through its dir, stop." if (-d $tmpCacheFileName);
         print "\n[.]\t\t Temporary cache file='$tmpCacheFileName'" if ($_[0]->{'debug'} >= DEBUG_MID);
         open ($fh, ">", $tmpCacheFileName);# or die "Could open not $tmpCacheFileName to write";
         # try to lock temporary cache file and no wait for locking.
         # LOCK_EX | LOCK_NB
         if (flock ($fh, 2 | 4)) {
            # if Miner could lock temporary file, it...
            chmod 0666, $fh;

            # ...fetch new data from controller...
            fetchDataFromController($_[0], $objPath, $jsonData);
            # unbuffered write it to temp file..
            syswrite ($fh, JSON::XS::encode_json($jsonData));
            # Now unlink old cache filedata from cache filename 
            # All processes, who already read data - do not stop and successfully completed reading
            unlink $cacheFileName;
            # Link name of cache file to temp file. File will be have two link - to cache and to temporary cache filenames. 
            # New run down processes can get access to data by cache filename
            link $tmpCacheFileName, $cacheFileName  or die "\n[!] Presumably no rights to unlink '$cacheFileName' file. Try to delete it ($!)";
            # Unlink temp filename from file. 
            # Process, that open temporary cache file can do something with filedata while file not closed
            unlink $tmpCacheFileName  or die "\n[!] '$tmpCacheFileName' unlink error \n";
            # Close temporary file. close() unlock filehandle.
            close $fh or die "[!] Can't close locked temporary cache file ($!)";;
            # No cache read from file need
            $needReadCache=FALSE;
         } else {
            close $fh or die "[!] Can't close temporary cache file ($!), stop.";;
         }
   } # if ($cacheExpire)

    # if need load data from cache file
    if ($needReadCache) {
       # open file
       open ($fh, "<", $cacheFileName) or die "[!] Can't open '$cacheFileName' ($!), stop.";
       # read data from file
       $jsonData=JSON::XS::decode_json(<$fh>);
       # close cache
       close $fh or die "[!] Can't close cache file ($!), stop.";
    }
  } # if (0 == $_[0]->{'cache_timeout'})

  ################################################## JSON processing ##################################################

  # Take each object
  for (my $i=0; $i < @{$jsonData}; $i++) {
     # Test object type or pass if 'obj-have-no-type' (workaround for WLAN, for example)
     $objType=@{$jsonData}[$i]->{'type'};
     next if ($objType && ($objType ne $givenObjType));
     # ID is given by command-line?
     # No ID given. Push all object which have correct type and skip next steps
     push (@{$_[2]}, @{$jsonData}[$i]), next unless ($_[0]->{'id'});

     # These steps is executed if ID is given

     # Taking from json-key object's ID
     # UBNT Phones store ID into 'device_id' key (?)
     $objID = ($givenObjType eq OBJ_UPH) ? @{$jsonData}[$i]->{'device_id'} : $objID=@{$jsonData}[$i]->{'_id'}; 

     # It is required object?
     # Yes. Push object to global @objJSON and jump out from the loop
     push (@{$_[2]}, @{$jsonData}[$i]), last if ($objID eq $_[0]->{'id'});
   } # foreach jsonData

   print "\n[<]\t Fetched data:\n\t", Dumper $_[2] if ($_[0]->{'debug'} >= DEBUG_HIGH);
   print "\n[-] fetchData() finished" if ($_[0]->{'debug'} >= DEBUG_LOW);
}

#####################################################################################################################################
#
#  Fetch data from from controller.
#
#####################################################################################################################################
sub fetchDataFromController {
   # $_[0] - GlobalConfig
   # $_[1] - object path
   # $_[2] - jsonData object ref
   #
   my $response, my $objPath = $_[1], my $fetchType=$_[0]->{'fetch_rules'}->{$_[0]->{'object'}}->{'method'}, 
   my $fetchCmd=$_[0]->{'fetch_rules'}->{$_[0]->{'object'}}->{'cmd'};

   print "\n[+] fetchDataFromController() started" if ($_[0]->{'debug'} >= DEBUG_LOW);
   print "\n[>]\t args: object path: '$_[1]'" if ($_[0]->{'debug'} >= DEBUG_MID);

   # HTTP UserAgent init
   # Set SSL_verify_mode=off to login without certificate manipulation
   # SSL_verify_mode => 0 eq SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_NONE ?
   $_[0]->{'ua'} = LWP::UserAgent-> new(cookie_jar => {}, agent => "UniFi Miner/" . MINER_VERSION . " (perl engine)",
                                                            ssl_opts => {SSL_verify_mode => 0, verify_hostname => 0}) unless ($_[0]->{'ua'});

   ################################################## Logging in  ##################################################
   # how to check 'still logged' state?
   unless ($_[0]->{'logged_in'}) {
     print "\n[.]\t\t Try to log in into controller..." if ($_[0]->{'debug'} >= DEBUG_LOW);
     $response=$_[0]->{'ua'}->post($_[0]->{'login_path'}, 'Content_type' => "application/$_[0]->{'login_type'}", 'Content' => $_[0]->{'login_data'});
     print "\n[>>]\t\t HTTP respose:\n\t", Dumper $response if ($_[0]->{'debug'} >= DEBUG_HIGH);
     my $rc=$response->code;
     if ($_[0]->{'version'} eq CONTROLLER_VERSION_4) {
        # v4 return 'Bad request' (code 400) on wrong auth
        die "\n[!] Login error: code $rc, stop." if ($rc eq '400');
        # v4 return 'OK' (code 200) on success login and must die only if get error
        die "\n[!] Other HTTP error: $rc, stop." if ($response->is_error);
     } elsif ($_[0]->{'version'} eq CONTROLLER_VERSION_3) {
        # v3 return 'OK' (code 200) on wrong auth
        die "\n[!] Login error: $rc, stop." if ($response->is_success );
        # v3 return 'Redirect' (code 302) on success login and must die only if code<>302
        die "\n[!] Other HTTP error: $rc, stop." if ($rc ne '302');
#     } else {
#        # v2 code
#        ;
       }
     print " successfully" if ($_[0]->{'debug'} >= DEBUG_LOW);
     $_[0]->{'logged_in'} = TRUE; 
  }


   ################################################## Fetch data from controller  ##################################################

   if (BY_CMD == $fetchType) {
      print "\n[.]\t\t Fetch data with CMD method: '$fetchCmd'" if ($_[0]->{'debug'} >= DEBUG_MID);
      $response=$_[0]->{'ua'}->post($objPath, 'Content_type' => 'application/json', 'Content' => $fetchCmd);

   } elsif (BY_GET == $fetchType) {
      print "\n[.]\t\t Fetch data with GET method" if ($_[0]->{'debug'} >= DEBUG_MID);
      $response=$_[0]->{'ua'}->get($objPath);
   }

   die "\n[!] JSON taking error, HTTP code: ", $response->status_line unless ($response->is_success), ", stop.";
   print "\n[>>]\t Fetched data:\n\t", Dumper $response->decoded_content if ($_[0]->{'debug'} >= DEBUG_HIGH);
   $_[2]=JSON::XS::decode_json($response->decoded_content);
   my $jsonMeta=$_[2]->{'meta'}->{'rc'};
   # server answer is ok ?
   die "[!] getJSON error: rc=$jsonMeta, stop." if ($jsonMeta ne 'ok'); 
   $_[2]=$_[2]->{'data'};
   print "\n[<]\t decoded data:\n\t", Dumper $_[2] if ($_[0]->{'debug'} >= DEBUG_HIGH);

   print "\n[-] fetchDataFromController() finished" if ($_[0]->{'debug'} >= DEBUG_LOW);
   $_[0]->{'downloaded'}=TRUE;
}


#####################################################################################################################################
#
#  Generate LLD-like JSON using fetched data
#
#####################################################################################################################################
sub makeLLD {
    # $_[0] - $globalConfig
    # $_[1] - result

    print "\n[+] makeLLD() started" if ($_[0]->{'debug'} >= DEBUG_LOW);
    print "\n[>]\t args: object type: '$_[0]->{'object'}'" if ($_[0]->{'debug'} >= DEBUG_MID);
    my $givenSiteName, my $jsonObj, my $lldResponse, my $lldPiece, my $siteList=(), my $objList, 
    my $givenObjType=$_[0]->{'object'}, my $siteWalking=TRUE;

    $siteWalking=FALSE if (($givenObjType eq OBJ_USW_PORT) && ($_[0]->{'version'} eq CONTROLLER_VERSION_4) || ($_[0]->{'version'} eq CONTROLLER_VERSION_3));

    if (! $siteWalking) {
       # 'no sites walking' routine code here
       print "\n[.]\t\t 'No sites walking' routine activated", if ($_[0]->{'debug'} >= DEBUG_MID);

       # Take objects
       # USW Ports LLD workaround: Store USW with given ID to $objList and then rewrite $objList with subtable {'port_table'}. 
       # Then make LLD for USW_PORT object
       if ($givenObjType eq OBJ_USW_PORT) {
          fetchData($_[0], OBJ_USW, $objList);
          $objList=@{$objList}[0]->{'port_table'};
       } else {
          fetchData($_[0], $givenObjType, $objList);
       }

       print "\n[.]\t\t Objects list:\n\t", Dumper $objList if ($_[0]->{'debug'} >= DEBUG_MID);
       # Add info to LLD-response 
       addToLLD($_[0], undef, $objList, $lldPiece) if ($objList);
    } else {
       # Get site list
       fetchData($_[0], OBJ_SITE, $siteList);
       print "\n[.]\t\t Sites list:\n\t", Dumper $siteList if ($_[0]->{'debug'} >= DEBUG_MID);
       # User ask LLD for 'site' object - make LLD piece with site list.
       if ($givenObjType eq OBJ_SITE) {
          addToLLD($_[0], undef, $siteList, $lldPiece) if ($siteList);
       } else {
       # User want to get LLD with objects for all or one sites
          $givenSiteName=$_[0]->{'sitename'};
          foreach my $siteObj (@{$siteList}) {
             # skip hidden site 'super', 0+ convert literal true/false to decimal
             next if (exists($siteObj->{'attr_hidden'}) && (0+$siteObj->{'attr_hidden'}));
             # skip site, if '-s' option used and current site other, that given
             next if ($_[0]->{'sitename_given'} && ($givenSiteName ne $siteObj->{'name'}));
             print "\n[.]\t\t Handle site: '$siteObj->{'name'}'" if ($_[0]->{'debug'} >= DEBUG_MID);
             # change {'sitename'} in $globalConfig. fetchData() use that config for forming path and get right info from cache/controller 
             $_[0]->{'sitename'}=$siteObj->{'name'};
             # Not nulled list causes duplicate LLD items
             $objList=();
             # Take objects from foreach'ed site
             fetchData($_[0], $givenObjType, $objList);
             # Add its info to LLD-response 
             print "\n[.]\t\t Objects list:\n\t", Dumper $objList if ($_[0]->{'debug'} >= DEBUG_MID);
             addToLLD($_[0], $siteObj, $objList, $lldPiece) if ($objList);
          } 
       } 
    } 
    
    # link LLD to {'data'} key
    $_[1]->{'data'} = $lldPiece;
    # make JSON
    $_[1]=JSON::XS::encode_json($_[1]);
    print "\n[<]\t Generated LLD:\n\t", Dumper $_[1] if ($_[0]->{'debug'} >= DEBUG_HIGH);
    print "\n[-] makeLLD() finished" if ($_[0]->{'debug'} >= DEBUG_LOW);
}

#####################################################################################################################################
#
#  Add a piece to exists LLD-like JSON 
#
#####################################################################################################################################
sub addToLLD {
    # $_[0] - $globalConfig
    # $_[1] - Site object
    # $_[2] - Incoming objects list
    # $_[3] - Outgoing objects list
    my $givenObjType=$_[0]->{'object'};
    print "\n[+] addToLLD() started" if ($_[0]->{'debug'} >= DEBUG_LOW);
    print "\n[>]\t args: object type: '$_[0]->{'object'}', site name: '$_[1]->{'name'}'" if ($_[0]->{'debug'} >= DEBUG_MID);

    # $i - incoming object's array element pointer. 
    # $o - outgoing object's array element pointer, init as length of that array to append elements to the end
    my $o = defined($_[3]) ? @{$_[3]} : 0;
    for (my $i=0; $i < @{$_[2]}; $i++, $o++) {
      $_[3][$o]->{'{#NAME}'}     = $_[2][$i]->{'name'} if ($_[2][$i]->{'name'});
      $_[3][$o]->{'{#ID}'}       = $_[2][$i]->{'_id'} if ($_[2][$i]->{'_id'});
      # $_[1] is undefined if script uses with v2 controller or generate LLD for OBJ_SITE  
      $_[3][$o]->{'{#SITENAME}'} = $_[1]->{'name'} if ($_[1]);
      $_[3][$o]->{'{#SITEID}'}   = $_[1]->{'_id'} if ($_[1]);
      $_[3][$o]->{'{#IP}'}       = $_[2][$i]->{'ip'}  if ($_[2][$i]->{'ip'});
      $_[3][$o]->{'{#MAC}'}      = $_[2][$i]->{'mac'} if ($_[2][$i]->{'mac'});
      # state of object: 0 - off, 1 - on
      $_[3][$o]->{'{#STATE}'}    = $_[2][$i]->{'state'} if ($_[2][$i]->{'state'});

      if ($givenObjType eq OBJ_HEALTH) {
         $_[3][$o]->{'{#SUBSYSTEM}'}= $_[2][$i]->{'subsystem'};
      } elsif ($givenObjType eq OBJ_WLAN) {
         # is_guest key could be not exist with 'user' network on v3 
         $_[3][$o]->{'{#ISGUEST}'}= 0+$_[2][$i]->{'is_guest'} if (exists($_[2][$i]->{'is_guest'}));
      } elsif ($givenObjType eq OBJ_USER ) {
         $_[3][$o]->{'{#NAME}'}   = $_[2][$i]->{'hostname'};
         # sometime {hostname} may be null. UniFi controller replace that hostnames by {'mac'}
         $_[3][$o]->{'{#NAME}'}   = $_[2][$i]->{'hostname'} ? $_[2][$i]->{'hostname'} : $_[3][$o]->{'{#MAC}'};
      } elsif ($givenObjType eq OBJ_UPH ) {
         $_[3][$o]->{'{#ID}'}     = $_[2][$i]->{'device_id'};
      } elsif ($givenObjType eq OBJ_SITE) {
         # 0+ - convert 'true'/'false' to 1/0 
         next if (exists($_[2][$i]->{'attr_hidden'}) && (0+$_[2][$i]->{'attr_hidden'}));
         $_[3][$o]->{'{#DESC}'}     = $_[2][$i]->{'desc'};
      } elsif ($givenObjType eq OBJ_USW_PORT) {
         $_[3][$o]->{'{#PORTIDX}'}     = $_[2][$i]->{'port_idx'};
         $_[3][$o]->{'{#MEDIA}'}     = $_[2][$i]->{'media'};
         $_[3][$o]->{'{#UP}'}     = 0+$_[2][$i]->{'up'};
#      } elsif ($givenObjType eq OBJ_UAP) {
#         ;
#      } elsif ($givenObjType eq OBJ_USG || $givenObjType eq OBJ_USW) {
#        ;
      }
    }

    print "\n[<]\t Generated LLD piece:\n\t", Dumper $_[3] if ($_[0]->{'debug'} >= DEBUG_HIGH);
    print "\n[-] addToLLD() finished" if ($_[0]->{'debug'} >= DEBUG_LOW);
}
