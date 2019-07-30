## UniFi Miner change log 

### v1.3.8
Added:

- New cli key _-j stringify\_method_. User can enable/disable "Pretty JSON generation" feature. 

Note: "Pretty JSON" formatting allow put to Zabbix more that 65535 bytes data blocks and user can control more objects (UAPs, Users, etc).


### v1.3.7
Added new objects:
- _uap\_vap\_table_ for _vap\_table_ array contained in UAPs data object. LLD is supported;
- _uap\_vwire\_vap\_table_ for _vwire\_vap\_table_ array inside UAPs data object. LLD is supported;
- _fw\_update_ for latest version update info;
- _wdg\_health_ for Health widget's data fetching;
- _wdg\_switch_ for Switch widget's data fetching.

Note: some metrics was reorganized by Ubiquinty and moved to new JSON-tree places.


### v1.3.6
Fixed:
- Script execution error when object without id-key reached (probably it unadopted devices);

Added:
- RegExp feature for the filter expression; 
- New action _raw_ and new virtual key _*_ for taking raw JSON subtree from the tree. 

### v1.3.5
Fixed:
- Metrics obtaining from UniFi Security Gateway;

Changes:
- Perl JSON now used instead JSON::XS to make able choosing JSON backend;  
- TLS moved to 1.2 to works with UniFi Controller v5.5 / v5.6 and above;

Added:
- UniFi Controller v5 releases real support; 
- New objects: _voucher_ , _dpi_ / _sitedpi_.

### v1.3.4
Fixed:
- UniFi Controller v3: error with logging in;
- UniFi Controller v3: error in 'still connected' testing on fetching data from controller;
- UniFi Controller v3: mapping _mac_-key to {#NAME} macro (Zabbix's LLD) if _name_-key is empty;
- Debug: print of HTTP response output.

### v1.3.3
Fixed:
- wrong fix warning in v1.3.2. Miner was ignore default cacheage with empty arg **-c** and no use cache feature;
- MAC detection error in **-i** option;
- site list obtaining ('site' object processing does not work).


### v1.3.2
Fixed:
- variable cast warning with using empty arguments that expected with numeric values (**-c ""** for example) fixed.

### v1.3.1
Fixed:
- removed "no sites walking" problem when option -s used with no value;
- code to avoid "push on reference is experimental" warning on perl > v5.20.

