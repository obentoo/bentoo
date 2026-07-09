# Bentoo

Bentōō is an initiative to distribute an user-friendly version of Gentoo linux Stage[5] to new users, with more updated packages, focusing on agility, security, privacy and games.

## Overlays

### eselect repository
```
eselect repository add bentoo git https://github.com/obentoo.git
```

### local Overlay

[Local overlays](https://wiki.gentoo.org/wiki/Creating_an_ebuild_repository) should be managed via `/etc/portage/repos.conf/`.
create a `/etc/portage/repos.conf/bentoo.conf` file containing precisely:

```
[bentoo]
location = /var/db/repos/bentoo
sync-type = git
sync-uri = https://github.com/obentoo.git
priority= 99
```

Afterwards, simply run `emerge --sync bentoo`, and Portage should seamlessly make all our ebuilds available.

### Bentoo Configurations

Here you can see the portage files configurations : https://github.com/obentoo/bentoo-files

### Bentoolkit 

Bentoolkit is a set of tools to manage Gentoo overlays : https://github.com/obentoo/bentoolkit

### Bentoo Dev

Bentoo Dev is a Claude Code plugin to help developers with Gentoo ebuilds : https://github.com/obentoo/bentoo-dev
