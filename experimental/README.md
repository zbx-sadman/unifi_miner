# Experimental place

### 30.06.2015
- All sites LLD implemented;
- Added new object 'site';
- Big changes to generate LLD procedure (**read notes**);
- Small changes in fetchData routines;
- SSL23_GET_SERVER_HELLO error fixed.

#### Notes

**At first** - macro **_{#ALIAS}_** changed to **_{#NAME}_**. Thus, as at begin Miner's work objects was UAP's only, the names were designated as _Alias_ (as they called in the web-interface). Now the list of objects is much wider and use of the macro _{#ALIAS}_ is wrong in fact. You need to make corrections to the template.

Starting with this release Miner supports 'all sites' feature with LLD routines. This feature activated when '-s' option not used. Resulting LLD can be filtered by _{#SITENAME}_ or _{#SITEID}_ macro.

You can get 'Other HTTP error: 500' while connect to UniFi controller. And when you try to connect again using '-d 3' option to get more debug info, you can may reach 'SSL23_GET_SERVER_HELLO' error in HTTP reply. Fix is as follows: open _unifi_miner.pl_ for edit, find remark with _SSL23_GET_SERVER_HELLO_ word and uncomment two next lines: 

` #use IO::Socket::SSL;`

` #IO::Socket::SSL::set_default_context(new IO::Socket::SSL::SSL_Context(SSL_version => 'tlsv1', SSL_verify_mode => Net::SSLeay::VERIFY_NONE()));`

#### Examples
   Getting LLD for all sites

  `./unifi_miner.pl -o site`

   Getting LLD for UAPs on all sites

  `./unifi_miner.pl -o uap`

   Getting LLD for WLANs on site 'siteone'

  `./unifi_miner.pl -o wlan -s siteone`



### 25.06.2015
- Rewritten getMetric procedure;
- Rewritten JSON load code;
- Rewritten cache renew procedure to reduce runtime and avoid race condition;
- Added subroutine for store statistic info into file.

#### Notes

For using statistic store feature you need to install `cpan Time::HiRes` (or `aptitude install libtime-hires-perl`) module and set needful values for _statfile_, _writestat_ variables. _Time::HiRes_ allow to get right time of Miner's internal subroutines execution (result not include time speded to perl modules init). If not required to use this feature, you can remark `use Time::HiRes` and set _writestat_ to FALSE inside Miner code. Then you could accelerate Miner a little.

Now i was reach time of once execution ~0m0.020s (with new code and using PPerl, data from cache, no Zabbix agent worked) vice ~0m0.120s (with old code and without PPerl, data from cache, no Zabbix agent worked) on my virtual linux box, which hosted UniFi Controller. Command to measure is `time ./unifi_miner.pl -o uap  -k "vap_table.[is_guest=1].is_guest" -a sum`. 

How to replace old edition of UniFi Miner accelerated with PPerl to new: 

1. Stop Zabbix agent: `service zabbix-agent stop`
2. Kill all instances of Miner that are running on your computer under zabbix account: `kill $(ps a -u zabbix -o pid,args | grep unifi_miner.pl | awk '{print $1}')`
3. Copy new edition to dir, which contain old file: `cp .../new/unifi_miner.pl cp .../bin/zabbix/unifi_miner.pl`
4. Start Zabbix agent `service zabbix-agent start`

### 23.06.2015
- Fixed wrong filter-key handling;
- Fixed JSON::XS integration problems;
- Fixed global var issue, which cause bug with PPerl;
- Try to change default option to _get_.

#### Notes
How to accelerate Miner (as perl-script):

1. Try to install JSON::XS. JSON module must be select it as backend instead JSON::PP. However here is problem: as noted on [CPAN](http://search.cpan.org/~makamaka/JSON-2.90/lib/JSON.pm) latest version is 2.90 and _this version is compatible with JSON::XS 2.34 and later. (Not yet compatble to JSON::XS 3.0x.)_, but latest verison of JSON::XS, that i fetch by `cpan JSON::XS` is 3.01. So, i guess, that old release (>=2.34 && <3.0) of JSON::XS must be found and installed for correct selecting backend by JSON module. 
2. Try to use [PPerl](http://search.cpan.org/~msergeant/PPerl-0.25/PPerl.pm). I've found it in CPAN (`cpan PPerl`) and in Debian repository (`aptitude install pperl`). Choose one, install modile and change `#!/usr/bin/perl` to `#!/usr/bin/pperl` on a first line of UniFi Miner. However here is problem too: PPerl want to create lock file. And try to create it inside _/home/zabbix/.pperl_ directory, if script was running under _zabbix_ user account. Otherwise it die with error like _Cannot open lock file_. U need to verify the existence of the _/home/zabbix_ directory and create, if it is not. Early versions (i get module version 0.25) had the option _-T/path/to/temp/files_. Now path is hardcoded. Note that Zabbix user home directory is not necessarily located in the _/home/zabbix_. Check it: `cat /etc/passwd | grep zabbix`.
3. if you are not going to use `-d` option, u can remark `use Data::Dumper;` in Miner code. It save time which spent to module Init.
4. Reduce using of filter-keys - look for alternative keys combinations. For example: `-o uap -k vap_table.is_guest -a sum` is faster that `-o uap -k vap_table.[is_guest=1].t -a count`.

I recommend mandatory use `-a` option with calling UniFi Miner - i thought to try implement LLD for nested object that addressed by _key_ and make a new action _discovery_

### 20.06.2015

- Add new object _user_ for fetching data from stat/sta.
- Add LLD for _user_ object
- Add new object _uph_ for UVP (UniFi VOIP Phone) devices 
- Add LLD for _uph_ object
- Extend LLD for UAP, USW, USG with {#STATE} macro
- Add workaround sub() for converting boolean from `true`/`false` to `1`/`0`.  

#### Notes
  I expect to slow Miner work for _user_ object on systems with many clients connected through big JSON taking from UniFi controler (~1kb per user). No different object for users and guests exists because of all clients stored in one JSON-array. 
 
  _uph_ object have a little metrics and use non-standart keys: `device_id` instead `_id`, for example.

  In some cases Miner was returned `true`/`false` for boolean JSON-keys, but Zabbix take only `1`/`0` for boolean. It assumedly fixed. 

#### Examples
   Getting LLD for all clients

  `./unifi_miner.pl -o user`

   Getting number of all guests

  `./unifi_miner.pl -o user -k is_guest -a sum`

   Getting number of all guests, which is authorized

  `./unifi_miner.pl -o user -k "[authorized=1].is_guest" -a sum`

   Getting number of all guests, connected to WLAN with ESSID 'Home NET'

  `./unifi_miner.pl -o user -k "[essid=Home NET].is_guest" -a sum`

   Getting number of all guests, connected to WLAN with ESSID 'Home NET' which served UAP with given MAC

  `./unifi_miner.pl -o user -k "[essid=Home NET&ap_mac=00:27:22:d4:73:13].is_guest" -a sum`


