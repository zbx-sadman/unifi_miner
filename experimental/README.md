# Experimental place

### 23.06.2015
- Fixed wrong filter-key handling;
- Fixed JSON::XS integration problems;
- Fixed global var issue, which cause bug with PPerl;
- Try to change default option to _get_.

#### Notes
How to accelerate Miner (as perl-script):

1. Try to install JSON::XS. JSON module must be select it as backend instead JSON::PP. However here is problem: as noted on [CPAN](http://search.cpan.org/~makamaka/JSON-2.90/lib/JSON.pm) latest version is 2.90 and _this version is compatible with JSON::XS 2.34 and later. (Not yet compatble to JSON::XS 3.0x.)_, but latest verison of JSON::XS, that i fetch by `cpan JSON::XS` is 3.01. So, i guess, that old release (>=2.34 && <3.0) of JSON::XS must be found and installed for correct selecting backend by JSON module. 
2. Try to use [PPerl](http://search.cpan.org/~msergeant/PPerl-0.25/PPerl.pm). I've found it in CPAN (`cpan PPerl`) and in Debian repository (`aptitude install pperl`). Choose one and change `#!/usr/bin/perl` to `#!/usr/bin/pperl` on a first line of UniFi Miner.  However here is problem too: PPerl want to create lock file. And try to create it inside _/home/zabbix/.pperl_ directory, if script was running under _zabbix_ user account. Otherwise it die with error like _Cannot open lock file_. U need to verify the existence of the _/home/zabbix_ directory and create, if it is not. Early versions (i get module version 0.25) had the option _-T/path/to/temp/files_. Now path is hardcoded.

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

### Examples
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


