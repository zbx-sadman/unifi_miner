#!/usr/bin/perl
#
#  (C) sadman@sfi.komi.com 2015
#  tanx to Jakob Borg (https://github.com/calmh/unifi-api) for some methods and ideas 
#
# 
#
use strict;
use warnings;
#use IO::Socket::SSL;
use Getopt::Std;
use Data::Dumper;
use JSON ();
use LWP ();
use Time::HiRes ('clock_gettime', 'CLOCK_REALTIME');



use constant {
     ACT_COUNT => 'count',
     ACT_SUM => 'sum',
     ACT_GET => 'get',
     ACT_DISCOVERY => 'discovery',
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
     TRUE => 1,
     FALSE => 0,

};


sub getJSON;
sub unifiLogin;
sub unifiLogout;
sub fetchData;
sub fetchDataFromController;
sub lldJSONGenerate;
sub getMetric;
sub convert_if_bool;
sub matchObject;
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
   # Name of your site 
   sitename => 'default', 
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

   # HiRes time of Miner internal processing start (not include Module Init stage)
   start_time => clock_gettime(CLOCK_REALTIME),
   # HiRes time of Miner internal processing stop
   stop_time => 0,
   # Level of dive (recursive call) for getMetric subroutine
   dive_level => 1,
   # Max level to which getMetric is dived
   max_depth => 0,
   # 
   downloaded => FALSE
  };

$globalConfig->{'start_time'}=clock_gettime(CLOCK_REALTIME) if ($globalConfig->{'write_stat'});

my @objJSON=();
my %options;
my $res;

getopts('a:c:d:i:k:l:m:n:o:p:s:u:v:', \%options);

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

# Set controller version specific data
if ($globalConfig->{'version'} eq CONTROLLER_VERSION_4) {
   $globalConfig->{'api_path'}="$globalConfig->{'location'}/api/s/$globalConfig->{'sitename'}";
   $globalConfig->{'login_path'}="$globalConfig->{'location'}/api/login";
   $globalConfig->{'login_data'}="{\"username\":\"$globalConfig->{'username'}\",\"password\":\"$globalConfig->{'password'}\"}";
   $globalConfig->{'login_type'}='json';
   $globalConfig->{'logout_path'}="$globalConfig->{'location'}/logout";
} elsif ($globalConfig->{'version'} eq CONTROLLER_VERSION_3) {
   $globalConfig->{'api_path'}="$globalConfig->{'location'}/api/s/$globalConfig->{'sitename'}";
   $globalConfig->{'login_path'}="$globalConfig->{'location'}/login";
   $globalConfig->{'login_data'}="username=$globalConfig->{'username'}&password=$globalConfig->{'password'}&login=login";
   $globalConfig->{'login_type'}='x-www-form-urlencoded';
   $globalConfig->{'logout_path'}="$globalConfig->{'location'}/logout";
} elsif ($globalConfig->{'version'} eq CONTROLLER_VERSION_2) {
   $globalConfig->{'api_path'}="$globalConfig->{'location'}/api";
   $globalConfig->{'login_path'}="$globalConfig->{'location'}/login";
   $globalConfig->{'login_data'}="username=$globalConfig->{'username'}&password=$globalConfig->{'password'}&login=login";
   $globalConfig->{'login_type'}='x-www-form-urlencoded';
   $globalConfig->{'logout_path'}="$globalConfig->{'location'}/logout";
} else {
   die MSG_UNKNOWN_CONTROLLER_VERSION, $globalConfig->{'version'};
}

print "\n[#]   Global config data:\n\t", Dumper $globalConfig if ($globalConfig->{'debug'} >= DEBUG_MID);

# First - check for object type. ...but its always defined in 'my $globalConfig {' section
#if ($globalConfig->{'object'}) {
   # load JSON data
   fetchData($globalConfig, \@objJSON);
   # Ok. Type is defined. How about key?
   if ($globalConfig->{'key'}) {
       # Key is given - need to get metric. 
       # if $globalConfig->{'id'} is exist then metric of this object has returned. 
       # If not - calculate $globalConfig->{'action'} for all items in objects list (all object of type = 'object name', for example - all 'uap'
       $res=getMetric($globalConfig, \@objJSON, $globalConfig->{'key'});
   } else { 
       # Key is null - going generate LLD-like JSON from loaded data
       $res=lldJSONGenerate($globalConfig, \@objJSON);
   }
#}

# Value could be 'null'. If need to replace null to other char - {'null_char'} must be defined
$res = $res ? $res : $globalConfig->{'null_char'} if (defined($globalConfig->{'null_char'}));

print "\n" if  ($globalConfig->{'debug'} >= DEBUG_LOW);
$res="" unless defined ($res);

# Push result of work to stdout
print  "$res\n";

# Write stat to file if need
if ($globalConfig->{'write_stat'}) {
   $globalConfig->{'stop_time'} = clock_gettime(CLOCK_REALTIME);
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

    print "\n[>] ($_[0]->{'dive_level'}) getMetric started" if ($_[0]->{'debug'} >= DEBUG_LOW);
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

       # Subtable could be not exist as 'vap_table' for UAPs which is powered off.
       # In this case $result must be undefined for properly processed on previous dive level if subroutine is called recursively
       # Test current object with filter-keys or pass inside if no filter defined
       if ((!@fData) || matchObject($_[1], \@fData)) {
          print "\n[.] Object is good" if ($_[0]->{'debug'} >= DEBUG_MID);
          if ($tableName && defined($_[1]->{$tableName})) {
             # if subkey was detected (tablename is given an exist) - do recursively calling getMetric func with subtable and subkey and get value from it
             print "\n[.] It's object. Go inside" if ($_[0]->{'debug'} >= DEBUG_MID);
             $result=getMetric($_[0], $_[1]->{$tableName}, $key); 
          } elsif (defined($_[1]->{$key})) {
             # Otherwise - just return value for given key
             print "\n[.] It's key. Take value" if ($_[0]->{'debug'} >= DEBUG_MID);
             $result=convert_if_bool($_[1]->{$key});
             print "\n[.] value=<$result>" if ($_[0]->{'debug'} >= DEBUG_MID);
          } else {
             print "\n[.] No key or table exist :(" if ($_[0]->{'debug'} >= DEBUG_MID);
          }
        }
   } # if (ref($_[1]) eq 'ARRAY') ... else ...

  print "\n[>] ($_[0]->{'dive_level'}]) getMetric finished (" if ($_[0]->{'debug'} >= DEBUG_LOW);
  print $result if ($_[0]->{'debug'} >= DEBUG_LOW && defined($result));
  print ") /$_[0]->{'maxdepth'}/ " if ($_[0]->{'debug'} >= DEBUG_LOW);

  #float up...
  $_[0]->{'dive_level'}--;

  return $result;
}

#####################################################################################################################################
#
#  Check the JSON object for a match with the list of filters
#
#####################################################################################################################################
sub matchObject {
   # $_[0] - tested object
   # $_[1] - filter data array
   # Init match counter
   my $matchCount=0;
   my $result=TRUE;
   my $objListLen=@{$_[1]};
   if ($objListLen) {
   # run trought flter list
      for (my $i=0; $i < $objListLen; $i++ ) {
          # if key (from filter) in object is defined and its value equal to value of filter - increase counter
          $matchCount++ if (defined($_[0]->{$_[1][$i]->{'key'}}) && ($_[0]->{$_[1][$i]->{'key'}} eq $_[1][$i]->{val}));
      }
      # Object not matched if match counter != length of filter list - one or more filters was not be matched
      $result=FALSE unless ($matchCount == $objListLen);
   }
   return $result;
}



#####################################################################################################################################
#
#  Return 1/0 instead true/false if variable type is bool and return untouched value, if not
#
#####################################################################################################################################
sub convert_if_bool {
   # $_[0] - tested variable
   # if type is boolean, convert true/false || 1/0 => 1/0 with casts to a number by math operation.
   if (JSON::is_bool($_[0])) { 
      return $_[0]+0 
   } else { 
      return $_[0] 
   }
}

#####################################################################################################################################
#
#  Fetch data from cache or call fetching from controller. Renew cache files.
#
#####################################################################################################################################
sub fetchData {
   # $_[0] - $GlobalConfig
   # $_[1] - jsonData global object
   print "\n[+] fetchData started" if ($_[0]->{'debug'} >= DEBUG_LOW);
   print "\n[#]   options:  object='$_[0]->{'object'}'," if ($_[0]->{'debug'} >= DEBUG_MID);
   print " id='$_[0]->{'id'}'," if ($_[0]->{'debug'} >= DEBUG_MID && $_[0]->{'id'});
   print " mac='$_[0]->{'mac'}'," if ($_[0]->{'debug'} >= DEBUG_MID && $_[0]->{'mac'});
   my $cacheExpire=FALSE;
   my $checkObjType=TRUE;
   my $needReadCache=TRUE;
   my $fh;
   my $jsonData;
   my $jsonLen;
   my $cacheFileName;
   my $tmpCacheFileName;
   my $objID;
   my $objPath;

   my $objectName=$_[0]->{'object'};

   # forming URI for objects store
   if ($objectName eq OBJ_WLAN) {
      $objPath="$_[0]->{'api_path'}/list/wlanconf"; 
      $checkObjType=FALSE; 
   } elsif ($objectName eq OBJ_USER) {
      $objPath="$_[0]->{'api_path'}/stat/sta"; 
      $checkObjType=FALSE; 
   } elsif ($objectName eq OBJ_UAP || $objectName eq OBJ_USW || $objectName eq OBJ_USG || $objectName eq OBJ_UPH) { 
     $objPath="$_[0]->{'api_path'}/stat/device"; 
   } else { 
      die "[!] Unknown object given"; 
   }

   # if MAC is given with comman-line option -  RapidWay for Controller v4 is allowed
   $objPath.="/$_[0]->{'mac'}" if (($_[0]->{'version'} eq CONTROLLER_VERSION_4) && ($objectName eq OBJ_UAP) && $_[0]->{'mac'});
   print "\n[.] Object path: $objPath\n" if ($_[0]->{'debug'} >= DEBUG_MID);


   ################################################## Take JSON  ##################################################

   # If cache timeout setted to 0 then no try to read/update cache - fetch data from controller
   if (0 == $_[0]->{'cache_timeout'}) {
      print "\n[.] No read/update cache because cache timeout = 0" if ($_[0]->{'debug'} >= DEBUG_MID);
      $jsonData=fetchDataFromController($_[0],$objPath);
   } else {
      # Change all [:/.] to _ to make correct filename
      ($cacheFileName = $objPath) =~ tr/\/\:\./_/;
      $cacheFileName = $_[0]->{'cache_root'} .'/'. $cacheFileName;
      # Cache filename point to dir? If so - die to avoid problem with read or link/unlink operations
      die "[!] Can't handle '$tmpCacheFileName' through its dir" if (-d $cacheFileName);
      print "\n[.] Cache file name: $cacheFileName\n" if ($_[0]->{'debug'} >= DEBUG_MID);
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
         print "\n[.] Cache expire or not found. Renew..." if ($_[0]->{'debug'} >= DEBUG_MID);
         $tmpCacheFileName=$cacheFileName . ".tmp";
         # Temporary cache filename point to dir? If so - die to avoid problem with write or link/unlink operations
         die "[!] Can't handle '$tmpCacheFileName' through its dir" if (-d $tmpCacheFileName);
         print "\n[.]   temporary cache file='$tmpCacheFileName'" if ($_[0]->{'debug'} >= DEBUG_MID);
         open ($fh, ">", $tmpCacheFileName);# or die "Could open not $tmpCacheFileName to write";
         # try to lock temporary cache file and no wait for locking.
         # LOCK_EX | LOCK_NB
         if (flock ($fh, 2 | 4)) {
            # if Miner could lock temporary file, it...
            chmod 0666, $fh;

            # ...fetch new data from controller...
            $jsonData=fetchDataFromController($_[0], $objPath);
            # unbuffered write it to temp file..
            syswrite ($fh, JSON::encode_json($jsonData));
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
       $jsonData=JSON::decode_json(<$fh>);
       # close cache
       close $fh;
    }
  } # if (0 == $_[0]->{'cache_timeout'})

################################################## JSON processing ##################################################
  $jsonLen=@{$jsonData};
  # Take each object
  for (my $nCnt=0; $nCnt < $jsonLen; $nCnt++) {
     # Test object type or pass if 'obj-have-no-type' (workaround for WLAN, for example)
     next if ($checkObjType && (@{$jsonData}[$nCnt]->{type} ne $_[0]->{'object'}));
     # ID is given by command-line?
     unless ($_[0]->{'id'}) {
       # No ID given. Push all object which have correct type
       push (@{$_[1]}, @{$jsonData}[$nCnt]);
       # and skip next steps
       next;
     }

     # These steps is executed if ID is given

     # Taking from json-key object's ID
     # UBNT Phones store ID into 'device_id' key (?)
     if ($objectName eq OBJ_UPH) {
        $objID=@{$jsonData}[$nCnt]->{device_id}; 
     } else { 
        $objID=@{$jsonData}[$nCnt]->{_id}; 
     }

     # It is required object?
     if ($objID eq $_[0]->{'id'}) { 
        # Yes. Push object to global @objJSON and jump out from the loop
        push (@{$_[1]}, @{$jsonData}[$nCnt]); last;
     }
   } # foreach jsonData

   print "\n[<]   fetched data:\n\t", Dumper $_[1] if ($_[0]->{'debug'} >= DEBUG_HIGH);
   print "\n[-] fetchDataFromController finished" if ($_[0]->{'debug'} >= DEBUG_LOW);
   return TRUE;
}

#####################################################################################################################################
#
#  Fetch data from from controller.
#
#####################################################################################################################################
sub fetchDataFromController {
   # $_[0] - GlobalConfig
   # $_[11 - object path
   #
   print "\n[+] fetchDataFromController started" if ($_[0]->{'debug'} >= DEBUG_LOW);
   print "\n[*] Login into UniFi controller" if ($_[0]->{'debug'} >= DEBUG_LOW);
   # HTTP UserAgent init
   # Set SSL_verify_mode=off to login without certificate manipulation
   # SSL_verify_mode => 0 eq SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_NONE ?
   my $ua = LWP::UserAgent-> new(cookie_jar => {}, agent => "UniFi Miner/" . MINER_VERSION . " (perl engine)",
                                 ssl_opts => {SSL_verify_mode => 0, verify_hostname => 0});
   unifiLogin($_[0], $ua);

   my $result=getJSON($_[0], $ua, $_[1]);
   #print "\n[<]   recieved from JSON requestor:\n\t $result" if $_[0]->{'debug'} >= DEBUG_HIGH;

   print "\n[*] Logout from UniFi controller" if  ($_[0]->{'debug'} >= DEBUG_LOW);
   unifiLogout($_[0], $ua);
   print "\n[-] fetchDataFromController finished" if ($_[0]->{'debug'} >= DEBUG_LOW);
   $_[0]->{'downloaded'}=TRUE;
   return $result;
}

#####################################################################################################################################
#
#  Generate LLD-like JSON using fetched data
#
#####################################################################################################################################
sub lldJSONGenerate{
    # $_[0] - $GlobalConfig
    # $_[1] - array/hash with info
    print "\n[+] lldJSONGenerate started" if ($_[0]->{'debug'} >= DEBUG_LOW);
    print "\n[#]   options: object='$_[0]->{'object'}'" if ($_[0]->{'debug'} >= DEBUG_MID);
    my $lldResponse;
    my $result;
    my $objectName=$_[0]->{'object'};
    my $jsonLen=@{$_[1]};
    # if $_[1] is array...
    if ($jsonLen) {
       # temporary workaround for handle USW ports 
       if ($_[0]->{'id'}) {
          my $lldItem=0;
          if ($objectName eq OBJ_USW) {
             print "usw_ports";
             foreach my $jsonObject (@{$_[1][0]->{'port_table'}}) {
               $result->[$lldItem]->{'{#ALIAS}'}=$jsonObject->{'name'};
               $result->[$lldItem]->{'{#PORTIDX}'}="$jsonObject->{'port_idx'}";
               $lldItem++;
             }
           }
        # end of workaround
        } else {
          for (my $i=0; $i < $jsonLen; $i++) {
            if ($objectName eq OBJ_WLAN) {
               $result->[$i]={'{#ALIAS}' => $_[1][$i]->{'name'}};
               $result->[$i]->{'{#ID}'}=$_[1][$i]->{'_id'};
               $result->[$i]->{'{#ISGUEST}'}=convert_if_bool($_[1][$i]->{'is_guest'});
               $result->[$i]->{'{#ISGUEST}'}=$_[1][$i]->{'is_guest'};
           } elsif ($objectName eq OBJ_USER ) {
              $result->[$i]->{'{#NAME}'}=$_[1][$i]->{'hostname'};
              $result->[$i]->{'{#ID}'}=$_[1][$i]->{'_id'};
              $result->[$i]->{'{#IP}'}=$_[1][$i]->{'ip'};
              $result->[$i]->{'{#MAC}'}=$_[1][$i]->{'mac'};
              # sometime {hostname} may be null. UniFi controller replace that hostnames by {'mac'}
              $result->[$i]->{'{#NAME}'}=$result->[$i]->{'{#MAC}'} unless defined ($result->[$i]->{'{#NAME}'});
           } elsif ($objectName eq OBJ_UPH ) {
              $result->[$i]->{'{#ID}'}=$_[1][$i]->{'device_id'};
              $result->[$i]->{'{#IP}'}=$_[1][$i]->{'ip'};
              $result->[$i]->{'{#MAC}'}=$_[1][$i]->{'mac'};
              # state of object: 0 - off, 1 - on
              $result->[$i]->{'{#STATE}'}=$_[1][$i]->{'state'};
           } elsif ($objectName eq OBJ_UAP || $objectName eq OBJ_USG || $objectName eq OBJ_USW) {
              $result->[$i]->{'{#ALIAS}'}=$_[1][$i]->{'name'};
              $result->[$i]->{'{#ID}'}=$_[1][$i]->{'_id'};
              $result->[$i]->{'{#IP}'}=$_[1][$i]->{'ip'};
              $result->[$i]->{'{#MAC}'}=$_[1][$i]->{'mac'};
              # state of object: 0 - off, 1 - on
              $result->[$i]->{'{#STATE}'}=$_[1][$i]->{'state'};
           }
         } #foreach;
      }
    }

    $lldResponse->{'data'}=$result;
    $result=JSON::encode_json($lldResponse);
    print "\n[<]   generated lld:\n\t", Dumper $result if ($_[0]->{'debug'} >= DEBUG_HIGH);
    print "\n[-] lldJSONGenerate finished" if ($_[0]->{'debug'} >= DEBUG_LOW);
    return $result;
}

#####################################################################################################################################
#
#  Authenticate against unifi controller
#
#####################################################################################################################################
sub unifiLogin {
   # $_[0] - GlobalConfig
   # $_[1] - user agent
   print "\n[>] unifiLogin started" if ($_[0]->{'debug'} >= DEBUG_LOW);
   print "\n[#]  options path='$_[0]->{'login_path'}' type='$_[0]->{'login_type'}' data='$_[0]->{'login_data'}'" if ($_[0]->{'debug'} >= DEBUG_MID);
   my $response=$_[1]->post($_[0]->{'login_path'}, 'Content_type' => "application/$_[0]->{'login_type'}", 'Content' => $_[0]->{'login_data'});
   print "\n[<]  HTTP respose:\n\t", Dumper $response if ($_[0]->{'debug'} >= DEBUG_HIGH);

   if ($_[0]->{'version'} eq CONTROLLER_VERSION_4) {
      # v4 return 'Bad request' (code 400) on wrong auth
      die "\n[!] Login error:" if ($response->code eq '400');
      # v4 return 'OK' (code 200) on success login and must die only if get error
      die "\n[!] Other HTTP error:", $response->code if ($response->is_error);
   } elsif ($_[0]->{'version'} eq CONTROLLER_VERSION_3) {
      # v3 return 'OK' (code 200) on wrong auth
      die "\n[!] Login error:", $response->code if ($response->is_success );
      # v3 return 'Redirect' (code 302) on success login and must die only if code<>302
      die "\n[!] Other HTTP error:", $response->code if ($response->code ne '302');
   } else {
      # v2 code
      ;
       }
   print "\n[-] unifiLogin finished successfully" if ($_[0]->{'debug'} >= DEBUG_LOW);
   return  $response->code;
}

#####################################################################################################################################
#
#  Close session 
#
#####################################################################################################################################
sub unifiLogout {
   # $_[0] - GlobalConfig
   # $_[1] - user agent
   print "\n[+] unifiLogout started" if ($_[0]->{'debug'} >= DEBUG_LOW);
   my $response=$_[1]->get($_[0]->{'logout_path'});
   print "\n[-] unifiLogout finished" if ($_[0]->{'debug'} >= DEBUG_LOW);
}

#####################################################################################################################################
#
#  Take JSON from controller via HTTP  
#
#####################################################################################################################################
sub getJSON {
   # $_[0] - GlobalConfig
   # $_[1] - user agent
   # $_[2] - uri string
   print "\n[+] getJSON started" if ($_[0]->{'debug'} >= DEBUG_LOW);
   print "\n[#]   options url=$_[1]" if ($_[0]->{'debug'} >= DEBUG_MID);
   my $response=$_[1]->get($_[2]);
   # if request is not success - die
   die "[!] JSON taking error, HTTP code:", $response->status_line unless ($response->is_success);
   print "\n[<]   fetched data:\n\t", Dumper $response->decoded_content if ($_[0]->{'debug'} >= DEBUG_HIGH);
   my $result=JSON::decode_json($response->decoded_content);
   my $jsonData=$result->{'data'};
   my $jsonMeta=$result->{'meta'};
   # server answer is ok ?
   die "[!] getJSON error: rc=$jsonMeta->{'rc'}" if ($jsonMeta->{'rc'} ne 'ok');
   print "\n[-] getJSON finished successfully" if ($_[0]->{'debug'} >= DEBUG_LOW);
   return $jsonData;    
}
