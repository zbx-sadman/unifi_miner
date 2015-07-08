#!/usr/bin/perl
#
#  (C) sadman@sfi.komi.com 2015
#  tanx to Jakob Borg (https://github.com/calmh/unifi-api) for some methods and ideas 
#
#
use strict;
use warnings;
use JSON;
use Data::Dumper;
#use IO::Socket::SSL;
use LWP;
use Getopt::Std;
use Digest::MD5 qw(md5_hex);
use File::stat;


use constant {
     ACT_COUNT => 'count',
     ACT_SUM => 'sum',
     ACT_GET => 'get',
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
     OBJ_UVP => 'uvp',
     OBJ_UAP => 'uap',
     OBJ_USG => 'usg',
     OBJ_WLAN => 'wlan',
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

my %options=();
getopts("a:c:d:i:k:l:m:n:o:p:s:u:v:", \%options);

#########################################################################################################################################
#
#  Default values for global scope
#
#########################################################################################################################################
my $globalConfig = {
   # Default action for objects metric
   action => ACT_COUNT,
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
   version => CONTROLLER_VERSION_3
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

print "\n[#]   Global config data:\n\t", Dumper $globalConfig if $globalConfig->{debug} >= DEBUG_HIGH;
my $res="";

# First - check for object name
if ($globalConfig->{object}) {
   # Ok. Name is exist. How about key?
   if ($globalConfig->{key}){
       # Key is given - get metric. 
       # if $globalConfig->{id} is exist then metric of this object has returned. 
       # If not calculate $globalConfig->{action} for all items in objects list (all object of type = 'object name', for example - all 'uap'
       $res=getMetric(fetchData(), $globalConfig->{key}, 1);
     }
   else
     { 
       # Key is null - generate LLD-like JSON
       $res=lldJSONGenerate(fetchData());
     }
}

# Value could be 'null'. {null_char} is defined - replace null to that. 
if (defined($globalConfig->{null_char}))
 { 
   $res = $res ? $res : $globalConfig->{null_char};
 }
print "\n" if  $globalConfig->{debug} >= DEBUG_LOW;
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
    # $_[0] - array/hash with info
    # $_[1] - key
    # $_[2] - dive level
    print "\n[>] ($_[2]) getMetric started" if $globalConfig->{debug} >= DEBUG_LOW;
    my $result;
    my $paramValue;
    my $table=$_[0];
    my $tableName;
    my $key=$_[1];
    my $fKey;
    my $fValue;
    my @fData=();
    my $fDataLen;
    my $fStr;

    print "\n[#]   options: key='$_[1]' action='$globalConfig->{action}'" if $globalConfig->{debug} >= DEBUG_MID;
    print "\n[+]   incoming object info:'\n\t", Dumper $_[0] if $globalConfig->{debug} >= DEBUG_HIGH;

    # maybe this code to regexp spliting need rewriten
    ($tableName, $key) = split(/[.]/, $key, 2);

    
    # check for [filterkey=value&filterkey=value&...] construction in tableName. If that exist - key filter feature will enabled
    # regexp matched string placed into $1 and $1 listed as $fStr
    ($fStr) = $tableName =~ m/^\[([\w]+=.+&{0,1})+\]$/;
    if ($fStr) {
      # filterString is exist - need to split its to key=value pairs with '&' separator
      my @fStrings = split('&', $fStr);
      # after splitting split again - to key and values. And push it to array
      foreach my $fStr (@fStrings) {
         # regexp with key=value format checking
         # ($fKey, $fValue) = $fStr =~ m/([-_\w]+)=([-_\w\x20]+)/gi;

         # split pair with '=' separator
         ($fKey, $fValue) = split('=', $fStr);
         # if key/value splitting was correct - push to filter data array
         if (defined($fKey) &&  defined($fValue)) {
            push (@fData, {key => $fKey, value => $fValue});
           }
       }
       # length of filter data array will used later for matching checking
       $fDataLen = scalar(@fData);
    }

    # if key is not defined after split (no comma in key) that mean no table name exist in key and key is first and only one part of splitted data
    if (! defined($key)) { $key = $tableName; $tableName=undef;}

    # Cheking for type of $_[0].
    # Array must be explored for key value in each element
    if (ref($table) eq "ARRAY") 
       {
         $result=@{$table};

         print "\n[.] $result sections given." if $globalConfig->{debug} >= DEBUG_MID;
         # if metric ask "how much items (AP's for example) in all" - just return array size (previously calculated in $result) and do nothing more
         if ($key ne KEY_ITEMS_NUM) 
           {
             print "\n[.] taking value from all sections" if $globalConfig->{debug} >= DEBUG_MID;
             $result=0;
             foreach my $hashRef (@{$table}) {

                  # If need to analyze elements in subtable...
                  # $tableName=something mean that subkey was detected
                  if ($tableName) { 
                     # Check for filter using: if filter data array non zero length - test analyzed object with filter. 
                     if ($fDataLen > 0) {
                        # Init match counter
                        my $matchCount=0;
                        foreach my $fHash (@fData) {
                          if ( defined($hashRef->{$fHash->{key}}) && ($hashRef->{$fHash->{key}} eq $fHash->{value}))
                          {
                             # increase if filter is matched
                             $matchCount++;
                             #print "\n >>> $fHash->{key} matched! \n";
                          }
                        }
                        # Number of matches is equal to filter data array (all filters is matched)? Yes - dive to lower level.
                        if ($matchCount == $fDataLen) {
                        #print "\n >>> As filter is matched, going to next level with key=$key , hashRef=", Dumper $hashRef, "\n";
                        $paramValue=getMetric($hashRef, $key, $_[2]+1); 
                        }
                     }
                     else {
                     # Do recursively calling getMetric func with subtable and subkey and get value from it
                     $paramValue=getMetric($hashRef->{$tableName}, $key, $_[2]+1); 
                     }
                   }
                  else {
                     # if it just "first-level" key - get it value                     
                     $paramValue=undef;
                     $paramValue=$hashRef->{$key} if (defined($hashRef->{$key}))
                   }
                  # need to fix trying sum of not numeric values
                  # do some math with value - sum or count               
                  if ($globalConfig->{action} eq ACT_SUM)
                     {
                       $result+=$paramValue if (defined($paramValue));
                     }
                  elsif ($globalConfig->{action} eq ACT_COUNT)
                     {
                       # Do count if key is exist
                       $result++ if (defined($paramValue)); 
                     }
                  else 
                     {
                       # Otherwise (ACT_GET option) - take value and go out from loop
                       if (defined($paramValue)) {
                           $result=$paramValue;
                           last;
                       }
                     }
                  print "\n[.] Value=$paramValue, result=$result" if $globalConfig->{debug} >= DEBUG_HIGH;
              }#foreach;
           }
       }
    else 
       {
         # it is not array. Just get metric value by hash index
         print "\n[.] Just one section given. Get metric." if $globalConfig->{debug} >= DEBUG_MID;
         # $tableName=something mean that subkey was detected
         # if subkey was detected - do recursively calling getMetric func with subtable and subkey and get value from it
         # Otherwise - just return value for given key
         if ($tableName) 
            { $result=getMetric($table->{$tableName}, $key, $_[2]+1); }
         else { 
              # Subtable can be not exist as vap_table for UAPs which is powered off.
              # In this case $result must be undefined for properly processed on previous dive level if subroutine is called recursively              
              $result=undef;
              $result=$table->{$key} if ( defined($table->{$key}));
            }
       }
  print "\n[>] ($_[2]) getMetric finished (" if $globalConfig->{debug} >= DEBUG_LOW;
  print $result if ($globalConfig->{debug} >= DEBUG_LOW && defined($result));
  print ")" if $globalConfig->{debug} >= DEBUG_LOW;

  return $result;
}

#####################################################################################################################################
#
#  Fetch data from cache or call fetching from controller. Renew cache files.
#
#####################################################################################################################################
sub fetchData {
   print "\n[+] fetchData started" if $globalConfig->{debug} >= DEBUG_LOW;
   print "\n[#]   options:  object='$globalConfig->{object}'," if $globalConfig->{debug} >= DEBUG_MID;
   print " id='$globalConfig->{id}'," if $globalConfig->{debug} >= DEBUG_MID && $globalConfig->{id};
   print " mac='$globalConfig->{mac}'," if $globalConfig->{debug} >= DEBUG_MID && $globalConfig->{mac};
   my $result;
   my $now=time();
   my $cacheExpire=FALSE;
   my $objPath;
   my $checkObjType=TRUE;
   my $fh;
   my $jsonData;
   my $v4RapidWay=FALSE;
   my $tmpCacheFileName;
   #
   my $objectName=$globalConfig->{object};
   # forming path to objects store
   if ($objectName eq OBJ_WLAN) 
      { $objPath="$globalConfig->{api_path}/list/wlanconf"; $checkObjType=FALSE; }
   elsif ($objectName eq OBJ_UAP || $objectName eq OBJ_USW || $objectName eq OBJ_USG || $objectName eq OBJ_UVP)
      { $objPath="$globalConfig->{api_path}/stat/device"; }
    else { die "[!] Unknown object given"; }

   if (($objectName eq OBJ_UAP) and ($globalConfig->{version} eq CONTROLLER_VERSION_4) and $globalConfig->{mac})  
      {
         $objPath.="/$globalConfig->{mac}"; $v4RapidWay=TRUE;
      }
   print "\n[.] Object path: $objPath\n" if $globalConfig->{debug} >= DEBUG_MID;

   # if cache timeout setted to 0 then no try to read/update cache - fetch data from controller
   if ($globalConfig->{cachetimeout} != 0)
      {
         my $cacheFileName = $globalConfig->{cacheroot} .'/'. md5_hex($objPath);
         print "\n[.] Cache file name: $cacheFileName\n" if $globalConfig->{debug} >= DEBUG_MID;
         # Cache file is exist and non-zero size?
         if (-e $cacheFileName && -s $cacheFileName)
            # Yes, is exist.
            # If cache is expire...
            { $cacheExpire = TRUE if ((stat($cacheFileName)->mtime + $globalConfig->{cachetimeout}) < $now) }
            # Cache file is not exist => cache is expire => need to create
         else
            { $cacheExpire = TRUE; }

         # Cache expire - need to update
         if ($cacheExpire)
            {
               print "\n[.] Cache expire or not found. Renew..." if $globalConfig->{debug} >= DEBUG_MID;
               # here we need to call login/fetch/logout chain
               $jsonData=fetchDataFromController($objPath);
               #
               $tmpCacheFileName=$cacheFileName . ".tmp";
               print "\n[.]   temporary cache file=$tmpCacheFileName" if $globalConfig->{debug} >= DEBUG_MID;
               open ($fh, "+>", $tmpCacheFileName) or die "Could not write to $tmpCacheFileName";
               chmod 0666, $fh;
#               sysopen ($fh,$cacheFileName, O_RDWR|O_CREAT|O_TRUNC, 0777) or die "Could not write to $cacheFileName";
               # lock file for monopoly mode write and push data
               # can i use O_EXLOCK flag into sysopen?

               # if script can lock cache temp file - write data, close and rename it to proper name
               if (flock ($fh, 2))
                  {
                     print $fh encode_json($jsonData);
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
               # first time try to open cache file for r/w (check for lock state -> check for finished write to cache by another process)
               # +< - do not create file
#               if (! open ($fh, "+<", $cacheFileName))
#                  {
#                     # wait...
#                     sleep 1;
#                     # second time try to open cache... if still locked - exit.
#                     open ($fh, "+<", $cacheFileName) or die "$cacheFileName is possibly locked, aborting";
#                  }
               open ($fh, "<", $cacheFileName) or die "Can't open $cacheFileName";
               # read data from file
               $jsonData=decode_json(<$fh>);
               # close cache
               close $fh;
            }
        }
    else
      {
         print "\n[.] No read/update cache because cache timeout = 0" if $globalConfig->{debug} >= DEBUG_MID;
         $jsonData=fetchDataFromController($objPath);
      }
   # When going by rapid way only one object is fetched
   if ($v4RapidWay) 
      { 
        print "\n[.] Rapidway allowed" if $globalConfig->{debug} >= DEBUG_MID;
        $result=@{$jsonData}[0];
      }
   else
     {
       # Lets analyze JSON 
       foreach my $hashRef (@{$jsonData}) {
          # ID is given?
          if ($globalConfig->{id})
          {
              # Object with given ID is found, jump out to end of function
             if ($hashRef->{'_id'} eq $globalConfig->{'id'}) { $result=$hashRef; last; }
          } 

          # Workaround for object without type key (WLAN for example)
          $hashRef->{type}=$globalConfig->{object} if (! $checkObjType);

          # Right type of object?
          if ($hashRef->{type} eq $globalConfig->{object}) 
             { 
               # Collect all object with given type
               { push (@{$result}, $hashRef); }
             } # if ... type
      } # foreach jsonData
     }
   print "\n[<]   fetched data:\n\t", Dumper $result if $globalConfig->{debug} >= DEBUG_HIGH;
   print "\n[-] fetchDataFromController finished" if $globalConfig->{debug} >= DEBUG_LOW;
   return $result;
}

#####################################################################################################################################
#
#  Fetch data from from controller.
#
#####################################################################################################################################
sub fetchDataFromController {
   # $_[0] - object path
   print "\n[+] fetchDataFromController started" if $globalConfig->{debug} >= DEBUG_LOW;
   print "\n[*] Login into UniFi controller" if $globalConfig->{debug} >= DEBUG_LOW;

   # HTTP UserAgent init
   # Set SSL_verify_mode=off to login without certificate manipulation
   # SSL_verify_mode => 0 eq SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_NONE ?
   my $ua = LWP::UserAgent-> new(cookie_jar => {}, agent => "UniFi Miner/" . MINER_VERSION . " (perl engine)",
                                 ssl_opts => {SSL_verify_mode => 0, verify_hostname => 0});
   unifiLogin($ua);

   my $result=getJSON($ua, $_[0]);
   #print "\n[<]   recieved from JSON requestor:\n\t $result" if $globalConfig->{debug} >= DEBUG_HIGH;

   print "\n[*] Logout from UniFi controller" if  $globalConfig->{debug} >= DEBUG_LOW;
   unifiLogout($ua);
   print "\n[-] fetchDataFromController finished" if $globalConfig->{debug} >= DEBUG_LOW;
   return $result;
}

#####################################################################################################################################
#
#  Generate LLD-like JSON using fetched data
#
#####################################################################################################################################
sub lldJSONGenerate{
    # $_[0] - array/hash with info
    print "\n[+] lldJSONGenerate started" if $globalConfig->{debug} >= DEBUG_LOW;
    print "\n[#]   options: object='$globalConfig->{object}'" if $globalConfig->{debug} >= DEBUG_MID;
    my $lldData;
    my $resut;
    my $lldItem = 0;
    my $objectName=$globalConfig->{object};
    #print "\n[!] _[0]:\n", Dumper $_[0];

    if (ref($_[0]) eq "ARRAY") 
       {
         foreach my $hashRef (@{$_[0]}) {
           if ($objectName eq OBJ_WLAN) {
               $lldData->{'data'}->[$lldItem]->{'{#ALIAS}'}=$hashRef->{'name'};
               $lldData->{'data'}->[$lldItem]->{'{#ID}'}=$hashRef->{'_id'};
           }
           elsif ($objectName eq OBJ_UAP || $objectName eq OBJ_USG || $objectName eq OBJ_USW || $objectName eq OBJ_UVP ) {
              $lldData->{'data'}->[$lldItem]->{'{#ALIAS}'}=$hashRef->{'name'};
              $lldData->{'data'}->[$lldItem]->{'{#IP}'}=$hashRef->{'ip'};
              $lldData->{'data'}->[$lldItem]->{'{#ID}'}=$hashRef->{'_id'};
              $lldData->{'data'}->[$lldItem]->{'{#MAC}'}=$hashRef->{'mac'};
           }
           $lldItem++;
         } #foreach;
      }
    # Just one object selected, need generate LLD with keys from subtable (USW for example)
    else
      {
        if ($objectName eq OBJ_USW) {
         my $uswMAC=$_[0]->{'mac'};
         foreach my $hashRef (@{$_[0]->{port_table}}) {
            $lldData->{'data'}->[$lldItem]->{'{#ALIAS}'}=$hashRef->{'name'};
            $lldData->{'data'}->[$lldItem]->{'{#PORTIDX}'}="$hashRef->{'port_idx'}";
#            $lldData->{'data'}->[$lldItem]->{'{#PSKEYPREFIX}'}="stat.sw-$uswMAC-port_$hashRef->{'port_idx'}-";
            $lldItem++;
         }
         }
      }
    $resut=to_json($lldData, {utf8 => 1, pretty => 1, allow_nonref => 1});
    print "\n[<]   generated lld:\n\t", Dumper $resut if $globalConfig->{debug} >= DEBUG_HIGH;
    print "\n[-] lldJSONGenerate finished" if $globalConfig->{debug} >= DEBUG_LOW;
    return $resut;
}

#####################################################################################################################################
#
#  Authenticate against unifi controller
#
#####################################################################################################################################
sub unifiLogin {
   # $_[0] - user agent
   print "\n[>] unifiLogin started" if $globalConfig->{debug} >= DEBUG_LOW;
   print "\n[#]  options path='$globalConfig->{login_path}' type='$globalConfig->{login_type}' data='$globalConfig->{login_data}'" if $globalConfig->{debug} >= DEBUG_MID;
   my $response=$_[0]->post($globalConfig->{login_path}, 'Content_type' => "application/$globalConfig->{login_type}", 'Content' => $globalConfig->{login_data});
   print "\n[<]  HTTP respose:\n\t", Dumper $response if $globalConfig->{debug} >= DEBUG_HIGH;
   # v3 return 'OK' (code 200) on wrong auth
   die "\n[!] Login error:", $response->code if ($response->is_success && $globalConfig->{version} eq CONTROLLER_VERSION_3);
   # v3 return 'Redirect' (code 302) on success login
   die "\n[!] Other HTTP error:", $response->code if ($response->code ne '302' && $globalConfig->{version} eq CONTROLLER_VERSION_3);

   # v3 return 'Bad request' (code 400) on wrong auth
   die "\n[!] Login error:" if ($response->code eq '400' && $globalConfig->{version} eq CONTROLLER_VERSION_4);
   # v3 return 'OK' (code 200) on success login
   die "\n[!] Other HTTP error:", $response->code if ($response->is_error && $globalConfig->{version} eq CONTROLLER_VERSION_4);
   print "\n[-] unifiLogin finished sucesfull " if $globalConfig->{debug} >= DEBUG_LOW;
   return  $response->code;
}

#####################################################################################################################################
#
#  Close session 
#
#####################################################################################################################################
sub unifiLogout {
   # $_[0] - user agent
   # $_[1] - bye message (?)
   print "\n[+] unifiLogout started" if $globalConfig->{debug} >= DEBUG_LOW;
   my $response=$_[0]->get($globalConfig->{logout_path});
   print "\n[-] unifiLogout finished" if $globalConfig->{debug} >= DEBUG_LOW;
}

#####################################################################################################################################
#
#  Take JSON from controller via HTTP  
#
#####################################################################################################################################
sub getJSON {
   # $_[0] - user agent
   # $_[1] - uri string
   print "\n[+] getJSON started" if $globalConfig->{debug} >= DEBUG_LOW;
   print "\n[#]   options url=$_[1]" if $globalConfig->{debug} >= DEBUG_MID;
   my $response=$_[0]->get($_[1]);
   # if request is not success - die
   die "[!] JSON taking error, HTTP code:", $response->status_line unless $response->is_success;
   print "\n[<]   fetched data:\n\t", Dumper $response->decoded_content if $globalConfig->{debug} >= DEBUG_HIGH;
   my $result=decode_json($response->decoded_content);
   my $jsonData=$result->{data};
   my $jsonMeta=$result->{meta};
   # server answer is ok ?
   if ($jsonMeta->{'rc'} eq 'ok') 
      { 
        print "\n[-] getJSON finished sucesfull" if $globalConfig->{debug} >= DEBUG_LOW;
        return $jsonData;    
      }
   else
      { die "[!] postJSON error: rc=$jsonMeta->{'rc'}"; }
}
