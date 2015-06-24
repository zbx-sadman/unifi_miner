#!/usr/bin/perl -w
#
#  (C) sadman@sfi.komi.com 2015
#  tanx to Jakob Borg (https://github.com/calmh/unifi-api) for some methods and ideas 
#
#  Experimental!
#
#BEGIN { $ENV{PERL_JSON_BACKEND} = 'JSON::XS' };
use strict;
use warnings;
#use 5.010;
#use JSON::XS;
#use IO::Socket::SSL;
use Getopt::Std;
#use Digest::MD5 qw(md5_hex);
use Data::Dumper;
use JSON qw ();
use LWP qw ();




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
     MSG_UNKNOWN_CONTROLLER_VERSION => "Version of controller is unknown: ",
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

my $maxDepth=0;
my @objJSON=();
my %options;
getopts("a:c:d:i:k:l:m:n:o:p:s:u:v:", \%options);


#########################################################################################################################################
#
#  Default values for global scope
#
#########################################################################################################################################
my $globalConfig = {
   # Default action for objects metric
   action => ACT_GET,
   # How much time live cache data. Use 0 for disabling cache processes
   cachetimeout => 60,
   # Where are store cache file. Better place is RAM-disk
   cacheroot=> '/run/shm', 
   # Debug level 
   debug => 0,
   # Where are controller answer. See value of 'unifi.https.port' in /opt/unifi/data/system.properties
   location => "https://127.0.0.1:8443", 
   # Operation object. wlan is exist in any case
   object => OBJ_WLAN, 
   # Name of your site 
   sitename => "default", 
   # who can read data with API
   username => "stat",
   # His pass
   password => "stat",
   # UniFi controller version
   version => CONTROLLER_VERSION_4
  };


# Rewrite default values by command line arguments
$globalConfig->{action}       = $options{a} if defined $options{a};
$globalConfig->{cachetimeout} = $options{c} if defined $options{c};
$globalConfig->{debug}        = $options{d} if defined $options{d};
$globalConfig->{id}           = $options{i} if defined $options{i};
$globalConfig->{key}          = $options{k} if defined $options{k};
$globalConfig->{location}     = $options{l} if defined $options{l};
$globalConfig->{mac}          = $options{m} if defined $options{m};
$globalConfig->{null_char}    = $options{n} if defined $options{n};
$globalConfig->{object}       = $options{o} if defined $options{o};
$globalConfig->{password}     = $options{p} if defined $options{p};
$globalConfig->{sitename}     = $options{s} if defined $options{s};
$globalConfig->{username}     = $options{u} if defined $options{u};
$globalConfig->{version}      = $options{v} if defined $options{v};

# Set controller version specific data

if ($globalConfig->{version} eq CONTROLLER_VERSION_4) {
       $globalConfig->{api_path}="$globalConfig->{location}/api/s/$globalConfig->{sitename}";
       $globalConfig->{login_path}="$globalConfig->{location}/api/login";
       $globalConfig->{logout_path}="$globalConfig->{location}/logout";
       $globalConfig->{login_data}="{\"username\":\"$globalConfig->{username}\",\"password\":\"$globalConfig->{password}\"}";
       $globalConfig->{login_type}='json';
     }
elsif ($globalConfig->{version} eq CONTROLLER_VERSION_3) {
       $globalConfig->{api_path}="$globalConfig->{location}/api/s/$globalConfig->{sitename}";
       $globalConfig->{login_path}="$globalConfig->{location}/login";
       $globalConfig->{logout_path}="$globalConfig->{location}/logout";
       $globalConfig->{login_data}="username=$globalConfig->{username}&password=$globalConfig->{password}&login=login";
       $globalConfig->{login_type}='x-www-form-urlencoded';
     }
elsif ($globalConfig->{version} eq CONTROLLER_VERSION_2) {
       $globalConfig->{api_path}="$globalConfig->{location}/api";
       $globalConfig->{login_path}="$globalConfig->{location}/login";
       $globalConfig->{logout_path}="$globalConfig->{location}/logout";
       $globalConfig->{login_data}="username=$globalConfig->{username}&password=$globalConfig->{password}&login=login";
       $globalConfig->{login_type}='x-www-form-urlencoded';
     }
else      
     {
        die MSG_UNKNOWN_CONTROLLER_VERSION, $globalConfig->{version};
     }

print "\n[#]   Global config data:\n\t", Dumper $globalConfig if ($globalConfig->{debug} >= DEBUG_MID);
my $res;

# First - check for object name
if ($globalConfig->{object}) {
   # Ok. Name is exist. How about key?
   if ($globalConfig->{key}){
       # Key is given - get metric. 
       # if $globalConfig->{id} is exist then metric of this object has returned. 
       # If not calculate $globalConfig->{action} for all items in objects list (all object of type = 'object name', for example - all 'uap'
       fetchData($globalConfig, \@objJSON);
       $res=getMetric($globalConfig, \@objJSON, $globalConfig->{key}, 1, $maxDepth);
     }
   else
     { 
       # Key is null - generate LLD-like JSON
       fetchData($globalConfig, \@objJSON);
       $res=lldJSONGenerate($globalConfig, \@objJSON);
     }
}

# Value could be 'null'. {null_char} is defined - replace null to that. 
if (defined($globalConfig->{null_char}))
 { 
   $res = $res ? $res : $globalConfig->{null_char};
 }
print "\n" if  ($globalConfig->{debug} >= DEBUG_LOW);
$res="" unless defined ($res);
# Put result of work to stdout
print  "$res\n";

##################################################################################################################################
#
#  Subroutines
#
##################################################################################################################################

#
# 
#
sub getMetric{
    # $_[0] - GlobalConfig
    # $_[1] - array/hash with info
    # $_[2] - key
    # $_[3] - dive level
    # $_[4] - max depth
    print "\n[>] ($_[3]) getMetric started" if ($_[0]->{debug} >= DEBUG_LOW);
    my $result;
    my $key=$_[2];

    print "\n[#]   options: key='$_[2]' action='$_[0]->{action}'" if ($_[0]->{debug} >= DEBUG_MID);
    print "\n[+]   incoming object info:'\n\t", Dumper $_[1] if ($_[0]->{debug} >= DEBUG_HIGH);

    # correcting maxDepth for ACT_COUNT operation
    $_[4] = ($_[3] > $_[4]) ? $_[3] : $_[4];

    # Checking for type of $_[1].
    # Array must be explored for key value in each element
    # if $_[0] is array...
    if (ref($_[1]) eq 'ARRAY') 
       {
         my $paramValue;
         my $objList=@{$_[1]};
         print "\n[.] Array with ", $objList, " objects detected" if ($_[0]->{debug} >= DEBUG_MID);
         # if metric ask "how much items (AP's for example) in all" - just return array size (previously calculated in $result) and do nothing more
         if ($key eq KEY_ITEMS_NUM) 
            { $result=$objList; }
         else
           {
             $result=0; 
             print "\n[.] taking value from all sections" if ($_[0]->{debug} >= DEBUG_MID);
             for (my $i=0; $i < $objList; $i++ ) {
                  # init $paramValue for right actions doing
                  $paramValue=undef;
                  # Do recursively calling getMetric func with subtable and subkey and get value from it
                  $paramValue=getMetric($_[0], $_[1][$i], $key, $_[3]+1, $_[4]); 
                  print "\n[.] paramValue=$paramValue" if ($_[0]->{debug} >= DEBUG_MID);

                  if ($_[0]->{action} eq ACT_GET) 
                     { $result=$paramValue; last; }

                  if (defined($paramValue))
                     {
                        print "\n[.] act #$_[0]->{action} " if ($_[0]->{debug} >= DEBUG_MID);
                        # need to fix trying sum of not numeric values
                        # do some math with value - sum or count               
                        if ($_[0]->{action} eq ACT_SUM)
                          { $result+=$paramValue; }
                        elsif ($_[0]->{action} eq ACT_COUNT)
                          {
                            # may be wrong algo :(
                            # workaround for correct counting with deep diving
                            # we must count keys in that objects, what placed only inside last level table
                            # in other case $result will be incremented by $paramValue (which is number of key in objects inside last level table)
                            if ($_[4]-$_[3] < 2 ) 
                              { $result++; }
                            else 
                              { $result+=$paramValue; }
                          }
                     }
                  print "\n[.] Value=$paramValue, result=$result" if ($_[0]->{debug} >= DEBUG_HIGH);
              }#foreach;
           }
       }
    # it is hash 
    else 
       {
        # it is not array (list of objects) - it's one object.
        print "\n[.] Just one object detected." if ($_[0]->{debug} >= DEBUG_MID);
        my $tableName;
        my @fData=();
        ($tableName, $key) = split(/[.]/, $key, 2);
        # if key is not defined after split (no comma in key) that mean no table name exist in incoming key and key is first and only one part of splitted data
        if (! defined($key)) 
          { $key = $tableName; undef $tableName;}
        else
          {
            my $fKey;
            my $fValue;
            my $fStr;
            # check for [filterkey=value&filterkey=value&...] construction in tableName. If that exist - key filter feature will enabled
            # regexp matched string placed into $1 and $1 listed as $fStr
            ($fStr) = $tableName =~ m/^\[([\w]+=.+&{0,1})+\]/;
            # ($fStr) = $tableName =~ m/^\[(.+)\]/;
            if ($fStr) 
               {
                 # filterString is exist - need to split its to key=value pairs with '&' separator
                 my @fStrings = split('&', $fStr);
                 # after splitting split again - to key and values. And store it.
                 for (my $i=0; $i < @fStrings; $i++) {
                    # split pair with '=' separator
                    ($fKey, $fValue) = split('=', $fStrings[$i]);
                    # if key/value splitting was correct - save filter data into list of hashes
                    push(@fData, {key=>$fKey, val=> $fValue}) if (defined($fKey) && defined($fValue));
                 }
                # flush tableName's value if tableName is represent filter-key
                undef $tableName;
              }
           }

         # Subtable can be not exist as vap_table for UAPs which is powered off.
         # In this case $result must be undefined for properly processed on previous dive level if subroutine is called recursively              
         # Apply filter-key to current object or pass inside if no filter defined

         if ((!@fData) || matchObject($_[1], \@fData)) {
              print "\n[.] Object is good" if ($_[0]->{debug} >= DEBUG_MID);
              if ($tableName && defined($_[1]->{$tableName})) 
                 {
                   # if subkey was detected (tablename is given an exist) - do recursively calling getMetric func with subtable and subkey and get value from it
                   print "\n[.] It's object. Go inside" if ($_[0]->{debug} >= DEBUG_MID);
                   $result=getMetric($_[0], $_[1]->{$tableName}, $key, $_[3]+1, $_[4]); 
                 } 
              elsif (defined($_[1]->{$key}))
                 {
                   # Otherwise - just return value for given key
                   print "\n[.] It's key. Take value" if ($_[0]->{debug} >= DEBUG_MID);
                   $result=convert_if_bool($_[1]->{$key});
                   print "\n[.] value=<$result>" if ($_[0]->{debug} >= DEBUG_MID);

                 } else
                 {
              print "\n[.] No key or table exist :(" if ($_[0]->{debug} >= DEBUG_MID);
              }
            }
       }

  print "\n[>] ($_[3]) getMetric finished (" if ($_[0]->{debug} >= DEBUG_LOW);
  print $result if ($_[0]->{debug} >= DEBUG_LOW && defined($result));
  print ") /$_[4]/ " if ($_[0]->{debug} >= DEBUG_LOW);
 
  return $result;
}

#####################################################################################################################################
#
#  
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
      for (my $i=0; $i < $objListLen; $i++ ) {
        $matchCount++ if (defined($_[0]->{$_[1][$i]->{key}}) && ($_[0]->{$_[1][$i]->{key}} eq $_[1][$i]->{val}));
      }
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
   if (JSON::is_bool($_[0]))
     { return $_[0]+0 }
   else
     { return $_[0] }
}

#####################################################################################################################################
#
#  Fetch data from cache or call fetching from controller. Renew cache files.
#
#####################################################################################################################################
sub fetchData {
   # $_[0] - $GlobalConfig
   # $_[1] - jsonData global object
   print "\n[+] fetchData started" if ($_[0]->{debug} >= DEBUG_LOW);
   print "\n[#]   options:  object='$_[0]->{object}'," if ($_[0]->{debug} >= DEBUG_MID);
   print " id='$_[0]->{id}'," if ($_[0]->{debug} >= DEBUG_MID && $_[0]->{id});
   print " mac='$_[0]->{mac}'," if ($_[0]->{debug} >= DEBUG_MID && $_[0]->{mac});
   my $cacheExpire=FALSE;
   my $objPath;
   my $checkObjType=TRUE;
   my $fh;
   my $jsonData;
   my $tmpCacheFileName;
   my $cacheFileName;
   my $jsonLen;
   my $objID;

   #
   my $objectName=$_[0]->{object};

   # forming path to objects store
   if ($objectName eq OBJ_WLAN) 
      { $objPath="$_[0]->{api_path}/list/wlanconf"; $checkObjType=FALSE; }
   elsif ($objectName eq OBJ_USER)
      { $objPath="$_[0]->{api_path}/stat/sta"; $checkObjType=FALSE; }
   elsif ($objectName eq OBJ_UAP || $objectName eq OBJ_USW || $objectName eq OBJ_USG || $objectName eq OBJ_UPH)
      { $objPath="$_[0]->{api_path}/stat/device"; }
    else { die "[!] Unknown object given"; }

   # if MAC is given with comman-line option -  RapidWay for Controller v4 is allowed
   $objPath.="/$_[0]->{mac}" if (($_[0]->{version} eq CONTROLLER_VERSION_4) && ($objectName eq OBJ_UAP) && $_[0]->{mac});

   print "\n[.] Object path: $objPath\n" if ($_[0]->{debug} >= DEBUG_MID);


   ################################################## Take JSON  ##################################################

   # if cache timeout setted to 0 then no try to read/update cache - fetch data from controller
   if (0 == $_[0]->{cachetimeout})
      {
         print "\n[.] No read/update cache because cache timeout = 0" if ($_[0]->{debug} >= DEBUG_MID);
         $jsonData=fetchDataFromController($_[0],$objPath);
      }
    else
      {
#         my $cacheFileName = $_[0]->{cacheroot} .'/'. md5_hex($objPath);
         # change all [:/.] to _ to make correct file name
         ($cacheFileName = $objPath) =~ tr/\/\:\./_/;
         $cacheFileName = $_[0]->{cacheroot} .'/'. $cacheFileName;
         print "\n[.] Cache file name: $cacheFileName\n" if ($_[0]->{debug} >= DEBUG_MID);
         # Cache file is exist and non-zero size?
         if (-e $cacheFileName && -s $cacheFileName) 
            { 
              # Yes, is exist.
              # If cache is expire...
              my @fileStat=stat($cacheFileName);
              $cacheExpire = TRUE if (($fileStat[9] + $_[0]->{cachetimeout}) < time()) }
            # Cache file is not exist => cache is expire => need to create
         else
            { $cacheExpire = TRUE; }

         # Cache expire - need to update
         if ($cacheExpire)
            {
               print "\n[.] Cache expire or not found. Renew..." if ($_[0]->{debug} >= DEBUG_MID);
               # here we need to call login/fetch/logout chain
               $jsonData=fetchDataFromController($_[0], $objPath);
               #
               $tmpCacheFileName=$cacheFileName . ".tmp";
               print "\n[.]   temporary cache file=$tmpCacheFileName" if ($_[0]->{debug} >= DEBUG_MID);
               open ($fh, "+>", $tmpCacheFileName) or die "Could not write to $tmpCacheFileName";
               chmod 0666, $fh;
#               sysopen ($fh,$cacheFileName, O_RDWR|O_CREAT|O_TRUNC, 0777) or die "Could not write to $cacheFileName";
               # lock file for monopoly mode write and push data
               # can i use O_EXLOCK flag into sysopen?

               # if script can lock cache temp file - write data, close and rename it to proper name
               if (flock ($fh, 2))
                  {
#                     print $fh $coder->encode($jsonData);
                     print $fh JSON::encode_json($jsonData);
                     close $fh;
                     rename $tmpCacheFileName, $cacheFileName;
                  }
               else
                  {
                     # can't lock - just close and use fetched json data for work
                     close $fh;
                  }

            }
          else
            {
               open ($fh, "<", $cacheFileName) or die "Can't open $cacheFileName";
               # read data from file
               $jsonData=JSON::decode_json(<$fh>);
#               $jsonData=$coder->decode(<$fh>);
               # close cache
               close $fh;
            }
        }

   ################################################## JSON processing ##################################################
   $jsonLen=@{$jsonData};
   # Take each object
   for (my $nCnt=0; $nCnt < $jsonLen; $nCnt++) {
     # Test object type or pass if 'obj-have-no-type' workaround (wor WLAN, for example)
     next if ($checkObjType && (@{$jsonData}[$nCnt]->{type} ne $_[0]->{object}));
     # ID is given by command-line?
     unless (defined($_[0]->{id}))
       {
         # No ID given. Push all object which have correct type
         push (@{$_[1]}, @{$jsonData}[$nCnt]);
         # and skip next steps
         next;
       }

      # These steps is executed if ID is given

      # Taking from json-key object's ID
      # UBNT Phones store ID into 'device_id' key (?)
      if ($objectName eq OBJ_UPH)
         { $objID=@{$jsonData}[$nCnt]->{'device_id'}; }
      else
         { $objID=@{$jsonData}[$nCnt]->{'_id'}; }
      # It is required object?
      if ($objID eq $_[0]->{id})
         { 
           # Yes. Push object to global @objJSON and jump out from the loop
           push (@{$_[1]}, @{$jsonData}[$nCnt]); last;
         }
       } # foreach jsonData

   print "\n[<]   fetched data:\n\t", Dumper $_[1] if ($_[0]->{debug} >= DEBUG_HIGH);
   print "\n[-] fetchDataFromController finished" if ($_[0]->{debug} >= DEBUG_LOW);
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
   print "\n[+] fetchDataFromController started" if ($_[0]->{debug} >= DEBUG_LOW);
   print "\n[*] Login into UniFi controller" if ($_[0]->{debug} >= DEBUG_LOW);
   # HTTP UserAgent init
   # Set SSL_verify_mode=off to login without certificate manipulation
   # SSL_verify_mode => 0 eq SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_NONE ?
   my $ua = LWP::UserAgent-> new(cookie_jar => {}, agent => "UniFi Miner/" . MINER_VERSION . " (perl engine)",
                                 ssl_opts => {SSL_verify_mode => 0, verify_hostname => 0});
   unifiLogin($_[0], $ua);

   my $result=getJSON($_[0], $ua, $_[1]);
   #print "\n[<]   recieved from JSON requestor:\n\t $result" if $_[0]->{debug} >= DEBUG_HIGH;

   print "\n[*] Logout from UniFi controller" if  ($_[0]->{debug} >= DEBUG_LOW);
   unifiLogout($_[0], $ua);
   print "\n[-] fetchDataFromController finished" if ($_[0]->{debug} >= DEBUG_LOW);
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
    print "\n[+] lldJSONGenerate started" if ($_[0]->{debug} >= DEBUG_LOW);
    print "\n[#]   options: object='$_[0]->{object}'" if ($_[0]->{debug} >= DEBUG_MID);
    my $lldResponse;
    my $result;
    my $objectName=$_[0]->{object};
    my $jsonLen=@{$_[1]};
    # if $_[1] is array...
    if (defined($_[1])) 
       {
        # temporary workaround for handle USW ports 
        if (defined($_[0]->{id}))
        {
          my $lldItem=0;
          if ($objectName eq OBJ_USW) {
             print "usw_ports";
             foreach my $jsonObject (@{$_[1][0]->{port_table}}) {
               $result->[$lldItem]->{'{#ALIAS}'}=$jsonObject->{'name'};
               $result->[$lldItem]->{'{#PORTIDX}'}="$jsonObject->{'port_idx'}";
               $lldItem++;
             }
           }
        }
        # end of workaround
        else
        {
         for (my $i=0; $i < $jsonLen; $i++) {
           if ($objectName eq OBJ_WLAN) {
               $result->[$i]->{'{#ALIAS}'}=$_[1][$i]->{'name'};
               $result->[$i]->{'{#ID}'}=$_[1][$i]->{'_id'};
#               $result->[$i]->{'{#ISGUEST}'}=convert_if_bool($_[1][$i]->{'is_guest'});
#               $result->[$i]->{'{#ISGUEST}'}=$_[1][$i]->{'is_guest'};

           }
           elsif ($objectName eq OBJ_USER ) {
              $result->[$i]->{'{#NAME}'}=$_[1][$i]->{'hostname'};
              $result->[$i]->{'{#ID}'}=$_[1][$i]->{'_id'};
              $result->[$i]->{'{#IP}'}=$_[1][$i]->{'ip'};
              $result->[$i]->{'{#MAC}'}=$_[1][$i]->{'mac'};
              # sometime {'hostname'} may be null. UniFi controller replace that hostnames by {'mac'}
              $result->[$i]->{'{#NAME}'}=$result->[$i]->{'{#MAC}'} unless defined ($result->[$i]->{'{#NAME}'});
           }
           elsif ($objectName eq OBJ_UPH ) {
              $result->[$i]->{'{#ID}'}=$_[1][$i]->{'device_id'};
              $result->[$i]->{'{#IP}'}=$_[1][$i]->{'ip'};
              $result->[$i]->{'{#MAC}'}=$_[1][$i]->{'mac'};
              # state of object: 0 - off, 1 - on
              $result->[$i]->{'{#STATE}'}=$_[1][$i]->{'state'};
           }
           elsif ($objectName eq OBJ_UAP || $objectName eq OBJ_USG || $objectName eq OBJ_USW) 
           {
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

#  For JSON::PP (use JSON / use JSON:PP)
#    $resut=encode_json($result, {utf8 => 1, pretty => 1});
    $result=JSON::encode_json($lldResponse);

#    my $coder = JSON::XS->new->ascii->pretty->allow_nonref;
#    $resut=$coder->encode ($result);

    print "\n[<]   generated lld:\n\t", Dumper $result if ($_[0]->{debug} >= DEBUG_HIGH);
    print "\n[-] lldJSONGenerate finished" if ($_[0]->{debug} >= DEBUG_LOW);
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
   print "\n[>] unifiLogin started" if ($_[0]->{debug} >= DEBUG_LOW);
   print "\n[#]  options path='$_[0]->{login_path}' type='$_[0]->{login_type}' data='$_[0]->{login_data}'" if ($_[0]->{debug} >= DEBUG_MID);
   my $response=$_[1]->post($_[0]->{login_path}, 'Content_type' => "application/$_[0]->{login_type}", 'Content' => $_[0]->{login_data});
   print "\n[<]  HTTP respose:\n\t", Dumper $response if ($_[0]->{debug} >= DEBUG_HIGH);

   if ($_[0]->{version} eq CONTROLLER_VERSION_4) 
      {
         # v4 return 'Bad request' (code 400) on wrong auth
         die "\n[!] Login error:" if ($response->code eq '400');
         # v4 return 'OK' (code 200) on success login and must die only if get error
         die "\n[!] Other HTTP error:", $response->code if ($response->is_error);
      }
   elsif ($_[0]->{version} eq CONTROLLER_VERSION_3) {
        # v3 return 'OK' (code 200) on wrong auth
        die "\n[!] Login error:", $response->code if ($response->is_success );
        # v3 return 'Redirect' (code 302) on success login and must die only if code<>302
        die "\n[!] Other HTTP error:", $response->code if ($response->code ne '302');
      }
   else {
      # v2 code
      ;
       }
   print "\n[-] unifiLogin finished successfully" if ($_[0]->{debug} >= DEBUG_LOW);
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
   print "\n[+] unifiLogout started" if ($_[0]->{debug} >= DEBUG_LOW);
   my $response=$_[1]->get($_[0]->{logout_path});
   print "\n[-] unifiLogout finished" if ($_[0]->{debug} >= DEBUG_LOW);
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
   print "\n[+] getJSON started" if ($_[0]->{debug} >= DEBUG_LOW);
   print "\n[#]   options url=$_[1]" if ($_[0]->{debug} >= DEBUG_MID);
   my $response=$_[1]->get($_[2]);
   # if request is not success - die
   die "[!] JSON taking error, HTTP code:", $response->status_line unless ($response->is_success);
   print "\n[<]   fetched data:\n\t", Dumper $response->decoded_content if ($_[0]->{debug} >= DEBUG_HIGH);
   my $result=JSON::decode_json($response->decoded_content);
#   my $result=from_json($response->decoded_content,{convert_blessed => 0, utf8 => 1});
   my $jsonData=$result->{data};
   my $jsonMeta=$result->{meta};
   # server answer is ok ?
   if ($jsonMeta->{'rc'} eq 'ok') 
      { 
        print "\n[-] getJSON finished successfully" if ($_[0]->{debug} >= DEBUG_LOW);
        return $jsonData;    
      }
   else
      { die "[!] getJSON error: rc=$jsonMeta->{'rc'}"; }
}
