# Experimental place

### 20.06.2015

- Add new object _user_ for fetching data from stat/sta.
- Add LLD for _user_ object
- Add new object _uph_ for UVP (UniFi VOIP Phone) devices 
- Add LLD for _uph_ object
- Extend LLD for UAP, USW, USG with {#STATE} macro
- Add workaround sub() for converting boolean from `true`/`false` to `1`/`0`.  

### Notes
  I expect to slow Miner work for _user_ object on systems with many clients connected through big JSON taking from UniFi controler (~1kb per user).  
  No different object for users and guests exists because of all clients stored in one JSON-array. 
 
  _uph_ object have a little metrics and use non-standart keys: `device_id` instead `_id`, for example.

  In some cases Miner return `true`/`false` for boolean JSON-keys, but Zabbix get only `1`/`0` as boolean.

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


