Transferometer
======
Data transfer accounting package for [OpenWrt](https://openwrt.org/).

## Requirements
* OpenWrt/LEDE 17.01.x

Note: This software depends on the *script-arp* feature of [Dnsmasq 2.76](http://www.thekelleys.org.uk/dnsmasq/CHANGELOG) and later.  OpenWrt/LEDE 17.01.x meets this requirement, while OpenWrt 15.05.x does not.

## Usage
To be determined.  (Transferometer is a work in progress.)

## Internal Processes
When Dnsmasq monitors a change in the ARP table, it calls Transferometer with parameters indicating the substance of the change:

* Startup.
* Run 'mkdir /tmp/~transferometer' to create a lock directory.  If exit code indicates failure (ex. directory already exists), abort.
* Create a PID file '/var/run/transferometer.pid' containing the PID (Process ID) of present Lua interpreter session.
  * To obtain the PID, open /proc/self/stat and read the first block of text, an integer value.
  * Be sure to open /proc/self/stat natively within Lua.  Reading it with 'cat' or another tool will yield the wrong PID.
* Create iptables accounting chains for built-in chains 'INPUT', 'OUTPUT', and 'FORWARD'.
* Create iptables rules to divert packets from built-in chains 'INPUT', 'OUTPUT', and 'FORWARD' to corresponding accouting chains.
* Read host byte counts and zero counters as a single iptables operation.  Update transfer.db.
* Read command line parameter #1 to determine action.  (Subsequent parameters vary depending on content of parameter #1.)
  * If 'arp-add', then:
    * Check for existing iptables rules in the 'FORWARD' chain matching IP address specified in parameter #3.
    * If rules exist, do nothing.
    * If rules are missing, add them.
    * Add or update entry in host.db.  (IP address = parameter #3, MAC address = parameter #2.)
  * If 'arp-del', then:
    * Delete iptables rules from the 'FORWARD' chain matching IP address specified in parameter #3.
    * Delete entry from host.db.
  * If any other value is passed as parameter #1, do nothing.
* Delete the PID file '/var/run/transferometer.pid'.
* Delete the lock directory '/tmp/~transferometer'.
* Shutdown.

## Development

Run [dev_setup.sh](scripts/dev_setup.sh) to automatically create a VM containing [OpenWrt 17.01.4](https://downloads.openwrt.org/releases/17.01.4/targets/x86/).

Requirements:
* Linux, macOS, [Cygwin](https://www.cygwin.com/) (Windows), or [MinGW/MSYS](http://mingw.org/) (Windows)
* [Bash](https://www.gnu.org/software/bash/)
* [curl](https://curl.haxx.se/) or [wget](https://www.gnu.org/software/wget/)
* [gunzip](https://www.gnu.org/software/gzip/) or [gzip](https://www.gnu.org/software/gzip/)
* [VirtualBox](https://www.virtualbox.org/) (installation directory must be added to PATH system variable)

Alternatively, you can follow the [instructions](https://openwrt.org/docs/guide-user/virtualization/virtualbox-vm) provided by the OpenWrt team to manually create a VM.

Once you have a working VM:

1. Follow the [instructions](https://openwrt.org/docs/guide-user/virtualization/virtualbox-vm) provided by the OpenWrt team to install [OpenWrt 17.01.4](https://downloads.openwrt.org/releases/17.01.4/targets/x86/) in a [VirtualBox](https://www.virtualbox.org/) VM.
2. Clone the Transferometer repo locally, then [use SCP to copy files](https://kb.iu.edu/d/agye) to your VM.
3. SSH into the VM, reconfigure Dnsmasq:
  * Add the following lines to */etc/dnsmasq.conf*:
```bash
script-arp
dhcp-script=/usr/sbin/transferometer
```
  * Restart Dnsmasq:
```bash
/etc/init.d/dnsmasq restart
```

## Contributing
1. Fork the repository.
2. Create a feature branch with a meaninful name.
3. Commit your changes.
4. Update the test suite.
5. Update documentation.
6. Submit a pull request.

## License
See [LICENSE](LICENSE) file.
