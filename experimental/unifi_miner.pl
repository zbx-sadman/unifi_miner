#!/usr/bin/perl
#
#  (C) sadman@sfi.komi.com 2015
#  tanx to Jakob Borg (https://github.com/calmh/unifi-api) for some methods and ideas 
#
# 
#
#use strict;
#use warnings;
#use Data::Dumper;
#use JSON ();
#use Types::Serialiser;
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
     OBJ_UPH => 'uph',
     OBJ_UAP => 'uap',
     OBJ_USG => 'usg',
     OBJ_WLAN => 'wlan',
     OBJ_USER => 'user',
     OBJ_SITE => 'site',
     TRUE => 1,
     FALSE => 0,

};


sub fetchData;
sub fetchDataFromController;
sub makeLLD;
sub addToLLD;
sub getMetric;
sub writeStat;

#########################################################################################################################################
#
#  Default values for global scope
#
#########################################################################################################################################
my $globalConfig = {
   # Default action for objects metric
   action => ACT_GET,
   # How much time live cache data. Use 0 for disabling cache processes
   cache_timeout => 60,
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
  };

# clock_gettime(1)=> clock_gettime(CLOCK_MONOLITIC)
$globalConfig->{'start_time'}=clock_gettime(1) if ($globalConfig->{'write_stat'});

my @objJSON=();
my %options;
my $res;

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
   $globalConfig->{'api_path'}="$globalConfig->{'location'}/api";
   $globalConfig->{'login_path'}="$globalConfig->{'location'}/api/login";
   $globalConfig->{'login_data'}="{\"username\":\"$globalConfig->{'username'}\",\"password\":\"$globalConfig->{'password'}\"}";
   $globalConfig->{'login_type'}='json';
   $globalConfig->{'logout_path'}="$globalConfig->{'location'}/logout";
   # Data fetch rules. 
   # BY_GET mean that data fetched by HTTP GET from .../api/[s/<site>/]{'path'} operation.
   #    [s/<site>/] must be excluded from path if {'excl_sitename'} is defined
   # BY_CMD say that data fetched by HTTP POST {'cmd'} to .../api/[s/<site>/]{'path'}
   #
   $globalConfig->{'fetch_rules'}= { 
     # `&` let use value of constant, otherwise we have 'OBJ_UAP' => {...} instead 'uap' => {...}
     &OBJ_SITE => {'method' => BY_GET, 'path' => 'self/sites', 'excl_sitename' => TRUE},
     &OBJ_USW  => {'method' => BY_GET, 'path' => 'stat/device'},
     &OBJ_UPH  => {'method' => BY_GET, 'path' => 'stat/device'},
     &OBJ_UAP  => {'method' => BY_GET, 'path' => 'stat/device'},
     &OBJ_USG  => {'method' => BY_GET, 'path' => 'stat/device'},
     &OBJ_WLAN => {'method' => BY_GET, 'path' => 'list/wlanconf'},
     &OBJ_USER => {'method' => BY_GET, 'path' => 'stat/sta'}
   };
} elsif ($globalConfig->{'version'} eq CONTROLLER_VERSION_3) {
   $globalConfig->{'api_path'}="$globalConfig->{'location'}/api";
   $globalConfig->{'login_path'}="$globalConfig->{'location'}/login";
   $globalConfig->{'login_data'}="username=$globalConfig->{'username'}&password=$globalConfig->{'password'}&login=login";
   $globalConfig->{'login_type'}='x-www-form-urlencoded';
   $globalConfig->{'logout_path'}="$globalConfig->{'location'}/logout";
   $globalConfig->{'fetch_rules'}= { 
     # `&` let use value of constant, otherwise we have 'OBJ_UAP' => {...} instead 'uap' => {...}
     &OBJ_SITE => {'method' => BY_CMD, 'path' => 'cmd/sitemgr', 'cmd' => '{"cmd":"get-sites"}'},
     &OBJ_USW  => {'method' => BY_GET, 'path' => 'stat/device'},
     &OBJ_UPH  => {'method' => BY_GET, 'path' => 'stat/device'},
     &OBJ_UAP  => {'method' => BY_GET, 'path' => 'stat/device'},
     &OBJ_USG  => {'method' => BY_GET, 'path' => 'stat/device'},
     &OBJ_WLAN => {'method' => BY_GET, 'path' => 'list/wlanconf'},
     &OBJ_USER => {'method' => BY_GET, 'path' => 'stat/sta'}
   };
} elsif ($globalConfig->{'version'} eq CONTROLLER_VERSION_2) {
   $globalConfig->{'api_path'}="$globalConfig->{'location'}/api";
   $globalConfig->{'login_path'}="$globalConfig->{'location'}/login";
   $globalConfig->{'login_data'}="username=$globalConfig->{'username'}&password=$globalConfig->{'password'}&login=login";
   $globalConfig->{'login_type'}='x-www-form-urlencoded';
   $globalConfig->{'logout_path'}="$globalConfig->{'location'}/logout";
   $globalConfig->{'fetch_rules'}= { 
     # `&` let use value of constant, otherwise we have 'OBJ_UAP' => {...} instead 'uap' => {...}
     &OBJ_UAP  => {'method' => BY_GET, 'path' => 'stat/device', 'excl_sitename' => TRUE},
     &OBJ_WLAN => {'method' => BY_GET, 'path' => 'list/wlanconf', 'excl_sitename' => TRUE},
     &OBJ_USER => {'method' => BY_GET, 'path' => 'stat/sta', 'excl_sitename' => TRUE}
   };
} else {
   die MSG_UNKNOWN_CONTROLLER_VERSION, $globalConfig->{'version'};
}

die "[!] Unknown object '$globalConfig->{'object'}' given. Stop " unless ($globalConfig->{'fetch_rules'}->{$globalConfig->{'object'}}); 

# First - check for object type. ...but its always defined in 'my $globalConfig {' section
#if ($globalConfig->{'object'}) {
   # load JSON data
   # Ok. Type is defined. How about key?
   if ($globalConfig->{'key'}) {
       # Key is given - need to get metric. 
       # if $globalConfig->{'id'} is exist then metric of this object has returned. 
       # If not - calculate $globalConfig->{'action'} for all items in objects list (all object of type = 'object name', for example - all 'uap'
       fetchData($globalConfig, $globalConfig->{'object'}, \@objJSON);
       $res=getMetric($globalConfig, \@objJSON, $globalConfig->{'key'});
   } else { 
       # Key is null - going generate LLD-like JSON from loaded data
       $res=makeLLD($globalConfig);
   }
#}

# Logout need if logging in before (in fetchData() sub) completed
print "\n[*] Logout from UniFi controller" if  ($globalConfig->{'debug'} >= DEBUG_LOW);
$globalConfig->{'ua'}->get($globalConfig->{'logout_path'}) if ($globalConfig->{'logged_in'});

# Value could be 'null'. If need to replace null to other char - {'null_char'} must be defined
$res = $res ? $res : $globalConfig->{'null_char'} if (defined($globalConfig->{'null_char'}));

print "\n" if  ($globalConfig->{'debug'} >= DEBUG_LOW);
$res="" unless defined ($res);

# Push result of work to stdout
print  "$res\n";

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

#####################################################################################################################################
#
#  Write statistic to file. Fields separated by commas.
#
#####################################################################################################################################
sub writeStat {
    # $_[0] - GlobalConfig
    open (my $fh, ">>", $_[0]->{'stat_file'}) or die "Could not open $_[0]->{'stat_file'} for storing statistic info";
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

    # dive to...
    $_[0]->{'dive_level'}++;

    print "\n[>] ($_[0]->{'dive_level'}) getMetric() started" if ($_[0]->{'debug'} >= DEBUG_LOW);
    my $result;
    my $key=$_[2];

    print "\n[#]   options: key='$_[2]' action='$_[0]->{'action'}'" if ($_[0]->{'debug'} >= DEBUG_MID);
    print "\n[+]   incoming object info:'\n\t", Dumper $_[1] if ($_[0]->{'debug'} >= DEBUG_HIGH);

    # correcting maxDepth for ACT_COUNT operation
    $_[0]->{'max_depth'} = ($_[0]->{'dive_level'} > $_[0]->{'max_depth'}) ? $_[0]->{'dive_level'} : $_[0]->{'max_depth'};
    
    # Checking for type of $_[1]. 
    # if $_[1] is array - need to explore any element
    if (ref($_[1]) eq 'ARRAY') {
       my $paramValue;
       my $objList=@{$_[1]};
       print "\n[.] Array with ", $objList, " objects detected" if ($_[0]->{'debug'} >= DEBUG_MID);

       # if metric ask "how much items (AP's for example) in all" - just return array size (previously calculated in $objList) and do nothing more
       if ($key eq KEY_ITEMS_NUM) { 
          $result=$objList; 
       } else {
          $result=0; 
          print "\n[.] taking value from all sections" if ($_[0]->{'debug'} >= DEBUG_MID);
          # Take each element of array
          for (my $i=0; $i < $objList; $i++ ) {
            # Init $paramValue for right actions doing
            $paramValue=undef;
            # Do recursively calling getMetric func for each element 
            $paramValue=getMetric($_[0], $_[1][$i], $key); 
            print "\n[.] paramValue=$paramValue" if ($_[0]->{'debug'} >= DEBUG_MID);

            # With 'get' action jump out from loop with first recieved value
            if ($_[0]->{'action'} eq ACT_GET) { 
               $result=$paramValue; last; 
            }

            # Otherwise - do something line sum or count
            if (defined($paramValue)) {
               print "\n[.] act #$_[0]->{'action'} " if ($_[0]->{'debug'} >= DEBUG_MID);
               # !!! need to fix trying sum of not numeric values
               # With 'sum' - grow $result
               if ($_[0]->{'action'} eq ACT_SUM) { 
                  $result+=$paramValue; 
               } elsif ($_[0]->{'action'} eq ACT_COUNT) {
                  # may be wrong algo :(
                  # workaround for correct counting with deep diving
                  # With 'count' we must count keys in objects, that placed only on last level
                  # in other case $result will be incremented by $paramValue (which is number of key in objects inside last level table)
                  if (($_[0]->{'max_depth'}-$_[0]->{'dive_level'}) < 2 ) {
                     $result++; 
                  } else {
                     $result+=$paramValue; 
                  }
              }
            }
            print "\n[.] Value=$paramValue, result=$result" if ($_[0]->{'debug'} >= DEBUG_HIGH);
          } #foreach 
       }
    } else {
      # it is not array (list of objects) - it's one object (hash)
      print "\n[.] Just one object detected." if ($_[0]->{'debug'} >= DEBUG_MID);
      my $tableName;
      my @fData=();
      my $matchCount=0;
      ($tableName, $key) = split(/[.]/, $key, 2);

      # if key is not defined after split (no comma in key) that mean no table name exist in incoming key 
      # and key is first and only one part of splitted data
      if (! defined($key)) { 
         $key = $tableName; undef $tableName;
      } else {
         my $fKey;
         my $fValue;
         my $fStr;
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
          print "\n[.] Check the object for keys matching" if ($_[0]->{'debug'} >= DEBUG_MID);
          # run trought flter list
          for (my $i=0; $i < @fData; $i++ ) {
             # if key (from filter) in object is defined and its value equal to value of filter - increase counter
             $matchCount++ if (defined($_[1]->{$fData[$i]->{'key'}}) && ($_[1]->{$fData[$i]->{'key'}} eq $fData[$i]->{val}));
          }     
        }

       # Subtable could be not exist as 'vap_table' for UAPs which is powered off.
       # In this case $result must stay undefined for properly processed on previous dive level if subroutine is called recursively
       # Pass inside if no filter defined (@fData == $matchCount == 0) or all keys is matched
       if ($matchCount == @fData) {
          print "\n[.] Object is good" if ($_[0]->{'debug'} >= DEBUG_MID);
          if ($tableName && defined($_[1]->{$tableName})) {
             # if subkey was detected (tablename is given an exist) - do recursively calling getMetric func with subtable and subkey and get value from it
             print "\n[.] It's object. Go inside" if ($_[0]->{'debug'} >= DEBUG_MID);
             $result=getMetric($_[0], $_[1]->{$tableName}, $key); 
          } elsif (defined($_[1]->{$key})) {
             # Otherwise - just return value for given key
             print "\n[.] It's key. Take value" if ($_[0]->{'debug'} >= DEBUG_MID);
             $result=$_[1]->{$key};
             print "\n[.] value=<$result>" if ($_[0]->{'debug'} >= DEBUG_MID);
          } else {
             print "\n[.] No key or table exist :(" if ($_[0]->{'debug'} >= DEBUG_MID);
          }
       } # if ($matchCount == @fData)
   } # if (ref($_[1]) eq 'ARRAY') ... else ...

  print "\n[>] ($_[0]->{'dive_level'}) getMetric() finished (" if ($_[0]->{'debug'} >= DEBUG_LOW);
  print $result if ($_[0]->{'debug'} >= DEBUG_LOW && defined($result));
  print ") /$_[0]->{'max_depth'}/ " if ($_[0]->{'debug'} >= DEBUG_LOW);

  #float up...
  $_[0]->{'dive_level'}--;

  return $result;
}

#####################################################################################################################################
#
#  Fetch data from cache or call fetching from controller. Renew cache files.
#
#####################################################################################################################################
sub fetchData {
   # $_[0] - $GlobalConfig
   # $_[1] - object name
   # $_[2] - jsonData object ref
   print "\n[+] fetchData() started" if ($_[0]->{'debug'} >= DEBUG_LOW);
   print "\n[#]  options:  object='$_[0]->{'object'}'," if ($_[0]->{'debug'} >= DEBUG_MID);
   print " id='$_[0]->{'id'}'," if ($_[0]->{'debug'} >= DEBUG_MID && $_[0]->{'id'});
   print " mac='$_[0]->{'mac'}'," if ($_[0]->{'debug'} >= DEBUG_MID && $_[0]->{'mac'});
   my $cacheExpire=FALSE;
   my $needReadCache=TRUE;
   my $fh;
   my $jsonData;
   my $jsonLen;
   my $cacheFileName;
   my $tmpCacheFileName;
   my $objID;
   my $objPath;
   my $objType;
   my $givenObjType=$_[1];

   $objPath  = $_[0]->{'api_path'} . ($_[0]->{'fetch_rules'}->{$_[1]}->{'excl_sitename'} ? '' : "/s/$_[0]->{'sitename'}") . "/$_[0]->{'fetch_rules'}->{$_[1]}->{'path'}";
   # if MAC is given with command-line option -  RapidWay for Controller v4 is allowed
   $objPath.="/$_[0]->{'mac'}" if (($_[0]->{'version'} eq CONTROLLER_VERSION_4) && ($givenObjType eq OBJ_UAP) && $_[0]->{'mac'});
   print "\n[.]   Object path: '$objPath'\n" if ($_[0]->{'debug'} >= DEBUG_MID);

   ################################################## Take JSON  ##################################################

   # If cache timeout setted to 0 then no try to read/update cache - fetch data from controller
   if (0 == $_[0]->{'cache_timeout'}) {
      print "\n[.]   No read/update cache because cache timeout = 0" if ($_[0]->{'debug'} >= DEBUG_MID);
      fetchDataFromController($_[0], $objPath, $jsonData);
   } else {
      # Change all [:/.] to _ to make correct filename
      ($cacheFileName = $objPath) =~ tr/\/\:\./_/;
      $cacheFileName = $_[0]->{'cache_root'} .'/'. $cacheFileName;
      # Cache filename point to dir? If so - die to avoid problem with read or link/unlink operations
      die "[!] Can't handle '$tmpCacheFileName' through its dir" if (-d $cacheFileName);
      print "\n[.]   Cache file name: '$cacheFileName'\n" if ($_[0]->{'debug'} >= DEBUG_MID);
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
         print "\n[.]   Cache expire or not found. Renew..." if ($_[0]->{'debug'} >= DEBUG_MID);
         $tmpCacheFileName=$cacheFileName . ".tmp";
         # Temporary cache filename point to dir? If so - die to avoid problem with write or link/unlink operations
         die "[!] Can't handle '$tmpCacheFileName' through its dir" if (-d $tmpCacheFileName);
         print "\n[.]   Temporary cache file='$tmpCacheFileName'" if ($_[0]->{'debug'} >= DEBUG_MID);
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
            link $tmpCacheFileName, $cacheFileName  or die "\n[!] Presumably no rights to unlink '$cacheFileName' file. Try to delete it";
            # Unlink temp filename from file. 
            # Process, that open temporary cache file can do something with filedata while file not closed
            unlink $tmpCacheFileName  or die "\n[!] '$tmpCacheFileName' unlink error \n";
            # Close temporary file. close() unlock filehandle.
            close $fh;
            # No cache read from file need
            $needReadCache=FALSE;
         } else {
            close $fh;
         }
   } # if ($cacheExpire)

    # if need load data from cache file
    if ($needReadCache) {
       # open file
       open ($fh, "<", $cacheFileName) or die "[!] Can't open '$cacheFileName'";
       # read data from file
       $jsonData=JSON::XS::decode_json(<$fh>);
       # close cache
       close $fh;
    }
  } # if (0 == $_[0]->{'cache_timeout'})

  ################################################## JSON processing ##################################################

  $jsonLen=@{$jsonData};
  # Take each object
  for (my $nCnt=0; $nCnt < $jsonLen; $nCnt++) {
     # Test object type or pass if 'obj-have-no-type' (workaround for WLAN, for example)
     $objType=@{$jsonData}[$nCnt]->{'type'};
     next if ($objType && ($objType ne $givenObjType));
#     next if (defined($jsonData[$nCnt]->{'type'}) && (@{$jsonData}[$nCnt]->{'type'} ne $_[0]->{'object'}));
     # ID is given by command-line?
     unless ($_[0]->{'id'}) {
       # No ID given. Push all object which have correct type
       push (@{$_[2]}, @{$jsonData}[$nCnt]);
       # and skip next steps
       next;
     }

     # These steps is executed if ID is given

     # Taking from json-key object's ID
     # UBNT Phones store ID into 'device_id' key (?)
     if ($givenObjType eq OBJ_UPH) {
        $objID=@{$jsonData}[$nCnt]->{'device_id'}; 
     } else { 
        $objID=@{$jsonData}[$nCnt]->{'_id'}; 
     }

     # It is required object?
     if ($objID eq $_[0]->{'id'}) { 
        # Yes. Push object to global @objJSON and jump out from the loop
        push (@{$_[2]}, @{$jsonData}[$nCnt]); last;
     }
   } # foreach jsonData

   print "\n[<]   Fetched data:\n\t", Dumper $_[2] if ($_[0]->{'debug'} >= DEBUG_HIGH);
   print "\n[-] fetchData() finished" if ($_[0]->{'debug'} >= DEBUG_LOW);
   return TRUE;
}

#####################################################################################################################################
#
#  Fetch data from from controller.
#
#####################################################################################################################################
sub fetchDataFromController {
   # $_[0] - GlobalConfig
   # $_[1] - object name
   # $_[2] - jsonData object ref
   #
   my $response;
   my $result;
   my $objPath;
   
   $objPath  = $_[1]; # $_[0]->{'api_path'} . ($_[0]->{'fetch_rules'}->{$_[1]}->{'excl_sitename'} ? '' : "/s/$_[0]->{'sitename'}") . "/$_[0]->{'fetch_rules'}->{$_[1]}->{'path'}";

   my $fetchType=$_[0]->{'fetch_rules'}->{$_[0]->{'object'}}->{'method'};
   my $fetchCmd=$_[0]->{'fetch_rules'}->{$_[0]->{'object'}}->{'cmd'};

   print "\n[+] fetchDataFromController() started" if ($_[0]->{'debug'} >= DEBUG_LOW);
   print "\n[#]   options: object='$_[1]'" if ($_[0]->{'debug'} >= DEBUG_MID);

   # HTTP UserAgent init
   # Set SSL_verify_mode=off to login without certificate manipulation
   # SSL_verify_mode => 0 eq SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_NONE ?
   unless ($_[0]->{'ua'}) {
       $_[0]->{'ua'} = LWP::UserAgent-> new(cookie_jar => {}, agent => "UniFi Miner/" . MINER_VERSION . " (perl engine)",
                                 ssl_opts => {SSL_verify_mode => 0, verify_hostname => 0});
      }

   ################################################## Logging in  ##################################################
   # how to check 'still logged' state?
   unless ($_[0]->{'logged_in'}) {
     print "\n[.] Try to log in into controller" if ($_[0]->{'debug'} >= DEBUG_LOW);
     $response=$_[0]->{'ua'}->post($_[0]->{'login_path'}, 'Content_type' => "application/$_[0]->{'login_type'}", 'Content' => $_[0]->{'login_data'});
     print "\n[<]  HTTP respose:\n\t", Dumper $response if ($_[0]->{'debug'} >= DEBUG_HIGH);

     if ($_[0]->{'version'} eq CONTROLLER_VERSION_4) {
        # v4 return 'Bad request' (code 400) on wrong auth
        die "\n[!] Login error: " if ($response->code eq '400');
        # v4 return 'OK' (code 200) on success login and must die only if get error
        die "\n[!] Other HTTP error: ", $response->code if ($response->is_error);
     } elsif ($_[0]->{'version'} eq CONTROLLER_VERSION_3) {
        # v3 return 'OK' (code 200) on wrong auth
        die "\n[!] Login error: ", $response->code if ($response->is_success );
        # v3 return 'Redirect' (code 302) on success login and must die only if code<>302
        die "\n[!] Other HTTP error: ", $response->code if ($response->code ne '302');
     } else {
        # v2 code
        ;
       }
     print "\n[-] log in finished successfully" if ($_[0]->{'debug'} >= DEBUG_LOW);
     $_[0]->{'logged_in'} = TRUE; 
  }


   ################################################## Fetch data from controller  ##################################################

   print "\n[.]  objPath=$objPath" if ($_[0]->{'debug'} >= DEBUG_LOW);
   if (BY_CMD == $fetchType) {
      print "\n[.]  fetch data with CMD method: '$fetchCmd'" if ($_[0]->{'debug'} >= DEBUG_MID);
      $response=$_[0]->{'ua'}->post($objPath, 'Content_type' => 'application/json', 'Content' => $fetchCmd);

   } elsif (BY_GET == $fetchType) {
      print "\n[.]  fetch data with GET method" if ($_[0]->{'debug'} >= DEBUG_MID);
      $response=$_[0]->{'ua'}->get($objPath);

   }

   die "\n[!] JSON taking error, HTTP code:", $response->status_line unless ($response->is_success);
   print "\n[<]   Fetched data:\n\t", Dumper $response->decoded_content if ($_[0]->{'debug'} >= DEBUG_HIGH);
   $result=JSON::XS::decode_json($response->decoded_content);
   my $jsonMeta=$result->{'meta'}->{'rc'};
   # server answer is ok ?
   die "[!] getJSON error: rc=$jsonMeta" if ($jsonMeta ne 'ok'); 
   $_[2]=$result->{'data'};
   print "\n[<]   decoded data:\n\t", Dumper $_[2] if ($_[0]->{'debug'} >= DEBUG_HIGH);

   print "\n[-] fetchDataFromController() finished" if ($_[0]->{'debug'} >= DEBUG_LOW);
   $_[0]->{'downloaded'}=TRUE;

   return TRUE;
}


#####################################################################################################################################
#
#  Generate LLD-like JSON using fetched data
#
#####################################################################################################################################
sub makeLLD {
    # $_[0] - $globalConfig
    print "\n[+] makeLLD() started" if ($_[0]->{'debug'} >= DEBUG_LOW);
    print "\n[#]   options: object='$_[0]->{'object'}'" if ($_[0]->{'debug'} >= DEBUG_MID);
    my $givenSiteName;
    my $jsonObj;
    my $lldResponse;
    my $lldPiece;
    my $result;
    my $siteList=();
    my $siteObj;
    my $objList;
    my $givenObjType=$_[0]->{'object'};

    if (($_[0]->{'version'} eq CONTROLLER_VERSION_4) || ($_[0]->{'version'} eq CONTROLLER_VERSION_3)) {
       # Get site list
       fetchData($_[0], OBJ_SITE, $siteList);
       print "\n[.]   Sites list:\n\t", Dumper $siteList if ($_[0]->{'debug'} >= DEBUG_MID);
       # User ask LLD for 'site' object - make LLD piece with site list.
       if ($givenObjType eq OBJ_SITE) {
          addToLLD($_[0], undef, $siteList, $lldPiece) if ($siteList);
       } else {
       # User want to get LLD with objects for all or one sites
          $givenSiteName=$_[0]->{'sitename'};
          foreach $siteObj (@{$siteList}) {
             # skip hidden site 'super'
#             next if (convert_if_bool($siteObj->{'attr_hidden'}));
             next if ($siteObj->{'attr_hidden'});
             # skip site, if '-s' option used and current site other, that given
             next if ($_[0]->{'sitename_given'} && ($givenSiteName ne $siteObj->{'name'}));
             print "\n[.]   Handle site: '$siteObj->{'name'}'" if ($_[0]->{'debug'} >= DEBUG_MID);
             # change {'sitename'} in $globalConfig. fetchData() use that config for forming path and get right info from cache/controller 
             $_[0]->{'sitename'}=$siteObj->{'name'};
             # Not nulled list causes duplicate LLD items
             $objList=();
             # Take objects from foreach'ed site
             fetchData($_[0], $givenObjType, $objList);
             # Add its info to LLD-response 
             print "\n[.]   Objects list:\n\t", Dumper $objList if ($_[0]->{'debug'} >= DEBUG_MID);
             addToLLD($_[0], $siteObj, $objList, $lldPiece) if ($objList);
          } 
       } 
    } else {
      # 'no sites walking' routine code here
      print "\n[.]   'no sites walking' routine activated", if ($_[0]->{'debug'} >= DEBUG_MID);
      # Take objects
      fetchData($_[0], $givenObjType, $objList);
      print "\n[.]   Objects list:\n\t", Dumper $objList if ($_[0]->{'debug'} >= DEBUG_MID);
      # Add info to LLD-response 
      addToLLD($_[0], undef, $objList, $lldPiece) if ($objList);
    }
    
    # link LLD to {'data'} key
    $result->{'data'} = $lldPiece;
    # make JSON
    $result=JSON::XS::encode_json($result);
    print "\n[<]   generated LLD:\n\t", Dumper $result if ($_[0]->{'debug'} >= DEBUG_HIGH);
    print "\n[-] makeLLD() finished" if ($_[0]->{'debug'} >= DEBUG_LOW);
    return $result;
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
    my $jsonObj;
    my $givenObjType=$_[0]->{'object'};
    my $result;
    print "\n[+] addToLLD() started" if ($_[0]->{'debug'} >= DEBUG_LOW);

    foreach $jsonObj (@{$_[2]}) {
      $result=();
      $result->{'{#NAME}'}     = $jsonObj->{'name'};
      $result->{'{#ID}'}       = $jsonObj->{'_id'};
      # $_[1] is undefined if script uses with v2 controller or generate LLD for OBJ_SITE  
      $result->{'{#SITENAME}'} = $_[1]->{'name'} if ($_[1]);
      $result->{'{#SITEID}'}   = $_[1]->{'_id'} if ($_[1]);
      $result->{'{#IP}'}       = $jsonObj->{'ip'}  if ($jsonObj->{'ip'});
      $result->{'{#MAC}'}      = $jsonObj->{'mac'} if ($jsonObj->{'mac'});
      # state of object: 0 - off, 1 - on
      $result->{'{#STATE}'}  = $jsonObj->{'state'} if ($jsonObj->{'state'});

      if ($givenObjType eq OBJ_WLAN) {
         # is_guest key could be not exist with 'user' network on v3 
         # 0+ - convert 'true'/'false' to 1/0 
         $result->{'{#ISGUEST}'}=0+$jsonObj->{'is_guest'} if (exists($jsonObj->{'is_guest'}));
      } elsif ($givenObjType eq OBJ_USER ) {
         $result->{'{#NAME}'}   = $jsonObj->{'hostname'};
         # sometime {hostname} may be null. UniFi controller replace that hostnames by {'mac'}
         $result->{'{#NAME}'}   = $jsonObj->{'hostname'} ? $jsonObj->{'hostname'} : $result->{'{#MAC}'};
      } elsif ($givenObjType eq OBJ_UPH ) {
         $result->{'{#ID}'}     = $jsonObj->{'device_id'};
      } elsif ($givenObjType eq OBJ_SITE) {
         # 0+ - convert 'true'/'false' to 1/0 
         next if (0+($jsonObj->{'attr_hidden'}));
         $result->{'{#DESC}'}     = $jsonObj->{'desc'};
#      } elsif ($givenObjType eq OBJ_UAP) {
#         ;
#      } elsif ($givenObjType eq OBJ_USG || $givenObjType eq OBJ_USW) {
#        ;
      }
      push(@{$_[3]}, $result);
    }

    print "\n[<]   Generated LLD piece:\n\t", Dumper $result if ($_[0]->{'debug'} >= DEBUG_HIGH);
    print "\n[-] addToLLD() finished" if ($_[0]->{'debug'} >= DEBUG_LOW);
}
