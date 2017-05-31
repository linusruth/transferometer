Transferometer
======
Data transfer accounting package for [LEDE](https://lede-project.org/).

## Requirements
* LEDE 17.01.x

Note: This software depends on the *script-arp* functionality in [Dnsmasq 2.76](http://www.thekelleys.org.uk/dnsmasq/CHANGELOG), included in LEDE 17.01.x.  OpenWRT 15.05.x includes Dnsmasq 2.73, which does not provide *script-arp*.  Future versions of OpenWRT will likely be compatibile with Transferometer, provided they include an updated Dnsmasq package.

## Usage
To be determined.  (Transferometer is a work in progress.)

## Development
1. Follow the [instructions](https://lede-project.org/docs/user-guide/virtualbox-vm) provided by the LEDE team to install [LEDE 17.01.1 x86_64](https://downloads.lede-project.org/releases/17.01.1/targets/x86/64/lede-17.01.1-x86-64-combined-ext4.img.gz) in a [VirtualBox](https://www.virtualbox.org/) VM.  (**Note: There is a flaw in the instructions.**  Please download the *ext4* image referenced above rather than the *squashfs* image it suggests.  Otherwise VBoxManage will throw an error during conversion indicating that the disk is "not aligned on a sector boundary".)
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