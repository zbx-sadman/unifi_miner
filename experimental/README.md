# Experimental place

### 10.07.2015
- Miner 1.0.0 released, [Miner2](https://github.com/zbx-sadman/unifi_miner/tree/master/experimental/UniFi_Proxy) (work name - UniFi Proxy) started;

#### Notes

[Miner2](https://github.com/zbx-sadman/unifi_miner/tree/master/experimental/UniFi_Proxy) branch based on code of Miner 1.0.0 and act as TCP server with fork support. It wait to request and response with metric value or action result. 
All user settings placed into .conf file (see path inside _miner2_tcp.pl->$confFileName_). Listen port defined via _.conf->listen_port_ option and the number of simultaneous connections defined via _.conf->max_connections_.

Format of request is: _action,object_type,sitename,key,id (not mac!),username,userpass,version,cache_timeout_. Empty (skipped) value replaced with defaults.

How to use:
 1. With netcat `echo "get,uap,default,name,<id_of_uap>" | nc 127.0.0.1 7777`;
 2. With umtcp_get (u need to compile _umtcp_get.c_): `umtcp_get 127.0.0.1 7777 "discovery,uap"`
 3. With Zabbix loadable module (u need to compile unifi.c and something else): use Item key (type: Zabbix agent (active)) _unifi.proxy_ as _unifi.proxy[sum,uap,default,_num-sta]_

To Zabbix integration example see _unifi.conf_ file.

How to compile & use Zabbix loadable module unifi.so:
 1. Download and unpack zabbix sources (i use latest - v2.4.5);
 2. Place zabbix_module\unifi directory with files into _.../zabbix-2.4.5/src/modules_ (near _dummy_ module dir);
 3. Run _.../zabbix-2.4.5/configure_ without options. Some .h files could be maked;
 4. `cd` to  _.../zabbix-2.4.5/src/modules/unifi_ and do `make` - _unifi.so_ must be created;
 5. `chown zabbix:zabbix unifi.so` & `mv -f ./unifi.so /usr/local/lib/zabbix/agent` or to other dir;
 6. Add _LoadModulePath=/usr/local/lib/zabbix/agent/_ & _LoadModule=unifi.so_ to your zabbix_agentd.conf;
 7. Restart Zabbix agent: `service zabbix-agent restart`;
 8. If _miner2_tcp.pl_ as server, try `zabbix_agentd -t unifi.proxy[discovery,wlan,default];
 9. On success - use unifi.proxy with yours templates.

Template example for Zabbix v2.4.5 here: zbx_v2_4_Template_UBNT_UniFi_Proxy.xml

Miner2 allow to reach on my installation:
- with netcat _real 0m0.011s_
- -"- umtcp_get _real 0m0.09s_
- -"- loadable module _real 0m0.07s_

Used measurement command: `time zabbix_agentd -t "unifi.proxy[sum,uap,default,vap_table.[is_guest=1].is_guest]"`.

Miner 1.0.0 without PPerl have _real 0m0.056s_, with PPerl - _real 0m0.023s_.

### 02.07.2015
- No more JSON wrap module supported;
- Code optimization in order to accelerate;
- Zabbix Template reworked.

#### Notes

As a result of Miner profiling decided to abandon support module JSON. It brings overhead on initialization stage and processing through just recalling one of installed JSON module (PP or JSON). 

Code optimization may cause a problem with output 'true'/'false' instead 1/0 for booleans. If u found this bug with getMetric operations (i.e. `.../unifi_miner.pl -o uap -i <some_uap_id> -k "vap_table.is_guest" -a get`) - write to me, please.

Zabbix template designed for Zabbix v2.4 (pre 2.4 users can't export its without correcting _filter_ tag) and tested on UniFi controller v4. 
Template contain Discovery rules (with Items, some Triggers and Graphs prototypes included) for:
- All sites on controller;
- UAP's on all sites (if u want to get UAPS for one site only, u must use LLD Filter feature or add sitename into key like that: _unifi.discovery[uap,MySuperSite]_);
- WLANs on site 'default' (if u want to get WLANs on all sites - just use key like _unifi.discovery[wlan]_);
- UniFi Phones on all sites. I haven't any UniFi devices except UAPs and can't check the prototypes works ;);
- UniFi Switches on all sites. Ports discovery not supported at this release.

I suspect, that UAP items list for all sites can be frighteningly large. Double check the Prototypes list and disable unwanted items before linking template to host.

For correct using the template and Miner, u must:

1. Install perl modules _JSON::XS_, _LWP_, _IO::Socket::SSL_, _Data::Dumper_ if u want to see debug messages using '-d', Time::HiRes for writing runtime stat (when _write_stat => TRUE_). U can get is with `cpan Module::Name` or `aptitude install libjson-xs-perl libwww-perl libio-socket-ssl-perl libdata-dumper-simple-perl libtime-hires-perl` for Debian;
3. Stop _zabbix-agent_;
3. Add to actual _zabbix_agentd.conf_ on box, which hosted UniFi Controller contents of _unifi.conf_ or hook up its with _Include=..._ option. If u use miner before and have other selfmaded keys - move its to new _unifi.conf_. **Note** that Tempalte use items with _Zabbix agent (active)_. U must turn on Active mode on Zabbix agent;
4. Put _unifi_miner.pl_ to _/usr/local/bin/zabbix/_  or point _UserParameter=_ to another place;
5. Replace _username/password/cacheroot/cachetimeout_ variables inside _unifi_miner.pl_ to yours own or use corresponding command-line options (_-u_, _-p_, etc);
6. Start _zabbix-agent_;
7. Import template;
8. Check and disable unwanted items prototypes if u not brave explorer;
9. Make and fill _{$FW_UAP_LATEST_VER}_ macro on host level with the value of firmware that you consider the last for UAPs. Otherwise - disable annoying trigger;
10. Link template to existing host;
11. Wait some time and chech Latest Data; 
12. In success try to accelerate Miner with decrease init stage by remark with hash pragmas: _use strict_, _use warnings_, _use Data::Dumper_, _use Time::HiRes_;
13. Skip this step, if u luckless man;
12. Try to take more speed with PPerl.



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

Now i was reach time of once execution ~0m0.020s (with new code and using PPerl, data from cache, no Zabbix agent worked, 6 UAPs) vice ~0m0.120s (with old code and without PPerl, data from cache, no Zabbix agent worked, 6 UAPs) on my virtual linux box, which hosted UniFi Controller. Command to measure is `time ./unifi_miner.pl -o uap  -k "vap_table.[is_guest=1].is_guest" -a sum`. 

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


